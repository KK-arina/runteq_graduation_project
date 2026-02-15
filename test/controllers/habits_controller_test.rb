require "test_helper"

# HabitsControllerのテスト
class HabitsControllerTest < ActionDispatch::IntegrationTest
  # setup: 各テスト実行前に毎回実行されるメソッド
  setup do
    # テスト用ユーザーを取得（fixtures から）
    @user = users(:one)
  end

  # ===== ログイン時のテスト =====
  
  test "should get index when logged in" do
    # ログイン処理
    # post: HTTPのPOSTリクエストを送信
    # login_path: /login への名前付きルート
    post login_path, params: { session: { email: @user.email, password: "password" } }
    
    # 習慣一覧ページにアクセス
    # get: HTTPのGETリクエストを送信
    # habits_path: /habits への名前付きルート
    get habits_path
    
    # 🔴 重要: missing assertions 警告を解消
    # 
    # 修正前（NG）:
    #   test の中に assert が1つもない
    #   → "Test is missing assertions" 警告が出る
    # 
    # 修正後（OK）:
    #   assert_response :success を追加
    #   → HTTPステータスコード 200（成功）が返ってくることを確認
    assert_response :success
  end

  # ===== 未ログイン時のテスト =====
  
  test "should redirect to login when not logged in" do
    # 未ログイン状態で習慣一覧ページにアクセス
    get habits_path
    
    # 🔴 重要: missing assertions 警告を解消
    # 
    # assert_redirected_to: ログインページにリダイレクトされることを確認
    # before_action :require_login により、未ログインユーザーはログインページにリダイレクト
    assert_redirected_to login_path
  end
end
