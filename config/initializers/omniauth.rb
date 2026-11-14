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

# ============================================================
# 本番のコールバック URL のホストを固定する（CVE-2026-63183 対応）
# ============================================================
#
# 【何を防ぐのか】
#   OmniAuth は、Google / LINE に渡す「ログイン後に戻ってくる URL（コールバック URL）」を、
#   何も設定しないとリクエストの Host / X-Forwarded-Host ヘッダーから組み立てる。
#   ヘッダーを偽装されると、この URL を別のホストに書き換えられるおそれがある。
#   full_host を指定すると、ヘッダーではなく、ここで決めたホストだけを使うようになる。
#
# 【APP_HOST を使う理由】
#   production.rb のメール内 URL と同じ環境変数を使い、ホストの設定を1か所にそろえる。
#   未設定でも現在の本番 URL（habitflow-web.onrender.com）になるので、起動は失敗しない。
#   Google Cloud Console / LINE Developers に登録しているコールバック URL と同じホストのため、
#   ログインの動きは変わらない。
#
# 【本番だけにする理由】
#   開発（http://localhost:3000）とテスト（www.example.com）は、
#   それぞれのホストのまま動かす必要があるため。
if Rails.env.production?
  OmniAuth.config.full_host = "https://#{ENV.fetch('APP_HOST', 'habitflow-web.onrender.com')}"
end