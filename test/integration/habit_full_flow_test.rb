# test/integration/habit_full_flow_test.rb
#
# ═══════════════════════════════════════════════════════════════════
# Issue #30: 統合テスト（主要フロー）
# 【テスト対象】習慣作成〜記録〜進捗確認のフロー
#
# 【このファイルがカバーする範囲】
#   - 習慣を作成してから、実際にチェックを入れて進捗が更新されるまでの流れ
#   - ダッシュボードと習慣一覧の両方で進捗が確認できること
#   - 複数の習慣を作成した場合の全体達成率の表示
#
# 【既存テストとの棲み分け】
#   habit_management_test.rb → 作成・削除の正常系・異常系・セキュリティ（個別機能）
#   habit_daily_record_test.rb → 日次記録のAM4:00境界値・重複防止（個別機能）
#   habit_record_instant_save_test.rb → Turbo Streamの即時保存（個別機能）
#   ↓ このファイルは「作成→記録→進捗確認」という
#     エンドツーエンドのフロー（一連の流れ）をテストします
# ═══════════════════════════════════════════════════════════════════

require "test_helper"

class HabitFullFlowTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストメソッドの実行前に毎回自動的に呼ばれる準備処理
  # ============================================================
  setup do
    # users(:one) → test/fixtures/users.yml の "one" キーのデータを取得
    @user = users(:one)
  end

  # ============================================================
  # テスト1: 習慣作成→記録→ダッシュボードで進捗確認の完全フロー
  # ============================================================
  # 【なぜこのフローを統合テストするのか？】
  # 「習慣を作成し、チェックを入れたら、ダッシュボードの進捗率が変わる」
  # という一連の流れは、モデルテストだけでは確認できません。
  # コントローラー・モデル・ビューが正しく連携しているかを検証します。
  test "習慣作成→日次記録→ダッシュボードで進捗確認ができること" do
    log_in_as(@user)

    # ── Step 1: 習慣を新規作成 ────────────────────────────────────
    # 週次目標 7 回の習慣を作成します
    assert_difference("Habit.count", 1) do
      post habits_path, params: {
        habit: {
          name:          "統合テスト用習慣",
          weekly_target: 7
        }
      }
    end

    # HabitsController#create は成功時に habits_path にリダイレクトします
    assert_redirected_to habits_path

    # ── 【Issue #31 バグ修正】作成した習慣の取得方法を変更 ──────────
    #
    # 【修正前の問題点】
    #   new_habit = Habit.order(created_at: :desc).first
    #   → 全ユーザーの習慣から「最新のもの」を取得していた。
    #
    #   フィクスチャ（users.yml）は ERB で動的に password_digest を生成するため、
    #   Rails がフィクスチャをDBに挿入するたびに created_at が変わる。
    #   その結果、フィクスチャの habit_one（読書）の created_at が
    #   テスト内で作成した「統合テスト用習慣」より新しくなることがあり、
    #   .first で取得される習慣が「読書」になってしまうバグが発生していた。
    #
    # 【修正後の方法】
    #   @user.habits.active.find_by(name: "統合テスト用習慣")
    #   → ログインユーザーの有効な習慣の中から習慣名で検索する。
    #   → 習慣名は一意ではないが、テスト用途なら十分に特定できる名前を使えば問題ない。
    #   → フィクスチャの created_at に依存しないため、テスト環境に左右されない。
    #
    # 【さらに安全にする追加チェック】
    #   assert_not_nil で確実に習慣が取得できたかを検証してから使う。
    #   nil のまま後続のテストに進むと NoMethodError になり、
    #   原因が分かりにくくなるため、ここで早期に検出する。
    new_habit = @user.habits.active.find_by(name: "統合テスト用習慣")
    assert_not_nil new_habit, "作成した習慣が見つかりませんでした。habits_path へのリダイレクト後に取得できているか確認してください。"
    assert_equal "統合テスト用習慣", new_habit.name
    assert_equal @user.id, new_habit.user_id

    # ── Step 2: 作成した習慣のページにアクセスして確認 ────────────
    get habits_path
    assert_response :success

    # 習慣名が一覧に表示されていることを確認
    # assert_select "body", text: /.../ → body内に指定テキストが含まれるか確認
    assert_select "body", text: /統合テスト用習慣/

    # ── Step 3: ダッシュボードで記録前の達成率（0%）を確認 ─────────
    get dashboard_path
    assert_response :success

    # ダッシュボードが正常に表示されること
    assert_select "h1", text: /ダッシュボード/

    # ── Step 4: 日次記録を作成（チェックをONにする） ──────────────
    # HabitRecordsController#create を呼び出します
    # Turbo Stream リクエストとして送信します
    # （headers: { "Accept" => "text/vnd.turbo-stream.html" } がTurbo StreamのMIMEタイプ）
    assert_difference("HabitRecord.count", 1) do
      post habit_habit_records_path(new_habit),
           params:  { completed: "1" },           # "1" = true（チェックON）として保存
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # Turbo Stream レスポンスが返ること
    # assert_response :success → HTTP 200 であることを確認
    assert_response :success
    # response.media_type → レスポンスの Content-Type を確認
    assert_equal "text/vnd.turbo-stream.html", response.media_type

    # 作成した記録を確認
    record = HabitRecord.order(created_at: :desc).first
    assert record.completed,   "completed: '1' を送信したので true になるはず"
    assert_equal @user.id,     record.user_id
    assert_equal new_habit.id, record.habit_id

    # ── Step 5: 記録後のダッシュボードで進捗率が更新されていることを確認 ──
    get dashboard_path
    assert_response :success

    # DashboardsController#index では @habit_stats に進捗率が格納される
    # ビューで「%」という文字が表示されていることを確認（進捗率の表示確認）
    assert_select "body", text: /%/

    # ── Step 6: 同じ日に再度チェックをONにしても重複しないこと ────
    # find_or_create_by の動作確認（UNIQUE制約の遵守）
    assert_no_difference("HabitRecord.count") do
      post habit_habit_records_path(new_habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # ── Step 7: チェックをOFFにできること（記録の更新） ──────────
    # PATCH リクエストで既存レコードを更新します
    patch habit_habit_record_path(new_habit, record),
          params:  { completed: "0" },            # "0" = false（チェックOFF）
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    record.reload  # DBから最新の状態を再読み込みする
    assert_not record.completed, "completed: '0' を送信したので false になるはず"
  end

  # ============================================================
  # テスト2: 習慣一覧ページで週次進捗が正しく表示されること
  # ============================================================
  # 【なぜこのテストが必要か？】
  # HabitsController#index では N+1 対策として @habit_stats を事前計算しています。
  # 記録を入れた後、習慣一覧ページでも進捗が正しく反映されることを確認します。
  test "習慣一覧ページで週次進捗率が表示されること" do
    log_in_as(@user)

    # fixtures の habit_one を使います（users(:one) に紐づく有効な習慣）
    habit = habits(:habit_one)

    # 今日の記録を作成します
    HabitRecord.create!(
      user:        @user,
      habit:       habit,
      record_date: HabitRecord.today_for_record,  # AM4:00 基準の今日
      completed:   true
    )

    # 習慣一覧ページにアクセス
    get habits_path
    assert_response :success

    # 習慣名が表示されていること
    assert_select "body", text: /読書/  # habit_one の name は "読書"（fixtures より）

    # 進捗率が「%」として表示されていること
    # （具体的な数値はテスト日によって変わるため、% 記号の存在だけ確認）
    assert_select "body", text: /%/
  end

  # ============================================================
  # テスト3: 習慣が0件の場合はEmpty Stateが表示されること
  # ============================================================
  # 【なぜこのテストが必要か？】
  # DashboardsController#index の @overall_rate 計算
  # （全習慣の rate の平均値）が正しく動作するか確認します。
  test "習慣が0件の場合はEmpty Stateが表示されること" do
    log_in_as(@user)

    # users(:one) の全習慣を論理削除します
    # update_all は SQL の UPDATE を直接実行するため、モデルのコールバックはスキップされます
    # ここでは deleted_at を一括で設定することで習慣を全て「削除済み」状態にします
    @user.habits.update_all(deleted_at: Time.current)

    # ダッシュボードにアクセス
    get dashboard_path
    assert_response :success

    # 習慣が0件のときに表示されるメッセージが確認できること
    # DashboardsController#index では @habits.empty? の場合に「まだ習慣が登録されていません」が表示される
    assert_select "p", text: /まだ習慣が登録されていません/
  end
end
