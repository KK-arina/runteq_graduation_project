# app/models/weekly_reflection.rb
#
# ==============================================================================
# WeeklyReflection モデル
# ==============================================================================
# 【変更履歴】
#   D-5: CrisisDetector モジュールをインクルード
#   E-1: mood バリデーション追加（1〜5の整数、任意入力）
#   E-1: reflection_comment に presence: true を追加（必須化）
#   E-1追加: direct_reason / background_situation / next_action を必須化
#   E-1修正: reflection_comment を任意に戻す
#            （ユーザーフィードバック: 自由コメントは任意にしてほしい）
#
# 【カラムと UI の対応表】
#   DB カラム名          | UIラベル                | 必須/任意
#   ────────────────────|─────────────────────────|──────────
#   mood                 | 気分スコア（1〜5）       | 任意
#   direct_reason        | なぜ？（直接の原因）     | 必須
#   background_situation | どう？（改善策）          | 必須
#   next_action          | からの？（次への展開）   | 必須
#   reflection_comment   | 自由コメント             | 任意（E-1修正で任意に戻す）
# ==============================================================================

class WeeklyReflection < ApplicationRecord
  # ── D-5 追加: CrisisDetector モジュールをインクルードする ────────────────
  include CrisisDetector

  # ============================================================
  # アソシエーション
  # ============================================================
  belongs_to :user

  has_many :habit_summaries,
           class_name: "WeeklyReflectionHabitSummary",
           dependent: :destroy

  has_many :task_summaries,
           class_name: "WeeklyReflectionTaskSummary",
           dependent: :destroy

  # ============================================================
  # コールバック
  # ============================================================
  before_validation :set_year_and_week_number

  # ============================================================
  # バリデーション
  # ============================================================
  validates :week_start_date, presence: true
  validates :week_end_date,   presence: true

  # ── E-1修正: reflection_comment を任意に戻す ──────────────────────────────
  #
  # 【変更前】presence: true, length: { maximum: 1000 }
  # 【変更後】length: { maximum: 1000 } のみ（presence: true を削除）
  #
  # 【変更理由】
  #   ユーザーフィードバックで「自由コメントは任意にしてほしい」という要件が追加された。
  #   自由コメントは任意入力のため、空でも保存できるようにする。
  #   allow_blank: true を使うと「空の場合はこのバリデーションをスキップする」という意味になる。
  #   つまり nil・空文字でも保存できるが、入力があれば1000文字以内チェックが走る。
  validates :reflection_comment, length: { maximum: 1000 }, allow_blank: true
  # ────────────────────────────────────────────────────────────────────────────

  # ── E-1追加: direct_reason バリデーション（必須）────────────────────────
  #
  # 【presence: true の意味】
  #   nil・空文字・空白のみの3パターンを弾く。
  #   Rails の presence は内部で blank? を使うため "   " も無効になる。
  #
  # 【i18n との連携】
  #   ja.yml の activerecord.attributes.weekly_reflection.direct_reason
  #   に "なぜ？（直接の原因）" と定義してあるため、
  #   エラーメッセージは「なぜ？（直接の原因）を入力してください」と表示される。
  validates :direct_reason,
            presence: true,
            length: { maximum: 1000 }

  # ── E-1追加: background_situation バリデーション（必須）──────────────────
  #
  # 【i18n との連携】
  #   ja.yml に "どう？（改善策）" と定義してあるため
  #   「どう？（改善策）を入力してください」と表示される。
  validates :background_situation,
            presence: true,
            length: { maximum: 1000 }

  # ── E-1追加: next_action バリデーション（必須）───────────────────────────
  #
  # 【i18n との連携】
  #   ja.yml に "からの？（次への展開）" と定義してあるため
  #   「からの？（次への展開）を入力してください」と表示される。
  validates :next_action,
            presence: true,
            length: { maximum: 1000 }

  # ── E-1 追加: mood バリデーション ─────────────────────────────────────────
  #
  # 【allow_nil: true を使う理由】
  #   気分スコアは任意入力のため nil を許容する。
  #
  # 【greater_than_or_equal_to / less_than_or_equal_to を使う理由】
  #   numericality に in: オプションは存在しない（Rails標準外）。
  #   この2つのオプションで 1〜5 の範囲を指定する。
  validates :mood,
            numericality: {
              only_integer:             true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to:    5,
              message:                  "は1〜5の整数で入力してください"
            },
            allow_nil: true

  validate  :week_end_date_must_be_six_days_after_start

  # ============================================================
  # スコープ
  # ============================================================
  scope :completed, -> { where.not(completed_at: nil) }
  scope :pending,   -> { where(completed_at: nil) }
  scope :recent,    -> { order(week_start_date: :desc) }
  scope :for_week,  ->(date) { where(week_start_date: date) }

  # ============================================================
  # クラスメソッド
  # ============================================================
  def self.current_week_start_date
    (Time.current - 4.hours).beginning_of_week(:monday).to_date
  end

  def self.find_or_build_for_current_week(user)
    start_date = current_week_start_date
    user.weekly_reflections.find_or_initialize_by(
      week_start_date: start_date
    ) do |reflection|
      reflection.week_end_date = start_date + 6.days
    end
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================
  def completed?
    completed_at.present?
  end

  def week_label
    "#{week_start_date.strftime('%Y/%m/%d')} - #{week_end_date.strftime('%m/%d')}"
  end

  def pending?
    !completed?
  end

  def complete!
    return if completed?
    update!(completed_at: Time.current, is_locked: true)
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  def crisis_text_fields
    [
      direct_reason,
      background_situation,
      next_action,
      reflection_comment
    ]
  end

  def set_year_and_week_number
    return unless week_start_date.present?
    self.year        = week_start_date.cwyear
    self.week_number = week_start_date.cweek
  end

  def week_end_date_must_be_six_days_after_start
    return unless week_start_date.present? && week_end_date.present?
    unless week_end_date == week_start_date + 6.days
      errors.add(:week_end_date, "は週の開始日から6日後でなければなりません")
    end
  end
end
