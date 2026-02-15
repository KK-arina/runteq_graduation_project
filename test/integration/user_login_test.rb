require "test_helper"

# ユーザーログイン機能の統合テスト
class UserLoginTest < ActionDispatch::IntegrationTest
  # setup: 各テスト実行前に毎回実行されるメソッド
  setup do
    # 🔴 重要: User.create! を使わない（fixtures と重複するため）
    # 
    # 修正前（NG）:
    # @user = User.create!(
    #   name: "Test User",
    #   email: "test@example.com",  # fixtures と重複してエラー
    #   password: "password",
    #   password_confirmation: "password"
    # )
    
    # 修正後（OK）:
    # fixtures を使う（test/fixtures/users.yml で定義）
    @user = users(:one)
  end

  # ===== ログイン成功テスト =====
  
  test "should login with valid credentials" do
    # ログインページにアクセス
    # get: HTTPのGETリクエストを送信
    # login_path: /login への名前付きルート
    get login_path
    # assert_response :success: HTTPステータスコード 200（成功）が返ってくることを確認
    assert_response :success

    # ログイン処理
    # post: HTTPのPOSTリクエストを送信
    # params: 送信するパラメータ
    #   session[email]: ログインフォームのメールアドレス欄
    #   session[password]: ログインフォームのパスワード欄
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password"  # fixtures で設定したパスワード
      }
    }

    # assert_redirected_to: リダイレクト先が指定のパスであることを確認
    # root_path: TOPページ（ランディングページ）
    assert_redirected_to root_path
    
    # follow_redirect!: リダイレクト先に実際に移動する
    # これにより、リダイレクト後のページの内容を確認できる
    follow_redirect!

    # assert_select: 指定したHTMLタグが存在することを確認
    # "div", text: /ログインしました/: "ログインしました"というテキストを含むdivタグが存在するか
    assert_select "div", text: /ログインしました/
  end

  # ===== ログイン失敗テスト（無効なメールアドレス） =====
  
  test "should not login with invalid email" do
    # ログインページにアクセス
    get login_path
    assert_response :success

    # 無効なメールアドレスでログイン試行
    # invalid@example.com: 存在しないメールアドレス
    post login_path, params: {
      session: {
        email: "invalid@example.com",
        password: "password"
      }
    }

    # assert_response :unprocessable_entity: HTTPステータスコード 422 が返ってくることを確認
    # ログイン失敗時は 422 を返すべき（Railsのベストプラクティス）
    assert_response :unprocessable_entity

    # エラーメッセージが表示されているか確認
    # "div", text: /メールアドレスまたはパスワードが正しくありません/
    assert_select "div", text: /メールアドレスまたはパスワードが正しくありません/
  end

  # ===== ログイン失敗テスト（無効なパスワード） =====
  
  test "should not login with invalid password" do
    # ログインページにアクセス
    get login_path
    assert_response :success

    # 無効なパスワードでログイン試行
    # wrongpassword: 間違ったパスワード
    post login_path, params: {
      session: {
        email: @user.email,
        password: "wrongpassword"
      }
    }

    # HTTPステータスコード 422 が返ってくることを確認
    assert_response :unprocessable_entity

    # エラーメッセージが表示されているか確認
    assert_select "div", text: /メールアドレスまたはパスワードが正しくありません/
  end

  # ===== ログアウトテスト =====
  
  test "should logout" do
    # まずログイン
    # post: HTTPのPOSTリクエストを送信
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password"
      }
    }

    # ログアウト処理
    # delete: HTTPのDELETEリクエストを送信
    # logout_path: /logout への名前付きルート
    delete logout_path

    # assert_redirected_to: ルートパスにリダイレクトされることを確認
    assert_redirected_to root_path
    
    # リダイレクト先に移動
    follow_redirect!

    # ログアウトメッセージが表示されているか確認
    assert_select "div", text: /ログアウトしました/
  end
end
