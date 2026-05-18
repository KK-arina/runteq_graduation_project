# config/initializers/omniauth.rb
#
# ==============================================================================
# F-1: OmniAuth Google OAuth2 設定ファイル
# ==============================================================================
#
# 【このファイルの役割】
#   アプリ起動時に OmniAuth ミドルウェアを Rails に組み込む。
#   Google OAuth2 の認証フローに必要な設定をここで一元管理する。
#
# 【OmniAuth の認証フローの概要】
#   1. ユーザーが「Googleでログイン」ボタンをクリック
#      → POST /auth/google_oauth2 がリクエストされる
#   2. OmniAuth が Google の認証ページへリダイレクトする
#   3. ユーザーが Google でログインを許可する
#   4. Google がコールバック URL へリダイレクトする
#      → GET /auth/google_oauth2/callback
#   5. OmniauthCallbacksController#google が呼び出される
#   6. request.env['omniauth.auth'] に認証情報が入っている
#
# 【ENV.fetch の使い方】
#   ENV.fetch("GOOGLE_CLIENT_ID", nil)
#   → 環境変数 GOOGLE_CLIENT_ID が設定されていればその値を返す
#   → 設定されていなければ nil を返す（アプリは起動できる）
#
# 【nil を許容する理由】
#   - 開発環境で Google Cloud Console 設定前でもアプリが起動できる
#   - 環境変数が未設定の場合は Google 認証を使わない運用も可能
#   - nil の場合は Google 認証ボタンを非表示にすることで対応する
#
# ==============================================================================

Rails.application.config.middleware.use OmniAuth::Builder do
  # ============================================================
  # Google OAuth2 プロバイダの設定
  # ============================================================
  #
  # 第1引数 :google_oauth2:
  #   使用するプロバイダ名。OmniAuth が内部で omniauth-google-oauth2 gem を呼ぶ。
  #   コールバックは /auth/google_oauth2/callback になる。
  #   users.provider カラムには "google_oauth2" が保存される。
  #   ※ Issue タスクでは 'google' と書いているが、実際の値は 'google_oauth2'
  #
  # 第2引数 ENV.fetch("GOOGLE_CLIENT_ID", nil):
  #   Google Cloud Console で発行した「クライアント ID」。
  #   環境変数 GOOGLE_CLIENT_ID から読み込む。
  #
  # 第3引数 ENV.fetch("GOOGLE_CLIENT_SECRET", nil):
  #   Google Cloud Console で発行した「クライアント シークレット」。
  #   環境変数 GOOGLE_CLIENT_SECRET から読み込む。
  #
  # scope:
  #   Google に要求する情報の範囲（スコープ）。
  #   "email"   → メールアドレスへのアクセス許可
  #   "profile" → 名前・プロフィール画像へのアクセス許可
  #   この2つは OmniAuth Google のデフォルトだが、明示的に書くことで意図を明確にする。
  #
  # skip_jwt:
  #   Google の ID トークン（JWT）の検証をスキップするかどうか。
  #   false = JWT 検証を行う（デフォルト・推奨）。
  #   本番環境では必ず false にしてセキュリティを確保する。
  #
  # prompt: "select_account":
  #   Google のアカウント選択画面を毎回表示する設定。
  #   複数の Google アカウントを持つユーザーがアカウントを選択できるようにする。
  #   これがないと前回ログインしたアカウントが自動選択されてしまう。
  provider :google_oauth2,
           ENV.fetch("GOOGLE_CLIENT_ID", nil),
           ENV.fetch("GOOGLE_CLIENT_SECRET", nil),
           scope:    "email,profile",
           skip_jwt: false,
           prompt:   "select_account"
end

# ============================================================
# OmniAuth のグローバル設定
# ============================================================
#
# 【on_failure の設定】
#   認証が失敗したとき（ユーザーがキャンセルした・エラーが起きた）に
#   どこへリダイレクトするかを設定する。
#
# 【env['omniauth.error.type'] とは】
#   OmniAuth が認証失敗時にセットするエラーの種類。
#   例: :access_denied（ユーザーがキャンセル）
#       :invalid_credentials（認証情報が無効）
#
# 【Rack::Response.new での redirect の仕組み】
#   Rack（Rails の下のレイヤー）で直接レスポンスを返す。
#   Rails のコントローラーを経由しない。
#   [302, { 'Location' => url }, []] の形式でリダイレクトを返す。
OmniAuth.config.on_failure = proc do |env|
  # エラー種類を取得する（:access_denied など）
  error_type = env["omniauth.error.type"]

  # ユーザーがキャンセルした場合は静かにログインページへ戻す
  # それ以外のエラーはアラートメッセージを付けてログインページへ
  if error_type == :access_denied
    Rack::Response.new(
      [],
      302,
      "Location" => "/login"
    ).finish
  else
    Rack::Response.new(
      [],
      302,
      "Location" => "/login?omniauth_error=true"
    ).finish
  end
end