# app/models/weekly_reflection_habit_summary.rb
#
# ==============================================================================
# 【このモデルの役割】
#   週次振り返り時点の「習慣のスナップショット」を管理するモデル。
#
# 【スナップショット設計とは？】
#   Habit（習慣）は後から名前・目標値・単位を変更できる。
#   しかし週次振り返りは「振り返りを行った時点の状態」を永続保存する必要がある。
#
#   例：
#   1週目：習慣「ジョギング」単位「分」目標120分
#          → サマリーに unit: "分", actual_value: 90.00 を保存
#   2週目：単位を「km」に変更
#   → 1週目の振り返りは「90分」のまま表示される（正しい記録を守れる）
#
# 【チェック型 vs 数値型の使うカラムの違い】
#
#   チェック型（measurement_type: :check_type）
#     actual_count  → 完了した日数（整数）。例: 5日
#     actual_value  → NULL（使わない）
#     unit          → NULL（使わない）
#     表示例: 「5 / 7 日（71%）」
#
#   数値型（measurement_type: :numeric_type）
#     actual_count  → 0（使わない。デフォルト値のまま）
#     actual_value  → numeric_value の週次合計（小数）。例: 90.00
#     unit          → スナップショット単位文字列。例: "分"
#     表示例: 「90 / 120 分（75%）」
#
# 【E-2 での変更内容】
#   - actual_value(decimal) / unit(string) カラムを追加（マイグレーション済み）
#   - build_from_habit クラスメソッドに数値型分岐を追加
#   - numeric? インスタンスメソッドを追加（表示の分岐に使う）
#   - summary_text インスタンスメソッドを追加（一元管理）
#
# 【E-2 レビュー反映】
#   - to_f → to_d に変更（BigDecimal 精度を保護）
#   - check_type 側にも deleted_at: nil 条件を追加（論理削除レコード除外の統一）
# ==============================================================================

class WeeklyReflectionHabitSummary < ApplicationRecord
  # ============================================================
  # アソシエーション（関連付け）
  # ============================================================

  # このサマリーは必ず WeeklyReflection に属する
  belongs_to :weekly_reflection

  # optional: true にする理由：
  #   on_delete: :nullify により、元の習慣が物理削除されると habit_id が NULL になる。
  #   NULL になった場合でも belongs_to のバリデーションでエラーにならないよう optional: true を設定。
  #   habit_name 等のスナップショットデータは残るので、画面表示には影響しない。
  belongs_to :habit, optional: true

  # ============================================================
  # バリデーション（入力値の検証）
  # ============================================================

  validates :habit_name,
            presence: true,
            length: { maximum: 50 }

  # weekly_target は達成率計算の「分母」になるため 1 以上を必須とする
  # 0 だと ZeroDivisionError が発生するため防御する
  validates :weekly_target,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  validates :actual_count,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 達成率は 0.00〜100.00 の範囲に収まるよう制限する
  validates :achievement_rate,
            presence: true,
            numericality: {
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 100
            }

  # actual_value は 0 以上の数値、または NULL（チェック型）を許容する
  # allow_nil: true を使う理由：
  #   チェック型では actual_value は使わないため NULL を保存する。
  #   NULL の場合はこのバリデーションをスキップする。
  validates :actual_value,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true

  # unit は最大10文字（Habit モデルの unit バリデーションと統一）
  # allow_blank: true を使う理由：
  #   チェック型では unit は NULL/空文字を許容するため。
  validates :unit, length: { maximum: 10 }, allow_blank: true

  # DB レベルの UNIQUE 制約に加え、Rails レベルでも重複を防ぐ（二重保証）
  # allow_nil: true → habit_id が NULL の場合はこのバリデーションをスキップする
  validates :habit_id,
            uniqueness: {
              scope: :weekly_reflection_id,
              message: "は既にこの振り返りに含まれています"
            },
            allow_nil: true

  # ============================================================
  # スコープ
  # ============================================================

  scope :by_achievement, -> { order(achievement_rate: :desc) }
  scope :completed,      -> { where(achievement_rate: 100) }
  scope :incomplete,     -> { where("achievement_rate < ?", 100) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # 1つの WeeklyReflection に紐づく全習慣のスナップショットを一括作成する
  def self.create_all_for_reflection!(weekly_reflection)
    # transaction により「全部成功 or 全部失敗」を保証する
    # 1件でも save! が失敗すると全件ロールバック（巻き戻し）される
    transaction do
      weekly_reflection.user.habits.active.each do |habit|
        # 二重作成の防止：
        #   既に同じ habit のサマリーが存在する場合はスキップする。
        #   振り返り入力途中でページを再読み込みした場合など、
        #   このメソッドが2回呼ばれても UNIQUE エラーにならず安全に動作する。
        next if weekly_reflection.habit_summaries.exists?(habit: habit)

        build_from_habit(weekly_reflection, habit).save!
      end
    end
  end

  # 習慣データからサマリーのインスタンスを組み立てる（DB には保存しない）
  #
  # 【チェック型と数値型で異なる処理】
  #   チェック型:
  #     completed: true かつ deleted_at: nil の habit_records を COUNT する
  #     actual_count に件数をセット、actual_value / unit は nil のまま
  #   数値型:
  #     deleted_at: nil の habit_records の numeric_value を SUM する
  #     actual_value に合計値をセット、unit に習慣の単位をセット（スナップショット）
  #     actual_count は 0（使わないがデフォルト値を維持）
  #
  # 【なぜ両方に deleted_at: nil を付けるのか】
  #   論理削除されたレコードを集計から除外するため。
  #   数値型だけでなくチェック型も統一することで、
  #   将来のバグ混入を防ぐ（E-2 レビュー反映）。
  #
  # 【なぜ数値型は completed 条件を付けないのか】
  #   数値型習慣は「値が入っていること」が実績を意味する（B-1 設計）。
  #   completed フラグは主にチェック型で使う概念であり、
  #   数値型に completed 条件を付けると「値があるが completed: false」の
  #   レコードを意図せず除外してしまう。
  #
  # 【なぜ SUM 集計するのか】
  #   数値型習慣は「今週何分ジョギングしたか」のような累積値を管理する。
  #   週の記録（月〜日の複数レコード）を合算して「週次実績値」とする。
  #
  # 【to_d を使う理由（E-2 レビュー反映）】
  #   Rails の decimal カラムは BigDecimal で管理されている。
  #   .to_f に変換すると浮動小数点の誤差（例: 0.1 + 0.2 ≠ 0.3）が発生する可能性がある。
  #   .to_d（BigDecimal 変換）を使うことで精度を保護する。
  def self.build_from_habit(weekly_reflection, habit)
    user       = weekly_reflection.user
    week_range = weekly_reflection.week_start_date..weekly_reflection.week_end_date

    if habit.numeric_type?
      # 数値型: numeric_value の SUM を BigDecimal で計算する
      # deleted_at: nil → 論理削除されたレコードを除外する
      # .to_d → SUM の結果が nil（記録なし）の場合に 0 に変換しつつ BigDecimal 精度を保護する
      actual_value = habit.habit_records
                          .where(user: user, record_date: week_range, deleted_at: nil)
                          .sum(:numeric_value)
                          .to_d

      # weekly_target は「1週間で達成したい目標値（例: 120分）」として扱う
      rate = calculate_rate(actual_value, habit.weekly_target)

      # weekly_reflection.habit_summaries.build を使うことで
      # weekly_reflection_id が自動的にセットされる
      weekly_reflection.habit_summaries.build(
        habit:            habit,
        habit_name:       habit.name,                  # スナップショット：振り返り時点の習慣名
        weekly_target:    habit.weekly_target,          # スナップショット：振り返り時点の目標値
        actual_count:     0,                            # 数値型では使わないが NOT NULL のため 0 をセット
        actual_value:     actual_value.round(2),        # 数値型の週次実績値合計（小数点2桁）
        unit:             habit.unit,                   # スナップショット：振り返り時点の単位
        achievement_rate: rate
      )
    else
      # チェック型: completed: true かつ deleted_at: nil の habit_records を COUNT する
      actual_count = habit.habit_records
                          .where(
                            user:        user,
                            record_date: week_range,
                            completed:   true,
                            deleted_at:  nil
                          )
                          .count

      # effective_weekly_target を使う理由：
      #   habit.weekly_target は除外日（habit_excluded_days）を考慮していない生の目標値。
      #   例: weekly_target=7 でも月・水・金を除外していれば実質目標は4日。
      #   habit.effective_weekly_target は除外日を差し引いた実質目標値を返す。
      #   振り返り時点の実質目標をスナップショットとして保存することで
      #   正確な達成率を計算できる。
      effective_target = habit.effective_weekly_target

      # effective_target が 0 の場合（全曜日除外など）は 1 で保護
      # weekly_target バリデーションが greater_than_or_equal_to: 1 のため
      # 0 が入るとバリデーションエラーになる
      safe_target = [ effective_target, 1 ].max

      rate = calculate_rate(actual_count, safe_target)

      weekly_reflection.habit_summaries.build(
        habit:            habit,
        habit_name:       habit.name,
        weekly_target:    safe_target,           # 除外日考慮後の実質目標値をスナップショット
        actual_count:     actual_count,
        actual_value:     nil,
        unit:             nil,
        achievement_rate: rate
      )
    end
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # numeric? : このサマリーが数値型習慣のものかを返す
  #
  # 【なぜ actual_value.present? で判定するのか】
  #   habit（関連先）が on_delete: :nullify で NULL になっている可能性がある。
  #   habit_id が NULL の場合でも、actual_value が保存されていれば数値型として
  #   正しく表示できる。スナップショットデータを信頼する設計。
  #
  # 【0.0 のときの挙動について】
  #   Rails では 0.0.present? == true（数値は 0 でも「存在する」と判定される）。
  #   そのため actual_value: 0.0 の場合も numeric? は true を返す。
  #   これは意図した動作：
  #     「今週ジョギングを0分だった」→「0 / 120 分（0%）」と表示する
  #   チェック型（actual_value: nil）と正しく区別できる。
  #
  # 【nil との区別】
  #   actual_value が nil  → チェック型 → numeric? = false → 「N / M 日」表示
  #   actual_value が 0.0  → 数値型・実績なし → numeric? = true → 「0 / M 単位」表示
  #   actual_value が 90.0 → 数値型・実績あり → numeric? = true → 「90 / M 単位」表示
  def numeric?
    actual_value.present?
  end

  # summary_text : 振り返り詳細ページで表示する実績テキストを返す
  #
  # 【チェック型の表示例】 → 「5 / 7 日（71%）」
  # 【数値型の表示例】    → 「90 / 120 分（75%）」
  # 【数値型・実績0の例】 → 「0 / 120 分（0%）」
  #
  # 【format("%g", value) を使う理由】
  #   %g は末尾のゼロを除去する書式指定子。
  #   例: 90.0  → "90"  （「90.0 分」ではなく「90 分」と表示できる）
  #       90.5  → "90.5"（小数点以下が 0 でない場合はそのまま表示）
  #   整数と小数が混在しても常に読みやすい表示になる。
  #
  # 【actual_value.to_f を使う理由】
  #   actual_value は BigDecimal 型（DB の decimal カラム）。
  #   format("%g") は Float を期待するため、表示専用で to_f 変換する。
  #   計算には使わないため精度問題は発生しない。
  def summary_text
    if numeric?
      # 数値型: 「実績値 / 目標値 単位（XX%）」形式
      actual_str = format("%g", actual_value.to_f)
      target_str = format("%g", weekly_target.to_f)
      unit_str   = unit.presence || ""
      "#{actual_str} / #{target_str} #{unit_str}（#{achievement_rate.to_i}%）".strip
    else
      # チェック型: 「達成日数 / 目標日数 日（XX%）」形式
      "#{actual_count} / #{weekly_target} 日（#{achievement_rate.to_i}%）"
    end
  end

  # achievement_rate_text : 達成率を「83.33%」形式で返す
  #
  # format('%.2f%%', ...) を使う理由:
  #   表示フォーマットと数値計算を分離できる。
  #   %% は % を文字として出力するためのエスケープ。
  def achievement_rate_text
    format("%.2f%%", achievement_rate)
  end

  # achieved? : 達成済みかどうか（達成率が100%以上）
  def achieved?
    achievement_rate >= 100
  end

  # ============================================================
  # プライベートクラスメソッド
  # ============================================================

  # calculate_rate : 達成率の計算ロジック
  #
  # 【引数】
  #   actual : 実績値（整数 or BigDecimal）
  #   target : 目標値（整数）
  #
  # 【各処理の役割】
  #   .to_f   → 割り算を Float で行う（BigDecimal のまま演算しても問題ないが
  #              clamp/round との相性を考慮して Float に変換）
  #   .clamp  → 実績が目標を超えても 100% までに収める
  #   .round  → 小数点2桁で丸める（例: 83.333... → 83.33）
  private_class_method def self.calculate_rate(actual, target)
    ((actual.to_f / target.to_f) * 100).clamp(0, 100).round(2)
  end
end