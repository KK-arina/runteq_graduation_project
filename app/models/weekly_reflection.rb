# app/models/weekly_reflection.rb
#
# ==============================================================================
# WeeklyReflection モデル（E-1: 気分スコア・バリデーション拡充）
# ==============================================================================
# 【E-1 での変更内容】
#   ① mood バリデーションを追加（1〜5 の整数。任意入力なので allow_nil: true）
#   ② reflection_comment に presence: true を追加
#      （変更前: length のみ → 変更後: presence: true, length: { maximum: 1000 }）
#
# 【レビュー指摘対応 (修正①)】
#   numericality に in: オプションは Rails 標準に存在しない。
#   greater_than_or_equal_to / less_than_or_equal_to を使用する。
#
# 【カラムと UI の対応表】
#   DB カラム名          | UIラベル            | リフレクション項目
#   ────────────────────|─────────────────────|──────────────────
#   mood                 | 気分スコア（1〜5）   | ★評価
#   direct_reason        | なぜ？（直接の原因） | Why（なぜ）
#   background_situation | どう？（改善策）      | How（どう）
#   next_action          | からの？（次への展開）| Next（からの）
#   reflection_comment   | 自由コメント（必須） | 自由記述
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

  # ── E-1 変更: reflection_comment に presence: true を追加 ─────────────────
  #
  # 【変更前】validates :reflection_comment, length: { maximum: 1000 }
  # 【変更後】presence: true, length: { maximum: 1000 }
  #
  # 【変更理由】
  #   振り返りコメントはAI分析の主要入力項目であるため必須化する。
  #   空のまま送信するとAI分析の質が著しく低下するため。
  #   presence: true は nil・空文字・空白文字のみ、の3パターンすべてを弾く。
  #   （Rails の presence は内部で blank? を使うため " " も弾かれる）
  #
  # 【i18n との連携】
  #   エラーメッセージは ja.yml の
  #   activerecord.attributes.weekly_reflection.reflection_comment
  #   から自動的に「振り返りコメントを入力してください」と表示される。
  validates :reflection_comment,
            presence: true,
            length: { maximum: 1000 }
  # ────────────────────────────────────────────────────────────────────────────

  validates :direct_reason,        length: { maximum: 1000 }
  validates :background_situation, length: { maximum: 1000 }
  validates :next_action,          length: { maximum: 1000 }

  # ── E-1 追加: mood バリデーション ─────────────────────────────────────────
  #
  # 【重要: numericality に in: オプションは存在しない】
  #   Rails の numericality バリデーターには in: オプションがない。
  #   in: を使うと「Unknown validator」または「silently ignored」になるため
  #   greater_than_or_equal_to / less_than_or_equal_to を使用する。
  #
  # 【allow_nil: true を使う理由】
  #   気分スコアは「任意入力」の項目。
  #   未入力（nil）でもフォームを送信できるようにするため allow_nil: true を使う。
  #   allow_nil: true は「nil の場合はこのバリデーションをスキップする」という意味。
  #   nil 以外の値が入力された場合のみ範囲チェック・整数チェックが走る。
  #
  # 【only_integer: true を使う理由】
  #   小数点の気分スコア（例: 3.5）は想定しない。
  #   ただし mood は DB の integer カラムなので ActiveRecord が自動的に
  #   小数を整数にキャストすることがある。
  #   only_integer: true を設定することで、フォームから文字列 "3.5" が
  #   送られてきた場合にバリデーションエラーにする。
  #
  # 【greater_than_or_equal_to: 1, less_than_or_equal_to: 5 の理由】
  #   星評価は1〜5の5段階。範囲外の値（0や6など）が
  #   パラメータ改ざんで送られてきた場合も弾くため明示的に範囲指定する。
  validates :mood,
            numericality: {
              only_integer:             true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to:    5,
              message:                  "は1〜5の整数で入力してください"
            },
            allow_nil: true
  # ────────────────────────────────────────────────────────────────────────────

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
  #   外部から直接呼ばれる必要はない。
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
