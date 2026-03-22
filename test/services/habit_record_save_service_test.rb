# test/services/habit_record_save_service_test.rb
#
# ============================================================
# 【このファイルの役割】
# HabitRecordSaveService のトランザクション動作をテストする。
# ============================================================

require "test_helper"

class HabitRecordSaveServiceTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)
  end

  # 【テスト1】正常に習慣記録が保存されること
  test "call が成功すると HabitRecord が作成されること" do
    travel_to Time.zone.local(2026, 3, 22, 10, 0, 0) do
      assert_difference "HabitRecord.count", 1 do
        result = HabitRecordSaveService.new(
          user:      @user,
          habit:     @habit,
          completed: true
        ).call

        assert result[:success], "call は成功を返すべき: #{result[:error]}"
        assert_not_nil result[:habit_record], "habit_record が戻り値に含まれるべき"
        assert result[:habit_record].completed, "completed が true になるべき"
      end
    end
  end

  # 【テスト2】既存レコードの更新
  test "既存の HabitRecord がある場合は更新されること" do
    travel_to Time.zone.local(2026, 3, 22, 10, 0, 0) do
      # 事前に今日の記録を作成する
      existing = HabitRecord.create!(
        user:        @user,
        habit:       @habit,
        record_date: HabitRecord.today_for_record,
        completed:   false
      )

      # 件数が増えないことを確認（新規作成ではなく更新）
      assert_no_difference "HabitRecord.count" do
        result = HabitRecordSaveService.new(
          user:      @user,
          habit:     @habit,
          completed: true
        ).call

        assert result[:success]
        assert_equal existing.id, result[:habit_record].id,
                     "既存のレコードが返されるべき"
        assert result[:habit_record].completed,
               "completed が true に更新されるべき"
      end
    end
  end

  # 【テスト3】成功時の戻り値
  test "成功時は { success: true, error: nil, habit_record: ... } を返すこと" do
    travel_to Time.zone.local(2026, 3, 22, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:      @user,
        habit:     @habit,
        completed: true
      ).call

      assert_equal true,  result[:success]
      assert_nil          result[:error]
      assert_instance_of  HabitRecord, result[:habit_record]
    end
  end
end