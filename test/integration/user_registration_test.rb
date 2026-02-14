require "test_helper"

# ==================== ユーザー登録の統合テスト ====================
# このファイルは、ユーザー登録機能が正しく動作するかをテストします
# 統合テスト: 複数のコントローラー・ビューを組み合わせた動作をテスト

class UserRegistrationTest < ActionDispatch::IntegrationTest
  # ==================== 正常系テスト ====================
  # test: テストケースを定義
  # "should register user with valid information":
  # 有効な情報でユーザー登録ができることをテスト
  test "should register user with valid information" do
    # get new_user_path: GET /users/new にアクセス
    # 新規登録フォームを表示
    get new_user_path
    
    # assert_response :success: HTTPステータスコードが200（成功）であることを検証
    assert_response :success
    
    # assert_difference: ブロック実行前後でカウントが変化することを検証
    # 'User.count', 1: User.countが1増えることを期待
    # つまり、ユーザーが1人作成されることを検証
    assert_difference 'User.count', 1 do
      # post users_path: POST /users にフォームデータを送信
      # params: { user: { name: "...", email: "...", ... } }
      post users_path, params: {
        user: {
          name: "新規ユーザー",
          email: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    
    # assert_redirected_to root_path: TOPページにリダイレクトされることを検証
    # ユーザー登録成功時の期待動作
    assert_redirected_to root_path
    
    # follow_redirect!: リダイレクト先のページに実際に遷移
    # これを実行しないと、フラッシュメッセージのテストができない
    follow_redirect!
    
    # assert_not flash.empty?: フラッシュメッセージが存在することを検証
    assert_not flash.empty?
    
    # assert_equal: 2つの値が等しいことを検証
    # flash[:notice]: 成功メッセージ
    # "ユーザー登録が完了しました": 期待されるメッセージ
    assert_equal "ユーザー登録が完了しました", flash[:notice]
  end

  # ==================== 異常系テスト ====================
  # "should not register user with invalid information":
  # 無効な情報ではユーザー登録ができないことをテスト
  test "should not register user with invalid information" do
    get new_user_path
    assert_response :success
    
    # assert_no_difference: ブロック実行前後でカウントが変化しないことを検証
    # 'User.count': User.countが変化しない（ユーザーが作成されない）
    assert_no_difference 'User.count' do
      post users_path, params: {
        user: {
          name: "",  # 無効: nameが空
          email: "invalid",  # 無効: メール形式が不正
          password: "foo",  # 無効: パスワードが8文字未満
          password_confirmation: "bar"  # 無効: パスワード確認が一致しない
        }
      }
    end
    
    # assert_response :unprocessable_entity: HTTPステータスコードが422であることを検証
    # 422 Unprocessable Entity: リクエストの形式は正しいが、内容に問題がある
    assert_response :unprocessable_entity
    
    # assert_not flash.empty?: フラッシュメッセージが存在することを検証
    # エラーメッセージが表示されるはず
    assert_not flash.empty?
  end
end
