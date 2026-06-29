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
#   2. from_omniauth クラスメソッドを追加。
#   3. email バリデーションに allow_nil: true を追加。
#   4. password バリデーションに if: :email_provider? 条件を追加。
#
# 【F-2 での変更内容】
#   from_omniauth クラスメソッドを LINE にも対応するよう拡張。
#
# 【F-3 での変更内容】
#   1. terms_agreed バリデーション（:acceptance）を追加。
#      allow_nil: true で OAuth ユーザーの create! には影響しない。
#   2. before_save :set_terms_agreed_at を追加。
#      同意チェック時に terms_agreed_at へ現在時刻を記録する。
#
# 【provider の値について】
#   OmniAuth Google OAuth2 gem は auth["provider"] に "google_oauth2" を返す。
#   OmniAuth LINE gem は auth["provider"] に "line" を返す。
#
# ==============================================================================
class User < ApplicationRecord
  # ============================================================
  # 認証関連
  # ============================================================
  #
  # has_secure_password validations: false:
  #   password / password_digest / authenticate メソッドを提供する Rails の機能。
  #   validations: false でデフォルトの「パスワード必須」バリデーションを無効化する。
  #   Google / LINE ログインユーザーは password_digest が NULL でも正常なユーザー。
  has_secure_password validations: false

  # ============================================================
  # F-3 追加: 利用規約同意用の仮想属性
  # ============================================================
  #
  # 【なぜ attr_accessor が必要なのか】
  #   terms_agreed は DB に存在しないカラムで、フォームのチェックボックスの
  #   値（"1" または "0"）を一時的に保持するだけの仮想属性。
  #   attr_accessor がないと「undefined method `terms_agreed'」エラーになる。
  #
  # 【acceptance バリデーションだけでは不十分な理由】
  #   Rails の :acceptance バリデーションは attr_accessor を自動生成しない。
  #   明示的に attr_accessor を定義する必要がある。
  attr_accessor :terms_agreed

  # ============================================================
  # アソシエーション
  # ============================================================
  #
  # 【F-6 B案: 統計データ保持設計】
  #
  # habits / tasks / weekly_reflections / user_purposes に
  # dependent: :destroy を設定しない理由:
  #   退会時は UserDestroyService による「論理削除 + 個人情報匿名化」を使用する。
  #   User レコードは物理削除しないため、紐付く活動データは
  #   「退会済みユーザー」に紐付いた匿名統計データとして保持される。
  #   これにより将来の習慣継続率分析・AI精度向上に活用できる。
  #
  # ⚠️ 重要: user.destroy は直接呼ばないこと
  #   dependent を外したため、User を物理削除すると外部キー制約違反
  #   （PG::ForeignKeyViolation）が発生する。
  #   退会処理は必ず UserDestroyService 経由で行うこと。
  #   before_destroy で物理削除を明示的にガードしている。
  has_many :habits
  has_many :habit_records,      dependent: :destroy  # habit経由で削除されるが念のため
  has_many :weekly_reflections
  has_many :tasks
  has_one  :user_setting
  has_many :user_purposes
  # H-8 追加: パーソナライズAIプロファイル（1ユーザー1プロファイル）
  # dependent: :destroy → ユーザーが退会時にプロファイルも削除される
  has_one :ai_user_profile, dependent: :destroy

  # ============================================================
  # F-6 追加: 論理削除スコープ
  # ============================================================
  #
  # scope :active: 退会していない（deleted_at が NULL の）ユーザーのみを返す
  #
  # 【使用例】
  #   User.active.find_by(email: "xxx") → 退会済みユーザーを誤取得しない
  #   ログイン処理・OmniAuth コールバックで必ず使うこと
  scope :active, -> { where(deleted_at: nil) }

  # ============================================================
  # バリデーション
  # ============================================================
  validates :name, presence: true, length: { maximum: 50 }

  # email バリデーション
  #
  # 【F-6 での変更: uniqueness の conditions を追加】
  #   DB レベルの部分インデックス（deleted_at IS NULL のみ対象）と
  #   Rails バリデーション側を完全に一致させるために
  #   conditions: -> { where(deleted_at: nil) } を使用する。
  #
  # 【なぜ scope: :deleted_at ではなく conditions を使うのか】
  #   scope: :deleted_at だと「deleted_at が同じ秒単位の値」のレコード間でしか
  #   チェックしないため、複数ユーザーが同時退会した場合に衝突する危険がある。
  #   conditions: で WHERE deleted_at IS NULL を指定する方が
  #   DB の部分インデックスと意味が完全に一致し、安全かつ正確。
  validates :email,
            presence:   true,
            length:     { maximum: 255 },
            uniqueness: {
              case_sensitive: false,
              conditions:     -> { where(deleted_at: nil) }
            },
            format:     { with: URI::MailTo::EMAIL_REGEXP },
            allow_nil:  true

  # ============================================================
  # password バリデーション（G-6 修正: on: :create を追加）
  # ============================================================
  #
  # 【なぜ on: :create を追加するのか】
  #   on: :create がない場合、update(:name) や update(line_user_id: nil) など
  #   password と無関係なカラムを更新する際にも presence バリデーションが走る。
  #   provider="email" のユーザーは password 仮想属性が空なため
  #   update が常に失敗してしまう問題が発生する。
  #
  #   on: :create にすることで:
  #     新規登録時: presence + length を検証する（従来通り）
  #     更新時:     password が入力された場合のみ length を検証する
  #
  # 【allow_nil: true + on: :update の意味】
  #   パスワード変更フォームを送信したとき（password が present? の場合）のみ
  #   8文字以上かどうかをチェックする。
  #   password が nil（未入力）の場合はスキップする（名前変更等の際に影響しない）。
  validates :password,
            presence: true,
            length:   { minimum: 8 },
            if:       ->(u) { u.provider.blank? || u.provider == "email" },
            on:       :create
  validates :password,
            length:    { minimum: 8 },
            allow_nil: true,
            if:        ->(u) { u.provider.blank? || u.provider == "email" },
            on:        :update
  validates :password, confirmation: true, if: ->(u) { u.provider.blank? || u.provider == "email" }
  validates :password_confirmation,
            presence: true,
            if:       ->(u) { (u.provider.blank? || u.provider == "email") && u.password.present? }

  # ============================================================
  # F-3 追加: 利用規約同意バリデーション
  # ============================================================
  #
  # 【:acceptance バリデーションとは】
  #   チェックボックスの「同意」が必須であることを検証する Rails 組み込みバリデーション。
  #   フォームから terms_agreed="1" が送られてくれば valid になる。
  #   "0" や "" は falsy として扱われ、バリデーションに失敗する。
  #
  # 【if: :email_provider? を使う理由（allow_nil: true より安全）】
  #   allow_nil: true にすると terms_agreed=nil でも通ってしまう。
  #   Strong Parameters 漏れやフォーム変更時に未同意登録を許してしまう危険がある。
  #   email_provider? で「メール登録ユーザーのみ必須」とすることで、
  #   OAuth ユーザーの create!（terms_agreed を渡さない）は自然にスキップされる。
  #   既存の email_provider? メソッドを再利用できるため保守性も高い。
  validates :terms_agreed,
            acceptance: true,
            if:         :email_provider?

  # ============================================================
  # コールバック
  # ============================================================
  before_save :downcase_email

  # F-3 追加: メール登録時のみ、同意チェックが入っていれば terms_agreed_at を記録する
  #
  # 【before_validation を使う理由】
  #   before_save だとプロフィール更新など全保存で毎回走る。
  #   before_validation にすることで「バリデーション前」に処理が入り、
  #   不要な保存時に走らせずに済む。
  #
  # 【if 条件を付ける理由】
  #   email_provider? のユーザーのみ（メール登録）に限定する。
  #   OAuth ユーザーは /terms_agreement ページで update_column で直接記録する。
  before_validation :set_terms_agreed_at, if: :email_provider?

  # ============================================================
  # F-6 追加: 物理削除ガード
  # ============================================================
  #
  # before_destroy :prevent_physical_destroy
  #
  # 【なぜこのガードが必要なのか】
  #   dependent: :destroy を外したことで、もし誰かが誤って
  #   user.destroy や User.destroy_all を呼ぶと、
  #   外部キー制約違反（PG::ForeignKeyViolation）が発生するか、
  #   関連する habits/tasks 等が孤児データになってしまう。
  #   このコールバックで物理削除を完全に禁止し、
  #   退会は必ず UserDestroyService 経由であることを強制する。
  before_destroy :prevent_physical_destroy

  after_create :create_user_setting

  # ============================================================
  # クラスメソッド（F-1 追加、F-2 拡張）
  # ============================================================

  # from_omniauth
  #
  # 【役割】
  #   OAuth 認証完了後に OmniAuth から渡される認証情報（auth ハッシュ）を元に、
  #   既存ユーザーを検索、または新規ユーザーを作成して返す。
  #
  # 【F-3 の影響】
  #   terms_agreed を渡さないため nil になる。
  #   allow_nil: true のバリデーション設定により create! は問題なく通過する。
  #   OAuth ユーザーの terms_agreed_at は /terms_agreement ページで記録する。
  def self.from_omniauth(auth)
    # ── ① provider + uid で既存ユーザーを検索する ──────────────────────────
    user = find_by(provider: auth["provider"], uid: auth["uid"])
    return user if user.present?

    # ── ② メールアドレスで既存ユーザーを検索してマージする ─────────────────
    email = auth.dig("info", "email")&.downcase

    if email.present?
      existing_user = find_by(email: email)

      if existing_user
        # 既存メールアカウントに OAuth 情報を紐付ける（マージ）
        #
        # 【update_columns を使う理由】
        #   バリデーションをスキップして指定カラムのみ直接更新する。
        existing_user.update_columns(
          provider:   auth["provider"],
          uid:        auth["uid"],
          updated_at: Time.current
        )
        return existing_user
      end
    end

    # ── ③ 完全な新規ユーザーを作成する ────────────────────────────────────
    create!(
      provider: auth["provider"],
      uid:      auth["uid"],
      name:     auth.dig("info", "name").presence || fallback_name_for(auth["provider"]),
      email:    email   # LINE の場合は nil になる（許容済み）
      # terms_agreed は渡さない → nil → allow_nil: true でパス
      # terms_agreed_at は /terms_agreement ページで別途記録する
    )
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # line_connected?（G-6 追加）
  #
  # 【役割】
  #   ユーザーがLINEと連携しているかどうかを返す。
  #
  # 【なぜ2つの条件を OR で組み合わせるのか】
  #   LINEとの連携には2つのパターンがある:
  #     1. LINEログイン: provider="line_v2_1" かつ uid=LINE_UID で認証している場合。
  #        → OmniauthCallbacksController#line で自動的に line_user_id も保存される設計だが、
  #          将来の変更やエッジケースに備えて provider 側も確認する。
  #     2. LINE通知のみ連携: provider は別（email/google等）だが
  #        line_user_id だけが保存されている場合。
  #        → 将来的に「メールログインユーザーがLINE通知だけ連携する」機能を追加したときに対応できる。
  #   どちらの場合も「LINE連携済み」と判定して正しい表示にするため OR で組み合わせる。
  def line_connected?
    provider == "line_v2_1" || line_user_id.present?
  end

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

  # terms_agreed_at?（F-3 追加）
  #
  # 【役割】
  #   ユーザーが利用規約に同意済みかどうかを返す。
  #   terms_agreed_at が NULL でない = 同意済み。
  #
  # 【使用場所】
  #   OAuthコントローラーで初回ログイン後の同意チェックに使用する。
  def terms_agreed?
    terms_agreed_at.present?
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # email_provider?（F-1 追加）
  #
  # 【役割】
  #   メールとパスワードで登録したユーザーかどうかを判定する。
  def email_provider?
    provider.blank? || provider == "email"
  end

  # fallback_name_for（F-2 追加）
  #
  # 【役割】
  #   OAuth プロバイダから名前が取得できなかった場合のフォールバック名を返す。
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

  # prevent_physical_destroy（F-6 追加）
  #
  # 【役割】
  #   本番・開発環境で User レコードの物理削除を禁止する。
  #
  # 【なぜテスト環境を除外するのか】
  #   既存テストの teardown メソッドで @user.destroy が呼ばれる場合があり、
  #   テスト環境でガードをかけると既存テスト全てが壊れる。
  #   テストデータの削除はフレームワークに委ねるため test 環境は除外する。
  def prevent_physical_destroy
    return if Rails.env.test?

    raise ActiveRecord::ReadOnlyRecord,
          "[User#prevent_physical_destroy] User の物理削除は禁止されています。" \
          "退会処理は UserDestroyService 経由で行ってください。 user_id=#{id}"
  end

  # set_terms_agreed_at（F-3 追加）
  #
  # 【役割】
  #   before_validation コールバックとして呼ばれる。
  #   terms_agreed が真値（"1" または true）であり、
  #   かつ terms_agreed_at がまだ未設定の場合にのみ現在時刻を記録する。
  #
  # 【なぜ terms_agreed_at.blank? を条件にするのか】
  #   プロフィール更新など2回目以降の保存で、最初に同意した日時を
  #   上書きしないように保護するため。
  #
  # 【ActiveModel::Type::Boolean.new.cast について】
  #   フォームから来る "1"（文字列）を true（bool）に確実に変換する。
  #   "1" → true / "0" → false / nil → nil のように変換される。
  def set_terms_agreed_at
    agreed = ActiveModel::Type::Boolean.new.cast(terms_agreed)
    if agreed && terms_agreed_at.blank?
      self.terms_agreed_at = Time.current
    end
  end
end