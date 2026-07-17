# test/models/numeric_habit_achievement_test.rb
#
# ==============================================================================
# 数値型習慣の達成率計算テスト（I-1: 境界値網羅）
# ==============================================================================
#
# 【このファイルの役割】
#   数値型習慣（measurement_type: :numeric_type）の「達成率」計算を
#   境界値（0%・ちょうど100%・100%超クランプ・切り捨て/丸め）で固定する。
#
# 【達成率の計算経路が2つあることに注意（重要）】
#   ① Habit#weekly_progress_stats … 画面表示用。整数%で floor（切り捨て）。
#        rate = ((numeric_sum / weekly_target) * 100).clamp(0,100).floor
#   ② WeeklyReflectionHabitSummary.build_from_habit … 振り返りスナップショット用。
#        achievement_rate = ((actual / target) * 100).clamp(0,100).round(2)（小数2桁）
#   丸め方が違う（floor と round(2)）ため、両方を別々に検証する。
#
# 【なぜ travel_to で金曜に固定するのか】
#   weekly_progress_stats は「今週(月〜今日)」を集計範囲にする。
#   テスト実行日が月曜だと範囲が1日しかなく、複数日の記録が範囲外になってしまう。
#   週の後半（金曜）に固定すれば、月〜金に置いた記録が確実に今週範囲へ入る。
# ==============================================================================
require "test_helper"

class NumericHabitAchievementTest < ActiveSupport::TestCase
  setup do
    # 2025-01-17 は金曜日。今週 = 月(13)〜金(17) が集計範囲に入る。
    travel_to Time.zone.local(2025, 1, 17, 10, 0, 0)

    @user  = users(:one)
    # 週次目標 150（分）の数値型習慣を用意する
    @habit = @user.habits.create!(
      name:             "ジョギング",
      weekly_target:    150,
      measurement_type: :numeric_type,
      unit:             "分"
    )

    @today      = HabitRecord.today_for_record       # 2025-01-17(金)
    @week_start = @today.beginning_of_week(:monday)  # 2025-01-13(月)
  end

  teardown { travel_back }

  # 週内の指定日に数値記録を作るヘルパー
  # 【completed: value > 0 の理由】
  #   数値型では「値が入っていれば実績あり」。0 のときだけ completed=false にする。
  def record_on(date, value, habit: @habit)
    habit.habit_records.create!(
      user:          @user,
      record_date:   date,
      numeric_value: value,
      completed:     value > 0
    )
  end

  # ============================================================
  # ① Habit#weekly_progress_stats（画面表示用・floor）
  # ============================================================

  test "記録なし: rate=0 / numeric_sum=0.0 / 分母は weekly_target" do
    stats = @habit.weekly_progress_stats(@user)
    assert_equal 0,   stats[:rate]
    assert_equal 0.0, stats[:numeric_sum]
    assert_nil   stats[:completed_count], "数値型は completed_count を使わない（nil）"
    assert_equal 150, stats[:effective_target]
  end

  test "実績が目標ちょうど（150/150）で rate=100" do
    record_on(@today, 150)
    assert_equal 100, @habit.weekly_progress_stats(@user)[:rate]
  end

  test "実績が目標の半分（75/150）で rate=50" do
    record_on(@today, 75)
    assert_equal 50, @habit.weekly_progress_stats(@user)[:rate]
  end

  test "境界: 149/150 は floor で 99（100未満は切り捨て）" do
    # 149 / 150 * 100 = 99.33... → floor → 99
    record_on(@today, 149)
    assert_equal 99, @habit.weekly_progress_stats(@user)[:rate]
  end

  test "境界: 目標超過（151/150）は 100 にクランプされる" do
    # 151 / 150 * 100 = 100.66... → clamp(0,100) → 100
    record_on(@today, 151)
    assert_equal 100, @habit.weekly_progress_stats(@user)[:rate]
  end

  test "週内の複数記録は SUM される（50+100=150 → 100%）" do
    record_on(@week_start,          50)   # 月
    record_on(@week_start + 2.days, 100)  # 水
    stats = @habit.weekly_progress_stats(@user)
    assert_equal 150.0, stats[:numeric_sum]
    assert_equal 100,   stats[:rate]
  end

  test "論理削除（deleted_at）された記録は集計から除外される" do
    # 100分の記録を作った後に論理削除する
    # update_column を使う理由: バリデーションを通さず deleted_at だけ直接立てるため
    deleted = record_on(@week_start, 100)  # 月（あとで論理削除）
    deleted.update_column(:deleted_at, Time.current)

    record_on(@today, 30)                  # 金（有効な記録）

    stats = @habit.weekly_progress_stats(@user)
    assert_equal 30.0, stats[:numeric_sum], "削除済み(100)は合算されず、有効な30のみ"
    assert_equal 20,   stats[:rate],        "30/150 = 20%"
  end

  test "floor の丸め: 目標3・実績2 → 66（66.66→切り捨て）" do
    small = @user.habits.create!(
      name: "腕立て", weekly_target: 3,
      measurement_type: :numeric_type, unit: "回"
    )
    record_on(@today, 2, habit: small)
    # 2 / 3 * 100 = 66.66... → floor → 66
    assert_equal 66, small.weekly_progress_stats(@user)[:rate]
  end

  # ============================================================
  # ② WeeklyReflectionHabitSummary.build_from_habit（スナップショット・round 2）
  # ============================================================
  #
  # 【なぜ WeeklyReflection を保存せずに new で使うのか】
  #   build_from_habit は reflection の user と週の範囲、そして habit_records だけを
  #   参照して「保存前のサマリー」を組み立てる。DB保存は不要なので、
  #   presence 必須フィールド（direct_reason 等）を用意しなくて済む new を使う。

  test "スナップショット: 100/150 → achievement_rate=66.67（round2で丸め）" do
    record_on(@today, 100)
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @week_start,
      week_end_date:   @week_start + 6.days
    )

    summary = WeeklyReflectionHabitSummary.build_from_habit(reflection, @habit)

    # 100 / 150 * 100 = 66.66... → round(2) → 66.67
    assert_in_delta 66.67, summary.achievement_rate.to_f, 0.01, "round(2) で 66.67 になる"
    assert_equal 100.0, summary.actual_value.to_f, "週次SUM(100)がスナップショットされる"
    assert_equal "分",  summary.unit,              "単位がスナップショットされる"
  end

  test "スナップショット: 目標超過（200/150）は 100.0 にクランプ" do
    record_on(@today, 200)
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @week_start,
      week_end_date:   @week_start + 6.days
    )
    summary = WeeklyReflectionHabitSummary.build_from_habit(reflection, @habit)
    assert_in_delta 100.0, summary.achievement_rate.to_f, 0.01
  end

  test "スナップショット: 記録なしは achievement_rate=0.0 / actual_value=0" do
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @week_start,
      week_end_date:   @week_start + 6.days
    )
    summary = WeeklyReflectionHabitSummary.build_from_habit(reflection, @habit)
    assert_in_delta 0.0, summary.achievement_rate.to_f, 0.01
    assert_equal 0.0, summary.actual_value.to_f
  end
end