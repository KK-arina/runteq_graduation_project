# test/models/ai_analysis_test.rb
#
# ==============================================================================
# AiAnalysis モデルテスト
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   WeeklyReflection.create! に reflection_comment を追加する。
#   （D-9 テスト "weekly_reflection 分析の場合は..." 内の create! を修正）
# ==============================================================================

require "test_helper"

class AiAnalysisTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @user_purpose = UserPurpose.create!(
      user:             @user,
      purpose:          "テスト Purpose",
      mission:          "テスト Mission",     # E-1修正: presence必須化対応
      vision:           "テスト Vision",
      value:            "テスト Value",       # E-1修正: presence必須化対応
      current_situation: "テスト Current",    # E-1修正: presence必須化対応
      analysis_state:   :completed
    )
  end

  test "必須フィールドが揃っている場合は有効である" do
    ai_analysis = AiAnalysis.new(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "テスト分析コメント",
      root_cause:       "テスト根本原因",
      coaching_message: "テストコーチングメッセージ",
      is_latest:        true
    )
    assert ai_analysis.valid?, "バリデーションエラー: #{ai_analysis.errors.full_messages}"
  end

  test "analysis_type が未設定の場合は無効である" do
    ai_analysis = AiAnalysis.new(
      user_purpose:     @user_purpose,
      analysis_comment: "テスト"
    )
    ai_analysis.write_attribute(:analysis_type, nil)
    assert_not ai_analysis.valid?
    assert ai_analysis.errors[:analysis_type].any?
  end

  test "user_purpose_id と weekly_reflection_id が両方 nil の場合は無効である" do
    ai_analysis = AiAnalysis.new(
      analysis_type:    :purpose_breakdown,
      analysis_comment: "テスト"
    )
    assert_not ai_analysis.valid?
    assert_includes ai_analysis.errors[:base],
                    "weekly_reflection_id または user_purpose_id のどちらかは必須です"
  end

  test "新しい分析を作成すると古い分析の is_latest が false になる" do
    first_analysis = AiAnalysis.create!(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "1回目の分析",
      is_latest:        true
    )
    assert first_analysis.is_latest

    second_analysis = AiAnalysis.create!(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "2回目の分析",
      is_latest:        true
    )

    first_analysis.reload
    assert_not first_analysis.is_latest
    assert second_analysis.is_latest
  end

  test "scope latest は is_latest=true のレコードのみ返す" do
    other_purpose = UserPurpose.create!(
      user:             @user,
      purpose:          "別の Purpose",
      mission:          "別の Mission",       # E-1修正: presence必須化対応
      vision:           "別の Vision",
      value:            "別の Value",         # E-1修正: presence必須化対応
      current_situation: "別の Current",      # E-1修正: presence必須化対応
      analysis_state:   :completed
    )

    latest = AiAnalysis.create!(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "最新の分析",
      is_latest:        true
    )

    old_analysis = AiAnalysis.create!(
      user_purpose:     other_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "古い分析",
      is_latest:        true
    )
    old_analysis.update_columns(is_latest: false)

    latest_records = AiAnalysis.latest
    assert_includes     latest_records, latest
    assert_not_includes latest_records, old_analysis
  end

  # ============================================================
  # D-9 追加テスト: input_snapshot スキーマバリデーション
  # ============================================================

  test "D-9: 全5キーが揃った input_snapshot は有効である" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot,
      is_latest:      true
    )
    assert ai_analysis.valid?, "エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: input_snapshot が nil の場合はバリデーションをスキップして有効になる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: nil,
      is_latest:      true
    )
    assert ai_analysis.valid?, "エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: purpose の値が nil でもキーが存在すればバリデーションを通過する" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.merge("purpose" => nil),
      is_latest:      true
    )
    assert ai_analysis.valid?, "エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: シンボルキーの input_snapshot でも正常にバリデーションが通過する" do
    snapshot_with_symbol_keys = {
      purpose:           "テストPurpose",
      mission:           "テストMission",
      vision:            "テストVision",
      value:             "テストValue",
      current_situation: "テストCurrent",
      version:           1,
      analyzed_at:       Time.current.iso8601
    }
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: snapshot_with_symbol_keys,
      is_latest:      true
    )
    assert ai_analysis.valid?, "エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: weekly_reflection 分析の場合は input_snapshot のPMVVキーチェックをスキップする" do
    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 【修正理由】
    #   E-1 で WeeklyReflection モデルに presence: true を追加したため、
    #   reflection_comment なしで create! するとバリデーションエラーが発生する。
    weekly_reflection = WeeklyReflection.create!(
      user:               @user,
      week_start_date:    Date.current.beginning_of_week,
      week_end_date:      Date.current.end_of_week,
      year:               Date.current.year,
      week_number:        Date.current.cweek,
      reflection_comment: "D-9テスト用振り返りコメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    reflection_snapshot = {
      "weekly_reflection_id" => weekly_reflection.id,
      "direct_reason"        => "仕事が忙しかった",
      "analyzed_at"          => Time.current.iso8601
    }

    ai_analysis = AiAnalysis.new(
      weekly_reflection: weekly_reflection,
      analysis_type:     :weekly_reflection,
      input_snapshot:    reflection_snapshot,
      is_latest:         true
    )

    assert ai_analysis.valid?, "エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: purpose キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("purpose"),
      is_latest:      true
    )
    assert_not ai_analysis.valid?
    assert ai_analysis.errors[:input_snapshot].any?
    assert_match "purpose", ai_analysis.errors[:input_snapshot].first
  end

  test "D-9: mission キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("mission"),
      is_latest:      true
    )
    assert_not ai_analysis.valid?
    assert_match "mission", ai_analysis.errors[:input_snapshot].first
  end

  test "D-9: vision キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("vision"),
      is_latest:      true
    )
    assert_not ai_analysis.valid?
    assert_match "vision", ai_analysis.errors[:input_snapshot].first
  end

  test "D-9: value キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("value"),
      is_latest:      true
    )
    assert_not ai_analysis.valid?
    assert_match "value", ai_analysis.errors[:input_snapshot].first
  end

  test "D-9: current_situation キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("current_situation"),
      is_latest:      true
    )
    assert_not ai_analysis.valid?
    assert_match "current_situation", ai_analysis.errors[:input_snapshot].first
  end

  test "D-9: 5キー全て欠落した場合は全キーがエラーメッセージに含まれる" do
    snapshot_without_pmvv_keys = {
      "version"     => 1,
      "analyzed_at" => Time.current.iso8601
    }
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: snapshot_without_pmvv_keys,
      is_latest:      true
    )
    assert_not ai_analysis.valid?
    error_message = ai_analysis.errors[:input_snapshot].first
    %w[purpose mission vision value current_situation].each do |key|
      assert_match key, error_message
    end
  end

  private

  def valid_input_snapshot
    {
      "purpose"           => "テストPurpose",
      "mission"           => "テストMission",
      "vision"            => "テストVision",
      "value"             => "テストValue",
      "current_situation" => "テストCurrent",
      "version"           => 1,
      "analyzed_at"       => Time.current.iso8601
    }
  end
end
