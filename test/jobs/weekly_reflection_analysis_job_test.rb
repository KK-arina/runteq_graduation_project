# test/jobs/weekly_reflection_analysis_job_test.rb
#
# ==============================================================================
# WeeklyReflectionAnalysisJob のテスト
# ==============================================================================
# 【テスト方針】
#   Minitest::Mock を使って AiClient をスタブ化する。
#   実際の API は呼ばずに、期待通りの動作をテストする。
#
# 【テスト環境での GoodJob 設定】
#   config/environments/test.rb で queue_adapter = :test に設定されているため
#   perform_later はキューに積まれるだけで実行されない。
#   テストでは perform_now を使って同期実行する。
#
# 【よくある間違い】
#   docker compose exec web bin/rails test ... ← 正しい
#   docker compose exec web rails test ...     ← 間違い（bin/rails を必ず使う）
# ==============================================================================

require "test_helper"

class WeeklyReflectionAnalysisJobTest < ActiveSupport::TestCase
  # ==============================================================
  # テスト前の共通セットアップ
  # ==============================================================
  def setup
    # テスト用ユーザーを作成する
    # SecureRandom.hex(4) でメールアドレスを一意にしてテスト間の衝突を防ぐ
    @user = User.create!(
      name:                  "テストユーザー",
      email:                 "test_job_#{SecureRandom.hex(4)}@example.com",
      password:              "password",
      password_confirmation: "password"
    )

    # user_setting を作成する（AI 利用回数管理に必要）
    @user_setting = UserSetting.create!(
      user:                      @user,
      ai_analysis_count:         0,
      ai_analysis_monthly_limit: 10
    )

    # WeeklyReflection を作成する
    # Date.new で固定日付を使うことで曜日に依存しない安定したテストになる
    week_start = Date.new(2026, 4, 20) # 月曜日
    @reflection = WeeklyReflection.create!(
      user:                 @user,
      week_start_date:      week_start,
      week_end_date:        week_start + 6.days,
      direct_reason:        "残業が多かった",
      background_situation: "朝の時間を活用する",
      next_action:          "朝型に切り替える",
      reflection_comment:   "来週は改善したい"
    )
    # 振り返りを完了状態にする（complete! で completed_at をセット）
    @reflection.complete!
  end

  # ==============================================================
  # 正常系: AI 分析が成功して AiAnalysis が作成される
  # ==============================================================
  test "AI分析が成功するとAiAnalysisレコードが作成される" do
    # Minitest::Mock を作成する
    # expect: 「analyze メソッドが String 引数で呼ばれたら success_response を返す」と定義
    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    # AiClient.new が呼ばれたら mock_client を返すように差し替える
    AiClient.stub(:new, mock_client) do
      # assert_difference: ブロック実行前後で AiAnalysis.count が 1 増えることを確認
      assert_difference "AiAnalysis.count", 1 do
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end

    # mock_client.verify: expect で定義したメソッドが実際に呼ばれたことを確認
    # 呼ばれなかった場合はテスト失敗になる
    mock_client.verify

    # 作成された AiAnalysis の内容を確認する
    analysis = AiAnalysis.order(:created_at).last
    assert_equal @reflection.id,     analysis.weekly_reflection_id
    assert_equal "weekly_reflection", analysis.analysis_type
    assert_equal "テスト分析コメント", analysis.analysis_comment
    assert_equal true,               analysis.is_latest
    assert_not_nil                   analysis.input_snapshot
    assert_not_nil                   analysis.actions_json
  end

  # ==============================================================
  # 正常系: ai_analysis_count がインクリメントされる
  # ==============================================================
  test "AI分析が成功するとai_analysis_countがインクリメントされる" do
    initial_count = @user_setting.ai_analysis_count # 0

    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
    end

    mock_client.verify

    # reload で DB から最新の値を取得して確認する
    # （Ruby オブジェクトのキャッシュではなく実際の DB 値を見る）
    @user_setting.reload
    assert_equal initial_count + 1, @user_setting.ai_analysis_count
  end

  # ==============================================================
  # 正常系: PMVV が存在する場合は input_snapshot に含まれる
  # ==============================================================
  test "PMVVが存在する場合はinput_snapshotにPMVV情報が含まれる" do
    # PMVV を作成する
    user_purpose = UserPurpose.create!(
      user:           @user,
      purpose:        "家族との時間を大切にしたい",
      vision:         "毎朝6時に起きられる自分",
      is_active:      true,
      analysis_state: :completed
    )

    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
    end

    mock_client.verify

    analysis = AiAnalysis.order(:created_at).last
    # input_snapshot に user_purpose キーが含まれていることを確認する
    assert_not_nil analysis.input_snapshot["user_purpose"]
    assert_equal   user_purpose.id, analysis.input_snapshot["user_purpose"]["id"]
  end

  # ==============================================================
  # 正常系: PMVV が存在しない場合でも正常に動作する
  # ==============================================================
  test "PMVVが存在しなくても正常に動作する" do
    # UserPurpose を作成しない状態でジョブを実行する
    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      assert_difference "AiAnalysis.count", 1 do
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end

    mock_client.verify

    analysis = AiAnalysis.order(:created_at).last
    # user_purpose キーが存在しないことを確認する
    assert_nil analysis.input_snapshot["user_purpose"]
  end

  # ==============================================================
  # 正常系: AI が nil を返した場合は AiAnalysis が作成されない
  # ==============================================================
  test "AIがnilを返した場合はAiAnalysisが作成されない" do
    mock_client = Minitest::Mock.new
    # nil を返すスタブ（全プロバイダ失敗 = Gemini + Groq 両方アウトの状態）
    mock_client.expect(:analyze, nil, [String])

    AiClient.stub(:new, mock_client) do
      assert_no_difference "AiAnalysis.count" do
        # nil を返してもジョブは例外を出さず静かに終了する設計
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end

    mock_client.verify

    # ai_analysis_count も増えていないことを確認する
    @user_setting.reload
    assert_equal 0, @user_setting.ai_analysis_count
  end

  # ==============================================================
  # 正常系: 月次上限に達している場合はスキップされる
  # ==============================================================
  test "月次上限に達している場合はAI分析がスキップされる" do
    # 月次上限まで使い切った状態にする（10/10）
    @user_setting.update!(
      ai_analysis_count:         10,
      ai_analysis_monthly_limit: 10
    )

    # AiClient が呼ばれないことを確認する
    # stub の中で例外を投げることで「もし呼ばれたらテスト失敗」にする
    AiClient.stub(:new, -> { raise "AiClient が呼ばれるべきではありません" }) do
      assert_no_difference "AiAnalysis.count" do
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end
  end

  # ==============================================================
  # 例外系: WeeklyReflection が存在しない場合
  # ==============================================================
  test "WeeklyReflectionが存在しない場合はジョブが静かに終了する" do
    # 【GoodJob 4.x の仕様】
    #   discard_on ActiveRecord::RecordNotFound は perform_now でも機能する。
    #   例外は外に伝播せず、ジョブが静かに破棄される。
    #   そのため「例外が発生しないこと」をテストする。
    assert_nothing_raised do
      WeeklyReflectionAnalysisJob.perform_now(999_999_999)
    end
  end

  # ==============================================================
  # 正常系: input_snapshot に振り返りの全フィールドが含まれる
  # ==============================================================
  test "input_snapshotに振り返りの全フィールドが含まれる" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
    end

    mock_client.verify

    analysis = AiAnalysis.order(:created_at).last
    snapshot = analysis.input_snapshot

    # jsonb はキーが文字列で返ってくるため to_s で比較する
    assert_equal @reflection.id.to_s,    snapshot["weekly_reflection_id"].to_s
    assert_equal "残業が多かった",        snapshot["direct_reason"]
    assert_equal "朝の時間を活用する",    snapshot["background_situation"]
    assert_equal "朝型に切り替える",      snapshot["next_action"]
    assert_not_nil                       snapshot["analyzed_at"]
  end

  private

  # ==============================================================
  # success_response: AI 成功レスポンスのスタブデータ
  # ==============================================================
  # 【なぜ private に置くか】
  #   複数のテストで共通して使うヘルパーメソッドをまとめる。
  #   テストコードの重複を排除して保守性を上げる。
  #
  # 【モデル名について】
  #   ai_client.rb の GEMINI_MODEL 定数と合わせて "gemini-2.5-flash" を使う。
  #   不一致があると将来のデバッグで混乱する原因になる。
  def success_response
    json_body = {
      analysis_comment:        "テスト分析コメント",
      root_cause:              "テスト根本原因",
      coaching_message:        "テストコーチングメッセージ",
      improvement_suggestions: "テスト改善提案",
      actions: [
        { type: "habit", title: "朝の読書",     description: "集中力が上がるため", frequency: "毎日", priority: "must"   },
        { type: "habit", title: "夜の振り返り", description: "翌日の準備ができるため", frequency: "毎日", priority: "should" },
        { type: "habit", title: "週次計画",     description: "優先度が整理できるため", frequency: "週1回", priority: "could" },
        { type: "task",  title: "睡眠環境を整える",     description: "質の高い睡眠のため", priority: "must"   },
        { type: "task",  title: "朝のルーティン設計",   description: "習慣化のため",       priority: "should" },
        { type: "task",  title: "スマホ使用ルール設定", description: "集中力維持のため",   priority: "could"  }
      ],
      crisis_detected: false
    }.to_json

    # ai_client.rb の GEMINI_MODEL = "gemini-2.5-flash" と一致させる
    { text: json_body, model: "gemini-2.5-flash" }
  end
end