# test/controllers/tasks_controller_test.rb
#
# ==============================================================================
# TasksControllerTest（C-2: 完了チェック・ステータス管理のテストを追加）
# ==============================================================================

require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0)

    @user       = users(:one)
    @other_user = users(:two)

    # ============================================================
    # 【修正】ログインパラメータのキー構造を修正する
    # ============================================================
    # 修正前（エラーの原因）:
    #   post login_path, params: { email: @user.email, password: "password" }
    #
    # 修正後:
    #   post login_path, params: { session: { email: ..., password: ... } }
    #
    # 【なぜ修正が必要か】
    #   SessionsController#create は params[:session][:email] でメールアドレスを取得する。
    #   params: { email: ... } だと params[:session] が nil になり、
    #   nil[:email] で NoMethodError: undefined method '[]' for nil が発生する。
    #   フォームの form_with model: :session に合わせて
    #   params: { session: { email: ..., password: ... } } と入れ子にする必要がある。
    post login_path, params: { session: { email: @user.email, password: "password" } }
  end

  teardown do
    travel_back
  end

  # ============================================================
  # C-1 既存テスト（変更なし）
  # ============================================================

  test "タスク一覧ページが表示される" do
    get tasks_path
    assert_response :success
  end

  test "タスク新規作成ページが表示される" do
    get new_task_path
    assert_response :success
  end

  test "タスクを作成できる" do
    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: { title: "テストタスク", priority: "must" }
      }
    end
    assert_redirected_to tasks_path
  end

  test "タイトルが空のときタスクを作成できない" do
    assert_no_difference("Task.count") do
      post tasks_path, params: {
        task: { title: "", priority: "must" }
      }
    end
    assert_response :unprocessable_entity
  end

  # ============================================================
  # C-2 追加テスト: toggle_complete
  # ============================================================

  test "未完了タスクを完了にできる（Turbo Stream）" do
    task = @user.tasks.create!(title: "完了テスト", priority: :must, status: :todo)

    patch toggle_complete_task_path(task),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    task.reload
    assert task.done?, "status が done になっていること"
    assert_not_nil task.completed_at, "completed_at が設定されていること"
  end

  test "完了タスクを未完了に戻せる（Turbo Stream）" do
    task = @user.tasks.create!(
      title: "未完了に戻すテスト",
      priority: :should,
      status: :done,
      completed_at: Time.current
    )

    patch toggle_complete_task_path(task),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    task.reload
    assert task.todo?, "status が todo に戻っていること"
    assert_nil task.completed_at, "completed_at が nil に戻っていること"
  end

  test "ロック中でもチェック操作ができる" do
    last_week_start = HabitRecord.today_for_record
                                 .beginning_of_week(:monday) - 1.week
    @user.weekly_reflections.create!(
      week_start_date: last_week_start,
      week_end_date:   last_week_start + 6.days
    )

    task = @user.tasks.create!(title: "ロック中テスト", priority: :must, status: :todo)

    patch toggle_complete_task_path(task),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    task.reload
    assert task.done?, "ロック中でも完了にできること"
  end

  test "未ログインではtoggle_completeにアクセスできない" do
    # ============================================================
    # 【修正】ログアウトのパラメータも修正する
    # ============================================================
    # SessionsController#destroy は DELETE /logout を期待している。
    # delete logout_path でセッションを破棄する。
    delete logout_path

    task = @user.tasks.create!(title: "未ログインテスト", priority: :must)

    patch toggle_complete_task_path(task)

    assert_redirected_to login_path
  end

  test "他ユーザーのタスクはtoggle_completeできない" do
    other_task = @other_user.tasks.create!(
      title: "他ユーザーのタスク",
      priority: :must
    )

    # ============================================================
    # 【修正】assert_raises を使わず 404 レスポンスで確認する
    # ============================================================
    # 修正前:
    #   assert_raises(ActiveRecord::RecordNotFound) do
    #     patch toggle_complete_task_path(other_task), ...
    #   end
    #
    # 修正後:
    #   assert_response :not_found
    #
    # 【なぜ修正するのか】
    #   ApplicationController に rescue_from ActiveRecord::RecordNotFound があるため、
    #   例外はコントローラー内で rescue されて 404 レスポンスとして返される。
    #   assert_raises は「例外がテストまで伝播すること」を期待するが、
    #   rescue_from がある場合は例外が伝播せず assert_raises が失敗する。
    #   代わりに assert_response :not_found でHTTPステータス404を確認する。
    patch toggle_complete_task_path(other_task),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found
  end

  # ============================================================
  # C-2 追加テスト: archive
  # ============================================================

  test "完了タスクをアーカイブできる（Turbo Stream）" do
    task = @user.tasks.create!(
      title: "アーカイブテスト",
      priority: :must,
      status: :done,
      completed_at: Time.current
    )

    patch archive_task_path(task),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    task.reload
    assert task.archived?, "status が archived になっていること"
  end

  test "未ログインではarchiveにアクセスできない" do
    delete logout_path

    task = @user.tasks.create!(
      title: "未ログインアーカイブテスト",
      priority: :must,
      status: :done,
      completed_at: Time.current
    )

    patch archive_task_path(task)
    assert_redirected_to login_path
  end

  # ============================================================
  # C-2 追加テスト: archive_all_done
  # ============================================================

  test "完了タスクを一括アーカイブできる（Turbo Stream）" do
    3.times do |i|
      @user.tasks.create!(
        title: "完了タスク#{i + 1}",
        priority: :should,
        status: :done,
        completed_at: Time.current
      )
    end

    todo_task = @user.tasks.create!(
      title: "未完了タスク",
      priority: :must,
      status: :todo
    )

    patch archive_all_done_tasks_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    assert_equal 0,
                 @user.tasks.active.where(status: :done).count,
                 "done タスクが 0 件になっていること"

    todo_task.reload
    assert todo_task.todo?, "未完了タスクは todo のままであること"
  end

  test "一括アーカイブは自分のタスクのみ対象にする" do
    @user.tasks.create!(
      title: "@user の完了タスク",
      priority: :must,
      status: :done,
      completed_at: Time.current
    )

    other_done = @other_user.tasks.create!(
      title: "@other_user の完了タスク",
      priority: :must,
      status: :done,
      completed_at: Time.current
    )

    patch archive_all_done_tasks_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    other_done.reload
    assert other_done.done?, "他ユーザーのタスクは done のままであること"
  end

  # ============================================================
  # C-3: destroy アクションのテスト（修正版）
  # ============================================================
  #
  # 【travel_to ブロックを使わない理由】
  #   ActionDispatch::IntegrationTest のセッションは
  #   travel_to ブロックをまたぐと引き継がれないことがある。
  #   setup で行った post login_path が無効になり未ログイン扱いになるため、
  #   require_login が先に動いて 302 が返り期待するステータスが確認できない。
  #
  #   setup で travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) 済み。
  #   4月8日（水曜日）は locked? が false になるため追加の travel_to は不要。
  #
  # 【例外: ロック中テストのみ travel_to ブロック内で再ログインする】
  #   月曜日への時刻移動が必要なため travel_to ブロックを使うが、
  #   ブロック内で post login_path を呼んで再ログインする。

  test "手動タスクを削除できる（HTML形式）" do
    # setup の時刻（2026/4/8 水曜）をそのまま使う
    # travel_to ブロックを使わないのでセッションが正常に引き継がれる
    task = Task.create!(
      user:         @user,
      title:        "削除テストタスク",
      priority:     :must,
      ai_generated: false
    )

    # soft_delete により deleted_at がセットされる
    # Task.active は deleted_at: nil のもののみ返すため -1 になる
    assert_difference "Task.active.count", -1 do
      delete task_path(task)
    end

    assert_redirected_to tasks_path(tab: "all")
    assert_equal "タスクを削除しました", flash[:notice]
  end

  test "AI生成タスクは削除できない（403を返す）" do
    # travel_to ブロックを使わない
    # setup の時刻（2026/4/8 水曜）はロックなし状態なので
    # destroy アクション内の ai_generated チェックが確実に最初に実行される
    #
    # 【なぜ travel_to ブロックを使ってはいけないか】
    #   travel_to ブロック内ではセッションが引き継がれず未ログイン扱いになる
    #   → require_login が先に動いて 302 が返る
    #   → 期待している 403 が確認できない
    ai_task = Task.create!(
      user:         @user,
      title:        "AI生成タスク",
      priority:     :must,
      ai_generated: true
    )

    # DELETE リクエストを送っても論理削除されない
    assert_no_difference "Task.active.count" do
      delete task_path(ai_task)
    end

    # destroy アクション内の ai_generated チェックで 403 が返る
    assert_response :forbidden
  end

  test "他ユーザーのタスクは削除できない（404を返す）" do
    # @other_user は setup で users(:two) として定義済み
    # travel_to ブロックを使わないのでセッションが正常に引き継がれる
    other_task = Task.create!(
      user:         @other_user,
      title:        "他ユーザーのタスク",
      priority:     :must,
      ai_generated: false
    )

    # current_user.tasks.find(params[:id]) で RecordNotFound → 404
    assert_no_difference "Task.active.count" do
      delete task_path(other_task)
    end

    assert_response :not_found
  end

  test "ロック中は手動タスクも削除できない" do
    # locked? の条件:
    #   ① 今が月曜日のAM4:00以降
    #   ② 前週の振り返りが未完了
    #
    # setup の時刻（2026/4/8 水曜）は条件①を満たさないため
    # 月曜日（2026/4/13）に時刻を移動する
    travel_to Time.zone.local(2026, 4, 13, 10, 0, 0) do
      # 前週（4/6〜4/12）の振り返りを未完了状態で作成する
      # completed_at: nil → locked? = true になる
      WeeklyReflection.create!(
        user:            @user,
        week_start_date: Date.new(2026, 4, 6),
        week_end_date:   Date.new(2026, 4, 12),
        year:            2026,
        week_number:     15
        # completed_at は nil のまま（未完了）
      )

      task = Task.create!(
        user:         @user,
        title:        "ロック中の削除テスト",
        priority:     :must,
        ai_generated: false
      )

      # travel_to ブロック内では setup のセッションが失われるため再ログインする
      post login_path, params: { session: { email: @user.email, password: "password" } }

      assert_no_difference "Task.active.count" do
        delete task_path(task)
      end

      # destroy アクション内の require_unlocked により redirect（302）が返る
      assert_response :redirect
    end
  end

  test "未ログイン状態では削除できない" do
    # ログアウトしてセッションを破棄する
    delete logout_path

    task = Task.create!(
      user:         @user,
      title:        "未ログインテスト",
      priority:     :must,
      ai_generated: false
    )

    assert_no_difference "Task.active.count" do
      delete task_path(task)
    end

    # require_login によりログインページへリダイレクト
    assert_redirected_to login_path
  end
end