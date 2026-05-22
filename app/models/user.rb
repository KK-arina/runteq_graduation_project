# app/models/user.rb
#
# ==============================================================================
# User（ユーザー）モデル
# ==============================================================================
#
# 【B-3 での変更内容】has_one :user_setting を追加。
# 【C-1 での変更内容】has_many :tasks を追加。
# 【D-1 での変更内容】has_many :user_purposes を追加。
#
# 【F-1 での変更内容】
#   1. has_secure_password に validations: false を追加。
#      Google ログインユーザーはパスワードを持たないため、
#      デフォルトの「パスワード必須」バリデーションを無効化して
#      独自バリデーション（email_provider? 条件付き）で制御する。
#
#   2. from_omniauth クラスメソッドを追加。
#      Google OAuth2 の認証情報を元に User を検索または新規作成する。
#
#   3. email バリデーションに allow_nil: true を追加。
#      LINE ログインではメールアドレスが取得できない場合があるため。
#
#   4. password バリデーションに if: :email_provider? 条件を追加。
#      Google ログインユーザーにはパスワードバリデーションを適用しない。
#
# 【F-2 での変更内容】
#   from_omniauth クラスメソッドを LINE にも対応するよう拡張する。
#   LINE はメールアドレスを返さない（email が nil になる）ため、
#   メールによるマージ処理を条件付きにする。
#
#   LINE の auth ハッシュ構造:
#     {
#       "provider" => "line",
#       "uid"      => "U1234567890abcdef",  # LINE の一意ユーザー ID
#       "info"     => {
#         "name"  => "山田太郎",
#         "image" => "https://profile.line.me/..."
#         # email は原則含まれない（特権スコープで別途申請が必要）
#       }
#     }
#
# 【provider の値について】
#   OmniAuth Google OAuth2 gem は auth["provider"] に "google_oauth2" を返す。
#   OmniAuth LINE gem は auth["provider"] に "line" を返す。
#   この値をそのまま DB に保存することで:
#     ① find_by(provider: auth["provider"]) と保存値が一致してバグが起きない
#     ② provider の変換ルールが不要でシンプル
#
# ==============================================================================
class User < ApplicationRecord
  # ============================================================
  # 認証関連
  # ============================================================
  #
  # has_secure_password validations: false:
  #   password / password_digest / authenticate メソッドを提供する Rails の機能。
  #   デフォルトでは「パスワードは必須」バリデーションが自動で付くが、
  #   validations: false でそれを無効化する。
  #
  # 【なぜ validations: false にするのか】
  #   Google / LINE ログインユーザーは password_digest が NULL でも正常なユーザー。
  #   デフォルトのバリデーションがあると OAuth ユーザーの create! が失敗してしまう。
  has_secure_password validations: false

  # ============================================================
  # アソシエーション
  # ============================================================
  has_many :habits,             dependent: :destroy
  has_many :habit_records,      dependent: :destroy
  has_many :weekly_reflections, dependent: :destroy
  has_many :tasks,              dependent: :destroy
  has_one  :user_setting
  has_many :user_purposes,      dependent: :destroy

  # ============================================================
  # バリデーション
  # ============================================================
  validates :name, presence: true, length: { maximum: 50 }

  # email バリデーション
  #
  # 【allow_nil: true について】
  #   LINE ログインではメールアドレスが取得できない場合がある。
  #   nil の場合は全バリデーションをスキップする。
  #   これにより「nil は許可（LINE用）」「空文字は不許可」という挙動になる。
  validates :email,
            presence:   true,
            length:     { maximum: 255 },
            uniqueness: { case_sensitive: false },
            format:     { with: URI::MailTo::EMAIL_REGEXP },
            allow_nil:  true

  # password バリデーション
  #
  # 【if: lambda の意味】
  #   provider が "email" または nil（メール登録ユーザー）の場合のみ
  #   パスワードのバリデーションを実行する。
  #   Google / LINE ユーザーにはパスワードバリデーションを適用しない。
  validates :password,
            presence:  true,
            length:    { minimum: 8 },
            if:        ->(u) { u.provider.blank? || u.provider == "email" }
  validates :password, confirmation: true, if: ->(u) { u.provider.blank? || u.provider == "email" }
  validates :password_confirmation,
            presence:  true,
            if:        ->(u) { (u.provider.blank? || u.provider == "email") && u.password.present? }

  # ============================================================
  # コールバック
  # ============================================================
  before_save :downcase_email

  # after_create :create_user_setting
  #
  # 【役割】
  #   ユーザー新規作成時に UserSetting レコードを自動作成する。
  #   Google / LINE ログインで新規ユーザーが作成された場合も同様に実行される。
  after_create :create_user_setting

  # ============================================================
  # クラスメソッド（F-1 追加、F-2 拡張）
  # ============================================================

  # from_omniauth
  #
  # 【役割】
  #   OAuth 認証完了後に OmniAuth から渡される認証情報（auth ハッシュ）を元に、
  #   既存ユーザーを検索、または新規ユーザーを作成して返す。
  #   Google OAuth2（F-1）と LINE Login（F-2）の両方に対応する。
  #
  # 【3段階の処理フロー】
  #   ① provider + uid で完全一致のユーザーを検索（2回目以降のログイン）
  #   ② 見つからない場合、同じメールの既存ユーザーを検索してマージ（初回 Google ログイン時）
  #      ※ LINE はメールを返さないため、② は email が存在する場合のみ実行する
  #   ③ それも見つからない場合、新規ユーザーを作成
  #
  # 【Google と LINE の auth ハッシュの違い】
  #   Google: provider="google_oauth2", email あり, name あり
  #   LINE:   provider="line",          email なし（原則）, name あり
  #
  def self.from_omniauth(auth)
    # ── ① provider + uid で既存ユーザーを検索する ──────────────────────────
    #
    # auth["provider"] は "google_oauth2" または "line"。
    # この値をそのまま保存・検索することで一致が保証される。
    user = find_by(provider: auth["provider"], uid: auth["uid"])
    return user if user.present?

    # ── ② メールアドレスで既存ユーザーを検索してマージする ─────────────────
    email = auth.dig("info", "email")&.downcase

    if email.present?
      existing_user = find_by(email: email)

      if existing_user
        # ── 既存メールアカウントに OAuth 情報を紐付ける（マージ）──
        #
        # 【なぜ update_columns を使うのか】
        #   update! を使うと email の uniqueness バリデーションが実行され
        #   バリデーションエラーが発生するリスクがある。
        #   update_columns はバリデーションをスキップして指定カラムのみ直接更新するため安全。
        #
        # 【updated_at を明示的に更新する理由】
        #   update_columns はデフォルトで updated_at を更新しない。
        #   将来のログ分析・監査で「いつ OAuth マージされたか」を追跡できるよう
        #   明示的に Time.current を設定する。
        existing_user.update_columns(
          provider:   auth["provider"],
          uid:        auth["uid"],
          updated_at: Time.current
        )
        return existing_user
      end
    end

    # ── ③ 完全な新規ユーザーを作成する ────────────────────────────────────
    #
    # 【LINE の uid について】
    #   LINE Login (OpenID Connect) の uid は auth["uid"] に入る「sub」値。
    #   ※ sub は LINE のユーザー識別子で、形式は固定されていない文字列。
    #   ※ Messaging API の userId（U から始まる）とは別物。混同しないこと。
    #
    #   users.uid     = LINE Login の sub（OmniAuth ログイン識別子）← 今回設定
    #   users.line_user_id = Messaging API 通知用 userId ← 今回は触らない
    #
    # 【LINE ユーザーの email について】
    #   LINE はメールアドレスを返さないため email は nil になる。
    #   email バリデーションに allow_nil: true を設定済みのため問題ない。
    create!(
      provider: auth["provider"],
      uid:      auth["uid"],
      name:     auth.dig("info", "name").presence || fallback_name_for(auth["provider"]),
      email:    email   # LINE の場合は nil になる（許容済み）
    )
  end

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

  # email_provider?（F-1 追加）
  #
  # 【役割】
  #   メールとパスワードで登録したユーザーかどうかを判定する。
  #   password バリデーションの if 条件として使用する。
  #
  # 【判定ロジック】
  #   provider が "email" または nil（古いユーザーで未設定）→ true（パスワード必須）
  #   provider が "google_oauth2" / "line" 等 → false（パスワード不要）
  def email_provider?
    provider.blank? || provider == "email"
  end

  # fallback_name_for（F-2 追加）
  #
  # 【役割】
  #   OAuth プロバイダから名前が取得できなかった場合のフォールバック名を返す。
  #   from_omniauth の create! 内で使用する。
  #
  # 【なぜプロバイダ別にフォールバック名を分けるのか】
  #   "Google User" / "LINE User" と区別することで、
  #   管理画面等で登録元プロバイダが分かりやすくなる。
  def self.fallback_name_for(provider)
    case provider
    when "google_oauth2" then "Google User"
    when "line_v2_1"     then "LINE User"
    else                      "SNS User"
    end
  end

  def create_user_setting
    UserSetting.create!(user: self)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[User#create_user_setting] UserSetting 作成失敗: #{e.message}"
  end

  def downcase_email
    self.email = email.to_s.downcase if email.present?
  end
end