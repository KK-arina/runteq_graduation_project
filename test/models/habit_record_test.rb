# test/models/habit_record_test.rb
#
# ==============================================================================
# 【テスト失敗修正】
#
#   ❸ Service 経由での数値型保存テストが失敗する問題
#
#   【原因】
#     HabitRecordSaveService を使って numeric_value: 30.5 を渡しているが、
#     Service 内の find_or_create_for が completed: false で新規レコードを作成する際、
#     numeric_value が nil のままになるためバリデーションエラーが発生していた。
#
#     HabitRecord.find_or_create_for の内部:
#       find_or_create_by!(user:, habit:, record_date:)
#     → numeric_value を指定していないため nil で作成しようとする
#     → numeric_value_required_for_numeric_type バリデーションで弾かれる
#
#   【修正方法】
#     HabitRecord.find_or_create_for を数値型対応にする必要がある。
#     ただし find_or_create_for は HabitRecord モデルのクラスメソッドで、
#     チェック型・数値型両方に使われているため、
#     数値型のときだけ numeric_value: 0.0 の初期値を渡すよう変更する。
#
#     → HabitRecord モデルの find_or_create_for を修正する（別ファイルで対応）
#     → このテストファイルは修正不要
#
#   ❸-補足: HabitRecordSaveService テストの日付重複問題
#     test/services/habit_record_save_service_test.rb の
#     「既存の HabitRecord がある場合は更新されること」で UNIQUE 制約違反が起きている。
#     これは別の既存テストが同日に record を作成済みのため。
#     → travel_to で別日付に移動してテストを実行する（service_test に修正を反映）
# ==============================================================================
#
# 【HabitRecord.find_or_create_for の修正が必要な箇所】
#   app/models/habit_record.rb の find_or_create_for を以下のように変更する:
#
#   def self.find_or_create_for(user, habit, date = today_for_record)
#     if habit.numeric_type?
#       # 数値型: numeric_value: 0.0 で初期作成（バリデーション通過のため）
#       create_with(numeric_value: 0.0, completed: false)
#         .find_or_create_by!(user: user, habit: habit, record_date: date)
#     else
#       find_or_create_by!(user: user, habit: habit, record_date: date)
#     end
#   end
#
# このファイルの変更は最小限。既存テストを壊さないよう
# 数値型のテストを travel_to で日付を明示して重複を避ける。

require "test_helper"

class HabitRecordTest < ActiveSupport::TestCase
  setup do
    @user        = users(:one)
    @check_habit = habits(:habit_one)
    @habit_record = HabitRecord.new(
      user: @user, habit: @check_habit,
      record_date: Date.current, completed: false
    )
  end

  # ============================================================
  # 既存テスト（変更なし）
  # ============================================================

  test "有効な習慣記録は保存できること" do
    assert @habit_record.valid?, @habit_record.errors.full_messages
    assert @habit_record.save
  end

  test "record_date が nil の場合は無効" do
    @habit_record.record_date = nil
    assert_not @habit_record.valid?
    assert @habit_record.errors.added?(:record_date, :blank)
  end

  test "completed が nil の場合は無効" do
    record = HabitRecord.new(
      user: @user, habit: @check_habit,
      record_date: Date.current, completed: nil
    )
    assert_not record.valid?
    assert_includes record.errors.map(&:type), :inclusion
    assert_equal 1, record.errors[:completed].count
  end

  test "同じユーザー・習慣・日付の記録は重複して作成できないこと" do
    @habit_record.save!
    duplicate = HabitRecord.new(
      user: @user, habit: @check_habit,
      record_date: @habit_record.record_date, completed: true
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors.map(&:type), :taken
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

  # ============================================================
  # B-1: numeric_value バリデーションテスト
  # ============================================================

  test "B-1: チェック型では numeric_value が nil でも有効" do
    record = HabitRecord.new(
      user: @user, habit: @check_habit,
      record_date: Date.current, completed: true, numeric_value: nil
    )
    assert record.valid?, record.errors.full_messages
  end

  test "B-1: 数値型で numeric_value が 0 のとき有効" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )
    record = HabitRecord.new(
      user: @user, habit: numeric_habit,
      record_date: Date.current, completed: false, numeric_value: 0
    )
    assert record.valid?, record.errors.full_messages
  end

  test "B-1: 数値型で numeric_value が正の数のとき有効" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )
    record = HabitRecord.new(
      user: @user, habit: numeric_habit,
      record_date: Date.current, completed: true, numeric_value: 30.5
    )
    assert record.valid?, record.errors.full_messages
  end

  test "B-1: 数値型で numeric_value が負の数のとき無効" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )
    record = HabitRecord.new(
      user: @user, habit: numeric_habit,
      record_date: Date.current, completed: false, numeric_value: -1.0
    )
    assert_not record.valid?
    assert record.errors[:numeric_value].any?
  end

  test "B-1: 数値型で numeric_value が nil のとき無効" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )
    record = HabitRecord.new(
      user: @user, habit: numeric_habit,
      record_date: Date.current, completed: false, numeric_value: nil
    )
    assert_not record.valid?
    assert record.errors[:numeric_value].any?
  end

  test "B-1: update_numeric_value! で numeric_value を更新できること" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )
    # ── travel_to で日付を固定して UNIQUE 制約の重複を回避 ──────────────────
    travel_to Time.zone.local(2026, 4, 1, 10, 0, 0) do
      record = HabitRecord.create!(
        user: @user, habit: numeric_habit,
        record_date: HabitRecord.today_for_record, completed: false, numeric_value: 0
      )
      record.update_numeric_value!(30.0)
      record.reload
      assert_equal 30.0, record.numeric_value.to_f
    end
  end

  # ============================================================
  # B-1: HabitRecordSaveService テスト
  # ============================================================

  test "B-1: チェック型習慣を Service 経由で保存できること" do
    # travel_to で既存テストと日付が重複しないようにする
    travel_to Time.zone.local(2026, 4, 1, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:      @user,
        habit:     @check_habit,
        completed: true
      ).call

      assert result[:success], result[:errors].inspect
      assert result[:habit_record].completed
      assert_nil result[:habit_record].numeric_value
    end
  end

  test "B-1: 数値型習慣を Service 経由で保存できること" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    travel_to Time.zone.local(2026, 4, 1, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:          @user,
        habit:         numeric_habit,
        numeric_value: 30.5
      ).call

      assert result[:success], result[:errors].inspect
      assert_equal 30.5, result[:habit_record].numeric_value.to_f
      assert result[:habit_record].completed
    end
  end

  test "B-1: 数値型で numeric_value=0 のとき completed は false" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    travel_to Time.zone.local(2026, 4, 1, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:          @user,
        habit:         numeric_habit,
        numeric_value: 0.0
      ).call

      assert result[:success], result[:errors].inspect
      assert_not result[:habit_record].completed
    end
  end

  # ── 修正: 超小数テストも travel_to で日付を分離 ──────────────────────────
  test "B-1: 数値型で numeric_value が 0.0001（超小数）のとき完了扱いになること" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    travel_to Time.zone.local(2026, 4, 2, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:          @user,
        habit:         numeric_habit,
        numeric_value: 0.0001
      ).call

      assert result[:success], result[:errors].inspect
      assert result[:habit_record].completed,
             "0.0001 > 0 なので completed: true になるべき"
    end
  end

  test "B-1: 数値型で numeric_value=nil のとき Service は失敗を返すこと" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    travel_to Time.zone.local(2026, 4, 3, 10, 0, 0) do
      result = HabitRecordSaveService.new(
        user:          @user,
        habit:         numeric_habit,
        numeric_value: nil
      ).call

      assert_not result[:success]
      assert result[:errors].is_a?(Array)
      assert result[:errors].any?
    end
  end
end
