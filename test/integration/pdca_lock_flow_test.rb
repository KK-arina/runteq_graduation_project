# test/integration/pdca_lock_flow_test.rb
#
# PDCA強制ロック機能フローテスト（E-1追加: 3フィールド必須化対応）
#
# 【E-1追加での変更内容】
#   create_last_week_reflection 内の WeeklyReflection.create! に3フィールドを追加する。

require "test_helper"

class PdcaLockFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)

    HabitRecord.where(user: @user).delete_all
  end

  # ── E-1追加: 3フィールドを追加 ────────────────────────────────────────────
  def create_last_week_reflection(completed:)
    last_week_start = Date.current.beginning_of_week(:monday) - 1.week

    WeeklyReflection.create!(
      user:                 @user,
      week_start_date:      last_week_start,
      week_end_date:        last_week_start + 6.days,
      reflection_comment:   "テスト用前週振り返り",
      direct_reason:        "テスト用の直接原因",        # E-1追加
      background_situation: "テスト用の改善策",           # E-1追加
      next_action:          "テスト用の次への展開",        # E-1追加
      completed_at:         completed ? Time.current : nil
    )
  end
  # ────────────────────────────────────────────────────────────────────────────

  test "ロック発動→振り返り完了によるロック解除→習慣作成の完全フロー" do
    travel_to Time.zone.local(2026, 3, 9, 4, 1, 0) do
      create_last_week_reflection(completed: false)

      log_in_as(@user)

      get dashboard_path
      assert_response :success
      assert_select "p", text: /先週の振り返りが未完了のため、一部の操作が制限されています/

      assert_no_difference("Habit.count") do
        post habits_path, params: {
          habit: { name: "ロック中に作成しようとした習慣", weekly_target: 5 }
        }
      end

      assert_response :redirect
      follow_redirect!
      assert_select "div", text: /先週の振り返りが未完了のため、この操作はできません/

      assert_difference("HabitRecord.count", 1) do
        post habit_habit_records_path(@habit),
             params:  { completed: "1" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end

      assert_response :success

      get new_weekly_reflection_path
      assert_response :success

      last_week_start = WeeklyReflection.current_week_start_date - 7.days
      last_week_reflection = @user.weekly_reflections
                                  .find_by(week_start_date: last_week_start)
      assert_not last_week_reflection.completed?

      # ── E-1追加: フォーム送信に3フィールドを追加 ──────────────────────
      #
      # 【変更理由】
      #   direct_reason / background_situation / next_action が必須になったため、
      #   これらを含まないと 422 Unprocessable Content になる。
      post weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment:   "ロック解除のための振り返り",
          direct_reason:        "残業が多かった",             # E-1追加
          background_situation: "朝型に切り替える",           # E-1追加
          next_action:          "他の習慣にも広げる"           # E-1追加
        }
      }
      # ────────────────────────────────────────────────────────────────────

      last_week_reflection.reload
      assert last_week_reflection.completed?

      assert_redirected_to dashboard_path
      follow_redirect!

      assert_select "body", text: /PDCAロックが解除されました/

      get dashboard_path
      assert_response :success
      assert_select "p",
        text:  /先週の振り返りが未完了のため、一部の操作が制限されています/,
        count: 0

      assert_difference("Habit.count", 1) do
        post habits_path, params: {
          habit: { name: "ロック解除後に作成した習慣", weekly_target: 3 }
        }
      end

      assert_redirected_to habits_path
    end
  end

  test "初週ユーザーは前週振り返りがなくてもロックされないこと" do
    travel_to Time.zone.local(2026, 3, 16, 4, 1, 0) do
      log_in_as(@user)

      get dashboard_path
      assert_response :success
      assert_select "p",
        text:  /先週の振り返りが未完了のため、一部の操作が制限されています/,
        count: 0

      assert_difference("Habit.count", 1) do
        post habits_path, params: {
          habit: { name: "初週に作成した習慣", weekly_target: 7 }
        }
      end

      assert_redirected_to habits_path
    end
  end
end
