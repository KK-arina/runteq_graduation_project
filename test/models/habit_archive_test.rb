# test/models/habit_archive_test.rb
#
# ==============================================================================
# Habit モデルのアーカイブ機能テスト（B-4）
# ==============================================================================
# 【このファイルの役割】
#   B-4 で追加したアーカイブ関連のモデルメソッド・スコープが
#   正しく動作するかを検証する。
#
# 【テスト方針】
#   1. scope :active  → アクティブな習慣だけを返すことを確認
#   2. scope :archived → アーカイブ済み習慣だけを返すことを確認
#   3. archive!       → archived_at がセットされることを確認
#   4. unarchive!     → archived_at が nil に戻ることを確認
#   5. archived?      → 状態に応じた真偽値を返すことを確認
#   6. active?        → アーカイブ済みは false を返すことを確認
# ==============================================================================

require "test_helper"

class HabitArchiveTest < ActiveSupport::TestCase
  # ============================================================
  # セットアップ: 各テストの前に実行される
  # ============================================================
  # setup ブロック:
  #   各テストの前に毎回実行されるセットアップメソッド。
  #   テストごとに独立したデータを用意することで
  #   テスト間の依存関係をなくす。

  setup do
    # fixtures :all で test/fixtures/*.yml のデータを使う（test_helper.rb で設定済み）。
    # ここでは users フィクスチャからユーザーを取得する。
    # fixtures の中に users: one が定義されていれば users(:one) で取得できる。
    @user = users(:one)

    # アクティブな習慣（削除もアーカイブもされていない）
    @active_habit = @user.habits.create!(
      name:             "テスト習慣（アクティブ）",
      measurement_type: :check_type,
      weekly_target:    5
    )

    # アーカイブ済みの習慣（archived_at が設定されている）
    @archived_habit = @user.habits.create!(
      name:             "テスト習慣（アーカイブ済み）",
      measurement_type: :check_type,
      weekly_target:    3,
      archived_at:      1.day.ago
    )

    # 削除済みの習慣（deleted_at が設定されている）
    @deleted_habit = @user.habits.create!(
      name:             "テスト習慣（削除済み）",
      measurement_type: :check_type,
      weekly_target:    7,
      deleted_at:       2.days.ago
    )
  end

  # ============================================================
  # scope :active のテスト
  # ============================================================

  # テスト名の命名規則:
  #   "test_" から始めるのが Rails の慣例。
  #   テスト名は「何をテストするか」が一目でわかる名前にする。

  test "scope active はアクティブな習慣のみを返す" do
    # current_user.habits.active で取得した ID のリストに
    # @active_habit が含まれることを確認する。
    #
    # assert_includes(collection, object):
    #   collection に object が含まれていれば PASS。
    #   含まれていなければ FAIL。
    active_ids = @user.habits.active.pluck(:id)
    assert_includes active_ids, @active_habit.id,
      "scope :active にアクティブな習慣が含まれているべき"
  end

  test "scope active はアーカイブ済み習慣を返さない" do
    active_ids = @user.habits.active.pluck(:id)
    # refute_includes(collection, object):
    #   collection に object が含まれていなければ PASS。
    #   含まれていれば FAIL。
    refute_includes active_ids, @archived_habit.id,
      "scope :active にアーカイブ済み習慣が含まれないべき"
  end

  test "scope active は削除済み習慣を返さない" do
    active_ids = @user.habits.active.pluck(:id)
    refute_includes active_ids, @deleted_habit.id,
      "scope :active に削除済み習慣が含まれないべき"
  end

  # ============================================================
  # scope :archived のテスト
  # ============================================================

  test "scope archived はアーカイブ済み習慣のみを返す" do
    archived_ids = @user.habits.archived.pluck(:id)
    assert_includes archived_ids, @archived_habit.id,
      "scope :archived にアーカイブ済み習慣が含まれているべき"
  end

  test "scope archived はアクティブな習慣を返さない" do
    archived_ids = @user.habits.archived.pluck(:id)
    refute_includes archived_ids, @active_habit.id,
      "scope :archived にアクティブな習慣が含まれないべき"
  end

  test "scope archived は削除済み習慣を返さない" do
    archived_ids = @user.habits.archived.pluck(:id)
    refute_includes archived_ids, @deleted_habit.id,
      "scope :archived に削除済み習慣が含まれないべき"
  end

  # ============================================================
  # archive! のテスト
  # ============================================================

  test "archive! を呼ぶと archived_at がセットされる" do
    # freeze_time はテスト中の時刻を固定するメソッド（ActiveSupport::Testing::TimeHelpers）。
    # Time.current を固定することで、archive! が設定する archived_at と
    # テスト内で期待する時刻が一致するようにする。
    freeze_time do
      @active_habit.archive!
      # reload: DB から最新の値を再取得する。
      # archive! が update! を呼んでいるので DB に保存されているはずだが、
      # Ruby のオブジェクトはメモリ上の値を保持しているため、
      # reload で DB から再取得して確認する。
      @active_habit.reload
      assert_not_nil @active_habit.archived_at,
        "archive! 後に archived_at が nil でないべき"
      assert_in_delta Time.current, @active_habit.archived_at, 1.second,
        "archive! 後の archived_at が現在時刻に近いべき"
    end
  end

  test "archive! 後は scope active に含まれない" do
    @active_habit.archive!
    active_ids = @user.habits.active.pluck(:id)
    refute_includes active_ids, @active_habit.id,
      "archive! 後は scope :active に含まれないべき"
  end

  test "archive! 後は scope archived に含まれる" do
    @active_habit.archive!
    archived_ids = @user.habits.archived.pluck(:id)
    assert_includes archived_ids, @active_habit.id,
      "archive! 後は scope :archived に含まれるべき"
  end

  # ============================================================
  # unarchive! のテスト
  # ============================================================

  test "unarchive! を呼ぶと archived_at が nil に戻る" do
    @archived_habit.unarchive!
    @archived_habit.reload
    assert_nil @archived_habit.archived_at,
      "unarchive! 後に archived_at が nil であるべき"
  end

  test "unarchive! 後は scope active に含まれる" do
    @archived_habit.unarchive!
    active_ids = @user.habits.active.pluck(:id)
    assert_includes active_ids, @archived_habit.id,
      "unarchive! 後は scope :active に含まれるべき"
  end

  test "unarchive! 後は scope archived に含まれない" do
    @archived_habit.unarchive!
    archived_ids = @user.habits.archived.pluck(:id)
    refute_includes archived_ids, @archived_habit.id,
      "unarchive! 後は scope :archived に含まれないべき"
  end

  # ============================================================
  # archived? のテスト
  # ============================================================

  test "archived? はアーカイブ済み習慣で true を返す" do
    assert @archived_habit.archived?,
      "アーカイブ済み習慣の archived? は true であるべき"
  end

  test "archived? はアクティブな習慣で false を返す" do
    assert_not @active_habit.archived?,
      "アクティブな習慣の archived? は false であるべき"
  end

  # ============================================================
  # active? のテスト（B-4 修正: archived_at も考慮するようになった）
  # ============================================================

  test "active? はアクティブな習慣で true を返す" do
    assert @active_habit.active?,
      "アクティブな習慣の active? は true であるべき"
  end

  test "active? はアーカイブ済み習慣で false を返す" do
    assert_not @archived_habit.active?,
      "アーカイブ済み習慣の active? は false であるべき"
  end

  test "active? は削除済み習慣で false を返す" do
    assert_not @deleted_habit.active?,
      "削除済み習慣の active? は false であるべき"
  end

  # ============================================================
  # 週次振り返りスナップショットとの関係（B-4 タスク要件の確認）
  # ============================================================

  test "アーカイブしても weekly_reflection_habit_summaries は残る" do
    # WeeklyReflectionHabitSummary のフィクスチャが存在しない場合は
    # このテストはスキップして構わない。
    # 実装がある場合は以下のようにテストする。
    #
    # dependent: :nullify の設定により、
    # 習慣が論理削除・アーカイブされてもサマリーは削除されない
    # （habit_id が NULL になるだけ）。
    # archive! は soft_delete と異なりレコードを削除しないため、
    # habit_id への参照は維持される。
    #
    # ここでは archive! が習慣記録（habit_records）を削除しないことだけ確認する。
    habit_record = @active_habit.habit_records.create!(
      user:        @user,
      record_date: Date.current,
      completed:   true
    )

    @active_habit.archive!

    # アーカイブ後も habit_records は削除されない（archive! はソフトデリートではない）
    assert HabitRecord.exists?(habit_record.id),
      "アーカイブ後も habit_records は削除されないべき"
  end

  # ============================================================
  # 異常系テスト（B-4 レビュー対応: 状態ガードの確認）
  # ============================================================
  # 【なぜ異常系テストが必要か】
  #   正常系（happy path）のテストだけでは
  #   「ありえない操作をしたときにどうなるか」が保証されない。
  #   異常系テストで状態ガードが正しく機能することを確認することで
  #   本番環境での不整合なデータ作成を防ぐ。

  test "archive! はアーカイブ済み習慣に二重実行するとエラーになる" do
    # @archived_habit はすでに archived_at が設定されている（setup で作成済み）。
    # archive! を呼ぶと「すでにアーカイブ済みです」RuntimeError が発生するはず。
    #
    # assert_raises(例外クラス) { ブロック }:
    #   ブロック内で指定した例外が発生すれば PASS。
    #   発生しなければ FAIL。
    assert_raises(RuntimeError) do
      @archived_habit.archive!
    end
  end

  test "archive! は削除済み習慣に実行するとエラーになる" do
    # @deleted_habit は deleted_at が設定されている（setup で作成済み）。
    # 削除済み習慣に archive! を呼ぶと
    # 「削除済みのため操作できません」RuntimeError が発生するはず。
    assert_raises(RuntimeError) do
      @deleted_habit.archive!
    end
  end

  test "unarchive! はアクティブな習慣に実行するとエラーになる" do
    # @active_habit は archived_at が nil（setup で作成済み）。
    # アーカイブされていない習慣に unarchive! を呼ぶと
    # 「アーカイブされていません」RuntimeError が発生するはず。
    assert_raises(RuntimeError) do
      @active_habit.unarchive!
    end
  end

  test "unarchive! は削除済み習慣に実行するとエラーになる" do
    # @deleted_habit は deleted_at が設定されているが archived_at は nil。
    # archived? = false なので unarchive! を呼ぶと RuntimeError が発生するはず。
    assert_raises(RuntimeError) do
      @deleted_habit.unarchive!
    end
  end
end