# test/integration/ai_throttle_release_test.rb
require "test_helper"

# ==============================================================================
# AI の連打防止（throttle_ai_request）が、AI に送らなかったときに元に戻ることのテスト
# ==============================================================================
#
# 【確かめたい不具合】
#   連打防止は、保存の「前」に「AI へのリクエストを受け付けた時刻」を記録する。
#   そのため、入力が足りなくて保存できなかったときにも時刻が残り、
#   入力を直して 1 分以内に送り直すと「少し待ってください」と止められていた。
#
# 【このテストで確かめること】
#   ・保存に失敗したとき / AI の月の上限で止まったときは、時刻が元の値に戻る
#   ・入力を直せば、すぐに送り直して保存できる
#   ・保存に成功したときは、今までどおり時刻が記録される（連打防止の役目は残っている）
class AiThrottleReleaseTest < ActionDispatch::IntegrationTest
  # PMVV を保存すると AI 分析ジョブが入る。
  # ActiveJob::TestHelper を入れると、ジョブは「入った」ことだけ記録され、実際には動かない。
  include ActiveJob::TestHelper

  # 振り返りのテストは、既存のテスト（weekly_reflections_controller_test.rb）と同じ日時で行う
  TEST_TIME = "2026-02-22 10:00:00".freeze

  setup do
    @user = users(:one)
    log_in_as(@user)

    # 前のテストの影響で連打防止に引っかからないよう、記録された時刻をクリアしておく
    @user.user_setting.update_columns(last_ai_requested_at: nil)

    # pmvv_analysis_flow_test.rb と同じ準備（既存の PMVV を無効にしておく）
    @user.user_purposes.update_all(is_active: false)
  end

  # 振り返りの入力（必須の3項目を含む）。overrides で一部だけ差し替えられる
  def valid_reflection_params(overrides = {})
    {
      reflection_comment:   "今週も頑張った",
      direct_reason:        "残業が多かった",
      background_situation: "朝型に切り替える",
      next_action:          "他の習慣にも広げる"
    }.merge(overrides)
  end

  # PMVV の入力。overrides で一部だけ差し替えられる
  def valid_pmvv_params(overrides = {})
    {
      purpose:           "健康でいきいきと長生きすること",
      mission:           "毎日体を動かす習慣を身につけること",
      vision:            "1年後、体力がついて疲れにくい自分になっている",
      value:             "家族との時間を何より大切にする",
      current_situation: "最近は運動不足で階段でも息が切れる"
    }.merge(overrides)
  end

  # DB に保存されている「連打防止の時刻」を読み直して返す
  # （reload しないと、テストの中で持っている古い値のままになるため）
  def last_ai_requested_at
    @user.user_setting.reload.last_ai_requested_at
  end

  # ============================================================
  # 振り返り（weekly_reflections#create）
  # ============================================================

  test "振り返り：必須の欄が空で保存に失敗したときは、時刻が記録されず、すぐに送り直せる" do
    travel_to Time.zone.parse(TEST_TIME) do
      # 1回目：必須の direct_reason が空なので保存に失敗する
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params(direct_reason: "")
      }
      assert_response 422
      assert_nil last_ai_requested_at, "保存に失敗したのに、連打防止の時刻が残っている"

      # 2回目：入力を直して、すぐに（同じ時刻に）送り直すと保存できる
      assert_difference "WeeklyReflection.count", 1 do
        post weekly_reflections_path, params: {
          weekly_reflection: valid_reflection_params
        }
      end
      assert_redirected_to weekly_reflections_path
    end
  end

  test "振り返り：保存に失敗したときは、記録する前の時刻に戻る" do
    travel_to Time.zone.parse(TEST_TIME) do
      # 5分前に AI へリクエストしていた、という状態を作る（連打防止には引っかからない）
      previous_at = 5.minutes.ago
      @user.user_setting.update_columns(last_ai_requested_at: previous_at)

      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params(direct_reason: "")
      }

      assert_response 422
      # 「今の時刻」ではなく「5分前」のままになっていること
      assert_equal previous_at.to_i, last_ai_requested_at.to_i
    end
  end

  test "振り返り：AI の月の上限で止まったときは、時刻が記録されない" do
    travel_to Time.zone.parse(TEST_TIME) do
      # 今月の AI 分析の回数を、上限と同じにしておく
      @user.user_setting.update_columns(ai_analysis_count: 3, ai_analysis_monthly_limit: 3)

      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params
      }

      assert_response 422
      assert_nil last_ai_requested_at, "AI に送っていないのに、連打防止の時刻が残っている"
    end
  end

  test "振り返り：保存に成功したときは、今までどおり時刻が記録される" do
    travel_to Time.zone.parse(TEST_TIME) do
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params
      }

      assert_redirected_to weekly_reflections_path
      # 連打防止の役目は残っている（成功したときは、その時刻が記録される）
      assert_equal Time.current.to_i, last_ai_requested_at.to_i
    end
  end

  # ============================================================
  # PMVV（user_purposes#create / #update）
  # ============================================================

  test "PMVV 登録：保存に失敗したときは、時刻が記録されず、すぐに送り直せる" do
    # 1回目：purpose が空なので保存に失敗する
    post user_purpose_path, params: { user_purpose: valid_pmvv_params(purpose: "") }
    assert_response 422
    assert_nil last_ai_requested_at, "保存に失敗したのに、連打防止の時刻が残っている"

    # 2回目：入力を直して、すぐに送り直すと保存できる
    assert_difference "UserPurpose.count", 1 do
      post user_purpose_path, params: { user_purpose: valid_pmvv_params }
    end
    assert_redirected_to user_purpose_path
  end

  test "PMVV 更新：保存に失敗したときは、時刻が記録されない" do
    patch user_purpose_path, params: { user_purpose: valid_pmvv_params(purpose: "") }

    assert_response 422
    assert_nil last_ai_requested_at, "保存に失敗したのに、連打防止の時刻が残っている"
  end
end
