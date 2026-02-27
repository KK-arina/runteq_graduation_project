# test/integration/pdca_lock_flow_test.rb
#
# ═══════════════════════════════════════════════════════════════════
# Issue #30: 統合テスト（主要フロー）
# 【テスト対象】PDCA強制ロック機能のフロー
#
# 【このファイルがカバーする範囲】
#   - ロック発動から振り返り完了によるロック解除までの完全フロー
#   - ロック中でも記録（チェック）はできること
#   - ロック解除後は通常操作ができること
#   - ダッシュボードの警告バナー表示・非表示
#
# 【既存テストとの棲み分け】
#   pdca_lock_test.rb → ロック中の各操作制限（個別機能の確認）
#   ↓ このファイルは「ロック発動→振り返り作成→ロック解除→習慣作成」という
#     エンドツーエンドのフロー（一連の流れ）をテストします
#
# 【travel_to について】
#   PDCAロックは「月曜日のAM4:00以降」に発動する時間依存機能です。
#   travel_to を使って時刻を固定することで、
#   どの曜日・時間にテストを実行しても再現性が保証されます。
#
# 【レビュー反映 ④】日付を完全固定に変更
#   変更前:
#     next_monday = Date.current.beginning_of_week(:monday) + 1.week
#     travel_to next_monday.in_time_zone.change(hour: 4, min: 1) do
#
#   ❗ 問題点:
#     Date.current は travel_to の「外」で評価されます。
#     テスト実行タイミングによっては travel_to で意図した時刻と
#     Date.current の計算結果がズレる可能性があります。
#
#   変更後:
#     travel_to Time.zone.local(2026, 3, 9, 4, 1, 0) do
#
#   ✅ 改善理由:
#     完全固定の日付を使うことで「どの環境・どの時間帯で実行しても
#     必ず同じ結果になる」再現性を最大化できます。
# ═══════════════════════════════════════════════════════════════════

require "test_helper"

class PdcaLockFlowTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストメソッドの実行前に毎回自動的に呼ばれる準備処理
  # ============================================================
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)

    # habit_records に今日の日付のデータが残っていると重複エラーになるため
    # テスト前にクリアします
    # delete_all は Rails のコールバックをスキップして直接 SQL DELETE を実行するため高速です
    HabitRecord.where(user: @user).delete_all
  end

  # ============================================================
  # ヘルパーメソッド: 前週の振り返りを作成する
  # ============================================================
  # 【引数の意味】
  #   completed: true  → 完了済み（completed_at に現在時刻をセット）
  #                       → locked? が false = ロック解除状態
  #   completed: false → 未完了（completed_at は nil のまま）
  #                       → locked? が true = ロック中状態
  #
  # 【なぜ current_week_start から計算するのか？】
  #   travel_to で時刻を固定した環境内で「前週」を正確に計算するため。
  #   固定された現在時刻を基準に「今週の月曜日 - 7日 = 前週の月曜日」を求めます。
  def create_last_week_reflection(completed:)
    # Date.current.beginning_of_week(:monday) → travel_to で固定した時刻での今週月曜日
    # - 1.week → 前週の月曜日
    last_week_start = Date.current.beginning_of_week(:monday) - 1.week

    WeeklyReflection.create!(
      user:               @user,
      week_start_date:    last_week_start,
      week_end_date:      last_week_start + 6.days,  # 月曜日 + 6日 = 日曜日
      reflection_comment: "テスト用前週振り返り",
      # completed: true のとき completed_at に時刻を入れる（完了済み）
      # completed: false のとき nil のまま（未完了 = pending? = true = ロック対象）
      completed_at:       completed ? Time.current : nil
    )
  end

  # ============================================================
  # テスト1: ロック発動→振り返り作成（ロック解除）→習慣作成の完全フロー
  # ============================================================
  # 【レビュー反映 ④】日付を完全固定に変更
  # 変更前: next_monday = Date.current.beginning_of_week + 1.week
  #         travel_to next_monday.in_time_zone.change(hour: 4, min: 1) do
  # ❗ 問題点: Date.current が travel_to の「外」で評価されるため、
  #   テスト実行タイミングによっては意図した時刻とズレる可能性があります。
  # 変更後: travel_to Time.zone.local(2026, 3, 9, 4, 1, 0) do
  # ✅ 2026-03-09（月）AM4:01 = ロック条件を確実に満たし、fixtures と重複しない日付
  test "ロック発動→振り返り完了によるロック解除→習慣作成の完全フロー" do
    # travel_to: テスト中の「現在時刻」を 2026-03-09（月）AM4:01 に完全固定します
    # これにより Date.current / Time.current が全てこの時刻を返します
    travel_to Time.zone.local(2026, 3, 9, 4, 1, 0) do

      # 前週の振り返りを「未完了」で作成 → ロック発動の原因
      create_last_week_reflection(completed: false)

      log_in_as(@user)

      # ── Step 1: ロック中はダッシュボードに警告バナーが表示される ──
      get dashboard_path
      assert_response :success

      # ダッシュボードの警告バナーが表示されること
      # DashboardsController#index で @locked = locked? を計算し
      # ビューで @locked が true のとき警告バナーを表示します
      assert_select "p", text: /先週の振り返りが未完了のため、一部の操作が制限されています/

      # ── Step 2: ロック中は習慣を新規作成できない ──────────────────
      # HabitsController の before_action :require_unlocked が
      # create アクションの前に locked? をチェックします
      assert_no_difference("Habit.count") do
        post habits_path, params: {
          habit: { name: "ロック中に作成しようとした習慣", weekly_target: 5 }
        }
      end

      # require_unlocked は flash[:alert] をセットして redirect_back します
      assert_response :redirect
      follow_redirect!
      assert_select "div", text: /先週の振り返りが未完了のため、この操作はできません/

      # ── Step 3: ロック中でも日次記録（チェック）はできる ──────────
      # HabitRecordsController には require_unlocked が設定されていません
      # 今日の記録を行う操作はロック中でも許可されます（設計上の意図）
      assert_difference("HabitRecord.count", 1) do
        post habit_habit_records_path(@habit),
             params:  { completed: "1" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end

      assert_response :success

      # ── Step 4: 振り返りフォームにアクセスできる ──────────────────
      # WeeklyReflectionsController の new / create には require_unlocked は設定されていません
      # ロック中でも振り返りを入力・保存することができます（ロック解除のために必要）
      get new_weekly_reflection_path
      assert_response :success

      # ── Step 5: 振り返りを保存してロックを解除する ────────────────
      # 今週の振り返りを作成します（fixtures と重複しない週）
      # travel_to で固定した時刻が「次の月曜日 AM4:01」なので、
      # 今週は「現在の月曜日〜日曜日」の範囲になります
      assert_difference("WeeklyReflection.count", 1) do
        post weekly_reflections_path, params: {
          weekly_reflection: {
            reflection_comment: "ロック解除のための振り返り"
          }
        }
      end

      # WeeklyReflectionsController#create の中で was_locked = true の場合
      # last_week の振り返りにも complete! を呼んでロックを解除します
      # その後 dashboard_path にリダイレクトします
      assert_redirected_to dashboard_path
      follow_redirect!

      # ロック解除メッセージが表示されること
      # flash[:unlock] に格納されたメッセージを確認します
      assert_select "body", text: /PDCAロックが解除されました/

      # ── Step 6: ロック解除後はダッシュボードに警告バナーが消える ──
      get dashboard_path
      assert_response :success
      assert_select "p",
        text:  /先週の振り返りが未完了のため、一部の操作が制限されています/,
        count: 0  # count: 0 → このテキストが0件（表示されない）であることを確認

      # ── Step 7: ロック解除後は習慣を作成できる ───────────────────
      assert_difference("Habit.count", 1) do
        post habits_path, params: {
          habit: { name: "ロック解除後に作成した習慣", weekly_target: 3 }
        }
      end

      assert_redirected_to habits_path
    end
  end

  # ============================================================
  # テスト2: 初週ユーザー（前週振り返りなし）はロックされないこと
  # ============================================================
  # 【なぜこのテストが必要か？】
  # ApplicationController の locked? メソッドには
  # 「前週レコードが存在しない場合はロックしない」という初週ユーザー対応があります。
  # （Step 3: last_week_exists が false の場合 return false）
  # この設計が正しく機能しているかを確認します。
  # 【レビュー反映 ④】日付を完全固定（テスト1と異なる日付で干渉を防ぐ）
  # 2026-03-16（月）AM4:01 を使用します（テスト1の 03-09 と異なる週）
  test "初週ユーザーは前週振り返りがなくてもロックされないこと" do
    # 2026-03-16（月）AM4:01 に完全固定します
    travel_to Time.zone.local(2026, 3, 16, 4, 1, 0) do

      # 前週の振り返りを作成しない（= 初週ユーザーの状態）

      log_in_as(@user)

      # ダッシュボードに警告バナーが表示されないこと
      get dashboard_path
      assert_response :success
      assert_select "p",
        text:  /先週の振り返りが未完了のため、一部の操作が制限されています/,
        count: 0  # 警告バナーが表示されないことを確認

      # 習慣を新規作成できること
      assert_difference("Habit.count", 1) do
        post habits_path, params: {
          habit: { name: "初週に作成した習慣", weekly_target: 7 }
        }
      end

      assert_redirected_to habits_path
    end
  end
end
