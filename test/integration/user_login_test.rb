require "test_helper"

# ==================== ユーザーログインの統合テスト ====================
# このファイルは、ログイン・ログアウト機能が正しく動作するかをテストします
# 統合テスト: 複数のコントローラー・ビューを組み合わせた動作をテスト

class UserLoginTest < ActionDispatch::IntegrationTest

  # ==================== テスト用データの準備 ====================
  # setup: 各テストの前に実行されるメソッド
  # テスト用のユーザーを作成
  def setup
    # @user: テスト用のユーザーを作成
    # create!: データベースに保存（newとsaveを一度に実行）
    # !: 失敗時に例外を発生させる（テストのデバッグがしやすい）
    @user = User.create!(
      name: "テストユーザー",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  # ==================== 正常系テスト ====================
  # 正しいメールアドレスとパスワードでログインできることをテスト
  test "should login with valid credentials" do
    # ログインフォームを表示
    get login_path
    assert_response :success

    # 正しい認証情報でログイン
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password123"
      }
    }

    # ログイン成功時はTOPページへリダイレクト
    assert_redirected_to root_path
    follow_redirect!

    # フラッシュメッセージ確認
    assert_not flash.empty?
    assert_equal "ログインしました", flash[:notice]

    # セッション確認
    assert is_logged_in?
    assert_equal @user.id, session[:user_id]
  end

  # ==================== 異常系テスト ====================

  # 存在しないメールアドレスではログインできないことをテスト
  test "should not login with invalid email" do
    get login_path

    post login_path, params: {
      session: {
        email: "invalid@example.com",
        password: "password123"
      }
    }

    assert_response :unprocessable_entity
    assert_not is_logged_in?
    assert_nil session[:user_id]

    assert_not flash.empty?
    assert_equal "メールアドレスまたはパスワードが正しくありません", flash[:alert]
  end

  # 間違ったパスワードではログインできないことをテスト
  test "should not login with invalid password" do
    get login_path

    post login_path, params: {
      session: {
        email: @user.email,
        password: "wrongpassword"
      }
    }

    assert_response :unprocessable_entity
    assert_not is_logged_in?
    assert_nil session[:user_id]

    assert_equal "メールアドレスまたはパスワードが正しくありません", flash[:alert]
  end

  # ==================== ログアウトテスト ====================
  test "should logout" do
    # まずログイン
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password123"
      }
    }

    assert is_logged_in?

    # ログアウト実行
    delete logout_path

    # Rails 7 + Turbo 環境では DELETE後は303になることが多い
    assert_response :see_other
    assert_redirected_to root_path
    follow_redirect!

    # セッション確認
    assert_not is_logged_in?
    assert_nil session[:user_id]

    # フラッシュ確認
    assert_not flash.empty?
    assert_equal "ログアウトしました", flash[:notice]
  end

  private

  # ==================== テスト用ヘルパーメソッド ====================
  # IntegrationTest 内では logged_in? に直接アクセスできないため、
  # session[:user_id] を直接確認する
  def is_logged_in?
    session[:user_id].present?
  end
end
