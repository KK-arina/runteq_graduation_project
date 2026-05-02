# app/models/weekly_reflection.rb
#
# ==============================================================================
# WeeklyReflection モデル（D-5: 危機介入機能を追加）
# ==============================================================================
# 【D-5 での変更内容】
#   ① CrisisDetector モジュールをインクルード
#   ② crisis_text_fields メソッドを定義（検出対象フィールドを指定）
#
# 【カラムと UI の対応表】
#   DB カラム名          | UIラベル            | リフレクション項目
#   ────────────────────|─────────────────────|──────────────────
#   direct_reason        | なぜ？（直接の原因） | Why（なぜ）
#   background_situation | どう？（改善策）      | How（どう）
#   next_action          | からの？（次への展開）| Next（からの）
#   reflection_comment   | 自由コメント（任意） | 自由記述
# ==============================================================================

class WeeklyReflection < ApplicationRecord
  # ── D-5 追加: CrisisDetector モジュールをインクルードする ────────────────
  #
  # 【インクルードの理由】
  #   振り返り入力の各テキストフィールドに「死にたい」「消えたい」などの
  #   危機ワードが含まれていないかを before_validation で自動検出する。
  #   検出された場合は crisis_word_detected フラグが true になる。
  #   このフラグをコントローラーが確認して AI 分析ジョブをスキップし、
  #   代わりに crisis_detected=true で AiAnalysis を記録する。
  include CrisisDetector
  # ────────────────────────────────────────────────────────────────────────────

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
  validates :reflection_comment, length: { maximum: 1000 }
  validates :direct_reason,      length: { maximum: 1000 }
  validates :background_situation, length: { maximum: 1000 }
  validates :next_action,        length: { maximum: 1000 }
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

  # ── D-5 追加: crisis_text_fields ──────────────────────────────────────────
  #
  # 【役割】
  #   CrisisDetector モジュールの check_crisis_keywords メソッドが
  #   危機ワードを検索する対象フィールドの値を配列で返す。
  #
  # 【なぜ private か】
  #   このメソッドは CrisisDetector から内部的に呼ばれるため、
  #   外部から直接呼ばれる必要はない。private にすることで
  #   誤った呼び出しを防ぐ。
  #
  # 【対象フィールドの選定理由】
  #   振り返り入力で自由記述できる全テキストフィールドを対象にする。
  #   ユーザーがどのフィールドに書くか予測できないため、全フィールドを検索する。
  def crisis_text_fields
    [
      direct_reason,        # なぜ？（直接の原因）
      background_situation, # どう？（改善策）
      next_action,          # からの？（次への展開）
      reflection_comment    # 自由コメント
    ]
  end
  # ────────────────────────────────────────────────────────────────────────────

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