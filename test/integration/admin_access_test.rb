# test/integration/admin_access_test.rb
#
# ==============================================================================
# 管理画面（/admin）の認可の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 未ログイン・一般ユーザー・ADMIN_EMAILS 未設定・退会済み・LINE ログインでは 404
#      （ログイン画面や同意ページへ移動せず、存在しない URL と同じ反応になる）
#   ② 管理者が手でログインした直後は開け、キャッシュ禁止・検索除外のヘッダーが付く
#   ③ 「ログインしたままにする」の自動ログインや、ログインから12時間を過ぎた状態では、
#      再ログインの案内（403）になる
#
# 【ENV を元に戻す理由】
#   ENV はテストの間で共有されるため、setup で元の値を控え、teardown で必ず戻す。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/admin_access_test.rb
# ==============================================================================
require "test_helper"

class AdminAccessTest < ActionDispatch::IntegrationTest
  # Cookie 名（concerns/remember_login.rb・config/application.rb と同じ名前）
  SESSION_COOKIE = "_habitflow_session".freeze

  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]

    # users(:one)（test1@example.com）を管理者、users(:two) を一般ユーザーとして使う
    @admin = users(:one)
    @other = users(:two)
    ENV["ADMIN_EMAILS"] = "test1@example.com"
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  # 「ログインしたままにする」にチェックしてメールでログインする
  def log_in_with_remember(user)
    post login_path, params: {
      session: { email: user.email, password: "password", remember_me: "1" }
    }
  end

  # ── ① 404 になるケース ─────────────────────────────────────────────
  test "未ログインでは 404 になり、ログイン画面へ移動しない" do
    get admin_root_path

    assert_response :not_found
  end

  test "一般ユーザーでは 404 になる" do
    log_in_as(@other)

    get admin_root_path

    assert_response :not_found
  end

  test "ADMIN_EMAILS が未設定なら、管理者のアドレスでも 404 になる" do
    ENV.delete("ADMIN_EMAILS")
    log_in_as(@admin)

    get admin_root_path

    assert_response :not_found
  end

  test "退会済みになったユーザーでは 404 になる" do
    log_in_as(@admin)
    # 退会した状態を作る（UserDestroyService を通さず deleted_at だけを入れる）
    @admin.update_columns(deleted_at: Time.current)

    get admin_root_path

    assert_response :not_found
  end

  test "同じメールで LINE ログインに切り替わったユーザーでは 404 になる" do
    log_in_as(@admin)
    # provider が line_v2_1 の状態を作る（LINE ログインは同じメールアドレスでも統合しなくなったが、provider で判定していることを確かめる）
    @admin.update_columns(provider: "line_v2_1")

    get admin_root_path

    assert_response :not_found
  end

  test "利用規約に未同意の一般ユーザーでも、同意ページではなく 404 になる" do
    log_in_as(@other)
    # ログインしたあとで未同意の状態にする（log_in_as は未同意なら同意済みにしてしまうため）
    @other.update_column(:terms_agreed_at, nil)

    get admin_root_path

    assert_response :not_found
  end

  test "404 は存在しない URL の 404 と同じ画面で、管理画面用のヘッダーは付かない" do
    log_in_as(@other)

    get "/this-page-does-not-exist"
    not_found_title = css_select("title").text

    get admin_root_path

    assert_response :not_found
    assert_equal not_found_title, css_select("title").text
    assert_nil response.headers["X-Robots-Tag"]
  end

  # ── ② 管理者が開けるケース ────────────────────────────────────────
  test "管理者が手でログインした直後は開け、キャッシュ禁止と検索除外が指定される" do
    log_in_as(@admin)

    get admin_root_path

    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "meta[name='robots'][content='noindex, nofollow']"
    assert_select "h1", I18n.t("admin.dashboards.show.title")
  end

  test "手でログインしてから11時間後でも開ける" do
    log_in_as(@admin)

    travel_to 11.hours.from_now do
      get admin_root_path
      assert_response :success
    end
  end

  # ── ③ 再ログインの案内になるケース ────────────────────────────────
  test "手でログインしてから12時間を過ぎると、再ログインの案内になる" do
    log_in_as(@admin)

    travel_to 13.hours.from_now do
      get admin_root_path

      assert_response :forbidden
      assert_select "h1", I18n.t("admin.reauth.title")
    end
  end

  test "ログインしたままにするの自動ログインでは、再ログインの案内になる" do
    log_in_with_remember(@admin)
    # ブラウザを閉じて開き直した状態にする（セッション Cookie だけを消す）
    cookies.delete(SESSION_COOKIE)

    get admin_root_path

    assert_response :forbidden
    assert_select "h1", I18n.t("admin.reauth.title")
    # 再ログインの案内にも、キャッシュ禁止と検索除外が付く
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    # ログアウトのボタン（DELETE /logout のフォーム）がある
    assert_select "form[action='#{logout_path}']"
  end
end
