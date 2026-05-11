# test/integration/weekly_reflection_flow_test.rb
#
# 週次振り返りフローテスト（E-1追加: 3フィールド必須化対応）
#
# 【E-1追加での変更内容】
#   post weekly_reflections_path に3フィールドを追加する。
#   WeeklyReflection.create! にも3フィールドを追加する。

require "test_helper"

class WeeklyReflectionFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)
  end

  test "振り返り一覧→新規作成→保存→詳細確認ができること" do
    travel_to Time.zone.local(2026, 3, 1, 5, 0, 0) do
      log_in_as(@user)

      get weekly_reflections_path
      assert_response :success

      assert_select "body", text: /今週の状況/
      assert_select "body", text: /過去の振り返り履歴/

      get new_weekly_reflection_path
      assert_response :success

      # ── E-1追加: 3フィールドを追加 ──────────────────────────────────────
      assert_difference("WeeklyReflection.count", 1) do
        post weekly_reflections_path, params: {
          weekly_reflection: {
            reflection_comment:   "今週は読書を毎日できた。来週も継続したい。",
            direct_reason:        "残業が少なかった",      # E-1追加
            background_situation: "朝の時間を活用した",    # E-1追加
            next_action:          "他の習慣にも広げる"      # E-1追加
          }
        }
      end
      # ────────────────────────────────────────────────────────────────────

      assert_redirected_to weekly_reflections_path

      week_start = Date.new(2026, 2, 23)
      reflection = @user.weekly_reflections.find_by(week_start_date: week_start)
      assert_not_nil reflection

      expected_habits_count = @user.habits.active.count
      assert_equal expected_habits_count, reflection.habit_summaries.count

      reflection.reload
      assert reflection.completed?

      get weekly_reflection_path(reflection)
      assert_response :success

      assert_select "body", text: /今週は読書を毎日できた/
    end
  end

  test "既に完了済みの振り返りがある週に新規作成フォームへアクセスするとリダイレクトされること" do
    travel_to Time.zone.local(2026, 3, 8, 5, 0, 0) do
      log_in_as(@user)

      # ── E-1追加: 3フィールドを追加 ──────────────────────────────────────
      existing_reflection = WeeklyReflection.create!(
        user:                 @user,
        week_start_date:      Date.new(2026, 3, 2),
        week_end_date:        Date.new(2026, 3, 8),
        reflection_comment:   "既に完了済みの振り返り",
        direct_reason:        "テスト用の直接原因",      # E-1追加
        background_situation: "テスト用の改善策",         # E-1追加
        next_action:          "テスト用の次への展開",      # E-1追加
        completed_at:         Time.current,
        is_locked:            true
      )
      # ────────────────────────────────────────────────────────────────────

      get new_weekly_reflection_path
      assert_redirected_to weekly_reflections_path
    end
  end

  test "振り返り詳細ページで習慣スナップショットが表示されること" do
    log_in_as(@user)

    reflection = weekly_reflections(:completed_one)

    get weekly_reflection_path(reflection)
    assert_response :success

    assert_select "body", text: /completed_oneの振り返り/
    assert_select "body", text: /ランニング/
    assert_select "body", text: /瞑想/
  end
end
