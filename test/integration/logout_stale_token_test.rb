# test/integration/logout_stale_token_test.rb
#
# ==============================================================================
# 古い画面からのログアウト（CSRF トークンの不一致）の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 正しいトークンなら、今までどおりログアウトできる
#   ② 古いトークンでも、まだログインしていれば
#      ログアウトせずに元の画面へ戻り、「もう一度押してください」と表示される
#   ③ 戻り先は自分のサイトだけ（外部サイトの Referer ならダッシュボードへ）
#   ④ すでにログアウトしている場合は、通常のログアウト後と同じトップページへ
#   ⑤ ログアウト以外（ログインの送信）は、今までどおり 422 の画面になる
#
# 【CSRF の検証を、このテストの中だけ有効にする理由】
#   config/environments/test.rb で allow_forgery_protection = false になっており、
#   ふつうのテストではトークンを確かめない（ほかのテストでトークンを用意しなくて済むように）。
#   このテストは「トークンが合わないとき」を確かめたいので、setup で true にして、
#   teardown で必ず元に戻す（ほかのテストに影響させない）。
#
# 【「古いトークン」の作り方】
#   実際には「ほかのウィンドウでログインし直して、セッションが作り直された」ときに起きる。
#   サーバーから見ると「今のセッションと合わない値が届いた」ことと同じなので、
#   適当な文字列（"stale-token"）を送って再現する。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/logout_stale_token_test.rb
# ==============================================================================
require "test_helper"

class LogoutStaleTokenTest < ActionDispatch::IntegrationTest
  STALE_TOKEN = "stale-token".freeze

  setup do
    @user = users(:one)

    # ログインは CSRF の検証を有効にする前に行う
    # （log_in_as はトークンを送らないため、有効にした後だと 422 になる）
    log_in_as(@user)

    # 元の値を覚えておき、teardown で必ず戻す
    @original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @original_forgery_protection
  end

  # ── テスト用のヘルパーメソッド ─────────────────────────────────────────

  # 表示中のページの <meta name="csrf-token"> から、今のセッションの正しいトークンを取り出す
  #   （ブラウザの button_to のフォームに入るトークンと同じ種類の値）
  def current_csrf_token
    css_select("meta[name='csrf-token']").first["content"]
  end

  # ログインが必要なページ（設定ページ）を開いて、ログイン中かどうかを返す
  #   設定ページはオンボーディング前でも表示されるため、fixture の状態に左右されない
  def logged_in_now?
    get settings_path
    response.successful?
  end

  # ── ① 正しいトークン ───────────────────────────────────────────────────
  test "正しいトークンなら、今までどおりログアウトできる" do
    get settings_path
    delete logout_path, params: { authenticity_token: current_csrf_token }

    assert_redirected_to root_path
    assert_equal "ログアウトしました", flash[:notice]
    assert_not logged_in_now?
  end

  # ── ② 古いトークン（まだログインしている） ────────────────────────────
  test "古いトークンでは、ログアウトせずに元の画面へ戻り、もう一度押す案内を表示する" do
    delete logout_path,
           params:  { authenticity_token: STALE_TOKEN },
           headers: { "HTTP_REFERER" => settings_url }

    # 303 で元の画面（設定ページ）に戻る
    assert_response :see_other
    assert_redirected_to settings_url
    assert_equal I18n.t("sessions.destroy.stale_page"), flash[:warning]

    # 戻った画面に案内が表示され、ログインしたままになっている
    follow_redirect!
    assert_response :success
    assert_select "[role='alert']", text: /#{Regexp.escape(I18n.t("sessions.destroy.stale_page"))}/
  end

  test "戻った画面の新しいトークンで、もう一度押すとログアウトできる" do
    delete logout_path,
           params:  { authenticity_token: STALE_TOKEN },
           headers: { "HTTP_REFERER" => settings_url }
    follow_redirect!

    # 描き直された画面のトークン（今のセッションのもの）で送り直す
    delete logout_path, params: { authenticity_token: current_csrf_token }

    assert_redirected_to root_path
    assert_not logged_in_now?
  end

  # ── ③ 戻り先は自分のサイトだけ ────────────────────────────────────────
  test "Referer が外部サイトや無い場合は、ダッシュボードに戻す" do
    delete logout_path,
           params:  { authenticity_token: STALE_TOKEN },
           headers: { "HTTP_REFERER" => "https://evil.example.com/phishing" }
    assert_redirected_to dashboard_path

    delete logout_path, params: { authenticity_token: STALE_TOKEN }
    assert_redirected_to dashboard_path
  end

  # ── ④ すでにログアウトしている ────────────────────────────────────────
  test "ほかのウィンドウですでにログアウトしていた場合は、通常のログアウト後と同じトップページへ" do
    # 「ほかのウィンドウ」でのログアウトを、正しいトークンで先に行う
    get settings_path
    delete logout_path, params: { authenticity_token: current_csrf_token }

    # 古い画面からのログアウト
    delete logout_path,
           params:  { authenticity_token: STALE_TOKEN },
           headers: { "HTTP_REFERER" => settings_url }

    assert_redirected_to root_path
    assert_equal "ログアウトしました", flash[:notice]
  end

  # ── ⑤ ログアウト以外は今までどおり ────────────────────────────────────
  test "ログインの送信でトークンが古い場合は、今までどおり 422 の画面になる" do
    post login_path, params: {
      authenticity_token: STALE_TOKEN,
      session: { email: @user.email, password: "password" }
    }

    assert_response :unprocessable_entity
  end
end
