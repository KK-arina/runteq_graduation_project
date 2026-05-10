# test/models/weekly_reflection_task_summary_test.rb
#
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   WeeklyReflection.create! に reflection_comment を追加する。
#   （「異なる振り返りなら...」テストと「by_priority スコープ...」テスト）
# ==============================================================================

require "test_helper"

class WeeklyReflectionTaskSummaryTest < ActiveSupport::TestCase
  setup do
    @user       = users(:one)
    @reflection = weekly_reflections(:completed_one)

    @task = @user.tasks.create!(
      title:        "テスト用タスク",
      priority:     :must,
      status:       :done,
      completed_at: Time.current
    )

    @summary = WeeklyReflectionTaskSummary.new(
      weekly_reflection: @reflection,
      task:              @task,
      title:             "テスト用タスク",
      priority:          :must,
      task_type:         :normal,
      was_completed:     true,
      completed_at:      Time.current,
      due_date:          Date.current
    )
  end

  test "有効なデータでサマリーが作成できること" do
    assert @summary.valid?, "有効なデータなのにバリデーションエラーが発生: #{@summary.errors.full_messages}"
  end

  test "title がなければ無効であること" do
    @summary.title = nil
    assert_not @summary.valid?
    assert_includes @summary.errors.full_messages.join, "タスク名"
  end

  test "title が101文字以上なら無効であること" do
    @summary.title = "a" * 101
    assert_not @summary.valid?
  end

  test "title が100文字ならば有効であること" do
    @summary.title = "a" * 100
    assert @summary.valid?, "title=100文字は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "priority がなければ無効であること" do
    @summary.priority = nil
    assert_not @summary.valid?
  end

  test "was_completed が nil なら無効であること" do
    @summary.was_completed = nil
    assert_not @summary.valid?
  end

  test "was_completed が false でも有効であること" do
    @summary.was_completed = false
    assert @summary.valid?, "was_completed=false は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "同じ振り返りに同じタスクのスナップショットは重複作成できないこと" do
    @summary.save!
    duplicate = WeeklyReflectionTaskSummary.new(
      weekly_reflection: @reflection,
      task:              @task,
      title:             "テスト用タスク（コピー）",
      priority:          :must,
      task_type:         :normal,
      was_completed:     false
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:task_id], "は既にこの振り返りに含まれています"
  end

  test "異なる振り返りなら同じタスクのスナップショットを作成できること" do
    @summary.save!

    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 【修正理由】
    #   E-1 で presence: true を追加したため、reflection_comment なしの
    #   create! はバリデーションエラーになる。
    other_reflection = WeeklyReflection.create!(
      user:               @user,
      week_start_date:    Date.new(2025, 11, 3),
      week_end_date:      Date.new(2025, 11, 9),
      is_locked:          true,
      reflection_comment: "タスクサマリーテスト用コメント" # E-1 追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    other_summary = WeeklyReflectionTaskSummary.new(
      weekly_reflection: other_reflection,
      task:              @task,
      title:             "テスト用タスク",
      priority:          :must,
      task_type:         :normal,
      was_completed:     true
    )
    assert other_summary.valid?, "異なる振り返りなら有効なはずです: #{other_summary.errors.full_messages}"
  end

  test "WeeklyReflection に紐づいていること" do
    @summary.save!
    assert_equal @reflection, @summary.reload.weekly_reflection
  end

  test "WeeklyReflection 削除時にスナップショットも削除されること（CASCADE）" do
    @summary.save!
    summary_id = @summary.id
    @reflection.destroy
    assert_not WeeklyReflectionTaskSummary.exists?(summary_id)
  end

  test "タスク削除時は task_id が NULL になりスナップショット自体は残ること（NULLIFY）" do
    @summary.save!
    summary_id = @summary.id
    @task.destroy
    reloaded = WeeklyReflectionTaskSummary.find(summary_id)
    assert_nil reloaded.task_id
    assert_equal "テスト用タスク", reloaded.title
  end

  test "build_from_task でスナップショットが正しく構築されること" do
    summary = WeeklyReflectionTaskSummary.build_from_task(@reflection, @task)
    assert_equal @task.title,     summary.title
    assert_equal @task.priority,  summary.priority
    assert_equal @task.task_type, summary.task_type
    assert summary.was_completed
    assert_equal @task.completed_at.to_i, summary.completed_at.to_i
  end

  test "build_from_task で未完了タスクは was_completed: false になること" do
    todo_task = @user.tasks.create!(
      title:    "未完了タスク",
      priority: :should,
      status:   :todo
    )
    summary = WeeklyReflectionTaskSummary.build_from_task(@reflection, todo_task)
    assert_not summary.was_completed
    assert_nil summary.completed_at
  end

  test "build_from_task で archived タスクは was_completed: true になること" do
    archived_task = @user.tasks.create!(
      title:        "アーカイブ済みタスク",
      priority:     :could,
      status:       :archived,
      completed_at: 1.day.ago
    )
    summary = WeeklyReflectionTaskSummary.build_from_task(@reflection, archived_task)
    assert summary.was_completed
  end

  test "create_all_for_reflection! で対象タスクのスナップショットが作成されること" do
    week_start  = @reflection.week_start_date
    target_task = @user.tasks.create!(
      title:        "当週期限タスク",
      priority:     :must,
      status:       :done,
      due_date:     week_start + 2.days,
      completed_at: Time.current
    )
    assert_difference "WeeklyReflectionTaskSummary.count", 1 do
      WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
    end
    created = @reflection.task_summaries.find_by(task: target_task)
    assert_not_nil created
    assert_equal "当週期限タスク", created.title
    assert created.was_completed
  end

  test "create_all_for_reflection! は2回実行しても件数が増えないこと（冪等性）" do
    @user.tasks.create!(
      title:    "冪等性テスト用タスク",
      priority: :must,
      status:   :todo,
      due_date: @reflection.week_start_date
    )
    WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
    assert_no_difference "WeeklyReflectionTaskSummary.count" do
      WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
    end
  end

  test "completed_tasks スコープが was_completed: true のサマリーのみ返すこと" do
    fixture_summary = weekly_reflection_task_summaries(:summary_one)
    assert fixture_summary.was_completed
    assert_includes WeeklyReflectionTaskSummary.completed_tasks, fixture_summary
  end

  test "by_priority スコープが優先度昇順（must→should→could）で返すこと" do
    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 【修正理由】
    #   E-1 で presence: true を追加したため、reflection_comment なしの
    #   create! はバリデーションエラーになる。
    ref = WeeklyReflection.create!(
      user:               @user,
      week_start_date:    Date.new(2025, 10, 6),
      week_end_date:      Date.new(2025, 10, 12),
      is_locked:          true,
      reflection_comment: "by_priorityスコープテスト用コメント" # E-1 追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    could_task = @user.tasks.create!(title: "Could", priority: :could, status: :todo)
    must_task  = @user.tasks.create!(title: "Must",  priority: :must,  status: :done, completed_at: Time.current)

    WeeklyReflectionTaskSummary.create!(
      weekly_reflection: ref, task: could_task,
      title: "Could", priority: :could, task_type: :normal, was_completed: false
    )
    WeeklyReflectionTaskSummary.create!(
      weekly_reflection: ref, task: must_task,
      title: "Must", priority: :must, task_type: :normal, was_completed: true
    )

    summaries = ref.task_summaries.by_priority
    assert_equal "must",  summaries.first.priority
    assert_equal "could", summaries.last.priority
  end

  test "priority_label が正しい日本語ラベルを返すこと" do
    @summary.priority = :must
    assert_equal "Must", @summary.priority_label
    @summary.priority = :should
    assert_equal "Should", @summary.priority_label
    @summary.priority = :could
    assert_equal "Could", @summary.priority_label
  end

  test "priority_color_class が優先度に応じたクラスを返すこと" do
    @summary.priority = :must
    assert_includes @summary.priority_color_class, "red"
    @summary.priority = :should
    assert_includes @summary.priority_color_class, "blue"
    @summary.priority = :could
    assert_includes @summary.priority_color_class, "green"
  end
end
