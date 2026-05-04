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
  end

  private

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
  # build_habit_stats（B-2: 除外日対応。変更なし）
  # ============================================================
  def build_habit_stats(habits, user)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    check_habit_ids   = habits.select(&:check_type?).map(&:id)
    numeric_habit_ids = habits.select(&:numeric_type?).map(&:id)

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

    habits.each_with_object({}) do |habit, hash|
      if habit.check_type?
        target          = habit.effective_weekly_target
        completed_count = check_counts[habit.id] || 0
        rate = target.zero? ? 0 :
          ((completed_count.to_f / target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: completed_count, numeric_sum: nil,
                           effective_target: target }
      else
        numeric_sum = (numeric_sums[habit.id] || 0).to_f
        rate = habit.weekly_target.zero? ? 0 :
          ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: nil, numeric_sum: numeric_sum,
                           effective_target: habit.weekly_target }
      end
    end
  end
end