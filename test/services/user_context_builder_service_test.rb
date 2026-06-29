# test/services/user_context_builder_service_test.rb
require "test_helper"

class UserContextBuilderServiceTest < ActiveSupport::TestCase
  # include はクラスレベルで宣言する（メソッド内で呼ぶと動作しない）
  include ActiveJob::TestHelper

  setup do
    @user    = users(:one)
    @service = UserContextBuilderService.new(user: @user)
  end

  # ----------------------------------------------------------
  # context_text_for のテスト
  # ----------------------------------------------------------

  test "context_text_for: プロファイルが存在しない場合は空文字を返すこと" do
    @user.ai_user_profile&.destroy
    assert_equal "", UserContextBuilderService.context_text_for(@user)
  end

  test "context_text_for: user が nil の場合は空文字を返すこと" do
    # user.nil? ガードの動作確認
    assert_equal "", UserContextBuilderService.context_text_for(nil)
  end

  test "context_text_for: context_summary が空の場合は空文字を返すこと" do
    AiUserProfile.find_or_initialize_by(user: @user).tap do |p|
      p.context_summary = ""
      p.analyzed_at     = Time.current
      p.save!
    end
    assert_equal "", UserContextBuilderService.context_text_for(@user)
  end

  test "context_text_for: context_summary が存在する場合はその内容を返すこと" do
    expected = "## このユーザーの過去8週間の傾向データ\nテスト用サマリー"
    AiUserProfile.find_or_initialize_by(user: @user).tap do |p|
      p.context_summary = expected
      p.analyzed_at     = Time.current
      p.save!
    end
    assert_equal expected, UserContextBuilderService.context_text_for(@user)
  end

  # ----------------------------------------------------------
  # call のテスト
  # ----------------------------------------------------------

  test "call: データが0件の場合も成功を返すこと" do
    @user.ai_user_profile&.destroy
    result = @service.call
    assert result[:success], "データ0件でも成功を返すべき: #{result[:error]}"
  end

  test "call: 成功したとき AiUserProfile レコードが作成されること" do
    @user.ai_user_profile&.destroy
    assert_difference "AiUserProfile.count", 1 do
      @service.call
    end
  end

  test "call: 2回呼んでも AiUserProfile は1件のみであること" do
    @user.ai_user_profile&.destroy
    @service.call
    @service.call
    assert_equal 1, AiUserProfile.where(user: @user).count,
                 "2回呼んでもプロファイルが重複しないべき"
  end

  test "call: 成功後に analyzed_at が設定されること" do
    @user.ai_user_profile&.destroy
    @service.call
    profile = AiUserProfile.find_by(user: @user)
    assert_not_nil profile.analyzed_at
    assert profile.analyzed_at > 1.minute.ago
  end

  # ----------------------------------------------------------
  # stale? のテスト
  # ----------------------------------------------------------

  test "stale?: analyzed_at が nil のとき true を返すこと" do
    profile = AiUserProfile.find_or_initialize_by(user: @user)
    profile.analyzed_at = nil
    profile.save!(validate: false)
    assert profile.stale?
  end

  test "stale?: analyzed_at が7日以内のとき false を返すこと" do
    profile = AiUserProfile.find_or_initialize_by(user: @user)
    profile.analyzed_at = 6.days.ago
    profile.save!(validate: false)
    assert_not profile.stale?
  end

  test "stale?: analyzed_at が7日以上前のとき true を返すこと" do
    profile = AiUserProfile.find_or_initialize_by(user: @user)
    profile.analyzed_at = 8.days.ago
    profile.save!(validate: false)
    assert profile.stale?
  end

  # ----------------------------------------------------------
  # generate_context_summary のテスト（private メソッドを send で呼ぶ）
  # ----------------------------------------------------------

  test "generate_context_summary: データ0件のとき空文字を返すこと" do
    result = @service.send(:generate_context_summary,
      habit_patterns:    { strong: [], weak: [], all: [] },
      reflection_trends: { completion_count: 0, completion_rate: 0,
                           avg_mood: nil, negative_keywords: [], positive_keywords: [] },
      proposal_adoption: { total_ai_tasks: 0, completed_ai_tasks: 0, adoption_rate: 0 }
    )
    assert_equal "", result
  end

  test "generate_context_summary: 傾向データのヘッダーが含まれること" do
    result = @service.send(:generate_context_summary,
      habit_patterns: {
        strong: [{ name: "読書", rate: 85 }],
        weak:   [],
        all:    [{ name: "読書", rate: 85 }]
      },
      reflection_trends: {
        completion_count: 4, completion_rate: 50,
        avg_mood: 3.5,
        negative_keywords: ["疲れ"],
        positive_keywords: ["達成"]
      },
      proposal_adoption: { total_ai_tasks: 5, completed_ai_tasks: 3, adoption_rate: 60 }
    )
    assert_includes result, "過去8週間の傾向データ"
    assert_includes result, "読書"
    assert_includes result, "振り返り完了率"
  end

  # ----------------------------------------------------------
  # UpdateAiProfileJob のエンキューテスト
  # ----------------------------------------------------------

  test "振り返り完了後に UpdateAiProfileJob がエンキューされること" do
    week_start = Date.parse("2026-08-03")
    week_end   = week_start + 6.days

    reflection = @user.weekly_reflections.build(
      week_start_date:      week_start,
      week_end_date:        week_end,
      direct_reason:        "テスト用の直接原因",
      background_situation: "テスト用の改善策",
      next_action:          "テスト用の次への展開",
      reflection_comment:   "テスト用コメント"
    )

    assert_enqueued_with(job: UpdateAiProfileJob) do
      WeeklyReflectionCompleteService.new(
        reflection: reflection,
        user:       @user,
        was_locked: false
      ).call
    end
  end
end