# test/integration/weekly_reflection_ai_status_test.rb
#
# ==============================================================================
# 振り返りの AI分析状態の表示テスト（AI分析状態の修正で追加）
# ==============================================================================
# 【このテストで保証すること】
#   ① 「AIなしで完了」すると、上限の残りに関係なく AI分析ジョブが登録されず、
#      ai_skipped_at と気分スコア（mood）が保存される
#   ② 完了時点で月の上限に達していた場合も ai_skipped_at が記録される
#   ③ 振り返り一覧のバナーが状態に応じて切り替わる
#      AIなしで完了 → skipped / 30分以内 → pending / 30分経過 → unavailable
#   ④ ダッシュボードの「分析中」バナーも同じ基準で表示される
#
# 【data-testid で確認する理由】
#   文言を変えてもテストが壊れないようにするため（H-10 と同じ方針）。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/weekly_reflection_ai_status_test.rb
# ==============================================================================
require "test_helper"

class WeeklyReflectionAiStatusIntegrationTest < ActionDispatch::IntegrationTest
  # assert_no_enqueued_jobs を使うために読み込む（ジョブが登録されたかを確認できる）
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    log_in_as(@user)
    @week_start = WeeklyReflection.current_week_start_date
    # 今週の振り返りが fixtures にあると「既に完了しています」になるため、先に消しておく
    @user.weekly_reflections.where(week_start_date: @week_start).destroy_all
  end

  # 今週の完了済み振り返りを作る（AI分析の記録は作らない）
  def create_completed_reflection(completed_at:, ai_skipped_at: nil)
    @user.weekly_reflections.create!(
      week_start_date:      @week_start,
      week_end_date:        @week_start + 6.days,
      direct_reason:        "残業が続いた",
      background_situation: "優先順位を見直す",
      next_action:          "週3回は定時で帰る",
      completed_at:         completed_at,
      ai_skipped_at:        ai_skipped_at
    )
  end

  # ── ① AIなしで完了 ────────────────────────────────────────────────────────
  test "AIなしで完了すると、上限に達していなくても AI分析ジョブは登録されず、気分スコアも保存される" do
    # 上限に達していない状態（以前はこの状態だとジョブが登録されてしまう可能性があった）
    @user.user_setting&.update_column(:ai_analysis_count, 0)

    assert_no_enqueued_jobs(only: WeeklyReflectionAnalysisJob) do
      post complete_without_ai_weekly_reflections_path, params: {
        direct_reason:        "残業が続いた",
        background_situation: "優先順位を見直す",
        next_action:          "週3回は定時で帰る",
        reflection_comment:   "",
        mood:                 "4"
      }
    end
    assert_response :redirect

    reflection = @user.weekly_reflections.where.not(ai_skipped_at: nil).order(:updated_at).last
    assert reflection, "ai_skipped_at が記録された振り返りがない"
    assert reflection.completed?
    assert_equal 4, reflection.mood
  end

  # ── ② 完了時点で上限に達していた ──────────────────────────────────────────
  test "通常の完了でも、月の上限に達していれば ai_skipped_at が記録される" do
    setting = @user.user_setting
    skip "user_setting が fixtures に無いため省略" unless setting
    setting.update_column(:ai_analysis_count, setting.ai_analysis_monthly_limit)

    reflection = WeeklyReflection.find_or_build_for_current_week(@user)
    reflection.assign_attributes(
      direct_reason:        "残業が続いた",
      background_situation: "優先順位を見直す",
      next_action:          "週3回は定時で帰る"
    )

    assert_no_enqueued_jobs(only: WeeklyReflectionAnalysisJob) do
      result = WeeklyReflectionCompleteService.new(
        reflection: reflection, user: @user, was_locked: false
      ).call
      assert result[:success]
    end
    assert reflection.reload.ai_skipped?
  end

  # ── ③ 振り返り一覧のバナー ────────────────────────────────────────────────
  test "振り返り一覧: AIなしで完了した週は「AI分析なしで完了」を表示し、分析中は表示しない" do
    create_completed_reflection(completed_at: 1.minute.ago, ai_skipped_at: 1.minute.ago)
    get weekly_reflections_path
    assert_response :success
    assert_select "[data-testid='ai-banner-skipped']", count: 1
    assert_select "[data-testid='ai-banner-pending']", count: 0
    assert_select "[data-testid='ai-banner-unavailable']", count: 0
  end

  test "振り返り一覧: 完了から30分以内で結果が無ければ「分析中」を表示する" do
    create_completed_reflection(completed_at: 5.minutes.ago)
    get weekly_reflections_path
    assert_response :success
    assert_select "[data-testid='ai-banner-pending']", count: 1
    assert_select "[data-testid='ai-banner-skipped']", count: 0
  end

  test "振り返り一覧: 30分たっても結果が無ければ「結果を用意できませんでした」を表示する" do
    create_completed_reflection(completed_at: 2.hours.ago)
    get weekly_reflections_path
    assert_response :success
    assert_select "[data-testid='ai-banner-unavailable']", count: 1
    assert_select "[data-testid='ai-banner-pending']", count: 0
  end

  # ── ④ ダッシュボードのバナー ──────────────────────────────────────────────
  test "ダッシュボード: AIなしで完了した週は「分析中」を表示しない" do
    create_completed_reflection(completed_at: 1.minute.ago, ai_skipped_at: 1.minute.ago)
    get dashboard_path
    assert_response :success
    assert_select "[data-testid='reflection-analysis-pending']", count: 0
  end

  test "ダッシュボード: 30分たっても結果が無ければ「分析中」を表示しない" do
    create_completed_reflection(completed_at: 2.hours.ago)
    get dashboard_path
    assert_response :success
    assert_select "[data-testid='reflection-analysis-pending']", count: 0
  end

  test "ダッシュボード: 完了から30分以内で結果が無ければ「分析中」を表示する" do
    create_completed_reflection(completed_at: 5.minutes.ago)
    get dashboard_path
    assert_response :success
    assert_select "[data-testid='reflection-analysis-pending']", count: 1
  end
end