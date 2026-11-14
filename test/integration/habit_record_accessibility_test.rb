# test/integration/habit_record_accessibility_test.rb
#
# ==============================================================================
# 習慣の日次記録（メモ入力欄）のアクセシビリティテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① メモ入力欄に、習慣ごとに異なる id（habit_memo_<習慣ID>）が付いている
#   ② autocomplete="off" と、読み上げ用の aria-label が付いている
#   ③ 1つの画面の中で id が重複していない（HTML として正しい状態）
#
# 【なぜ id の重複も確認するのか】
#   同じ id が2つあると、label の for や aria-describedby が
#   どちらの要素を指すのか決まらなくなり、スクリーンリーダーが誤った読み上げをする。
#   習慣一覧とダッシュボードは、習慣の数だけこのパーシャルを並べるため確認しておく。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/habit_record_accessibility_test.rb
# ==============================================================================
require "test_helper"

class HabitRecordAccessibilityTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    log_in_as(@user)

    # 表示を確実にするため、テスト内で習慣を2つ作る（チェック型と数値型）
    @check_habit = Habit.create!(
      user:             @user,
      name:             "メモ確認用チェック型",
      weekly_target:    7,
      measurement_type: :check_type
    )
    @numeric_habit = Habit.create!(
      user:             @user,
      name:             "メモ確認用数値型",
      weekly_target:    30,
      measurement_type: :numeric_type,
      unit:             "分"
    )
  end

  # 指定したページで、メモ欄の属性と id の重複がないことを確認する
  def assert_memo_fields_accessible(path)
    get path
    assert_response :success

    [@check_habit, @numeric_habit].each do |habit|
      # [id='...'] で属性を指定して1つだけ見つかることを確認する
      assert_select "textarea[id='habit_memo_#{habit.id}'][autocomplete='off']", count: 1
      assert_select "textarea[id='habit_memo_#{habit.id}'][aria-label='習慣メモ入力欄（#{habit.name}）']"
    end

    # ページ内のすべての id を集めて、重複がないことを確認する
    ids = css_select("[id]").map { |element| element["id"] }
    duplicated = ids.tally.select { |_id, count| count > 1 }.keys
    assert_empty duplicated, "ページ内で id が重複している: #{duplicated.join(', ')}"
  end

  test "習慣一覧のメモ入力欄に id と autocomplete があり、id が重複していない" do
    assert_memo_fields_accessible(habits_path)
  end

  test "ダッシュボードのメモ入力欄に id と autocomplete があり、id が重複していない" do
    assert_memo_fields_accessible(dashboard_path)
  end
end