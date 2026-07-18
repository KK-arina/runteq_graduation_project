# app/controllers/dashboards_controller.rb
#
# ==============================================================================
# DashboardsController
# ==============================================================================
# 【変更履歴】
#   B-2: @habits 取得時に includes(:habit_excluded_days) を追加（N+1防止）
#        build_habit_stats のチェック型の分母を effective_weekly_target に変更
#   C-1: @today_tasks（今日が期限のタスク最大5件）を追加
#   C-6: @task_priority_stats（Must/Should/Could 別の週次達成率）を追加
#        今週（月曜〜今日）のタスクを優先度別に集計し、達成率を計算する
#   D-7: @current_purpose / @ai_analysis を追加（PMVV 分析完了バナー用）
# ==============================================================================

class DashboardsController < ApplicationController
  # ログインしていないユーザーはアクセスできないように制限する
  before_action :require_login

  def index
    @today      = HabitRecord.today_for_record
    @week_start = @today.beginning_of_week(:monday)

    # ── 習慣データの取得 ────────────────────────────────────────────────
    # includes(:habit_excluded_days) により、除外日データを一括で読み込む。
    # これがないと habit.effective_weekly_target を呼ぶたびに
    # habit_excluded_days への SELECT が発行される（N+1問題）。
    @habits = current_user.habits.active
                          .includes(:habit_excluded_days)
                          .order(created_at: :desc)

    # 今日の記録をハッシュ化して高速参照できるようにする。
    # index_by(&:habit_id) により { habit_id => HabitRecord } の形になる。
    # ビューで @today_records_hash[habit.id] と O(1) で参照できる。
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    @habit_stats = build_habit_stats(@habits, current_user)

    # 全習慣の達成率の平均を全体達成率として計算する。
    # 習慣が0件のときは 0 を返す（0除算を防ぐ）。
    @overall_rate = @habits.empty? ? 0 :
      (@habit_stats.values.map { |s| s[:rate] }.sum.to_f / @habit_stats.size).round

    @locked = locked?

    # ── C-1: 今日のタスク ────────────────────────────────────────────────
    # 今日が期限（due_date = 今日）のタスクを最大5件取得する。
    # .active       → deleted_at が nil のもの（論理削除されていないもの）。
    # .not_archived → status が archived のものを除く。
    # .today        → due_date が AM4:00基準の「今日」に一致するもの。
    # .order(priority: :asc) → must(0) → should(1) → could(2) の重要度順。
    # .limit(5) → ダッシュボードには最大5件のみ表示する（画面の見やすさのため）。
    @today_tasks = current_user.tasks
                               .active
                               .not_archived
                               .today
                               .order(priority: :asc)
                               .limit(5)

    # ── C-6: Must/Should/Could 別の週次タスク達成率 ──────────────────────
    @task_priority_stats = build_task_priority_stats(current_user)

    # ── D-7: PMVV 分析バナー用データ ──────────────────────────────────────
    #
    # 【役割】
    #   ダッシュボードに PMVV AI分析完了バナーを表示するために
    #   現在有効な UserPurpose と最新の AiAnalysis を取得する。
    #
    # 【UserPurpose.current_for の役割】
    #   current_user に紐づく is_active=true の UserPurpose を1件取得する。
    #   PMVV 未入力またはスキップしたユーザーは nil が返る。
    #
    # 【@current_purpose が nil のとき】
    #   スキップしたユーザーや PMVV 未入力ユーザーは nil のまま。
    #   ビュー側で if @current_purpose のガードが機能するため安全。
    @current_purpose = UserPurpose.current_for(current_user)

    # 【@ai_analysis の取得条件】
    #   user_purpose_id: @current_purpose.id → 現在有効な PMVV に紐づく分析のみ
    #   is_latest: true                      → 最新の分析結果のみ（再分析後の古いものを除外）
    #   analysis_type: :purpose_breakdown    → PMVV分析（週次振り返り分析と区別）
    #
    # 【&. (Safe Navigation Operator) を使う理由】
    #   @current_purpose が nil の場合、.id を呼ぶと NoMethodError になる。
    #   &. を使うと nil の場合は nil を返してエラーを防げる。
    @ai_analysis = if @current_purpose
                     AiAnalysis.where(
                       user_purpose_id: @current_purpose.id,
                       is_latest:       true,
                       analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
                     ).first
                   end
    # ─────────────────────────────────────────────────────────────────────
    #
    # G-4 追加: ダッシュボードで current_user.user_setting を複数回呼ぶ N+1 を防ぐ。
    # ビュー内で current_user.user_setting&.rest_mode_active? を複数回呼んでいるため、
    # コントローラで1回だけ取得してインスタンス変数に格納する。
    # これにより SELECT クエリが1回で済む。
    @user_setting = current_user.user_setting

    # ── H-9 追加: PMVV完了バナーの永続表示判定 ────────────────────────────
    #
    # 【役割】
    #   これまでPMVV完了バナーは Turbo Stream のライブ配信専用で、
    #   リロードすると消えていた。この判定を加えることで、
    #   サーバー描画時にも「未確認の完了バナー」を復元表示できるようにする。
    #   （振り返りバナーが @reflection_ai_analysis で復元表示するのと同じ考え方）
    #
    # 【表示条件（すべて満たすとき true）】
    #   ① @current_purpose が completed?         → 分析が完了している
    #   ② @ai_analysis が存在する                → 表示すべき最新の分析結果がある
    #   ③ crisis_detected? が false              → 危機検出スキップの分析は完了バナーを出さない
    #   ④ 未確認である                            → まだ✖で閉じていない、または閉じた後に再分析された
    #        pmvv_banner_dismissed_at が nil（一度も閉じていない）、または
    #        最新分析の created_at が閉じた日時より新しい（=再分析で新しい結果が来た）
    #
    # 【④の created_at 比較の意味】
    #   ✖ を押すと pmvv_banner_dismissed_at = 現在時刻 になる。
    #   その時点の分析は created_at <= dismissed_at になり非表示。
    #   その後 PMVV を再分析すると新しい分析の created_at > dismissed_at となり再表示される。
    pmvv_banner_dismissed_at = @user_setting&.pmvv_banner_dismissed_at
    @show_pmvv_completion_banner =
      @current_purpose&.completed? &&
      @ai_analysis.present? &&
      !@ai_analysis.crisis_detected? &&
      (pmvv_banner_dismissed_at.nil? || @ai_analysis.created_at > pmvv_banner_dismissed_at)
    # ─────────────────────────────────────────────────────────────────────

    # ── G-9 追加 / H-10 修正: 振り返りAI分析の状態判定（分析中・完了・危機スキップ）──
    #
    # 【H-10 で直している不具合】
    #   D-5（危機介入機能）で危機ワードが検出されると AI分析はスキップされ、
    #   crisis_detected: true / actions_json: nil の「スキップ専用レコード」だけが作られる。
    #   修正前はこのブロックで .where.not(actions_json: nil) を掛けて
    #   「actions_json が nil のレコード」を除外していたため、危機スキップが最新だと
    #   「分析結果が1件も無い＝分析中」と誤解釈され、スピナーバナーが永久表示された。
    #   → 最新レコードを“絞り込まずに”1件取得し、crisis_detected で分岐して解決する。

    # 直近で「完了済み（completed_at あり）」の振り返りを1件取得する。
    # order(completed_at: :desc).first で「一番最近完了した振り返り」を得る。
    @latest_completed_reflection = current_user.weekly_reflections
                                               .completed
                                               .order(completed_at: :desc)
                                               .first

    # その振り返りに紐づく「最新（is_latest: true）」の AI分析レコードを1件だけ取得する。
    #
    # 【なぜ .latest（= where(is_latest: true)）で1件に絞れるのか】
    #   ① AiAnalysis の before_create :deactivate_previous_analyses が、
    #      新しい分析を作る前に同じ振り返りの古い分析を is_latest: false にする。
    #   ② schema.rb の部分ユニークインデックス（weekly_reflection_id かつ is_latest = true）で
    #      「1振り返りにつき is_latest: true は最大1件」がDBレベルで保証されている。
    #   よって .latest.first は「その振り返りの最新分析ちょうど1件（無ければ nil）」になる。
    #   （危機介入レコードが複数あっても、is_latest: true は常に最新の1件だけ）
    latest_reflection_analysis =
      @latest_completed_reflection&.ai_analyses&.latest&.first

    # ① 危機介入によって分析がスキップされたか？（レビュー指摘①: present? を明示）
    #
    # 【present? && crisis_detected? という書き方にした理由】
    #   latest_reflection_analysis&.crisis_detected? || false でも動くが、
    #   「&.（safe navigation）」と「|| false」が混ざると初心者には読みにくい。
    #   「レコードが存在する（present?）かつ 危機検出（crisis_detected?）」と
    #   日本語の条件そのままに読めるこの形にする。
    #   present? が false のときは && の短絡評価でそこで確定するため、
    #   結果は必ず true / false のどちらかになる（nil にならない）。
    @reflection_crisis_skipped =
      latest_reflection_analysis.present? && latest_reflection_analysis.crisis_detected?

    # ② 「完了バナー」を出す対象＝通常完了した分析だけを採用する。
    #
    # 【actions_json.nil? で判定する理由（＝挙動を一切変えない）】
    #   修正前の DB 条件 .where.not(actions_json: nil) と“完全に同じ意味”を Ruby 側で再現する。
    #   （.present? ではなく .nil? を使うのは、提案が空配列 [] の完了分析も従来どおり
    #     「完了」として扱い、既存挙動と1ミリもズレないようにするため）
    #   通常完了は actions_json に提案配列が入り nil ではない／危機スキップは nil なので
    #   ここで自然に除外され、@reflection_ai_analysis には通常完了だけが入る。
    #
    #   ※将来 ai_analyses に status カラム（例: :failed）を追加する際は、この判定を
    #     AiAnalysis モデルの述語メソッド（completed? 等）へ切り出すとより堅牢になる。
    #     今回は本ISSUEのスコープ（ダッシュボード表示ロジックのみ）に留め、挙動を維持する。
    @reflection_ai_analysis =
      if latest_reflection_analysis && !latest_reflection_analysis.actions_json.nil?
        latest_reflection_analysis
      end

    # ③ 「振り返りAI分析中...」バナーを出すかのフラグ。
    #   判定条件が長くなるため、レビュー指摘⑤に従い private の
    #   reflection_analysis_pending? に切り出して呼び出す（index を読みやすく保つ）。
    @reflection_analysis_pending = reflection_analysis_pending?

    # ── H-9: 振り返り完了バナーの永続表示判定（ロジック変更なし）──
    #
    # @reflection_ai_analysis（＝通常完了の分析）が存在し、かつ「未確認（✖で閉じていない or
    # 閉じた後に再分析された）」ときだけ表示する。危機スキップ時は @reflection_ai_analysis が
    # nil になるため、このバナーは自動的に非表示になる（＝通常完了バナーの挙動に影響しない）。
    reflection_banner_dismissed_at = @user_setting&.reflection_banner_dismissed_at
    @show_reflection_completion_banner =
      @reflection_ai_analysis.present? &&
      (reflection_banner_dismissed_at.nil? ||
       @reflection_ai_analysis.created_at > reflection_banner_dismissed_at)
    # ─────────────────────────────────────────────────────────────────────
  end

  private

  # ── H-10 追加: 「振り返りAI分析中」バナーを出すかの判定（レビュー指摘⑤で切り出し）──
  #
  # 【なぜ private メソッドに切り出すか】
  #   index アクションが縦に長くなり読みにくくなるため、判定条件だけを別メソッドにまとめる。
  #   このメソッドは index の中で先にセットしたインスタンス変数に依存しているので、
  #   必ず @latest_completed_reflection / @reflection_ai_analysis / @reflection_crisis_skipped を
  #   セットした後に呼び出すこと。
  #
  # 【各条件の意味】
  #   @latest_completed_reflection.present?  … 完了済み振り返りが存在する
  #   @reflection_ai_analysis.nil?           … 通常完了の分析結果がまだ無い
  #   !@reflection_crisis_skipped            … 危機スキップではない（★H-10 の肝。
  #                                            これが無いと危機スキップを「分析中」と誤判定し
  #                                            スピナーが永久表示される）
  #   completed_at >= 1.week.ago             … 直近1週間以内の振り返りに限定
  #                                            （古い振り返りで分析中バナーが出るのを防ぐ）
  def reflection_analysis_pending?
    @latest_completed_reflection.present? &&
      @reflection_ai_analysis.nil? &&
      !@reflection_crisis_skipped &&
      @latest_completed_reflection.completed_at >= 1.week.ago
  end

  # ============================================================
  # C-6: build_task_priority_stats（タイムゾーン修正版）
  # ============================================================
  def build_task_priority_stats(user)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)

    week_start_time = week_start.in_time_zone.beginning_of_day
    today_end_time  = today.in_time_zone.end_of_day

    base_scope = user.tasks
                     .active
                     .where(
                       "(created_at BETWEEN :start AND :end_time) OR (due_date BETWEEN :due_start AND :due_end)",
                       start:     week_start_time,
                       end_time:  today_end_time,
                       due_start: week_start,
                       due_end:   today
                     )

    total_counts = base_scope.unscope(:order).group(:priority).count

    done_counts = base_scope.unscope(:order)
                            .where(status: [ Task.statuses[:done], Task.statuses[:archived] ])
                            .group(:priority)
                            .count

    %w[must should could].each_with_object({}) do |priority_name, result|
      total = total_counts[priority_name] || 0
      done  = done_counts[priority_name]  || 0
      rate = total.zero? ? 0 : ((done.to_f / total) * 100).clamp(0, 100).floor
      result[priority_name] = { total: total, done: done, rate: rate }
    end
  end

  # ============================================================
  # build_habit_stats（B-2: 除外日対応 / I-6: キャッシュ導入）
  # ============================================================
  #
  # 【#I-6 での変更内容と設計思想（最重要・必読）】
  #
  #   このメソッドは元々「DBから集計する処理」と「達成率を割り算する処理」が
  #   ひと続きになっていた。#I-6 ではこれを2つに分割し、
  #   ★DBから集計する部分だけ★ をキャッシュする。
  #
  #     fetch_weekly_record_counts … DBに問い合わせる（2クエリ）→ キャッシュ対象
  #     build_stats_from_counts    … 割り算するだけ（0クエリ）  → 毎回実行
  #
  # 【なぜ達成率まで一緒にキャッシュしないのか（これが設計の肝）】
  #
  #   達成率の分母は habit.effective_weekly_target で、
  #   その中身は「weekly_target と (7 - 除外日数) の小さいほう」である。
  #   もし達成率まで丸ごとキャッシュすると、次の不具合が起きる:
  #
  #     ・習慣の「週の目標回数」を 5回 → 3回 に変更しても、
  #       最大1時間ダッシュボードの達成率が古いままになる
  #     ・「日曜は除外」の設定を変えても、最大1時間反映されない
  #
  #   一方、割り算だけを毎回行う設計なら:
  #
  #     ・effective_weekly_target は includes(:habit_excluded_days) で
  #       事前読み込み済みの配列を数えるだけなので【追加クエリ0件】
  #     ・目標値・除外日の変更が【即座に】画面へ反映される
  #     ・除外日を管理する habit_excluded_day.rb に一切手を加えずに済む
  #
  #   「キャッシュするのはDBアクセスだけ。CPUで一瞬で終わる計算はキャッシュしない」
  #   という原則を守ることで、速度と正確さを両立できる。
  #
  # 【キャッシュが古い習慣を含む/含まないケースの安全性】
  #   キャッシュの中身は { habit_id => 件数 } のハッシュ。
  #     ・習慣を新規作成 → キャッシュにその id が無い → 0件として扱う（正しい。記録がまだ無いため）
  #     ・習慣を削除     → キャッシュに id が残るが、habits に無いので無視される（実害なし）
  #     ・アーカイブ復元 → 過去の記録があるのに0件になる恐れがあるため、
  #                        Habit モデルの after_commit でキャッシュを消して対処している
  def build_habit_stats(habits, user)
    # Rails.cache.fetch(キー, expires_in:) do ... end
    #   【動作】
    #     ① キーに対応する値がキャッシュにあれば、その値を返す（ブロックは実行しない）
    #     ② 無ければブロックを実行し、その戻り値をキャッシュに保存してから返す
    #
    #   【expires_in: 1.hour にする理由（ISSUE の指定どおり）】
    #     after_commit による明示的な削除があるので、通常この期限に頼ることはない。
    #     これは「保険」として機能する:
    #       ・update_all など、コールバックを通さない経路でデータが変わった場合
    #       ・キャッシュ削除の DELETE が何らかの理由で失敗した場合
    #     最悪でも1時間で必ず正しい値に戻ることを保証する安全装置。
    #
    #   【キーに user.id を含める理由（セキュリティ上の必須事項）】
    #     含め忘れると、全ユーザーが同じキーを共有してしまい、
    #     他人の習慣達成率が自分の画面に表示されるという重大な情報漏洩になる。
    #     ApplicationRecord.dashboard_habit_stats_cache_key が必ず user_id を含む形で
    #     キーを組み立てるため、呼び出し側で入れ忘れる事故を防いでいる。
    counts = Rails.cache.fetch(
      ApplicationRecord.dashboard_habit_stats_cache_key(user.id),
      expires_in: 1.hour
    ) do
      fetch_weekly_record_counts(habits, user)
    end

    build_stats_from_counts(habits, counts)
  end

  # ── I-6 追加: fetch_weekly_record_counts（キャッシュ対象の「DBアクセス部分」）──
  #
  # 【役割】
  #   今週（月曜〜今日）の習慣記録を habit_id ごとに集計する。
  #   このメソッドの中身だけが2回のSQLを発行する。
  #
  # 【戻り値の形】
  #   {
  #     check_counts: { 1 => 3, 2 => 5 },        # チェック型: habit_id => 完了日数
  #     numeric_sums: { 3 => 120.0 }             # 数値型:     habit_id => 数値の合計
  #   }
  #
  # 【❗キャッシュに保存できる値の条件】
  #   Solid Cache は値を Marshal（Rubyの標準シリアライズ）でバイナリ化して
  #   PostgreSQL の bytea カラムに保存する。
  #   そのため保存できるのは「Marshal 可能なオブジェクト」に限られる。
  #     ○ Hash / Array / Integer / Float / BigDecimal / String / Date … すべて可
  #     ✗ ActiveRecord のインスタンス（可能だが、DBの最新状態とズレるため厳禁）
  #     ✗ Proc / IO / データベース接続など
  #   ここで返しているのは数値のハッシュだけなので安全。
  #   （group(...).count / group(...).sum(...) は ActiveRecord オブジェクトではなく
  #     素の Hash を返すため、そのままキャッシュに入れられる）
  #
  # 【B-2 からのロジック変更は一切ない】
  #   元の build_habit_stats の前半部分をそのまま切り出しただけ。
  #   SQL の内容・条件は完全に同一のため、集計結果は今までと1ミリも変わらない。
  def fetch_weekly_record_counts(habits, user)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    check_habit_ids   = habits.select(&:check_type?).map(&:id)
    numeric_habit_ids = habits.select(&:numeric_type?).map(&:id)

    # 該当する習慣が0件のときは SQL を発行せず空ハッシュを返す。
    # （where(habit_id: []) でも動くが、無駄なクエリを1回節約できる）
    check_counts = if check_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: check_habit_ids, record_date: week_range, completed: true)
        .group(:habit_id)
        .count
    else
      {}
    end

    numeric_sums = if numeric_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: numeric_habit_ids, record_date: week_range, deleted_at: nil)
        .group(:habit_id)
        .sum(:numeric_value)
    else
      {}
    end

    { check_counts: check_counts, numeric_sums: numeric_sums }
  end

  # ── I-6 追加: build_stats_from_counts（毎回実行する「割り算部分」）──────────
  #
  # 【役割】
  #   キャッシュから取り出した集計値と、DBから毎回取得している最新の習慣情報を
  #   組み合わせて達成率を計算する。DBアクセスは0件。
  #
  # 【habit.effective_weekly_target が追加クエリを発生させない理由】
  #   DashboardsController#index が
  #     current_user.habits.active.includes(:habit_excluded_days)
  #   で除外日を事前読み込み（preload）しているため、
  #   effective_weekly_target の内部で呼ばれる habit_excluded_days.size は
  #   メモリ上の配列を数えるだけで済む。
  #   （もし .pluck を使っていたら preload 済みでも毎回SQLが飛ぶ。
  #     この違いは #H-9 で Habit#excluded_day_numbers を .pluck → .map に
  #     変更した際に確認済み）
  #
  # 【counts[:check_counts] に || {} を付ける理由】
  #   万一キャッシュに想定外の形（nil や古い構造）が入っていても
  #   NoMethodError で画面が真っ白になるのを防ぐ防御。
  #   キーが無ければ「0件」として扱われ、達成率0%と表示されるだけで済む。
  #
  # 【計算ロジックは B-2 から一切変更なし】
  #   clamp(0, 100).floor（切り捨て）も含めて元のコードと完全に同一。
  #   既存テスト（Must 2/3件 → 66% 等）の期待値がそのまま通る。
  def build_stats_from_counts(habits, counts)
    check_counts = counts[:check_counts] || {}
    numeric_sums = counts[:numeric_sums] || {}

    habits.each_with_object({}) do |habit, hash|
      if habit.check_type?
        # effective_weekly_target: 除外日を考慮した実質的な目標回数。
        # 毎回計算するため、除外日の設定変更が即座に反映される。
        target          = habit.effective_weekly_target
        completed_count = check_counts[habit.id] || 0
        rate = target.zero? ? 0 :
          ((completed_count.to_f / target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: completed_count, numeric_sum: nil,
                           effective_target: target }
      else
        # to_f を付ける理由: sum(:numeric_value) は decimal カラムのため
        # BigDecimal を返す。ビューでの表示や割り算を Float に統一する。
        numeric_sum = (numeric_sums[habit.id] || 0).to_f
        rate = habit.weekly_target.zero? ? 0 :
          ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: nil, numeric_sum: numeric_sum,
                           effective_target: habit.weekly_target }
      end
    end
  end
end