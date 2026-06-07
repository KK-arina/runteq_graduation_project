# test/controllers/settings_controller_g6_test.rb
#
# ==============================================================================
# SettingsController G-6 テスト
# ==============================================================================
#
# 【なぜ既存ファイルではなく新規ファイルを作るのか】
#   既存の settings_controller_test.rb を上書きすると
#   G-5 以前のテストが消える危険がある。
#   G-6 専用のテストファイルに分けることで安全に追加できる。
# ==============================================================================
require "test_helper"

class SettingsControllerG6Test < ActionDispatch::IntegrationTest

  setup do
    # テスト用ユーザーを fixture から取得する
    @user = users(:one)

    # log_in_as を使う理由:
    #   test_helper.rb で定義済みのログインヘルパー。
    #   既存テストと同じ方法でログインすることで
    #   セッションの仕組みが変わっても追従できる。
    #   直接 post login_path を使うとパスワードの fixture 値に依存してしまい
    #   fixture が変わるとテストが落ちる。
    log_in_as(@user)

    # user_setting が存在しない場合に備えて確実に生成する
    # find_or_create_by! を使う理由:
    #   テスト環境では after_create コールバックが実行されない場合があるため
    #   明示的に生成して nil エラーを防ぐ。
    @user_setting = UserSetting.find_or_create_by!(user: @user)
  end

  # ============================================================
  # show アクションのテスト
  # ============================================================

  test "設定ページにアクセスできる" do
    get settings_path
    assert_response :success
  end

  test "設定ページに AIコスト使用状況のプログレスバーが表示される" do
    get settings_path
    assert_response :success
    # role="progressbar" 属性を持つ要素が存在することを確認する
    assert_select "[role='progressbar']"
  end

  test "設定ページにタイムゾーン設定のセレクトボックスが表示される" do
    get settings_path
    assert_response :success
    # name="time_zone" の select 要素が存在することを確認する
    assert_select "select[name='time_zone']"
  end

  test "設定ページにプロフィール編集ボタンが表示される" do
    get settings_path
    assert_response :success
    # data-action に settings-profile#openEdit が含まれる要素が存在することを確認する
    assert_select "[data-action*='settings-profile#openEdit']"
  end

  test "設定ページに音声入力ボタンが表示される" do
    get settings_path
    assert_response :success
    # data-action に voice-input#toggle が含まれる要素が存在することを確認する
    assert_select "[data-action*='voice-input#toggle']"
  end

  # ============================================================
  # update_profile アクションのテスト
  # ============================================================

  test "ユーザー名を正常に更新できる" do
    # scope: :user でネストされたパラメータを送る
    # ビューの form_with scope: :user と一致させる
    patch update_profile_settings_path,
          params: { user: { name: "新しい名前テスト" } }

    assert_redirected_to settings_path

    # DB上のユーザー名が更新されていることを確認する
    # reload: DBから最新の値を取得する（キャッシュを使わない）
    assert_equal "新しい名前テスト", @user.reload.name
  end

  test "ログイン状態で設定ページにアクセスできる（ログイン確認）" do
    get settings_path
    assert_response :success, "ログインできていません: #{response.location}"
  end

  test "空のユーザー名では更新できない" do
    original_name = @user.name

    patch update_profile_settings_path,
          params: { user: { name: "" } }

    # バリデーションエラーで設定ページにリダイレクトされる
    assert_redirected_to settings_path

    # DB上のユーザー名が変わっていないことを確認する
    assert_equal original_name, @user.reload.name
  end

  test "50文字超のユーザー名では更新できない" do
    long_name = "あ" * 51
    original_name = @user.name

    patch update_profile_settings_path,
          params: { user: { name: long_name } }

    assert_redirected_to settings_path
    assert_equal original_name, @user.reload.name
  end

  # ============================================================
  # update_timezone アクションのテスト
  # ============================================================

  test "有効なタイムゾーン（Tokyo）に更新できる" do
    patch update_timezone_settings_path,
          params: { time_zone: "Tokyo" }

    assert_redirected_to settings_path
    # user_setting のタイムゾーンが更新されていることを確認する
    assert_equal "Tokyo", @user_setting.reload.time_zone
  end

  test "有効なタイムゾーン（Hawaii）に更新できる" do
    patch update_timezone_settings_path,
          params: { time_zone: "Hawaii" }

    assert_redirected_to settings_path
    assert_equal "Hawaii", @user_setting.reload.time_zone
  end

  test "無効なタイムゾーンでは更新できない" do
    original_tz = @user_setting.time_zone

    patch update_timezone_settings_path,
          params: { time_zone: "InvalidTimezone/DoesNotExist" }

    assert_redirected_to settings_path

    # タイムゾーンが変わっていないことを確認する
    assert_equal original_tz, @user_setting.reload.time_zone

    # flash[:alert] に無効タイムゾーンのメッセージが入っていることを確認する
    assert_equal I18n.t("settings.update_timezone.invalid"), flash[:alert]
  end

  # ============================================================
  # disconnect_line アクションのテスト
  # ============================================================

  test "LINE通知連携を解除できる（providerがemail・line_user_idあり）" do
    # LINE通知のみ連携している状態を作る
    # provider は "email"（または "google_oauth2"）のままで
    # line_user_id だけ設定する
    @user.update_columns(
      line_user_id: "U1234567890abcdef",
      provider: "email"
    )
    @user.reload  # ← これを追加

    delete disconnect_line_settings_path

    assert_redirected_to settings_path
    # line_user_id が nil になっていることを確認する
    assert_nil @user.reload.line_user_id
  end

  test "LINEログインユーザーは連携解除できない" do
    # LINEログインユーザーの状態を作る
    @user.update_columns(
      provider: "line_v2_1",
      uid: "U1234567890abcdef",
      line_user_id: "U1234567890abcdef"
    )

    delete disconnect_line_settings_path

    assert_redirected_to settings_path

    # line_user_id が nil になっていないことを確認する（解除されていない）
    assert_not_nil @user.reload.line_user_id

    # エラーメッセージが表示されることを確認する
    assert_equal I18n.t("settings.disconnect_line.login_user_error"), flash[:alert]
  end

  test "LINE未連携の状態で解除しても正常に動作する" do
    @user.update_column(:line_user_id, nil)

    delete disconnect_line_settings_path

    # エラーにならずリダイレクトされる
    assert_redirected_to settings_path
    assert_nil @user.reload.line_user_id
  end

end
