# test/controllers/tasks_controller_test.rb
#
# ==============================================================================
# TasksController テスト（C-1: 基本CRUD）【最終完成版】
# ==============================================================================
# 【レビュー指摘対応済み】
#   ① travel_to をブロックなし + teardown で travel_back に変更
#   ② fixed_time / locked_monday メソッドで時刻定数を一元管理
#   ③ login_as のパラメータ形式を SessionsController に合わせて修正
#      params: { session: { email: ..., password: ... } }
#   ④ ロックテストでリダイレクトとフラッシュメッセージを明示的に検証
#   ⑤ ai_generated の Strong Parameters 拒否テストを追加
# ==============================================================================
require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # fixed_time: テスト全体で使う固定時刻（木曜日・ロックなし）
  # ============================================================
  # 木曜日を選んだ理由:
  #   月曜日 AM4:00 以降は locked? が true になる可能性がある。
  #   木曜日なら確実に locked? = false にしやすい。
  def fixed_time
    Time.zone.local(2026, 4, 9, 10, 0, 0)  # 木曜日 AM10:00
  end

  # locked_monday: ロック状態テスト用の月曜日時刻
  # 月曜日 AM4:00 以降 → ApplicationController#locked? が true を返す条件
  def locked_monday
    Time.zone.local(2026, 4, 7, 10, 0, 0)  # 月曜日 AM10:00
  end

  # ============================================================
  # setup: 各テストの前に実行される共通処理
  # ============================================================
  def setup
    # travel_to をブロックなしで呼ぶ。
    # teardown で travel_back するまで全テストで時間が固定される。
    travel_to fixed_time

    @user = User.create!(
      name:                  "タスクテストユーザー",
      email:                 "tasks_ctrl@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    # locked? が false になるよう前週の振り返りを「完了済み」で作成する。
    # completed_at が nil でないレコードが存在すれば ApplicationController#locked? は false を返す。
    last_week_start = HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week
    WeeklyReflection.create!(
      user:            @user,
      week_start_date: last_week_start,
      week_end_date:   last_week_start + 6.days,
      completed_at:    Time.current,
      year:            last_week_start.cwyear,
      week_number:     last_week_start.cweek
    )
  end

  # ============================================================
  # teardown: 各テストの後に実行される後処理
  # ============================================================
  # travel_to（ブロックなし）は teardown で必ず travel_back する。
  # これがないと次のテストにも固定時間が引き継がれて不安定になる。
  def teardown
    travel_back
  end

  # ============================================================
  # login_as ヘルパー
  # ============================================================
  # 【SessionsController 確認済み】
  # SessionsController#create は params[:session][:email] を使っているため、
  # { session: { email: ..., password: ... } } の入れ子構造が必須。
  #
  # 間違った形式（NG）:
  #   post login_path, params: { email: user.email, password: "password123" }
  #   → params[:session] が nil → NoMethodError または認証失敗
  #
  # 正しい形式（OK）:
  #   post login_path, params: { session: { email: user.email, password: "password123" } }
  #   → params[:session][:email] が正しく "xxx@example.com" を返す
  def login_as(user)
    post login_path, params: { session: { email: user.email, password: "password123" } }
  end

  # ============================================================
  # index アクションのテスト
  # ============================================================

  test "未ログインでアクセスするとログインページにリダイレクト" do
    get tasks_path
    assert_redirected_to login_path
  end

  test "ログイン済みでアクセスするとタスク一覧ページが表示される" do
    login_as(@user)
    get tasks_path
    assert_response :success
    assert_select "h1", "タスク管理"
  end

  test "タブパラメータなしでは all タブとして動作する" do
    login_as(@user)
    get tasks_path
    assert_response :success
  end

  test "tab=must でリクエストすると Must タスクのみ返す" do
    login_as(@user)
    get tasks_path(tab: "must")
    assert_response :success
  end

  test "tab=should でリクエストすると Should タスクのみ返す" do
    login_as(@user)
    get tasks_path(tab: "should")
    assert_response :success
  end

  test "tab=could でリクエストすると Could タスクのみ返す" do
    login_as(@user)
    get tasks_path(tab: "could")
    assert_response :success
  end

  test "tab=done でリクエストすると完了済みタスクを返す" do
    login_as(@user)
    get tasks_path(tab: "done")
    assert_response :success
  end

  # ============================================================
  # new アクションのテスト
  # ============================================================

  test "未ログインで new にアクセスするとログインページにリダイレクト" do
    get new_task_path
    assert_redirected_to login_path
  end

  test "ログイン済みで new にアクセスするとフォームが表示される" do
    login_as(@user)
    get new_task_path
    assert_response :success
    assert_select "h1", "タスクを追加"
    # form の action が tasks_path（POST /tasks）であることを確認する
    assert_select "form[action=?]", tasks_path
  end

  # ============================================================
  # create アクションのテスト
  # ============================================================

  test "有効なパラメータでタスクが作成される" do
    login_as(@user)
    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: { title: "新しいタスク", priority: "must" }
      }
    end
    assert_redirected_to tasks_path
    # リダイレクト後のページにトースト通知が表示されることを確認する
    follow_redirect!
    assert_match "タスクを作成しました", response.body
  end

  test "タイトルなしでは保存されずフォームが再表示される" do
    login_as(@user)
    assert_no_difference("Task.count") do
      post tasks_path, params: {
        task: { title: "", priority: "must" }
      }
    end
    # バリデーションエラー時は 422 を返してフォームを再表示する
    assert_response :unprocessable_entity
    # エラーメッセージエリアが表示されていることを確認する
    assert_select "div[role=alert]"
  end

  test "作成されたタスクは current_user に紐付く" do
    login_as(@user)
    post tasks_path, params: {
      task: { title: "私のタスク", priority: "should" }
    }
    task = Task.last
    assert_equal @user.id, task.user_id,
      "作成されたタスクが current_user に紐付いていない（user_id が一致しない）"
  end

  test "ai_generated は Strong Parameters で拒否される" do
    # 【テストの意図】
    # ai_generated は task_params で許可していないパラメータ。
    # フォームから ai_generated: true を送っても無視される（false のまま）ことを確認する。
    # これにより「AIが生成したタスク」をユーザーが偽装できないことを担保する。
    login_as(@user)
    post tasks_path, params: {
      task: { title: "AIタスク偽装", priority: "must", ai_generated: true }
    }
    task = Task.last
    assert_not task.ai_generated?,
      "ai_generated が Strong Parameters をすり抜けて true になっている（セキュリティ上の問題）"
  end

  # ============================================================
  # ロック状態のテスト
  # ============================================================
  # 【レビュー修正】
  #   assert_no_difference だけでは「なぜ作成されなかったか」が不明。
  #   ロックによるリダイレクトが発生していることと、
  #   フラッシュメッセージに振り返りへの誘導が含まれることを検証する。

  test "ロック中は create が拒否されてリダイレクトされる" do
    # setup の fixed_time（木曜日）から locked_monday（月曜日）に切り替える。
    # travel_back → travel_to の順で時間を切り替える必要がある。
    travel_back
    travel_to locked_monday

    locked_user = User.create!(
      name:                  "ロックユーザー",
      email:                 "locked_task@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    # 前週の振り返りを「未完了」（completed_at: nil）で作成する。
    # completed_at が nil = 未完了 → locked? が true になる条件を満たす。
    last_week_start = HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week
    WeeklyReflection.create!(
      user:            locked_user,
      week_start_date: last_week_start,
      week_end_date:   last_week_start + 6.days,
      year:            last_week_start.cwyear,
      week_number:     last_week_start.cweek
      # completed_at は設定しない（nil = 未完了）
    )

    login_as(locked_user)

    # タスクが作成されないことを確認する
    assert_no_difference("Task.count") do
      post tasks_path, params: {
        task: { title: "ロック中のタスク", priority: "must" }
      }
    end

    # 【レビュー修正】リダイレクトが発生していることを確認する
    # ApplicationController#require_unlocked は redirect_back を実行する
    assert_response :redirect,
      "ロック中なのにリダイレクトされていない（require_unlocked が機能していない可能性）"

    # リダイレクト後のフラッシュメッセージに「振り返り」という文字が含まれることを確認する
    # ApplicationController#require_unlocked のメッセージ:
    #   "先週の振り返りが未完了のため、この操作はできません。先に振り返りを完了してください。"
    follow_redirect!
    assert_match "振り返り", response.body,
      "ロック中のフラッシュメッセージに「振り返り」という文字が含まれていない"
  end
end