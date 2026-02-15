require "test_helper"

# 習慣新規作成機能の統合テスト
# 実際のユーザー操作フローをシミュレートしてテスト
class HabitCreationTest < ActionDispatch::IntegrationTest
  # setup: 各テスト実行前に毎回実行されるメソッド
  # テストデータの準備を行う
  setup do
    # テスト用ユーザーを作成（fixtures から取得）
    # @user: インスタンス変数（このテストクラス内で共有される）
    # users(:one): test/fixtures/users.yml で定義されたテストデータ
    @user = users(:one)
    
    # 他のユーザーも作成（セキュリティテスト用）
    @other_user = users(:two)
  end

  test "ログイン後に習慣を作成できること" do
    # ログイン処理をシミュレート
    post login_path, params: { session: { email: @user.email, password: "password" } }
    assert_redirected_to root_path
    follow_redirect!

    # 新規作成フォームページにアクセス
    get new_habit_path
    assert_response :success

    # 習慣作成処理
    assert_difference("Habit.count", 1) do
      post habits_path, params: { habit: { name: "朝のランニング", weekly_target: 5 } }
    end

    # 習慣一覧ページにリダイレクトされることを確認
    assert_redirected_to habits_path
    follow_redirect!
    
    # フラッシュメッセージの確認
    assert_select "div", text: /習慣を登録しました/
    
    # 作成された習慣が正しいユーザーに紐づいているか確認
    assert_equal @user.id, Habit.last.user_id
  end

  test "習慣名が空欄の場合はエラーメッセージが表示されること" do
    # ログイン処理
    post login_path, params: { session: { email: @user.email, password: "password" } }
    
    # 習慣作成を試みる（習慣名が空欄）
    assert_no_difference("Habit.count") do
      post habits_path, params: { habit: { name: "", weekly_target: 7 } }
    end

    # HTTPステータスコード 422 が返ってくることを確認
    assert_response :unprocessable_entity
    
    # エラーメッセージが表示されているか確認
    assert_select "div.bg-red-50"
  end

  test "週次目標値が0の場合はエラーメッセージが表示されること" do
    # ログイン処理
    post login_path, params: { session: { email: @user.email, password: "password" } }
    
    # 習慣作成を試みる（週次目標値が0）
    assert_no_difference("Habit.count") do
      post habits_path, params: { habit: { name: "読書", weekly_target: 0 } }
    end

    # HTTPステータスコード 422 が返ってくることを確認
    assert_response :unprocessable_entity
    
    # エラーメッセージが表示されているか確認
    assert_select "div.bg-red-50"
  end

  test "週次目標値が8の場合はエラーメッセージが表示されること" do
    # ログイン処理
    post login_path, params: { session: { email: @user.email, password: "password" } }
    
    # 習慣作成を試みる（週次目標値が8 = 上限超過）
    assert_no_difference("Habit.count") do
      post habits_path, params: { habit: { name: "読書", weekly_target: 8 } }
    end

    # HTTPステータスコード 422 が返ってくることを確認
    assert_response :unprocessable_entity
    
    # エラーメッセージが表示されているか確認
    assert_select "div.bg-red-50"
  end

  test "未ログイン時は新規作成フォームにアクセスできないこと" do
    # 🔴 重要: IntegrationTest では session に直接アクセスできない
    # 
    # 修正前（NG）:
    #   delete logout_path if logged_in?
    #   → NoMethodError: undefined method 'session' for nil
    # 
    # 修正後（OK）:
    #   logged_in? メソッドを削除し、直接テスト
    #   → 挙動ベースでテストする
    
    # 未ログイン状態で新規作成フォームにアクセス
    get new_habit_path
    
    # assert_redirected_to: ログインページにリダイレクトされることを確認
    # before_action :require_login により、未ログインユーザーはログインページにリダイレクト
    assert_redirected_to login_path
  end

  test "未ログイン時は習慣を作成できないこと" do
    # 🔴 重要: logged_in? メソッドを使わず、直接テスト
    
    # 未ログイン状態で習慣作成を試みる
    assert_no_difference("Habit.count") do
      post habits_path, params: { habit: { name: "朝のランニング", weekly_target: 5 } }
    end
    
    # ログインページにリダイレクトされることを確認
    assert_redirected_to login_path
  end

  test "他ユーザーのuser_idを指定しても無視されること（セキュリティテスト）" do
    # ログイン処理（@user としてログイン）
    post login_path, params: { session: { email: @user.email, password: "password" } }
    
    # 習慣作成を試みる（不正なuser_idを含む）
    # params に other_user の user_id を含めて送信
    # Strong Parameters により user_id は無視されるべき
    assert_difference("Habit.count", 1) do
      post habits_path, params: {
        habit: {
          name: "不正テスト",
          weekly_target: 3,
          user_id: @other_user.id  # 不正なパラメータ（無視されるべき）
        }
      }
    end
    
    # 作成された習慣のuser_idが正しいか確認
    # Habit.last.user_id: 最後に作成された習慣のuser_id
    # @user.id: ログイン中のユーザーのID（正しいID）
    # @other_user.id ではなく @user.id になっているべき
    assert_equal @user.id, Habit.last.user_id
    
    # 念のため、@other_user のIDではないことも確認
    assert_not_equal @other_user.id, Habit.last.user_id
  end
end