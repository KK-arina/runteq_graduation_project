# ファイルパス: test/models/weekly_reflection_test.rb
#
# 【このファイルの役割】
# WeeklyReflection モデルの動作を自動テストする。
# Issue #25 では complete! / completed? / pending? メソッドのテストを追加する。
#
# 【修正履歴】
# v3: freeze_time 内での travel_to ネストを修正
#   Rails が「freeze_time ブロック内で travel_to を呼ぶな」と警告するため、
#   以下のように変更した:
#
#   ❌ 修正前（エラーになる）:
#     freeze_time do
#       travel 1.hour do  ← freeze_time 内で時刻移動はNG
#         ...
#       end
#     end
#
#   ✅ 修正後（正しい書き方）:
#     freeze_time do
#       first_time = reflection.completed_at  # 最初の時刻を記録
#     end
#     travel 1.hour do  ← freeze_time の外で時刻移動する
#       reflection.complete!  # 2回目: 時刻が変わっても completed_at は変わらないはず
#       assert_equal first_time, ...
#     end
#
# 【テストの実行方法】
# docker compose exec web rails test test/models/weekly_reflection_test.rb

require "test_helper"

class WeeklyReflectionTest < ActiveSupport::TestCase
  # ============================================================
  # complete! メソッドのテスト（Issue #25 で追加）
  # ============================================================

  # 【テスト1】complete! を呼ぶと completed_at に現在時刻が入ること
  test "complete! sets completed_at to the exact current time" do
    reflection = weekly_reflections(:pending_reflection)
    assert_nil reflection.completed_at,
               "前提: テスト前は completed_at が nil であること"

    # freeze_time とは？
    # Time.current を「このブロックが実行された瞬間の時刻」で完全に固定する。
    # これがないと「complete! を呼んだ時刻」と「assert で確認する時刻」がズレる可能性があり、
    # テストが「たまに失敗する（フレーキーテスト）」になってしまう。
    freeze_time do
      reflection.complete!

      # reload でDBから最新データを再取得する
      # （メモリ上のオブジェクトではなく、実際にDBに保存された値を確認するため）
      reflection.reload

      assert_not_nil reflection.completed_at,
                     "complete! 後は completed_at に時刻が入ること"

      # freeze_time により Time.current は固定されているので、1秒の誤差も出ない
      assert_equal Time.current.to_i,
                   reflection.completed_at.to_i,
                   "complete! 後の completed_at は凍結した現在時刻と一致すること"
    end
  end

  # 【テスト2】complete! の冪等性テスト
  #
  # 冪等性（べきとうせい）とは？
  # 「何度実行しても同じ結果になる性質」のこと。
  # complete! を2回呼んでも completed_at が最初の時刻のままであることを確認する。
  #
  # 【修正のポイント】
  # freeze_time ブロックの「内側」で travel_to / travel を呼ぶと Rails が警告を出す。
  # → 1回目と2回目を「別々のブロック」に分けて解決する。
  test "complete! does not overwrite completed_at when called twice - idempotency" do
    reflection = weekly_reflections(:pending_reflection)

    # === 1回目: freeze_time で時刻を固定して complete! を呼ぶ ===
    first_completed_at = nil

    freeze_time do
      reflection.complete!
      reflection.reload
      # 1回目の完了時刻を変数に保存しておく
      first_completed_at = reflection.completed_at
      assert_not_nil first_completed_at,
                     "1回目の complete! で completed_at が設定されること"
    end

    # === 2回目: 1時間後に travel して complete! を呼ぶ ===
    # travel とは？
    # 現在時刻を「指定した分だけ進めた」状態でブロックを実行する。
    # freeze_time とは違い、「今から1時間後」という相対的な指定ができる。
    travel 1.hour do
      reflection.complete!
      reflection.reload

      # completed_at が最初の時刻のまま変わっていないことを確認する
      # 1時間後に complete! を呼んでも、すでに completed? = true なので何もしないはず
      assert_equal first_completed_at.to_i,
                   reflection.completed_at.to_i,
                   "complete! を2回呼んでも completed_at は最初の時刻のまま変わらないこと（冪等性）"
    end
  end

  # 【テスト3】completed? は complete! 前後で正しく true/false を返すこと
  test "completed? returns false before complete! and true after" do
    reflection = weekly_reflections(:pending_reflection)

    assert_not reflection.completed?,
               "complete! 前は completed? が false であること"

    reflection.complete!

    assert reflection.completed?,
           "complete! 後は completed? が true であること"
  end

  # 【テスト4】pending? は completed? の逆であること
  test "pending? is the inverse of completed?" do
    reflection = weekly_reflections(:pending_reflection)

    # 未完了状態: pending? = true, completed? = false
    assert reflection.pending?,
           "complete! 前は pending? が true であること"
    assert_not reflection.completed?,
               "complete! 前は completed? が false であること"

    reflection.complete!

    # 完了後: pending? = false, completed? = true
    assert_not reflection.pending?,
               "complete! 後は pending? が false であること"
    assert reflection.completed?,
           "complete! 後は completed? が true であること"
  end

  # 【テスト5】新規インスタンスは未完了状態であること
  test "completed? returns false and pending? returns true for a new unsaved record" do
    reflection = WeeklyReflection.new
    assert_not reflection.completed?,
               "新規（未保存）レコードは completed? が false であること"
    assert reflection.pending?,
           "新規（未保存）レコードは pending? が true であること"
  end

  # 【テスト6】完了済みレコードは completed? が true、pending? が false であること
  test "completed_reflection fixture has correct completed? and pending? state" do
    reflection = weekly_reflections(:completed_reflection)
    assert_not_nil reflection.completed_at

    assert reflection.completed?,
           "completed_at が設定されているレコードは completed? が true であること"
    assert_not reflection.pending?,
               "completed_at が設定されているレコードは pending? が false であること"
  end

  # ============================================================
  # locked? との統合テスト（Issue #25 の核心）
  # ============================================================
  #
  # application_controller.rb の locked? は pending? を使って判定している。
  # 「振り返り完了 → pending? が false → locked? が false」という連鎖を確認する。

  # 【テスト7】前週の振り返りを complete! すると pending? が false になること
  test "completing last week reflection makes pending? return false" do
    # travel_to で「月曜日の AM4:01」に時刻を固定する
    travel_to Time.zone.parse("2026-02-16 04:01:00") do # 月曜日 AM4:01
      # pending_reflection は 2026-02-09 週（前週）の未完了振り返り
      reflection = weekly_reflections(:pending_reflection)
      assert reflection.pending?,
             "前提: complete! 前は pending? が true であること"

      reflection.complete!

      assert_not reflection.pending?,
                 "complete! 後は pending? が false になること"
      assert reflection.completed?,
             "complete! 後は completed? が true になること"
    end
  end

  # 【テスト8】AM3:59 境界値テスト（ロックが早まらないことを確認）
  test "pending? behavior is unaffected by the 4AM boundary" do
    # AM3:59 と AM4:01 で pending? の動作は変わらない（時刻はモデルと無関係）
    # pending? は completed_at の有無だけを見る
    reflection = weekly_reflections(:pending_reflection)

    travel_to Time.zone.parse("2026-02-16 03:59:00") do
      assert reflection.pending?,
             "AM3:59 でも未完了の振り返りは pending? が true であること"
    end

    travel_to Time.zone.parse("2026-02-16 04:01:00") do
      assert reflection.pending?,
             "AM4:01 でも（complete! 前なので）pending? が true であること"
    end
  end

  # ============================================================
  # バリデーションテスト
  # ============================================================

  test "is invalid when week_end_date is not 6 days after week_start_date" do
    reflection = WeeklyReflection.new(
      user:               users(:one),
      week_start_date:    Date.parse("2026-02-16"),
      week_end_date:      Date.parse("2026-02-20"), # 4日後（誤り: 6日後でなければならない）
      reflection_comment: "テスト"
    )

    assert_not reflection.valid?,
               "week_end_date が week_start_date + 4日の場合はバリデーションエラーになること"
    assert_includes reflection.errors[:week_end_date],
                    "は週の開始日から6日後でなければなりません"
  end

  test "is valid when week_end_date is exactly 6 days after week_start_date" do
    reflection = WeeklyReflection.new(
      user:               users(:one),
      week_start_date:    Date.parse("2026-02-16"), # 月曜日
      week_end_date:      Date.parse("2026-02-22"), # 日曜日（6日後）
      reflection_comment: "テスト"
    )

    assert reflection.valid?,
           "week_end_date が week_start_date + 6日の場合はバリデーションが通ること"
  end
end
