# app/controllers/weekly_reflections_controller.rb
#
# ==============================================================================
# WeeklyReflectionsController（B-2: 除外日対応）
# ==============================================================================
# 【B-2 での変更内容】
#   ① @habits 取得時に includes(:habit_excluded_days) を追加（N+1防止）
#   ② build_habit_stats のチェック型の分母を effective_weekly_target に変更
# ==============================================================================

class WeeklyReflectionsController < ApplicationController
  before_action :require_login
  before_action :set_weekly_reflection, only: [ :show ]

  def index
    @weekly_reflections = current_user.weekly_reflections
                                      .completed
                                      .recent
                                      .includes(:habit_summaries)

    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    # includes(:habit_excluded_days)（B-2 追加）
    @habits = current_user.habits.active.includes(:habit_excluded_days)
    @habit_stats = build_habit_stats(@habits, current_user)
  end

  def new
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    # includes(:habit_excluded_days)（B-2 追加）
    @habits = current_user.habits.active.includes(:habit_excluded_days)
    @habit_stats = build_habit_stats(@habits, current_user)

    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

  def create
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    @weekly_reflection.assign_attributes(weekly_reflection_params)
    was_locked = current_user.locked?

    result = WeeklyReflectionCompleteService.new(
      reflection:  @weekly_reflection,
      user:        current_user,
      was_locked:  was_locked,
      corrections: params[:reflection_numeric_corrections]
    ).call

    if result[:success]
      current_user.reload

      if was_locked
        flash[:unlock] = "振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！🔓"
        redirect_to dashboard_path
      else
        redirect_to weekly_reflections_path,
                    notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
      end
    else
      Rails.logger.error "WeeklyReflectionCompleteService failed: #{result[:error]}"

      # includes(:habit_excluded_days)（B-2 追加）
      @habits = current_user.habits.active.includes(:habit_excluded_days)
      @habit_stats = build_habit_stats(@habits, current_user)
      @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
      @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }

      flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # habit_name はスナップショット列のため habit の eager loading は不要
    # .to_a で配列化し .count / .size がメモリ上で完結するようにする
    @habit_summaries = @weekly_reflection.habit_summaries
                                        .order(achievement_rate: :desc)
                                        .to_a
    @overall_achievement_rate = calculate_overall_achievement_rate
  end

  private

  def calculate_overall_achievement_rate
    return 0 if @habit_summaries.empty?
    (@habit_summaries.map(&:achievement_rate).sum / @habit_summaries.size.to_f).round(1)
  end

  def set_weekly_reflection
    @weekly_reflection = current_user.weekly_reflections.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to weekly_reflections_path, alert: "振り返りが見つかりませんでした。"
  end

  def weekly_reflection_params
    params.require(:weekly_reflection).permit(
      :reflection_comment,
      :direct_reason,
      :background_situation,
      :next_action
    )
  end

  def find_pending_last_week_reflection
    current_week = WeeklyReflection.current_week_start_date
    last_week    = current_week - 7.days
    current_user.weekly_reflections
                .pending
                .find_by(week_start_date: last_week)
  end

  # build_habit_stats（B-2: 除外日対応に更新）
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
        # 【B-2 変更】分母を effective_weekly_target に変更
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