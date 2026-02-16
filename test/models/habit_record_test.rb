require "test_helper"

# ==============================================================================
# HabitRecord モデルのテスト
# ==============================================================================
# 【テスト項目】
# 1. バリデーションのテスト
# 2. アソシエーションのテスト
# 3. UNIQUE制約のテスト
# 4. AM 4:00 基準の日付計算のテスト
# 5. スコープのテスト
# 6. トグルメソッドのテスト
# ==============================================================================
class HabitRecordTest < ActiveSupport::TestCase
  # ============================================================================
  # セットアップ（各テストの前に実行される）
  # ============================================================================
  setup do
    # テスト用のユーザーを取得（fixtures から）
    @user = users(:one)
    
    # テスト用の習慣を取得（fixtures から）
    @habit = habits(:one)
    
    # ========================================================================
    # 【重要】テスト用の習慣記録を作成（保存しない）
    # ========================================================================
    # - new で作成するだけで save! はしない
    # - 各テストで必要に応じて save! する
    # - これにより fixtures との重複を避ける
    # ========================================================================
    @habit_record = HabitRecord.new(
      user: @user,
      habit: @habit,
      record_date: Date.current,  # 今日の日付
      completed: false
    )
  end

  # ============================================================================
  # 1. バリデーションのテスト
  # ============================================================================
  
  # ----------------------------------------------------------------------------
  # 1-1. 正常系: 有効な習慣記録は保存できること
  # ----------------------------------------------------------------------------
  test "有効な習慣記録は保存できること" do
    # バリデーションが通ることを確認
    assert @habit_record.valid?, "習慣記録が有効でありません: #{@habit_record.errors.full_messages}"
    
    # 保存できることを確認
    assert @habit_record.save, "習慣記録を保存できませんでした"
  end

  # ----------------------------------------------------------------------------
  # 1-2. 異常系: record_date が nil の場合は無効
  # ----------------------------------------------------------------------------
  test "record_date が nil の場合は無効" do
    @habit_record.record_date = nil
    
    # バリデーションが通らないことを確認
    assert_not @habit_record.valid?, "record_date が nil でもバリデーションが通ってしまいました"
    
    # エラーメッセージに "Record date" が含まれることを確認
    assert_includes @habit_record.errors[:record_date], "can't be blank"
  end

  # ----------------------------------------------------------------------------
  # 1-3. 異常系: completed が nil の場合は無効
  # ----------------------------------------------------------------------------
  test "completed が nil の場合は無効" do
    @habit_record.completed = nil
    
    # バリデーションが通らないことを確認
    assert_not @habit_record.valid?, "completed が nil でもバリデーションが通ってしまいました"
    
    # エラーメッセージに "Completed" が含まれることを確認
    assert_includes @habit_record.errors[:completed], "is not included in the list"
  end

  # ============================================================================
  # 2. アソシエーションのテスト
  # ============================================================================
  
  # ----------------------------------------------------------------------------
  # 2-1. User との関連付けが正しく動作すること
  # ----------------------------------------------------------------------------
  test "User との関連付けが正しく動作すること" do
    # 習慣記録を保存
    @habit_record.save!
    
    # user_id が正しく設定されていることを確認
    assert_equal @user.id, @habit_record.user_id
    
    # user メソッドで User オブジェクトを取得できることを確認
    assert_equal @user, @habit_record.user
    
    # ユーザーの habit_records から逆引きできることを確認
    assert_includes @user.habit_records, @habit_record
  end

  # ----------------------------------------------------------------------------
  # 2-2. Habit との関連付けが正しく動作すること
  # ----------------------------------------------------------------------------
  test "Habit との関連付けが正しく動作すること" do
    # 習慣記録を保存
    @habit_record.save!
    
    # habit_id が正しく設定されていることを確認
    assert_equal @habit.id, @habit_record.habit_id
    
    # habit メソッドで Habit オブジェクトを取得できることを確認
    assert_equal @habit, @habit_record.habit
    
    # 習慣の habit_records から逆引きできることを確認
    assert_includes @habit.habit_records, @habit_record
  end

  # ----------------------------------------------------------------------------
  # 2-3. ユーザーが削除されたら習慣記録も削除されること（CASCADE）
  # ----------------------------------------------------------------------------
  test "ユーザーが削除されたら習慣記録も削除されること（CASCADE）" do
    # 習慣記録を保存
    @habit_record.save!
    
    # 習慣記録のIDを保存
    record_id = @habit_record.id
    
    # ユーザーを削除
    @user.destroy
    
    # 習慣記録が削除されていることを確認（DB + アプリの二重削除）
    assert_nil HabitRecord.find_by(id: record_id)
  end

  # ----------------------------------------------------------------------------
  # 2-4. 習慣が削除されたら習慣記録も削除されること（CASCADE）
  # ----------------------------------------------------------------------------
  test "習慣が削除されたら習慣記録も削除されること（CASCADE）" do
    # 習慣記録を保存
    @habit_record.save!
    
    # 習慣記録のIDを保存
    record_id = @habit_record.id
    
    # 習慣を削除
    @habit.destroy
    
    # 習慣記録が削除されていることを確認（DB + アプリの二重削除）
    assert_nil HabitRecord.find_by(id: record_id)
  end

  # ============================================================================
  # 3. UNIQUE制約のテスト
  # ============================================================================
  
  # ----------------------------------------------------------------------------
  # 3-1. 同じユーザー・習慣・日付の記録は重複して作成できないこと
  # ----------------------------------------------------------------------------
  test "同じユーザー・習慣・日付の記録は重複して作成できないこと" do
    # 1つ目の習慣記録を保存
    @habit_record.save!
    
    # 2つ目の習慣記録を作成（同じユーザー・習慣・日付）
    duplicate_record = HabitRecord.new(
      user: @user,
      habit: @habit,
      record_date: @habit_record.record_date,
      completed: true
    )
    
    # バリデーションが通らないことを確認
    assert_not duplicate_record.valid?, "重複する習慣記録が作成できてしまいました"
    
    # エラーメッセージに "Record date" が含まれることを確認
    assert_includes duplicate_record.errors[:record_date], "has already been taken"
  end

  # ----------------------------------------------------------------------------
  # 3-2. 異なる日付なら同じユーザー・習慣でも作成できること
  # ----------------------------------------------------------------------------
  test "異なる日付なら同じユーザー・習慣でも作成できること" do
    # 1つ目の習慣記録を保存（今日）
    @habit_record.save!
    
    # 2つ目の習慣記録を作成（明日）
    another_record = HabitRecord.new(
      user: @user,
      habit: @habit,
      record_date: Date.current + 1.day,  # 修正: Date.tomorrow → Date.current + 1.day
      completed: true
    )
    
    # バリデーションが通ることを確認
    assert another_record.valid?, "異なる日付の習慣記録が作成できませんでした"
    
    # 保存できることを確認
    assert another_record.save, "習慣記録を保存できませんでした"
  end

  # ============================================================================
  # 4. AM 4:00 基準の日付計算のテスト
  # ============================================================================
  
  # ----------------------------------------------------------------------------
  # 4-1. AM 4:00 より前は前日として扱われること
  # ----------------------------------------------------------------------------
  test "AM 4:00 より前は前日として扱われること" do
    # 現在時刻を 2024/1/1 AM 3:59 に設定
    travel_to Time.zone.local(2024, 1, 1, 3, 59) do
      # today_for_record メソッドを実行
      result = HabitRecord.today_for_record
      
      # 2023/12/31 が返ることを確認
      assert_equal Date.new(2023, 12, 31), result
    end
  end

  # ----------------------------------------------------------------------------
  # 4-2. AM 4:00 以降は当日として扱われること
  # ----------------------------------------------------------------------------
  test "AM 4:00 以降は当日として扱われること" do
    # 現在時刻を 2024/1/1 AM 4:00 に設定
    travel_to Time.zone.local(2024, 1, 1, 4, 0) do
      # today_for_record メソッドを実行
      result = HabitRecord.today_for_record
      
      # 2024/1/1 が返ることを確認
      assert_equal Date.new(2024, 1, 1), result
    end
  end

  # ----------------------------------------------------------------------------
  # 4-3. PM 11:59 は当日として扱われること
  # ----------------------------------------------------------------------------
  test "PM 11:59 は当日として扱われること" do
    # 現在時刻を 2024/1/1 PM 11:59 に設定
    travel_to Time.zone.local(2024, 1, 1, 23, 59) do
      # today_for_record メソッドを実行
      result = HabitRecord.today_for_record
      
      # 2024/1/1 が返ることを確認
      assert_equal Date.new(2024, 1, 1), result
    end
  end

  # ============================================================================
  # 5. スコープのテスト
  # ============================================================================
  
  # ----------------------------------------------------------------------------
  # 5-1. for_date スコープが正しく動作すること
  # ----------------------------------------------------------------------------
  test "for_date スコープが正しく動作すること" do
    # 今日の記録を作成
    today_record = HabitRecord.create!(
      user: @user,
      habit: @habit,
      record_date: Date.current,
      completed: true
    )
    
    # 昨日の記録を作成
    yesterday_record = HabitRecord.create!(
      user: @user,
      habit: habits(:two),
      record_date: Date.current - 1.day,
      completed: false
    )
    
    # for_date スコープで今日の記録のみを取得
    results = HabitRecord.for_date(Date.current)
    
    # 今日の記録が含まれていることを確認
    assert_includes results, today_record
    
    # 昨日の記録が含まれていないことを確認
    assert_not_includes results, yesterday_record
  end

  # ----------------------------------------------------------------------------
  # 5-2. for_user スコープが正しく動作すること
  # ----------------------------------------------------------------------------
  test "for_user スコープが正しく動作すること" do
    # ユーザー1の記録を作成
    user1_record = HabitRecord.create!(
      user: @user,
      habit: @habit,
      record_date: Date.current,
      completed: true
    )
    
    # ユーザー2の記録を作成
    user2 = users(:two)
    user2_record = HabitRecord.create!(
      user: user2,
      habit: habits(:two),
      record_date: Date.current,
      completed: false
    )
    
    # for_user スコープでユーザー1の記録のみを取得
    results = HabitRecord.for_user(@user)
    
    # ユーザー1の記録が含まれていることを確認
    assert_includes results, user1_record
    
    # ユーザー2の記録が含まれていないことを確認
    assert_not_includes results, user2_record
  end

  # ============================================================================
  # 6. find_or_create_for メソッドのテスト
  # ============================================================================
  
  # ----------------------------------------------------------------------------
  # 6-1. 既存の記録がない場合は新規作成されること
  # ----------------------------------------------------------------------------
  test "既存の記録がない場合は新規作成されること" do
    # find_or_create_for メソッドを実行
    record = HabitRecord.find_or_create_for(@user, @habit, Date.current)
    
    # 新規作成されたことを確認
    assert record.persisted?, "習慣記録が作成されませんでした"
    
    # user_id が正しく設定されていることを確認
    assert_equal @user.id, record.user_id
    
    # habit_id が正しく設定されていることを確認
    assert_equal @habit.id, record.habit_id
    
    # record_date が正しく設定されていることを確認
    assert_equal Date.current, record.record_date
  end

  # ----------------------------------------------------------------------------
  # 6-2. 既存の記録がある場合は既存レコードを取得すること
  # ----------------------------------------------------------------------------
  test "既存の記録がある場合は既存レコードを取得すること" do
    # 既存の習慣記録を作成
    existing_record = HabitRecord.create!(
      user: @user,
      habit: @habit,
      record_date: Date.current,
      completed: true
    )
    
    # find_or_create_for メソッドを実行
    record = HabitRecord.find_or_create_for(@user, @habit, Date.current)
    
    # 既存レコードと同じIDであることを確認
    assert_equal existing_record.id, record.id
    
    # completed の値が保持されていることを確認
    assert record.completed
  end

  # ============================================================================
  # 7. toggle_completed! メソッドのテスト
  # ============================================================================
  
  # ----------------------------------------------------------------------------
  # 7-1. completed が false から true に切り替わること
  # ----------------------------------------------------------------------------
  test "completed が false から true に切り替わること" do
    # 習慣記録を保存（completed: false）
    @habit_record.save!
    
    # toggle_completed! メソッドを実行
    @habit_record.toggle_completed!
    
    # completed が true になったことを確認
    assert @habit_record.completed
  end

  # ----------------------------------------------------------------------------
  # 7-2. completed が true から false に切り替わること
  # ----------------------------------------------------------------------------
  test "completed が true から false に切り替わること" do
    # 習慣記録を保存（completed: true）
    @habit_record.completed = true
    @habit_record.save!
    
    # toggle_completed! メソッドを実行
    @habit_record.toggle_completed!
    
    # completed が false になったことを確認
    assert_not @habit_record.completed
  end
end