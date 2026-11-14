# test/integration/remember_login_settings_test.rb
#
# ==============================================================================
# ログイン保持: 設定画面の操作と、無効化（パスワードリセット・退会）の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 設定画面にログイン保持セクションが表示される
#   ② 「この端末でログインを保持する」「この端末のログイン保持をやめる」が動く
#   ③ 「すべての端末からログアウトする」で、ほかの端末のログイン保持とセッションが無効になり、
#      操作した端末はログインしたまま使える
#   ④ パスワードリセットで、すべての端末のログイン保持とセッションが無効になる
#   ⑤ 退会で、すべての端末のログイン保持とセッションが無効になる
#
# 【「ほかの端末」の再現方法】
#   open_session で、Cookie を別々に持つテスト用ブラウザをもう1つ作る。
#   このテストのメインのブラウザを「端末A」、open_session で作ったものを「端末B」とする。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/remember_login_settings_test.rb
# ==============================================================================
require "test_helper"

class RememberLoginSettingsTest < ActionDispatch::IntegrationTest
  REMEMBER_COOKIE = "_habitflow_remember".freeze
  SESSION_COOKIE  = "_habitflow_session".freeze

  setup do
    @user = users(:one)
  end

  # ── テスト用のヘルパーメソッド ─────────────────────────────────────────

  # 端末B（別の Cookie を持つテスト用ブラウザ）で「ログインしたままにする」付きでログインする
  #
  # 【open_session とは】
  #   統合テストの中で、もう1つ独立したブラウザのようなものを作るメソッド。
  #   返ってきたオブジェクトに get / post などを送ると、そのブラウザの Cookie で通信する。
  def open_remembered_device(user)
    device = open_session
    device.post login_path, params: {
      session: { email: user.email, password: "password", remember_me: "1" }
    }
    device
  end

  # 指定した端末で「ログインが必要なページ」を開き、ログイン画面に飛ばされたかを返す
  def redirected_to_login?(device)
    device.get dashboard_path
    device.response.redirect? && device.response.location.include?("/login")
  end

  # ── ① 表示 ──────────────────────────────────────────────────────────────
  test "設定画面にログイン保持セクションが表示され、最初は保持していない状態になっている" do
    log_in_as(@user)

    get settings_path

    assert_response :success
    assert_select "[data-testid='remember-login-section']"
    assert_select "[data-testid='remember-this-device-off']"
    assert_select "form[action='#{remember_device_settings_path}']"
  end

  # ── ② この端末のオン / オフ ─────────────────────────────────────────────
  test "「この端末でログインを保持する」でトークンを発行し、表示が保持中になる" do
    log_in_as(@user)

    assert_difference -> { @user.remember_tokens.count }, 1 do
      post remember_device_settings_path
    end
    assert_redirected_to settings_path
    assert cookies[REMEMBER_COOKIE].present?

    follow_redirect!
    assert_select "[data-testid='remember-this-device-on']"
    assert_select "form[action='#{forget_device_settings_path}']"
  end

  test "すでに保持中の端末で押しても、トークンは増えない" do
    log_in_as(@user)
    post remember_device_settings_path

    assert_no_difference -> { @user.remember_tokens.count } do
      post remember_device_settings_path
    end
    assert_equal I18n.t("remember_login.flash.already_enabled"), flash[:notice]
  end

  test "「この端末のログイン保持をやめる」でトークンを削除し、ブラウザ再起動後はログイン画面になる" do
    log_in_as(@user)
    post remember_device_settings_path

    delete forget_device_settings_path

    assert_redirected_to settings_path
    assert_equal 0, @user.remember_tokens.count
    assert cookies[REMEMBER_COOKIE].blank?

    # 今のログインは続いている
    get settings_path
    assert_response :success

    # ブラウザを閉じたら（セッション Cookie が消えたら）ログインが必要になる
    cookies.delete(SESSION_COOKIE)
    get dashboard_path
    assert_redirected_to %r{/login}
  end

  test "この端末のログイン保持をやめても、ほかの端末のログイン保持は残る" do
    device_b = open_remembered_device(@user)

    log_in_as(@user)
    post remember_device_settings_path
    assert_equal 2, @user.remember_tokens.count

    delete forget_device_settings_path

    assert_equal 1, @user.remember_tokens.count
    # 端末Bはブラウザ再起動後も自動ログインできる
    device_b.cookies.delete(SESSION_COOKIE)
    assert_not redirected_to_login?(device_b)
  end

  # ── ③ すべての端末からログアウト ────────────────────────────────────────
  test "「すべての端末からログアウトする」で、ほかの端末のセッションとログイン保持が無効になる" do
    device_b = open_remembered_device(@user)
    assert_not redirected_to_login?(device_b), "端末Bはログインできている"

    log_in_as(@user)
    before_version = @user.reload.auth_version

    delete revoke_all_devices_settings_path

    assert_redirected_to settings_path
    assert_equal 0, @user.remember_tokens.count
    assert_equal before_version + 1, @user.reload.auth_version

    # 端末B: ブラウザを閉じていなくても、次のアクセスでログアウトされる
    assert redirected_to_login?(device_b)

    # 端末A（操作した端末）: ログインしたまま使える
    get settings_path
    assert_response :success
  end

  test "「すべての端末からログアウトする」は、操作した端末のログイン保持も解除する" do
    log_in_as(@user)
    post remember_device_settings_path

    delete revoke_all_devices_settings_path

    assert cookies[REMEMBER_COOKIE].blank?
    cookies.delete(SESSION_COOKIE)
    get dashboard_path
    assert_redirected_to %r{/login}
  end

  test "「すべての端末からログアウトする」は、ほかのユーザーのログイン保持を消さない" do
    other_device = open_remembered_device(users(:two))

    log_in_as(@user)
    delete revoke_all_devices_settings_path

    assert_equal 1, users(:two).remember_tokens.count
    assert_not redirected_to_login?(other_device)
  end

  # ── ④ パスワードリセット ───────────────────────────────────────────────
  test "パスワードリセットで、すべての端末のログイン保持とセッションが無効になる" do
    device_b = open_remembered_device(@user)
    before_version = @user.reload.auth_version

    # 端末A（未ログイン）でパスワードリセットを完了する
    raw_token = PasswordResetToken.generate_token_for(@user)
    patch password_reset_path(raw_token), params: {
      password_reset: { password: "newpassword123", password_confirmation: "newpassword123" }
    }
    assert_redirected_to login_path

    assert_equal 0, @user.remember_tokens.count
    assert_equal before_version + 1, @user.reload.auth_version

    # 端末B: ログインしていたセッションも、ログイン保持も使えない
    assert redirected_to_login?(device_b)
    device_b.cookies.delete(SESSION_COOKIE)
    assert redirected_to_login?(device_b)
  end

  test "パスワードリセットに失敗したときは、ログイン保持を解除しない" do
    device_b = open_remembered_device(@user)

    raw_token = PasswordResetToken.generate_token_for(@user)
    patch password_reset_path(raw_token), params: {
      password_reset: { password: "short", password_confirmation: "short" }
    }
    assert_response :unprocessable_entity

    # トランザクションごと取り消されるので、トークンは残り、端末Bも使える
    assert_equal 1, @user.remember_tokens.count
    assert_not redirected_to_login?(device_b)
  end

  # ── ⑤ 退会 ──────────────────────────────────────────────────────────────
  test "退会で、すべての端末のログイン保持とセッションが無効になり、Cookie も削除される" do
    device_b = open_remembered_device(@user)

    log_in_as(@user)
    post remember_device_settings_path

    delete settings_path

    assert_redirected_to root_path
    assert_equal 0, RememberToken.where(user_id: @user.id).count
    assert cookies[REMEMBER_COOKIE].blank?

    # 端末B: セッションもログイン保持も使えない
    assert redirected_to_login?(device_b)
    device_b.cookies.delete(SESSION_COOKIE)
    assert redirected_to_login?(device_b)
  end

  test "UserDestroyService は RememberToken を削除し、auth_version を1つ進める" do
    RememberToken.issue_for!(@user)
    before_version = @user.reload.auth_version

    result = UserDestroyService.new(user: @user).call

    assert result[:success], result[:error]
    assert_equal 0, RememberToken.where(user_id: @user.id).count
    assert_equal before_version + 1, @user.reload.auth_version
  end
end