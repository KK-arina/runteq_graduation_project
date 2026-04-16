# test/controllers/dashboards_controller_test.rb
#
# ==============================================================================
# DashboardsController テスト（C-6: タスク優先度別達成率を追加）
# ==============================================================================
# 【テスト戦略】
#   ビューに表示される HTML を assert_select で検証する（Rails 7 対応）。
#   assigns は rails-controller-testing gem なしでは使えないため使用しない。
#
# 【fixtures の扱い】
#   tasks.yml に ai_generated_task（user: one）が存在するため、
#   各テストの冒頭で @user.tasks.update_all(deleted_at: Time.current) を呼び
#   fixtures タスクを論理削除してからテスト用データを作成する。
#   これにより fixtures の影響を受けずに集計結果を制御できる。
#
# 【assert_select のセレクタ指定】
#   "span" だけではページ全体の全 span にマッチしてしまい
#   ユーザー名など無関係な要素も検索対象になる。
#   data-testid 属性を使って「テスト用の識別子」を HTML に埋め込み、
#   "[data-testid='priority-badge-must']" のように具体的に絞り込む。
#
# 【ログイン成功の保証】
#   post login_path だけではログイン失敗してもテストが落ちない可能性がある。
#   assert_redirected_to dashboard_path でリダイレクト先を確認し、
#   follow_redirect! で実際にダッシュボードページへ遷移してから
#   ログイン済み状態であることを保証する。
# ==============================================================================

require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テスト前に実行する共通処理
  # ============================================================
  # travel_to で日付を水曜日に固定する。
  # 理由:
  #   beginning_of_week(:monday) が使われているため、
  #   月曜日に実行すると週の範囲が1日分になり
  #   データが集計されないバグが起きやすい。
  #   水曜日に固定することで「月〜水」の3日分の範囲が確保される。
  setup do
    # 2026-04-15（水曜日）に固定する
    travel_to Time.zone.local(2026, 4, 15, 10, 0, 0)

    @user = users(:one)

    # ログイン処理
    # post だけではログイン失敗してもテストが続行してしまう場合がある。
    # assert_redirected_to でログイン成功後のリダイレクト先を確認し、
    # follow_redirect! でダッシュボードページへ実際に遷移することで
    # 「ログイン済み状態」を確実に保証する。
    post login_path, params: { session: { email: @user.email, password: "password" } }
    assert_redirected_to dashboard_path
    follow_redirect!

    # fixtures のタスク（ai_generated_task など）を論理削除して
    # 各テストがクリーンな状態から始められるようにする。
    # update_all はコールバックを起こさず1クエリで完了するため高速。
    @user.tasks.update_all(deleted_at: Time.current)
  end

  # teardown で travel_to を必ず元に戻す。
  # 戻し忘れると他のテストの時刻が汚染される。
  teardown do
    travel_back
  end

  # ============================================================
  # 基本表示テスト
  # ============================================================

  test "ダッシュボードが正常に表示される" do
    get dashboard_path
    assert_response :success
  end

  # ============================================================
  # C-6: タスク優先度別達成率のビュー検証テスト
  # ============================================================

  test "タスクが0件のとき達成率セクション全体が非表示になる" do
    # setup で全タスクを論理削除済み → 追加作成しない

    get dashboard_path
    assert_response :success

    # total が全て 0 のため「今週のタスク達成率」セクションが非表示になること。
    # data-testid="task-priority-stats-section" で絞り込む。
    assert_select "[data-testid='task-priority-stats-section']", count: 0
  end

  test "Must タスクが3件あり2件完了の場合に Must バッジと 66% が表示される" do
    today = HabitRecord.today_for_record

    must_tasks = 3.times.map do |i|
      @user.tasks.create!(
        title:    "Mustタスク#{i + 1}",
        priority: :must,
        status:   :todo,
        due_date: today
      )
    end

    must_tasks[0].update!(status: :done, completed_at: Time.current)
    must_tasks[1].update!(status: :done, completed_at: Time.current)

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='task-priority-stats-section']"
    assert_select "[data-testid='priority-badge-must']", text: "Must"
    assert_select "[data-testid='priority-count-must']", text: /2\/3件 完了/
    assert_select "[data-testid='priority-rate-must']", text: "66%"
  end

  test "Should タスクが全件完了の場合に 100% と表示される" do
    today = HabitRecord.today_for_record

    2.times do |i|
      @user.tasks.create!(
        title:        "Shouldタスク#{i + 1}",
        priority:     :should,
        status:       :done,
        due_date:     today,
        completed_at: Time.current
      )
    end

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='priority-badge-should']", text: "Should"
    assert_select "[data-testid='priority-rate-should']",  text: "100%"
  end

  test "archived タスクも完了として達成率にカウントされる" do
    today = HabitRecord.today_for_record

    # archived タスクを1件作成する（1/1 = 100%）
    @user.tasks.create!(
      title:        "アーカイブ済みタスク",
      priority:     :could,
      status:       :archived,
      due_date:     today,
      completed_at: Time.current
    )

    get dashboard_path
    assert_response :success

    # Could バッジが表示されること
    assert_select "[data-testid='priority-badge-could']", text: "Could"

    # archived を done としてカウントするため 100% になること
    assert_select "[data-testid='priority-rate-could']", text: "100%"
  end

  test "Could タスクが 0 件のとき Could の行が非表示になる" do
    today = HabitRecord.today_for_record

    # Must タスクのみ作成（Could は作らない）
    @user.tasks.create!(
      title:    "Mustのみ",
      priority: :must,
      status:   :todo,
      due_date: today
    )

    get dashboard_path
    assert_response :success

    # Must バッジは表示されること
    assert_select "[data-testid='priority-badge-must']", text: "Must"

    # Could バッジは表示されないこと（total が 0 のため行ごと非表示）
    assert_select "[data-testid='priority-badge-could']", count: 0
  end

  test "Must と Should の両方にタスクがある場合は両方のバッジが表示される" do
    today = HabitRecord.today_for_record

    @user.tasks.create!(
      title:    "Must1",
      priority: :must,
      status:   :todo,
      due_date: today
    )
    @user.tasks.create!(
      title:        "Should1",
      priority:     :should,
      status:       :done,
      due_date:     today,
      completed_at: Time.current
    )

    get dashboard_path
    assert_response :success

    assert_select "[data-testid='priority-badge-must']",   text: "Must"
    assert_select "[data-testid='priority-badge-should']", text: "Should"
  end

  test "今週の範囲外（先週）のタスクは達成率に含まれない" do
    # 先週の due_date を持つタスクを作成する
    last_week_date = HabitRecord.today_for_record - 8.days

    task = @user.tasks.create!(
      title:    "先週のタスク",
      priority: :must,
      status:   :done,
      due_date: last_week_date
    )

    # created_at も先週に設定する。
    # Task.create! は travel_to の時刻（今週）で created_at を設定するため、
    # created_at が今週の BETWEEN 条件にヒットしてしまう。
    # update_columns はバリデーション・コールバックをスキップして
    # 直接カラムを書き換えるため、タイムスタンプを任意の値に設定できる。
    task.update_columns(
      created_at: last_week_date.in_time_zone.beginning_of_day,
      updated_at: last_week_date.in_time_zone.beginning_of_day
    )

    get dashboard_path
    assert_response :success

    # due_date も created_at も先週 → 集計対象が 0件 → セクション非表示
    assert_select "[data-testid='task-priority-stats-section']", count: 0
  end
end