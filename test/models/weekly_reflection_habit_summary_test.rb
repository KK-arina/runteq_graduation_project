# test/models/weekly_reflection_habit_summary_test.rb
#
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   WeeklyReflection.create! に reflection_comment を追加する。
#   （「異なる振り返りなら同じ習慣のサマリーを作成できること」テスト）
# ==============================================================================

require "test_helper"

class WeeklyReflectionHabitSummaryTest < ActiveSupport::TestCase
  setup do
    @user       = users(:one)
    @habit      = habits(:habit_one)
    @reflection = weekly_reflections(:for_summary_test)

    @summary = WeeklyReflectionHabitSummary.new(
      weekly_reflection: @reflection,
      habit:             @habit,
      habit_name:        "読書",
      weekly_target:     7,
      actual_count:      5,
      achievement_rate:  71.43
    )
  end

  test "有効なデータでサマリーが作成できること" do
    assert @summary.valid?, "有効なデータなのにバリデーションエラーが発生: #{@summary.errors.full_messages}"
  end

  test "habit_nameがなければ無効であること" do
    @summary.habit_name = nil
    assert_not @summary.valid?
    assert @summary.errors.added?(:habit_name, :blank)
  end

  test "habit_nameが51文字以上なら無効であること" do
    @summary.habit_name = "a" * 51
    assert_not @summary.valid?
    assert @summary.errors.added?(:habit_name, :too_long, count: 50)
  end

  test "habit_nameが50文字ならば有効であること" do
    @summary.habit_name = "a" * 50
    assert @summary.valid?
  end

  test "weekly_targetがなければ無効であること" do
    @summary.weekly_target = nil
    assert_not @summary.valid?
    assert @summary.errors.added?(:weekly_target, :blank)
  end

  test "weekly_targetが0なら無効であること" do
    @summary.weekly_target = 0
    assert_not @summary.valid?
  end

  test "weekly_targetが1なら有効であること" do
    @summary.weekly_target = 1
    assert @summary.valid?, "weekly_target=1 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "actual_countがなければ無効であること" do
    @summary.actual_count = nil
    assert_not @summary.valid?
  end

  test "actual_countが負数なら無効であること" do
    @summary.actual_count = -1
    assert_not @summary.valid?
  end

  test "actual_countが0なら有効であること" do
    @summary.actual_count = 0
    assert @summary.valid?, "actual_count=0 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "achievement_rateが101なら無効であること" do
    @summary.achievement_rate = 101
    assert_not @summary.valid?
  end

  test "achievement_rateが-1なら無効であること" do
    @summary.achievement_rate = -1
    assert_not @summary.valid?
  end

  test "achievement_rateが100なら有効であること" do
    @summary.achievement_rate = 100
    assert @summary.valid?, "achievement_rate=100 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "achievement_rateが0なら有効であること" do
    @summary.achievement_rate = 0
    assert @summary.valid?, "achievement_rate=0 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "同じ振り返りに同じ習慣のサマリーは重複作成できないこと" do
    @summary.save!
    duplicate = WeeklyReflectionHabitSummary.new(
      weekly_reflection: @reflection,
      habit:             @habit,
      habit_name:        "読書（コピー）",
      weekly_target:     7,
      actual_count:      3,
      achievement_rate:  42.86
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:habit_id], "は既にこの振り返りに含まれています"
  end

  test "異なる振り返りなら同じ習慣のサマリーを作成できること" do
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
      reflection_comment: "異なる振り返りテスト用コメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    other_summary = WeeklyReflectionHabitSummary.new(
      weekly_reflection: other_reflection,
      habit:             @habit,
      habit_name:        "読書",
      weekly_target:     7,
      actual_count:      5,
      achievement_rate:  71.0
    )
    assert other_summary.valid?, "異なる振り返りなら有効なはずです: #{other_summary.errors.full_messages}"
  end

  test "WeeklyReflectionに紐づいていること" do
    @summary.save!
    assert_equal @reflection, @summary.reload.weekly_reflection
  end

  test "WeeklyReflection削除時にサマリーも削除されること（CASCADE）" do
    @summary.save!
    summary_id = @summary.id
    @reflection.destroy
    assert_not WeeklyReflectionHabitSummary.exists?(summary_id)
  end

  test "build_from_habit でスナップショットが正しく構築されること" do
    @habit.habit_records.where(user: @user).destroy_all
    week_start = @reflection.week_start_date
    3.times do |i|
      HabitRecord.create!(
        user:        @user,
        habit:       @habit,
        record_date: week_start + i.days,
        completed:   true
      )
    end
    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, @habit)
    assert_equal @habit.name,          summary.habit_name
    assert_equal @habit.weekly_target, summary.weekly_target
    assert_equal 3,                    summary.actual_count
    expected_rate = (3.0 / @habit.weekly_target * 100).clamp(0, 100).round(2)
    assert_equal expected_rate, summary.achievement_rate
  end

  test "build_from_habit で未完了レコードは実績に含まれないこと" do
    @habit.habit_records.where(user: @user).destroy_all
    week_start = @reflection.week_start_date
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start,          completed: true)
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start + 1.day,  completed: false)
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start + 2.days, completed: false)
    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, @habit)
    assert_equal 1, summary.actual_count
  end

  test "build_from_habit で他のユーザーの記録は含まれないこと" do
    @habit.habit_records.where(user: @user).destroy_all
    week_start = @reflection.week_start_date
    other_user = users(:two)
    2.times { |i| HabitRecord.create!(user: @user,       habit: @habit, record_date: week_start + i.days, completed: true) }
    3.times { |i| HabitRecord.create!(user: other_user,  habit: @habit, record_date: week_start + i.days, completed: true) }
    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, @habit)
    assert_equal 2, summary.actual_count
  end

  test "create_all_for_reflection! で全習慣のサマリーが作成されること" do
    active_habits      = @user.habits.active
    existing_habit_ids = @reflection.habit_summaries.pluck(:habit_id)
    expected_new       = active_habits.where.not(id: existing_habit_ids).count
    assert_difference "WeeklyReflectionHabitSummary.count", expected_new do
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)
    end
    active_ids         = active_habits.pluck(:id).sort
    created_active_ids = @reflection.habit_summaries.reload.where(habit_id: active_ids).pluck(:habit_id).sort
    assert_equal active_ids, created_active_ids
  end

  test "create_all_for_reflection! は2回実行しても件数が増えないこと（冪等性）" do
    WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)
    assert_no_difference "WeeklyReflectionHabitSummary.count" do
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)
    end
  end

  test "achievement_rate_text が正しい形式で返ること" do
    @summary.achievement_rate = 71.43
    assert_equal "71.43%", @summary.achievement_rate_text
  end

  test "achievement_rate_text が整数でも小数点2桁で返ること" do
    @summary.achievement_rate = 100
    assert_equal "100.00%", @summary.achievement_rate_text
  end

  test "achieved? が達成率100%のとき true を返すこと" do
    @summary.achievement_rate = 100
    assert @summary.achieved?
  end

  test "achieved? が達成率99%のとき false を返すこと" do
    @summary.achievement_rate = 99
    assert_not @summary.achieved?
  end

  test "completed スコープが達成率100%のサマリーのみ返すこと" do
    completed_fixture = weekly_reflection_habit_summaries(:one_habit_one)
    assert_includes WeeklyReflectionHabitSummary.completed, completed_fixture
  end

  test "incomplete スコープが達成率100%未満のサマリーのみ返すこと" do
    incomplete_fixture = weekly_reflection_habit_summaries(:two_habit_one)
    assert_includes WeeklyReflectionHabitSummary.incomplete, incomplete_fixture
    assert_not_includes WeeklyReflectionHabitSummary.completed, incomplete_fixture
  end
end
