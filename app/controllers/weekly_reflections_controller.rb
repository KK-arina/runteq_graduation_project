# app/controllers/weekly_reflections_controller.rb
#
# ═══════════════════════════════════════════════════════════════════
# 【このファイルの役割】
#   週次振り返り（WeeklyReflection）に関するHTTPリクエストを受け取り、
#   適切なデータ処理とビュー表示を担当するコントローラー。
# ═══════════════════════════════════════════════════════════════════
#
# 【Issue #A-7 での変更箇所】
#
#   create アクションのビジネスロジックを
#   WeeklyReflectionCompleteService に委譲するように変更。
#
#   変更前:
#     create アクション内に直接 ActiveRecord::Base.transaction を書いていた。
#     → コントローラーが肥大化していた
#     → 同じロジックを別の場所から呼び出せなかった
#
#   変更後:
#     WeeklyReflectionCompleteService.new(...).call を呼ぶだけ。
#     → コントローラーは「受け取り→サービスへ委譲→レスポンス返却」のみ担当
#     → ビジネスロジックはサービスクラスに集約
#     → テストがサービス単体で書けるようになった

class WeeklyReflectionsController < ApplicationController
  before_action :require_login
  before_action :set_weekly_reflection, only: [ :show ]

  # ---------------------------------------------------------------
  # index アクション
  # GET /weekly_reflections
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
  # new アクション
  # GET /weekly_reflections/new
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
  # create アクション（Issue #A-7 で変更）
  # POST /weekly_reflections
  # ---------------------------------------------------------------
  def create
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    @weekly_reflection.assign_attributes(weekly_reflection_params)

    # ── Issue #A-7: ロック状態を「保存前に」記録する ──────────────
    # 【なぜ保存前に記録するのか？】
    # WeeklyReflectionCompleteService の中で complete! を呼ぶと
    # locked? が false になってしまう。
    # サービスを呼ぶ「前」に locked? の値を取っておき、
    # サービスに渡すことで正確な判断ができる。
    was_locked = current_user.locked?

    # ── Issue #A-7: サービスクラスに委譲 ─────────────────────────
    # 変更前: このコントローラーに直接 transaction ブロックを書いていた
    # 変更後: WeeklyReflectionCompleteService に委譲する
    #
    # WeeklyReflectionCompleteService.new(...)
    # → サービスオブジェクトを生成する（initialize を呼ぶ）
    # .call
    # → トランザクションを実行してフローを完了する
    # → 戻り値: { success: true/false, error: nil/"メッセージ" }
    result = WeeklyReflectionCompleteService.new(
      reflection: @weekly_reflection,
      user:       current_user,
      was_locked: was_locked
    ).call

    if result[:success]
      # current_user.reload
      # → セッションのキャッシュを使わず、DBから最新の状態を取得する。
      # → complete! で変化した locked? の判定を正確にするため。
      current_user.reload

      if was_locked
        redirect_to dashboard_path,
                    flash: { unlock: "🔓 振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！" }
      else
        redirect_to weekly_reflections_path,
                    notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
      end
    else
      # サービスから失敗が返ってきた場合
      # result[:error] にはエラーメッセージが入っている
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
  # show アクション
  # GET /weekly_reflections/:id
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
    params.require(:weekly_reflection).permit(:reflection_comment)
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

    records_count_by_habit = HabitRecord
      .where(user: user, habit: habits, record_date: week_range, completed: true)
      .group(:habit_id)
      .count

    habits.each_with_object({}) do |habit, hash|
      completed_count = records_count_by_habit[habit.id] || 0
      rate = if habit.weekly_target.zero?
               0
             else
               ((completed_count.to_f / habit.weekly_target) * 100)
                 .clamp(0, 100)
                 .floor
             end
      hash[habit.id] = { rate: rate, completed_count: completed_count }
    end
  end
end