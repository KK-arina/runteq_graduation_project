# test/models/weekly_reflection_habit_summary_test.rb
#
# 【このテストファイルの目的】
# WeeklyReflectionHabitSummary モデルの動作が正しいことを自動検証する。
#
# 【fixtureとの衝突を避ける設計】
# fixtureには current_week × habit_two, last_week × habit_one を定義。
# テスト本体では current_week × habit_one を使うことで重複を防いでいます。

require "test_helper"

class WeeklyReflectionHabitSummaryTest < ActiveSupport::TestCase
  # ============================================================
  # setup: 各テスト実行前に呼ばれる前処理
  # ============================================================
  setup do
    @user       = users(:one)
    @habit      = habits(:habit_one)
    @reflection = weekly_reflections(:for_summary_test)

    # .new でインスタンスを作成（DBには保存しない）
    # → fixtureには current_week × habit_one は存在しないため
    #   この組み合わせはUNIQUE違反にならない
    @summary = WeeklyReflectionHabitSummary.new(
      weekly_reflection: @reflection,
      habit:             @habit,
      habit_name:        "読書",
      weekly_target:     7,
      actual_count:      5,
      achievement_rate:  71.43
    )
  end

  # ============================================================
  # バリデーションテスト
  # ============================================================

  test "有効なデータでサマリーが作成できること" do
    # @summary はまだDBに存在しないので valid? はtrueになるはず
    assert @summary.valid?, "有効なデータなのにバリデーションエラーが発生: #{@summary.errors.full_messages}"
  end

  test "habit_nameがなければ無効であること" do
    @summary.habit_name = nil
    assert_not @summary.valid?
    assert @summary.errors.added?(:habit_name, :blank)
  end

  test "habit_nameが51文字以上なら無効であること" do
    @summary.habit_name = "a" * 51
    assert_not @summary.valid?
    assert @summary.errors.added?(:habit_name, :too_long, count: 50)
  end

  test "habit_nameが50文字ならば有効であること" do
    @summary.habit_name = "a" * 50
    # habit_name を変更しているだけで reflection × habit の組み合わせは変わらないため valid
    assert @summary.valid?
  end

  test "weekly_targetがなければ無効であること" do
    @summary.weekly_target = nil
    assert_not @summary.valid?
    assert @summary.errors.added?(:weekly_target, :blank)
  end

  test "weekly_targetが0なら無効であること" do
    @summary.weekly_target = 0
    assert_not @summary.valid?
  end

  test "weekly_targetが1なら有効であること" do
    @summary.weekly_target = 1
    assert @summary.valid?, "weekly_target=1 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "actual_countがなければ無効であること" do
    @summary.actual_count = nil
    assert_not @summary.valid?
  end

  test "actual_countが負数なら無効であること" do
    @summary.actual_count = -1
    assert_not @summary.valid?
  end

  test "actual_countが0なら有効であること" do
    @summary.actual_count = 0
    assert @summary.valid?, "actual_count=0 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "achievement_rateが101なら無効であること" do
    @summary.achievement_rate = 101
    assert_not @summary.valid?
  end

  test "achievement_rateが-1なら無効であること" do
    @summary.achievement_rate = -1
    assert_not @summary.valid?
  end

  test "achievement_rateが100なら有効であること" do
    @summary.achievement_rate = 100
    assert @summary.valid?, "achievement_rate=100 は有効なはずです: #{@summary.errors.full_messages}"
  end

  test "achievement_rateが0なら有効であること" do
    @summary.achievement_rate = 0
    assert @summary.valid?, "achievement_rate=0 は有効なはずです: #{@summary.errors.full_messages}"
  end

  # ============================================================
  # UNIQUE制約テスト
  # ============================================================

  test "同じ振り返りに同じ習慣のサマリーは重複作成できないこと" do
    # 1件目を保存
    @summary.save!

    # 同じ weekly_reflection × habit で2件目を作成しようとする
    duplicate = WeeklyReflectionHabitSummary.new(
      weekly_reflection: @reflection,
      habit:             @habit,
      habit_name:        "読書（コピー）",
      weekly_target:     7,
      actual_count:      3,
      achievement_rate:  42.86
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:habit_id], "は既にこの振り返りに含まれています"
  end

  test "異なる振り返りなら同じ習慣のサマリーを作成できること" do
    # @reflection（for_summary_test）× habit_one を保存する
    @summary.save!

    # 別の振り返り用レコードを作成（テスト内で直接作る）
    other_reflection = WeeklyReflection.create!(
      user:            @user,
      week_start_date: Date.new(2025, 11, 3),
      week_end_date:   Date.new(2025, 11, 9),
      is_locked:       true
    )

    other_summary = WeeklyReflectionHabitSummary.new(
      weekly_reflection: other_reflection,
      habit:             @habit,
      habit_name:        "読書",
      weekly_target:     7,
      actual_count:      5,
      achievement_rate:  71.0
    )

    assert other_summary.valid?,
      "異なる振り返りなら有効なはずです: #{other_summary.errors.full_messages}"
  end

  # ============================================================
  # アソシエーションテスト
  # ============================================================

  test "WeeklyReflectionに紐づいていること" do
    @summary.save!
    assert_equal @reflection, @summary.reload.weekly_reflection
  end

  test "WeeklyReflection削除時にサマリーも削除されること（CASCADE）" do
    @summary.save!
    summary_id = @summary.id

    # WeeklyReflection を削除
    @reflection.destroy

    # CASCADEによりサマリーも削除されていることを確認
    assert_not WeeklyReflectionHabitSummary.exists?(summary_id)
  end

  # ============================================================
  # クラスメソッドテスト（スナップショット保存ロジック）
  # ============================================================

  test "build_from_habit でスナップショットが正しく構築されること" do
    # habit_records をクリアして件数を確定させる
    @habit.habit_records.where(user: @user).destroy_all

    week_start = @reflection.week_start_date
    3.times do |i|
      HabitRecord.create!(
        user:        @user,
        habit:       @habit,
        record_date: week_start + i.days,
        completed:   true
      )
    end

    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, @habit)

    # スナップショットが正しくコピーされていることを確認
    assert_equal @habit.name,          summary.habit_name
    assert_equal @habit.weekly_target, summary.weekly_target
    assert_equal 3,                    summary.actual_count

    # 達成率: 3 / weekly_target * 100
    expected_rate = (3.0 / @habit.weekly_target * 100).clamp(0, 100).round(2)
    assert_equal expected_rate, summary.achievement_rate
  end

  test "build_from_habit で未完了レコードは実績に含まれないこと" do
    @habit.habit_records.where(user: @user).destroy_all

    week_start = @reflection.week_start_date
    # 完了1件 + 未完了2件
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start,             completed: true)
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start + 1.day,     completed: false)
    HabitRecord.create!(user: @user, habit: @habit, record_date: week_start + 2.days,    completed: false)

    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, @habit)

    # 完了は1件のみカウントされること
    assert_equal 1, summary.actual_count
  end

  test "build_from_habit で他のユーザーの記録は含まれないこと" do
    @habit.habit_records.where(user: @user).destroy_all

    week_start = @reflection.week_start_date
    other_user = users(:two)

    # @user: 2件完了
    2.times do |i|
      HabitRecord.create!(user: @user, habit: @habit,
                          record_date: week_start + i.days, completed: true)
    end
    # other_user: 3件完了（カウントされないはず）
    3.times do |i|
      HabitRecord.create!(user: other_user, habit: @habit,
                          record_date: week_start + i.days, completed: true)
    end

    summary = WeeklyReflectionHabitSummary.build_from_habit(@reflection, @habit)

    # @user の2件のみカウントされること
    assert_equal 2, summary.actual_count
  end

  test "create_all_for_reflection! で全習慣のサマリーが作成されること" do
    # ── テスト設計の考え方 ───────────────────────────────────────
    # create_all_for_reflection! の責務は
    # 「active な習慣すべてにサマリーを持たせること」であり、
    # 「サマリーの総件数を active 習慣数と一致させること」ではない。
    #
    # fixtureには active でない習慣のサマリーが含まれる場合があるため、
    # 「件数 == active習慣数」という比較は壊れやすい。
    #
    # 正しい検証方法：
    # 「active習慣のIDが、作成済みサマリーのhabit_idに全部含まれているか」
    # を確認することで「余計なものは無視・必要なものは全部ある」を同時に保証する。
    # ────────────────────────────────────────────────────────────
    active_habits      = @user.habits.active
    existing_habit_ids = @reflection.habit_summaries.pluck(:habit_id)
    expected_new       = active_habits.where.not(id: existing_habit_ids).count

    assert_difference "WeeklyReflectionHabitSummary.count", expected_new do
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)
    end

    # active習慣のIDと、作成済みサマリーのhabit_idを比較して完全一致を確認する
    # .sort を使うことで順序の違いによる誤検知を防ぐ
    active_ids          = active_habits.pluck(:id).sort
    created_active_ids  = @reflection.habit_summaries
                                     .reload
                                     .where(habit_id: active_ids)
                                     .pluck(:habit_id)
                                     .sort

    assert_equal active_ids, created_active_ids,
      "active な全習慣のサマリーが作成されていません。\n" \
      "不足: #{active_ids - created_active_ids}"
  end

  test "create_all_for_reflection! は2回実行しても件数が増えないこと（冪等性）" do
    # ── 冪等性（idempotent）とは ─────────────────────────────────
    # 同じ操作を何度実行しても結果が変わらない性質。
    # ページリロードやAPIの二重送信が起きても安全であることを保証する。
    #
    # このメソッドは「next if exists?」によりスキップするため
    # 2回呼んでもデータが重複しない。それをここで確認する。
    # ────────────────────────────────────────────────────────────

    # 1回目：全サマリーを作成
    WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)

    # 2回目：件数が変わらないことを確認
    assert_no_difference "WeeklyReflectionHabitSummary.count" do
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)
    end
  end

  # ============================================================
  # インスタンスメソッドテスト
  # ============================================================

  test "achievement_rate_text が正しい形式で返ること" do
    @summary.achievement_rate = 71.43
    assert_equal "71.43%", @summary.achievement_rate_text
  end

  test "achievement_rate_text が整数でも小数点2桁で返ること" do
    # format('%.2f%%', ...) により 100 → "100.00%" になることを確認
    @summary.achievement_rate = 100
    assert_equal "100.00%", @summary.achievement_rate_text
  end

  test "achieved? が達成率100%のとき true を返すこと" do
    @summary.achievement_rate = 100
    assert @summary.achieved?
  end

  test "achieved? が達成率99%のとき false を返すこと" do
    @summary.achievement_rate = 99
    assert_not @summary.achieved?
  end

  # ============================================================
  # スコープテスト
  # ============================================================

  test "completed スコープが達成率100%のサマリーのみ返すこと" do
    completed_fixture = weekly_reflection_habit_summaries(:one_habit_one)  # achievement_rate: 100
    assert_includes WeeklyReflectionHabitSummary.completed, completed_fixture
  end

  test "incomplete スコープが達成率100%未満のサマリーのみ返すこと" do
    incomplete_fixture = weekly_reflection_habit_summaries(:two_habit_one)  # achievement_rate: 71
    assert_includes WeeklyReflectionHabitSummary.incomplete, incomplete_fixture
    assert_not_includes WeeklyReflectionHabitSummary.completed, incomplete_fixture
  end
end
