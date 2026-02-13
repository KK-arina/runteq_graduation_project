require "test_helper"

# ==========================================================
# ユーザーログインの統合テスト
# ログイン・ログアウト機能が正しく動作するかを検証する
# 統合テスト: 複数のコントローラー・ビューを組み合わせた動作をテスト
# ==========================================================
class UserLoginTest < ActionDispatch::IntegrationTest

  # ==========================================================
  # テスト用データの準備
  # setup: 各テストの前に実行される
  # ==========================================================
  def setup
    @user = User.create!(
      name: "テストユーザー",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  # ==========================================================
  # 正常系テスト
  # 正しいメールアドレスとパスワードでログインできること
  # ==========================================================
  test "should login with valid credentials" do
    # ログインフォーム表示
    get login_path
    assert_response :success

    # ログイン実行
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password123"
      }
    }

    # TOPページへリダイレクト
    assert_redirected_to root_path

    # リダイレクト先へ遷移
    follow_redirect!

    # フラッシュメッセージ確認
    assert_not flash.empty?
    assert_equal "ログインしました", flash[:notice]

    # セッション確認
    assert is_logged_in?
    assert_equal @user.id, session[:user_id]
  end

  # ==========================================================
  # 異常系テスト（メールアドレス不正）
  # ==========================================================
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
  end

  # ==========================================================
  # 異常系テスト（パスワード不正）
  # ==========================================================
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
  end

  # ==========================================================
  # ログアウトテスト
  # ==========================================================
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

    # 303 See Other（Rails 7 + Turbo 推奨）
    assert_response :see_other
    assert_redirected_to root_path

    follow_redirect!

    assert_not is_logged_in?
    assert_nil session[:user_id]
    assert_not flash.empty?
    assert_equal "ログアウトしました", flash[:notice]
  end

  private

  # ==========================================================
  # テスト用ヘルパーメソッド
  # IntegrationTestではコントローラーのlogged_in?は使えないため
  # session[:user_id] を直接確認する
  # ==========================================================
  def is_logged_in?
    session[:user_id].present?
  end
end
