# test/controllers/habits_controller_test.rb
#
# 【このファイルの役割】
# HabitsController のコントローラーテスト。
#
# 【修正理由】
# Rails 6以降、assigns メソッドは rails-controller-testing gem に切り出された。
# gem を追加しなくても済むよう、テストの検証方法を変更した。
#
# 変更前: assigns(:habit_stats) でコントローラーの変数を直接確認
# 変更後: レスポンスのHTMLやステータスコードで動作を検証
#
# 【コントローラーテストの考え方】
# コントローラーテストでは「ユーザーがアクセスしたとき何が起きるか」を確認する。
# 具体的には:
#   ① 正しいHTTPステータスコードが返るか
#   ② 正しいページにリダイレクトされるか
#   ③ 画面に期待するコンテンツが表示されるか
# 内部変数の中身は「モデルテスト」で確認するのが Rails の慣習。

require "test_helper"

class HabitsControllerTest < ActionDispatch::IntegrationTest

  setup do
    # fixtures からテスト用ユーザーを取得する
    @user = users(:one)

    # ログイン状態を作る
    # post login_path でセッションを確立し、以降のリクエストにログイン状態を引き継ぐ
    post login_path, params: { session: { email: @user.email, password: "password" } }
  end

  # ============================================================
  # GET /habits のテスト
  # ============================================================

  test "習慣一覧ページが正常に表示されること" do
    get habits_path

    # assert_response :success → HTTP 200 が返ることを確認
    assert_response :success
  end

  test "習慣がある場合に習慣名が表示されること" do
    # テスト用の習慣を作成
    habit = @user.habits.create!(name: "テスト習慣_進捗確認", weekly_target: 7)

    get habits_path

    # assert_select でHTMLの内容を検証する
    # "h2" → h2タグを探す
    # text: habit.name → そのタグ内に習慣名が含まれるか確認
    assert_select "h2", text: habit.name,
                  message: "習慣名「#{habit.name}」がページに表示されていません"
  end

  test "習慣がある場合に進捗バーが表示されること" do
    @user.habits.create!(name: "進捗バーテスト習慣", weekly_target: 3)

    get habits_path

    # assert_response :success で200が返ることを確認
    # 進捗バーのHTML要素（プログレスバーを含むdiv）が存在するか確認
    assert_response :success

    # レスポンスのHTML本文に「今週の進捗」というテキストが含まれているか確認
    # assert_match(期待する文字列またはRegex, 検索対象の文字列)
    assert_match "今週の進捗", response.body,
                 "「今週の進捗」テキストがページに表示されていません"
  end

  test "習慣がある場合に完了日数の表示形式（n / m 日達成）が含まれること" do
    habit = @user.habits.create!(name: "完了日数テスト習慣", weekly_target: 5)

    get habits_path

    # "0 / 5 日達成" のような文字列がレスポンスに含まれるか確認
    # 記録が0件の場合は "0 / (weekly_target) 日達成" が表示されるはず
    assert_match "0 / #{habit.weekly_target} 日達成", response.body,
                 "完了日数の表示「0 / #{habit.weekly_target} 日達成」がページに見つかりません"
  end

  test "習慣の記録がある場合に完了日数が正しく表示されること" do
    habit = @user.habits.create!(name: "記録ありテスト習慣", weekly_target: 7)

    # 今週分の完了記録を2件作成する
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)

    HabitRecord.create!(user: @user, habit: habit, record_date: week_start,     completed: true)
    HabitRecord.create!(user: @user, habit: habit, record_date: week_start + 1, completed: true) if (week_start + 1) <= today

    # 実際に作成できた完了件数を確認
    actual_count = HabitRecord.where(user: @user, habit: habit,
                                      record_date: week_start..today,
                                      completed: true).count

    get habits_path

    # "2 / 7 日達成"（または actual_count に応じた値）が表示されているか
    assert_match "#{actual_count} / #{habit.weekly_target} 日達成", response.body,
                 "完了日数「#{actual_count} / #{habit.weekly_target} 日達成」が表示されていません"
  end

  test "習慣が0件のとき Empty State が表示されること" do
    # このユーザーの習慣をすべて論理削除して0件にする
    @user.habits.active.each(&:soft_delete)

    get habits_path

    assert_response :success
    # 「まだ習慣が登録されていません」というテキストが含まれるか確認
    assert_match "まだ習慣が登録されていません", response.body,
                 "Empty State のテキストが表示されていません"
  end

  test "ログインしていない場合はログインページにリダイレクトされること" do
    # ログアウトしてセッションを破棄する
    delete logout_path

    get habits_path

    # assert_redirected_to → 指定URLへリダイレクトされることを確認
    assert_redirected_to login_path
  end
end