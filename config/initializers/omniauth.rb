# config/initializers/omniauth.rb
#
# ==============================================================================
# F-1: OmniAuth Google OAuth2 設定ファイル
# F-2: OmniAuth LINE ログイン設定を追加
# ==============================================================================
#
# 【このファイルの役割】
#   アプリ起動時に OmniAuth ミドルウェアを Rails に組み込む。
#   Google OAuth2 と LINE Login の認証フローに必要な設定をここで一元管理する。
#
# 【OmniAuth の認証フローの概要】
#   1. ユーザーが「LINEでログイン」ボタンをクリック
#      → POST /auth/line_v21 がリクエストされる
#   2. OmniAuth が LINE の認証ページへリダイレクトする
#   3. ユーザーが LINE でログインを許可する
#   4. LINE が コールバック URL へリダイレクトする
#      → GET /auth/line_v21/callback
#   5. OmniauthCallbacksController#line アクションが呼び出される
#   6. request.env['omniauth.auth'] に認証情報が入っている
#
# 【ENV.fetch の使い方】
#   ENV.fetch("LINE_CHANNEL_ID", nil)
#   → 環境変数 LINE_CHANNEL_ID が設定されていればその値を返す
#   → 設定されていなければ nil を返す（アプリは起動できる）
#
# 【nil を許容する理由】
#   - 開発環境で LINE Developers Console 設定前でもアプリが起動できる
#   - 環境変数が未設定の場合は LINE 認証を使わない運用も可能
#   - nil の場合は LINE 認証ボタンを非表示にすることで対応する
#
# ==============================================================================

Rails.application.config.middleware.use OmniAuth::Builder do
  # ============================================================
  # Google OAuth2 プロバイダの設定（F-1 から継続）
  # ============================================================
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
  # 【重要】プロバイダ名は :line_v21（アンダースコア区切り）を使用する。
  #
  #   gem 名: omniauth-line-v2_1
  #   OmniAuth のストラテジークラス名: OmniAuth::Strategies::LineV21
  #   provider シンボル: :line_v21（OmniAuth が LineV21 を snake_case 変換した名前）
  #
  #   NG: provider :line      → OmniAuth::Strategies::Line を探してしまい
  #       「uninitialized constant OmniAuth::Strategies::Line」エラーになる
  #   OK: provider :line_v21  → OmniAuth::Strategies::LineV21 が正しく読み込まれる
  #
  # 【コールバック URL の変化】
  #   :line_v21 を使うと OmniAuth が自動生成するコールバック URL は
  #   /auth/line_v21/callback になる。
  #   routes.rb と LINE Developers Console のコールバック URL もこれに合わせる。
  #
  # 【users.provider カラムに保存される値】
  #   auth["provider"] には "line_v21" が入る。
  #   DB の provider カラムには "line_v21" が保存される。
  #
  # scope: "profile openid":
  #   "profile"  → 表示名・プロフィール画像へのアクセス許可（必須）
  #   "openid"   → OpenID Connect による uid（sub）取得に必須
  provider :line_v21,
           ENV.fetch("LINE_CHANNEL_ID", nil),
           ENV.fetch("LINE_CHANNEL_SECRET", nil),
           scope: "profile openid"
end

# ============================================================
# OmniAuth のグローバル設定
# ============================================================
OmniAuth.config.on_failure = proc do |env|
  error_type = env["omniauth.error.type"]

  if error_type == :access_denied
    Rack::Response.new([], 302, "Location" => "/login").finish
  else
    Rack::Response.new([], 302, "Location" => "/login?omniauth_error=true").finish
  end
end