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
    # ✅ 修正ポイント
    # 旧: follow_redirect! → assert_select "div", text: /ユーザー登録が完了しました/
    #     → root_path経由でダッシュボードへ2段階リダイレクトしていた
    #
    # 新: UsersController#create が dashboard_path に直接リダイレクトするため
    #     1回の follow_redirect! で完結する
    #     コメントで指摘された「1回目の遷移を明示的に確認」も追加
    # ------------------------------------------------------------------

    # 1回目：登録後 dashboard_path へのリダイレクトを明示的に確認
    assert_redirected_to dashboard_path

    # リダイレクト先のダッシュボードページを取得
    follow_redirect!
    assert_response :success

    # ダッシュボードが表示されていることを確認
    assert_select "h1", text: /ダッシュボード/
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