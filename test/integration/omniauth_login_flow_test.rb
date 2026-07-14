# test/integration/omniauth_login_flow_test.rb
#
# ==============================================================================
# OmniAuth ログインフロー統合テスト（I-1）
# ==============================================================================
#
# 【このテストの役割】
#   Google / LINE の OAuth コールバック（/auth/:provider/callback）を叩いたときに
#   ① ユーザーが作成/取得され ② ログイン状態になり ③ 正しい画面へ遷移する
#   という一連の流れ（統合フロー）を検証する。
#   ※ User.from_omniauth のモデル単体挙動は user_test.rb でカバー済みのため、
#     ここでは「コントローラー〜セッション〜リダイレクト」を担保する。
#
# 【OmniAuth をテストで動かす仕組み】
#   OmniAuth.config.test_mode = true にすると、実際の外部通信をせず
#   あらかじめ用意した「モック認証情報(mock_auth)」を使えるようになる。
#   さらに統合テストのリクエスト env は Rails.application.env_config を土台に
#   組み立てられるため、そこへ "omniauth.auth" を積んでおくと、
#   コントローラーの request.env["omniauth.auth"] でモック情報を受け取れる。
# ==============================================================================
require "test_helper"

class OmniauthLoginFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    # 【重要】テスト間の汚染を防ぐため、モック・テストモード・env を必ず元に戻す。
    #   これを忘れると後続テストが意図せず OmniAuth モックを引き継いでしまう。
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:line_v2_1]     = nil
    OmniAuth.config.test_mode = false
    Rails.application.env_config.delete("omniauth.auth")
  end

  # コールバックが読む request.env["omniauth.auth"] にモック認証情報を載せるヘルパー
  #
  # 【引数】
  #   provider : :google_oauth2 / :line_v2_1
  #   info:      { email:, name: } など OmniAuth の info ハッシュ
  #   uid:       プロバイダ側のユーザー識別子（デフォルトはランダム）
  def stub_omniauth(provider, info: {}, uid: "uid_#{SecureRandom.hex(6)}")
    auth = OmniAuth::AuthHash.new(provider: provider.to_s, uid: uid, info: info)
    OmniAuth.config.mock_auth[provider] = auth
    # 統合テストのリクエスト env にモック auth を載せる（コントローラーがここから読む）
    Rails.application.env_config["omniauth.auth"] = auth
    auth
  end

  # ============================================================
  # Google
  # ============================================================

  test "Google初回ログイン: 新規ユーザーを作成し、未同意なので利用規約同意ページへ遷移する" do
    auth = stub_omniauth(:google_oauth2,
                         info: { email: "new_g_#{SecureRandom.hex(4)}@example.com",
                                 name:  "グーグル太郎" })

    # コールバックを叩くとユーザーが1人作られる
    assert_difference "User.count", 1 do
      get "/auth/google_oauth2/callback"
    end

    user = User.find_by(provider: "google_oauth2", uid: auth.uid)
    assert_not_nil user,          "Google ユーザーが作成される"
    assert_equal "グーグル太郎", user.name

    # 新規ユーザーは terms_agreed_at が nil のため、まず利用規約同意ページへ誘導される
    assert_redirected_to terms_agreement_path

    # 【ログイン状態の確認】遷移先(要ログイン)を実際に開けることでセッション確立を検証する
    follow_redirect!
    assert_response :success
  end

  test "Google再ログイン: 既存(同意済み・オンボ済み)ユーザーはダッシュボードへ遷移する" do
    existing = User.create!(
      name:            "既存グーグル",
      provider:        "google_oauth2",
      uid:             "g_existing_#{SecureRandom.hex(4)}",
      email:           "existing_g_#{SecureRandom.hex(4)}@example.com",
      terms_agreed_at: Time.current,   # 同意済み
      first_login_at:  1.month.ago     # オンボーディング完了済み
    )
    stub_omniauth(:google_oauth2, uid: existing.uid,
                  info: { email: existing.email, name: existing.name })

    # 既存ユーザーなので新規作成は起きない
    assert_no_difference "User.count" do
      get "/auth/google_oauth2/callback"
    end

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
  end

  # ============================================================
  # LINE
  # ============================================================

  test "LINE初回ログイン: メールなしで新規作成し line_user_id を保存、同意ページへ遷移する" do
    # LINE はメールアドレスを返さない（info に email を入れない）
    auth = stub_omniauth(:line_v2_1, info: { name: "ライン花子" })

    assert_difference "User.count", 1 do
      get "/auth/line_v2_1/callback"
    end

    user = User.find_by(provider: "line_v2_1", uid: auth.uid)
    assert_not_nil user
    assert_equal "ライン花子", user.name
    assert_nil   user.email, "LINEはメールを返さないため email は nil"
    # LINE Login の uid（= Messaging API の userId）が line_user_id として保存される
    assert_equal auth.uid, user.line_user_id

    assert_redirected_to terms_agreement_path
    follow_redirect!
    assert_response :success
  end

  test "LINEで名前が空のときはフォールバック名『LINE User』になる" do
    auth = stub_omniauth(:line_v2_1, info: { name: nil })

    get "/auth/line_v2_1/callback"

    user = User.find_by(provider: "line_v2_1", uid: auth.uid)
    assert_equal "LINE User", user.name
  end

  # ============================================================
  # 失敗系
  # ============================================================

  test "認証失敗(/auth/failure)はログインページへ戻す" do
    get "/auth/failure", params: { message: "invalid_credentials" }
    assert_redirected_to login_path(omniauth_error: true)
  end
end