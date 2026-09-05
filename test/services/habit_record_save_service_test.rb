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
    @habit = habits(:habit_one)   # チェック型・除外日なし（読書・weekly_target 7）
  end

  # 【テスト1】正常に習慣記録が保存されること
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

  # ============================================================================
  # 【テスト4〜9】#I-3: 記録保存時のストリーク即時再計算
  # ============================================================================
  #   記録を保存したタイミングで @habit.calculate_streak! が呼ばれ、
  #   current_streak / longest_streak が最新化されることを検証する。
  #   habit_one は除外日なしのチェック型なので、具体的な連続日数で検証できる。

  # 【テスト4】今日を達成すると current_streak が 1 になること（=保存時に再計算される）
  test "今日の記録を達成にすると current_streak が 1 になること" do
    travel_to Time.zone.local(2030, 1, 15, 10, 0, 0) do
      HabitRecordSaveService.new(
        user:      @user,
        habit:     @habit,
        completed: true
      ).call
      assert_equal 1, @habit.reload.current_streak,
                   "今日を達成すると current_streak は 1 に再計算されるべき"
    end
  end

  # 【テスト5】3日連続で達成すると current_streak が 3 になること
  test "3日連続で達成すると current_streak が 3 になること" do
    [ 20, 21, 22 ].each do |day|
      travel_to Time.zone.local(2030, 1, day, 10, 0, 0) do
        HabitRecordSaveService.new(
          user:      @user,
          habit:     @habit,
          completed: true
        ).call
      end
    end
    assert_equal 3, @habit.reload.current_streak,
                 "3日連続達成で current_streak は 3 になるべき"
    assert_operator @habit.reload.longest_streak, :>=, 3,
                    "longest_streak も 3 以上に更新されるべき"
  end

  # 【テスト6】今日の記録を未達成に戻すと current_streak が 0 になること
  test "今日の記録を completed:false にすると current_streak が 0 になること" do
    travel_to Time.zone.local(2030, 1, 11, 10, 0, 0) do
      HabitRecordSaveService.new(user: @user, habit: @habit, completed: true).call
      HabitRecordSaveService.new(user: @user, habit: @habit, completed: false).call
      assert_equal 0, @habit.reload.current_streak,
                   "今日の記録を外すと現在のストリークは 0 に再計算されるべき"
    end
  end

  # 【テスト7】memo だけ更新しても completed が維持されること（NOT_PROVIDED 設計）
  test "memo だけ更新しても既存の completed が維持されること" do
    travel_to Time.zone.local(2030, 1, 12, 10, 0, 0) do
      HabitRecordSaveService.new(user: @user, habit: @habit, completed: true).call

      result = HabitRecordSaveService.new(
        user:  @user,
        habit: @habit,
        memo:  "テストメモ"
      ).call

      assert result[:success], "memo 更新は成功すべき: #{result[:errors]}"
      assert_equal "テストメモ", result[:habit_record].memo, "memo が更新されるべき"
      assert result[:habit_record].completed,
             "memo だけ更新しても completed は true のまま維持されるべき"
    end
  end

  # 【テスト8】数値型: numeric_value > 0 で completed=true になりストリークが再計算されること
  #   habit_numeric は fixture_only_user 所有なので、そのユーザーとペアで使う。
  test "数値型: numeric_value > 0 で completed=true になり current_streak が 1 になること" do
    numeric_user  = users(:fixture_only_user)
    numeric_habit = habits(:habit_numeric)
    travel_to Time.zone.local(2030, 1, 25, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:          numeric_user,
        habit:         numeric_habit,
        numeric_value: 30
      ).call
      assert result[:success], "保存は成功すべき: #{result[:errors]}"
      assert result[:habit_record].completed,
             "numeric_value > 0 なら completed は true になるべき"
      assert_equal 1, numeric_habit.reload.current_streak,
                   "今日達成すると current_streak は 1 になるべき"
    end
  end

  # 【テスト9】数値型: numeric_value = 0 で completed=false になること
  test "数値型: numeric_value = 0 で completed=false になり current_streak が 0 のままであること" do
    numeric_user  = users(:fixture_only_user)
    numeric_habit = habits(:habit_numeric)
    travel_to Time.zone.local(2030, 1, 26, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:          numeric_user,
        habit:         numeric_habit,
        numeric_value: 0
      ).call
      assert result[:success], "保存は成功すべき: #{result[:errors]}"
      assert_not result[:habit_record].completed,
                 "numeric_value = 0 なら completed は false になるべき"
      assert_equal 0, numeric_habit.reload.current_streak,
                   "未達成なので current_streak は 0 のままであるべき"
    end
  end
end
