# app/models/weekly_reflection.rb
#
# ==============================================================================
# WeeklyReflection モデル（リフレクション手法対応）
# ==============================================================================
# 【変更内容】
#   ① next_action カラムのバリデーション追加（1000文字以内、任意）
#      「からの？（次への展開）」に対応するカラム
#
# 【カラムと UI の対応表】
#   DB カラム名          | UIラベル            | リフレクション項目
#   ────────────────────|─────────────────────|──────────────────
#   direct_reason        | なぜ？（直接の原因） | Why（なぜ）
#   background_situation | どう？（改善策）      | How（どう）※ラベルを変更
#   next_action          | からの？（次への展開）| Next（からの）※新規追加
#   reflection_comment   | 自由コメント（任意） | 自由記述
#
# 【background_situation について】
#   カラム名は「背景・状況」を意味するが、UI の変更に伴い
#   「どうすれば来週は変えられそうですか？（改善策）」として使う。
#   カラム名のリネームは既存マイグレーション不変ルールのため行わず、
#   View のラベルのみ変更することで対応する。
# ==============================================================================

class WeeklyReflection < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================
  belongs_to :user

  has_many :habit_summaries,
           class_name: "WeeklyReflectionHabitSummary",
           dependent: :destroy

  # ============================================================
  # コールバック
  # ============================================================

  # before_validation :set_year_and_week_number
  # バリデーション実行「前」に year と week_number を自動セットする。
  # week_start_date から ISO 週番号を計算して設定する。
  before_validation :set_year_and_week_number

  # ============================================================
  # バリデーション
  # ============================================================

  validates :week_start_date, presence: true
  validates :week_end_date,   presence: true

  # reflection_comment: 自由コメント（任意・1000文字以内）
  validates :reflection_comment, length: { maximum: 1000 }

  # direct_reason: なぜ？（直接の原因）任意・1000文字以内
  validates :direct_reason, length: { maximum: 1000 }

  # background_situation: どう？（改善策）任意・1000文字以内
  # ※ UI ラベルは「背景・状況」→「どうすれば変えられそうか？」に変更済み
  validates :background_situation, length: { maximum: 1000 }

  # ── 追加: next_action バリデーション ──────────────────────────────────────
  #
  # next_action: からの？（次への展開）任意・1000文字以内
  # 「この振り返りから他の習慣・行動に活かせることは何か？」を記入する欄。
  # UI 設計では任意入力のため presence バリデーションは付けない。
  validates :next_action, length: { maximum: 1000 }
  # ────────────────────────────────────────────────────────────────────────────

  validate :week_end_date_must_be_six_days_after_start

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

  # current_week_start_date
  # AM4:00 基準で「今週の月曜日」を返す。
  # ダッシュボードの日付計算と同じ基準を使うことで一貫性を保つ。
  def self.current_week_start_date
    (Time.current - 4.hours).beginning_of_week(:monday).to_date
  end

  # find_or_build_for_current_week
  # 今週の振り返りレコードを探して返す。なければ初期値でビルドする。
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

  # completed?: completed_at に時刻が入っているかどうかを返す
  def completed?
    completed_at.present?
  end

  # week_label: 「2026/03/09 - 03/15」形式の文字列を返す（ビューで使用）
  def week_label
    "#{week_start_date.strftime('%Y/%m/%d')} - #{week_end_date.strftime('%m/%d')}"
  end

  # pending?: completed? の逆（未完了かどうか）
  def pending?
    !completed?
  end

  # complete!: 振り返りを完了状態にする（冪等性あり）
  # completed? が true の場合は何もしない。
  def complete!
    return if completed?
    update!(completed_at: Time.current, is_locked: true)
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # set_year_and_week_number
  # week_start_date から ISO 週番号の year・week_number を自動計算する。
  # UNIQUE 制約 (user_id, year, week_number) のために必要。
  #
  # cwyear: ISO 週番号ベースの年（12月末〜1月初の境界で正確）
  # cweek:  ISO 週番号（1〜53）
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
