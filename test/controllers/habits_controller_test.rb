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
    get habits_path
    assert_response :success

    # 【修正理由】
    # assert_select "h3", text: /習慣/ は「h3のテキストが /習慣/ にマッチする」検証ですが、
    # fixtures の習慣名は「読書」のため「習慣」という文字を含まず失敗していました。
    # fixtures に実際に登録されている習慣名で検証します。
    assert_select "h3", text: /読書/
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

  test "習慣がある場合に完了日数の表示形式（n/m日）が含まれること" do
    get habits_path
    assert_response :success

    # 【修正理由】
    # fixtures の習慣は weekly_target: 7 のため「0/5日」は存在しません。
    # また fixtures にはすでに今週の記録が1件存在するため「1/7日」と表示されます。
    # fixtures の実際の状態に合わせてテストを書き直しています。
    #
    # assert_match を使う理由:
    #   ビューの span 内テキストは改行を含むため assert_select では一致しません。
    #   response.body（HTML全体の文字列）から検索する assert_match を使います。
    assert_match(/\d+\/7日/, response.body)
  end

  test "習慣の記録がある場合に完了日数が正しく表示されること" do
    habit = habits(:habit_one)
    today = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)

    # 【重要】テストを独立させるため、今週の記録を全て削除してからテスト用記録を作成します。
    # fixtures にすでに今週の記録が存在する場合、削除せずに記録を追加すると
    # 「fixtures の件数 + テストで追加した件数」になってしまい、期待値がズレます。
    # delete_all を先に実行することで「必ず2件だけ」の状態を保証します。
    HabitRecord.where(
      user: @user,
      habit: habit,
      record_date: week_start..week_start + 6.days
    ).delete_all

    # 今週の月曜・火曜に記録を2件作成（= 「2/7日」と表示されるはず）
    HabitRecord.create!(user: @user, habit: habit, record_date: week_start,           completed: true)
    HabitRecord.create!(user: @user, habit: habit, record_date: week_start + 1.day,   completed: true)

    get habits_path
    assert_response :success

    # 今週の記録が2件のため「2/7日」と表示されることを確認します
    assert_match(/2\/7日/, response.body)
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
