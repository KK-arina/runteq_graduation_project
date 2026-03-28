# app/models/habit.rb
#
# ==============================================================================
# Habit（習慣）モデル（B-2: 除外日設定対応）
# ==============================================================================
# 【B-2 での変更内容】
#
#   ① has_many :habit_excluded_days を追加
#      習慣が削除されたときに除外日設定も一緒に削除するため
#      dependent: :destroy を指定する。
#
#   ② effective_weekly_target メソッドを追加
#      実施予定日数 = 7 - 除外日数 を返す。
#      達成率計算の分母として使用する。
#
#   ③ weekly_progress_stats を除外日対応に更新
#      分母を weekly_target から effective_weekly_target に変更。
#      チェック型のみ除外日の影響を受ける（数値型は目標値で計算する）。
#
#   ④ excluded_day_numbers メソッドを追加
#      設定されている除外日の day_of_week 配列を返す便利メソッド。
#      ビューや計算で何度も habit.habit_excluded_days.pluck(:day_of_week) と
#      書かずに済むようにする。
#
# 【なぜチェック型だけ除外日の影響を受けるのか】
#   チェック型: 「週に何日実施するか」が目標 → 除外日を引いた実施可能日数が分母
#               例: 目標5日, 除外: 土日 → 5日/5日 = 100%（7日ではなく5日が満点）
#   数値型:     「週に何分/冊/km達成するか」が目標 → 曜日に依存しない絶対数値
#               例: 目標150分, 除外: 土日 → 150分/150分 = 100%（分母は変わらない）
# ==============================================================================

class Habit < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  belongs_to :user
  has_many :habit_records, dependent: :destroy
  has_many :weekly_reflection_habit_summaries, dependent: :nullify

  # has_many :habit_excluded_days（B-2 追加）
  # 【理由】
  #   習慣に対して複数の除外日を設定できる（例: 土曜・日曜の2件）。
  #   dependent: :destroy を指定することで、習慣が論理削除（soft_delete）ではなく
  #   物理削除されたときに除外日設定も一緒に削除される。
  #   論理削除（deleted_at を付ける）の場合は連動しないが、
  #   将来の完全削除機能に備えて指定しておく。
  has_many :habit_excluded_days, dependent: :destroy

  # ============================================================
  # Enum 定義
  # ============================================================

  # measurement_type の enum
  # DB には整数（0, 1）で保存されるが、Ruby 上では名前で扱える。
  # 自動生成されるメソッド例:
  #   habit.check_type?   → measurement_type == 0 なら true
  #   habit.numeric_type? → measurement_type == 1 なら true
  #   Habit.check_type    → measurement_type が 0 の習慣を返すスコープ
  enum :measurement_type, {
    check_type:   0,  # チェック型（やった/やらない）
    numeric_type: 1   # 数値型（分・冊・km などを数値で記録）
  }

  # ============================================================
  # バリデーション
  # ============================================================

  validates :name, presence: true, length: { maximum: 50 }

  # ── weekly_target のバリデーション ──────────────────────────────────────────
  #
  # 共通: 必須・整数・1以上（チェック型・数値型どちらも最低1以上必要）
  # チェック型専用: 7以下（週7日が上限）
  # 数値型は上限なし
  validates :weekly_target,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              message: "は1以上の整数を入力してください"
            }

  # チェック型のみ weekly_target の上限を7に制限する
  validates :weekly_target,
            numericality: {
              less_than_or_equal_to: 7,
              message: "は7以下で設定してください（チェック型は週7日が最大）"
            },
            if: -> { check_type? }

  # measurement_type は enum の有効値のみ許可
  validates :measurement_type, presence: true,
                                inclusion: {
                                  in: measurement_types.keys,
                                  message: "は有効な値を選択してください"
                                }

  # 数値型では unit（単位）を必須にする
  validates :unit,
            presence: {
              message: "は数値型習慣では入力が必要です"
            },
            length: { maximum: 10 },
            if: -> { numeric_type? }

  # ============================================================
  # スコープ
  # ============================================================

  # active: 論理削除されていない習慣だけを返す
  scope :active, -> { where(deleted_at: nil) }

  # deleted: 論理削除済みの習慣だけを返す
  scope :deleted, -> { where.not(deleted_at: nil) }

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  def soft_delete
    touch(:deleted_at)
  end

  def active?
    deleted_at.nil?
  end

  def deleted?
    !active?
  end

  # excluded_day_numbers（B-2 追加）
  # 【役割】
  #   設定されている除外日の day_of_week 番号の配列を返す。
  #
  # 【なぜ便利メソッドとして定義するのか】
  #   ビューや達成率計算で除外日番号が必要な場面が複数ある。
  #   毎回 habit.habit_excluded_days.pluck(:day_of_week) と書くと冗長で、
  #   N+1 問題も起きやすい。
  #   このメソッドに一本化することでコードの重複を防ぐ。
  #
  # 【pluck(:day_of_week) とは】
  #   関連レコードから指定カラムの値だけを配列で取得する Rails メソッド。
  #   HabitExcludedDay オブジェクト全体を取得する load より軽量。
  #   例: habit に土曜(6)・日曜(0)が設定されている場合 → [6, 0] を返す
  #
  # 【.sort の理由】
  #   表示順を曜日番号の昇順（0=日〜6=土）に統一するため。
  #   pluck は挿入順に返すことが多いが保証されないため明示的にソートする。
  def excluded_day_numbers
    habit_excluded_days.pluck(:day_of_week).sort
  end

  # effective_weekly_target（B-2 追加）
  # 【役割】
  #   チェック型習慣の「実際に実施予定の日数」を返す。
  #   達成率計算の分母として使用する。
  #
  # 【計算式】
  #   実施予定日数 = weekly_target（目標日数）
  #   ただし除外日がある場合は（7 - 除外日数）と weekly_target の小さい方を使う。
  #
  # 【なぜ min を使うのか】
  #   例: weekly_target=5, 除外日=土日(2日)
  #     → 実施可能な最大日数 = 7 - 2 = 5日
  #     → effective_weekly_target = min(5, 5) = 5  ← 正しい
  #   例: weekly_target=5, 除外日=なし
  #     → 実施可能な最大日数 = 7 - 0 = 7日
  #     → effective_weekly_target = min(5, 7) = 5  ← 正しい
  #   例: weekly_target=3, 除外日=土日+金(3日)
  #     → 実施可能な最大日数 = 7 - 3 = 4日
  #     → effective_weekly_target = min(3, 4) = 3  ← 正しい
  #
  # 【数値型では呼び出さない】
  #   数値型は weekly_target が絶対数値（分・冊など）のため除外日は関係ない。
  #   呼び出し元で check_type? を確認してから使うこと。
  def effective_weekly_target
    excluded_count = habit_excluded_days.size
    available_days = 7 - excluded_count
    # weekly_target と実施可能な最大日数の小さい方を返す
    # [a, b].min → a と b の小さい方を返す Ruby の Array#min
    [ weekly_target, available_days ].min
  end

  # ============================================================
  # 進捗統計メソッド
  # ============================================================

  # weekly_progress_stats（B-2: 除外日対応に更新）
  # 今週の進捗率と詳細を返す。measurement_type によって計算方法を分岐する。
  #
  # 【B-2 での変更内容】
  #   チェック型の分母を weekly_target から effective_weekly_target に変更。
  #   除外日がある場合は実施予定日数（最大 7 - 除外日数）が分母になる。
  #
  # 戻り値 Hash:
  #   チェック型: { rate: Integer, completed_count: Integer, numeric_sum: nil,
  #                 effective_target: Integer }
  #   数値型:     { rate: Integer, completed_count: nil, numeric_sum: Float,
  #                 effective_target: Integer }
  def weekly_progress_stats(user)
    range = current_week_range

    if check_type?
      # 【B-2 変更】分母を effective_weekly_target（除外日考慮後の実施予定日数）に変更
      target = effective_weekly_target
      return { rate: 0, completed_count: 0, numeric_sum: nil, effective_target: target } if target.zero?

      completed_count = habit_records
                          .where(user: user, record_date: range, completed: true)
                          .count
      rate = ((completed_count.to_f / target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: completed_count, numeric_sum: nil, effective_target: target }
    else
      # 数値型は weekly_target のまま（除外日は関係ない）
      return { rate: 0, completed_count: nil, numeric_sum: 0.0, effective_target: weekly_target } if weekly_target.zero?

      numeric_sum   = habit_records
                        .where(user: user, record_date: range, deleted_at: nil)
                        .sum(:numeric_value)
      numeric_sum_f = numeric_sum.to_f
      rate          = ((numeric_sum_f / weekly_target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: nil, numeric_sum: numeric_sum_f, effective_target: weekly_target }
    end
  end

  # ============================================================
  # private
  # ============================================================
  private

  # current_week_range: AM4:00基準で「今週の月曜日〜今日」の Range を返す
  def current_week_range
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_start..today
  end
end