require "test_helper"

# ==================== ユーザー登録の統合テスト ====================
# このファイルは、ユーザー登録機能が正しく動作するかをテストします
# 統合テスト: 複数のコントローラー・ビューを組み合わせた動作をテスト

class UserRegistrationTest < ActionDispatch::IntegrationTest
  # ==================== 正常系テスト ====================
  
  # test: テストケースを定義
  # "should register new user with valid information":
  # 正しい情報でユーザー登録ができることをテスト
  test "should register new user with valid information" do
    # get new_user_path: GET /users/new にアクセス
    # 新規登録フォームを表示
    get new_user_path
    
    # assert_response :success: HTTPステータスコードが200（成功）であることを検証
    assert_response :success
    
    # assert_difference: ブロック実行前後でUser.countが1増えることを検証
    # User.count: データベース内のユーザー数を取得
    # 期待: テスト実行前は0人、実行後は1人
    assert_difference "User.count", 1 do
      # post users_path: POST /users にフォームデータを送信
      # params: { user: { ... } }: フォームから送信されるパラメータ
      post users_path, params: {
        user: {
          name: "テストユーザー",
          email: "test@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    
    # assert_redirected_to root_path: TOPページにリダイレクトされることを検証
    # 登録成功時の期待動作
    assert_redirected_to root_path
    
    # follow_redirect!: リダイレクト先のページに実際に遷移
    # これを実行しないと、フラッシュメッセージのテストができない
    follow_redirect!
    
    # assert_not flash.empty?: フラッシュメッセージが存在することを検証
    # flash.empty?: flashが空かどうかをチェック
    # assert_not: 否定形（空でないことを検証）
    assert_not flash.empty?
    
    # assert_equal: 2つの値が等しいことを検証
    # flash[:notice]: 成功メッセージ
    # "ユーザー登録が完了しました": 期待されるメッセージ
    assert_equal "ユーザー登録が完了しました", flash[:notice]
    
    # assert: 条件が真（true）であることを検証
    # logged_in?: 下記で定義したヘルパーメソッド
    # 期待: 登録後は自動的にログインしている
    assert logged_in?
  end
  
  # ==================== 異常系テスト ====================
  
  # "should not register user with invalid information":
  # 無効な情報ではユーザー登録ができないことをテスト
  test "should not register user with invalid information" do
    get new_user_path
    assert_response :success
    
    # assert_no_difference: ブロック実行前後でUser.countが変わらないことを検証
    # User.count: データベース内のユーザー数を取得
    # 期待: バリデーションエラーで保存されないため、ユーザー数は0のまま
    assert_no_difference "User.count" do
      post users_path, params: {
        user: {
          name: "",  # バリデーションエラー: 名前が空
          email: "invalid",  # バリデーションエラー: メール形式が不正
          password: "short",  # バリデーションエラー: 8文字未満
          password_confirmation: "different"  # バリデーションエラー: パスワードが一致しない
        }
      }
    end
    
    # assert_response :unprocessable_entity: HTTPステータスコードが422であることを検証
    # 422 Unprocessable Entity: リクエストの形式は正しいが、内容に問題がある
    assert_response :unprocessable_entity
    
    # assert_select: 特定のHTML要素が存在することを検証
    # "div.bg-red-50": エラーメッセージのdiv要素
    # エラーメッセージエリアが表示されているか確認
    assert_select "div.bg-red-50"
    
    # assert_not logged_in?: ログインしていないことを検証
    # 期待: 登録失敗時はログインしない
    assert_not logged_in?
  end
  
  private
  
  # ==================== ヘルパーメソッド ====================
  # logged_in?: テスト内でログイン状態をチェック
  # session[:user_id].present?: セッションにuser_idが存在するかチェック
  def logged_in?
    session[:user_id].present?
  end
end