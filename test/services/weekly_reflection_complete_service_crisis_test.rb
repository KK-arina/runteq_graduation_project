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
      next_action:          "何もわからない",            # E-1追加: presence必須化のため空文字不可
      reflection_comment:   "今週はとてもつらかった",  # E-1 追加: presence: true 対応
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
      background_situation: "朝型に切り替えたい",                  # E-1追加: presence必須化のため空文字不可
      next_action:          "来週から実践する",                    # E-1追加: presence必須化のため空文字不可
      reflection_comment:   "今週を振り返って前向きに取り組めた", # E-1 追加
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

  # ============================================================
  # I-1 追加: 危機検出時のジョブ抑制と記録内容の詳細検証
  # ============================================================

  # 【なぜ UpdateAiProfileJob も検証するのか】
  #   危機検出時、サービスは enqueue_analysis_job_if_eligible を通らない設計。
  #   そのため AI分析ジョブだけでなく、その中で呼ばれる
  #   AIプロファイル更新ジョブ(UpdateAiProfileJob)も一緒に抑制される。
  #   この「巻き添え抑制」が保たれていることを確認する。
  test "危機ワード検出時は UpdateAiProfileJob もエンキューされない" do
    assert_no_enqueued_jobs(only: UpdateAiProfileJob) do
      WeeklyReflectionCompleteService.new(
        reflection: @reflection,
        user:       @user,
        was_locked: false
      ).call
    end
  end

  # 【なぜ記録の中身まで検証するのか】
  #   crisis_detected: true だけでなく、あとから運営が追跡・集計できるよう
  #   「最新フラグ(is_latest)」「分析種別(weekly_reflection)」
  #   「prompt_version が crisis_skip」であることまで固定する。
  test "危機時に作成される AiAnalysis の中身が正しい" do
    WeeklyReflectionCompleteService.new(
      reflection: @reflection,
      user:       @user,
      was_locked: false
    ).call

    ai = AiAnalysis.order(created_at: :desc).first
    assert ai.crisis_detected,                       "crisis_detected は true"
    assert ai.is_latest,                             "is_latest は true（最新分析として記録）"
    assert_equal "weekly_reflection", ai.analysis_type,  "分析種別は weekly_reflection"
    assert_equal "crisis_skip",       ai.prompt_version, "prompt_version は crisis_skip"
  end
end
