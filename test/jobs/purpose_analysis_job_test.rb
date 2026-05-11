# test/jobs/purpose_analysis_job_test.rb
#
# PurposeAnalysisJob テスト（E-1追加: UserPurpose 5フィールド必須化対応）
#
# 【E-1追加での変更内容】
#   UserPurpose の mission / value / current_situation が presence: true になったため、
#   setup の UserPurpose.create! にこれら3フィールドを追加する。

require "test_helper"

class PurposeAnalysisJobTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)

    # ── E-1追加: mission / value / current_situation を追加 ──────────────
    #
    # 【変更理由】
    #   UserPurpose の5フィールドが presence: true になったため、
    #   mission / value / current_situation がないと create! でエラーになる。
    @user_purpose = UserPurpose.create!(
      user:              @user,
      purpose:           "テスト Purpose",
      mission:           "テスト Mission",           # E-1追加
      vision:            "テスト Vision",
      value:             "テスト Value",             # E-1追加
      current_situation: "テスト Current Situation", # E-1追加
      analysis_state:    :pending
    )
    # ────────────────────────────────────────────────────────────────────────
  end

  def stub_ai_client(return_value)
    mock = Minitest::Mock.new
    mock.expect(:analyze, return_value, [ String ])
    AiClient.stub(:new, mock) do
      yield
    end
    mock.verify
  end

  test "AI API が成功した場合に analysis_state が completed になる" do
    mock_result = {
      text:  {
        analysis_comment:        "テスト分析コメント",
        root_cause:              "テスト根本原因",
        coaching_message:        "テストコーチングメッセージ",
        improvement_suggestions: "テスト改善提案",
        actions: [
          { type: "habit", title: "テスト習慣", description: "説明", frequency: "毎日", priority: "must" }
        ],
        crisis_detected: false
      }.to_json,
      model: "gemini-2.5-flash"
    }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.completed?,
           "analysis_state が completed になっているはず。現在: #{@user_purpose.analysis_state}"
    assert_nil @user_purpose.last_error_message

    ai_analysis = AiAnalysis.find_by(user_purpose: @user_purpose, is_latest: true)
    assert_not_nil ai_analysis
    assert_equal "テスト分析コメント", ai_analysis.analysis_comment
    assert ai_analysis.is_latest
  end

  test "AI API が nil を返した場合（全プロバイダ失敗1回目）は再エンキューされる" do
    stub_ai_client(nil) do
      PurposeAnalysisJob.perform_now(@user_purpose.id, reenqueue_count: 0)
    end

    @user_purpose.reload
    assert @user_purpose.pending?,
           "1回目の失敗では pending に戻るはず。現在: #{@user_purpose.analysis_state}"
    assert @user_purpose.last_error_message.include?("再試行"),
           "再試行を案内するメッセージが設定されているはず: #{@user_purpose.last_error_message}"
  end

  test "AI API が nil を返した場合（最大再エンキュー回数超過）は failed になる" do
    stub_ai_client(nil) do
      PurposeAnalysisJob.perform_now(
        @user_purpose.id,
        reenqueue_count: PurposeAnalysisJob::MAX_REENQUEUE_COUNT
      )
    end

    @user_purpose.reload
    assert @user_purpose.failed?,
           "最大再試行回数超過では failed になるはず。現在: #{@user_purpose.analysis_state}"
    assert @user_purpose.last_error_message.present?
  end

  test "存在しない user_purpose_id の場合はジョブが破棄される" do
    assert_nothing_raised do
      PurposeAnalysisJob.perform_now(999_999)
    end
  end

  test "AI API が不正な JSON を返した場合に analysis_state が failed になる" do
    mock_result = { text: "これは JSON ではありません", model: "gemini-2.5-flash" }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.failed?, "analysis_state が failed になっているはず"
  end

  test "JSONパース失敗時に metadata に raw_response が保存される" do
    invalid_json = "これは JSON ではありません（デバッグ用保存テスト）"
    mock_result  = { text: invalid_json, model: "gemini-2.5-flash" }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.failed?

    debug_record = AiAnalysis.where(
      user_purpose_id: @user_purpose.id,
      is_latest:       false
    ).order(:created_at).last

    assert_not_nil debug_record
    assert_not_nil debug_record.metadata
    assert debug_record.metadata["raw_response"].present?
    assert_equal invalid_json, debug_record.metadata["raw_response"]
    assert_not_nil debug_record.metadata["parse_failed_at"]
  end

  test "AI が JSON の前後に文章を含む場合でも正常に動作する" do
    json_body = {
      analysis_comment:        "テスト分析コメント",
      root_cause:              "テスト根本原因",
      coaching_message:        "テストコーチングメッセージ",
      improvement_suggestions: "テスト改善提案",
      actions: [
        { type: "habit", title: "テスト習慣", description: "説明", frequency: "毎日", priority: "must" }
      ],
      crisis_detected: false
    }.to_json

    mock_result = {
      text:  "はい、分析結果です。\n#{json_body}\n\n以上です。",
      model: "gemini-2.5-flash"
    }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.completed?,
           "前後に文章があっても completed になるはず。現在: #{@user_purpose.analysis_state}"
  end

  test "AI が actions を配列以外で返した場合に analysis_state が failed になる" do
    mock_result = {
      text: {
        analysis_comment:        "コメント",
        root_cause:              "原因",
        coaching_message:        "メッセージ",
        improvement_suggestions: "提案",
        actions:                 "やってみましょう",
        crisis_detected:         false
      }.to_json,
      model: "gemini-2.5-flash"
    }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.failed?
  end

  test "AiClient::AuthError が発生した場合に analysis_state が failed になる" do
    auth_error_client = Object.new
    def auth_error_client.analyze(_prompt)
      raise AiClient::AuthError, "テスト: API キーが不正です"
    end

    AiClient.stub(:new, auth_error_client) do
      assert_nothing_raised do
        PurposeAnalysisJob.perform_now(@user_purpose.id)
      end
    end

    @user_purpose.reload
    assert @user_purpose.failed?,
           "AuthError 時は analysis_state が failed になるはず。現在: #{@user_purpose.analysis_state}"
    assert @user_purpose.last_error_message.include?("接続できません"),
           "認証エラーのメッセージが設定されているはず: #{@user_purpose.last_error_message}"
  end
end
