# config/initializers/omniauth.rb

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV.fetch("GOOGLE_CLIENT_ID", nil),
           ENV.fetch("GOOGLE_CLIENT_SECRET", nil),
           scope:    "email,profile",
           skip_jwt: false,
           prompt:   "select_account"

  # ============================================================
  # F-2 追加: LINE Login プロバイダの設定
  # ============================================================
  #
  # 【重要】ストラテジーファイルのパスが
  #   omniauth/strategies/line_v2_1.rb のため、
  #   プロバイダ名は :line_v2_1（数字の間もアンダースコア）となる。
  #
  #   NG: provider :line      → OmniAuth::Strategies::Line が存在しない
  #   NG: provider :line_v21  → OmniAuth::Strategies::LineV21 が存在しない
  #   OK: provider :line_v2_1 → OmniAuth::Strategies::LineV21 を正しく読み込む
  #
  # 【コールバック URL】
  #   /auth/line_v2_1/callback になる。
  #   routes.rb と LINE Developers Console も合わせて修正する。
  provider :line_v2_1,
           ENV.fetch("LINE_CHANNEL_ID", nil),
           ENV.fetch("LINE_CHANNEL_SECRET", nil),
           scope: "profile openid"
end

OmniAuth.config.on_failure = proc do |env|
  error_type = env["omniauth.error.type"]

  if error_type == :access_denied
    Rack::Response.new([], 302, "Location" => "/login").finish
  else
    Rack::Response.new([], 302, "Location" => "/login?omniauth_error=true").finish
  end
end