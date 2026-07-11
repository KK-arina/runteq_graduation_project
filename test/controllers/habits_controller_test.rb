# test/controllers/habits_controller_test.rb
#
# 【このファイルの役割】
# HabitsController のコントローラーテスト。
#
# 【修正理由】
# Rails 6以降、assigns メソッドは rails-controller-testing gem に切り出された。
# gem を追加しなくても済むよう、テストの検証方法を変更した。
#
# 変更前: assigns(:habit_stats) でコントローラーの変数を直接確認
# 変更後: レスポンスのHTMLやステータスコードで動作を検証
#
# 【コントローラーテストの考え方】
# コントローラーテストでは「ユーザーがアクセスしたとき何が起きるか」を確認する。
# 具体的には:
#   ① 正しいHTTPステータスコードが返るか
#   ② 正しいページにリダイレクトされるか
#   ③ 画面に期待するコンテンツが表示されるか
# 内部変数の中身は「モデルテスト」で確認するのが Rails の慣習。

require "test_helper"

class HabitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # fixtures からテスト用ユーザーを取得する
    @user = users(:one)

    # ログイン状態を作る
    # post login_path でセッションを確立し、以降のリクエストにログイン状態を引き継ぐ
    post login_path, params: { session: { email: @user.email, password: "password" } }
  end

  # ============================================================
  # GET /habits のテスト
  # ============================================================

  test "習慣一覧ページが正常に表示されること" do
    get habits_path

    # assert_response :success → HTTP 200 が返ることを確認
    assert_response :success
  end

  test "習慣がある場合に習慣名が表示されること" do
    get habits_path
    assert_response :success

    # 【修正理由】
    # assert_select "h3", text: /習慣/ は「h3のテキストが /習慣/ にマッチする」検証ですが、
    # fixtures の習慣名は「読書」のため「習慣」という文字を含まず失敗していました。
    # fixtures に実際に登録されている習慣名で検証します。
    assert_select "h3", text: /読書/
  end

  test "習慣がある場合に進捗バーが表示されること" do
    @user.habits.create!(name: "進捗バーテスト習慣", weekly_target: 3)

    get habits_path

    # assert_response :success で200が返ることを確認
    # 進捗バーのHTML要素（プログレスバーを含むdiv）が存在するか確認
    assert_response :success

    # レスポンスのHTML本文に「今週の進捗」というテキストが含まれているか確認
    # assert_match(期待する文字列またはRegex, 検索対象の文字列)
    assert_match "今週の進捗", response.body,
                 "「今週の進捗」テキストがページに表示されていません"
  end

  test "習慣がある場合に完了日数の表示形式（n/m日）が含まれること" do
    get habits_path
    assert_response :success

    # 【修正理由】
    # fixtures の習慣は weekly_target: 7 のため「0/5日」は存在しません。
    # また fixtures にはすでに今週の記録が1件存在するため「1/7日」と表示されます。
    # fixtures の実際の状態に合わせてテストを書き直しています。
    #
    # assert_match を使う理由:
    #   ビューの span 内テキストは改行を含むため assert_select では一致しません。
    #   response.body（HTML全体の文字列）から検索する assert_match を使います。
    assert_match(/\d+\/7日/, response.body)
  end

  test "習慣の記録がある場合に完了日数が正しく表示されること" do
    # 【修正理由】
    #   current_week_range は week_start..today_for_record の範囲で集計する。
    #   今日が月曜の場合、週の範囲が「月曜1日分」のため
    #   月曜・火曜に作成した2件のうち月曜分しかカウントされず
    #   「1/7日」と表示されてしまう。
    #   travel_to で水曜以降に固定することで「2/7日」が確実に表示される。
    travel_to Time.zone.parse("2025-01-15 10:00:00") do  # 2025-01-15 = 水曜日
      habit = habits(:habit_one)
      today = HabitRecord.today_for_record
      week_start = today.beginning_of_week(:monday)

      HabitRecord.where(
        user: @user,
        habit: habit,
        record_date: week_start..week_start + 6.days
      ).delete_all

      HabitRecord.create!(user: @user, habit: habit, record_date: week_start,         completed: true)
      HabitRecord.create!(user: @user, habit: habit, record_date: week_start + 1.day, completed: true)

      get habits_path
      assert_response :success

      assert_match(/2\/7日/, response.body)
    end
  end

  test "習慣が0件のとき Empty State が表示されること" do
    # このユーザーの習慣をすべて論理削除して0件にする
    @user.habits.active.each(&:soft_delete)

    get habits_path

    assert_response :success
    # 「まだ習慣が登録されていません」というテキストが含まれるか確認
    assert_match "まだ習慣が登録されていません", response.body,
                 "Empty State のテキストが表示されていません"
  end

  test "ログインしていない場合はログインページにリダイレクトされること" do
    # ログアウトしてセッションを破棄する
    delete logout_path

    get habits_path

    # assert_redirected_to → 指定URLへリダイレクトされることを確認
    assert_redirected_to %r{/login}
  end

  # ============================================================
  # H-9: 習慣一覧で habit_excluded_days への追加SELECTが発生しないこと（N+1 回帰テスト）
  # ============================================================
  #
  # 【このテストの狙い】
  #   Habit#excluded_day_numbers を .pluck → .map に変更したことで、
  #   habits#index（includes(:habit_excluded_days) 済み）を表示しても
  #   除外日テーブルへの追加 SELECT が発生しない（preload 済み配列を使う）ことを、
  #   実際に発行された SQL を数えて決定論的に検証する。
  #
  # 【なぜ bullet を test 環境全体で raise させないのか】
  #   Bullet.raise を test 全体で有効化すると、H-9 と無関係の既存ページに
  #   潜在的な N+1 があった場合にも別テストが巻き込まれて落ちるリスクがある。
  #   スコープを本 ISSUE に限定し redo を避けるため、
  #   /habits に限定した「クエリ数カウント」で検証する。
  #
  # 【検証ロジック】
  #   includes(:habit_excluded_days) の preload は 1 回だけ SELECT を発行する。
  #   修正後（.map）は各カードが preload 済み配列を読むため追加 SELECT は 0 件
  #   → habit_excluded_days への SELECT 合計は「1 回以下」になる。
  #   修正前（.pluck）なら習慣数だけ SELECT が飛び、この assert は失敗する。
  test "H-9: 習慣一覧で habit_excluded_days への追加SELECTが発生しない（N+1回帰）" do
    travel_to Time.zone.local(2026, 6, 24, 10, 0, 0) do
      # 除外日を持つ習慣を複数作成する（N+1 が起きうる状況を作る）
      3.times do |i|
        habit = @user.habits.create!(
          name:             "N+1テスト習慣#{i + 1}",
          measurement_type: :check_type,
          weekly_target:    5
        )
        habit.habit_excluded_days.create!(day_of_week: 0) # 日曜を除外
        habit.habit_excluded_days.create!(day_of_week: 6) # 土曜を除外
      end

      # habit_excluded_days への実 SELECT（キャッシュ・スキーマ照会を除く）を収集する
      excluded_day_selects = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        event   = ActiveSupport::Notifications::Event.new(*args)
        payload = event.payload
        next if payload[:cached]            # クエリキャッシュのヒットは実DBアクセスではない
        next if payload[:name] == "SCHEMA"  # スキーマ照会は対象外
        sql = payload[:sql].to_s
        excluded_day_selects << sql if sql =~ /SELECT.+habit_excluded_days/i
      end

      begin
        get habits_path
        assert_response :success
      ensure
        # 後続テストに影響しないよう必ず購読解除する
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      assert excluded_day_selects.size <= 1,
             "habit_excluded_days への SELECT が #{excluded_day_selects.size} 回発行された（N+1 の疑い）。" \
             "includes(:habit_excluded_days) の preload 済み配列を .map で読むべき。"
    end
  end
end
