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
#      将来の LINE ログインではメールアドレスが取得できない場合があるため。
#
#   4. password バリデーションに if: :email_provider? 条件を追加。
#      Google ログインユーザーにはパスワードバリデーションを適用しない。
#
# 【provider の値について】
#   OmniAuth Google OAuth2 gem は auth["provider"] に "google_oauth2" を返す。
#   この値をそのまま DB に保存することで:
#     ① find_by(provider: auth["provider"]) と保存値が一致してバグが起きない
#     ② 将来 LINE（"line"）等を追加しても変換ルールが不要でシンプル
#   タスク要件の「provider='google'」は「Google系プロバイダ」の意味として解釈する。
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
  #   Google ログインユーザーは password_digest が NULL でも正常なユーザー。
  #   デフォルトのバリデーションがあると Google ユーザーの create! が失敗してしまう。
  #   そのため自動バリデーションを切り、下部の独自バリデーションで
  #   「メールログインユーザーのみパスワードを必須」と制御する。
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
  # 【F-1 変更点: allow_nil: true を追加】
  #   Google ログインではメールアドレスは必ず取得できるため今回は実質影響なし。
  #   将来の LINE ログイン（メールなし）に備えて now_nil: true を付与しておく。
  #
  # 【presence: true と allow_nil: true の共存について】
  #   allow_nil: true を付けると nil の場合は全バリデーションをスキップする。
  #   presence: true は空文字（""）を弾くが nil はスキップされる。
  #   これにより「nil は許可（LINE用）」「空文字は不許可」という挙動になる。
  validates :email,
            presence:   true,
            length:     { maximum: 255 },
            uniqueness: { case_sensitive: false },
            format:     { with: URI::MailTo::EMAIL_REGEXP },
            allow_nil:  true

  # password バリデーション
  #
  # 【F-1 変更点: if: :email_provider? を追加】
  #   変更前: validates :password, length: { minimum: 8 }, allow_nil: true
  #   変更後: if: :email_provider? を追加して Google ユーザーには適用しない
  #
  # 【allow_nil: true の意味】
  #   パスワードが nil の場合はバリデーションをスキップ（変更なしとして扱う）。
  #   新規登録時に password が入力されていれば 8 文字以上を検証する。
  validates :password,
            length:    { minimum: 8 },
            allow_nil: true,
            if:        :email_provider?

  # ============================================================
  # コールバック
  # ============================================================
  before_save :downcase_email

  # after_create :create_user_setting（D-4 追加）
  #
  # 【役割】
  #   ユーザー新規作成時に UserSetting レコードを自動作成する。
  #   Google ログインで新規ユーザーが作成された場合も同様に実行される。
  after_create :create_user_setting

  # ============================================================
  # クラスメソッド（F-1 追加）
  # ============================================================

  # from_omniauth
  #
  # 【役割】
  #   Google 認証完了後に OmniAuth から渡される認証情報（auth ハッシュ）を元に、
  #   既存ユーザーを検索、または新規ユーザーを作成して返す。
  #
  # 【auth ハッシュの構造（Google OAuth2 gem が返す値）】
  #   {
  #     "provider" => "google_oauth2",           # gem のデフォルト値
  #     "uid"      => "100000000000000000000",   # Google の一意ユーザー ID（sub 値）
  #     "info"     => {
  #       "email" => "user@example.com",
  #       "name"  => "山田太郎"
  #     }
  #   }
  #
  # 【3段階の処理フロー】
  #   ① provider + uid で完全一致のユーザーを検索（2回目以降のログイン）
  #   ② 見つからない場合、同じメールの既存ユーザーを検索してマージ（初回 Google ログイン）
  #   ③ それも見つからない場合、新規ユーザーを作成
  #
  def self.from_omniauth(auth)
    # ── ① provider + uid で既存ユーザーを検索する ──────────────────────────
    #
    # auth["provider"] は "google_oauth2"（gem のデフォルト値）。
    # この値をそのまま保存・検索することで一致が保証される。
    # "google" に変換すると find_by の検索キーと保存値が食い違いバグの原因になる。
    user = find_by(provider: auth["provider"], uid: auth["uid"])
    return user if user.present?

    # ── ② メールアドレスで既存ユーザーを検索してマージする ─────────────────
    #
    # 【この処理が必要な理由（完了条件「重複しない」の実装）】
    #   "taro@example.com" でメール登録済みのユーザーが
    #   同じメールの Google アカウントで初めてログインする場合、
    #   ① の provider + uid では見つからない（初回のため）。
    #   しかしメールで見つかった場合は「同一人物」として
    #   既存アカウントに Google 情報を追加する（新規作成しない）。
    #
    # auth.dig("info", "email"):
    #   ネストしたハッシュを安全に掘り下げるメソッド。
    #   "info" キーや "email" キーが存在しない場合は nil を返す（例外なし）。
    #
    # &.downcase:
    #   Safe Navigation Operator（ぼっち演算子）。
    #   email が nil の場合 downcase を呼ばずに nil を返す。
    #   DB は before_save で小文字保存のため比較前に lowercase にする。
    email = auth.dig("info", "email")&.downcase
    existing_user = find_by(email: email) if email.present?

    if existing_user
      # ── 既存メールアカウントに Google 情報を紐付ける（マージ）──
      #
      # 【なぜ update_columns を使うのか】
      #   update! を使うと email の uniqueness バリデーションが実行される。
      #   このとき Rails は「自分自身のメールと重複している」と判定して
      #   バリデーションエラーが発生するリスクがある（同じメールを持つ自分自身との衝突）。
      #   update_columns はバリデーションをスキップして指定カラムのみ直接更新するため安全。
      #   provider と uid を上書きするだけで他のカラムには触れない。
      existing_user.update_columns(
        provider: auth["provider"],
        uid:      auth["uid"]
      )
      return existing_user
    end

    # ── ③ 完全な新規ユーザーを作成する ────────────────────────────────────
    #
    # create!:
    #   保存に失敗した場合 ActiveRecord::RecordInvalid 例外を発生させる。
    #   呼び出し元（OmniauthCallbacksController）で rescue して対応する。
    #
    # 【password: nil について】
    #   has_secure_password validations: false にしているため nil で保存できる。
    #   Google ユーザーはパスワードでログインしないため password_digest は NULL で正常。
    #   email_provider? が false を返すため password バリデーションも実行されない。
    create!(
      provider: auth["provider"],
      uid:      auth["uid"],
      name:     auth.dig("info", "name").presence || "Google User",
      email:    email
      # password を明示しない = nil = has_secure_password validations: false により OK
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
  #   provider が "google_oauth2" 等 → false（パスワード不要）
  #
  # 【なぜ nil も含めるのか】
  #   A-1 マイグレーション前から存在する古いユーザーレコードは
  #   provider が NULL の場合がある。
  #   これらはメールログインユーザーとして扱いパスワードを必須にする。
  def email_provider?
    provider.blank? || provider == "email"
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