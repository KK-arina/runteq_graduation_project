# test/integration/weekly_reflection_create_test.rb
#
# 振り返り作成フロー E2E テスト（E-1追加: 3フィールド必須化対応）
#
# 【E-1追加での変更内容】
#   post weekly_reflections_path に3フィールドを追加する。

require "test_helper"

class WeeklyReflectionCreateTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "ログイン後に振り返りを作成して一覧ページへリダイレクトされること" do
    travel_to Time.zone.local(2026, 2, 22, 5, 0, 0) do
      log_in_as(@user)

      get new_weekly_reflection_path
      assert_response :success

      # ── E-1追加: 3フィールドを追加 ──────────────────────────────────────
      #
      # 【変更理由】
      #   direct_reason / background_situation / next_action が必須になったため、
      #   これらを含まないと 422 Unprocessable Content が返り、
      #   assert_redirected_to が失敗する。
      post weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment:   "今週は筋トレを3日しかできなかった。残業が多かった。",
          direct_reason:        "残業が続き、帰宅後に体力が残っていなかった",  # E-1追加
          background_situation: "朝30分早く起きてトレーニング時間を確保する", # E-1追加
          next_action:          "朝型の生活リズムを読書にも広げる"             # E-1追加
        }
      }
      # ────────────────────────────────────────────────────────────────────

      assert_redirected_to weekly_reflections_path
    end
  end

  test "振り返りコメントが1001文字以上の場合はバリデーションエラーになること" do
    travel_to Time.zone.local(2026, 2, 22, 5, 0, 0) do
      log_in_as(@user)

      over_limit_comment = "あ" * 1001

      assert_no_difference "WeeklyReflection.count" do
        post weekly_reflections_path, params: {
          weekly_reflection: { reflection_comment: over_limit_comment }
        }
      end

      assert_response :unprocessable_entity
    end
  end
end
