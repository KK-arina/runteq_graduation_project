# test/controllers/habits_menu_controller_test.rb
#
# ==============================================================================
# HabitsController の削除確認モーダル（M-1）テスト（B-5 修正版）
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   weekly_reflections.create! に reflection_comment を追加する。
#   （line 142 付近の「ロック中は...」テスト）
# ==============================================================================

require "test_helper"

class HabitsMenuControllerTest < ActionDispatch::IntegrationTest

  setup do
    @user = users(:one)

    @habit = @user.habits.create!(
      name:             "⋯メニューテスト習慣",
      measurement_type: :check_type,
      weekly_target:    5
    )

    post login_path, params: {
      session: { email: @user.email, password: "password" }
    }
  end

  test "習慣一覧ページに data-controller='habit-menu' が含まれる（ロック解除中）" do
    get habits_path
    assert_response :success
    assert_select "[data-controller='habit-menu']"
  end

  test "習慣一覧ページに data-habit-menu-habit-name-value が含まれる" do
    get habits_path
    assert_response :success
    assert_select "[data-habit-menu-habit-name-value='⋯メニューテスト習慣']"
  end

  test "習慣一覧ページに data-habit-menu-modal-id-value が含まれる" do
    get habits_path
    assert_response :success
    assert_select "[data-habit-menu-modal-id-value='habit-modal-#{@habit.id}']"
  end

  test "習慣一覧ページに data-habit-menu-sheet-id-value が含まれる" do
    get habits_path
    assert_response :success
    assert_select "[data-habit-menu-sheet-id-value='habit-sheet-#{@habit.id}']"
  end

  test "習慣一覧ページにモーダル用のDIVが含まれる" do
    get habits_path
    assert_response :success
    assert_select "#habit-modal-#{@habit.id}"
  end

  test "習慣一覧ページにボトムシート用のDIVが含まれる" do
    get habits_path
    assert_response :success
    assert_select "#habit-sheet-#{@habit.id}"
  end

  test "習慣一覧ページのモーダル内にアーカイブURLが含まれる" do
    get habits_path
    assert_response :success
    assert_select "#habit-modal-#{@habit.id}" do
      assert_select "form[action='#{archive_habit_path(@habit)}']"
    end
  end

  test "習慣一覧ページのモーダル内に削除URLが含まれる" do
    get habits_path
    assert_response :success
    assert_select "#habit-modal-#{@habit.id}" do
      assert_select "form[action='#{habit_path(@habit)}']"
    end
  end

  test "ロック中は data-controller='habit-menu' が出力されない" do
    last_week_start = HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week

    # ── E-1 修正: reflection_comment を追加 ──────────────────────────────────
    #
    # 【修正理由】
    #   E-1 で WeeklyReflection モデルに presence: true を追加したため、
    #   reflection_comment なしで create! するとバリデーションエラーが発生する。
    #   テスト用の文字列を追加してバリデーションを通過させる。
    @user.weekly_reflections.create!(
      week_start_date:    last_week_start,
      week_end_date:      last_week_start + 6.days,
      reflection_comment: "ロック状態テスト用コメント", # E-1 追加
      direct_reason:        "テスト用の直接原因", # E-1追加
      background_situation: "テスト用の改善策",   # E-1追加
      next_action:          "テスト用の次への展開", # E-1追加
    )
    # ────────────────────────────────────────────────────────────────────────────

    travel_to last_week_start + 1.week + 5.hours do
      get habits_path
      assert_response :success
      assert_select "[data-controller='habit-menu']", count: 0
    end
  end

  test "POST /habits/:id/archive でアーカイブが実行されトーストが表示される" do
    post archive_habit_path(@habit)
    assert_redirected_to habits_path
    follow_redirect!
    assert_response :success
    assert_match "アーカイブしました", response.body
  end

  test "DELETE /habits/:id で削除が実行されトーストが表示される" do
    delete habit_path(@habit)
    assert_redirected_to habits_path
    follow_redirect!
    assert_response :success
    assert_match "削除しました", response.body
  end

  test "アーカイブ後に習慣一覧から習慣が消える" do
    post archive_habit_path(@habit)
    follow_redirect!
    assert_select "[data-habit-menu-modal-id-value='habit-modal-#{@habit.id}']", count: 0
  end

  test "削除後に習慣一覧から習慣が消える" do
    delete habit_path(@habit)
    follow_redirect!
    assert_select "[data-habit-menu-modal-id-value='habit-modal-#{@habit.id}']", count: 0
  end

  test "他ユーザーの習慣はアーカイブも削除もできない" do
    other_user  = users(:two)
    other_habit = other_user.habits.create!(
      name:             "他ユーザー習慣",
      measurement_type: :check_type,
      weekly_target:    5
    )

    post archive_habit_path(other_habit)
    assert_redirected_to habits_path
    other_habit.reload
    assert_nil other_habit.archived_at

    delete habit_path(other_habit)
    assert_redirected_to habits_path
    other_habit.reload
    assert_nil other_habit.deleted_at
  end
end
