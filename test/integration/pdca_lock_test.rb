# test/integration/pdca_lock_test.rb
#
# PDCA強制ロック機能の統合テスト（E-1追加: 3フィールド必須化対応）
#
# 【E-1追加での変更内容】
#   direct_reason / background_situation / next_action が presence: true になったため、
#   create_last_week_reflection メソッド内の WeeklyReflection.create! に3フィールドを追加する。

require "test_helper"

class PdcaLockTest < ActionDispatch::IntegrationTest
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)

    HabitRecord.where(user: @user).delete_all

    next_monday = Date.current.beginning_of_week(:monday)
    travel_to next_monday.in_time_zone.change(hour: 4, min: 1) + 1.week
  end

  teardown do
    travel_back
  end

  def login
    log_in_as(@user)
  end

  # ── E-1追加: 3フィールドを追加 ────────────────────────────────────────────
  #
  # 【変更理由】
  #   direct_reason / background_situation / next_action が presence: true になったため、
  #   これらのフィールドがないと WeeklyReflection.create! でバリデーションエラーが発生する。
  def create_last_week_reflection(completed:)
    last_week_start = Date.current.beginning_of_week(:monday) - 1.week

    WeeklyReflection.create!(
      user:                 @user,
      week_start_date:      last_week_start,
      week_end_date:        last_week_start + 6.days,
      reflection_comment:   "テスト用振り返り",
      direct_reason:        "テスト用の直接原因",        # E-1追加
      background_situation: "テスト用の改善策",           # E-1追加
      next_action:          "テスト用の次への展開",        # E-1追加
      completed_at:         completed ? Time.current : nil
    )
  end
  # ────────────────────────────────────────────────────────────────────────────

  test "前週未完了かつ月曜AM4:00以降→ダッシュボードに警告バナーが表示される" do
    create_last_week_reflection(completed: false)
    login

    get dashboard_path
    assert_response :success
    assert_select "p", text: /先週の振り返りが未完了のため、一部の操作が制限されています/
  end

  test "前週完了済み→ダッシュボードに警告バナーは表示されない" do
    create_last_week_reflection(completed: true)
    login

    get dashboard_path
    assert_response :success
    assert_select "p",
      text: /先週の振り返りが未完了のため、一部の操作が制限されています/,
      count: 0
  end

  test "前週の振り返りが存在しない（初週）→ダッシュボードに警告バナーは表示されない" do
    login

    get dashboard_path
    assert_response :success
    assert_select "p",
      text: /先週の振り返りが未完了のため、一部の操作が制限されています/,
      count: 0
  end

  test "月曜AM3:59（AM4:00前）は前週未完了でもロックされない" do
    create_last_week_reflection(completed: false)
    login

    this_monday = Date.current.beginning_of_week(:monday)
    travel_to this_monday.in_time_zone.change(hour: 3, min: 59)

    get dashboard_path
    assert_response :success
    assert_select "p",
      text: /先週の振り返りが未完了のため、一部の操作が制限されています/,
      count: 0

    travel_back
  end

  test "ロック中は習慣を新規作成できない" do
    create_last_week_reflection(completed: false)
    login

    assert_no_difference("Habit.count") do
      post habits_path, params: { habit: { name: "ロック中の習慣", weekly_target: 7 } }
    end

    assert_response :redirect
    follow_redirect!
    assert_select "div", text: /先週の振り返りが未完了のため、この操作はできません/
  end

  test "ロック解除中は習慣を新規作成できる" do
    create_last_week_reflection(completed: true)
    login

    assert_difference("Habit.count", 1) do
      post habits_path, params: { habit: { name: "新しい習慣", weekly_target: 7 } }
    end

    assert_redirected_to habits_path
  end

  test "ロック中は習慣を削除できない" do
    create_last_week_reflection(completed: false)
    login

    assert_no_difference("Habit.active.count") do
      delete habit_path(@habit)
    end

    assert_response :redirect
    follow_redirect!
    assert_select "div", text: /先週の振り返りが未完了のため、この操作はできません/
  end

  test "ロック解除中は習慣を削除できる" do
    create_last_week_reflection(completed: true)
    login

    assert_difference("Habit.active.count", -1) do
      delete habit_path(@habit)
    end

    assert_redirected_to habits_path
  end

  test "ロック中でも習慣の日次記録（即時保存）はできる" do
    create_last_week_reflection(completed: false)
    login

    assert_difference("HabitRecord.count", 1) do
      post habit_habit_records_path(@habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    record = HabitRecord.last
    assert_equal HabitRecord.today_for_record, record.record_date
    assert record.completed
  end
end
