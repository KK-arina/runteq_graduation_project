# app/models/user.rb
#
# ==============================================================================
# User（ユーザー）モデル
# ==============================================================================
#
# 【B-3 での変更内容】
#   has_one :user_setting を追加。
#   Habit#on_rest_mode? が user.user_setting を参照するため必要。
#
# ==============================================================================

class User < ApplicationRecord
  # ============================================================
  # 認証関連
  # ============================================================

  has_secure_password

  # ============================================================
  # アソシエーション
  # ============================================================

  has_many :habits, dependent: :destroy
  has_many :habit_records, dependent: :destroy
  has_many :weekly_reflections, dependent: :destroy

  # has_one :user_setting（B-3 追加）
  # 【理由】
  #   Habit#on_rest_mode? が user.user_setting&.rest_mode_active? を呼ぶため、
  #   User モデルから user_setting にアクセスできる必要がある。
  #   1人のユーザーに1つの設定レコード（UNIQUE制約あり）のため has_one を使う。
  has_one :user_setting

  # ============================================================
  # バリデーション
  # ============================================================

  validates :name,  presence: true, length: { maximum: 50 }
  validates :email,
            presence: true,
            length: { maximum: 255 },
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # ============================================================
  # コールバック
  # ============================================================

  before_save :downcase_email

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  def locked?
    adjusted_time = Time.current - 4.hours
    return false unless adjusted_time.monday?

    last_week_start = WeeklyReflection.current_week_start_date - 7.days

    last_week_completed = weekly_reflections
                            .for_week(last_week_start)
                            .completed
                            .exists?

    !last_week_completed
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  def downcase_email
    self.email = email.to_s.downcase
  end
end