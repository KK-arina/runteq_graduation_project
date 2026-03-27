# app/controllers/weekly_reflections_controller.rb
#
# ==============================================================================
# 【リフレクション手法対応での変更内容】
#   ① create アクションで params[:reflection_numeric_corrections] を
#     WeeklyReflectionCompleteService に渡す（corrections: 引数）
#   ② weekly_reflection_params に :direct_reason / :background_situation /
#     :next_action を追加
#   ③ build_habit_stats を B-1 数値型対応版に更新
# ==============================================================================

class WeeklyReflectionsController < ApplicationController
  before_action :require_login
  before_action :set_weekly_reflection, only: [ :show ]

  # ---------------------------------------------------------------
  # index
  # ---------------------------------------------------------------
  def index
    @weekly_reflections = current_user.weekly_reflections
                                      .completed
                                      .recent
                                      .includes(:habit_summaries)

    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    @habits = current_user.habits.active
    @habit_stats = build_habit_stats(@habits, current_user)
  end

  # ---------------------------------------------------------------
  # new
  # ---------------------------------------------------------------
  def new
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    @habits = current_user.habits.active
    @habit_stats = build_habit_stats(@habits, current_user)

    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

  # ---------------------------------------------------------------
  # create
  # ---------------------------------------------------------------
  def create
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    @weekly_reflection.assign_attributes(weekly_reflection_params)
    was_locked = current_user.locked?

    # ── 変更: corrections を Service に渡す ────────────────────────────────
    #
    # params[:reflection_numeric_corrections] は以下の形式で届く:
    #   { "habit_1" => "150.0", "habit_3" => "45" }
    # フォームの name 属性が:
    #   name="reflection_numeric_corrections[habit_#{habit.id}]"
    # のように設定されているため、Rails が自動でネストしたハッシュに変換する。
    #
    # .permit! は使わず、Service 内で habit_id の妥当性チェックを行う設計にしている。
    # （Service が自分のユーザーの習慣かどうかを確認するため）
    #
    # nil の場合は Service 側で {} に変換されるため、
    # ここでは presence チェック不要（nil のまま渡す）。
    result = WeeklyReflectionCompleteService.new(
      reflection:  @weekly_reflection,
      user:        current_user,
      was_locked:  was_locked,
      corrections: params[:reflection_numeric_corrections]  # ← 追加
    ).call
    # ────────────────────────────────────────────────────────────────────────

    if result[:success]
      current_user.reload

      if was_locked
        redirect_to dashboard_path,
                    flash: { unlock: "🔓 振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！" }
      else
        redirect_to weekly_reflections_path,
                    notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
      end
    else
      Rails.logger.error "WeeklyReflectionCompleteService failed: #{result[:error]}"

      @habits = current_user.habits.active
      @habit_stats = build_habit_stats(@habits, current_user)
      @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
      @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }

      flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  # ---------------------------------------------------------------
  # show
  # ---------------------------------------------------------------
  def show
    @habit_summaries = @weekly_reflection.habit_summaries
                                         .includes(:habit)
                                         .order(achievement_rate: :desc)

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
        completed_count = check_counts[habit.id] || 0
        rate = habit.weekly_target.zero? ? 0 :
          ((completed_count.to_f / habit.weekly_target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: completed_count, numeric_sum: nil }
      else
        numeric_sum = (numeric_sums[habit.id] || 0).to_f
        rate = habit.weekly_target.zero? ? 0 :
          ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: nil, numeric_sum: numeric_sum }
      end
    end
  end
end
