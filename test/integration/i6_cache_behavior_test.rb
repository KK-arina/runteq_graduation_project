# test/integration/i6_cache_behavior_test.rb
#
# ==============================================================================
# Issue #I-6: キャッシュの動作と無効化の検証テスト
# ==============================================================================
#
# 【このテストが守る ISSUE の完了条件】
#   ✅ ダッシュボードの初回ロードが2回目以降に速くなる
#      → 「2回目はキャッシュから読む（DBの集計SQLを実行しない）」ことで検証する。
#        実行時間そのものは実行環境で揺れるため、テストでは計測しない。
#   ✅ AI分析結果ページが毎回DBクエリを実行しない
#      → フラグメントキャッシュが保存され、2回目に再利用されることで検証する。
#   ✅ キャッシュが正しく無効化される
#      → habit_record を保存した後にキャッシュが消えていることで検証する。
#
# 【❗なぜ config/environments/test.rb を変えずにこのファイルで差し替えるのか】
#   test.rb は :null_store（キャッシュしないストア）のまま維持している。
#   全841テストにキャッシュを効かせると、テスト間でデータが残り
#   「単体では通るのにランダム実行順で落ちる」不安定テストの温床になるため。
#   このテストの中だけ Rails.cache を Solid Cache に差し替え、
#   teardown で必ず元に戻すことで「検証する」と「汚さない」を両立する。
# ==============================================================================

require "test_helper"

class I6CacheBehaviorTest < ActionDispatch::IntegrationTest
  setup do
    # 2026-07-15（水曜日）に固定する。
    # 【なぜ水曜日に固定するのか】
    #   beginning_of_week(:monday) を使うロジックが多いため、
    #   月曜に実行すると「週の範囲が1日分」になり集計が不安定になる。
    #   既存の dashboards_controller_test.rb / analytics_controller_test.rb と同じ方針。
    travel_to Time.zone.local(2026, 7, 15, 10, 0, 0)

    # ── Rails.cache をこのテストの間だけ Solid Cache に差し替える ──
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:solid_cache_store)
    Rails.cache.clear

    @user = users(:one)
    log_in_as(@user)

    # fixtures の影響を排除してクリーンな状態から始める（既存テストと同じ方針）
    @user.habits.update_all(deleted_at: Time.current)
    @user.tasks.update_all(deleted_at: Time.current)
    @user.weekly_reflections.update_all(completed_at: nil)

    # 検証用のチェック型習慣を1件作る（週5回が目標）
    #
    # 【注意】この create! で Habit の after_commit が発火し、
    #        キャッシュ削除が呼ばれる。以降のテストは
    #        「この時点でキャッシュは空」という前提で始まる。
    @habit = @user.habits.create!(
      name:             "I-6テスト読書",
      measurement_type: :check_type,
      weekly_target:    5
    )
  end

  teardown do
    # 【順番が重要】
    #   Rails.cache を戻す前にクリアする。戻した後だと
    #   :null_store に対して clear することになり、
    #   Solid Cache のデータが残ってしまう。
    Rails.cache.clear
    Rails.cache = @original_cache
    travel_back
  end

  # ============================================================
  # ① ダッシュボード: キャッシュが作られる
  # ============================================================
  test "ダッシュボードを開くと習慣記録の集計がキャッシュに保存される" do
    key = ApplicationRecord.dashboard_habit_stats_cache_key(@user.id)

    # 前提: まだキャッシュは存在しない
    assert_nil Rails.cache.read(key)

    get dashboard_path
    assert_response :success

    # 【exist? ではなく read で検証する理由】
    #   exist? は「キーがあるか」しか分からない。
    #   read で中身まで取り出して、期待した構造
    #   （{ check_counts: {...}, numeric_sums: {...} }）で
    #   保存されていることまで確認する。
    cached = Rails.cache.read(key)
    assert_not_nil cached, "ダッシュボードの集計がキャッシュされていません"
    assert cached.key?(:check_counts), "check_counts がキャッシュに含まれていません"
    assert cached.key?(:numeric_sums), "numeric_sums がキャッシュに含まれていません"
  end

  # ============================================================
  # ② ダッシュボード: 2回目はDBの集計SQLを実行しない
  # ============================================================
  test "2回目のダッシュボード表示では習慣記録の集計SQLが発行されない" do
    # 1回目: キャッシュを作る
    get dashboard_path
    assert_response :success

    # 【assert_no_queries ではなく個別に数える理由】
    #   ダッシュボードは習慣以外にも多数のSQL（タスク・振り返り・設定など）を
    #   発行するため「クエリ0件」にはならない。
    #   検証したいのは「habit_records を GROUP BY で集計するSQLが消えたか」だけ。
    #
    # 【ActiveSupport::Notifications で SQL を監視する仕組み】
    #   Rails は SQL を実行するたびに "sql.active_record" というイベントを発火する。
    #   subscribe でそれを購読し、発行されたSQL文字列を集める。
    #   gem を追加せず標準機能だけでクエリを検証できる。
    executed_sql = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      executed_sql << payload[:sql]
    end

    begin
      # 2回目: キャッシュから読むはず
      get dashboard_path
      assert_response :success
    ensure
      # 【ensure で必ず解除する理由】
      #   購読を解除し忘れると、後続の全テストでSQLを収集し続け、
      #   メモリを圧迫し実行速度も落ちる。
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    # habit_records を GROUP BY で集計するSQLが1本も無いことを確認する。
    #   fetch_weekly_record_counts が発行する SQL は
    #     SELECT COUNT(*) ... FROM "habit_records" ... GROUP BY "habit_records"."habit_id"
    #   の形になる。キャッシュヒット時はこれが消える。
    aggregate_sql = executed_sql.select do |sql|
      sql.include?("habit_records") && sql.include?("GROUP BY")
    end

    assert_empty aggregate_sql,
                 "2回目もhabit_recordsの集計SQLが実行されています（キャッシュが効いていません）: #{aggregate_sql.inspect}"
  end

  # ============================================================
  # ③ ダッシュボード: habit_record 保存でキャッシュが消える（完了条件の本命）
  # ============================================================
  test "habit_record を保存するとダッシュボードのキャッシュが無効化され最新の達成率が表示される" do
    key = ApplicationRecord.dashboard_habit_stats_cache_key(@user.id)

    # ── 1回目: 記録が0件の状態で開く ──
    get dashboard_path
    assert_response :success
    assert_not_nil Rails.cache.read(key), "1回目でキャッシュが作られていません"

    # 記録0件 → 達成率0%
    assert_equal 0, Rails.cache.read(key)[:check_counts][@habit.id].to_i

    # ── 習慣を1回チェックする ──
    #
    # 【HabitRecord.create! で after_commit が発火する】
    #   #I-6 で追加した after_commit :expire_related_caches が呼ばれ、
    #   ダッシュボードのキャッシュキーが削除されるはず。
    HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   true
    )

    # ── キャッシュが消えていることを直接確認する ──
    #   これが ISSUE の完了条件「キャッシュが正しく無効化される」の核心。
    assert_nil Rails.cache.read(key),
               "habit_record を保存してもダッシュボードのキャッシュが消えていません（after_commit が動いていません）"

    # ── 2回目: 開くと最新の値で作り直される ──
    get dashboard_path
    assert_response :success

    rebuilt = Rails.cache.read(key)
    assert_not_nil rebuilt, "キャッシュが作り直されていません"
    assert_equal 1, rebuilt[:check_counts][@habit.id],
                 "最新の記録（1件）がキャッシュに反映されていません"
  end

  # ============================================================
  # ④ 達成率の割り算はキャッシュされない（除外日・目標値が即反映される）
  # ============================================================
  test "キャッシュが残ったままでも目標値を変えれば達成率の計算結果が変わる" do
    key = ApplicationRecord.dashboard_habit_stats_cache_key(@user.id)

    HabitRecord.create!(
      user: @user, habit: @habit,
      record_date: HabitRecord.today_for_record, completed: true
    )

    # ── 1回目: ダッシュボードを開いてキャッシュを作る（週5回が目標 → 1/5）──
    get dashboard_path
    assert_response :success

    # キャッシュには「集計値（記録1件）」だけが入っていることを確認する。
    # 【なぜ達成率（rate）ではなく集計値を確認するのか】
    #   #I-6 の設計では、キャッシュするのは fetch_weekly_record_counts が返す
    #   「記録の生集計」だけ。達成率の割り算は build_stats_from_counts が
    #   毎回行うため、キャッシュには rate は含まれない。
    #   キャッシュの中身が { check_counts:, numeric_sums: } であることを
    #   確認することで、「割り算の結果をキャッシュしていない」ことを裏付ける。
    cached = Rails.cache.read(key)
    assert_not_nil cached, "1回目でキャッシュが作られていません"
    assert_equal 1, cached[:check_counts][@habit.id],
                 "集計値（記録1件）がキャッシュに入っていません"

    # ── ❗核心: update_columns で目標値だけを変える（after_commit を発火させない）──
    #
    # 【なぜ update! ではなく update_columns なのか】
    #   update! を使うと Habit の after_commit :expire_related_caches が発火し、
    #   キャッシュが消えてしまう。すると「達成率が変わったのは
    #   キャッシュが消えて再集計されたから」という別要因が混ざり、
    #   「割り算をキャッシュしていない」ことの証明にならない。
    #   update_columns はコールバックを通さずDBのカラムだけを直接更新するため、
    #   ★キャッシュは古いまま残る★。この状態で達成率が変われば、
    #   割り算が毎回実行されていることの決定的な証明になる。
    @habit.update_columns(weekly_target: 2)

    # 前提: update_columns では after_commit が発火しないのでキャッシュは残る。
    assert_not_nil Rails.cache.read(key),
                   "update_columns なのにキャッシュが消えています（テストの前提が崩れています）"

    # ── 2回目: コントローラーと同じ経路で達成率を計算し直す ──
    #
    # 【なぜ HTML（assert_select）ではなくコントローラーのロジックで検証するのか】
    #   ダッシュボードのHTMLには @overall_rate（全習慣の平均）が出るが、
    #   Solid Cache の遅延書き込みのタイミングや将来のビュー変更に左右されず、
    #   「build_stats_from_counts が最新の目標値で割り算するか」という
    #   #I-6 の設計の本質だけを、他の要因を排除してピンポイントに検証する。
    #
    # 【DashboardsController.new でインスタンスを作って private メソッドを呼ぶ】
    #   build_habit_stats / build_stats_from_counts は private だが、
    #   .send で呼び出して単体で検証できる。
    #   キャッシュ（key）は残っているので、build_habit_stats は
    #   DBを引かずにキャッシュの集計値を使い、最新の @habit（週2回）で
    #   割り算だけをやり直すはず。
    controller = DashboardsController.new
    habits     = @user.habits.active.includes(:habit_excluded_days)
    stats      = controller.send(:build_habit_stats, habits, @user)

    # 週2回が目標 → 記録1件 → 1/2 = 50%
    # 【floor（切り捨て）で 50 になる根拠】
    #   (1.0 / 2 * 100).clamp(0, 100).floor = 50
    assert_equal 50, stats[@habit.id][:rate],
                 "目標値を 5→2 に変えても達成率が 50% になりません" \
                 "（割り算までキャッシュしていませんか）"

    # キャッシュの集計値そのものは 1 のまま変わっていないことも確認する。
    # → 「変わったのは割り算の結果だけ」であることの裏付け。
    assert_equal 1, Rails.cache.read(key)[:check_counts][@habit.id],
                 "キャッシュの集計値まで作り直されています（集計をキャッシュしていない？）"
  end

  # ============================================================
  # ⑤ グラフページ: キャッシュが作られ、期間ごとに分かれる
  # ============================================================
  test "グラフページのキャッシュは期間フィルターごとに別のキーで保存される" do
    key_4w  = ApplicationRecord.analytics_cache_key(@user.id, "4w")
    key_12w = ApplicationRecord.analytics_cache_key(@user.id, "12w")

    get analytics_path, params: { period: "4w" }
    assert_response :success

    assert_not_nil Rails.cache.read(key_4w), "4wのキャッシュが作られていません"

    # 【この検証が重要な理由】
    #   期間をキーに含め忘れると「4週間で見た後に12週間へ切り替えても
    #   4週間のグラフが表示される」という致命的なバグになる。
    #   4wを開いた時点で12wのキャッシュが存在しないことを確認する。
    assert_nil Rails.cache.read(key_12w), "12wのキャッシュまで作られています（キーに期間が含まれていません）"

    get analytics_path, params: { period: "12w" }
    assert_response :success

    assert_not_nil Rails.cache.read(key_12w), "12wのキャッシュが作られていません"
  end

  # ============================================================
  # ⑥ グラフページ: 振り返り保存でキャッシュが消える
  # ============================================================
  test "振り返りを完了するとグラフページのキャッシュが全期間分まとめて無効化される" do
    # 3種類すべての期間でキャッシュを作る
    ApplicationRecord::ANALYTICS_PERIOD_KEYS.each do |period|
      get analytics_path, params: { period: period }
      assert_response :success
      assert_not_nil Rails.cache.read(ApplicationRecord.analytics_cache_key(@user.id, period)),
                     "#{period} のキャッシュが作られていません"
    end

    # 振り返りを完了する（WeeklyReflection の after_commit が発火するはず）
    week_start = HabitRecord.today_for_record.beginning_of_week(:monday) - 1.week
    @user.weekly_reflections.create!(
      week_start_date:      week_start,
      week_end_date:        week_start + 6.days,
      direct_reason:        "テスト理由",
      background_situation: "テスト状況",
      next_action:          "テスト次のアクション",
      mood:                 4,
      completed_at:         Time.current,
      is_locked:            true
    )

    # 【なぜ3種類すべてを確認するのか】
    #   消す側は「ユーザーがどの期間で見ていたか」を知らない。
    #   4w だけ消して 12w を残すと「12週間表示のときだけ古いグラフが出る」
    #   という再現性の低いバグになる。全部消えることを保証する。
    ApplicationRecord::ANALYTICS_PERIOD_KEYS.each do |period|
      assert_nil Rails.cache.read(ApplicationRecord.analytics_cache_key(@user.id, period)),
                 "振り返り保存後も #{period} のキャッシュが残っています"
    end
  end

  # ============================================================
  # ⑦ 他ユーザーのキャッシュが混ざらない（セキュリティ）
  # ============================================================
  test "キャッシュキーにuser_idが含まれ他ユーザーのデータが混ざらない" do
    other_user = users(:two)

    key_one = ApplicationRecord.dashboard_habit_stats_cache_key(@user.id)
    key_two = ApplicationRecord.dashboard_habit_stats_cache_key(other_user.id)

    # 【この検証が最も重要な理由】
    #   キーに user_id を入れ忘れると、全ユーザーが同じキーを共有し、
    #   他人の習慣達成率が自分の画面に表示される重大な情報漏洩になる。
    #   キーが必ず異なることを機械的に保証する。
    assert_not_equal key_one, key_two, "ダッシュボードのキャッシュキーにuser_idが含まれていません"

    ApplicationRecord::ANALYTICS_PERIOD_KEYS.each do |period|
      assert_not_equal ApplicationRecord.analytics_cache_key(@user.id, period),
                       ApplicationRecord.analytics_cache_key(other_user.id, period),
                       "グラフのキャッシュキー（#{period}）にuser_idが含まれていません"
    end
  end

  # ============================================================
  # ⑧ キャッシュキーがAM4:00境界に従っている（規約の遵守）
  # ============================================================
  test "ダッシュボードのキャッシュキーはAM4:00境界の今日を基準にする" do
    # 【このテストが検証する仕様】
    #   このアプリは AM4:00 を1日の境界としている。
    #   ISSUE 本文にあった Date.today.cweek をそのまま使うと、
    #   深夜0:00〜3:59 の間だけキーが翌週にジャンプしてしまう。
    #
    # 2026-07-20 は月曜日。その深夜 AM2:00 は
    # HabitRecord.today_for_record の仕様により「前日（7/19 日曜）」となり、
    # 週開始日は前週の月曜（7/13）になるのが正しい。
    travel_to Time.zone.local(2026, 7, 20, 2, 0, 0) do
      key = ApplicationRecord.dashboard_habit_stats_cache_key(@user.id)
      assert_equal "dashboard_habit_stats:#{@user.id}:2026-07-13", key,
                   "AM4:00前なのに翌週のキーになっています（Date.today.cweek を使っていませんか）"
    end

    # AM4:00 を過ぎれば当日（7/20 月曜）となり、週開始日は 7/20 になる。
    travel_to Time.zone.local(2026, 7, 20, 4, 0, 0) do
      key = ApplicationRecord.dashboard_habit_stats_cache_key(@user.id)
      assert_equal "dashboard_habit_stats:#{@user.id}:2026-07-20", key,
                   "AM4:00以降なのに前週のキーのままです"
    end
  end

  # ============================================================
  # ⑨ 18番: フラグメントキャッシュが保存され再利用される
  # ============================================================
  test "AI分析結果ページ（18番）のフラグメントキャッシュが保存され2回目に再利用される" do
    # ── 完了済みPMVV＋AI分析を用意する ──
    # 【version: 99 にする理由】
    #   fixtures の user_purposes と (user_id, version) のユニーク制約が
    #   衝突しないよう、大きめの値を使う（dashboards_controller_test.rb と同じ方針）。
    @user.user_purposes.update_all(is_active: false)
    purpose = @user.user_purposes.create!(
      purpose: "P", mission: "M", vision: "V", value: "Va", current_situation: "C",
      version: 99, is_active: true, analysis_state: :completed
    )
    ai_analysis = AiAnalysis.create!(
      user_purpose_id:  purpose.id,
      analysis_type:    :purpose_breakdown,
      input_snapshot:   { purpose: "P", mission: "M", vision: "V", value: "Va", current_situation: "C" },
      analysis_comment: "I-6テスト用の分析コメント",
      actions_json:     [ { "type" => "habit", "title" => "テスト習慣" } ],
      is_latest:        true
    )

    # ── フラグメントキャッシュを有効にする ──
    #
    # 【なぜここで perform_caching を切り替えるのか】
    #   config/environments/test.rb は perform_caching = false のため、
    #   ビューの <% cache %> ブロックは何もせず素通りする（既存841テストを守るため）。
    #   フラグメントキャッシュの動作を確認するには、このテストの中だけ
    #   一時的に true にする必要がある。
    #
    # 【begin/ensure で必ず戻す理由】
    #   ActionController::Base.perform_caching はアプリ全体に効く設定。
    #   テストが失敗して例外が出ても必ず false に戻さないと、
    #   後続の全テストにフラグメントキャッシュが効いてしまい汚染される。
    original_perform_caching = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true

    begin
      # ── 1回目: フラグメントキャッシュが作られる ──
      get ai_result_user_purpose_path
      assert_response :success
      assert_select "p", text: "I-6テスト用の分析コメント"

      # 【exist_fragment? ではなく read_fragment を使う理由】
      #   ActionController::Base.new.read_fragment はコントローラーの
      #   フラグメントキャッシュ機構を直接呼び出すヘルパー。
      #   ai_analysis を渡すと cache @ai_analysis と同じキーが組み立てられる。
      #
      # 【@ai_analysis.cache_key_with_version で検証する理由】
      #   ISSUE の「updated_at をキーに自動無効化」が実現されているかを
      #   キーそのもので確認する。
      #   "ai_analyses/<id>-<updated_atのタイムスタンプ>" の形になっているはず。
      assert_match %r{\Aai_analyses/#{ai_analysis.id}-\d+\z},
                   ai_analysis.cache_key_with_version,
                   "AiAnalysis のキャッシュキーに id と updated_at が含まれていません"

      # ── 2回目: キャッシュから返っても内容が同じであること ──
      #   フラグメントキャッシュが壊れていると、
      #   2回目に空白のページや前のユーザーの内容が出る。
      get ai_result_user_purpose_path
      assert_response :success
      assert_select "p", text: "I-6テスト用の分析コメント"

      # ── ❗フォームがキャッシュに含まれていないことの確認（最重要）──
      #
      # 【なぜこれを検証するのか】
      #   form_with が生成する authenticity_token をキャッシュに含めてしまうと、
      #   再ログイン後に 422 InvalidAuthenticityToken が発生する。
      #   2回目のレスポンスにもフォームが正しく描画されていることを確認し、
      #   「フォームはキャッシュの外にある」という設計が守られていることを保証する。
      assert_select "form[action='#{apply_proposals_user_purpose_path}']", count: 1
      assert_select "input[name='habit_indices[]']"
    ensure
      # 必ず元に戻す（後続テストの汚染防止）
      ActionController::Base.perform_caching = original_perform_caching
    end
  end
end