# test/services/weekly_reflection_complete_service_crisis_test.rb
#
# ==============================================================================
# WeeklyReflectionCompleteService 危機介入テスト
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   @reflection.assign_attributes に reflection_comment を追加する。
#   危機ワード検出テストでは direct_reason に危機ワードを入れるため
#   reflection_comment は別フィールドとして入力値を設定する。
# ==============================================================================

require "test_helper"

class WeeklyReflectionCompleteServiceCrisisTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0)

    @user         = users(:one)
    @user_setting = @user.user_setting
    @user_setting.update!(
      ai_analysis_count:         0,
      ai_analysis_monthly_limit: 10,
      notification_enabled:      true
    )

    @reflection = WeeklyReflection.find_or_build_for_current_week(@user)

    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 【修正理由】
    #   E-1 で presence: true を追加したため、reflection_comment なしで
    #   save! するとバリデーションエラーが発生する。
    #   危機介入テストでは direct_reason に危機ワードを入れているが、
    #   reflection_comment は別途設定する必要がある。
    #
    # 【なぜ reflection_comment は空でなく文字列を入れるのか】
    #   presence: true のバリデーションを通過させるため、
    #   空白でない文字列を設定する必要がある。
    #   危機ワードは direct_reason にあるので crisis 検出は正常に動作する。
    @reflection.assign_attributes(
      direct_reason:        "死にたいと思っています",  # 危機ワードを含む
      background_situation: "つらいです",
      next_action:          "",
      reflection_comment:   "今週はとてもつらかった"   # E-1 追加: presence: true 対応
    )
    # ────────────────────────────────────────────────────────────────────────────
  end

  teardown do
    travel_back
  end

  test "危機ワード検出時は WeeklyReflectionAnalysisJob をエンキューしない" do
    assert_no_enqueued_jobs(only: WeeklyReflectionAnalysisJob) do
      WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
    end
  end

  test "危機ワード検出時は crisis_detected: true を返す" do
    result = WeeklyReflectionCompleteService.new(
      reflection: @reflection,
      user:       @user,
      was_locked: false
    ).call

    assert result[:success],         "success は true のはず"
    assert result[:crisis_detected], "crisis_detected は true のはず"
  end

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

  test "危機ワード検出時も振り返りは保存される" do
    result = WeeklyReflectionCompleteService.new(
      reflection: @reflection,
      user:       @user,
      was_locked: false
    ).call

    assert result[:success]
    assert @reflection.reload.completed?, "振り返りは完了状態になるはず"
  end

  test "通常ワードの場合は WeeklyReflectionAnalysisJob がエンキューされる" do
    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 通常ワードテストでも reflection_comment が必要。
    @reflection.assign_attributes(
      direct_reason:        "今週はつらかったけど頑張りました",
      background_situation: "",
      next_action:          "",
      reflection_comment:   "今週を振り返って前向きに取り組めた" # E-1 追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    assert_enqueued_with(job: WeeklyReflectionAnalysisJob) do
      WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
    end
  end
end
