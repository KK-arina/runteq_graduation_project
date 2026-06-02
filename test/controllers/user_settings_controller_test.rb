# test/controllers/user_settings_controller_test.rb
#
# ==============================================================================
# UserSettingsControllerTest（G-3 新規作成・修正済み）
# ==============================================================================
#
# 【修正内容】
#   ① 未ログイン PATCH のリダイレクト先: update_notification_settings_settings_path
#      の URL は /settings/notification_settings と同じなので
#      redirect_to パラメータも notification_settings_settings_path と一致する
#   ② LINE 連携ボタン確認: form[action] ではなく response.body の文字列で確認する
#      （button_to の action はフル URL になるため assert_select が効かない）
# ==============================================================================
require "test_helper"

class UserSettingsControllerTest < ActionDispatch::IntegrationTest

  setup do
    @user = users(:one)
    @user_setting = @user.user_setting ||
                    UserSetting.find_or_create_by!(user: @user)
  end

  # ===========================================================================
  # テスト1: 未ログイン状態でのアクセス制限
  # ===========================================================================

  test "未ログイン状態で通知設定ページにアクセスするとログインページへリダイレクトされる" do
    get notification_settings_settings_path

    assert_redirected_to login_path(redirect_to: notification_settings_settings_path)
  end

  test "未ログイン状態で PATCH を送るとログインページへリダイレクトされる" do
    patch update_notification_settings_settings_path,
          params: { user_setting: { notification_enabled: "1" } }

    # PATCH の URL（/settings/notification_settings）は GET と同じなので
    # redirect_to パラメータも notification_settings_settings_path と一致する
    assert_redirected_to login_path(redirect_to: notification_settings_settings_path)
  end

  # ===========================================================================
  # テスト2: ログイン済みでの通知設定ページ表示（GET）
  # ===========================================================================

  test "ログイン済みで通知設定ページが表示される" do
    log_in_as(@user)
    get notification_settings_settings_path
    assert_response :success
  end

  test "通知設定ページに4つのトグルスイッチとスライダーが表示される" do
    log_in_as(@user)
    get notification_settings_settings_path

    assert_select "input[name='user_setting[notification_enabled]']"
    assert_select "input[name='user_setting[line_notification_enabled]']"
    assert_select "input[name='user_setting[email_notification_enabled]']"
    assert_select "input[name='user_setting[weekly_report_enabled]']"
    assert_select "input[type='range'][name='user_setting[daily_notification_limit]']"
  end

  # ===========================================================================
  # テスト3: 通知設定の保存（PATCH）
  # ===========================================================================

  test "通知設定を保存するとフラッシュメッセージが表示される" do
    log_in_as(@user)

    patch update_notification_settings_settings_path,
          params: {
            user_setting: {
              notification_enabled:        "1",
              line_notification_enabled:   "0",
              email_notification_enabled:  "1",
              weekly_report_enabled:       "1",
              daily_notification_limit:    "5"
            }
          }

    # format.html は 303 redirect になる（Turbo でない通常リクエスト）
    assert_redirected_to notification_settings_settings_path
    follow_redirect!
    assert_match "通知設定を保存しました", response.body
  end

  test "通知設定が DB に正しく保存される" do
    log_in_as(@user)

    patch update_notification_settings_settings_path,
          params: {
            user_setting: {
              notification_enabled:       "1",
              email_notification_enabled: "1",
              weekly_report_enabled:      "0",
              daily_notification_limit:   "3"
            }
          }

    @user_setting.reload
    assert_equal true,  @user_setting.notification_enabled
    assert_equal true,  @user_setting.email_notification_enabled
    assert_equal false, @user_setting.weekly_report_enabled
    assert_equal 3,     @user_setting.daily_notification_limit
  end

  # ===========================================================================
  # テスト4: LINE 未連携時の表示
  # ===========================================================================

  test "LINE 未連携の場合に連携ボタンが表示され LINE 通知トグルが disabled になる" do
    @user.update_column(:line_user_id, nil)
    log_in_as(@user)

    get notification_settings_settings_path

    # LINE 連携ボタンのテキストが表示されていることを確認する
    # button_to の action はフル URL になるため response.body で文字列確認する
    assert_match "LINE でログイン・連携する", response.body

    # LINE 通知トグルが disabled になっている
    assert_select "input[name='user_setting[line_notification_enabled]'][disabled]"
  end

  # ===========================================================================
  # テスト5: LINE 連携済み時の表示
  # ===========================================================================

  test "LINE 連携済みの場合に連携済みと表示される" do
    @user.update_column(:line_user_id, "U123456789abcdef")
    log_in_as(@user)

    get notification_settings_settings_path

    assert_match "連携済み", response.body
    assert_select "input[name='user_setting[line_notification_enabled]']:not([disabled])"
  end
end