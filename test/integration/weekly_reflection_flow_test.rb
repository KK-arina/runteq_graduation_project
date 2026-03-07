# test/integration/weekly_reflection_flow_test.rb
#
# ═══════════════════════════════════════════════════════════════════
# Issue #30: 統合テスト（主要フロー）
# 【テスト対象】週次振り返りフローのテスト
#
# 【このファイルがカバーする範囲】
#   - 振り返り一覧ページの表示
#   - 振り返り新規作成→保存→一覧ページへのリダイレクト
#   - 振り返り詳細ページの表示
#   - 完了済み振り返りへの再アクセス（リダイレクト）
#   - WeeklyReflectionHabitSummary（スナップショット）の作成確認
#
# 【既存テストとの棲み分け】
#   weekly_reflection_index_test.rb → 一覧ページの表示確認（個別機能）
#   weekly_reflection_create_test.rb → バリデーション確認（個別機能）
#   ↓ このファイルは「一覧確認→振り返り作成→詳細確認」という
#     エンドツーエンドのフロー（一連の流れ）をテストします
#
# 【travel_to について】
#   travel_to は Rails の TimeHelpers で提供されるメソッドです。
#   「現在時刻」を指定した時刻に固定することで、
#   テスト実行日時に関わらず常に同じ結果を得られます（再現性の保証）。
#   週次振り返りは「今週の月曜日〜日曜日」の範囲に依存するため
#   travel_to を使った時刻固定が必須です。
# ═══════════════════════════════════════════════════════════════════

require "test_helper"

class WeeklyReflectionFlowTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストメソッドの実行前に毎回自動的に呼ばれる準備処理
  # ============================================================
  setup do
    # users(:one) → test/fixtures/users.yml の "one" キーのデータを取得
    @user  = users(:one)
    # habits(:habit_one) → test/fixtures/habits.yml の "habit_one" キーのデータを取得
    @habit = habits(:habit_one)
  end

  # ============================================================
  # テスト1: 振り返り作成フロー（一覧→新規作成→保存→詳細確認）
  # ============================================================
  # 【なぜ travel_to を使うのか？】
  #   WeeklyReflection.find_or_build_for_current_week は
  #   「今週の月曜日」を起点に振り返りを検索・生成します。
  #   テストを実行する日が変わると week_start_date が変わり、
  #   fixtures との衝突（UNIQUE制約エラー）が起きる可能性があります。
  #   travel_to で「日曜日の午前5時」に固定することで、
  #   fixtures（completed_one: 2026-01-05 〜 / completed_reflection: 2026-02-02 〜）
  #   と重複しない安全な時刻でテストを実行します。
  test "振り返り一覧→新規作成→保存→詳細確認ができること" do
    # travel_to: テスト中の「現在時刻」を 2026-03-01 AM5:00（日曜）に固定します
    # 2026-03-01（日曜）のため、今週は 2026-02-23（月曜）〜 2026-03-01（日曜）
    # この週の振り返りは fixtures に存在しないため UNIQUE 制約に違反しません
    travel_to Time.zone.local(2026, 3, 1, 5, 0, 0) do
      log_in_as(@user)

      # ── Step 1: 振り返り一覧ページにアクセス ─────────────────────
      get weekly_reflections_path
      assert_response :success

      # 「今週の状況」セクションが表示されること
      assert_select "body", text: /今週の状況/
      # 「過去の振り返り履歴」セクションが表示されること
      assert_select "body", text: /過去の振り返り履歴/

      # ── Step 2: 振り返り新規作成フォームにアクセス ────────────────
      get new_weekly_reflection_path
      assert_response :success

      # ── Step 3: 振り返りを保存する ────────────────────────────────
      # assert_difference: ブロック実行後に WeeklyReflection のレコードが
      # 1件増えることを確認します（保存が成功したことの証明）
      assert_difference("WeeklyReflection.count", 1) do
        post weekly_reflections_path, params: {
          weekly_reflection: {
            reflection_comment: "今週は読書を毎日できた。来週も継続したい。"
          }
        }
      end

      # WeeklyReflectionsController#create は保存後に weekly_reflections_path に
      # リダイレクトします（ロック中でない場合）
      assert_redirected_to weekly_reflections_path

      # 保存された振り返りを取得します
      week_start = Date.new(2026, 2, 23) # travel_toで固定した週の月曜
      reflection = @user.weekly_reflections.find_by(week_start_date: week_start)
      assert_not_nil reflection, "2026-02-23週の振り返りがDBに見つかりません"

      # ── Step 4: WeeklyReflectionHabitSummary（スナップショット）が
      #            作成されていることを確認 ─────────────────────────
      # WeeklyReflectionsController#create では
      # WeeklyReflectionHabitSummary.create_all_for_reflection! を呼んでいます。
      # これによりユーザーの全有効習慣のスナップショットが作成されるはずです。
      expected_habits_count = @user.habits.active.count
      assert_equal expected_habits_count, reflection.habit_summaries.count,
        "振り返り保存後、ユーザーの全有効習慣のスナップショットが作成されているはず"

      # ── Step 5: 保存後に complete! が呼ばれていること ─────────────
      # WeeklyReflectionsController#create は保存後に complete! を呼び出します。
      # complete! は completed_at に現在時刻をセットします。
      reflection.reload  # DB から最新状態を再取得
      assert reflection.completed?,
        "保存後は completed? が true になっているはず"

      # ── Step 6: 詳細ページが表示されること ───────────────────────
      get weekly_reflection_path(reflection)
      assert_response :success

      # 振り返りコメントが詳細ページに表示されること
      assert_select "body", text: /今週は読書を毎日できた/
    end
  end

  # ============================================================
  # テスト2: 完了済み振り返りに再度アクセスしてもリダイレクトされること
  # ============================================================
  # 【なぜこのテストが必要か？】
  # WeeklyReflectionsController#new では、今週の振り返りが既に完了済みの場合
  # 「今週の振り返りは既に完了しています。」というメッセージと共に
  # 詳細ページにリダイレクトします。
  # この動作を確認することで、同じ週に2回振り返りを作成できないことを保証します。
  test "既に完了済みの振り返りがある週に新規作成フォームへアクセスするとリダイレクトされること" do
    # 2026-03-08（日曜）に固定します
    # 今週は 2026-03-02（月曜）〜 2026-03-08（日曜）
    travel_to Time.zone.local(2026, 3, 8, 5, 0, 0) do
      log_in_as(@user)

      # 今週の振り返りを事前に「完了済み」状態で作成します
      existing_reflection = WeeklyReflection.create!(
        user:               @user,
        week_start_date:    Date.new(2026, 3, 2),  # 今週月曜日
        week_end_date:      Date.new(2026, 3, 8),  # 今週日曜日
        reflection_comment: "既に完了済みの振り返り",
        completed_at:       Time.current,           # 完了済み（nil でない）
        is_locked:          true                    # is_locked も合わせて true にする
      )

      # 新規作成フォームにアクセスすると完了済みの振り返り詳細にリダイレクト
      # WeeklyReflectionsController#new の条件:
      # if @weekly_reflection.persisted? && @weekly_reflection.is_locked?
      get new_weekly_reflection_path
      assert_redirected_to weekly_reflections_path
    end
  end

  # ============================================================
  # テスト3: 振り返りの詳細ページで習慣スナップショットが表示されること
  # ============================================================
  # 【なぜこのテストが必要か？】
  # WeeklyReflectionsController#show では habit_summaries を takes:habit で
  # 一括取得（N+1対策）して表示します。
  # fixtures の completed_one（振り返り）+ summary_one / summary_two（スナップショット）
  # のデータを使って、詳細ページの表示内容を確認します。
  test "振り返り詳細ページで習慣スナップショットが表示されること" do
    log_in_as(@user)

    # fixtures の completed_one の振り返りを使います
    # weekly_reflections(:completed_one) は users(:one) に紐づく完了済み振り返りです
    reflection = weekly_reflections(:completed_one)

    get weekly_reflection_path(reflection)
    assert_response :success

    # 振り返りコメントが表示されること
    assert_select "body", text: /completed_oneの振り返り/

    # 習慣スナップショット（summary_one の "ランニング"）が表示されること
    # weekly_reflection_habit_summaries.yml の summary_one のデータ
    assert_select "body", text: /ランニング/

    # 習慣スナップショット（summary_two の "瞑想"）が表示されること
    assert_select "body", text: /瞑想/
  end
end
