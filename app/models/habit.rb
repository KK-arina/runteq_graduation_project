# app/models/habit.rb
#
# ==============================================================================
# Habit（習慣）モデル（B-1: レビュー修正版）
# ==============================================================================
# 【レビュー指摘による修正内容】
#
#   ① weekly_target のバリデーションを measurement_type で分岐（重要修正）
#      修正前: 全習慣で 1〜7 の制限
#             → 数値型で「150分/週」のような目標が設定できなかった
#      修正後: チェック型は 1〜7、数値型は 1 以上（上限なし）
#
# 【なぜ分岐が必要なのか】
#   チェック型: 1週間は最大7日 → weekly_target の上限は7が自然
#   数値型:    「150分/週」「50冊/年換算で週1冊」など、7を超える値が意味を持つ
#              → 上限を設けると有用な習慣が登録できなくなる
# ==============================================================================

class Habit < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  belongs_to :user
  has_many :habit_records, dependent: :destroy
  has_many :weekly_reflection_habit_summaries, dependent: :nullify

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

  # ── weekly_target のバリデーション（レビュー修正版）──────────────────────
  #
  # 【修正前の問題】
  #   less_than_or_equal_to: 7 という制限がチェック型・数値型に一律に適用されていた。
  #   数値型で「150分/週」という目標を設定しようとすると弾かれてしまっていた。
  #
  # 【修正内容】
  #   共通バリデーション: 必須・整数・1以上（チェック型・数値型どちらも最低1以上必要）
  #   チェック型専用:     7以下（週7日が上限）
  #   数値型は上限なし（カスタムバリデーションで制御しない）
  #
  # 【less_than_or_equal_to: 7 を unless で制御する理由】
  #   if: -> { check_type? } を使うと「チェック型のときだけ7以下」という
  #   制約を明示できて意図が伝わりやすい。
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
  # ────────────────────────────────────────────────────────────────────────────

  # measurement_type は enum の有効値のみ許可
  validates :measurement_type, presence: true,
                                inclusion: {
                                  in: measurement_types.keys,
                                  message: "は有効な値を選択してください"
                                }

  # 数値型では unit（単位）を必須にする
  # チェック型では unit は不要（nil でOK）
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

  # ============================================================
  # 進捗統計メソッド
  # ============================================================

  # weekly_progress_stats
  # 今週の進捗率と詳細を返す。measurement_type によって計算方法を分岐する。
  #
  # チェック型: 完了日数 / weekly_target × 100
  # 数値型:    SUM(numeric_value) / weekly_target × 100
  #
  # 戻り値 Hash:
  #   チェック型: { rate: Integer, completed_count: Integer, numeric_sum: nil }
  #   数値型:    { rate: Integer, completed_count: nil, numeric_sum: Float }
  def weekly_progress_stats(user)
    range = current_week_range
    return { rate: 0, completed_count: 0, numeric_sum: nil } if weekly_target.zero?

    if check_type?
      completed_count = habit_records
                          .where(user: user, record_date: range, completed: true)
                          .count
      rate = ((completed_count.to_f / weekly_target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: completed_count, numeric_sum: nil }
    else
      numeric_sum   = habit_records
                        .where(user: user, record_date: range, deleted_at: nil)
                        .sum(:numeric_value)
      numeric_sum_f = numeric_sum.to_f
      rate          = ((numeric_sum_f / weekly_target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: nil, numeric_sum: numeric_sum_f }
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
