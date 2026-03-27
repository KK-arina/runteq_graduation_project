# test/services/habit_record_save_service_test.rb
#
# ============================================================
# 【テスト失敗修正】
#
# 【問題】
#   3つのテストが同じ日付（2026-03-22）を使っていたため、
#   テスト実行順序によってレコードが重複し UNIQUE 制約違反が発生していた。
#   Rails の Minitest はテストをランダム順で実行するため、
#   同じ日付・同じ習慣のレコードが別テストで作成済みになる場合がある。
#
# 【修正方針】
#   各テストに異なる日付を割り当てる（1日ずつずらす）。
#   これにより UNIQUE(user_id, habit_id, record_date) 制約の衝突を回避する。
#   テスト1: 2026-04-10（既存のテストと重複しない未来日付）
#   テスト2: 2026-04-11
#   テスト3: 2026-04-12
#   ※ 2026-03-22 は他のテストで使われている可能性があるため使用しない
# ============================================================

require "test_helper"

class HabitRecordSaveServiceTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)
  end

  # 【テスト1】正常に習慣記録が保存されること
  # 日付: 2026-04-10（他テストと重複しない日付を使用）
  test "call が成功すると HabitRecord が作成されること" do
    travel_to Time.zone.local(2026, 4, 10, 10, 0, 0) do
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
  # 日付: 2026-04-11（テスト1と異なる日付）
  test "既存の HabitRecord がある場合は更新されること" do
    travel_to Time.zone.local(2026, 4, 11, 10, 0, 0) do
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
  # 日付: 2026-04-12（テスト1・2と異なる日付）
  test "成功時は { success: true, habit_record: ... } を返すこと" do
    travel_to Time.zone.local(2026, 4, 12, 10, 0, 0) do
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
