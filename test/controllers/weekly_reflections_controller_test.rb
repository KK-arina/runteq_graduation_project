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

  # ============================================================
  # G-9 テスト: task_modify の処理確認
  # ============================================================
  #
  # 【なぜ fixtures を使わず AiAnalysis.create! するのか】
  #   ai_analyses.yml フィクスチャが存在しないため、
  #   テスト内でレコードを直接作成する。
  #
  # 【なぜ completed_reflection フィクスチャを使うのか】
  #   weekly_reflections.yml に 'one' は存在しない。
  #   completed_at が設定済みの completed_reflection が
  #   confirm_proposals の「completed? チェック」を通過できる。
  test "confirm_proposals: task_modify でチェックしたタスクの優先度が更新されること" do
    reflection = weekly_reflections(:completed_reflection)

    # AiAnalysis フィクスチャが存在しないためテスト内で直接作成する
    ai_analysis = AiAnalysis.create!(
      weekly_reflection_id: reflection.id,
      analysis_type:        :weekly_reflection,
      is_latest:            true,
      crisis_detected:      false,
      prompt_version:       "v2.0",
      input_snapshot:       { week_start_date: reflection.week_start_date.to_s },
      actions_json: [
        {
          "type"       => "task_modify",
          "task_title" => "G9修正テストタスク",
          "changes"    => { "priority" => "should" },
          "reason"     => "優先度の見直し",
          "priority"   => "should"
        }
      ]
    )

    # 対象タスクを must で作成する
    task = Task.create!(
      user:      users(:one),
      title:     "G9修正テストタスク",
      priority:  :must,
      status:    :todo,
      task_type: :normal
    )

    log_in_as users(:one)

    post confirm_proposals_weekly_reflections_path,
         params: {
           reflection_id:       reflection.id,
           task_modify_indices: ["0"]
         }

    assert_redirected_to dashboard_path
    task.reload
    assert_equal "should", task.priority, "優先度が should に更新されていること"
  end

  # ============================================================
  # G-9 テスト: 存在しないタスク名は安全にスキップされること
  # ============================================================
  test "confirm_proposals: 存在しないタスク名は修正をスキップしてエラーにならないこと" do
    reflection = weekly_reflections(:completed_reflection)

    AiAnalysis.create!(
      weekly_reflection_id: reflection.id,
      analysis_type:        :weekly_reflection,
      is_latest:            true,
      crisis_detected:      false,
      prompt_version:       "v2.0",
      input_snapshot:       { week_start_date: reflection.week_start_date.to_s },
      actions_json: [
        {
          "type"       => "task_modify",
          "task_title" => "存在しないタスク名G9",
          "changes"    => { "priority" => "must" },
          "reason"     => "テスト",
          "priority"   => "must"
        }
      ]
    )

    log_in_as users(:one)

    # 存在しない名前のタスクでもエラーにならず正常にリダイレクトされること
    assert_nothing_raised do
      post confirm_proposals_weekly_reflections_path,
           params: {
             reflection_id:       reflection.id,
             task_modify_indices: ["0"]
           }
    end

    assert_redirected_to dashboard_path
  end

  # ============================================================
  # G-9 テスト: goal_review チェックで PMVV ページへリダイレクト
  # ============================================================
  test "confirm_proposals: goal_review_requested=1 のとき user_purpose_path へリダイレクト" do
    reflection = weekly_reflections(:completed_reflection)

    AiAnalysis.create!(
      weekly_reflection_id: reflection.id,
      analysis_type:        :weekly_reflection,
      is_latest:            true,
      crisis_detected:      false,
      prompt_version:       "v2.0",
      input_snapshot:       { week_start_date: reflection.week_start_date.to_s },
      actions_json: [
        {
          "type"         => "goal_review",
          "review_point" => "Vision の見直しが必要です",
          "reason"       => "PMVVとのギャップが大きい",
          "priority"     => "could"
        }
      ]
    )

    log_in_as users(:one)

    post confirm_proposals_weekly_reflections_path,
         params: {
           reflection_id:         reflection.id,
           goal_review_requested: "1"
         }

    # goal_review_requested == "1" の場合は user_purpose_path へリダイレクト
    assert_redirected_to user_purpose_path
  end
end