# test/models/weekly_reflection_task_summary_test.rb
#
# ==============================================================================
# WeeklyReflectionTaskSummary モデルテスト
# ==============================================================================
#
# 【テスト設計方針】
#   WeeklyReflectionHabitSummaryTest と同じ構成を採用する。
#   バリデーション → UNIQUE制約 → アソシエーション → クラスメソッド → インスタンスメソッド
#   の順でテストを記述することで、設計の意図と一致した網羅的なテストになる。
#
# 【fixture との衝突を避ける設計】
#   fixture には completed_one × ai_generated_task を定義済み。
#   テスト本体では completed_one × for_summary_test_task（テスト内で作成）を使うことで
#   UNIQUE 制約違反を防ぐ。
# ==============================================================================

require "test_helper"

class WeeklyReflectionTaskSummaryTest < ActiveSupport::TestCase
  # ============================================================
  # setup: 各テスト実行前に呼ばれる前処理
  # ============================================================
  setup do
    @user       = users(:one)
    @reflection = weekly_reflections(:completed_one)

    # テスト用タスクを動的に作成する
    # fixture の ai_generated_task は summary_one fixture が使っているため
    # 別のタスクを作成して UNIQUE 制約違反を回避する
    @task = @user.tasks.create!(
      title:    "テスト用タスク",
      priority: :must,
      status:   :done,
      completed_at: Time.current
    )

    # .new でインスタンスを作成（DB には保存しない）
    # → 各テストで valid? / invalid? を確認するため
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

  # ============================================================
  # バリデーションテスト
  # ============================================================

  test "有効なデータでサマリーが作成できること" do
    assert @summary.valid?,
           "有効なデータなのにバリデーションエラーが発生: #{@summary.errors.full_messages}"
  end

  test "title がなければ無効であること" do
    @summary.title = nil
    assert_not @summary.valid?
    # エラーメッセージが日本語で返ること
    assert_includes @summary.errors.full_messages.join, "タスク名"
  end

  test "title が101文字以上なら無効であること" do
    @summary.title = "a" * 101
    assert_not @summary.valid?
  end

  test "title が100文字ならば有効であること" do
    @summary.title = "a" * 100
    assert @summary.valid?,
           "title=100文字は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "priority がなければ無効であること" do
    @summary.priority = nil
    assert_not @summary.valid?
  end

  test "was_completed が nil なら無効であること" do
    @summary.was_completed = nil
    assert_not @summary.valid?
    # inclusion バリデーションで [true, false] 以外は弾かれる
  end

  test "was_completed が false でも有効であること（presence: true では弾かれないこと）" do
    # presence: true のみのバリデーションでは false が「空白」と誤判定される。
    # inclusion: { in: [true, false] } を使っているため false は有効な値。
    @summary.was_completed = false
    assert @summary.valid?,
           "was_completed=false は有効なはずです: #{@summary.errors.full_messages}"
  end

  # ============================================================
  # UNIQUE 制約テスト
  # ============================================================

  test "同じ振り返りに同じタスクのスナップショットは重複作成できないこと" do
    # 1件目を保存
    @summary.save!

    # 同じ weekly_reflection × task で2件目を作成しようとする
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

    # 別の振り返りを作成
    other_reflection = WeeklyReflection.create!(
      user:            @user,
      week_start_date: Date.new(2025, 11, 3),
      week_end_date:   Date.new(2025, 11, 9),
      is_locked:       true
    )

    other_summary = WeeklyReflectionTaskSummary.new(
      weekly_reflection: other_reflection,
      task:              @task,
      title:             "テスト用タスク",
      priority:          :must,
      task_type:         :normal,
      was_completed:     true
    )

    assert other_summary.valid?,
           "異なる振り返りなら有効なはずです: #{other_summary.errors.full_messages}"
  end

  # ============================================================
  # アソシエーションテスト
  # ============================================================

  test "WeeklyReflection に紐づいていること" do
    @summary.save!
    assert_equal @reflection, @summary.reload.weekly_reflection
  end

  test "WeeklyReflection 削除時にスナップショットも削除されること（CASCADE）" do
    @summary.save!
    summary_id = @summary.id

    # on_delete: :cascade により WeeklyReflection 削除時に自動削除される
    @reflection.destroy

    assert_not WeeklyReflectionTaskSummary.exists?(summary_id),
               "振り返り削除時にスナップショットも削除されるべき"
  end

  test "タスク削除時は task_id が NULL になりスナップショット自体は残ること（NULLIFY）" do
    @summary.save!
    summary_id = @summary.id

    # on_delete: :nullify によりタスク削除時は task_id が NULL になる
    @task.destroy

    reloaded = WeeklyReflectionTaskSummary.find(summary_id)
    assert_nil reloaded.task_id,
               "タスク削除後は task_id が NULL になるべき"
    assert_equal "テスト用タスク", reloaded.title,
                 "タスク削除後もタイトルのスナップショットは残るべき"
  end

  # ============================================================
  # クラスメソッドテスト（スナップショット保存ロジック）
  # ============================================================

  test "build_from_task でスナップショットが正しく構築されること" do
    # 完了済みタスクからスナップショットを構築
    summary = WeeklyReflectionTaskSummary.build_from_task(@reflection, @task)

    # タイトル・優先度・種別がコピーされていること
    assert_equal @task.title,     summary.title
    assert_equal @task.priority,  summary.priority
    assert_equal @task.task_type, summary.task_type

    # done? || archived? なので was_completed = true
    assert summary.was_completed,
           "done? のタスクは was_completed: true になるべき"

    # completed_at もコピーされていること
    assert_equal @task.completed_at.to_i, summary.completed_at.to_i
  end

  test "build_from_task で未完了タスクは was_completed: false になること" do
    # 未完了タスクを作成
    todo_task = @user.tasks.create!(
      title:    "未完了タスク",
      priority: :should,
      status:   :todo
    )

    summary = WeeklyReflectionTaskSummary.build_from_task(@reflection, todo_task)

    assert_not summary.was_completed,
               "todo のタスクは was_completed: false になるべき"
    assert_nil summary.completed_at,
               "未完了タスクの completed_at は nil になるべき"
  end

  test "build_from_task で archived タスクは was_completed: true になること" do
    # アーカイブ済みタスクは「完了後にアーカイブ」した状態
    archived_task = @user.tasks.create!(
      title:        "アーカイブ済みタスク",
      priority:     :could,
      status:       :archived,
      completed_at: 1.day.ago
    )

    summary = WeeklyReflectionTaskSummary.build_from_task(@reflection, archived_task)

    assert summary.was_completed,
           "archived のタスクは was_completed: true になるべき"
  end

  test "create_all_for_reflection! で対象タスクのスナップショットが作成されること" do
    # 当週に due_date があるタスクを作成
    week_start = @reflection.week_start_date
    week_end   = @reflection.week_end_date

    target_task = @user.tasks.create!(
      title:    "当週期限タスク",
      priority: :must,
      status:   :done,
      due_date: week_start + 2.days,
      completed_at: Time.current
    )

    assert_difference "WeeklyReflectionTaskSummary.count", 1 do
      WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
    end

    created = @reflection.task_summaries.find_by(task: target_task)
    assert_not_nil created,
                   "当週期限タスクのスナップショットが作成されているべき"
    assert_equal "当週期限タスク", created.title
    assert created.was_completed
  end

  test "create_all_for_reflection! は2回実行しても件数が増えないこと（冪等性）" do
    # 対象タスクを作成
    @user.tasks.create!(
      title:    "冪等性テスト用タスク",
      priority: :must,
      status:   :todo,
      due_date: @reflection.week_start_date
    )

    # 1回目
    WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
    count_after_first = WeeklyReflectionTaskSummary.count

    # 2回目: 件数が変わらないこと
    assert_no_difference "WeeklyReflectionTaskSummary.count" do
      WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
    end
  end

  # ============================================================
  # スコープテスト
  # ============================================================

  test "completed_tasks スコープが was_completed: true のサマリーのみ返すこと" do
    fixture_summary = weekly_reflection_task_summaries(:summary_one)
    assert fixture_summary.was_completed

    assert_includes WeeklyReflectionTaskSummary.completed_tasks, fixture_summary
  end

  test "by_priority スコープが優先度昇順（must→should→could）で返すこと" do
    # 複数の優先度のスナップショットを作成
    ref = WeeklyReflection.create!(
      user:            @user,
      week_start_date: Date.new(2025, 10, 6),
      week_end_date:   Date.new(2025, 10, 12),
      is_locked:       true
    )

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

  # ============================================================
  # インスタンスメソッドテスト
  # ============================================================

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