# test/services/habit_record_save_service_test.rb
# 日付を未来（フィクスチャと衝突しない日付）に変更する
#
# 【修正理由】
#   フィクスチャ habit_records.yml が 2.days.ago（2026-04-10）と
#   3.days.ago（2026-04-09）を使っている。
#   テスト1が travel_to 2026-04-10 を使っていたため
#   UNIQUE(user_id, habit_id, record_date) 制約が衝突していた。
#   未来日付（フィクスチャが絶対に使わない日付）に変更することで解決する。
require "test_helper"

class HabitRecordSaveServiceTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)
  end

  # 【テスト1】正常に習慣記録が保存されること
  # 日付を未来（2030-01-01）に変更してフィクスチャと衝突しないようにする
  test "call が成功すると HabitRecord が作成されること" do
    travel_to Time.zone.local(2030, 1, 1, 10, 0, 0) do
      assert_difference "HabitRecord.count", 1 do
        result = HabitRecordSaveService.new(
          user:      @user,
          habit:     @habit,
          completed: true
        ).call
        assert result[:success], "call は成功を返すべき: #{result[:errors]}"
        assert_not_nil result[:habit_record], "habit_record が戻り値に含まれるべき"
        assert result[:habit_record].completed, "completed が true になるべき"
      end
    end
  end

  # 【テスト2】既存レコードの更新
  # 日付を未来（2030-01-02）に変更してテスト1とも衝突しないようにする
  test "既存の HabitRecord がある場合は更新されること" do
    travel_to Time.zone.local(2030, 1, 2, 10, 0, 0) do
      existing = HabitRecord.create!(
        user:        @user,
        habit:       @habit,
        record_date: HabitRecord.today_for_record,
        completed:   false
      )
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
  # 日付を未来（2030-01-03）に変更してテスト1・2とも衝突しないようにする
  test "成功時は { success: true, habit_record: ... } を返すこと" do
    travel_to Time.zone.local(2030, 1, 3, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:      @user,
        habit:     @habit,
        completed: true
      ).call
      assert_equal true, result[:success]
      assert_instance_of HabitRecord, result[:habit_record]
    end
  end
end