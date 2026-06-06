# test/controllers/user_settings_rest_mode_test.rb
#
# ==============================================================================
# UserSettingsRestModeTest（G-4 修正版）
# ==============================================================================
#
# 【修正内容】
#   ① current_user_habit_with_rest_mode → create_habit_with_rest_mode にリネーム
#      理由: IntegrationTest では current_user メソッドは使えないため。
#            メソッド名が実態（@user を使う）と合っていなかったため修正。
#   ② Date.tomorrow → 1.day.from_now.to_date に変更
#      理由: タイムゾーン境界で稀に不安定になるため。
#   ③ measurement_type: :check_type を確認済み（enum定義と一致）
#      docker compose exec web bin/rails runner "puts Habit.measurement_types.inspect"
#      → {"check_type"=>0, "numeric_type"=>1} で :check_type が正しいことを確認。
# ==============================================================================
require "test_helper"

class UserSettingsRestModeTest < ActionDispatch::IntegrationTest

  setup do
    @user         = users(:one)
    @user_setting = @user.user_setting ||
                    UserSetting.find_or_create_by!(user: @user)
    @user_setting.update_columns(rest_mode_until: nil, rest_mode_reason: nil)
  end

  # ===========================================================================
  # テスト1: 未ログイン状態でのアクセス制限
  # ===========================================================================

  test "未ログイン状態でお休みモードページにアクセスするとログインページへリダイレクトされる" do
    get rest_mode_settings_path
    assert_redirected_to login_path(redirect_to: rest_mode_settings_path)
  end

  test "未ログイン状態で POST を送るとログインページへリダイレクトされる" do
    post start_rest_mode_settings_path,
         params: { user_setting: { rest_mode_until: 1.day.from_now.to_date.to_s } }
    assert_redirected_to login_path(redirect_to: rest_mode_settings_path)
  end

  test "未ログイン状態で DELETE を送るとログインページへリダイレクトされる" do
    delete stop_rest_mode_settings_path
    assert_redirected_to login_path(redirect_to: rest_mode_settings_path)
  end

  # ===========================================================================
  # テスト2: お休みモード設定ページの表示（GET）
  # ===========================================================================

  test "ログイン済みでお休みモード設定ページが表示される" do
    log_in_as(@user)
    get rest_mode_settings_path
    assert_response :success
  end

  test "お休みモード中でない場合は設定フォームが表示される" do
    log_in_as(@user)
    get rest_mode_settings_path
    assert_select "[data-testid='open-rest-mode-modal-btn']"
  end

  test "お休みモード中の場合は終了ボタンが表示される" do
    @user_setting.update_columns(rest_mode_until: 3.days.from_now)
    log_in_as(@user)
    get rest_mode_settings_path
    assert_select "[data-testid='rest-mode-active-section']"
  end

  # ===========================================================================
  # テスト3: お休みモードの開始（POST）
  # ===========================================================================

  test "正しい日付でお休みモードを開始できる" do
    log_in_as(@user)

    post start_rest_mode_settings_path,
         params: {
           user_setting: {
             rest_mode_until:  1.day.from_now.to_date.to_s,
             rest_mode_reason: "海外旅行"
           }
         }

    assert_redirected_to rest_mode_settings_path
    @user_setting.reload
    assert_not_nil @user_setting.rest_mode_until
    assert @user_setting.rest_mode_active?
    assert_equal "海外旅行", @user_setting.rest_mode_reason
  end

  test "理由なしでもお休みモードを開始できる" do
    log_in_as(@user)

    post start_rest_mode_settings_path,
         params: {
           user_setting: {
             rest_mode_until: 7.days.from_now.to_date.to_s
           }
         }

    assert_redirected_to rest_mode_settings_path
    @user_setting.reload
    assert @user_setting.rest_mode_active?
    # rest_mode_reason は nil または空文字のどちらでも許容する
    assert @user_setting.rest_mode_reason.blank?
  end

  test "終了日が空の場合はバリデーションエラーになる" do
    log_in_as(@user)

    post start_rest_mode_settings_path,
         params: { user_setting: { rest_mode_until: "" } }

    assert_response :unprocessable_entity
    @user_setting.reload
    assert_nil @user_setting.rest_mode_until
  end

  test "終了日が過去の日付の場合はバリデーションエラーになる" do
    log_in_as(@user)

    post start_rest_mode_settings_path,
         params: { user_setting: { rest_mode_until: 1.day.ago.to_date.to_s } }

    assert_response :unprocessable_entity
    @user_setting.reload
    assert_nil @user_setting.rest_mode_until
  end

  # ===========================================================================
  # テスト4: お休みモードの終了（DELETE）
  # ===========================================================================

  test "お休みモードを手動で終了できる" do
    @user_setting.update_columns(
      rest_mode_until:  3.days.from_now,
      rest_mode_reason: "テスト"
    )

    log_in_as(@user)
    delete stop_rest_mode_settings_path

    assert_redirected_to rest_mode_settings_path
    @user_setting.reload
    assert_nil @user_setting.rest_mode_until
    assert_nil @user_setting.rest_mode_reason
    assert_not @user_setting.rest_mode_active?
  end

  # ===========================================================================
  # テスト5: ダッシュボードのバナー表示
  # ===========================================================================

  test "お休みモード中にダッシュボードに休息中バナーが表示される" do
    # allow_rest_mode=true の習慣を作成する
    habit = create_habit_with_rest_mode(true)

    # お休みモードを設定する
    @user_setting.update_columns(rest_mode_until: 3.days.from_now)

    log_in_as(@user)
    get dashboard_path

    # バナーが表示されていること
    assert_select "*[data-testid=?]", "rest-mode-dashboard-banner"

    # allow_rest_mode=true の習慣に「😴 休息中」バッジが表示されていること
    assert_select "*[data-testid=?]", "rest-mode-habit-badge-#{habit.id}"
  end

  test "お休みモード中でない場合はダッシュボードにバナーが表示されない" do
    # rest_mode_until は nil のまま（setup でリセット済み）

    log_in_as(@user)
    get dashboard_path

    assert_select "*[data-testid=?]", "rest-mode-dashboard-banner", count: 0
  end

  private

  # ===========================================================================
  # ヘルパーメソッド
  # ===========================================================================

  # allow_rest_mode の設定値を指定して習慣を作成するヘルパー。
  #
  # 【なぜ current_user_habit_with_rest_mode から改名したのか】
  #   ActionDispatch::IntegrationTest では current_user メソッドは使えない。
  #   また「current_user の習慣を作る」という名前が実態（@user を使う）と
  #   合っていなかったため、create_habit_with_rest_mode に統一する。
  #
  # 【measurement_type: :check_type について】
  #   docker compose exec web bin/rails runner "puts Habit.measurement_types.inspect"
  #   → {"check_type"=>0, "numeric_type"=>1} で :check_type が正しいことを確認済み。
  def create_habit_with_rest_mode(allow_rest_mode)
    @user.habits.create!(
      name:             "テスト習慣",
      measurement_type: :check_type,
      weekly_target:    5,
      allow_rest_mode:  allow_rest_mode
    )
  end
end