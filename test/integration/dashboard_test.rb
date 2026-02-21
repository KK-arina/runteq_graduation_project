# test/integration/dashboard_test.rb
# =============================================================
# ダッシュボード機能の統合テスト
# HTTP リクエストの流れを通して画面の内容・動作を検証する
# =============================================================

require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
  end

  # ---- ダッシュボードの基本表示テスト ----
  test "ダッシュボードに達成率サマリーが表示されること" do
    # TestLoginHelper のメソッドを使用（test_helper.rb で定義）
    log_in_as(@user)

    get dashboard_path
    assert_response :success

    # assert_select : HTMLに指定の要素・テキストが存在するか確認
    assert_select "h1", text: /ダッシュボード/
    assert_select "h2", text: /今週の達成率/
    assert_select "h2", text: /今日の習慣チェック/
  end

  # ---- 習慣が0件の場合のEmpty State表示テスト ----
  test "習慣が0件のときEmpty Stateが表示されること" do
    # テスト用に有効な習慣をすべて論理削除する
    @user.habits.update_all(deleted_at: Time.current)

    log_in_as(@user)

    get dashboard_path
    assert_response :success

    # 習慣が0件のときのメッセージが表示されることを確認
    assert_select "p", text: /まだ習慣が登録されていません/
  end

  # ---- ルートパスからのリダイレクトテスト ----
  test "ログイン後にルートパスへアクセスするとダッシュボードにリダイレクトされること" do
    log_in_as(@user)

    get root_path
    assert_redirected_to dashboard_path
  end
end