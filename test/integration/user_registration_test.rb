require "test_helper"

# ユーザー登録機能の統合テスト
# 実際のユーザー操作フローをシミュレートしてテスト
class UserRegistrationTest < ActionDispatch::IntegrationTest  # ← クラス名を修正
  # test "テスト名": テストケースを定義
  test "有効な情報でユーザー登録ができること" do
    # ユーザー登録ページにアクセス
    # get: HTTPのGETリクエストを送信
    # new_user_path: /users/new への名前付きルート
    get new_user_path
    # assert_response :success: HTTPステータスコード 200（成功）が返ってくることを確認
    assert_response :success

    # ユーザー登録処理
    # assert_difference: ブロック実行前後で指定した値が変化することを確認
    # "User.count", 1: User の総数が1増えることを期待
    assert_difference("User.count", 1) do
      # post: HTTPのPOSTリクエストを送信
      # users_path: /users への名前付きルート（UsersController の create アクション）
      # params: 送信するパラメータ
      #   user[name]: ユーザー名
      #   user[email]: メールアドレス
      #   user[password]: パスワード
      #   user[password_confirmation]: パスワード確認
      post users_path, params: {
        user: {
          name: "Test User",
          email: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    # assert_redirected_to: リダイレクト先が指定のパスであることを確認
    # root_path: TOPページ（ランディングページ）
    # ユーザー登録成功後は自動的にログインし、TOPページにリダイレクト
    assert_redirected_to root_path
    
    # follow_redirect!: リダイレクト先に実際に移動する
    follow_redirect!

    # assert_select: 指定したHTMLタグが存在することを確認
    # "div", text: /ユーザー登録が完了しました/: 
    #   "ユーザー登録が完了しました"というテキストを含むdivタグが存在するか
    assert_select "div", text: /ユーザー登録が完了しました/
  end

  test "無効な情報ではユーザー登録ができないこと" do
    # ユーザー登録ページにアクセス
    get new_user_path
    assert_response :success

    # 無効な情報でユーザー登録を試みる
    # assert_no_difference: ブロック実行前後で指定した値が変化しないことを確認
    # "User.count": User の総数が増えないことを期待（バリデーションエラーで保存失敗）
    assert_no_difference("User.count") do
      post users_path, params: {
        user: {
          name: "",  # 空欄（バリデーションエラー）
          email: "invalid",  # 無効なメールアドレス
          password: "pass",  # 短すぎるパスワード（8文字未満）
          password_confirmation: "pass"
        }
      }
    end

    # assert_response :unprocessable_entity: HTTPステータスコード 422 が返ってくることを確認
    # バリデーションエラー時は 422 を返すべき（Railsのベストプラクティス）
    assert_response :unprocessable_entity
    
    # エラーメッセージが表示されているか確認
    # "div.bg-red-50": 赤色のエラーボックス（Tailwind CSS クラス）
    assert_select "div.bg-red-50"
  end
end
