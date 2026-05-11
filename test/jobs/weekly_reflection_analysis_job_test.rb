# test/jobs/weekly_reflection_analysis_job_test.rb
#
# WeeklyReflectionAnalysisJob テスト（E-1追加: UserPurpose 5フィールド必須化対応）
#
# 【E-1追加での変更内容】
#   「PMVVが存在する場合は...」テスト内の UserPurpose.create! に
#   mission / value / current_situation を追加する。

require "test_helper"

class WeeklyReflectionAnalysisJobTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      name:                  "テストユーザー",
      email:                 "test_job_#{SecureRandom.hex(4)}@example.com",
      password:              "password",
      password_confirmation: "password",
      first_login_at:        1.month.ago
    )

    @user_setting = @user.user_setting

    week_start = Date.new(2026, 4, 20)
    @reflection = WeeklyReflection.create!(
      user:                 @user,
      week_start_date:      week_start,
      week_end_date:        week_start + 6.days,
      direct_reason:        "残業が多かった",
      background_situation: "朝の時間を活用する",
      next_action:          "朝型に切り替える",
      reflection_comment:   "来週は改善したい"
    )
    @reflection.complete!
  end

  test "AI分析が成功するとAiAnalysisレコードが作成される" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      assert_difference "AiAnalysis.count", 1 do
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end

    mock_client.verify

    analysis = AiAnalysis.order(:created_at).last
    assert_equal @reflection.id,     analysis.weekly_reflection_id
    assert_equal "weekly_reflection", analysis.analysis_type
    assert_equal "テスト分析コメント", analysis.analysis_comment
    assert_equal true,               analysis.is_latest
    assert_not_nil                   analysis.input_snapshot
    assert_not_nil                   analysis.actions_json
  end

  test "AI分析が成功するとai_analysis_countがインクリメントされる" do
    initial_count = @user_setting.ai_analysis_count

    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
    end

    mock_client.verify

    @user_setting.reload
    assert_equal initial_count + 1, @user_setting.ai_analysis_count
  end

  test "PMVVが存在する場合はinput_snapshotにPMVV情報が含まれる" do
    # ── E-1追加: mission / value / current_situation を追加 ──────────────
    #
    # 【変更理由】
    #   UserPurpose の5フィールドが presence: true になったため、
    #   mission / value / current_situation がないと create! でエラーになる。
    user_purpose = UserPurpose.create!(
      user:              @user,
      purpose:           "家族との時間を大切にしたい",
      mission:           "毎朝の習慣を身につける",          # E-1追加
      vision:            "毎朝6時に起きられる自分",
      value:             "家族との夕食は削らない",           # E-1追加
      current_situation: "夜11時に寝ているが睡眠の質が悪い", # E-1追加
      is_active:         true,
      analysis_state:    :completed
    )
    # ────────────────────────────────────────────────────────────────────────

    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
    end

    mock_client.verify

    analysis = AiAnalysis.order(:created_at).last
    assert_not_nil analysis.input_snapshot["user_purpose"]
    assert_equal   user_purpose.id, analysis.input_snapshot["user_purpose"]["id"]
  end

  test "PMVVが存在しなくても正常に動作する" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      assert_difference "AiAnalysis.count", 1 do
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end

    mock_client.verify

    analysis = AiAnalysis.order(:created_at).last
    assert_nil analysis.input_snapshot["user_purpose"]
  end

  test "AIがnilを返した場合はAiAnalysisが作成されない" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, nil, [String])

    AiClient.stub(:new, mock_client) do
      assert_no_difference "AiAnalysis.count" do
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end

    mock_client.verify

    @user_setting.reload
    assert_equal 0, @user_setting.ai_analysis_count
  end

  test "月次上限に達している場合はAI分析がスキップされる" do
    @user_setting.update!(
      ai_analysis_count:         10,
      ai_analysis_monthly_limit: 10
    )

    AiClient.stub(:new, -> { raise "AiClient が呼ばれるべきではありません" }) do
      assert_no_difference "AiAnalysis.count" do
        WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
      end
    end
  end

  test "WeeklyReflectionが存在しない場合はジョブが静かに終了する" do
    assert_nothing_raised do
      WeeklyReflectionAnalysisJob.perform_now(999_999_999)
    end
  end

  test "input_snapshotに振り返りの全フィールドが含まれる" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:analyze, success_response, [String])

    AiClient.stub(:new, mock_client) do
      WeeklyReflectionAnalysisJob.perform_now(@reflection.id)
    end

    mock_client.verify

    analysis = AiAnalysis.order(:created_at).last
    snapshot = analysis.input_snapshot

    assert_equal @reflection.id.to_s,    snapshot["weekly_reflection_id"].to_s
    assert_equal "残業が多かった",        snapshot["direct_reason"]
    assert_equal "朝の時間を活用する",    snapshot["background_situation"]
    assert_equal "朝型に切り替える",      snapshot["next_action"]
    assert_not_nil                       snapshot["analyzed_at"]
  end

  private

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

    { text: json_body, model: "gemini-2.5-flash" }
  end
end
