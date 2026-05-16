# test/controllers/weekly_reflections_controller_test.rb
#
# WeeklyReflectionsController テスト（E-1追加: 3フィールド必須化対応）
#
# 【E-1追加での変更内容】
#   direct_reason / background_situation / next_action が必須になったため、
#   post weekly_reflections_path に3フィールドを追加する。
#   これらがないと 422 Unprocessable Content が返り、
#   リダイレクトを期待するテストが失敗する。

require "test_helper"

class WeeklyReflectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    log_in_as(@user)
  end

  # ── 共通のフォームパラメータ ──────────────────────────────────────────────
  #
  # 【なぜメソッドにまとめるのか】
  #   必須化された3フィールドを全テストで共通化することで、
  #   将来さらにフィールドが追加されたときに1か所だけ修正すれば済む。
  def valid_reflection_params(overrides = {})
    {
      reflection_comment:   "今週も頑張った！",
      direct_reason:        "残業が多かった",          # E-1追加: presence必須化対応
      background_situation: "朝型に切り替える",        # E-1追加: presence必須化対応
      next_action:          "他の習慣にも広げる"        # E-1追加: presence必須化対応
    }.merge(overrides)
  end
  # ────────────────────────────────────────────────────────────────────────────

  test "create completes reflection and redirects to weekly_reflections" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      assert_difference "WeeklyReflection.count", 1 do
        post weekly_reflections_path, params: {
          weekly_reflection: valid_reflection_params
        }
      end

      assert_redirected_to weekly_reflections_path
    end
  end

  test "create sets completed_at on the new reflection" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params
      }

      reflection = WeeklyReflection.last

      assert_not_nil reflection.completed_at
      assert reflection.completed?
      assert_not reflection.pending?
    end
  end

  test "create with previously locked user shows unlock flash message" do
    locked_user = users(:locked_user)
    log_in_as(locked_user)

    travel_to Time.zone.parse("2026-02-16 04:01:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params(
          reflection_comment: "前週の振り返りです"
        )
      }

      follow_redirect!
      assert_match "ロックが解除されました", response.body
    end
  end

  test "create without locked state shows normal notice" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params(
          reflection_comment: "通常の振り返り"
        )
      }

      follow_redirect!
      assert_match "振り返りを保存しました", response.body
      assert_no_match "ロックが解除されました", response.body
    end
  end

  test "create prevents double submission" do
    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params(reflection_comment: "1回目")
      }

      @user.user_setting.update_columns(
        last_ai_requested_at: 2.minutes.ago
      )

      assert_no_difference "WeeklyReflection.count" do
        post weekly_reflections_path, params: {
          weekly_reflection: valid_reflection_params(reflection_comment: "2回目（作成されないはず）")
        }
      end

      assert_redirected_to weekly_reflections_path
    end
  end

  test "create redirects to login if not authenticated" do
    delete logout_path

    travel_to Time.zone.parse("2026-02-22 10:00:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params
      }

      assert_redirected_to %r{/login}
    end
  end

  test "user is no longer locked after completing reflection via controller" do
    locked_user = users(:locked_user)
    log_in_as(locked_user)

    travel_to Time.zone.parse("2026-02-16 04:01:00") do
      post weekly_reflections_path, params: {
        weekly_reflection: valid_reflection_params(
          reflection_comment: "振り返り完了！"
        )
      }

      locked_user.reload

      last_week_start = WeeklyReflection.current_week_start_date - 7.days
      last_week_reflection = locked_user.weekly_reflections
                                        .find_by(week_start_date: last_week_start)
      assert_not_nil last_week_reflection
      assert last_week_reflection.completed?, "前週の振り返りは completed? が true になること"
      assert_not locked_user.locked?
      assert_not last_week_reflection.pending?

      assert_redirected_to dashboard_path
    end
  end
end
