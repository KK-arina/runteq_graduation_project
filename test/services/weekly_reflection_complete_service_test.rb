# test/services/weekly_reflection_complete_service_test.rb
#
# ==============================================================================
# 【テスト失敗修正】
#
# 「再補正しても元の記録（事実）を基準に正しく動くこと」が
# `RecordNotUnique: データが重複しています` で失敗していた。
#
# 【原因】
#   再補正テストで @week_start（2026-03-23）〜 @week_end（2026-03-29）の
#   週に対して振り返りを2回保存しようとしていた。
#   WeeklyReflection には UNIQUE(user_id, week_start_date) 制約があるため、
#   同じ週に2つの振り返りを create! しようとして RecordNotUnique が発生する。
#
# 【修正方針】
#   再補正テストでは「振り返りの保存（weekly_reflection の create）」ではなく
#   「補正ロジックだけ」を2回呼ぶ設計に変更する。
#
#   具体的には:
#   1回目: reflection1 を build して save! → 2回目: 同じ reflection1 を使い直す
#   ただし completed! で完了済みになると2回目の save! が弾かれるため、
#   1回目はあえて completed? 状態を避ける必要がある。
#
#   最もシンプルな解決策:
#   apply_numeric_corrections! に相当する部分だけを
#   テストから直接呼び出す（private メソッドなので send を使う）。
#   これにより「振り返り保存 → 完了」という Service の全体フローを2回走らせず、
#   補正ロジックだけを繰り返し確認できる。
# ==============================================================================

require "test_helper"

class WeeklyReflectionCompleteServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)

    @week_start = Date.parse("2026-03-23")
    @week_end   = Date.parse("2026-03-29")

    @reflection = @user.weekly_reflections.build(
      week_start_date: @week_start,
      week_end_date:   @week_end
    )

    @numeric_habit = @user.habits.create!(
      name:             "ジョギング",
      weekly_target:    5,
      measurement_type: :numeric_type,
      unit:             "分"
    )
  end

  # ============================================================
  # corrections なし（既存動作への影響なし確認）
  # ============================================================

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

  # ============================================================
  # 数値補正の基本テスト
  # ============================================================

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

  # ============================================================
  # 再補正テスト（修正版）
  # ============================================================
  #
  # 【修正内容】
  #   週次振り返りの UNIQUE 制約（user_id, week_start_date）のため、
  #   同じ週に Service を2回呼ぶと2回目の reflection.save! で
  #   RecordNotUnique が発生する。
  #
  #   解決策: apply_numeric_corrections! だけを2回呼ぶ。
  #   Service の private メソッドを send で呼び出し、
  #   「補正ロジックの繰り返し適用」だけをテストする。
  #   Service 全体フロー（save! → complete!）は1回目のみ実行。

  test "再補正しても元の記録（事実）を基準に正しく動くこと" do
    # 元の記録: 75分（月〜水に25分ずつ）
    [0, 1, 2].each do |offset|
      HabitRecord.create!(
        user: @user, habit: @numeric_habit,
        record_date: @week_start + offset,
        completed: true, numeric_value: 25.0,
        is_manual_input: false
      )
    end

    # 1回目の補正: 75分 → 90分（差分+15分）
    # Service 全体フローを実行（save! + complete! が走る）
    result1 = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "90" }
    ).call
    assert result1[:success], result1[:error]

    # 1回目の補正後: week_end_date に 15 分が記録されているはず
    end_record_after_first = HabitRecord.find_by(
      user: @user, habit: @numeric_habit, record_date: @week_end
    )
    assert_equal 15.0, end_record_after_first.numeric_value.to_f,
                 "1回目の補正後: 差分 15 分が記録されているべき"

    # 2回目の補正: 75分 → 100分（差分+25分）
    # 同じ週に振り返りを再 save! すると UNIQUE 制約違反になるため、
    # apply_numeric_corrections! だけを直接呼び出してロジックのみ検証する。
    #
    # 【期待値の考え方】
    #   current_sum（事実: is_manual_input: false/nil のみ） = 75分
    #   target_sum = 100分
    #   diff = 100 - 75 = 25分
    #   week_end_date の現在値 = 15分（1回目の補正分）
    #   新しい week_end_date の値 = 15 + 25 = 40分
    service2 = WeeklyReflectionCompleteService.new(
      reflection:  @reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "100" }
    )
    # private メソッドを直接呼び出して補正ロジックだけをテストする
    # （Service の全体フローは1回目に完了済みのため再実行しない）
    service2.send(:apply_numeric_corrections!)

    end_record_after_second = HabitRecord.find_by(
      user: @user, habit: @numeric_habit, record_date: @week_end
    )
    assert_equal 40.0, end_record_after_second.numeric_value.to_f,
                 "2回目の補正後: week_end_date の値が 15 + 25 = 40 になるべき"
  end

  # ============================================================
  # セキュリティ・堅牢性テスト
  # ============================================================

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
    assert HabitRecord.where(user: other_user, habit: other_habit).empty?,
           "他ユーザーの記録は変更されないべき"
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
    assert_nil HabitRecord.find_by(user: @user, habit: check_habit, record_date: @week_end),
               "チェック型習慣には補正が適用されないべき"
  end

  test "不正な補正値（文字列）が来ても Service がクラッシュしないこと" do
    # 別の週を使う（上のテストと reflection の week_start_date が重複しないよう）
    other_reflection = @user.weekly_reflections.build(
      week_start_date: Date.parse("2026-04-06"),
      week_end_date:   Date.parse("2026-04-12")
    )
    result = WeeklyReflectionCompleteService.new(
      reflection:  other_reflection,
      user:        @user,
      was_locked:  false,
      corrections: { "habit_#{@numeric_habit.id}" => "abc" }
    ).call
    assert result[:success], "不正な補正値は無視されて正常完了するべき"
  end

  test "不正なキー形式が来てもスキップされること" do
    other_reflection = @user.weekly_reflections.build(
      week_start_date: Date.parse("2026-04-13"),
      week_end_date:   Date.parse("2026-04-19")
    )
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
    assert HabitRecord.where(user: @user, record_date: Date.parse("2026-04-19")).empty?,
           "不正なキーから記録が作成されないべき"
  end

  test "corrections を渡さなくても動作すること" do
    other_reflection = @user.weekly_reflections.build(
      week_start_date: Date.parse("2026-04-20"),
      week_end_date:   Date.parse("2026-04-26")
    )
    result = WeeklyReflectionCompleteService.new(
      reflection: other_reflection,
      user:       @user,
      was_locked: false
    ).call
    assert result[:success], "corrections なしでも正常完了するべき"
  end
end
