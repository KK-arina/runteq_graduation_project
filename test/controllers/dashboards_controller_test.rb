# test/controllers/dashboards_controller_test.rb
#
# ==============================================================================
# DashboardsController テスト（C-6: タスク優先度別達成率を追加）
# ==============================================================================
# 【テスト戦略】
#   ビューに表示される HTML を assert_select で検証する（Rails 7 対応）。
#   assigns は rails-controller-testing gem なしでは使えないため使用しない。
#
# 【fixtures の扱い】
#   tasks.yml に ai_generated_task（user: one）が存在するため、
#   各テストの冒頭で @user.tasks.update_all(deleted_at: Time.current) を呼び
#   fixtures タスクを論理削除してからテスト用データを作成する。
#
# 【H-9 追加】
#   PMVV完了バナー / 振り返り完了バナーの「✖を押すまでリロード後も残す」
#   永続表示ロジックの回帰テストを末尾に追加。
# ==============================================================================

require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テスト前に実行する共通処理
  # ============================================================
  setup do
    # 2026-04-15（水曜日）に固定する
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0)

    @user = users(:one)

    post login_path, params: { session: { email: @user.email, password: "password" } }
    assert_redirected_to dashboard_path
    follow_redirect!

    @user.tasks.update_all(deleted_at: Time.current)
  end

  teardown do
    travel_back
  end

  # ============================================================
  # 基本表示テスト
  # ============================================================

  test "ダッシュボードが正常に表示される" do
    get dashboard_path
    assert_response :success
  end

  # ============================================================
  # C-6: タスク優先度別達成率のビュー検証テスト
  # ============================================================

  test "タスクが0件のとき達成率セクション全体が非表示になる" do
    get dashboard_path
    assert_response :success
    assert_select "[data-testid='task-priority-stats-section']", count: 0
  end

  test "Must タスクが3件あり2件完了の場合に Must バッジと 66% が表示される" do
    today = HabitRecord.today_for_record

    must_tasks = 3.times.map do |i|
      @user.tasks.create!(
        title:    "Mustタスク#{i + 1}",
        priority: :must,
        status:   :todo,
        due_date: today
      )
    end

    must_tasks[0].update!(status: :done, completed_at: Time.current)
    must_tasks[1].update!(status: :done, completed_at: Time.current)

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='task-priority-stats-section']"
    assert_select "[data-testid='priority-badge-must']", text: "Must"
    assert_select "[data-testid='priority-count-must']", text: /2\/3件 完了/
    assert_select "[data-testid='priority-rate-must']", text: "66%"
  end

  test "Should タスクが全件完了の場合に 100% と表示される" do
    today = HabitRecord.today_for_record

    2.times do |i|
      @user.tasks.create!(
        title:        "Shouldタスク#{i + 1}",
        priority:     :should,
        status:       :done,
        due_date:     today,
        completed_at: Time.current
      )
    end

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='priority-badge-should']", text: "Should"
    assert_select "[data-testid='priority-rate-should']",  text: "100%"
  end

  test "archived タスクも完了として達成率にカウントされる" do
    today = HabitRecord.today_for_record

    @user.tasks.create!(
      title:        "アーカイブ済みタスク",
      priority:     :could,
      status:       :archived,
      due_date:     today,
      completed_at: Time.current
    )

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='priority-badge-could']", text: "Could"
    assert_select "[data-testid='priority-rate-could']", text: "100%"
  end

  test "Could タスクが 0 件のとき Could の行が非表示になる" do
    today = HabitRecord.today_for_record

    @user.tasks.create!(
      title:    "Mustのみ",
      priority: :must,
      status:   :todo,
      due_date: today
    )

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='priority-badge-must']", text: "Must"
    assert_select "[data-testid='priority-badge-could']", count: 0
  end

  test "Must と Should の両方にタスクがある場合は両方のバッジが表示される" do
    today = HabitRecord.today_for_record

    @user.tasks.create!(
      title:    "Must1",
      priority: :must,
      status:   :todo,
      due_date: today
    )
    @user.tasks.create!(
      title:        "Should1",
      priority:     :should,
      status:       :done,
      due_date:     today,
      completed_at: Time.current
    )

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='priority-badge-must']",   text: "Must"
    assert_select "[data-testid='priority-badge-should']", text: "Should"
  end

  test "今週の範囲外（先週）のタスクは達成率に含まれない" do
    last_week_date = HabitRecord.today_for_record - 8.days

    task = @user.tasks.create!(
      title:    "先週のタスク",
      priority: :must,
      status:   :done,
      due_date: last_week_date
    )

    task.update_columns(
      created_at: last_week_date.in_time_zone.beginning_of_day,
      updated_at: last_week_date.in_time_zone.beginning_of_day
    )

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='task-priority-stats-section']", count: 0
  end

  # ============================================================
  # H-7: Empty State UI テスト
  # ============================================================

  test "習慣が0件のときダッシュボードの Empty State が表示される" do
    @user.habits.update_all(deleted_at: Time.current)

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='dashboard-habits-empty-state']"
  end

  test "習慣が0件かつ非ロック中は「最初の習慣を追加する」CTAリンクが表示される" do
    @user.habits.update_all(deleted_at: Time.current)

    get dashboard_path
    assert_response :success

    assert_select "a[href='#{new_habit_path}']", text: "最初の習慣を追加する"
  end

  # ============================================================
  # H-9 追加: PMVV完了バナーの永続表示（✖を押すまでリロード後も残す）
  # ============================================================
  #
  # 【共通ヘルパー】完了済みPMVV＋最新の purpose_breakdown 分析を用意する。
  #   version は fixtures との (user_id, version) 衝突を避けるため大きめの値を使う。
  #   input_snapshot はPMVV分析のスキーマ検証（5キー必須）を満たすため全キーを渡す。
  def create_completed_pmvv_with_analysis(user)
    user.user_purposes.update_all(is_active: false) # 既存の有効PMVVを無効化して一意にする
    purpose = user.user_purposes.create!(
      purpose: "P", mission: "M", vision: "V", value: "Va", current_situation: "C",
      version: 99, is_active: true, analysis_state: :completed
    )
    analysis = AiAnalysis.create!(
      user_purpose_id: purpose.id,
      analysis_type:   :purpose_breakdown,
      input_snapshot:  { purpose: "P", mission: "M", vision: "V", value: "Va", current_situation: "C" },
      actions_json:    [ { "type" => "habit", "title" => "テスト習慣" } ],
      is_latest:       true
    )
    [ purpose, analysis ]
  end

  test "PMVV分析が完了していてバナー未確認なら、ダッシュボードに完了バナーが表示される" do
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0) do
      create_completed_pmvv_with_analysis(@user)
      @user.user_setting.update_columns(pmvv_banner_dismissed_at: nil)

      get dashboard_path
      assert_response :success
      assert_select "p", text: "目標分析が完了しました", count: 1
    end
  end

  test "✖で閉じた後（dismissed_atが分析より新しい）はリロードしてもPMVVバナーが表示されない" do
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0) do
      _purpose, analysis = create_completed_pmvv_with_analysis(@user)
      @user.user_setting.update_columns(pmvv_banner_dismissed_at: analysis.created_at + 1.second)

      get dashboard_path
      assert_response :success
      assert_select "p", text: "目標分析が完了しました", count: 0
    end
  end

  test "✖で閉じた後にPMVVを再分析（新しい分析）したらバナーが再表示される" do
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0) do
      _purpose, first_analysis = create_completed_pmvv_with_analysis(@user)
      @user.user_setting.update_columns(pmvv_banner_dismissed_at: first_analysis.created_at + 1.second)
    end

    travel_to Time.zone.local(2026, 4, 15, 11, 0, 0) do
      purpose = @user.user_purposes.find_by(is_active: true)
      AiAnalysis.create!(
        user_purpose_id: purpose.id,
        analysis_type:   :purpose_breakdown,
        input_snapshot:  { purpose: "P", mission: "M", vision: "V", value: "Va", current_situation: "C" },
        actions_json:    [ { "type" => "habit", "title" => "再分析の習慣" } ],
        is_latest:       true
      )

      get dashboard_path
      assert_response :success
      assert_select "p", text: "目標分析が完了しました", count: 1
    end
  end

  test "dismiss_completion_banner(PMVV)を叩くと pmvv_banner_dismissed_at が更新される" do
    assert_nil @user.user_setting.pmvv_banner_dismissed_at

    travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
      patch dismiss_completion_banner_user_purpose_path
      assert_response :no_content
    end

    @user.user_setting.reload
    assert_not_nil @user.user_setting.pmvv_banner_dismissed_at
    assert_equal Time.zone.local(2026, 4, 15, 12, 0, 0), @user.user_setting.pmvv_banner_dismissed_at
  end

  # ============================================================
  # H-9 追加: 振り返り完了バナーの永続表示（PMVVと対称）
  # ============================================================
  #
  # 【共通ヘルパー】完了済み振り返り＋最新の振り返りAI分析（actions_json あり）を用意する。
  #   week_start_date は fixtures（2026-01〜02）と衝突しない at 基準の週にする。
  def create_completed_reflection_with_analysis(user, at:)
    week_start = at.to_date.beginning_of_week(:monday) - 1.week
    reflection = user.weekly_reflections.create!(
      week_start_date:      week_start,
      week_end_date:        week_start + 6.days,
      direct_reason:        "テスト理由",
      background_situation: "テスト状況",
      next_action:          "テスト次のアクション",
      completed_at:         at,
      is_locked:            true
    )
    analysis = AiAnalysis.create!(
      weekly_reflection: reflection,
      analysis_type:     :weekly_reflection,
      actions_json:      [ { "type" => "habit", "title" => "振り返り提案" } ],
      is_latest:         true
    )
    [ reflection, analysis ]
  end

  test "振り返り分析が完了していてバナー未確認なら、ダッシュボードに完了バナーが表示される" do
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0) do
      create_completed_reflection_with_analysis(@user, at: Time.current)
      @user.user_setting.update_columns(reflection_banner_dismissed_at: nil)

      get dashboard_path
      assert_response :success
      assert_select "p", text: "振り返りAI分析が完了しました", count: 1
    end
  end

  test "✖で閉じた後（dismissed_atが分析より新しい）はリロードしても振り返りバナーが表示されない" do
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0) do
      _reflection, analysis = create_completed_reflection_with_analysis(@user, at: Time.current)
      @user.user_setting.update_columns(reflection_banner_dismissed_at: analysis.created_at + 1.second)

      get dashboard_path
      assert_response :success
      assert_select "p", text: "振り返りAI分析が完了しました", count: 0
    end
  end

  test "✖で閉じた後に振り返りを再分析したらバナーが再表示される" do
    reflection = nil
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0) do
      reflection, first_analysis = create_completed_reflection_with_analysis(@user, at: Time.current)
      @user.user_setting.update_columns(reflection_banner_dismissed_at: first_analysis.created_at + 1.second)
    end

    travel_to Time.zone.local(2026, 4, 15, 11, 0, 0) do
      AiAnalysis.create!(
        weekly_reflection: reflection,
        analysis_type:     :weekly_reflection,
        actions_json:      [ { "type" => "habit", "title" => "再分析の提案" } ],
        is_latest:         true
      )

      get dashboard_path
      assert_response :success
      assert_select "p", text: "振り返りAI分析が完了しました", count: 1
    end
  end

  test "dismiss_completion_banner(振り返り)を叩くと reflection_banner_dismissed_at が更新される" do
    assert_nil @user.user_setting.reflection_banner_dismissed_at

    travel_to Time.zone.local(2026, 4, 15, 13, 0, 0) do
      patch dismiss_completion_banner_weekly_reflections_path
      assert_response :no_content
    end

    @user.user_setting.reload
    assert_not_nil @user.user_setting.reflection_banner_dismissed_at
    assert_equal Time.zone.local(2026, 4, 15, 13, 0, 0), @user.user_setting.reflection_banner_dismissed_at
  end
end