# test/models/habit_test.rb
#
# 【このファイルの役割】
# Habit モデルのユニットテスト。
# バリデーション、スコープ、インスタンスメソッド（論理削除・進捗統計）を検証する。

require "test_helper"

class HabitTest < ActiveSupport::TestCase

  setup do
    @user = users(:one)
    @habit = @user.habits.create!(name: "テスト習慣", weekly_target: 7)
  end

  # ============================================================
  # バリデーションテスト（変更なし）
  # ============================================================

  test "有効な属性で習慣が作成できること" do
    assert @habit.valid?, "有効な属性なのに invalid: #{@habit.errors.full_messages}"
  end

  test "習慣名が空欄のとき無効であること" do
    @habit.name = ""
    assert_not @habit.valid?
  end

  test "習慣名が51文字以上のとき無効であること" do
    @habit.name = "あ" * 51
    assert_not @habit.valid?
  end

  test "習慣名が50文字のとき有効であること" do
    @habit.name = "あ" * 50
    assert @habit.valid?, @habit.errors.full_messages
  end

  test "週次目標が0のとき無効であること" do
    @habit.weekly_target = 0
    assert_not @habit.valid?
  end

  test "週次目標が8以上のとき無効であること" do
    @habit.weekly_target = 8
    assert_not @habit.valid?
  end

  test "週次目標が1のとき有効であること" do
    @habit.weekly_target = 1
    assert @habit.valid?, @habit.errors.full_messages
  end

  test "週次目標が7のとき有効であること" do
    @habit.weekly_target = 7
    assert @habit.valid?, @habit.errors.full_messages
  end

  # ============================================================
  # スコープテスト（変更なし）
  # ============================================================

  test "active スコープは論理削除されていない習慣のみ返すこと" do
    @habit.soft_delete
    assert_not_includes @user.habits.active, @habit
  end

  test "deleted スコープは論理削除された習慣のみ返すこと" do
    @habit.soft_delete
    assert_includes @user.habits.deleted, @habit
  end

  test "soft_delete で deleted_at が設定されること" do
    @habit.soft_delete
    @habit.reload
    assert_not_nil @habit.deleted_at
  end

  test "soft_delete 後に deleted? が true を返すこと" do
    @habit.soft_delete
    assert @habit.deleted?
  end

  test "soft_delete 前に active? が true を返すこと" do
    assert @habit.active?
  end

  # ============================================================
  # 進捗統計テスト（Issue #16 ── メソッド名を weekly_progress_stats に変更）
  # ============================================================

  # 【共通ヘルパー】
  # テスト内で stats[:rate] と stats[:completed_count] を使うため、
  # 毎回 @habit.weekly_progress_stats(@user) を呼ぶのではなく、
  # 変数に受けるパターンで統一する。

  test "戻り値が rate と completed_count を持つハッシュであること" do
    stats = @habit.weekly_progress_stats(@user)

    # assert_instance_of(期待する型, 実際の値) → 型チェック
    assert_instance_of Hash, stats, "戻り値が Hash ではありません"
    assert stats.key?(:rate),            "rate キーが存在しません"
    assert stats.key?(:completed_count), "completed_count キーが存在しません"
  end

  test "記録が0件のとき rate は 0、completed_count は 0 であること" do
    stats = @habit.weekly_progress_stats(@user)

    assert_equal 0, stats[:rate],            "記録なしの rate が 0 ではありません"
    assert_equal 0, stats[:completed_count], "記録なしの completed_count が 0 ではありません"
  end

  test "今週3日完了したとき completed_count は 3 であること" do
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)

    # 月曜から最大3日分（未来はスキップ）の完了記録を作成
    3.times do |i|
      date = week_start + i
      break if date > today
      HabitRecord.create!(user: @user, habit: @habit, record_date: date, completed: true)
    end

    # 実際に作成できた件数を確認
    actual = HabitRecord.where(user: @user, habit: @habit,
                                record_date: week_start..today,
                                completed: true).count

    stats = @habit.weekly_progress_stats(@user)

    assert_equal actual, stats[:completed_count],
                 "completed_count が実際の完了数と一致しません"
    # rate も整合しているか確認
    expected_rate = ((actual.to_f / 7) * 100).clamp(0, 100).floor
    assert_equal expected_rate, stats[:rate],
                 "rate の計算が正しくありません: 完了=#{actual}/7, 期待=#{expected_rate}, 実際=#{stats[:rate]}"
  end

  test "未完了の記録は rate にも completed_count にも含まれないこと" do
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)

    # 完了済み1件
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start, completed: true)
    # 未完了1件（completed: false）
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start + 1, completed: false) if (week_start + 1) <= today

    stats = @habit.weekly_progress_stats(@user)

    assert_equal 1, stats[:completed_count], "未完了記録が completed_count に含まれています"
    expected_rate = ((1.to_f / 7) * 100).clamp(0, 100).floor
    assert_equal expected_rate, stats[:rate], "未完了記録が rate に含まれています"
  end

  test "他ユーザーの記録は含まれないこと" do
    other_user = users(:two)
    today      = HabitRecord.today_for_record

    HabitRecord.create!(user: other_user, habit: @habit, record_date: today, completed: true)

    stats = @habit.weekly_progress_stats(@user)

    assert_equal 0, stats[:rate],            "他ユーザーの記録が rate に含まれています"
    assert_equal 0, stats[:completed_count], "他ユーザーの記録が completed_count に含まれています"
  end

  test "AM4:00 より前は前日として扱われること" do
    travel_to Time.zone.local(2026, 2, 19, 3, 59, 0) do
      assert_equal Date.new(2026, 2, 18), HabitRecord.today_for_record
    end
  end

  test "AM4:00 以降は当日として扱われること" do
    travel_to Time.zone.local(2026, 2, 19, 4, 0, 0) do
      assert_equal Date.new(2026, 2, 19), HabitRecord.today_for_record
    end
  end
end