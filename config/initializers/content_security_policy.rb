# config/initializers/content_security_policy.rb
#
# ============================================================
# F-1 追加: Google OAuth2 のための CSP 設定更新
# ============================================================
#
# 【変更内容】
#   form_action に Google の認証エンドポイントを追加する。
#
# 【なぜ form_action の設定が必要なのか】
#   OmniAuth は button_to（フォーム POST）で認証を開始する。
#   CSP の form-action ディレクティブは「このフォームの送信先（action属性）
#   として許可するURL」を制御する。
#
#   form_action を設定しない場合、デフォルトは default_src の設定に従う。
#   :self のみでは外部URL（accounts.google.com）へのフォーム送信が
#   ブロックされてしまう。
#
#   → form_action に :self と Google 認証 URL のドメインを追加する。

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none
  policy.script_src  :self, :https, :unsafe_inline
  policy.style_src   :self, :https, :unsafe_inline

  # ── F-1 追加: フォーム送信先の許可設定 ──────────────────────────────────
  #
  # form_action:
  #   フォームの action 属性として許可する送信先を制限する CSP ディレクティブ。
  #
  # :self:
  #   同じオリジン（自アプリ）へのフォーム送信を許可する。
  #   通常のフォーム（ログイン・習慣登録等）のため必須。
  #
  # "https://accounts.google.com":
  #   Google OAuth2 の認証開始エンドポイント。
  #   OmniAuth が /auth/google_oauth2 への POST 後、
  #   内部で Google 認証 URL へリダイレクトする際に必要。
  policy.form_action :self, "https://accounts.google.com"
end

Rails.application.config.content_security_policy_nonce_generator =
  ->(_request) { SecureRandom.base64(16) }

Rails.application.config.content_security_policy_nonce_directives = []