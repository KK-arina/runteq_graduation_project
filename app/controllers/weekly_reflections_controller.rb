# app/controllers/weekly_reflections_controller.rb
#
# ==============================================================================
# WeeklyReflectionsController（D-5: 危機介入機能を追加）
# ==============================================================================
# 【D-5 での変更内容】
#   create アクションで WeeklyReflectionCompleteService の戻り値に
#   crisis_detected: true が含まれている場合、
#   flash[:crisis] にフラグを立てて振り返り入力ページにリダイレクトする。
#   このフラグをビューが受け取って危機介入モーダルを表示する。
#
# 【なぜ flash を使うのか】
#   リダイレクト後のページ（new.html.erb）でモーダルを表示するために、
#   リダイレクト前のリクエストのデータをリダイレクト後に渡す手段として
#   flash が最適。flash は1リクエストだけ生きるセッション情報。
# ==============================================================================

class WeeklyReflectionsController < ApplicationController
  before_action :require_login
  before_action :set_weekly_reflection, only: [:show]

  def index
    @weekly_reflections = current_user.weekly_reflections
                                      .completed
                                      .recent
                                      .includes(:habit_summaries)

    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)
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

      # ── D-5 追加: 危機ワード検出時の分岐 ────────────────────────────────
      #
      # 【なぜ crisis_detected: true でも success: true を返すのか】
      #   振り返りの保存自体は成功しているため、success: true になる。
      #   crisis 検出は「保存の失敗」ではなく「特別な状態」なので、
      #   success の中に crisis_detected フラグを含めて判断する。
      #
      # 【flash[:crisis] の使い方】
      #   リダイレクト先のビューで `flash[:crisis]` が true なら
      #   危機介入モーダルを自動表示する（JavaScript で制御）。
      #   flash は1リクエスト分のみ有効なので、ページ遷移後は自動でクリアされる。
      if result[:crisis_detected]
        Rails.logger.warn "[WeeklyReflectionsController] 危機ワード検出: user_id=#{current_user.id}"

        # flash[:crisis]: JavaScript がモーダルを表示するためのトリガー
        flash[:crisis] = true

        # ロック解除済みなら unlock バナーも表示する
        if was_locked
          flash[:unlock] = "振り返りが完了しました。PDCAロックが解除されました。🔓"
        end

        # 振り返り入力ページに戻す（保存は完了しているのでダッシュボードでもよいが、
        # モーダルを見てもらうために振り返りページに留める）
        redirect_to new_weekly_reflection_path
        return
      end
      # ────────────────────────────────────────────────────────────────────────

      if was_locked
        flash[:unlock] = "振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！🔓"
        redirect_to dashboard_path
      else
        redirect_to weekly_reflections_path,
                    notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
      end
    else
      Rails.logger.error "WeeklyReflectionCompleteService failed: #{result[:error]}"

      @habits = current_user.habits.active.includes(:habit_excluded_days)
      @habit_stats = build_habit_stats(@habits, current_user)
      @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
      @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }

      flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @habit_summaries = @weekly_reflection.habit_summaries
                                         .order(achievement_rate: :desc)
                                         .to_a
    @task_summaries  = @weekly_reflection.task_summaries
                                         .by_priority
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