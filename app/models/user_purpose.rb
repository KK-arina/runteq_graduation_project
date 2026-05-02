# app/models/user_purpose.rb
#
# ==============================================================================
# UserPurpose（PMVV目標）モデル（D-5: 危機介入機能を追加）
# ==============================================================================
# 【D-5 での変更内容】
#   ① CrisisDetector モジュールをインクルード
#   ② crisis_text_fields メソッドを定義（検出対象フィールドを指定）
# ==============================================================================

class UserPurpose < ApplicationRecord
  # ── D-5 追加: CrisisDetector モジュールをインクルードする ────────────────
  #
  # 【インクルードの理由】
  #   PMVV 入力の各フィールドに危機ワードが含まれていないかを
  #   before_validation で自動検出する。
  #   特に「Current（今の自分の現状）」フィールドには
  #   つらい現状が書かれる可能性が高いため、全フィールドを対象にする。
  include CrisisDetector
  # ────────────────────────────────────────────────────────────────────────────

  # ============================================================
  # アソシエーション
  # ============================================================
  belongs_to :user

  # ============================================================
  # enum 定義
  # ============================================================
  enum :analysis_state, {
    pending:   0,
    analyzing: 1,
    completed: 2,
    failed:    3
  }

  # ============================================================
  # バリデーション
  # ============================================================
  validates :version,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  validates :purpose,           length: { maximum: 1000 }, allow_blank: true
  validates :mission,           length: { maximum: 1000 }, allow_blank: true
  validates :vision,            length: { maximum: 1000 }, allow_blank: true
  validates :value,             length: { maximum: 500  }, allow_blank: true
  validates :current_situation, length: { maximum: 1000 }, allow_blank: true

  validate :at_least_one_field_present

  # ============================================================
  # スコープ
  # ============================================================
  scope :active,      -> { where(is_active: true) }
  scope :by_version,  -> { order(version: :desc) }

  # ============================================================
  # コールバック
  # ============================================================
  before_validation :set_version, on: :create
  before_save       :deactivate_previous_versions

  # ============================================================
  # クラスメソッド
  # ============================================================
  def self.current_for(user)
    where(user: user, is_active: true).order(version: :desc).first
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # ── D-5 追加: crisis_text_fields ──────────────────────────────────────────
  #
  # 【役割】
  #   CrisisDetector モジュールが危機ワードを検索する対象フィールドを返す。
  #
  # 【対象フィールドの選定理由】
  #   PMVV の全フィールドを対象にする。
  #   特に current_situation（現状）と mission（今最も必要なこと）には
  #   追い詰められた状況が書かれる可能性がある。
  def crisis_text_fields
    [
      purpose,           # 人生で大切にしていること
      mission,           # 今最も必要なこと
      vision,            # 1年後の理想の自分
      value,             # 絶対に譲れないこと
      current_situation  # 今の自分の現状（最も危機ワードが出やすいフィールド）
    ]
  end
  # ────────────────────────────────────────────────────────────────────────────

  def set_version
    max_version = user.user_purposes.maximum(:version).to_i
    self.version = max_version + 1
  end

  def deactivate_previous_versions
    scope = user.user_purposes.where(is_active: true)
    scope = scope.where.not(id: id) if persisted?
    scope.update_all(is_active: false)
  end

  def at_least_one_field_present
    fields = [purpose, mission, vision, value, current_situation]
    if fields.all?(&:blank?)
      errors.add(:base, "Purpose / Mission / Vision / Value / Current のうち少なくとも1つを入力してください")
    end
  end
end