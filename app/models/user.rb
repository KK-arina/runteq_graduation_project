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

  # after_create :create_user_setting（D-4 追加）
  # 【理由】
  #   ユーザー登録時に UserSetting レコードを自動作成する。
  #   UserSetting がない場合、WeeklyReflectionAnalysisJob 等の
  #   AI分析ジョブが月次上限チェックで early return してしまい、
  #   ジョブがエンキューされない問題が発生する。
  #
  # 【なぜ after_create か】
  #   before_create の時点では user.id がまだ存在しない。
  #   after_create 時点で id が確定するため、UserSetting の
  #   user_id 外部キーに正しく設定できる。
  after_create :create_user_setting

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

  # create_user_setting
  # 【役割】
  #   ユーザー新規作成時に UserSetting レコードをデフォルト値で自動作成する。
  #   schema.rb のデフォルト値が適用されるため引数は user のみで十分。
  #
  # 【rescue している理由】
  #   UserSetting 作成失敗でユーザー登録自体をロールバックさせないため。
  #   ログを残すことでデバッグ可能にする。
  def create_user_setting
    UserSetting.create!(user: self)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[User#create_user_setting] UserSetting 作成失敗: #{e.message}"
  end

  def downcase_email
    self.email = email.to_s.downcase
  end
end