# test/jobs/purpose_analysis_job_test.rb
#
# ==============================================================================
# PurposeAnalysisJob テスト（Minitest::Mock 版）
# ==============================================================================
#
# 【Minitest::Mock とは】
#   Rails 標準の Minitest に組み込まれているモックライブラリ。
#   RSpec の double に相当する。
#
# 【Minitest::Mock の使い方】
#   mock = Minitest::Mock.new
#   mock.expect :メソッド名, 戻り値, [引数の型]
#   # expect: 「このメソッドがこの引数で呼ばれたらこの値を返す」と宣言する
#
#   mock.verify
#   # verify: expect で宣言したメソッドが実際に呼ばれたか検証する
#   # 呼ばれていない場合はテスト失敗になる → テストの信頼性が上がる
#
# 【Object#stub との違い】
#   Object#stub: 「呼ばれたら返す」だけで、呼ばれたかどうかは検証しない
#   Minitest::Mock: 「呼ばれたか・引数は正しいか」まで検証する
#
# 【AiClient.stub(:new, mock) の仕組み】
#   AiClient.new が呼ばれたときに mock オブジェクトを返す。
#   ブロックを抜けると元の AiClient.new に戻る（テスト間の汚染なし）。
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
  # 【役割】
  #   AiClient.new が呼ばれたときに、指定した値を返す偽クライアントを
  #   ブロックスコープ内だけで使えるようにする。
  #
  # 【Minitest::Mock を使う理由（Object#define_singleton_method との違い）】
  #   Object#define_singleton_method 版:
  #     analyze が呼ばれなくても（Job が途中でリターンしても）テストは通る
  #     → テストが「分析APIが呼ばれた」ことを保証できない
  #
  #   Minitest::Mock 版:
  #     mock.verify でブロック終了時に「analyzeが呼ばれたか」を検証する
  #     → 呼ばれていなければテスト失敗 → テストの信頼性が高い
  #
  # 【引数: [String]】
  #   mock.expect :analyze, return_value, [String] の第3引数は
  #   「期待する引数の型の配列」。
  #   analyze にはプロンプト文字列が渡されるため String を指定する。
  #   型が違う引数が渡されたら MockExpectationError でテスト失敗する。
  def stub_ai_client(return_value)
    mock = Minitest::Mock.new
    # expect: analyze が String 引数で呼ばれたら return_value を返す
    mock.expect(:analyze, return_value, [ String ])

    # AiClient.stub(:new, mock): AiClient.new が mock を返すようにする
    AiClient.stub(:new, mock) do
      yield  # ブロック（テストの本体）を実行する
    end

    # verify: expect で宣言したメソッドが実際に呼ばれたか検証する
    # analyze が呼ばれていなければここでテスト失敗する
    mock.verify
  end

  # ----------------------------------------------------------
  # nil を返す場合専用のヘルパー
  # ----------------------------------------------------------
  # 【なぜ別メソッドか】
  #   nil を返すケース（全プロバイダ失敗）では Job が早期リターンするため
  #   analyze は呼ばれるが後続の処理は走らない。
  #   通常の stub_ai_client と同じ検証で問題ない。
  def stub_ai_client_nil
    stub_ai_client(nil) { yield }
  end

  # ============================================================
  # 正常系テスト
  # ============================================================

  test "AI API が成功した場合に analysis_state が completed になる" do
    mock_result = {
      text:  {
        analysis_comment:        "テスト分析コメント",
        root_cause:              "テスト根本原因",
        coaching_message:        "テストコーチングメッセージ",
        improvement_suggestions: "テスト改善提案",
        actions:         [
          { type: "habit", title: "テスト習慣", description: "説明", frequency: "毎日", priority: "must" }
        ],
        crisis_detected: false
      }.to_json,
      model: "gemini-2.0-flash"
    }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.completed?,
           "analysis_state が completed になっているはず。現在: #{@user_purpose.analysis_state}"
    assert_nil @user_purpose.last_error_message, "エラーメッセージはないはず"

    ai_analysis = AiAnalysis.find_by(user_purpose: @user_purpose)
    assert_not_nil ai_analysis,                          "AiAnalysis レコードが作成されているはず"
    assert_equal "テスト分析コメント", ai_analysis.analysis_comment
    assert_equal "gemini-2.0-flash",   ai_analysis.ai_model_name, "モデル名が正しく保存されているはず"
    assert ai_analysis.is_latest,                        "is_latest=true になっているはず"
  end

  # ============================================================
  # 異常系テスト
  # ============================================================

  test "AI API が nil を返した場合に analysis_state が failed になる" do
    stub_ai_client(nil) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.failed?,                        "analysis_state が failed になっているはず"
    assert @user_purpose.last_error_message.present?,    "エラーメッセージが記録されているはず"
  end

  test "存在しない user_purpose_id の場合はジョブが破棄される" do
    # discard_on ActiveRecord::RecordNotFound により例外がジョブの外に出ない
    # AiClient は呼ばれないので stub 不要
    assert_nothing_raised do
      PurposeAnalysisJob.perform_now(999_999)
    end
  end

  test "AI API が不正な JSON を返した場合に analysis_state が failed になる" do
    mock_result = { text: "これは JSON ではありません", model: "gemini-2.0-flash" }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.failed?, "analysis_state が failed になっているはず"
  end

  test "AI が actions を配列以外で返した場合に analysis_state が failed になる" do
    mock_result = {
      text:  {
        analysis_comment:        "コメント",
        root_cause:              "原因",
        coaching_message:        "メッセージ",
        improvement_suggestions: "提案",
        actions:                 "やってみましょう",  # 配列でない
        crisis_detected:         false
      }.to_json,
      model: "gemini-2.0-flash"
    }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.failed?, "analysis_state が failed になっているはず"
  end

  test "AI が JSON の前後に文章を含む場合でも正常に動作する" do
    json_body = {
      analysis_comment:        "テスト分析コメント",
      root_cause:              "テスト根本原因",
      coaching_message:        "テストコーチングメッセージ",
      improvement_suggestions: "テスト改善提案",
      actions:         [
        { type: "habit", title: "テスト習慣", description: "説明", frequency: "毎日", priority: "must" }
      ],
      crisis_detected: false
    }.to_json

    mock_result = {
      text:  "はい、分析結果です。\n#{json_body}\n\n以上です。",  # 前後に文章
      model: "gemini-2.0-flash"
    }

    stub_ai_client(mock_result) do
      PurposeAnalysisJob.perform_now(@user_purpose.id)
    end

    @user_purpose.reload
    assert @user_purpose.completed?,
           "前後に文章があっても completed になるはず。現在: #{@user_purpose.analysis_state}"
  end
end