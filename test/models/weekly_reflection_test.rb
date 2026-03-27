# test/models/weekly_reflection_test.rb
#
# ==============================================================================
# WeeklyReflection モデルテスト（リフレクション手法対応）
# ==============================================================================
# 【追加テスト】
#   ① next_action カラムのバリデーションテスト
#      - 1000文字以内で有効
#      - 1001文字で無効
#      - nil / 空文字でも有効（任意入力）
#
#   ② 3フィールドがすべて保存されることのテスト
#      - direct_reason / background_situation / next_action が
#        まとめて保存・取得できることを確認する
# ==============================================================================

require "test_helper"

class WeeklyReflectionTest < ActiveSupport::TestCase

  # ============================================================
  # complete! メソッドのテスト（既存）
  # ============================================================

  test "complete! sets completed_at to the exact current time" do
    reflection = weekly_reflections(:pending_reflection)
    assert_nil reflection.completed_at

    freeze_time do
      reflection.complete!
      reflection.reload
      assert_not_nil reflection.completed_at
      assert_equal Time.current.to_i, reflection.completed_at.to_i
    end
  end

  test "complete! does not overwrite completed_at when called twice - idempotency" do
    reflection = weekly_reflections(:pending_reflection)
    first_completed_at = nil

    freeze_time do
      reflection.complete!
      reflection.reload
      first_completed_at = reflection.completed_at
      assert_not_nil first_completed_at
    end

    travel 1.hour do
      reflection.complete!
      reflection.reload
      assert_equal first_completed_at.to_i, reflection.completed_at.to_i,
                   "complete! を2回呼んでも completed_at は変わらないこと"
    end
  end

  test "completed? returns false before complete! and true after" do
    reflection = weekly_reflections(:pending_reflection)
    assert_not reflection.completed?
    reflection.complete!
    assert reflection.completed?
  end

  test "pending? is the inverse of completed?" do
    reflection = weekly_reflections(:pending_reflection)
    assert reflection.pending?
    assert_not reflection.completed?
    reflection.complete!
    assert_not reflection.pending?
    assert reflection.completed?
  end

  test "completed? returns false for a new unsaved record" do
    reflection = WeeklyReflection.new
    assert_not reflection.completed?
    assert reflection.pending?
  end

  test "completed_reflection fixture has correct state" do
    reflection = weekly_reflections(:completed_reflection)
    assert_not_nil reflection.completed_at
    assert reflection.completed?
    assert_not reflection.pending?
  end

  # ============================================================
  # locked? との統合テスト（既存）
  # ============================================================

  test "completing last week reflection makes pending? return false" do
    travel_to Time.zone.parse("2026-02-16 04:01:00") do
      reflection = weekly_reflections(:pending_reflection)
      assert reflection.pending?
      reflection.complete!
      assert_not reflection.pending?
      assert reflection.completed?
    end
  end

  test "pending? behavior is unaffected by the 4AM boundary" do
    reflection = weekly_reflections(:pending_reflection)

    travel_to Time.zone.parse("2026-02-16 03:59:00") do
      assert reflection.pending?
    end

    travel_to Time.zone.parse("2026-02-16 04:01:00") do
      assert reflection.pending?
    end
  end

  # ============================================================
  # バリデーションテスト（既存）
  # ============================================================

  test "is invalid when week_end_date is not 6 days after week_start_date" do
    reflection = WeeklyReflection.new(
      user:            users(:one),
      week_start_date: Date.parse("2026-02-16"),
      week_end_date:   Date.parse("2026-02-20")
    )
    assert_not reflection.valid?
    assert_includes reflection.errors[:week_end_date], "は週の開始日から6日後でなければなりません"
  end

  test "is valid when week_end_date is exactly 6 days after week_start_date" do
    reflection = WeeklyReflection.new(
      user:            users(:one),
      week_start_date: Date.parse("2026-02-16"),
      week_end_date:   Date.parse("2026-02-22")
    )
    assert reflection.valid?, reflection.errors.full_messages
  end

  # ============================================================
  # next_action カラムのテスト（リフレクション手法対応で追加）
  # ============================================================

  test "next_action が nil でも有効であること（任意入力）" do
    # 「からの？」は任意入力なので nil でバリデーションが通る必要がある
    reflection = WeeklyReflection.new(
      user:            users(:one),
      week_start_date: Date.parse("2026-03-16"),
      week_end_date:   Date.parse("2026-03-22"),
      next_action:     nil
    )
    assert reflection.valid?, "next_action=nil でも valid であるべき: #{reflection.errors.full_messages}"
  end

  test "next_action が空文字でも有効であること（任意入力）" do
    reflection = WeeklyReflection.new(
      user:            users(:one),
      week_start_date: Date.parse("2026-03-16"),
      week_end_date:   Date.parse("2026-03-22"),
      next_action:     ""
    )
    assert reflection.valid?, "next_action='' でも valid であるべき: #{reflection.errors.full_messages}"
  end

  test "next_action が1000文字以内のとき有効であること" do
    reflection = WeeklyReflection.new(
      user:            users(:one),
      week_start_date: Date.parse("2026-03-16"),
      week_end_date:   Date.parse("2026-03-22"),
      next_action:     "あ" * 1000
    )
    assert reflection.valid?, "next_action=1000文字は valid であるべき: #{reflection.errors.full_messages}"
  end

  test "next_action が1001文字のとき無効であること" do
    reflection = WeeklyReflection.new(
      user:            users(:one),
      week_start_date: Date.parse("2026-03-16"),
      week_end_date:   Date.parse("2026-03-22"),
      next_action:     "あ" * 1001
    )
    assert_not reflection.valid?, "next_action=1001文字は invalid であるべき"
    assert reflection.errors[:next_action].any?, "next_action にエラーが存在するべき"
  end

  # ============================================================
  # リフレクション3フィールドの保存テスト（統合確認）
  # ============================================================

  test "なぜ？どう？からの？の3フィールドがまとめて保存・取得できること" do
    # 3つのリフレクションフィールドをすべて入力して保存する
    reflection = WeeklyReflection.create!(
      user:                  users(:one),
      week_start_date:       Date.parse("2026-03-23"),
      week_end_date:         Date.parse("2026-03-29"),
      direct_reason:         "残業が続き、帰宅後に動ける体力が残っていなかった",
      background_situation:  "朝30分早く起きてトレーニング時間を確保する",
      next_action:           "朝型の生活リズムを読書・英語学習にも広げる",
      reflection_comment:    "今週は特に疲れた"
    )

    # DB から読み直して値が正しく保存されたことを確認する
    reflection.reload

    assert_equal "残業が続き、帰宅後に動ける体力が残っていなかった",
                 reflection.direct_reason,
                 "direct_reason が正しく保存されるべき"

    assert_equal "朝30分早く起きてトレーニング時間を確保する",
                 reflection.background_situation,
                 "background_situation が正しく保存されるべき"

    assert_equal "朝型の生活リズムを読書・英語学習にも広げる",
                 reflection.next_action,
                 "next_action が正しく保存されるべき"

    assert_equal "今週は特に疲れた",
                 reflection.reflection_comment,
                 "reflection_comment が正しく保存されるべき"
  end

  test "next_action のみ入力して他を nil にしても保存できること" do
    # からの？だけ入力してもバリデーションが通ることを確認する
    reflection = WeeklyReflection.create!(
      user:            users(:one),
      week_start_date: Date.parse("2026-03-23"),
      week_end_date:   Date.parse("2026-03-29"),
      next_action:     "この振り返りから他の習慣にも朝型を広げる"
    )

    reflection.reload
    assert_nil reflection.direct_reason
    assert_nil reflection.background_situation
    assert_equal "この振り返りから他の習慣にも朝型を広げる", reflection.next_action
  end
end
