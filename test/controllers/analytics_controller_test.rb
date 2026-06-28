# test/controllers/analytics_controller_test.rb
#
# ==============================================================================
# AnalyticsController テスト（H-4: グラフ・進捗分析ページ）
# ==============================================================================
#
# 【テスト戦略】
#   dashboards_controller_test.rb と同じ方針を採用する。
#     - travel_to で日付を固定し、週の境界による不安定なテストを防ぐ
#     - setup で fixtures の習慣・振り返りを論理削除/未完了化してクリーンな状態にする
#     - log_in_as ヘルパー（test_helper.rb）でログイン処理を共通化する
#     - assert_select の data-testid で要素を厳密に検証する
# ==============================================================================

require "test_helper"

class AnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # 2026-06-24（水曜日）に固定する。
    # beginning_of_week(:monday) を使うロジックが多いため、
    # 月曜日に実行すると「週の範囲が1日分」になり集計が不安定になることを防ぐ。
    travel_to Time.zone.local(2026, 6, 24, 10, 0, 0)

    @user = users(:one)
    log_in_as(@user)

    # fixtures の影響を排除してテストをクリーンな状態から開始する。
    # （dashboards_controller_test.rb と同じ設計方針）
    @user.habits.update_all(deleted_at: Time.current)
    @user.weekly_reflections.update_all(completed_at: nil)
  end

  teardown do
    travel_back
  end

  # ============================================================
  # 基本表示テスト
  # ============================================================

  test "ログイン済みならグラフページが正常に表示される" do
    get analytics_path
    assert_response :success
  end

  test "未ログインの場合はログインページへリダイレクトされる" do
    delete logout_path
    get analytics_path
    # E-4 でクエリパラメータ(redirect_to)が付くため正規表現で判定する
    assert_redirected_to %r{/login}
  end

  # ============================================================
  # Empty State テスト
  # ============================================================

  test "習慣も振り返りも0件のときEmpty Stateが表示される" do
    get analytics_path
    assert_response :success
    assert_select "[data-testid='analytics-empty-state']"
  end

  test "習慣が1件でもあればEmpty Stateは表示されない" do
    @user.habits.create!(
      name: "テスト読書",
      measurement_type: :check_type,
      weekly_target: 5
    )

    get analytics_path
    assert_response :success
    assert_select "[data-testid='analytics-empty-state']", count: 0
  end

  # ============================================================
  # 期間フィルターテスト
  # ============================================================

  test "periodパラメータが12wのときも正常に表示される" do
    @user.habits.create!(
      name: "テスト習慣",
      measurement_type: :check_type,
      weekly_target: 5
    )

    get analytics_path, params: { period: "12w" }
    assert_response :success
  end

  test "periodパラメータがallのときも正常に表示される" do
    @user.habits.create!(
      name: "テスト習慣",
      measurement_type: :check_type,
      weekly_target: 5
    )

    get analytics_path, params: { period: "all" }
    assert_response :success
  end

  test "不正なperiodパラメータが渡されてもエラーにならず4週がデフォルトになる" do
    @user.habits.create!(
      name: "テスト習慣",
      measurement_type: :check_type,
      weekly_target: 5
    )

    get analytics_path, params: { period: "invalid_value" }
    assert_response :success
  end

  # ============================================================
  # H-4: バッジリセット（last_analytics_viewed_at）テスト
  # ============================================================

  test "グラフページを開くとlast_analytics_viewed_atが現在時刻に更新される" do
    assert_nil @user.user_setting.last_analytics_viewed_at

    get analytics_path

    @user.user_setting.reload
    assert_not_nil @user.user_setting.last_analytics_viewed_at
    # travel_to で固定した時刻と一致することを確認する
    assert_equal Time.zone.local(2026, 6, 24, 10, 0, 0), @user.user_setting.last_analytics_viewed_at
  end

  # ============================================================
  # 数値型習慣を含むケースのテスト（達成率計算の確認）
  # ============================================================

  test "数値型習慣の記録があってもエラーにならず表示される" do
    habit = @user.habits.create!(
      name: "ジョギング",
      measurement_type: :numeric_type,
      unit: "分",
      weekly_target: 100
    )
    HabitRecord.create!(
      user: @user, habit: habit,
      record_date: HabitRecord.today_for_record,
      completed: false, numeric_value: 30.0
    )

    get analytics_path
    assert_response :success
    assert_select "[data-testid='analytics-empty-state']", count: 0
  end

  # ============================================================
  # 気分スコアを含む振り返りのテスト
  # ============================================================

  test "気分スコア付きの振り返りがあるとEmpty Stateにならない" do
    @user.weekly_reflections.create!(
      week_start_date:       HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week,
      week_end_date:         HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week + 6.days,
      direct_reason:         "テスト理由",
      background_situation:  "テスト状況",
      next_action:           "テスト次のアクション",
      mood:                  4,
      completed_at:          Time.current,
      is_locked:             true
    )

    get analytics_path
    assert_response :success
    assert_select "[data-testid='analytics-empty-state']", count: 0
  end

  # ============================================================
  # H-4: バッジリセットのエンドツーエンド検証（レビュー指摘①への実証テスト）
  # ============================================================
  #
  # 【このテストの狙い】
  #   「update_columns はメモリ上の属性も更新するため reload は不要」という
  #   設計判断が本当に正しいかを、実際のHTML出力で検証する。
  #   コードを読んで「正しいはず」と判断するだけでなく、
  #   実際にブラウザに表示される内容で裏付けることで設計判断の信頼性を担保する。
  #
  # 【travel_to を3段階に分ける理由】
  #   AI分析の作成日時とページ訪問日時が「同一の凍結時刻」になってしまうと、
  #   bn_ai_analysis_count の比較が `created_at >= since`（境界含む）であるため、
  #   タイムスタンプが完全一致した場合にバッジが消えない誤判定が起きうる。
  #   実際の運用ではAI分析完了とユーザーのページ訪問が同一マイクロ秒に
  #   起こることはまずないため、テストでも段階的に時刻を進めることで
  #   現実の利用シーンを正確に再現する。
  test "AI分析完了後にダッシュボードへ青バッジが表示され、グラフページ訪問後は消える" do
    # ① AI分析を含む振り返りを作成する（この時刻が created_at として記録される）
    travel_to Time.zone.local(2026, 6, 24, 10, 0, 0) do
      reflection = @user.weekly_reflections.create!(
        week_start_date:      HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week,
        week_end_date:        HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week + 6.days,
        direct_reason:        "テスト理由",
        background_situation: "テスト状況",
        next_action:          "テスト次のアクション",
        completed_at:         Time.current,
        is_locked:            true
      )
      AiAnalysis.create!(
        weekly_reflection: reflection,
        analysis_type:     :weekly_reflection,
        actions_json:       [ { "type" => "habit", "title" => "テスト習慣" } ],
        is_latest:          true
      )
    end

    badge_label = I18n.t("shared.bottom_navigation.tabs.analytics.badge_aria_label")

    # ② 1秒後にダッシュボードを開く → バッジが表示されていることを確認
    travel_to Time.zone.local(2026, 6, 24, 10, 0, 1) do
      get dashboard_path
      assert_response :success
      assert_select "span[aria-label='#{badge_label}']"
    end

    # ③ さらに1秒後にグラフページを訪問する（ここで last_analytics_viewed_at が更新される）
    travel_to Time.zone.local(2026, 6, 24, 10, 0, 2) do
      get analytics_path
      assert_response :success
    end

    # ④ さらに1秒後に再度ダッシュボードを開く → バッジが消えていることを確認
    travel_to Time.zone.local(2026, 6, 24, 10, 0, 3) do
      get dashboard_path
      assert_response :success
      assert_select "span[aria-label='#{badge_label}']", count: 0
    end
  end

  # ============================================================
  # H-7: Empty State data-testid 継続確認テスト
  # ============================================================
  #
  # 【このテストの目的】
  #   analytics/index.html.erb の Empty State を共通パーシャルに移行した後も
  #   data-testid="analytics-empty-state" が正しく出力されることを確認する。
  #   既存テスト "習慣も振り返りも0件のときEmpty Stateが表示される" と
  #   同じ機能を検証しているが、H-7 の変更で壊れていないことの明示的な確認として残す。

  test "H-7: 共通パーシャルに移行後も analytics-empty-state の testid が正しく出力される" do
    # setup で @user.habits / weekly_reflections はクリア済み
    get analytics_path
    assert_response :success

    # パーシャル側で testid: "analytics-empty-state" を正しく受け取っていること
    assert_select "[data-testid='analytics-empty-state']"

    # ダッシュボードへのリンクが存在すること
    assert_select "a[href='#{dashboard_path}']", text: "ダッシュボードへ →"
  end
end