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
# 【C-1 での変更内容】
#   has_many :tasks を追加。
#   TasksController で current_user.tasks を使うために必要。
#
# 【D-1 での変更内容】
#   has_many :user_purposes を追加。
#   UserPurposesController で current_user.user_purposes を使うために必要。
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
  has_many :habits,             dependent: :destroy
  has_many :habit_records,      dependent: :destroy
  has_many :weekly_reflections, dependent: :destroy

  # has_many :tasks（C-1 追加）
  # 【理由】
  #   1人のユーザーは複数のタスクを持てる（1対多の関係）。
  #   TasksController の index / create で current_user.tasks を呼ぶため必要。
  #   DashboardsController でも current_user.tasks.active.not_archived.today を使う。
  #
  # dependent: :destroy:
  #   ユーザーが削除されたとき、そのユーザーの全タスクも削除する。
  #   schema.rb で add_foreign_key "tasks", "users", on_delete: :cascade と
  #   定義されているが、Rails 側にも書くことでコードを読む人への意図が明確になる。
  #
  #   DB側 cascade（SQLレベル）と Rails側 dependent: :destroy の違い:
  #     cascade             → Rails コールバック（before_destroy など）は走らない
  #     dependent: :destroy → Rails コールバックが走る（将来の拡張に対応できる）
  has_many :tasks, dependent: :destroy

  # has_one :user_setting（B-3 追加）
  # 【理由】
  #   Habit#on_rest_mode? が user.user_setting&.rest_mode_active? を呼ぶため、
  #   User モデルから user_setting にアクセスできる必要がある。
  #   1人のユーザーに1つの設定レコード（UNIQUE制約あり）のため has_one を使う。
  has_one :user_setting

  # has_many :user_purposes（D-1 追加）
  # 【理由】
  #   1人のユーザーは複数の PMVV 目標を持てる（バージョン管理のため）。
  #   ユーザーが目標を更新するたびに新しいレコードを作成し、
  #   過去のバージョンを履歴として保持するため has_many が必要。
  #   UserPurposesController の new / create / edit / update で
  #   current_user.user_purposes を使用する。
  #
  # dependent: :destroy:
  #   ユーザーが削除されたとき、PMVV 記録も全て削除する。
  #   schema.rb の add_foreign_key "user_purposes", "users", on_delete: :cascade と対応。
  has_many :user_purposes, dependent: :destroy

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