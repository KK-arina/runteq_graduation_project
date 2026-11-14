# test/models/weekly_reflection_ai_status_test.rb
#
# ==============================================================================
# WeeklyReflection の AI分析状態メソッドのテスト（AI分析状態の修正で追加）
# ==============================================================================
# 【このテストで保証すること】
#   ai_analysis_pending?(has_analysis:) が「分析中」を表示してよい場合だけ true を返す。
#     ・完了から30分以内で結果が無い           → true
#     ・30分を過ぎた                         → false
#     ・AIなしで完了した（ai_skipped_at あり） → false
#     ・結果がある                           → false
#     ・未完了                               → false
#
# 【DB に保存しない理由】
#   判定は列の値だけで決まるため、WeeklyReflection.new で十分。テストが速くなる。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/models/weekly_reflection_ai_status_test.rb
# ==============================================================================
require "test_helper"

class WeeklyReflectionAiStatusTest < ActiveSupport::TestCase
  def build_reflection(completed_at:, ai_skipped_at: nil)
    WeeklyReflection.new(completed_at: completed_at, ai_skipped_at: ai_skipped_at)
  end

  test "完了から30分以内で結果が無ければ、分析中とみなす" do
    reflection = build_reflection(completed_at: 5.minutes.ago)
    assert reflection.ai_analysis_pending?(has_analysis: false)
  end

  test "完了から30分を過ぎたら、分析中とみなさない" do
    reflection = build_reflection(completed_at: (WeeklyReflection::AI_ANALYSIS_WAIT_LIMIT + 1.minute).ago)
    assert_not reflection.ai_analysis_pending?(has_analysis: false)
  end

  test "AIなしで完了した振り返りは、完了直後でも分析中とみなさない" do
    reflection = build_reflection(completed_at: 1.minute.ago, ai_skipped_at: 1.minute.ago)
    assert reflection.ai_skipped?
    assert_not reflection.ai_analysis_pending?(has_analysis: false)
  end

  test "AI分析の結果があれば、分析中とみなさない" do
    reflection = build_reflection(completed_at: 1.minute.ago)
    assert_not reflection.ai_analysis_pending?(has_analysis: true)
  end

  test "未完了の振り返りは、分析中とみなさない" do
    reflection = build_reflection(completed_at: nil)
    assert_not reflection.ai_analysis_pending?(has_analysis: false)
  end
end