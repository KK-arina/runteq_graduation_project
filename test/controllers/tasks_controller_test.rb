# test/controllers/tasks_controller_test.rb
#
# ==============================================================================
# TasksControllerTest
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   WeeklyReflection.create! に reflection_comment を追加する。
#   （「ロック中でもチェック操作ができる」「ロック中は手動タスクも削除できない」テスト）
# ==============================================================================

require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0)

    @user       = users(:one)
    @other_user = users(:two)

    post login_path, params: { session: { email: @user.email, password: "password" } }
  end

  teardown do
    travel_back
  end

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
      post tasks_path, params: { task: { title: "テストタスク", priority: "must" } }
    end
    assert_redirected_to tasks_path
  end

  test "タイトルが空のときタスクを作成できない" do
    assert_no_difference("Task.count") do
      post tasks_path, params: { task: { title: "", priority: "must" } }
    end
    assert_response :unprocessable_entity
  end

  test "未完了タスクを完了にできる（Turbo Stream）" do
    task = @user.tasks.create!(title: "完了テスト", priority: :must, status: :todo)
    patch toggle_complete_task_path(task), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    task.reload
    assert task.done?
    assert_not_nil task.completed_at
  end

  test "完了タスクを未完了に戻せる（Turbo Stream）" do
    task = @user.tasks.create!(
      title: "未完了に戻すテスト",
      priority: :should,
      status: :done,
      completed_at: Time.current
    )
    patch toggle_complete_task_path(task), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    task.reload
    assert task.todo?
    assert_nil task.completed_at
  end

  test "ロック中でもチェック操作ができる" do
    last_week_start = HabitRecord.today_for_record
                                 .beginning_of_week(:monday) - 1.week

    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 【修正理由】
    #   E-1 で presence: true を追加したため、reflection_comment なしの
    #   create! はバリデーションエラーになる。
    @user.weekly_reflections.create!(
      week_start_date:    last_week_start,
      week_end_date:      last_week_start + 6.days,
      reflection_comment: "ロック中チェックテスト用コメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    task = @user.tasks.create!(title: "ロック中テスト", priority: :must, status: :todo)
    patch toggle_complete_task_path(task), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    task.reload
    assert task.done?
  end

  test "未ログインではtoggle_completeにアクセスできない" do
    delete logout_path
    task = @user.tasks.create!(title: "未ログインテスト", priority: :must)
    patch toggle_complete_task_path(task)
    assert_redirected_to %r{/login}
  end

  test "他ユーザーのタスクはtoggle_completeできない" do
    other_task = @other_user.tasks.create!(title: "他ユーザーのタスク", priority: :must)
    patch toggle_complete_task_path(other_task), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :not_found
  end

  test "完了タスクをアーカイブできる（Turbo Stream）" do
    task = @user.tasks.create!(
      title: "アーカイブテスト", priority: :must, status: :done, completed_at: Time.current
    )
    patch archive_task_path(task), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    task.reload
    assert task.archived?
  end

  test "未ログインではarchiveにアクセスできない" do
    delete logout_path
    task = @user.tasks.create!(
      title: "未ログインアーカイブテスト", priority: :must, status: :done, completed_at: Time.current
    )
    patch archive_task_path(task)
    assert_redirected_to %r{/login}
  end

  test "完了タスクを一括アーカイブできる（Turbo Stream）" do
    3.times do |i|
      @user.tasks.create!(
        title: "完了タスク#{i + 1}", priority: :should, status: :done, completed_at: Time.current
      )
    end
    todo_task = @user.tasks.create!(title: "未完了タスク", priority: :must, status: :todo)
    patch archive_all_done_tasks_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal 0, @user.tasks.active.where(status: :done).count
    todo_task.reload
    assert todo_task.todo?
  end

  test "一括アーカイブは自分のタスクのみ対象にする" do
    @user.tasks.create!(
      title: "@user の完了タスク", priority: :must, status: :done, completed_at: Time.current
    )
    other_done = @other_user.tasks.create!(
      title: "@other_user の完了タスク", priority: :must, status: :done, completed_at: Time.current
    )
    patch archive_all_done_tasks_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    other_done.reload
    assert other_done.done?
  end

  test "手動タスクを削除できる（HTML形式）" do
    task = Task.create!(user: @user, title: "削除テストタスク", priority: :must, ai_generated: false)
    assert_difference "Task.active.count", -1 do
      delete task_path(task)
    end
    assert_redirected_to tasks_path(tab: "all")
    assert_equal "タスクを削除しました", flash[:notice]
  end

  test "AI生成タスクは削除できない（403を返す）" do
    ai_task = Task.create!(user: @user, title: "AI生成タスク", priority: :must, ai_generated: true)
    assert_no_difference "Task.active.count" do
      delete task_path(ai_task)
    end
    assert_response :forbidden
  end

  test "他ユーザーのタスクは削除できない（404を返す）" do
    other_task = Task.create!(user: @other_user, title: "他ユーザーのタスク", priority: :must, ai_generated: false)
    assert_no_difference "Task.active.count" do
      delete task_path(other_task)
    end
    assert_response :not_found
  end

  test "ロック中は手動タスクも削除できない" do
    travel_to Time.zone.local(2026, 4, 13, 10, 0, 0) do
      # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
      #
      # 【修正理由】
      #   E-1 で presence: true を追加したため、reflection_comment なしの
      #   create! はバリデーションエラーになる。
      WeeklyReflection.create!(
        user:               @user,
        week_start_date:    Date.new(2026, 4, 6),
        week_end_date:      Date.new(2026, 4, 12),
        year:               2026,
        week_number:        15,
        reflection_comment: "ロック中タスク削除テスト用コメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
      )
      # ────────────────────────────────────────────────────────────────────────────

      task = Task.create!(user: @user, title: "ロック中の削除テスト", priority: :must, ai_generated: false)
      post login_path, params: { session: { email: @user.email, password: "password" } }
      assert_no_difference "Task.active.count" do
        delete task_path(task)
      end
      assert_response :redirect
    end
  end

  test "未ログイン状態では削除できない" do
    delete logout_path
    task = Task.create!(user: @user, title: "未ログインテスト", priority: :must, ai_generated: false)
    assert_no_difference "Task.active.count" do
      delete task_path(task)
    end
    assert_redirected_to %r{/login}
  end

  # ============================================================
  # H-7: タスク一覧 Empty State テスト
  # ============================================================

  test "タスクが0件のとき Empty State が表示される" do
    # fixtures のタスクを論理削除して0件にする
    @user.tasks.update_all(deleted_at: Time.current)

    get tasks_path
    assert_response :success

    assert_select "[data-testid='tasks-empty-state']"
  end

  test "タスクが0件のとき all タブに「タスクを追加する」CTAリンクが表示される" do
    @user.tasks.update_all(deleted_at: Time.current)

    get tasks_path
    assert_response :success

    assert_select "a[href='#{new_task_path}']", text: "タスクを追加する"
  end

  test "done タブが0件のとき done 専用 Empty State が表示される" do
    @user.tasks.update_all(deleted_at: Time.current)

    get tasks_path, params: { tab: "done" }
    assert_response :success

    assert_select "[data-testid='tasks-done-empty-state']"
  end

  # ============================================================
  # I-1 追加: 作成→完了→アーカイブの一連フロー（エンドツーエンド）
  # ============================================================
  #
  # 【なぜ追加するのか】
  #   既存テストは create / toggle_complete / archive を「個別に」検証しているが、
  #   POSTで作成したタスクを完了にし、さらにアーカイブするという
  #   一連の動線（エンドツーエンド）は通しで検証されていなかった。
  #   1本のフローとして繋げ、状態遷移が最後まで破綻しないことを保証する。
  test "作成→完了→アーカイブの一連フローが最後まで正しく遷移する" do
    # ① 作成: POST で新規タスクを作る（通常のHTMLリクエスト）
    assert_difference "@user.tasks.count", 1 do
      post tasks_path, params: {
        task: { title: "通しフロー用タスク", priority: "must", task_type: "normal" }
      }
    end
    assert_redirected_to tasks_path

    task = @user.tasks.order(:created_at).last
    assert task.todo?, "作成直後は todo 状態"

    # ② 完了: toggle_complete で done にする（Turbo Stream）
    patch toggle_complete_task_path(task),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    task.reload
    assert task.done?,             "完了操作後は done 状態"
    assert_not_nil task.completed_at, "完了日時が記録される"

    # ③ アーカイブ: done のタスクを archive する（Turbo Stream）
    patch archive_task_path(task),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    task.reload
    assert task.archived?,         "アーカイブ操作後は archived 状態"

    # ④ 最終確認: 有効な done 一覧には残らない（アーカイブされたため）
    assert_not_includes @user.tasks.active.where(status: :done), task,
                        "アーカイブ後は有効な完了タスク一覧から外れる"
  end
end
