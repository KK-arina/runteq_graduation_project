# app/models/weekly_reflection_habit_summary.rb
#
# 【このモデルの役割】
# 週次振り返り時点の「習慣のスナップショット」を管理するモデル。
#
# 【スナップショット設計とは？】
# Habit（習慣）は後から名前・目標値を変更できます。
# しかし週次振り返りは「振り返りを行った時点の状態」を永続保存する必要があります。
#
# 例：
# 1週目：習慣名「読書」目標7回 → サマリーに「読書, 7回」をコピー保存
# 2週目：習慣名を「英語学習」に変更
# → 1週目の振り返りを見ても「読書」のまま表示される（正しい記録を守れる）
#
# これが「履歴テーブル」ではなく「スナップショット」と呼ぶ理由です。

class WeeklyReflectionHabitSummary < ApplicationRecord
  # ============================================================
  # アソシエーション（関連付け）
  # ============================================================

  # このサマリーは必ず WeeklyReflection に属する
  belongs_to :weekly_reflection

  # optional: true にする理由：
  # on_delete: :nullify により、元の習慣が物理削除されると habit_id が NULL になります。
  # NULL になった場合でも belongs_to のバリデーションでエラーにならないよう optional: true を設定。
  # habit_name 等のスナップショットデータは残るので、画面表示には影響しません。
  belongs_to :habit, optional: true

  # ============================================================
  # バリデーション（入力値の検証）
  # ============================================================

  validates :habit_name,
            presence: true,
            length: { maximum: 50 }

  # weekly_target は達成率計算の「分母」になるため 1 以上を必須とします
  # 0 だと ZeroDivisionError が発生するため防御します
  validates :weekly_target,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  validates :actual_count,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 達成率は 0.00〜100.00 の範囲に収まるよう制限します
  validates :achievement_rate,
            presence: true,
            numericality: {
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 100
            }

  # DBレベルのUNIQUE制約に加え、Railsレベルでも重複を防ぎます（二重保証）
  # allow_nil: true → habit_id が NULL の場合はこのバリデーションをスキップします
  validates :habit_id,
            uniqueness: {
              scope: :weekly_reflection_id,
              message: 'は既にこの振り返りに含まれています'
            },
            allow_nil: true

  # ============================================================
  # スコープ
  # ============================================================

  scope :by_achievement, -> { order(achievement_rate: :desc) }
  scope :completed,      -> { where(achievement_rate: 100) }
  scope :incomplete,     -> { where('achievement_rate < ?', 100) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # 1つの WeeklyReflection に紐づく全習慣のスナップショットを一括作成します
  def self.create_all_for_reflection!(weekly_reflection)
    # transaction により「全部成功 or 全部失敗」を保証します
    # 1件でも save! が失敗すると全件ロールバック（巻き戻し）されます
    transaction do
      weekly_reflection.user.habits.active.each do |habit|
        # ── 改善点：二重作成の防止 ──────────────────────────────
        # 既に同じ habit のサマリーが存在する場合はスキップします。
        # 例えば振り返り入力途中でページを再読み込みした場合など、
        # このメソッドが2回呼ばれてもUNIQUEエラーにならず安全に動作します。
        # ────────────────────────────────────────────────────────
        next if weekly_reflection.habit_summaries.exists?(habit: habit)

        build_from_habit(weekly_reflection, habit).save!
      end
    end
  end

  # 習慣データからサマリーのインスタンスを組み立てます（DBには保存しません）
  def self.build_from_habit(weekly_reflection, habit)
    user       = weekly_reflection.user
    week_range = weekly_reflection.week_start_date..weekly_reflection.week_end_date

    actual_count = habit.habit_records
                        .where(user: user, record_date: week_range, completed: true)
                        .count

    rate = calculate_rate(actual_count, habit.weekly_target)

    # weekly_reflection.habit_summaries.build を使うことで
    # weekly_reflection_id が自動的にセットされます
    weekly_reflection.habit_summaries.build(
      habit:            habit,
      habit_name:       habit.name,           # スナップショット：振り返り時点の習慣名
      weekly_target:    habit.weekly_target,   # スナップショット：振り返り時点の目標値
      actual_count:     actual_count,
      achievement_rate: rate
    )
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # 達成率を「83.33%」形式で返します
  # ── 改善点：format を使う理由 ────────────────────────────────
  # format('%.2f%%', ...) は表示フォーマットと数値計算を分離できます。
  # 将来 DB の scale（小数桁数）が変わっても、表示は常に2桁を保証できます。
  # %% は % を文字として出力するためのエスケープです。
  # ────────────────────────────────────────────────────────────
  def achievement_rate_text
    format('%.2f%%', achievement_rate)
  end

  # 達成済みかどうか（達成率が100%以上）
  def achieved?
    achievement_rate >= 100
  end

  # ============================================================
  # プライベートクラスメソッド
  # ============================================================

  # 達成率の計算ロジックを独立させることで、変更が1箇所で済みます
  private_class_method def self.calculate_rate(actual, target)
    # .to_f → 整数同士の割り算では小数点以下が切り捨てられるため Float に変換します
    # .clamp(0, 100) → 実績が目標を超えても 100% までに収めます
    # .round(2) → 小数点2桁で丸めます（例: 83.333... → 83.33）
    ((actual.to_f / target) * 100).clamp(0, 100).round(2)
  end
end