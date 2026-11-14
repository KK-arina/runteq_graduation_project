# test/integration/remember_login_email_test.rb
#
# ==============================================================================
# ログイン保持（メール／パスワードログイン）の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① チェックありでログイン → セッションが切れても自動でログインされる
#   ② チェックなしでログイン → セッションが切れたらログイン画面になる
#   ③ 改ざんした Cookie・期限切れトークン・退会済みユーザーでは自動ログインしない
#   ④ 使うたびに期限が延びる
#   ⑤ ログアウトでこの端末のログイン保持が無効になる
#   ⑥ Cookie の属性（httponly / samesite、セッション Cookie に期限がないこと）
#
# 【「ブラウザを閉じた」状態の再現方法】
#   cookies.delete("_habitflow_session") でセッション Cookie だけを消す。
#   セッション Cookie は期限なし（ブラウザを閉じると消える）なので、
#   これがブラウザを閉じて開き直したときと同じ状態になる。
#   ログイン保持の Cookie（_habitflow_remember）は期限付きなので残る。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/remember_login_email_test.rb
# ==============================================================================
require "test_helper"

class RememberLoginEmailTest < ActionDispatch::IntegrationTest
  # Cookie 名（concerns/remember_login.rb・config/application.rb と同じ名前）
  REMEMBER_COOKIE = "_habitflow_remember".freeze
  SESSION_COOKIE  = "_habitflow_session".freeze

  setup do
    @user = users(:one)
  end

  # ── テスト用のヘルパーメソッド ─────────────────────────────────────────

  # チェックボックスの値を指定してメールログインする
  #   remember_me: "1" ならチェックあり、"0" ならチェックなし
  def log_in_with_remember(user, remember_me:)
    post login_path, params: {
      session: { email: user.email, password: "password", remember_me: remember_me }
    }
  end

  # ブラウザを閉じて開き直した状態を作る（セッション Cookie だけを消す）
  def simulate_browser_restart
    cookies.delete(SESSION_COOKIE)
  end

  # レスポンスの Set-Cookie ヘッダーから、指定した Cookie の行を取り出す
  #   Rails 8 / Rack 3 では複数の Cookie が配列または改行区切りで返るため、両方に対応する。
  def set_cookie_line_for(name)
    Array(response.headers["set-cookie"]).join("\n").split("\n")
                                         .find { |line| line.start_with?("#{name}=") }
  end

  # ── ① チェックあり ─────────────────────────────────────────────────────
  test "チェックありでログインするとトークンを発行し、ブラウザ再起動後も自動でログインされる" do
    assert_difference -> { @user.remember_tokens.count }, 1 do
      log_in_with_remember(@user, remember_me: "1")
    end
    assert cookies[REMEMBER_COOKIE].present?, "ログイン保持の Cookie が保存されるべき"

    simulate_browser_restart

    # ログインが必要なページを開いても、ログイン画面に飛ばされない
    get dashboard_path
    assert_response :success
  end

  test "自動ログインのあとは、通知リンクなどで開いたページがそのまま表示される" do
    log_in_with_remember(@user, remember_me: "1")
    simulate_browser_restart

    # require_login で /login?redirect_to=... に飛ばされず、目的のページが表示される
    get habits_path
    assert_response :success
  end

  test "ログイン保持中に /login を開くとダッシュボードへ移動する" do
    log_in_with_remember(@user, remember_me: "1")
    simulate_browser_restart

    get login_path
    assert_redirected_to dashboard_path
  end

  # ── ② チェックなし ─────────────────────────────────────────────────────
  test "チェックなしでログインするとトークンを発行せず、ブラウザ再起動後はログイン画面になる" do
    assert_no_difference -> { RememberToken.count } do
      log_in_with_remember(@user, remember_me: "0")
    end
    assert cookies[REMEMBER_COOKIE].blank?

    simulate_browser_restart

    get dashboard_path
    assert_redirected_to %r{/login}
  end

  test "チェックありで保持中でも、チェックなしで再ログインすると古いトークンを削除する" do
    log_in_with_remember(@user, remember_me: "1")
    assert_equal 1, @user.remember_tokens.count

    log_in_with_remember(@user, remember_me: "0")

    assert_equal 0, @user.remember_tokens.count
    assert cookies[REMEMBER_COOKIE].blank?
  end

  # ── ③ 自動ログインしてはいけないケース ─────────────────────────────────
  test "改ざんした Cookie では自動ログインせず、その Cookie を削除する" do
    cookies[REMEMBER_COOKIE] = "tampered-value"

    get dashboard_path

    assert_redirected_to %r{/login}
    assert cookies[REMEMBER_COOKIE].blank?, "使えない Cookie は削除されるべき"
  end

  test "30日間使わなかったトークンでは自動ログインしない" do
    log_in_with_remember(@user, remember_me: "1")
    simulate_browser_restart

    # travel_to: テストの中だけ現在時刻を31日後に進める
    travel_to 31.days.from_now do
      get dashboard_path
      assert_redirected_to %r{/login}
    end
  end

  test "退会済みユーザーのトークンでは自動ログインせず、トークンを削除する" do
    log_in_with_remember(@user, remember_me: "1")
    simulate_browser_restart

    # 退会した状態を作る（UserDestroyService を通さず deleted_at だけを入れる）
    @user.update_columns(deleted_at: Time.current)

    get dashboard_path

    assert_redirected_to %r{/login}
    assert_equal 0, RememberToken.where(user_id: @user.id).count
  end

  # ── ④ 使うたびに期限が延びる ───────────────────────────────────────────
  test "使うたびに期限が延びるので、最初のログインから30日を超えても使い続けられる" do
    log_in_with_remember(@user, remember_me: "1")

    # 20日後に使う → ここから30日後まで延長される
    travel_to 20.days.from_now do
      simulate_browser_restart
      get dashboard_path
      assert_response :success
    end

    # 最初のログインから40日後（前回の利用から20日後）でも、まだ自動ログインできる
    travel_to 40.days.from_now do
      simulate_browser_restart
      get dashboard_path
      assert_response :success
    end
  end

  # ── ⑤ ログアウト ────────────────────────────────────────────────────────
  test "ログアウトするとこの端末のトークンを削除し、再起動後も自動ログインしない" do
    log_in_with_remember(@user, remember_me: "1")

    delete logout_path

    assert_equal 0, @user.remember_tokens.count
    assert cookies[REMEMBER_COOKIE].blank?

    simulate_browser_restart
    get dashboard_path
    assert_redirected_to %r{/login}
  end

  # ── ⑥ Cookie の属性 ─────────────────────────────────────────────────────
  test "ログイン保持の Cookie は httponly と samesite=lax が付き、セッション Cookie には期限がない" do
    log_in_with_remember(@user, remember_me: "1")

    remember_line = set_cookie_line_for(REMEMBER_COOKIE)
    session_line  = set_cookie_line_for(SESSION_COOKIE)

    assert_not_nil remember_line, "ログイン保持の Cookie が発行されるべき"
    assert_match(/httponly/i, remember_line)
    assert_match(/samesite=lax/i, remember_line)
    assert_match(/expires=/i, remember_line, "ログイン保持の Cookie には期限が必要")

    # セッション Cookie は期限なし（ブラウザを閉じると消える）
    assert_not_nil session_line
    assert_no_match(/expires=/i, session_line)
  end

  # ── 新規登録 ────────────────────────────────────────────────────────────
  test "新規登録ではトークンを発行しない" do
    assert_no_difference -> { RememberToken.count } do
      post users_path, params: {
        user: {
          name:                  "保持テスト",
          email:                 "remember_signup@example.com",
          password:              "password123",
          password_confirmation: "password123",
          terms_agreed:          "1"
        }
      }
    end
    assert_redirected_to dashboard_path
  end
end