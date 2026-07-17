# test/integration/pmvv_analysis_flow_test.rb
#
# ==============================================================================
# PMVV入力 → AI分析 → ダッシュボード反映フロー統合テスト（I-1）
# ==============================================================================
#
# 【このテストの役割】
#   PMVV目標の入力(create/update)が
#     ① UserPurpose を保存し ② 旧版を無効化し（バージョン管理）
#     ③ PurposeAnalysisJob を投入する（危機ワード時はスキップして failed 記録）
#   ことと、AI分析結果の提案を apply_proposals で
#     ④ 習慣・タスクとしてダッシュボードに反映する
#   ことを検証する。
#
#   ※ 「AI分析結果 → 完了バナーのダッシュボード表示」は
#      dashboards_controller_test.rb が既にカバー済みのため、ここでは重複させない。
#   ※ PurposeAnalysisJob 自体の中身は purpose_analysis_job_test.rb がカバー済み。
#      本テストは「ジョブが投入されること」までを担保する（AIの実行はしない）。
#
# 【throttle_ai_request（連打防止）への配慮】
#   create/update/retry_analysis は ApplicationController の throttle_ai_request 対象で、
#   「直近1分以内にAIリクエスト済み」または「pending/analyzing のPMVVが存在」すると
#   redirect_back で弾かれる。そのため各テストは
#     ・last_ai_requested_at を nil にリセット
#     ・既存PMVVは completed 状態にする（pending/analyzing を残さない）
#   ことで、検証対象のリクエストが確実に本処理まで到達するようにしている。
# ==============================================================================
require "test_helper"

class PmvvAnalysisFlowTest < ActionDispatch::IntegrationTest
  # assert_enqueued_with / assert_no_enqueued_jobs を使うために必要
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    log_in_as(@user)

    # throttle 対策: 直近リクエスト時刻をクリアし、既存PMVVを一旦すべて無効化する
    @user.user_setting.update_columns(last_ai_requested_at: nil)
    @user.user_purposes.update_all(is_active: false)
  end

  # 有効なPMVVパラメータ（overrides で一部だけ差し替え可能）
  def valid_pmvv_params(overrides = {})
    {
      purpose:           "健康でいきいきと長生きすること",
      mission:           "毎日体を動かす習慣を身につけること",
      vision:            "1年後、体力がついて疲れにくい自分になっている",
      value:             "家族との時間を何より大切にする",
      current_situation: "最近は運動不足で階段でも息が切れる"
    }.merge(overrides)
  end

  # ============================================================
  # 入力(create) → AI分析ジョブ投入
  # ============================================================

  test "create: UserPurposeを保存しpending・旧版を無効化・PurposeAnalysisJobを投入する" do
    # 旧版（有効・完了済み）を1件用意 → 新規作成で「無効化される」ことを確認する
    old = @user.user_purposes.create!(
      valid_pmvv_params.merge(version: 1, is_active: true, analysis_state: :completed)
    )

    # AIジョブが投入され、UserPurpose が1件増えることを同時に確認する
    assert_enqueued_with(job: PurposeAnalysisJob) do
      assert_difference "@user.user_purposes.count", 1 do
        post user_purpose_path, params: { user_purpose: valid_pmvv_params }
      end
    end

    assert_redirected_to user_purpose_path

    new_purpose = UserPurpose.current_for(@user)
    assert new_purpose.pending?,             "新しいPMVVは pending 状態"
    assert new_purpose.is_active,            "新しいPMVVは有効"
    assert_not_equal old.id, new_purpose.id, "既存更新ではなく新レコードが作られる"
    assert_not old.reload.is_active,         "旧版は無効化される"
  end

  test "create(危機ワード検出): ジョブは投入されず failed・危機分析を記録し flash[:crisis] が立つ" do
    # current_situation に危機ワード（CRISIS_KEYWORDS の「消えてしまいたい」）を含める
    assert_no_enqueued_jobs(only: PurposeAnalysisJob) do
      assert_difference "AiAnalysis.count", 1 do
        post user_purpose_path, params: {
          user_purpose: valid_pmvv_params(current_situation: "もう消えてしまいたい")
        }
      end
    end

    assert flash[:crisis],           "危機検出時は flash[:crisis] が立つ"
    assert_redirected_to user_purpose_path

    purpose = UserPurpose.current_for(@user)
    assert purpose.failed?,          "危機時は analysis_state=failed になる"

    ai = AiAnalysis.order(created_at: :desc).first
    assert ai.crisis_detected,                        "crisis_detected は true"
    assert_equal "purpose_breakdown", ai.analysis_type, "PMVV分析として記録される"
    assert_equal "crisis_skip",       ai.prompt_version
    assert ai.is_latest
  end

  # ============================================================
  # 更新(update) → バージョン管理（新レコード作成＋旧版無効化）
  # ============================================================

  test "update: 新レコードを作成し旧版を無効化して current_for が最新内容を返す" do
    old = @user.user_purposes.create!(
      valid_pmvv_params.merge(version: 1, is_active: true, analysis_state: :completed)
    )

    assert_enqueued_with(job: PurposeAnalysisJob) do
      assert_difference "@user.user_purposes.count", 1 do
        patch user_purpose_path, params: {
          user_purpose: valid_pmvv_params(purpose: "更新後のPurpose")
        }
      end
    end

    assert_redirected_to user_purpose_path

    current = UserPurpose.current_for(@user)
    assert_equal "更新後のPurpose", current.purpose, "current_for が更新後の内容を返す"
    assert_not_equal old.id, current.id,            "更新は新レコード作成として実装されている"
    assert_not old.reload.is_active,                "旧版は無効化される"
  end

  # ============================================================
  # apply_proposals → 提案をダッシュボードへ反映（習慣・タスク作成）
  # ============================================================

  test "apply_proposals: 選択した提案から習慣・タスクを作成しダッシュボードへ遷移する" do
    purpose = @user.user_purposes.create!(
      valid_pmvv_params.merge(version: 1, is_active: true, analysis_state: :completed)
    )
    # purpose_breakdown 分析は input_snapshot に5キー必須（D-9スキーマ検証）
    AiAnalysis.create!(
      user_purpose_id: purpose.id,
      analysis_type:   :purpose_breakdown,
      is_latest:       true,
      input_snapshot:  valid_pmvv_params,   # 5キーを満たす
      actions_json: [
        { "type" => "habit", "title" => "朝ジョギング", "frequency" => "週3回" },
        { "type" => "task",  "title" => "ランニングシューズを買う", "priority" => "must" }
      ]
    )

    # 習慣・タスクがそれぞれ1件ずつ増える
    assert_difference [ "@user.habits.count", "@user.tasks.count" ], 1 do
      post apply_proposals_user_purpose_path, params: {
        habit_indices: [ "0" ],
        task_indices:  [ "0" ]
      }
    end

    assert_redirected_to dashboard_path

    habit = @user.habits.order(:created_at).last
    assert_equal "朝ジョギング", habit.name
    assert_equal 3, habit.weekly_target, "『週3回』が weekly_target=3 に変換される"
    assert habit.check_type?,            "AI提案の習慣はチェック型で作成される"

    task = @user.tasks.where(ai_generated: true).order(:created_at).last
    assert_equal "ランニングシューズを買う", task.title
    assert task.must?,         "priority=must で作成される"
    assert task.improve?,      "AI提案タスクは task_type=improve"
    assert task.ai_generated?, "AI提案タスクは ai_generated=true"
  end
end