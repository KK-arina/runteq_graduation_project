# test/models/habit_progress_test.rb
# ============================================================
# Issue #17: 進捗率計算 モデルテスト（補完版）
#
# 【既存テストとの関係】
# habit_test.rb に基本的なバリデーションテストがあります。
# このファイルでは Issue #16 で実装した
# weekly_progress_stats メソッドのテストを詳細に追加します。
#
# 【weekly_progress_stats とは？】
# Habitモデルのインスタンスメソッドで、
# { rate: Integer(0〜100), completed_count: Integer } を返します。
# 今週（月曜〜今日）の進捗率を計算します。
# ============================================================

require "test_helper"

class HabitProgressTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)   # weekly_target: 7

    # ============================================================
    # 【なぜここで destroy_all するのか？】
    # habit_records.yml のフィクスチャには record_one（2日前・完了済み）が
    # 定義されています。「2日前」が今週の月曜日以降に含まれる場合、
    # 「記録0件のテスト」や「未完了除外のテスト」の前提が崩れてしまいます。
    #
    # setup で毎回クリアすることで、全テストが「記録0件」の
    # クリーンな状態から始まることを保証します。
    #
    # 【destroy_all と delete_all の違い】
    # destroy_all → Railsのコールバック（before_destroy など）を実行してから削除
    # delete_all  → コールバックをスキップしてSQLで直接削除（高速だが注意が必要）
    # ここではコールバックを正しく通したいので destroy_all を使います。
    # ============================================================
    @habit.habit_records.destroy_all
  end

  # ===========================================================
  # ■ weekly_progress_stats メソッドのテスト
  # ===========================================================

  # ---------------------------------------------------------
  # 記録が0件の場合: rate=0, completed_count=0 が返ること
  # ---------------------------------------------------------
  test "記録が0件の場合は rate:0, completed_count:0 が返ること" do
    # setup で destroy_all 済みなのでここでは何もしなくてよい

    result = @habit.weekly_progress_stats(@user)

    # Hash のキーと値を確認
    assert_equal 0, result[:rate],            "記録0件なので達成率は0%のはず"
    assert_equal 0, result[:completed_count], "記録0件なので完了数は0のはず"
  end

  # ---------------------------------------------------------
  # 完了済みの記録のみカウントされること（未完了は除外）
  # ---------------------------------------------------------
  test "completed:false の記録は進捗率に含まれないこと" do
    # setup で destroy_all 済みなのでフィクスチャの記録は存在しない
    today  = HabitRecord.today_for_record
    monday = today.beginning_of_week(:monday)

    # 未完了の記録を1件だけ作成
    HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: monday,
      completed:   false   # 未完了
    )

    result = @habit.weekly_progress_stats(@user)

    # 未完了なので completed_count は 0 のまま
    assert_equal 0, result[:completed_count],
      "completed:false の記録はカウントされないはず"
  end

  # ---------------------------------------------------------
  # 完了済み記録が1件ある場合の進捗率テスト
  # (weekly_target=7 なので 1/7 ≒ 14%)
  # ---------------------------------------------------------
  test "完了記録1件の場合は正しい進捗率が返ること" do
    # setup で destroy_all 済みなのでここでは追加のクリアは不要
    today  = HabitRecord.today_for_record
    monday = today.beginning_of_week(:monday)

    # 完了済み記録を1件作成
    HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: monday,
      completed:   true
    )

    result = @habit.weekly_progress_stats(@user)

    # 1 / 7 * 100 = 14.28... → floor で 14
    expected_rate = ((1.0 / @habit.weekly_target) * 100).floor
    assert_equal expected_rate, result[:rate],
      "1件完了 / 目標7件 なので #{expected_rate}% のはず"
    assert_equal 1, result[:completed_count],
      "完了記録が1件なので completed_count は 1 のはず"
  end

  # ---------------------------------------------------------
  # 他ユーザーの記録はカウントされないこと
  # ---------------------------------------------------------
  test "他ユーザーの記録は進捗率に含まれないこと" do
    # setup で destroy_all 済みなのでここでは追加のクリアは不要
    today      = HabitRecord.today_for_record
    monday     = today.beginning_of_week(:monday)
    other_user = users(:two)

    # 他ユーザーが同じ habit に記録を作成
    HabitRecord.create!(
      user:        other_user,
      habit:       @habit,
      record_date: monday,
      completed:   true
    )

    # @user の統計を取得 → 他ユーザーの記録は含まれないはず
    result = @habit.weekly_progress_stats(@user)
    assert_equal 0, result[:completed_count],
      "他ユーザーの記録は @user の進捗率に含まれないはず"
  end

  # ---------------------------------------------------------
  # 進捗率が100%を超えないこと（clamp のテスト）
  # 【clamp とは？】
  # 数値を指定した範囲内に収めるメソッドです。
  # rate.clamp(0, 100) とすることで、100を超えても100に丸められます。
  # ---------------------------------------------------------
  test "進捗率は最大100%になること" do
    # setup で destroy_all 済みなのでここでは追加のクリアは不要
    today  = HabitRecord.today_for_record
    monday = today.beginning_of_week(:monday)

    # weekly_target(7) を超える記録を作成（8件試みる）
    8.times do |i|
      # i=0 なら monday, i=1 なら monday+1日 ... と日付をずらす
      record_date = monday + i.days
      # 未来日は UNIQUE制約以前に「今週」の範囲外になるため作成しない
      break if record_date > today

      HabitRecord.find_or_create_by!(
        user:        @user,
        habit:       @habit,
        record_date: record_date
      ).update!(completed: true)
    end

    result = @habit.weekly_progress_stats(@user)

    # clamp(0, 100) により 100 を超えないこと
    assert result[:rate] <= 100,
      "進捗率は 100% を超えないはず（clamp で制限）"
  end

  # ---------------------------------------------------------
  # 先週の記録は今週の進捗率に含まれないこと
  # ---------------------------------------------------------
  test "先週の記録は今週の進捗率に含まれないこと" do
    # setup で destroy_all 済みなのでここでは追加のクリアは不要

    # 「先週」の月曜日の記録を作成
    last_monday = HabitRecord.today_for_record.beginning_of_week(:monday) - 7.days

    HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: last_monday,   # 先週の記録
      completed:   true
    )

    result = @habit.weekly_progress_stats(@user)

    # 今週の集計には含まれないので 0 のはず
    assert_equal 0, result[:completed_count],
      "先週の記録は今週の進捗率に含まれないはず"
  end

  # ===========================================================
  # ■ AM4:00 境界値 × 進捗率 複合テスト
  # ===========================================================

  # ---------------------------------------------------------
  # AM3:59 時点では、今日の日付は「前日」扱いになること
  # ---------------------------------------------------------
  test "AM3:59 時点の today_for_record は前日の日付になること" do
    # travel_to でシステム時刻を操作（test_helper.rb の TimeHelpers が必要）
    travel_to Time.zone.parse("2026-02-17 03:59:00") do   # 月曜AM3:59
      today = HabitRecord.today_for_record
      # AM3:59 → 前日（日曜）扱い
      assert_equal Date.new(2026, 2, 16), today,
        "月曜AM3:59 は前日（日曜 2026-02-16）扱いのはず"
    end
  end
end
