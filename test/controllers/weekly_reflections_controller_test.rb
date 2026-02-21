# test/controllers/weekly_reflections_controller_test.rb
#
# ═══════════════════════════════════════════════════════════════════
# 【このファイルの役割】
#   WeeklyReflectionsController の各アクションが
#   正しく動作するかを自動テストで確認する。
#
#   Rails のコントローラーテスト（ActionDispatch::Integration）を使用。
#   実際の HTTP リクエストをシミュレートしてレスポンスを検証する。
# ═══════════════════════════════════════════════════════════════════

require "test_helper"

class WeeklyReflectionsControllerTest < ActionDispatch::IntegrationTest
  # ---------------------------------------------------------------
  # setup
  # 【なぜ使うのか】
  #   各テストメソッドが実行される前に共通の準備処理を行う。
  #   ここでテスト用ユーザーをログイン状態にしておくことで、
  #   各テストメソッドで同じ前提条件からスタートできる。
  # ---------------------------------------------------------------
  setup do
    # fixtures(:users) で定義した "one" ユーザーをロード
    @user = users(:one)

    # log_in_as ... test_helper.rb に定義したログインヘルパーメソッド
    # セッションに current_user を設定した状態にする
    log_in_as(@user)

    # テスト用の完了済み振り返りをロード（fixtures で定義）
    @completed_reflection = weekly_reflections(:completed_one)
  end

  # ================================================================
  # show アクションのテスト群（Issue #23 で追加）
  # ================================================================

  # ---------------------------------------------------------------
  # test: 詳細ページが正常に表示されること
  # ---------------------------------------------------------------
  test "should get show" do
    # GET /weekly_reflections/:id へリクエストを送信
    get weekly_reflection_path(@completed_reflection)

    # assert_response :success ... HTTP ステータスコード 200 を確認
    assert_response :success
  end

  # ---------------------------------------------------------------
  # test: 詳細ページに対象週の期間が表示されること
  # ---------------------------------------------------------------
  test "should display week period on show page" do
    get weekly_reflection_path(@completed_reflection)

    assert_response :success

    # assert_select でページ内に特定のHTMLと文字列が存在することを確認する
    # text: /正規表現/ は「その文字列を含むか」をチェックする
    # ページの構造が壊れた（例: span → div に変えてしまった）場合も検知できる

    # 対象週の開始日が <p> タグ内に表示されているか
    assert_select "p", text: /#{@completed_reflection.week_start_date.strftime("%Y年%m月%d日")}/

    # 「今週の総合達成率」セクションが <h2> として存在するか
    # UI崩壊（見出しの削除・変更）も検知できる
    assert_select "h2", text: /今週の総合達成率/

    # 「習慣別 実績サマリー」セクションが存在するか
    assert_select "h2", text: /習慣別 実績サマリー/

    # 「振り返りコメント」セクションが存在するか
    assert_select "h2", text: /振り返りコメント/
  end

  # ---------------------------------------------------------------
  # test: 詳細ページに振り返りコメントが表示されること
  # ---------------------------------------------------------------
  test "should display reflection comment on show page" do
    get weekly_reflection_path(@completed_reflection)

    assert_response :success

    # コメントが存在する場合、そのテキストが表示されているか確認
    if @completed_reflection.reflection_comment.present?
      assert_select "div", text: /#{Regexp.escape(@completed_reflection.reflection_comment[0..20])}/
    end
  end

  # ---------------------------------------------------------------
  # test: 他ユーザーの振り返りにアクセスしたとき一覧にリダイレクトされること
  # ---------------------------------------------------------------
  test "should redirect to index when accessing other user's reflection" do
    # fixtures で定義した別ユーザーの振り返り
    other_reflection = weekly_reflections(:other_user_reflection)

    # @user でログイン中に other_user の振り返りへアクセスを試みる
    get weekly_reflection_path(other_reflection)

    # assert_redirected_to: リダイレクト先を確認
    # 他ユーザーのデータへのアクセスは一覧ページへリダイレクトされるべき
    assert_redirected_to weekly_reflections_path
  end

  # ---------------------------------------------------------------
  # test: 存在しない ID へのアクセスで一覧にリダイレクトされること
  # ---------------------------------------------------------------
  test "should redirect to index when reflection not found" do
    # 存在しない ID（999999）へアクセス
    get weekly_reflection_path(id: 999999)

    assert_redirected_to weekly_reflections_path
  end

  # ---------------------------------------------------------------
  # test: 未ログインのユーザーはログインページにリダイレクトされること
  # ---------------------------------------------------------------
  test "should redirect unauthenticated user from show" do
    # セッションをリセットしてログアウト状態にする
    delete session_path

    get weekly_reflection_path(@completed_reflection)

    # require_login の動作確認
    # application_controller.rb が redirect_to login_path しているため login_path が正しい
    assert_redirected_to login_path
  end

  # ================================================================
  # index アクションのテスト群
  # ================================================================

  test "should get index" do
    get weekly_reflections_path
    assert_response :success
  end

  # ================================================================
  # new アクションのテスト群
  # ================================================================

  test "should get new" do
    # travel_to: 指定した日時に時刻を固定してテストする（AM4:00基準テスト用）
    # 日曜日 AM4:00 以降に固定することで振り返り期間内として扱われる
    travel_to WeeklyReflection.current_week_start_date.end_of_day do
      get new_weekly_reflection_path
      assert_response :success
    end
  end

  test "should redirect to show if current week already completed" do
    # 今週の完了済み振り返りがある状態でフォームにアクセスしたとき
    # → 詳細ページへリダイレクトされるべき

    # @completed_reflection の週に時刻を固定
    travel_to @completed_reflection.week_start_date.end_of_day do
      get new_weekly_reflection_path
      # 完了済みなので show へリダイレクト
      assert_redirected_to weekly_reflection_path(@completed_reflection)
    end
  end
end
