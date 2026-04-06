# app/controllers/dashboards_controller.rb
#
# ==============================================================================
# DashboardsController（B-2: 除外日対応）
# ==============================================================================
# 【B-2 での変更内容】
#   ① @habits 取得時に includes(:habit_excluded_days) を追加（N+1防止）
#   ② build_habit_stats のチェック型の分母を effective_weekly_target に変更
# ==============================================================================

class DashboardsController < ApplicationController
  before_action :require_login

  def index
    @today      = HabitRecord.today_for_record
    @week_start = @today.beginning_of_week(:monday)

    @habits = current_user.habits.active
                          .includes(:habit_excluded_days)
                          .order(created_at: :desc)

    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    @habit_stats = build_habit_stats(@habits, current_user)

    @overall_rate = @habits.empty? ? 0 :
      (@habit_stats.values.map { |s| s[:rate] }.sum.to_f / @habit_stats.size).round

    @locked = locked?

    # ── C-1 追加: 今日のタスク ──────────────────────────────────────────
    # 今日が期限（due_date = 今日）のタスクを取得する。
    # .active           → 論理削除されていないもの
    # .not_archived     → アーカイブ済みを除く
    # .today            → due_date = 今日（HabitRecord.today_for_record）
    # .order(priority:) → 重要度順（must → should → could）
    #
    # なぜ today スコープを使うのか:
    #   ダッシュボードには「今日やるべきタスク」のみ表示する。
    #   due_date を持たないタスクや未来・過去のタスクは
    #   タスク一覧ページ（/tasks）で管理する。
    @today_tasks = current_user.tasks
                                .active
                                .not_archived
                                .today
                                .order(priority: :asc)
                                .limit(5)  # ダッシュボードには最大5件表示
  end

  private

  # build_habit_stats（B-2: 除外日対応に更新）
  # チェック型の分母を effective_weekly_target（除外日考慮後）に変更する。
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
        # 【B-2 変更】分母を effective_weekly_target（除外日考慮後の実施予定日数）に変更
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