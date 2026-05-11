# test/services/weekly_reflection_complete_service_test.rb
#
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   @reflection = @user.weekly_reflections.build(...) に
#   reflection_comment を追加する。
#   build で作成した @reflection が保存時にバリデーションを通過できるようにする。
# ==============================================================================

require "test_helper"

class WeeklyReflectionCompleteServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)

    @week_start = Date.parse("2026-03-23")
    @week_end   = Date.parse("2026-03-29")

    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 【修正理由】
    #   E-1 で presence: true を追加したため、reflection_comment なしで
    #   save! するとバリデーションエラーが発生する。
    #   build でオブジェクトを作成する時点で reflection_comment を設定しておく。
    @reflection = @user.weekly_reflections.build(
      week_start_date:    @week_start,
      week_end_date:      @week_end,
      reflection_comment: "サービステスト用振り返りコメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    @numeric_habit = @user.habits.create!(
      name:             "ジョギング",
      weekly_target:    5,
      measurement_type: :numeric_type,
      unit:             "分"
    )
  end

  test "corrections が nil のとき正常に完了すること" do
    result = WeeklyReflectionCompleteService.new(
      reflection: @reflection, user: @user, was_locked: false, corrections: nil
    ).call
    assert result[:success], result[:error]
  end

  test "corrections が空ハッシュのとき正常に完了すること" do
    result = WeeklyReflectionCompleteService.new(
      reflection: @reflection, user: @user, was_locked: false, corrections: {}
    ).call
    assert result[:success], result[:error]
  end

  test "今週75分の記録を90分に補正すると差分15分が week_end_date に加算されること" do
    [0, 1, 2].each do |offset|
      HabitRecord.create!(
        user: @user, habit: @numeric_habit,
        record_date: @week_start + offset,
        completed: true, numeric_value: 25.0
      )
    end

    result = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "90" }
    ).call

    assert result[:success], result[:error]
    end_record = HabitRecord.find_by(user: @user, habit: @numeric_habit, record_date: @week_end)
    assert_not_nil end_record
    assert_equal 15.0, end_record.numeric_value.to_f
    assert end_record.completed
    assert end_record.is_manual_input
  end

  test "補正値が現在の合計と同じとき DB 操作をスキップすること" do
    HabitRecord.create!(
      user: @user, habit: @numeric_habit,
      record_date: @week_start, completed: true, numeric_value: 60.0
    )

    result = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "60" }
    ).call

    assert result[:success], result[:error]
    assert_nil HabitRecord.find_by(user: @user, habit: @numeric_habit, record_date: @week_end)
  end

  test "記録が0件のとき補正で30分を設定すると week_end_date に30分が記録されること" do
    result = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "30" }
    ).call

    assert result[:success], result[:error]
    end_record = HabitRecord.find_by(user: @user, habit: @numeric_habit, record_date: @week_end)
    assert_not_nil end_record
    assert_equal 30.0, end_record.numeric_value.to_f
  end

  test "マイナス差分のとき week_end_date の値が 0 以上にクランプされること" do
    HabitRecord.create!(
      user: @user, habit: @numeric_habit,
      record_date: @week_start, completed: true, numeric_value: 100.0
    )

    result = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "80" }
    ).call

    assert result[:success], result[:error]
    end_record = HabitRecord.find_by(user: @user, habit: @numeric_habit, record_date: @week_end)
    assert_not_nil end_record
    assert_equal 0.0, end_record.numeric_value.to_f
    assert_not end_record.completed
  end

  test "再補正しても元の記録（事実）を基準に正しく動くこと" do
    [0, 1, 2].each do |offset|
      HabitRecord.create!(
        user: @user, habit: @numeric_habit,
        record_date: @week_start + offset,
        completed: true, numeric_value: 25.0,
        is_manual_input: false
      )
    end

    result1 = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "90" }
    ).call
    assert result1[:success], result1[:error]

    end_record_after_first = HabitRecord.find_by(
      user: @user, habit: @numeric_habit, record_date: @week_end
    )
    assert_equal 15.0, end_record_after_first.numeric_value.to_f

    service2 = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "100" }
    )
    service2.send(:apply_numeric_corrections!)

    end_record_after_second = HabitRecord.find_by(
      user: @user, habit: @numeric_habit, record_date: @week_end
    )
    assert_equal 40.0, end_record_after_second.numeric_value.to_f
  end

  test "他ユーザーの習慣 ID が含まれていても処理されないこと" do
    other_user  = users(:two)
    other_habit = other_user.habits.create!(
      name: "他ユーザーの習慣", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    result = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{other_habit.id}" => "100" }
    ).call

    assert result[:success], result[:error]
    assert HabitRecord.where(user: other_user, habit: other_habit).empty?
  end

  test "チェック型習慣の ID が含まれていても処理されないこと" do
    check_habit = @user.habits.create!(
      name: "読書", weekly_target: 5, measurement_type: :check_type
    )

    result = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{check_habit.id}" => "5" }
    ).call

    assert result[:success], result[:error]
    assert_nil HabitRecord.find_by(user: @user, habit: check_habit, record_date: @week_end)
  end

  test "不正な補正値（文字列）が来ても Service がクラッシュしないこと" do
    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    other_reflection = @user.weekly_reflections.build(
      week_start_date:    Date.parse("2026-04-06"),
      week_end_date:      Date.parse("2026-04-12"),
      reflection_comment: "不正補正値テスト用コメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    result = WeeklyReflectionCompleteService.new(
      reflection:  other_reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "abc" }
    ).call
    assert result[:success], "不正な補正値は無視されて正常完了するべき"
  end

  test "不正なキー形式が来てもスキップされること" do
    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    other_reflection = @user.weekly_reflections.build(
      week_start_date:    Date.parse("2026-04-13"),
      week_end_date:      Date.parse("2026-04-19"),
      reflection_comment: "不正キーテスト用コメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    result = WeeklyReflectionCompleteService.new(
      reflection:  other_reflection,
      user:        @user,
      was_locked:  false,
      corrections: {
        "habit_1;DROP TABLE habits" => "100",
        "habit_abc"                 => "50",
        ""                          => "20"
      }
    ).call

    assert result[:success], "不正なキー形式は無視されて正常完了するべき"
    assert HabitRecord.where(user: @user, record_date: Date.parse("2026-04-19")).empty?
  end

  test "corrections を渡さなくても動作すること" do
    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    other_reflection = @user.weekly_reflections.build(
      week_start_date:    Date.parse("2026-04-20"),
      week_end_date:      Date.parse("2026-04-26"),
      reflection_comment: "correctionsなしテスト用コメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    result = WeeklyReflectionCompleteService.new(
      reflection: other_reflection,
      user:       @user,
      was_locked: false
    ).call
    assert result[:success], "corrections なしでも正常完了するべき"
  end

  test "振り返り完了後にWeeklyReflectionAnalysisJobがエンキューされる" do
    assert_enqueued_with(job: WeeklyReflectionAnalysisJob) do
      result = WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
      assert result[:success], "サービスが成功を返すことを確認"
    end
  end

  test "月次上限到達時はWeeklyReflectionAnalysisJobがエンキューされない" do
    @user.user_setting.update!(
      ai_analysis_count:         10,
      ai_analysis_monthly_limit: 10
    )
    assert_no_enqueued_jobs(only: WeeklyReflectionAnalysisJob) do
      WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
    end
  end
end
