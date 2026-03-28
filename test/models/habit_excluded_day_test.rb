# test/models/habit_excluded_day_test.rb
#
# ==============================================================================
# HabitExcludedDay モデルテスト（B-2）
# ==============================================================================
# 【テストの目的】
#   ① バリデーションが正しく機能すること
#   ② UNIQUE制約（アプリ層・DB層）が機能すること
#   ③ Habit モデルの除外日関連メソッドが正しく動くこと
#   ④ 達成率計算が除外日を考慮した正しい分母で計算されること
# ==============================================================================

require "test_helper"

class HabitExcludedDayTest < ActiveSupport::TestCase
  # ============================================================
  # setup: 各テストの前に実行される準備処理
  # ============================================================
  # 【理由】
  #   毎回 User・Habit を作成するのはコードの重複なので
  #   setup メソッドにまとめてインスタンス変数に代入する。
  def setup
    @user = User.create!(
      name:             "テストユーザー",
      email:            "test_b2_#{SecureRandom.hex(4)}@example.com",
      password:         "password123",
      password_confirmation: "password123"
    )

    @habit = @user.habits.create!(
      name:             "筋トレ",
      weekly_target:    5,
      measurement_type: :check_type
    )
  end

  # ============================================================
  # ① バリデーションテスト
  # ============================================================

  test "有効な day_of_week（0〜6）で保存できる" do
    # 0（日）〜6（土）の全ての曜日で保存できることを確認する
    (0..6).each do |day|
      excluded_day = @habit.habit_excluded_days.build(day_of_week: day)
      assert excluded_day.valid?, "day_of_week=#{day} で invalid: #{excluded_day.errors.full_messages}"
    end
  end

  test "day_of_week が nil のとき無効になる" do
    excluded_day = @habit.habit_excluded_days.build(day_of_week: nil)
    assert_not excluded_day.valid?
    assert_includes excluded_day.errors[:day_of_week], "を入力してください"
  end

  test "day_of_week が 7 のとき無効になる（0〜6 の範囲外）" do
    excluded_day = @habit.habit_excluded_days.build(day_of_week: 7)
    assert_not excluded_day.valid?
    assert excluded_day.errors[:day_of_week].any?
  end

  test "day_of_week が -1 のとき無効になる（0〜6 の範囲外）" do
    excluded_day = @habit.habit_excluded_days.build(day_of_week: -1)
    assert_not excluded_day.valid?
    assert excluded_day.errors[:day_of_week].any?
  end

  # ============================================================
  # ② UNIQUE制約テスト（アプリ層）
  # ============================================================

  test "同じ habit_id と day_of_week の組み合わせは重複登録できない" do
    # 最初の保存は成功する
    @habit.habit_excluded_days.create!(day_of_week: 6)

    # 同じ組み合わせを再度保存しようとすると無効になる
    duplicate = @habit.habit_excluded_days.build(day_of_week: 6)
    assert_not duplicate.valid?
    assert duplicate.errors[:day_of_week].any?,
           "重複の土曜日はバリデーションエラーになるはず"
  end

  test "異なる habit_id なら同じ day_of_week で保存できる" do
    # 別の習慣を作成する
    other_habit = @user.habits.create!(
      name:             "読書",
      weekly_target:    5,
      measurement_type: :check_type
    )

    # 両方の習慣で土曜（6）を除外しても問題ない
    @habit.habit_excluded_days.create!(day_of_week: 6)
    other_excluded = other_habit.habit_excluded_days.build(day_of_week: 6)
    assert other_excluded.valid?, "異なる習慣で同じ曜日は保存できるはず"
  end

  # ============================================================
  # ③ Habit モデルの除外日関連メソッドテスト
  # ============================================================

  test "excluded_day_numbers が除外日の番号配列をソート順で返す" do
    @habit.habit_excluded_days.create!(day_of_week: 6)  # 土曜
    @habit.habit_excluded_days.create!(day_of_week: 0)  # 日曜

    # reload して最新状態を取得する
    # 【なぜ reload するのか】
    #   create! 後も @habit インスタンスはキャッシュを持っている場合がある。
    #   reload することで DB の最新状態を取得できる。
    @habit.reload
    assert_equal [0, 6], @habit.excluded_day_numbers,
                 "除外日番号が昇順（0=日, 6=土）でソートされるはず"
  end

  test "除外日がない場合 excluded_day_numbers は空配列を返す" do
    assert_equal [], @habit.excluded_day_numbers
  end

  test "effective_weekly_target が除外日を考慮した実施予定日数を返す" do
    # 目標5日・除外:土日(2日) → min(5, 7-2) = min(5, 5) = 5
    @habit.habit_excluded_days.create!(day_of_week: 6)  # 土
    @habit.habit_excluded_days.create!(day_of_week: 0)  # 日
    @habit.reload

    assert_equal 5, @habit.effective_weekly_target,
                 "目標5日・除外土日 → 実施予定日数は5"
  end

  test "effective_weekly_target: 除外日なしの場合は weekly_target と同じ値を返す" do
    # 除外日なし → min(5, 7) = 5
    assert_equal 5, @habit.effective_weekly_target
  end

  test "effective_weekly_target: 除外日が多い場合は実施可能日数を分母にする" do
    # 目標7日・除外5日 → min(7, 7-5) = min(7, 2) = 2
    habit_7 = @user.habits.create!(
      name: "毎日の習慣",
      weekly_target: 7,
      measurement_type: :check_type
    )
    [1, 2, 3, 4, 5].each { |d| habit_7.habit_excluded_days.create!(day_of_week: d) }
    habit_7.reload

    assert_equal 2, habit_7.effective_weekly_target,
                 "目標7日・除外5日 → 実施予定日数は2"
  end

  # ============================================================
  # ④ 達成率計算テスト（除外日考慮）
  # ============================================================

  test "チェック型: 土日除外で5日実施すると達成率100%になる" do
    # 土日を除外日に設定する
    @habit.habit_excluded_days.create!(day_of_week: 0)  # 日
    @habit.habit_excluded_days.create!(day_of_week: 6)  # 土
    @habit.reload

    # 今週月〜金の5日分の記録を作成する（AM4:00基準の今日を基点に）
    today = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    5.times do |i|
      @habit.habit_records.create!(
        user:        @user,
        record_date: week_start + i.days,
        completed:   true
      )
    end

    stats = @habit.weekly_progress_stats(@user)

    # 除外日考慮後の effective_weekly_target = 5 なので
    # 5日完了 / 5日 = 100%
    assert_equal 5, stats[:completed_count],
                 "5日実施されているはず"
    assert_equal 5, stats[:effective_target],
                 "除外土日後の実施予定日数は5のはず"
    assert_equal 100, stats[:rate],
                 "5/5 = 100% のはず"
  end

  test "チェック型: 除外日なしで weekly_target を分母にする（従来通り）" do
    # 除外日なし・3日完了・目標5日
    today = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    3.times do |i|
      @habit.habit_records.create!(
        user:        @user,
        record_date: week_start + i.days,
        completed:   true
      )
    end

    stats = @habit.weekly_progress_stats(@user)

    assert_equal 3, stats[:completed_count]
    assert_equal 5, stats[:effective_target],
                 "除外日なし → effective_target = weekly_target = 5"
    assert_equal 60, stats[:rate],   # 3/5 = 60%
                 "3/5 = 60% のはず"
  end

  test "数値型: 除外日を設定しても weekly_target を分母にする" do
    # 数値型習慣に除外日を設定しても達成率の分母は変わらない
    numeric_habit = @user.habits.create!(
      name:             "ジョギング",
      weekly_target:    150,
      measurement_type: :numeric_type,
      unit:             "分"
    )
    # 除外日を設定する（数値型では影響しないはず）
    numeric_habit.habit_excluded_days.create!(day_of_week: 6)
    numeric_habit.habit_excluded_days.create!(day_of_week: 0)
    numeric_habit.reload

    today = HabitRecord.today_for_record
    numeric_habit.habit_records.create!(
      user:          @user,
      record_date:   today,
      completed:     true,
      numeric_value: 150.0
    )

    stats = numeric_habit.weekly_progress_stats(@user)

    # 数値型は weekly_target（150）が分母
    assert_equal 150, stats[:effective_target],
                 "数値型は除外日に関わらず weekly_target = 150 が分母のはず"
    assert_equal 100, stats[:rate],
                 "150/150 = 100% のはず"
  end
  
  # ============================================================
  # ⑤ 除外日を全て外す操作のテスト（destroy_all 設計の検証）
  # ============================================================

  test "除外日を全て外すと空配列になる" do
    # 事前に除外日を設定する
    @habit.habit_excluded_days.create!(day_of_week: 0)  # 日
    @habit.habit_excluded_days.create!(day_of_week: 6)  # 土
    @habit.reload

    # 除外日が設定されていることを確認する
    assert_equal [0, 6], @habit.excluded_day_numbers

    # Controller の save_excluded_days! が行う操作を再現する
    # 【なぜ destroy_all を使うのか】
    #   「チェックを全て外す」= params[:excluded_day_numbers] が nil になる。
    #   destroy_all で既存データを消してから return することで
    #   「全除外解除」が正しく DB に反映される。
    @habit.habit_excluded_days.destroy_all
    @habit.reload

    # 全て削除されていることを確認する
    assert_equal [], @habit.excluded_day_numbers,
                 "全除外設定を解除すると空配列になるはず"

    # effective_weekly_target も元の weekly_target に戻ることを確認する
    assert_equal @habit.weekly_target, @habit.effective_weekly_target,
                 "除外日がなくなると effective_weekly_target = weekly_target になるはず"
  end
end