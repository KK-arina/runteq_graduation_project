# test/integration/ai_limit_modal_accessibility_test.rb
#
# ==============================================================================
# AI コスト上限モーダル（14-B）のアクセシビリティテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① モーダルの中の id が、パソコン用とスマホ用で重複していない
#   ② パソコン用・スマホ用の両方が role="dialog" を持ち、
#      aria-labelledby がそれぞれの見出しを指している
#   ③ hidden 項目の name（送信される項目名）が正しい
#      （AI分析状態の修正で mood を追加）
#
# 【検査する画面】
#   このモーダルはダッシュボードと振り返り一覧でも表示されるため、両方を確認する。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/ai_limit_modal_accessibility_test.rb
# ==============================================================================
require "test_helper"

class AiLimitModalAccessibilityTest < ActionDispatch::IntegrationTest
  # モーダル全体を特定するセレクター
  MODAL = "[data-controller='ai-limit-modal']".freeze

  # complete_without_ai に送る項目（パソコン用・スマホ用で1つずつある）
  HIDDEN_FIELDS = %w[reflection_comment direct_reason background_situation next_action mood].freeze

  setup do
    @user = users(:one)
    log_in_as(@user)
  end

  # 指定したページで、モーダルのアクセシビリティを確認する
  def assert_ai_limit_modal_accessible(path)
    get path
    assert_response :success

    # ① モーダルの中の id に重複がない
    ids = css_select("#{MODAL} [id]").map { |element| element["id"] }
    assert ids.any?, "モーダルの中に id が1つもない（セレクターの間違いの可能性）"
    duplicated = ids.tally.select { |_id, count| count > 1 }.keys
    assert_empty duplicated, "モーダルの中で id が重複している: #{duplicated.join(', ')}"

    # ② ダイアログが2つあり、aria-labelledby がそれぞれの見出しを指している
    dialogs = css_select("#{MODAL} [role='dialog']")
    assert_equal 2, dialogs.size, "パソコン用とスマホ用の2つのダイアログがあるはず"
    dialogs.each do |dialog|
      assert_equal "true", dialog["aria-modal"]
      title_id = dialog["aria-labelledby"]
      # 見出しの id がダイアログの中に実在すること
      assert dialog.css("[id='#{title_id}']").any?,
             "aria-labelledby=#{title_id} の見出しがダイアログの中にない"
    end

    # ③ 送信される項目名が正しい（パソコン用とスマホ用で1つずつ）
    HIDDEN_FIELDS.each do |field|
      assert_select "#{MODAL} input[type='hidden'][name='#{field}'][data-field='#{field}']", count: 2
    end
  end

  test "ダッシュボードの AI 上限モーダルは id が重複せず、ダイアログとして名前を持つ" do
    assert_ai_limit_modal_accessible(dashboard_path)
  end

  test "振り返り一覧の AI 上限モーダルは id が重複せず、ダイアログとして名前を持つ" do
    assert_ai_limit_modal_accessible(weekly_reflections_path)
  end
end