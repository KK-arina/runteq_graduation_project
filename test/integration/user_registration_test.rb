# test/integration/user_registration_test.rb
# =============================================================
# ユーザー登録機能の統合テスト
# =============================================================

require "test_helper"

class UserRegistrationTest < ActionDispatch::IntegrationTest
  # test/integration/user_registration_test.rb
  # 有効な情報でユーザー登録ができること テストを修正

  test "有効な情報でユーザー登録ができること" do
    assert_difference "User.count", 1 do
      post users_path, params: {
        user: {
          name:                  "テストユーザー",
          email:                 "new_user@example.com",
          password:              "password",
          password_confirmation: "password"
        }
      }
    end

    # ------------------------------------------------------------------
    # D-7 対応: 新規ユーザーは first_login_at = NULL のため
    # UsersController#create は dashboard_path へリダイレクトするが、
    # DashboardsController の require_login → redirect_to_onboarding_if_needed で
    # /onboarding/step5 へ再リダイレクトされる。
    # 1回目のリダイレクト先は dashboard_path のまま変わらない。
    # ------------------------------------------------------------------

    # 1回目：登録後 dashboard_path へのリダイレクトを確認（変更なし）
    assert_redirected_to dashboard_path

    # 2回目：dashboard_path にアクセスすると /onboarding/step5 へリダイレクト
    # D-7 対応: 新規ユーザーはオンボーディングへ誘導される
    follow_redirect!
    assert_redirected_to onboarding_step5_path
  end

  # ---- 無効な情報での登録失敗テスト ----
  test "無効な情報ではユーザー登録できないこと" do
    assert_no_difference "User.count" do
      post users_path, params: {
        user: {
          name:                  "",
          email:                 "invalid",
          password:              "short",
          password_confirmation: "mismatch"
        }
      }
    end

    # エラーメッセージが表示されること（登録フォームに留まる）
    assert_response :unprocessable_entity
  end
end
