require "test_helper"

class HabitsControllerTest < ActionDispatch::IntegrationTest
  # テスト用のユーザーと習慣を作成するセットアップ
  setup do
    @user = users(:one)  # fixturesから取得（将来的に実装）
    # ログイン処理（将来的に実装）
  end

  # 習慣一覧ページが正常に表示されることを確認するテスト
  test "should get index when logged in" do
    # 将来的に実装
    # get habits_url
    # assert_response :success
  end

  # 未ログイン時はログインページにリダイレクトされることを確認するテスト
  test "should redirect to login when not logged in" do
    # 将来的に実装
    # get habits_url
    # assert_redirected_to login_url
  end
end
