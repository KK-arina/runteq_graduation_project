# test/services/weekly_reflection_complete_service_test.rb
#
# ============================================================
# 【最終版】
# テスト4・5のメソッド差し替えを stub に統一する。
#
# 【stub とは】
# minitest の Object#stub メソッド。
# 指定したメソッドをブロック内だけ差し替えて、
# ブロックを抜けると自動で元に戻る。
# → ensure 不要・グローバルな状態汚染なし・フレーキー防止
#
# 【stub の書き方】
# オブジェクト.stub(:メソッド名, 返り値 or lambda) do
#   # このブロック内だけメソッドが差し替えられる
# end
#
# 例外を raise させたい場合は lambda を使う:
# obj.stub(:method_name, -> { raise SomeError }) do ... end
# ============================================================

require "test_helper"

class WeeklyReflectionCompleteServiceTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)
  end

  # 【テスト1】振り返りが正常に保存・完了されること
  test "call が成功すると振り返りが保存され completed? が true になること" do
    week_start = Date.new(2026, 6, 1) # week 23

    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    week_start,
      week_end_date:      week_start + 6.days,
      reflection_comment: "今週の振り返りテスト"
    )

    assert_difference "WeeklyReflection.count", 1 do
      result = WeeklyReflectionCompleteService.new(
        reflection:  reflection,
        user:        @user,
        was_locked:  false
      ).call

      assert result[:success], "call は成功を返すべき: #{result[:error]}"
    end

    reflection.reload
    assert reflection.completed?,
           "call 後は completed? が true になるべき"
    assert_not_nil reflection.completed_at,
                   "call 後は completed_at に時刻が入るべき"
  end

  # 【テスト2】習慣スナップショットが作成されること
  test "call が成功すると習慣スナップショットが作成されること" do
    week_start = Date.new(2026, 6, 8) # week 24

    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    week_start,
      week_end_date:      week_start + 6.days,
      reflection_comment: "スナップショットテスト"
    )

    expected_count = @user.habits.active.count

    assert_difference "WeeklyReflectionHabitSummary.count", expected_count do
      result = WeeklyReflectionCompleteService.new(
        reflection:  reflection,
        user:        @user,
        was_locked:  false
      ).call

      assert result[:success], "call は成功を返すべき: #{result[:error]}"
    end
  end

  # 【テスト3】成功時の戻り値が正しいこと
  test "成功時は { success: true, error: nil } を返すこと" do
    week_start = Date.new(2026, 6, 15) # week 25

    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    week_start,
      week_end_date:      week_start + 6.days,
      reflection_comment: "戻り値テスト"
    )

    result = WeeklyReflectionCompleteService.new(
      reflection:  reflection,
      user:        @user,
      was_locked:  false
    ).call

    assert_equal true, result[:success]
    assert_nil         result[:error]
  end

  # 【テスト4】スナップショット作成が失敗したとき WeeklyReflection もロールバックされること
  #
  # 【stub を使う理由】
  # クラスメソッドをブロック内だけ差し替える。
  # ブロックを抜けると自動で元に戻るためフレーキーにならない。
  # minitest/mock が読み込まれていれば クラスにも インスタンスにも使える。
  test "スナップショット作成が失敗したとき WeeklyReflection もロールバックされること" do
    week_start = Date.new(2026, 6, 22) # week 26

    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    week_start,
      week_end_date:      week_start + 6.days,
      reflection_comment: "ロールバックテスト"
    )

    reflection_count_before = WeeklyReflection.count
    summary_count_before    = WeeklyReflectionHabitSummary.count

    # WeeklyReflectionHabitSummary.create_all_for_reflection! を
    # 失敗する lambda で差し替える。
    # stub のブロックを抜けると自動で元に戻る。
    error_lambda = ->(_reflection) {
      invalid_record = WeeklyReflection.new
      invalid_record.errors.add(:base, "テスト用の強制エラー")
      raise ActiveRecord::RecordInvalid, invalid_record
    }

    WeeklyReflectionHabitSummary.stub(:create_all_for_reflection!, error_lambda) do
      result = WeeklyReflectionCompleteService.new(
        reflection:  reflection,
        user:        @user,
        was_locked:  false
      ).call

      assert_equal reflection_count_before, WeeklyReflection.count,
                   "ロールバックにより WeeklyReflection の件数が変わらないこと"
      assert_equal summary_count_before, WeeklyReflectionHabitSummary.count,
                   "ロールバックにより HabitSummary の件数が変わらないこと"
      assert_equal false, result[:success]
      assert_not_nil result[:error]
    end
  end

  # 【テスト5】complete! が失敗したときもロールバックされること
  #
  # 【インスタンスに stub を使う】
  # reflection インスタンスの complete! だけを差し替える。
  # WeeklyReflection クラス全体には影響しない。
  test "complete! が失敗したとき WeeklyReflection と HabitSummary 両方ロールバックされること" do
    week_start = Date.new(2026, 6, 29) # week 27

    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    week_start,
      week_end_date:      week_start + 6.days,
      reflection_comment: "complete失敗テスト"
    )

    reflection_count_before = WeeklyReflection.count
    summary_count_before    = WeeklyReflectionHabitSummary.count

    # reflection インスタンスの complete! だけを差し替える。
    # -> { } は引数なしの lambda。
    error_lambda = -> {
      invalid_record = WeeklyReflection.new
      invalid_record.errors.add(:base, "complete! の強制失敗")
      raise ActiveRecord::RecordInvalid, invalid_record
    }

    reflection.stub(:complete!, error_lambda) do
      result = WeeklyReflectionCompleteService.new(
        reflection:  reflection,
        user:        @user,
        was_locked:  false
      ).call

      assert_equal reflection_count_before, WeeklyReflection.count,
                   "ロールバックにより WeeklyReflection の件数が変わらないこと"
      assert_equal summary_count_before, WeeklyReflectionHabitSummary.count,
                   "ロールバックにより HabitSummary の件数が変わらないこと"
      assert_equal false, result[:success]
    end
  end

  # 【テスト6】was_locked: true のとき前週振り返りも完了されること
  test "was_locked が true のとき前週の振り返りも complete! されること" do
    last_week_start = Date.new(2026, 7, 6)  # week 28
    this_week_start = Date.new(2026, 7, 13) # week 29

    last_week_reflection = WeeklyReflection.create!(
      user:               @user,
      week_start_date:    last_week_start,
      week_end_date:      last_week_start + 6.days,
      reflection_comment: "前週の振り返り（未完了）"
    )

    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    this_week_start,
      week_end_date:      this_week_start + 6.days,
      reflection_comment: "今週の振り返り"
    )

    travel_to Time.zone.local(2026, 7, 13, 4, 1, 0) do
      result = WeeklyReflectionCompleteService.new(
        reflection:  reflection,
        user:        @user,
        was_locked:  true
      ).call

      assert result[:success], "call は成功するべき: #{result[:error]}"

      last_week_reflection.reload
      assert last_week_reflection.completed?,
             "was_locked: true のとき前週振り返りも completed? が true になるべき"
    end
  end
end