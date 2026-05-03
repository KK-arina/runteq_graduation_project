# app/controllers/weekly_reflections_controller.rb
#
# ==============================================================================
# WeeklyReflectionsController
# ==============================================================================
# 【変更履歴】
#   D-5: create アクションに危機介入（crisis_detected）分岐を追加
#   D-6: create アクションに AI コスト上限チェックを追加
#        ・上限に達している場合は flash.now[:ai_limit] = true をセットして
#          render :new を実行する（redirect_to ではなく render を使う理由は後述）
#        ・complete_without_ai アクションを新規追加
#          → 振り返りを保存してロック解除するが AI 分析ジョブはエンキューしない
#
# 【D-6 の最重要設計ポイント: render vs redirect_to】
#   NG: redirect_to new_weekly_reflection_path
#     → ユーザーが書いた「振り返りコメント」「なぜ？」等のテキストがすべて消える
#     → 書き直しを強いられるため UX が最悪になる
#
#   OK: render :new, status: :unprocessable_entity
#     → @weekly_reflection のインスタンス変数が保持されるため、
#       フォームに入力済みの内容がそのまま残る
#     → モーダルだけが浮かび上がり、ユーザーは選択するだけでよい
#
# 【flash.now vs flash の使い分け】
#   flash      : 次のリクエスト（リダイレクト先）まで保持される
#   flash.now  : 現在のリクエスト内（render したビュー）だけで有効
#   render :new のときは flash.now を使う。flash を使うと
#   次のページ遷移でも表示されてしまい、モーダルが二重に起動する。
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

  # ============================================================
  # create アクション（D-6: AI コスト上限チェックを追加）
  # ============================================================
  def create
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    # フォームの入力値を @weekly_reflection にセットする。
    # assign_attributes を先に実行することで、AI上限チェックで
    # render :new になった場合もフォームの入力内容が残る。
    @weekly_reflection.assign_attributes(weekly_reflection_params)

    # ── D-6 追加: AI コスト上限チェック ──────────────────────────────────────
    #
    # 【flash.now を使う理由】
    #   render :new（リダイレクトなし）でビューを描画するため、
    #   flash.now で「このリクエスト内だけ有効」なフラグを立てる。
    #   flash を使うと次のリクエストでもフラグが残りモーダルが二重起動する。
    if ai_limit_exceeded?
      flash.now[:ai_limit] = true
      setup_new_form_variables
      render :new, status: :unprocessable_entity
      return
    end
    # ────────────────────────────────────────────────────────────────────────────

    was_locked = current_user.locked?

    result = WeeklyReflectionCompleteService.new(
      reflection:  @weekly_reflection,
      user:        current_user,
      was_locked:  was_locked,
      corrections: params[:reflection_numeric_corrections]
    ).call

    if result[:success]
      current_user.reload

      # ── D-5: 危機ワード検出時の分岐（変更なし）──────────────────────────
      if result[:crisis_detected]
        Rails.logger.warn "[WeeklyReflectionsController] 危機ワード検出: user_id=#{current_user.id}"
        flash[:crisis] = true

        if was_locked
          flash[:unlock] = "振り返りが完了しました。PDCAロックが解除されました。🔓"
          redirect_to dashboard_path
        else
          redirect_to weekly_reflections_path
        end
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
      setup_new_form_variables
      flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # complete_without_ai アクション（D-6 新規追加）
  # ============================================================
  #
  # 【役割】
  #   Stimulus の submitWithoutAi() から呼ばれる。
  #   メインフォームの action を /weekly_reflections/complete_without_ai に
  #   書き換えて送信するため、ユーザーが入力した振り返り内容がそのまま届く。
  #   振り返りの保存とロック解除は通常通り行うが、
  #   AI 分析ジョブはエンキューしない（上限チェックで自動スキップされる）。
  def complete_without_ai
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    @weekly_reflection.assign_attributes(complete_without_ai_params)
    was_locked = current_user.locked?

    result = WeeklyReflectionCompleteService.new(
      reflection:  @weekly_reflection,
      user:        current_user,
      was_locked:  was_locked,
      corrections: params[:reflection_numeric_corrections]
    ).call

    if result[:success]
      current_user.reload

      if result[:crisis_detected]
        flash[:crisis] = true
        if was_locked
          flash[:unlock] = "振り返りが完了しました。PDCAロックが解除されました。🔓"
          redirect_to dashboard_path
        else
          redirect_to weekly_reflections_path
        end
        return
      end

      if was_locked
        flash[:unlock] = "振り返りが完了しました！PDCAロックが解除されました。（今月のAI分析回数の上限に達したため、AI分析はスキップされました）🔓"
        redirect_to dashboard_path
      else
        redirect_to weekly_reflections_path,
                    notice: "今週の振り返りを保存しました！（AI分析はスキップされました）お疲れ様でした🎉"
      end
    else
      Rails.logger.error "WeeklyReflectionCompleteService (without AI) failed: #{result[:error]}"
      setup_new_form_variables
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

  # complete_without_ai 専用のパラメータ取得メソッド
  # モーダルのフォームは weekly_reflection[] なしで送信されるため
  # weekly_reflection_params とは別に定義する
  def complete_without_ai_params
    # params に weekly_reflection キーがある場合（通常フォームからの送信）
    if params[:weekly_reflection].present?
      weekly_reflection_params
    else
      # モーダルの hidden フィールドからの送信（フラットなパラメータ）
      params.permit(
        :reflection_comment,
        :direct_reason,
        :background_situation,
        :next_action
      )
    end
  end

  # setup_new_form_variables（D-6 新規追加）
  # new ビューのレンダリングに必要な変数を一括セットする。
  # create と complete_without_ai の両方で render :new する際に使う（DRY化）。
  def setup_new_form_variables
    @habits = current_user.habits.active.includes(:habit_excluded_days)
    @habit_stats = build_habit_stats(@habits, current_user)
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

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