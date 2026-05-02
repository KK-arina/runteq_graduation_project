# test/services/weekly_reflection_complete_service_crisis_test.rb
#
# ==============================================================================
# WeeklyReflectionCompleteService 危機介入テスト
# ==============================================================================

require "test_helper"

class WeeklyReflectionCompleteServiceCrisisTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    # 水曜日に固定（週中に固定することで week_range の問題を回避）
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0)

    @user       = users(:one)
    @user_setting = @user.user_setting
    @user_setting.update!(
      ai_analysis_count:          0,
      ai_analysis_monthly_limit:  10,
      notification_enabled:       true
    )

    @reflection = WeeklyReflection.find_or_build_for_current_week(@user)
    @reflection.assign_attributes(
      direct_reason:        "死にたいと思っています",
      background_situation: "つらいです",
      next_action:          "",
      reflection_comment:   ""
    )
  end

  teardown do
    travel_back
  end

  # 【危機ワード検出時】 AI ジョブがエンキューされない
  test "危機ワード検出時は WeeklyReflectionAnalysisJob をエンキューしない" do
    assert_no_enqueued_jobs(only: WeeklyReflectionAnalysisJob) do
      WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
    end
  end

  # 【危機ワード検出時】 crisis_detected: true が返される
  test "危機ワード検出時は crisis_detected: true を返す" do
    result = WeeklyReflectionCompleteService.new(
      reflection: @reflection,
      user:       @user,
      was_locked: false
    ).call

    assert result[:success],        "success は true のはず"
    assert result[:crisis_detected], "crisis_detected は true のはず"
  end

  # 【危機ワード検出時】 AiAnalysis が crisis_detected=true で作成される
  test "危機ワード検出時は crisis_detected=true の AiAnalysis が作成される" do
    assert_difference "AiAnalysis.count", 1 do
      WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
    end

    ai_analysis = AiAnalysis.order(created_at: :desc).first
    assert ai_analysis.crisis_detected, "crisis_detected は true のはず"
  end

  # 【危機ワード検出時】 振り返りは保存される（ロック解除も通常通り）
  test "危機ワード検出時も振り返りは保存される" do
    result = WeeklyReflectionCompleteService.new(
      reflection: @reflection,
      user:       @user,
      was_locked: false
    ).call

    assert result[:success]
    assert @reflection.reload.completed?, "振り返りは完了状態になるはず"
  end

  # 【通常ワードの場合】 AI ジョブがエンキューされる
  test "通常ワードの場合は WeeklyReflectionAnalysisJob がエンキューされる" do
    @reflection.assign_attributes(
      direct_reason: "今週はつらかったけど頑張りました",
      background_situation: "",
      next_action: "",
      reflection_comment: ""
    )

    assert_enqueued_with(job: WeeklyReflectionAnalysisJob) do
      WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
    end
  end
end