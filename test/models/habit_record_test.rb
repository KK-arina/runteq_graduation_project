require "test_helper"

class HabitRecordTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @habit = habits(:habit_one)
    @habit_record = HabitRecord.new(
      user: @user,
      habit: @habit,
      record_date: Date.current,
      completed: false
    )
  end

  test "有効な習慣記録は保存できること" do
    assert @habit_record.valid?, "習慣記録が有効でありません: #{@habit_record.errors.full_messages}"
    assert @habit_record.save, "習慣記録を保存できませんでした"
  end

  test "record_date が nil の場合は無効" do
    @habit_record.record_date = nil
    assert_not @habit_record.valid?, "record_date が nil でもバリデーションが通ってしまいました"
    assert @habit_record.errors.added?(:record_date, :blank)
  end

  test "completed が nil の場合は無効" do
    habit_record = HabitRecord.new(
      user: @user,
      habit: @habit,
      record_date: Date.current,
      completed: nil
    )
    assert_not habit_record.valid?, "completed が nil でもバリデーションが通ってしまいました"
    assert_includes habit_record.errors.map(&:type), :inclusion
           "nil の場合は inclusion バリデーションのエラーメッセージが出ること"
    assert_equal 1, habit_record.errors[:completed].count,
                 "completed のエラーメッセージは1つだけであること"
  end

  test "User との関連付けが正しく動作すること" do
    @habit_record.save!
    assert_equal @user.id, @habit_record.user_id
    assert_equal @user, @habit_record.user
    assert_includes @user.habit_records, @habit_record
  end

  test "Habit との関連付けが正しく動作すること" do
    @habit_record.save!
    assert_equal @habit.id, @habit_record.habit_id
    assert_equal @habit, @habit_record.habit
    assert_includes @habit.habit_records, @habit_record
  end

  test "ユーザーが削除されたら習慣記録も削除されること（CASCADE）" do
    @habit_record.save!
    record_id = @habit_record.id
    @user.destroy
    assert_nil HabitRecord.find_by(id: record_id)
  end

  test "習慣が削除されたら習慣記録も削除されること（CASCADE）" do
    @habit_record.save!
    record_id = @habit_record.id
    @habit.destroy
    assert_nil HabitRecord.find_by(id: record_id)
  end

  test "同じユーザー・習慣・日付の記録は重複して作成できないこと" do
    @habit_record.save!
    duplicate_record = HabitRecord.new(
      user: @user,
      habit: @habit,
      record_date: @habit_record.record_date,
      completed: true
    )
    assert_not duplicate_record.valid?, "重複する習慣記録が作成できてしまいました"
    assert_includes duplicate_record.errors.map(&:type), :taken
  end

  test "異なる日付なら同じユーザー・習慣でも作成できること" do
    @habit_record.save!
    another_record = HabitRecord.new(
      user: @user,
      habit: @habit,
      record_date: Date.current + 1.day,
      completed: true
    )
    assert another_record.valid?, "異なる日付の習慣記録が作成できませんでした"
    assert another_record.save, "習慣記録を保存できませんでした"
  end

  test "AM 4:00 より前は前日として扱われること" do
    travel_to Time.zone.local(2024, 1, 1, 3, 59) do
      assert_equal Date.new(2023, 12, 31), HabitRecord.today_for_record
    end
  end

  test "AM 4:00 以降は当日として扱われること" do
    travel_to Time.zone.local(2024, 1, 1, 4, 0) do
      assert_equal Date.new(2024, 1, 1), HabitRecord.today_for_record
    end
  end

  test "PM 11:59 は当日として扱われること" do
    travel_to Time.zone.local(2024, 1, 1, 23, 59) do
      assert_equal Date.new(2024, 1, 1), HabitRecord.today_for_record
    end
  end

  test "for_date スコープが正しく動作すること" do
    today_record = HabitRecord.create!(
      user: @user, habit: @habit,
      record_date: Date.current, completed: true
    )
    yesterday_record = HabitRecord.create!(
      user: @user, habit: habits(:habit_two),
      record_date: Date.current - 1.day, completed: false
    )
    results = HabitRecord.for_date(Date.current)
    assert_includes results, today_record
    assert_not_includes results, yesterday_record
  end

  test "for_user スコープが正しく動作すること" do
    user1_record = HabitRecord.create!(
      user: @user, habit: @habit,
      record_date: Date.current, completed: true
    )
    user2 = users(:two)
    user2_record = HabitRecord.create!(
      user: user2, habit: habits(:habit_two),
      record_date: Date.current, completed: false
    )
    results = HabitRecord.for_user(@user)
    assert_includes results, user1_record
    assert_not_includes results, user2_record
  end

  test "既存の記録がない場合は新規作成されること" do
    record = HabitRecord.find_or_create_for(@user, @habit, Date.current)
    assert record.persisted?, "習慣記録が作成されませんでした"
    assert_equal @user.id, record.user_id
    assert_equal @habit.id, record.habit_id
    assert_equal Date.current, record.record_date
  end

  test "既存の記録がある場合は既存レコードを取得すること" do
    existing_record = HabitRecord.create!(
      user: @user, habit: @habit,
      record_date: Date.current, completed: true
    )
    record = HabitRecord.find_or_create_for(@user, @habit, Date.current)
    assert_equal existing_record.id, record.id
    assert record.completed
  end

  test "completed が false から true に切り替わること" do
    @habit_record.save!
    @habit_record.toggle_completed!
    assert @habit_record.completed
  end

  test "completed が true から false に切り替わること" do
    @habit_record.completed = true
    @habit_record.save!
    @habit_record.toggle_completed!
    assert_not @habit_record.completed
  end
end
