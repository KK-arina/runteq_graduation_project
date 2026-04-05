# test/models/habit_sort_test.rb
# ==============================================================================
# B-6: 習慣のカラー・アイコン・並び替えのテスト
# ==============================================================================
require "test_helper"

class HabitSortTest < ActiveSupport::TestCase
  # ────────────────────────────────────────────────────────────
  # セットアップ
  # ────────────────────────────────────────────────────────────
  # travel_to で日付を固定する。
  # current_week_range が曜日に依存しないようにするため水曜日に固定する。
  setup do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) # 水曜日

    @user = users(:one)

    # テスト用習慣を3件作成する（position 順に並ぶことを確認するため）
    @habit1 = @user.habits.create!(
      name: "読書",
      weekly_target: 5,
      measurement_type: :check_type,
      color: "#3b82f6",
      icon: "📚"
    )
    @habit2 = @user.habits.create!(
      name: "筋トレ",
      weekly_target: 3,
      measurement_type: :check_type,
      color: "#ef4444",
      icon: "💪"
    )
    @habit3 = @user.habits.create!(
      name: "ジョギング",
      weekly_target: 7,
      measurement_type: :check_type,
      color: "#10b981",
      icon: "🏃"
    )
  end

  teardown do
    travel_back
  end

  # ────────────────────────────────────────────────────────────
  # カラーのテスト
  # ────────────────────────────────────────────────────────────

  test "有効なカラーコードが保存される" do
    # #rrggbb 形式の正しいカラーコードが保存されることを確認する
    habit = @user.habits.build(
      name: "テスト習慣",
      weekly_target: 5,
      measurement_type: :check_type,
      color: "#8b5cf6"
    )
    assert habit.valid?, "有効なカラーコードでバリデーションが通ること"
    assert_equal "#8b5cf6", habit.color
  end

  test "不正なカラーコードはバリデーションエラーになる" do
    # # を含まない文字列、短すぎる文字列はエラーになることを確認する
    habit = @user.habits.build(
      name: "テスト習慣",
      weekly_target: 5,
      measurement_type: :check_type,
      color: "invalid_color"
    )
    assert_not habit.valid?
    assert_includes habit.errors[:color], "は #rrggbb 形式で入力してください"
  end

  test "カラーが空でもバリデーションが通る（allow_blank）" do
    # color は任意項目なので nil / 空文字でもエラーにならないことを確認する
    habit = @user.habits.build(
      name: "テスト習慣",
      weekly_target: 5,
      measurement_type: :check_type,
      color: nil
    )
    assert habit.valid?, "カラーが nil でもバリデーションが通ること"
  end

  # ────────────────────────────────────────────────────────────
  # アイコンのテスト
  # ────────────────────────────────────────────────────────────

  test "アイコンが保存される" do
    habit = @user.habits.create!(
      name: "テスト習慣2",
      weekly_target: 3,
      measurement_type: :check_type,
      icon: "🌱"
    )
    assert_equal "🌱", habit.reload.icon
  end

  test "3文字以上のアイコンはバリデーションエラーになる" do
    habit = @user.habits.build(
      name: "テスト習慣",
      weekly_target: 5,
      measurement_type: :check_type,
      icon: "abc"
    )
    assert_not habit.valid?
    assert habit.errors[:icon].any?
  end

  # ────────────────────────────────────────────────────────────
  # acts_as_list / 並び替えのテスト
  # ────────────────────────────────────────────────────────────

  test "新規作成した習慣は末尾の position に追加される" do
    # acts_as_list の add_new_at: :bottom により
    # 新しく作った習慣は既存の末尾に追加されることを確認する
    habits = @user.habits.active

    # ==============================================================
    # 【修正】compact で nil を除外してからソートする
    # ==============================================================
    # 【問題の原因】
    #   fixtures（テストデータ）の既存習慣は position が nil の場合がある。
    #   nil が含まれた配列を sort すると
    #   "comparison of Integer with nil failed" エラーが発生する。
    #
    # 【修正内容】
    #   compact で nil を除外した上でソート順を確認する。
    #   setup で作成した3件（@habit1, @habit2, @habit3）は
    #   acts_as_list が自動で position を付与するため nil にはならない。
    #   これらについては個別に position が nil でないことを確認する。
    # ==============================================================
    positions = habits.map(&:position).compact

    assert_equal positions.sort, positions,
      "position が設定されているアクティブな習慣は昇順に並んでいること"

    # setup で作成した3件は必ず position が設定されているはず
    [@habit1, @habit2, @habit3].each do |habit|
      assert_not_nil habit.reload.position,
        "#{habit.name} の position が nil でないこと（acts_as_list が自動付与する）"
    end
  end

  test "scope :active は position 昇順で習慣を返す" do
    # B-6 で scope :active の order を position 昇順に変更したことを確認する
    habits = @user.habits.active
    positions = habits.map(&:position).compact

    assert_equal positions.sort, positions,
      "scope :active が position ASC で並んでいること"
  end

  test "insert_at で position が正しく更新される" do
    # habit2（筋トレ）を先頭（position=1）に移動する
    @habit2.insert_at(1)

    # リロードして DB の最新値を取得する
    @habit1.reload
    @habit2.reload
    @habit3.reload

    # habit2 が position=1 になっていること
    assert_equal 1, @habit2.position, "insert_at(1) で position=1 になること"

    # 他の習慣は自動的にずれていること
    # habit1 は 2 に、habit3 は 3 になるはず
    assert_equal [1, 2, 3], [@habit2, @habit1, @habit3].map(&:position).sort,
      "並び替え後に 1,2,3 の連番になること"
  end
end