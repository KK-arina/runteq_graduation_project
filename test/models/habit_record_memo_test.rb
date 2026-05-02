# test/models/habit_record_memo_test.rb
#
# ==============================================================================
# HabitRecord メモ機能のモデルテスト（B-7）
# ==============================================================================
#
# 【このテストファイルの役割】
#   B-7 で追加した memo バリデーションと has_memo? メソッドが
#   正しく動作することを確認する。
#
# 【fixture 名について】
#   test/fixtures/users.yml  → ラベル: one, two, locked_user
#   test/fixtures/habits.yml → ラベル: habit_one, habit_two, habit_deleted
#
#   users(:one)       → users.yml の "one" に対応するユーザー
#   habits(:habit_one) → habits.yml の "habit_one" に対応する習慣
#
#   ※ "alice" や "morning_jog" のような名前は存在しないためエラーになる
#
# 【テスト実行コマンド】
#   docker compose exec web bin/rails test test/models/habit_record_memo_test.rb
#
# ==============================================================================

require "test_helper"

class HabitRecordMemoTest < ActiveSupport::TestCase
  # setup: 各テストの前に実行される共通の前処理
  def setup
    # users.yml の "one" ラベルに対応するユーザーを取得する
    @user  = users(:one)
    # habits.yml の "habit_one" ラベルに対応する習慣を取得する
    # ※ habits.yml では "habit_one" というラベルが定義されている（"one" ではない）
    @habit = habits(:habit_one)
  end

  # ============================================================
  # memo バリデーションのテスト
  # ============================================================

  test "メモが nil の場合は有効（任意項目のため）" do
    # メモなしでレコードを作成できることを確認する
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 1),
      completed:   false,
      memo:        nil
    )
    # assert record.valid? は record.valid? が true であることを確認する
    # 失敗した場合は record.errors.full_messages も表示して原因を分かりやすくする
    assert record.valid?, record.errors.full_messages.inspect
  end

  test "メモが空文字の場合は有効（任意項目のため）" do
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 2),
      completed:   false,
      memo:        ""
    )
    assert record.valid?, record.errors.full_messages.inspect
  end

  test "メモが200文字以内の場合は有効" do
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 3),
      completed:   false,
      # "a" * 200 で200文字の文字列を作る
      memo:        "a" * 200
    )
    assert record.valid?, record.errors.full_messages.inspect
  end

  test "メモが201文字以上の場合は無効（200文字制限）" do
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 4),
      completed:   false,
      memo:        "a" * 201
    )
    # assert_not record.valid? は record.valid? が false であることを確認する
    assert_not record.valid?
    # errors[:memo] にバリデーションエラーメッセージが入っていることを確認する
    assert_includes record.errors[:memo], "は200文字以内で入力してください"
  end

  # ============================================================
  # has_memo? メソッドのテスト
  # ============================================================

  test "has_memo? はメモが nil の場合 false を返す" do
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 5),
      completed:   false,
      memo:        nil
    )
    # assert_not は false であることを確認する
    assert_not record.has_memo?
  end

  test "has_memo? はメモが空文字の場合 false を返す" do
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 6),
      completed:   false,
      memo:        ""
    )
    assert_not record.has_memo?
  end

  test "has_memo? はメモが存在する場合 true を返す" do
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 7),
      completed:   false,
      memo:        "今日は調子がよかった"
    )
    # assert は true であることを確認する
    assert record.has_memo?
  end

  test "has_memo? はメモがスペースのみの場合 false を返す" do
    # スペースのみはメモなしとみなす（present? は " " に対して false を返す）
    record = HabitRecord.new(
      user:        @user,
      habit:       @habit,
      record_date: Date.new(2025, 1, 8),
      completed:   false,
      memo:        "   "
    )
    assert_not record.has_memo?
  end
end