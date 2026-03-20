# test/integration/user_login_test.rb
# =============================================================
# ユーザーログイン機能の統合テスト
# =============================================================

require "test_helper"

class UserLoginTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
  end

  # test/integration/user_login_test.rb
  # should login with valid credentials テストを修正

  test "should login with valid credentials" do
    get login_path
    assert_response :success

    post login_path, params: {
      session: {
        email:    @user.email,
        password: "password"
      }
    }

    # ------------------------------------------------------------------
    # ✅ 修正ポイント
    # 旧: assert_redirected_to root_path
    # 新: assert_redirected_to dashboard_path
    #     SessionsController#create が dashboard_path に変わったため
    # ------------------------------------------------------------------
    assert_redirected_to dashboard_path

    follow_redirect!
    assert_response :success
    assert_select "h1", text: /ダッシュボード/
  end

  test "無効な認証情報ではログインできないこと" do
    post login_path, params: {
      session: {
        email:    @user.email,
        password: "wrong_password"
      }
    }

    # ログイン失敗時はログインページに留まること
    assert_response :unprocessable_entity
  end
end
