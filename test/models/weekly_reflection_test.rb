# test/models/weekly_reflection_test.rb
#
# ==============================================================================
# WeeklyReflection モデルテスト（E-1: 気分スコア・presence バリデーション追加）
# ==============================================================================
#
# 【E-1 での追加テスト】
#   ① mood バリデーションテスト
#      - nil でも有効（任意入力）
#      - 1〜5 の整数で有効
#      - 0 は無効（範囲外）
#      - 6 は無効（範囲外）
#      - "3.5" の文字列（型キャスト前）は無効（only_integer）
#   ② reflection_comment の presence バリデーションテスト
#      - nil で無効
#      - 空文字で無効
#      - 空白のみで無効
#      - 入力ありで有効
#
# 【レビュー指摘への対応】
#   ① week_start_date を月曜日（月曜スタート）に統一
#      理由: 将来「週開始は月曜のみ」バリデーションが追加されても壊れないようにする
#           2026-04-07（火曜）→ 2026-04-06（月曜）に変更
#   ② テスト用の固定日付を将来のフィクスチャと重複しない範囲に設定
#      理由: UNIQUE(user_id, year, week_number) 制約でテストが突然壊れるのを防ぐ
#           2026-04 付近を使用（フィクスチャは 2026-01〜02 のため被らない）
#   ③ mood=3.5 テストを型キャスト対策済み形式に変更
#      理由: mood は integer カラムのため、Ruby で 3.5 を代入すると
#           ActiveRecord が 3 にキャストしてしまい false positive になる恐れがある。
#           文字列 "3.5" を直接代入する方法で型変換前の入力を検証する。
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
      week_end_date:   Date.parse("2026-02-20"),
      reflection_comment: "テスト" # E-1: presence 必須化に対応
    )
    assert_not reflection.valid?
    assert_includes reflection.errors[:week_end_date], "は週の開始日から6日後でなければなりません"
  end

  test "is valid when week_end_date is exactly 6 days after week_start_date" do
    reflection = WeeklyReflection.new(
      user:            users(:one),
      week_start_date: Date.parse("2026-02-16"),
      week_end_date:   Date.parse("2026-02-22"),
      reflection_comment: "テスト振り返りコメント" # E-1: presence 必須化に対応
    )
    assert reflection.valid?, reflection.errors.full_messages
  end

  # ============================================================
  # E-1 追加: mood（気分スコア）バリデーションテスト
  # ============================================================

  # ── mood が nil のとき有効（任意入力）────────────────────────────────────
  test "mood が nil でも有効であること（任意入力）" do
    reflection = build_valid_reflection(mood: nil)
    assert reflection.valid?, "mood=nil でも valid であるべき: #{reflection.errors.full_messages}"
  end

  # ── mood が 1〜5 の整数のとき有効 ─────────────────────────────────────────
  test "mood が 1 のとき有効であること" do
    reflection = build_valid_reflection(mood: 1)
    assert reflection.valid?, "mood=1 は valid であるべき: #{reflection.errors.full_messages}"
  end

  test "mood が 3 のとき有効であること" do
    reflection = build_valid_reflection(mood: 3)
    assert reflection.valid?, "mood=3 は valid であるべき: #{reflection.errors.full_messages}"
  end

  test "mood が 5 のとき有効であること" do
    reflection = build_valid_reflection(mood: 5)
    assert reflection.valid?, "mood=5 は valid であるべき: #{reflection.errors.full_messages}"
  end

  # ── mood が範囲外のとき無効 ───────────────────────────────────────────────
  test "mood が 0 のとき無効であること（最小値は1）" do
    reflection = build_valid_reflection(mood: 0)
    assert_not reflection.valid?, "mood=0 は invalid であるべき"
    assert reflection.errors[:mood].any?, "mood にエラーが存在するべき"
  end

  test "mood が 6 のとき無効であること（最大値は5）" do
    reflection = build_valid_reflection(mood: 6)
    assert_not reflection.valid?, "mood=6 は invalid であるべき"
    assert reflection.errors[:mood].any?, "mood にエラーが存在するべき"
  end

  test "mood が -1 のとき無効であること（負の値は不可）" do
    reflection = build_valid_reflection(mood: -1)
    assert_not reflection.valid?, "mood=-1 は invalid であるべき"
    assert reflection.errors[:mood].any?, "mood にエラーが存在するべき"
  end

  # ── mood が小数文字列のとき無効 ───────────────────────────────────────────
  #
  # 【レビュー指摘への対応: 型キャスト問題】
  #   mood は DB の integer カラムのため、Ruby で mood: 3.5 と代入すると
  #   ActiveRecord が自動的に 3（整数）にキャストする。
  #   その結果 3.5 → 3 → valid になり、テストが「小数を弾けていない」のに
  #   「パスする」という false positive（偽陽性）になる。
  #
  # 【解決方法: 文字列 "3.5" を使う】
  #   フォームからの入力はすべて文字列として届く。
  #   文字列 "3.5" を代入すると ActiveRecord は型変換を試みるが、
  #   only_integer: true のバリデーションが文字列パースの段階で弾く。
  #   これにより「フォームから "3.5" が送られてきたとき」の実際の動作を検証できる。
  #
  #   ただし Rails バージョンや DB アダプタによって挙動が異なる場合があるため、
  #   実際のパラメータ経由テストもブラウザで確認すること。
  test "mood に小数文字列 '3.5' を代入したとき無効であること（only_integer）" do
    reflection = build_valid_reflection
    # 文字列で直接代入することで型キャスト前のバリデーションを検証する
    # これはフォームから "3.5" という文字列が送られてきた場合のシミュレーション
    reflection[:mood] = "3.5"
    assert_not reflection.valid?, "mood='3.5' は invalid であるべき（整数のみ有効）"
    assert reflection.errors[:mood].any?, "mood にエラーが存在するべき"
  end

  # ============================================================
  # E-1 追加: reflection_comment の presence バリデーションテスト
  # ============================================================

  # ── reflection_comment が nil のとき無効 ──────────────────────────────────
  test "reflection_comment が nil のとき無効であること" do
    reflection = build_valid_reflection(reflection_comment: nil)
    assert_not reflection.valid?, "reflection_comment=nil は invalid であるべき"
    assert reflection.errors[:reflection_comment].any?,
           "reflection_comment にエラーが存在するべき"
  end

  # ── reflection_comment が空文字のとき無効 ───────────────────────────────
  test "reflection_comment が空文字のとき無効であること" do
    reflection = build_valid_reflection(reflection_comment: "")
    assert_not reflection.valid?, "reflection_comment='' は invalid であるべき"
    assert reflection.errors[:reflection_comment].any?,
           "reflection_comment にエラーが存在するべき"
  end

  # ── reflection_comment が空白文字のみのとき無効 ─────────────────────────
  test "reflection_comment が空白文字のみのとき無効であること" do
    # Rails の presence: true は内部で blank? を使うため
    # "   ".blank? => true のため空白のみも無効になる
    reflection = build_valid_reflection(reflection_comment: "   ")
    assert_not reflection.valid?, "reflection_comment=' ' は invalid であるべき"
    assert reflection.errors[:reflection_comment].any?,
           "reflection_comment にエラーが存在するべき"
  end

  # ── reflection_comment にテキストがあるとき有効 ──────────────────────────
  test "reflection_comment にテキストがあるとき有効であること" do
    reflection = build_valid_reflection(reflection_comment: "今週は頑張りました")
    assert reflection.valid?,
           "reflection_comment にテキストがあるときは valid であるべき: #{reflection.errors.full_messages}"
  end

  test "reflection_comment が 1000 文字のとき有効であること" do
    reflection = build_valid_reflection(reflection_comment: "あ" * 1000)
    assert reflection.valid?,
           "reflection_comment=1000文字は valid であるべき: #{reflection.errors.full_messages}"
  end

  test "reflection_comment が 1001 文字のとき無効であること" do
    reflection = build_valid_reflection(reflection_comment: "あ" * 1001)
    assert_not reflection.valid?, "reflection_comment=1001文字は invalid であるべき"
    assert reflection.errors[:reflection_comment].any?,
           "reflection_comment にエラーが存在するべき"
  end

  # ============================================================
  # next_action カラムのテスト（リフレクション手法対応で追加済み）
  # ============================================================

  test "next_action が nil でも有効であること（任意入力）" do
    reflection = build_valid_reflection(next_action: nil)
    assert reflection.valid?, "next_action=nil でも valid であるべき: #{reflection.errors.full_messages}"
  end

  test "next_action が空文字でも有効であること（任意入力）" do
    reflection = build_valid_reflection(next_action: "")
    assert reflection.valid?, "next_action='' でも valid であるべき: #{reflection.errors.full_messages}"
  end

  test "next_action が1000文字以内のとき有効であること" do
    reflection = build_valid_reflection(next_action: "あ" * 1000)
    assert reflection.valid?, "next_action=1000文字は valid であるべき: #{reflection.errors.full_messages}"
  end

  test "next_action が1001文字のとき無効であること" do
    reflection = build_valid_reflection(next_action: "あ" * 1001)
    assert_not reflection.valid?, "next_action=1001文字は invalid であるべき"
    assert reflection.errors[:next_action].any?, "next_action にエラーが存在するべき"
  end

  # ============================================================
  # リフレクション全フィールドの保存テスト（統合確認）
  # ============================================================

  test "mood を含む全フィールドがまとめて保存・取得できること" do
    # 【レビュー指摘対応】
    #   week_start_date は月曜日（月曜スタート）に固定する。
    #   2030-01-07（月）〜2030-01-13（日）を使用。
    #   フィクスチャ（2026年）と年が異なるため UNIQUE 制約には絶対に引っかからない。
    reflection = WeeklyReflection.create!(
      user:                  users(:one),
      week_start_date:       Date.parse("2030-01-07"), # 月曜日
      week_end_date:         Date.parse("2030-01-13"), # 日曜日（6日後）
      mood:                  4,
      direct_reason:         "残業が続き、帰宅後に動ける体力が残っていなかった",
      background_situation:  "朝30分早く起きてトレーニング時間を確保する",
      next_action:           "朝型の生活リズムを読書・英語学習にも広げる",
      reflection_comment:    "今週は特に疲れた。でも少し前進できた。"
    )

    reflection.reload

    assert_equal 4, reflection.mood, "mood が正しく保存されるべき"
    assert_equal "残業が続き、帰宅後に動ける体力が残っていなかった",
                 reflection.direct_reason,
                 "direct_reason が正しく保存されるべき"
    assert_equal "朝30分早く起きてトレーニング時間を確保する",
                 reflection.background_situation,
                 "background_situation が正しく保存されるべき"
    assert_equal "朝型の生活リズムを読書・英語学習にも広げる",
                 reflection.next_action,
                 "next_action が正しく保存されるべき"
    assert_equal "今週は特に疲れた。でも少し前進できた。",
                 reflection.reflection_comment,
                 "reflection_comment が正しく保存されるべき"
  end

  test "mood が nil のまま保存できること（任意入力）" do
    reflection = WeeklyReflection.create!(
      user:               users(:one),
      week_start_date:    Date.parse("2030-01-14"), # 月曜日
      week_end_date:      Date.parse("2030-01-20"), # 日曜日（6日後）
      mood:               nil,
      reflection_comment: "気分スコアなしの振り返り"
    )

    reflection.reload
    assert_nil reflection.mood, "mood=nil が正しく保存されるべき"
  end

  test "next_action のみ入力して他を nil にしても保存できること" do
    reflection = WeeklyReflection.create!(
      user:               users(:one),
      week_start_date:    Date.parse("2030-01-21"), # 月曜日
      week_end_date:      Date.parse("2030-01-27"), # 日曜日（6日後）
      next_action:        "この振り返りから他の習慣にも朝型を広げる",
      reflection_comment: "からの？だけ入力した振り返り"
    )

    reflection.reload
    assert_nil reflection.direct_reason
    assert_nil reflection.background_situation
    assert_equal "この振り返りから他の習慣にも朝型を広げる", reflection.next_action
  end

  # ============================================================
  # プライベートヘルパーメソッド
  # ============================================================
  private

  # build_valid_reflection
  # 【役割】
  #   バリデーションが通る最低限の有効なレコードをメモリ上に構築するヘルパー。
  #   各テストで重複コードを書かずに WeeklyReflection を組み立てられる。
  #
  # 【なぜ create! ではなく new を使うのか】
  #   バリデーションテストでは DB 保存は不要。
  #   new で組み立てた後 valid? を呼ぶだけでよいため
  #   DB アクセスをなくしてテストを高速化する。
  #
  # 【week_start_date の選択理由（レビュー指摘対応）】
  #   ① 月曜日（2030-01-28）に固定する
  #      → 将来「週開始は月曜のみ」バリデーションが追加されても安全
  #   ② 2030年を使用する
  #      → フィクスチャ（2026年）と年が異なるため UNIQUE 制約に絶対引っかからない
  #   ③ new（DB保存なし）なので実際には UNIQUE 制約は走らないが、
  #      create! を使うテストとの一貫性のため 2030年に統一する
  def build_valid_reflection(overrides = {})
    WeeklyReflection.new({
      user:               users(:one),
      week_start_date:    Date.parse("2030-01-28"), # 月曜日
      week_end_date:      Date.parse("2030-02-03"), # 日曜日（6日後）
      reflection_comment: "デフォルトの振り返りコメント"
    }.merge(overrides))
  end
end
