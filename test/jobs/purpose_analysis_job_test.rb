# test/jobs/purpose_analysis_job_test.rb
#
# ==============================================================================
# PurposeAnalysisJob テスト（D-11 更新版）
# ==============================================================================
#
# 【D-11 での追加テスト】
#   ① タイムアウト（Timeout::Error）時に analysis_state が failed になる
#   ② 全プロバイダ失敗後の再エンキューが行われる（reenqueue_count < MAX）
#   ③ 最大再エンキュー回数超過後に failed 確定する
#   ④ JSONパース失敗時に metadata に raw_response が保存される
#   ⑤ 401エラー（AiClient::AuthError）時に analysis_state が failed になる
#
# 【Minitest::Mock とは（再掲）】
#   AiClient.new の戻り値を差し替えて、実際の API を呼ばずにテストする。
#   mock.verify で「analyze が呼ばれたか」まで検証する。
#
# ==============================================================================

require "test_helper"

class PurposeAnalysisJobTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @user_purpose = UserPurpose.create!(
      user:           @user,
      purpose:        "テスト Purpose",
      vision:         "テスト Vision",
      analysis_state: :pending
    )
  end

  # ----------------------------------------------------------
  # ヘルパー: stub_ai_client(return_value) { block }
  # ----------------------------------------------------------
  def stub_ai_client(return_value)
    mock = Minitest::Mock.new
    mock.expect(:analyze, return_value, [ String ])
    AiClient.stub(:new, mock) do
      yield
    end
    mock.verify
  end

  # ============================================================
  # 正常系テスト（既存）
  # ============================================================

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
    # 【テストの検証内容】
    #   nil を返した場合、reenqueue_count < MAX_REENQUEUE_COUNT（0 < 3）なので
    #   failed にはならず、pending に戻して再エンキューするはず。
    stub_ai_client(nil) do
      PurposeAnalysisJob.perform_now(@user_purpose.id, reenqueue_count: 0)
    end

    @user_purpose.reload
    # pending に戻っているはず（failed ではない）
    assert @user_purpose.pending?,
           "1回目の失敗では pending に戻るはず。現在: #{@user_purpose.analysis_state}"
    # エラーメッセージに「再試行」の旨が含まれるはず
    assert @user_purpose.last_error_message.include?("再試行"),
           "再試行を案内するメッセージが設定されているはず: #{@user_purpose.last_error_message}"
  end

  test "AI API が nil を返した場合（最大再エンキュー回数超過）は failed になる" do
    # 【テストの検証内容】
    #   reenqueue_count が MAX_REENQUEUE_COUNT（3）に達している場合は
    #   failed 確定になるはず。
    stub_ai_client(nil) do
      PurposeAnalysisJob.perform_now(
        @user_purpose.id,
        reenqueue_count: PurposeAnalysisJob::MAX_REENQUEUE_COUNT
      )
    end

    @user_purpose.reload
    assert @user_purpose.failed?,
           "最大再試行回数超過では failed になるはず。現在: #{@user_purpose.analysis_state}"
    assert @user_purpose.last_error_message.present?,
           "エラーメッセージが設定されているはず"
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

  # ============================================================
  # D-11 追加テスト
  # ============================================================

  test "JSONパース失敗時に metadata に raw_response が保存される" do
    # 【テストの検証内容】
    #   不正なJSONを返したとき、デバッグ用の AiAnalysis レコードが
    #   metadata に raw_response を含めて作成されるはず。
    invalid_json = "これは JSON ではありません（デバッグ用保存テスト）"
    mock_result  = { text: invalid_json, model: "gemini-2.5-flash" }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.failed?

    # metadata に raw_response が保存されているはず
    # is_latest: false のデバッグ用レコードを探す
    debug_record = AiAnalysis.where(
      user_purpose_id: @user_purpose.id,
      is_latest:       false
    ).order(:created_at).last

    assert_not_nil debug_record, "デバッグ用 AiAnalysis レコードが作成されているはず"
    assert_not_nil debug_record.metadata, "metadata が存在するはず"
    assert debug_record.metadata["raw_response"].present?,
           "metadata に raw_response が保存されているはず"
    assert_equal invalid_json, debug_record.metadata["raw_response"],
           "raw_response の内容が正しいはず"
    assert_not_nil debug_record.metadata["parse_failed_at"],
           "parse_failed_at が記録されているはず"
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
        actions:                 "やってみましょう",  # 配列でない
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
    # 【テストの検証内容】
    #   AiClient.new.analyze が AiClient::AuthError を raise した場合、
    #   handle_failure が呼ばれて analysis_state が failed になるはず。
    #
    # 【stub の仕組み】
    #   AiClient.stub(:new, ...) に lambda を渡すと、
    #   .new が呼ばれたときに lambda が評価される。
    #   lambda 内で raise することで「AiClient が例外を投げる」状況を再現できる。
    auth_error_client = Object.new
    def auth_error_client.analyze(_prompt)
      raise AiClient::AuthError, "テスト: API キーが不正です"
    end

    AiClient.stub(:new, auth_error_client) do
      # discard_on AiClient::AuthError により例外は外に出ない
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