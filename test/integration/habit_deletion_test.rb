require "test_helper"

class HabitDeletionTest < ActionDispatch::IntegrationTest
  # setup: 各テスト実行前に自動的に実行されるメソッド
  # ログイン状態を事前に作成しておく
  setup do
    # fixtures から test ユーザーを取得
    @user = users(:one)
    
    # fixtures から other ユーザーを取得（他のユーザーの習慣削除テスト用）
    @other_user = users(:two)
    
    # test ユーザーの習慣を取得
    @habit = habits(:one)
    
    # other ユーザーの習慣を取得
    @other_habit = habits(:two)
    
    # test ユーザーでログイン
    # セッションに user_id を保存することでログイン状態を作成
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password"  # fixtures で設定したパスワード
      }
    }
  end
  
  # テスト1: ログイン後に習慣を論理削除できること
  test "ログイン後に習慣を論理削除できること" do
    # 削除前の習慣数を確認（有効な習慣のみ）
    assert_equal 1, @user.habits.active.count
    
    # 削除リクエストを送信
    # delete: DELETEリクエストを送信
    # habit_path(@habit): /habits/:id のパス
    # assert_difference: ブロック実行前後でカウントが変化することを確認
    # -1: 1件減少することを期待
    assert_difference("Habit.active.count", -1) do
      delete habit_path(@habit)
    end
    
    # 削除後の習慣数を確認（有効な習慣のみ）
    assert_equal 0, @user.habits.active.count
    
    # 論理削除されていることを確認（deleted_at が設定されている）
    @habit.reload  # データベースから最新の状態を再読み込み
    assert_not_nil @habit.deleted_at, "deleted_at が設定されているはず"
    
    # 物理削除されていないことを確認
    assert Habit.exists?(@habit.id), "習慣がデータベースに残っているはず"
    
    # リダイレクト先の確認
    assert_redirected_to habits_path
    
    # リダイレクト先に移動
    follow_redirect!
    
    # 成功メッセージが表示されることを確認
    assert_select "div", text: /習慣を削除しました/
  end
  
  # テスト2: 他のユーザーの習慣は削除できないこと（セキュリティテスト）
  test "他のユーザーの習慣は削除できないこと" do
    # 削除前の習慣数を確認
    assert_equal 1, @other_user.habits.active.count
    
    # 他のユーザーの習慣を削除しようとする
    # assert_no_difference: ブロック実行前後でカウントが変化しないことを確認
    assert_no_difference("Habit.active.count") do
      delete habit_path(@other_habit)
    end
    
    # 他のユーザーの習慣数は変わらないことを確認
    assert_equal 1, @other_user.habits.active.count
    
    # 習慣一覧ページにリダイレクトされることを確認
    assert_redirected_to habits_path
    
    # リダイレクト先に移動
    follow_redirect!
    
    # エラーメッセージが表示されることを確認
    assert_select "div", text: /習慣が見つかりませんでした/
  end
  
  # テスト3: 論理削除済みの習慣は再度削除できないこと
  test "論理削除済みの習慣は再度削除できないこと" do
    # 習慣を論理削除
    @habit.soft_delete
    
    # 削除前の習慣数を確認（有効な習慣のみ）
    assert_equal 0, @user.habits.active.count
    
    # 論理削除済みの習慣を削除しようとする
    assert_no_difference("Habit.count") do
      delete habit_path(@habit)
    end
    
    # 習慣一覧ページにリダイレクトされることを確認
    assert_redirected_to habits_path
    
    # リダイレクト先に移動
    follow_redirect!
    
    # エラーメッセージが表示されることを確認
    assert_select "div", text: /習慣が見つかりませんでした/
  end
  
  # テスト4: 未ログイン時は習慣を削除できないこと
  test "未ログイン時は習慣を削除できないこと" do
    # ログアウト
    delete logout_path
    
    # 削除前の習慣数を確認
    assert_equal 1, @user.habits.active.count
    
    # 習慣を削除しようとする
    assert_no_difference("Habit.active.count") do
      delete habit_path(@habit)
    end
    
    # ログインページにリダイレクトされることを確認
    assert_redirected_to login_path
  end
end