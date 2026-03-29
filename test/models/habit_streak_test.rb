# test/models/habit_streak_test.rb
#
# ==============================================================================
# B-3: ストリーク計算テスト
# ==============================================================================
#
# 【テストの目的】
#   Habit#calculate_streak! と HabitRecord の状態判定メソッドが
#   正しく動作することを確認する。
#
# 【travel_to を使う理由】
#   ストリーク計算は「今日の日付」に依存するため、
#   travel_to で日付を固定してテストの再現性を保証する。
#   テスト実行日によって結果が変わる「不安定なテスト」を防ぐ。
#
# 【AM4:00 境界テストの重要性】
#   HabitFlow では AM4:00 を1日の境界として扱うため、
#   3:59 と 4:00 の境界前後でテストして動作を確認する。
#
# ==============================================================================

require "test_helper"

class HabitStreakTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @habit = @user.habits.create!(
      name:             "テスト習慣（ストリーク）",
      weekly_target:    7,
      measurement_type: :check_type
    )
    # user_setting がない場合に on_rest_mode? が nil を返さないよう作成する
    # UserSetting.find_or_create_by! を使うことで重複エラーを防ぐ
    @user_setting = UserSetting.find_or_create_by!(user: @user) do |s|
      s.time_zone                = "Asia/Tokyo"
      s.daily_notification_limit = 5
      s.ai_analysis_monthly_limit = 10
    end
  end

  # ============================================================
  # ① calculate_streak! の基本動作テスト
  # ============================================================

  test "記録が0件のとき current_streak は 0 になること" do
    # travel_to: テスト実行日を水曜日 AM10:00 に固定する
    # 理由: 週の途中の日付で「記録なし = streak 0」を確認するため
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      result = @habit.calculate_streak!
      assert_equal 0, result
      @habit.reload
      assert_equal 0, @habit.current_streak
      assert_equal 0, @habit.longest_streak
    end
  end

  test "今日だけ完了したとき current_streak は 1 になること" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      today = HabitRecord.today_for_record
      HabitRecord.create!(
        user: @user, habit: @habit,
        record_date: today, completed: true
      )
      result = @habit.calculate_streak!
      assert_equal 1, result
      @habit.reload
      assert_equal 1, @habit.current_streak
    end
  end

  test "今日・昨日連続完了したとき current_streak は 2 になること" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      today     = HabitRecord.today_for_record
      yesterday = today - 1

      HabitRecord.create!(user: @user, habit: @habit, record_date: today,     completed: true)
      HabitRecord.create!(user: @user, habit: @habit, record_date: yesterday,  completed: true)

      result = @habit.calculate_streak!
      assert_equal 2, result
    end
  end

  test "3日連続完了したとき current_streak は 3 になること" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      today = HabitRecord.today_for_record

      3.times do |i|
        HabitRecord.create!(
          user: @user, habit: @habit,
          record_date: today - i, completed: true
        )
      end

      result = @habit.calculate_streak!
      assert_equal 3, result
    end
  end

  test "昨日だけ達成・今日未達成のとき current_streak は 0 になること" do
    # 「今日が未達成なら streak は 0」という仕様の確認
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      yesterday = HabitRecord.today_for_record - 1
      HabitRecord.create!(user: @user, habit: @habit, record_date: yesterday, completed: true)

      result = @habit.calculate_streak!
      # 今日の記録がないので streak = 0
      assert_equal 0, result
    end
  end

  # ============================================================
  # ② longest_streak の保護テスト
  # ============================================================

  test "longest_streak は streak が小さくなっても上書きされないこと" do
    # 最高記録を先にセットしておく
    @habit.update_columns(longest_streak: 10, current_streak: 10)

    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      today = HabitRecord.today_for_record
      # 今日だけ達成（streak = 1）
      HabitRecord.create!(user: @user, habit: @habit, record_date: today, completed: true)

      @habit.calculate_streak!
      @habit.reload

      # current_streak は 1 に更新されるが longest_streak は 10 のまま
      assert_equal 1,  @habit.current_streak
      assert_equal 10, @habit.longest_streak, "longest_streak は上書きされてはいけない"
    end
  end

  test "streak が longest_streak を超えたとき longest_streak も更新されること" do
    @habit.update_columns(longest_streak: 2, current_streak: 2)

    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      today = HabitRecord.today_for_record

      # 3日連続達成（streak = 3 > longest_streak = 2）
      3.times do |i|
        HabitRecord.create!(
          user: @user, habit: @habit,
          record_date: today - i, completed: true
        )
      end

      @habit.calculate_streak!
      @habit.reload

      assert_equal 3, @habit.current_streak
      assert_equal 3, @habit.longest_streak, "streak が過去最高を超えたので更新されるべき"
    end
  end

  # ============================================================
  # ③ 除外日テスト
  # ============================================================

  test "除外日（日曜）はスキップしてストリークが継続すること" do
    # 水曜日 AM10:00 に固定
    # 2026/4/6(月) 〜 2026/4/8(水) で、4/5(日)が除外日の場合
    # 月〜水の3日間達成でもストリークは3になるべき
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      # 日曜を除外日として設定
      HabitExcludedDay.create!(habit: @habit, day_of_week: 0) # 0 = 日曜

      today = HabitRecord.today_for_record # 2026-04-08（水）

      # 月・火・水の3日間達成
      # 2026-04-06(月), 2026-04-07(火), 2026-04-08(水)
      [ today, today - 1, today - 2 ].each do |date|
        HabitRecord.create!(user: @user, habit: @habit, record_date: date, completed: true)
      end

      result = @habit.calculate_streak!

      # 土曜日(2026-04-04)と日曜日(2026-04-05)が存在するが、
      # 日曜は除外日なのでスキップ。
      # 土曜(2026-04-04)は記録なし → ループがそこで break
      # → streak = 3（月・火・水）
      assert_equal 3, result,
                   "除外日（日曜）はスキップされてストリークが継続するべき"
    end
  end

  test "除外日が連続していてもストリークが正しく計算されること" do
    # 土・日を除外日として設定し、月〜金の5日間達成をテスト
    travel_to Time.zone.local(2026, 4, 11, 10, 0, 0) do # 土曜日
      HabitExcludedDay.create!(habit: @habit, day_of_week: 0) # 日曜
      HabitExcludedDay.create!(habit: @habit, day_of_week: 6) # 土曜

      today = HabitRecord.today_for_record # 2026-04-11（土）

      # 月〜金の5日間達成（土曜は除外日なので今日は記録しない）
      # 2026-04-06(月) 〜 2026-04-10(金)
      5.times do |i|
        date = today - 1 - i  # 金・木・水・火・月
        HabitRecord.create!(user: @user, habit: @habit, record_date: date, completed: true)
      end

      result = @habit.calculate_streak!

      # 土(今日)は除外 → 金〜月の5日間でストリーク5
      # その前の日曜も除外 → さらに前の土曜は記録なし → break
      assert_equal 5, result,
                   "土日除外で月〜金の5日間達成はストリーク5になるべき"
    end
  end

  # ============================================================
  # ④ お休みモードテスト（rest_mode_on_date? を使う修正版）
  # ============================================================

  test "お休みモード中（allow_rest_mode=true）は記録がなくてもストリークを維持すること" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      # 現在から10日後までお休みモード設定
      # → 4/8(今日)もお休みモード中
      @user_setting.update!(rest_mode_until: Time.current + 10.days)

      # 今日の記録なし・過去の記録もなし
      result = @habit.calculate_streak!

      # 「お休みモード中は未達成をスキップ」だが、
      # 達成記録が1件もないため遡っても streak は増えない → 0
      assert_equal 0, result
    end
  end

  test "お休みモード中でも過去に達成記録があればストリークが継続すること" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      # rest_mode_until を今日以降に設定
      # → 今日(4/8)もお休みモード中
      @user_setting.update!(rest_mode_until: Time.zone.local(2026, 4, 10))

      today = HabitRecord.today_for_record # 2026-04-08

      # 今日(4/8)の記録なし・昨日(4/7)達成済み
      HabitRecord.create!(user: @user, habit: @habit, record_date: today - 1, completed: true)

      result = @habit.calculate_streak!

      # 4/8(今日): 記録なし → rest_mode_on_date?(2026-04-08) は true → スキップ
      # 4/7(昨日): 達成 → streak + 1
      # 4/6: 記録なし → rest_mode_on_date?(2026-04-06) は false → break
      # → streak = 1
      assert_equal 1, result,
                   "お休みモード中は今日をスキップして昨日の達成を継続とみなすべき"
    end
  end

  test "お休みモード終了後の過去日付はスキップされないこと" do
    # 【このテストの目的】
    #   rest_mode_on_date? が「日付単位」で正しく判定できているかを確認する。
    #   on_rest_mode?（現在のみ判定）との違いを検証する重要なテスト。
    travel_to Time.zone.local(2026, 4, 12, 10, 0, 0) do
      # rest_mode_until を 4/10（金）に設定
      # → 4/12（今日）はお休みモード終了後
      @user_setting.update!(rest_mode_until: Time.zone.local(2026, 4, 10))

      today = HabitRecord.today_for_record # 2026-04-12（日）

      # 今日(4/12)の記録なし
      # 4/11(土)の記録なし
      # 4/10(金)達成済み（お休みモード最終日）
      HabitRecord.create!(user: @user, habit: @habit, record_date: Date.new(2026, 4, 10), completed: true)

      result = @habit.calculate_streak!

      # 4/12(今日): 記録なし → rest_mode_on_date?(4/12) は false（終了後）→ break
      # → streak = 0
      assert_equal 0, result,
                   "お休みモード終了後の日付は通常通りの判定になるべき"
    end
  end

  test "allow_rest_mode=false の習慣はお休みモード中でもストリークがリセットされること" do
    # allow_rest_mode = false に設定
    @habit.update_columns(allow_rest_mode: false)

    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      @user_setting.update!(rest_mode_until: Time.zone.local(2026, 4, 10))

      yesterday = HabitRecord.today_for_record - 1
      HabitRecord.create!(user: @user, habit: @habit, record_date: yesterday, completed: true)

      result = @habit.calculate_streak!

      # allow_rest_mode = false なので rest_mode_on_date? は false を返す
      # → 今日の未達成で break → streak = 0
      assert_equal 0, result,
                   "allow_rest_mode=false の習慣はお休みモード中でもリセットされるべき"
    end
  end

  # ============================================================
  # ⑤ AM4:00 境界テスト
  # ============================================================

  test "AM3:59 は前日の日付として扱われること" do
    travel_to Time.zone.local(2026, 4, 8, 3, 59, 0) do
      # 3:59 は「前日（4月7日）」として扱われる
      assert_equal Date.new(2026, 4, 7), HabitRecord.today_for_record
    end
  end

  test "AM4:00 は当日の日付として扱われること" do
    travel_to Time.zone.local(2026, 4, 8, 4, 0, 0) do
      # 4:00 は「当日（4月8日）」として扱われる
      assert_equal Date.new(2026, 4, 8), HabitRecord.today_for_record
    end
  end

  test "AM3:59 時点のストリーク計算は前日基準になること" do
    travel_to Time.zone.local(2026, 4, 8, 3, 59, 0) do
      # この時点での「今日」は 4月7日（火）
      today = HabitRecord.today_for_record
      assert_equal Date.new(2026, 4, 7), today

      # 4月7日（火）と4月6日（月）に達成記録
      HabitRecord.create!(user: @user, habit: @habit, record_date: today,     completed: true)
      HabitRecord.create!(user: @user, habit: @habit, record_date: today - 1,  completed: true)

      result = @habit.calculate_streak!
      assert_equal 2, result
    end
  end

  # ============================================================
  # ⑥ 数値型習慣のストリークテスト
  # ============================================================

  test "数値型習慣でも numeric_value > 0 のときストリークが増加すること" do
    numeric_habit = @user.habits.create!(
      name:             "ジョギング",
      weekly_target:    5,
      measurement_type: :numeric_type,
      unit:             "分"
    )

    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      today = HabitRecord.today_for_record

      HabitRecord.create!(
        user: @user, habit: numeric_habit,
        record_date: today, completed: true, numeric_value: 30.0
      )

      result = numeric_habit.calculate_streak!
      assert_equal 1, result
    end
  end

  test "数値型習慣で numeric_value = 0 のときストリークが増加しないこと" do
    numeric_habit = @user.habits.create!(
      name:             "ジョギング",
      weekly_target:    5,
      measurement_type: :numeric_type,
      unit:             "分"
    )

    travel_to Time.zone.local(2026, 4, 9, 10, 0, 0) do
      today = HabitRecord.today_for_record

      HabitRecord.create!(
        user: @user, habit: numeric_habit,
        record_date: today, completed: false, numeric_value: 0.0
      )

      result = numeric_habit.calculate_streak!
      assert_equal 0, result
    end
  end

  # ============================================================
  # ⑦ HabitRecord の状態判定メソッドテスト
  # ============================================================

  test "recorded?: チェック型で completed=true のとき true を返すこと" do
    travel_to Time.zone.local(2026, 4, 10, 10, 0, 0) do
      record = HabitRecord.create!(
        user: @user, habit: @habit,
        record_date: HabitRecord.today_for_record, completed: true
      )
      assert record.recorded?
    end
  end

  test "recorded?: チェック型で completed=false のとき false を返すこと" do
    travel_to Time.zone.local(2026, 4, 11, 10, 0, 0) do
      record = HabitRecord.create!(
        user: @user, habit: @habit,
        record_date: HabitRecord.today_for_record, completed: false
      )
      assert_not record.recorded?
    end
  end

  test "first_recorded_today?: 今日作成されたレコードで true を返すこと" do
    travel_to Time.zone.local(2026, 4, 12, 10, 0, 0) do
      record = HabitRecord.create!(
        user: @user, habit: @habit,
        record_date: HabitRecord.today_for_record, completed: true
      )
      assert record.first_recorded_today?
    end
  end

# test/models/habit_streak_test.rb の
# 「first_recorded_today?: 昨日作成されたレコードで false を返すこと」テストのみ修正
#
# 【エラーの原因】
#   travel_to ブロックの中に別の travel_to ブロックをネストすると
#   Rails が警告ではなく RuntimeError を発生させる。
#   （Rails 7.x 以降は入れ子の travel_to を禁止している）
#
# 【修正方針】
#   「昨日作成されたレコード」を再現するために travel_to のネストを使っていたが、
#   update_columns で created_at を直接書き換えてから
#   travel_to を1つだけ使う方式に変更する。
#
#   具体的な手順:
#   1. 今日（4/13）のコンテキストで travel_to する
#   2. record_date を昨日（4/12）にしてレコードを作成する
#   3. created_at を昨日に強制変更（update_columns 使用）
#   4. first_recorded_today? が false を返すことを確認する

  test "first_recorded_today?: 昨日作成されたレコードで false を返すこと" do
    # travel_to で「今日」を 4/13 に固定する
    # 【理由】
    #   first_recorded_today? は「created_at が today_for_record と一致するか」を
    #   判定するため、「今日」が何日かを固定する必要がある。
    travel_to Time.zone.local(2026, 4, 13, 10, 0, 0) do
      # 昨日(4/12)の record_date でレコードを作成する
      # record_date を昨日にすることで UNIQUE 制約（同日・同習慣の重複）を回避する
      record = HabitRecord.create!(
        user:        @user,
        habit:       @habit,
        record_date: Date.new(2026, 4, 12), # 昨日の日付
        completed:   false
      )

      # created_at を昨日（4/12）に強制変更する
      # 【なぜ update_columns を使うのか】
      #   update! は created_at を変更できない（Railsが自動管理するため）。
      #   update_columns はバリデーションと自動タイムスタンプ更新をスキップするため、
      #   created_at を任意の値に直接変更できる。
      # 【なぜ travel_to をネストしないのか】
      #   Rails 7.x 以降は travel_to のネストを RuntimeError として禁止している。
      #   代わりに created_at を直接書き換えることで「昨日作成」を再現する。
      record.update_columns(created_at: Time.zone.local(2026, 4, 12, 10, 0, 0))

      # 「今日（4/13）のコンテキスト」で first_recorded_today? を呼ぶ
      # created_at が 4/12 なので today_for_record（4/13）と一致しない → false
      assert_not record.first_recorded_today?,
                 "昨日作成のレコードは first_recorded_today? が false であるべき"
    end
  end

  test "updated_today?: 今日更新されたレコードで true を返すこと" do
    travel_to Time.zone.local(2026, 4, 14, 10, 0, 0) do
      record = HabitRecord.create!(
        user: @user, habit: @habit,
        record_date: HabitRecord.today_for_record, completed: false
      )
      # created_at を過去に変更してから update して「今日更新」を再現
      record.update_columns(created_at: Time.current - 1.day)
      record.update!(completed: true)

      assert record.updated_today?,
             "today更新されたレコードは updated_today? が true であるべき"
    end
  end

  test "updated_today?: 作成直後（更新なし）のレコードで false を返すこと" do
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0) do
      record = HabitRecord.create!(
        user: @user, habit: @habit,
        record_date: HabitRecord.today_for_record, completed: false
      )
      # created_at と updated_at は同じなので updated_today? は false
      assert_not record.updated_today?,
                 "作成直後のレコードは updated_today? が false であるべき"
    end
  end

  # ============================================================
  # ⑧ StreakCalculationJob テスト
  # ============================================================

  test "StreakCalculationJob が実行されてストリークが更新されること" do
    travel_to Time.zone.local(2026, 4, 16, 10, 0, 0) do
      today = HabitRecord.today_for_record
      HabitRecord.create!(user: @user, habit: @habit, record_date: today, completed: true)

      # ジョブを直接実行（テスト環境では :test アダプターで同期実行）
      assert_nothing_raised do
        StreakCalculationJob.perform_now
      end

      @habit.reload
      assert_equal 1, @habit.current_streak,
                   "ジョブ実行後に current_streak が更新されるべき"
      assert_not_nil @habit.last_streak_calculated_at,
                     "ジョブ実行後に last_streak_calculated_at が設定されるべき"
    end
  end
end