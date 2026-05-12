# test/models/weekly_reflection_habit_summary_test.rb
#
# ==============================================================================
# 【E-2 変更内容】
#   数値型習慣のスナップショット保存・summary_text 表示に関するテストを追加する。
#
# 【E-2 レビュー反映】
#   - numeric? の 0.0 テストを正しい仕様（true を返す）に修正
#   - actual_value=0.0 でも単位付き表示されることを確認するテストを追加
#   - habit_numeric は user: two のため、HabitRecord は @user（users:one）で作成
# ==============================================================================

require "test_helper"

class WeeklyReflectionHabitSummaryTest < ActiveSupport::TestCase
  setup do
    @user       = users(:one)
    @habit      = habits(:habit_one)
    @reflection = weekly_reflections(:for_summary_test)

    # チェック型サマリーのベースオブジェクト
    # actual_value: nil, unit: nil → チェック型を表す
    @summary = WeeklyReflectionHabitSummary.new(
      weekly_reflection: @reflection,
      habit:             @habit,
      habit_name:        "読書",
      weekly_target:     7,
      actual_count:      5,
      actual_value:      nil,
      unit:              nil,
      achievement_rate:  71.43
    )
  end

  # ============================================================
  # 基本バリデーションテスト
  # ============================================================

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

  # ============================================================
  # E-2 追加: actual_value / unit バリデーションテスト
  # ============================================================

  test "actual_valueがnilなら有効であること（チェック型）" do
    # チェック型では actual_value は NULL を許容する
    @summary.actual_value = nil
    assert @summary.valid?, "actual_value=nil は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "actual_valueが0.0なら有効であること（数値型・記録なし）" do
    # 数値型で実績が0のケースも許容する
    @summary.actual_value = 0.0
    assert @summary.valid?, "actual_value=0.0 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "actual_valueが負数なら無効であること" do
    @summary.actual_value = -1.0
    assert_not @summary.valid?
    assert @summary.errors[:actual_value].any?, "actual_value が負数のときエラーが出るべき"
  end

  test "unitが11文字以上なら無効であること" do
    @summary.unit = "a" * 11
    assert_not @summary.valid?
  end

  test "unitがnilなら有効であること（チェック型）" do
    @summary.unit = nil
    assert @summary.valid?, "unit=nil は有効なはずです: #{@summary.errors.full_messages}"
  end

  # ============================================================
  # UNIQUE 制約テスト
  # ============================================================

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
    other_reflection = WeeklyReflection.create!(
      user:                 @user,
      week_start_date:      Date.new(2025, 11, 3),
      week_end_date:        Date.new(2025, 11, 9),
      is_locked:            true,
      reflection_comment:   "異なる振り返りテスト用コメント",
      direct_reason:        "テスト用の直接原因",
      background_situation: "テスト用の改善策",
      next_action:          "テスト用の次への展開"
    )
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

  # ============================================================
  # アソシエーション・CASCADE テスト
  # ============================================================

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

  # ============================================================
  # build_from_habit テスト（チェック型）
  # ============================================================

  test "build_from_habit でチェック型のスナップショットが正しく構築されること" do
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
    assert_nil                         summary.actual_value, "チェック型の actual_value は nil であるべき"
    assert_nil                         summary.unit,         "チェック型の unit は nil であるべき"
    expected_rate = (3.0 / @habit.weekly_target * 100).clamp(0, 100).round(2)
    assert_equal expected_rate,        summary.achievement_rate
  end

  test "build_from_habit で未完了レコードは実績に含まれないこと（チェック型）" do
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
    2.times { |i| HabitRecord.create!(user: @user,      habit: @habit, record_date: week_start + i.days, completed: true) }
    3.times { |i| HabitRecord.create!(user: other_user, habit: @habit, record_date: week_start + i.days, completed: true) }
    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, @habit)
    assert_equal 2, summary.actual_count
  end

  # ============================================================
  # build_from_habit テスト（数値型）E-2 追加
  # ============================================================

  test "build_from_habit で数値型のスナップショットが正しく構築されること" do
    # habit_numeric は user: two のフィクスチャだが、
    # build_from_habit は weekly_reflection.user（@user = users(:one)）で
    # habit_records を集計するため、HabitRecord は @user で作成する。
    # （習慣の所有者とレコードの所有者が異なるケースはスナップショット設計上あり得る）
    numeric_habit = habits(:habit_numeric)
    numeric_habit.habit_records.where(user: @user).destroy_all

    week_start = @reflection.week_start_date
    # 月: 30分、水: 30分、金: 30分 → 合計 90分
    [ 0, 2, 4 ].each do |offset|
      HabitRecord.create!(
        user:          @user,
        habit:         numeric_habit,
        record_date:   week_start + offset.days,
        completed:     true,
        numeric_value: 30.0
      )
    end

    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, numeric_habit)

    assert_equal numeric_habit.name,          summary.habit_name
    assert_equal numeric_habit.weekly_target, summary.weekly_target
    assert_equal 0,    summary.actual_count,       "数値型の actual_count は 0 であるべき"
    assert_equal 90.0, summary.actual_value.to_f,  "numeric_value の SUM が actual_value にセットされるべき"
    assert_equal "分", summary.unit,               "習慣の unit がスナップショットとして保存されるべき"
    expected_rate = (90.0 / numeric_habit.weekly_target * 100).clamp(0, 100).round(2)
    assert_equal expected_rate, summary.achievement_rate
  end

  test "build_from_habit で数値型の記録がない場合 actual_value が 0.0 になること" do
    # 記録なしのケース（actual_value = 0.0, achievement_rate = 0.0）
    numeric_habit = habits(:habit_numeric)
    numeric_habit.habit_records.where(user: @user).destroy_all

    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, numeric_habit)
    assert_equal 0.0,  summary.actual_value.to_f, "記録なしの場合 actual_value は 0.0 であるべき"
    assert_equal 0.0,  summary.achievement_rate,  "記録なしの場合 achievement_rate は 0.0 であるべき"
    assert_equal "分", summary.unit,              "記録なしでも unit はスナップショットとして保存されるべき"
  end

  # ============================================================
  # create_all_for_reflection! テスト
  # ============================================================

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

  # ============================================================
  # インスタンスメソッドテスト
  # ============================================================

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

  # ============================================================
  # E-2 追加: numeric? メソッドのテスト
  # ============================================================

  test "numeric? は actual_value が存在するとき true を返すこと" do
    # actual_value に値があれば数値型サマリーと判定する
    @summary.actual_value = 90.0
    assert @summary.numeric?, "actual_value が存在するとき numeric? は true を返すべき"
  end

  test "numeric? は actual_value が nil のとき false を返すこと" do
    # actual_value が NULL（チェック型）のときは false
    @summary.actual_value = nil
    assert_not @summary.numeric?, "actual_value が nil のとき numeric? は false を返すべき"
  end

  test "numeric? は actual_value が 0.0 のとき true を返すこと" do
    # Rails では 0.0.present? == true（数値は 0 でも「存在する」と判定される）
    # 「今週0分だった」数値型習慣も「0 / 120 分（0%）」と表示するため true が正しい仕様
    @summary.actual_value = 0.0
    assert @summary.numeric?, "actual_value=0.0 のとき numeric? は true を返すべき（0.0.present? == true）"
  end

  # ============================================================
  # E-2 追加: summary_text メソッドのテスト
  # ============================================================

  test "summary_text はチェック型で「N / M 日（XX%）」形式を返すこと" do
    @summary.actual_count     = 5
    @summary.weekly_target    = 7
    @summary.actual_value     = nil
    @summary.achievement_rate = 71.43
    assert_equal "5 / 7 日（71%）", @summary.summary_text
  end

  test "summary_text は数値型で「N / M 単位（XX%）」形式を返すこと" do
    @summary.actual_value     = 90.0
    @summary.weekly_target    = 120
    @summary.unit             = "分"
    @summary.achievement_rate = 75.0
    assert_equal "90 / 120 分（75%）", @summary.summary_text
  end

  test "summary_text は数値型で小数点を正しく表示すること" do
    @summary.actual_value     = 6.5
    @summary.weekly_target    = 10
    @summary.unit             = "km"
    @summary.achievement_rate = 65.0
    assert_equal "6.5 / 10 km（65%）", @summary.summary_text
  end

  test "summary_text は数値型で整数値の末尾ゼロを除去すること" do
    @summary.actual_value     = 90.0
    @summary.weekly_target    = 120
    @summary.unit             = "分"
    @summary.achievement_rate = 75.0
    assert_equal "90 / 120 分（75%）", @summary.summary_text
  end

  test "summary_text は数値型で実績0のとき単位付きで表示すること" do
    # 実績が0でも「0 / 120 分（0%）」と表示されるべき
    # チェック型の「0 / 7 日（0%）」と区別できることを確認する
    @summary.actual_value     = 0.0
    @summary.weekly_target    = 120
    @summary.unit             = "分"
    @summary.achievement_rate = 0.0
    assert_equal "0 / 120 分（0%）", @summary.summary_text
  end

  # ============================================================
  # スコープテスト
  # ============================================================

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