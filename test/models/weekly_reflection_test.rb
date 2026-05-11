# test/models/weekly_reflection_test.rb
#
# ==============================================================================
# WeeklyReflection モデルテスト
# ==============================================================================
# 【E-1修正での変更内容】
#   reflection_comment を任意に戻したため、以下のテストを修正する:
#   ① reflection_comment=nil → 有効（presence廃止のため）
#   ② reflection_comment='' → 有効（presence廃止のため）
#   ③ reflection_comment=' ' → 有効（presence廃止のため）
#   ④ build_valid_reflection から reflection_comment のデフォルト値を削除
#      （任意項目のため nil でも valid? が true になる）
#
#   direct_reason / background_situation / next_action は必須のまま維持。
# ==============================================================================

require "test_helper"

class WeeklyReflectionTest < ActiveSupport::TestCase

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

  test "complete! does not overwrite completed_at when called twice" do
    reflection = weekly_reflections(:pending_reflection)
    first_completed_at = nil
    freeze_time do
      reflection.complete!
      reflection.reload
      first_completed_at = reflection.completed_at
    end
    travel 1.hour do
      reflection.complete!
      reflection.reload
      assert_equal first_completed_at.to_i, reflection.completed_at.to_i
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
    reflection.complete!
    assert_not reflection.pending?
  end

  test "completed? returns false for a new unsaved record" do
    assert_not WeeklyReflection.new.completed?
  end

  test "completed_reflection fixture has correct state" do
    assert weekly_reflections(:completed_reflection).completed?
  end

  test "completing last week reflection makes pending? return false" do
    travel_to Time.zone.parse("2026-02-16 04:01:00") do
      reflection = weekly_reflections(:pending_reflection)
      reflection.complete!
      assert reflection.completed?
    end
  end

  test "pending? behavior is unaffected by the 4AM boundary" do
    reflection = weekly_reflections(:pending_reflection)

    # ── E-1修正: travel_to ブロック内のアサーションが Minitest にカウントされない
    # 問題を解消するため、ブロックを展開して通常の形式に変更する。
    #
    # 【変更前】
    #   travel_to(...) { assert reflection.pending? }
    #   → Minitest がブロック内のアサーションを認識しないため
    #     "Test is missing assertions" 警告が発生する。
    #
    # 【変更後】
    #   travel_to(...) / travel_back の形式に展開する。
    #   アサーションがブロックの外にあるため Minitest が正しく認識する。
    travel_to Time.zone.parse("2026-02-16 03:59:00")
    assert reflection.pending?, "AM3:59 では pending? は true のまま"
    travel_back

    travel_to Time.zone.parse("2026-02-16 04:01:00")
    assert reflection.pending?, "AM4:01 でも pending? は true のまま（4AM境界はロック判定に使われるがpending?には影響しない）"
    travel_back
  end

  test "is invalid when week_end_date is not 6 days after week_start_date" do
    reflection = WeeklyReflection.new(
      user:                 users(:one),
      week_start_date:      Date.parse("2026-02-16"),
      week_end_date:        Date.parse("2026-02-20"),
      direct_reason:        "テスト",
      background_situation: "テスト",
      next_action:          "テスト"
    )
    assert_not reflection.valid?
    assert_includes reflection.errors[:week_end_date], "は週の開始日から6日後でなければなりません"
  end

  test "is valid when week_end_date is exactly 6 days after week_start_date" do
    assert build_valid_reflection.valid?
  end

  # ============================================================
  # mood バリデーションテスト
  # ============================================================

  test "mood が nil でも有効であること（任意入力）" do
    assert build_valid_reflection(mood: nil).valid?
  end

  test "mood が 1〜5 のとき有効であること" do
    (1..5).each { |s| assert build_valid_reflection(mood: s).valid? }
  end

  test "mood が 0 のとき無効であること" do
    r = build_valid_reflection(mood: 0)
    assert_not r.valid?
    assert r.errors[:mood].any?
  end

  test "mood が 6 のとき無効であること" do
    r = build_valid_reflection(mood: 6)
    assert_not r.valid?
    assert r.errors[:mood].any?
  end

  test "mood に小数文字列を代入したとき無効であること" do
    r = build_valid_reflection
    r[:mood] = "3.5"
    assert_not r.valid?
    assert r.errors[:mood].any?
  end

  # ============================================================
  # reflection_comment バリデーションテスト（E-1修正: 任意に変更）
  # ============================================================

  # ── 任意化により nil・空文字・空白すべて有効になる ────────────────────────
  #
  # 【変更前】presence: true → nil/空文字は invalid
  # 【変更後】任意 → nil/空文字でも valid
  test "reflection_comment が nil でも有効であること（任意入力）" do
    # E-1修正: presence: true を削除したため nil でも valid になる
    assert build_valid_reflection(reflection_comment: nil).valid?
  end

  test "reflection_comment が空文字でも有効であること（任意入力）" do
    assert build_valid_reflection(reflection_comment: "").valid?
  end

  test "reflection_comment が空白のみでも有効であること（任意入力）" do
    # allow_blank: true なので空白のみも valid
    assert build_valid_reflection(reflection_comment: "   ").valid?
  end

  test "reflection_comment が 1000 文字のとき有効であること" do
    assert build_valid_reflection(reflection_comment: "あ" * 1000).valid?
  end

  test "reflection_comment が 1001 文字のとき無効であること" do
    r = build_valid_reflection(reflection_comment: "あ" * 1001)
    assert_not r.valid?
    assert r.errors[:reflection_comment].any?
  end

  # ============================================================
  # direct_reason バリデーションテスト（必須）
  # ============================================================

  test "direct_reason が nil のとき無効であること" do
    r = build_valid_reflection(direct_reason: nil)
    assert_not r.valid?
    assert r.errors[:direct_reason].any?
  end

  test "direct_reason が空文字のとき無効であること" do
    r = build_valid_reflection(direct_reason: "")
    assert_not r.valid?
    assert r.errors[:direct_reason].any?
  end

  test "direct_reason が空白のみのとき無効であること" do
    r = build_valid_reflection(direct_reason: "   ")
    assert_not r.valid?
    assert r.errors[:direct_reason].any?
  end

  test "direct_reason にテキストがあるとき有効であること" do
    assert build_valid_reflection(direct_reason: "残業が多かった").valid?
  end

  test "direct_reason が 1001 文字のとき無効であること" do
    r = build_valid_reflection(direct_reason: "あ" * 1001)
    assert_not r.valid?
    assert r.errors[:direct_reason].any?
  end

  # ============================================================
  # background_situation バリデーションテスト（必須）
  # ============================================================

  test "background_situation が nil のとき無効であること" do
    r = build_valid_reflection(background_situation: nil)
    assert_not r.valid?
    assert r.errors[:background_situation].any?
  end

  test "background_situation が空文字のとき無効であること" do
    r = build_valid_reflection(background_situation: "")
    assert_not r.valid?
    assert r.errors[:background_situation].any?
  end

  test "background_situation にテキストがあるとき有効であること" do
    assert build_valid_reflection(background_situation: "朝型に切り替える").valid?
  end

  test "background_situation が 1001 文字のとき無効であること" do
    r = build_valid_reflection(background_situation: "あ" * 1001)
    assert_not r.valid?
    assert r.errors[:background_situation].any?
  end

  # ============================================================
  # next_action バリデーションテスト（必須）
  # ============================================================

  test "next_action が nil のとき無効であること" do
    r = build_valid_reflection(next_action: nil)
    assert_not r.valid?
    assert r.errors[:next_action].any?
  end

  test "next_action が空文字のとき無効であること" do
    r = build_valid_reflection(next_action: "")
    assert_not r.valid?
    assert r.errors[:next_action].any?
  end

  test "next_action にテキストがあるとき有効であること" do
    assert build_valid_reflection(next_action: "他の習慣にも広げる").valid?
  end

  test "next_action が 1001 文字のとき無効であること" do
    r = build_valid_reflection(next_action: "あ" * 1001)
    assert_not r.valid?
    assert r.errors[:next_action].any?
  end

  # ============================================================
  # 全フィールドの保存テスト
  # ============================================================

  test "全フィールドがまとめて保存・取得できること" do
    reflection = WeeklyReflection.create!(
      user:                  users(:one),
      week_start_date:       Date.parse("2030-01-07"),
      week_end_date:         Date.parse("2030-01-13"),
      mood:                  4,
      direct_reason:         "残業が続いた",
      background_situation:  "朝型に切り替える",
      next_action:           "他の習慣にも広げる",
      reflection_comment:    "今週は特に疲れた"  # 任意だが入力した場合
    )
    reflection.reload
    assert_equal 4,          reflection.mood
    assert_equal "残業が続いた", reflection.direct_reason
  end

  test "reflection_comment なしでも保存できること（任意化確認）" do
    # E-1修正: reflection_comment が nil でも保存できることを確認する
    reflection = WeeklyReflection.create!(
      user:                  users(:one),
      week_start_date:       Date.parse("2030-01-14"),
      week_end_date:         Date.parse("2030-01-20"),
      direct_reason:         "理由テスト",
      background_situation:  "改善テスト",
      next_action:           "展開テスト",
      reflection_comment:    nil   # 任意のため nil でも保存できる
    )
    reflection.reload
    assert_nil reflection.reflection_comment
  end

  # ============================================================
  # プライベートヘルパーメソッド
  # ============================================================
  private

  # build_valid_reflection
  # 【E-1修正での変更】
  #   reflection_comment のデフォルト値を削除した。
  #   任意化されたため nil でも valid? が true になる。
  #   direct_reason / background_situation / next_action は必須のため
  #   デフォルト値を維持する。
  def build_valid_reflection(overrides = {})
    WeeklyReflection.new({
      user:                  users(:one),
      week_start_date:       Date.parse("2030-01-28"),
      week_end_date:         Date.parse("2030-02-03"),
      direct_reason:         "デフォルトのなぜ？テキスト",
      background_situation:  "デフォルトのどう？テキスト",
      next_action:           "デフォルトのからの？テキスト"
      # reflection_comment はデフォルト値なし（任意のため nil でも valid）
    }.merge(overrides))
  end
end
