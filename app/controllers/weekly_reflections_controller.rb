# app/controllers/weekly_reflections_controller.rb
#
# ═══════════════════════════════════════════════════════════════════
# 【このファイルの役割】
#   週次振り返り（WeeklyReflection）に関するHTTPリクエストを受け取り、
#   適切なデータ処理とビュー表示を担当するコントローラー。
#   Rails の MVC アーキテクチャにおける "C（Controller）" の部分。
# ═══════════════════════════════════════════════════════════════════
#
# 【Issue #25 での変更箇所（create アクションのみ）】
#
#   変更前:
#     @weekly_reflection.is_locked = true  ← 完了フラグを直接セット
#     @weekly_reflection.save!
#     redirect_to weekly_reflections_path, notice: "..."
#
#   変更後:
#     was_locked = current_user.locked?      ← 保存前にロック状態を記録
#     @weekly_reflection.save!
#     @weekly_reflection.complete!           ← complete! で completed_at に時刻を記録
#     current_user.reload                    ← キャッシュリセット
#     if was_locked → dashboard_path + unlock メッセージ
#     else          → weekly_reflections_path + 通常メッセージ（元のまま）
#
#   index / new / show / private メソッドは一切変更なし。

class WeeklyReflectionsController < ApplicationController
  before_action :require_login
  before_action :set_weekly_reflection, only: [:show]

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

    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end
  end

  # ---------------------------------------------------------------
  # new アクション
  # GET /weekly_reflections/new
  # ---------------------------------------------------------------
  def new
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.is_locked?
      redirect_to @weekly_reflection, notice: "今週の振り返りは既に完了しています。"
      return
    end

    @habits = current_user.habits.active

    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

  # ---------------------------------------------------------------
  # create アクション
  # POST /weekly_reflections
  # ---------------------------------------------------------------
  def create
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.is_locked?
      redirect_to @weekly_reflection, notice: "今週の振り返りは既に完了しています。"
      return
    end

    @weekly_reflection.assign_attributes(weekly_reflection_params)

    # ============================================================
    # Issue #25: ロック状態を「保存前に」記録する
    # ============================================================
    # complete! を呼んだ後は locked? が false になるため、
    # 「元々ロック中だったか」を保存前に変数へ入れておく。
    was_locked = current_user.locked?

    ActiveRecord::Base.transaction do
      @weekly_reflection.save!
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@weekly_reflection)

      # 今週の振り返りを完了にする（is_locked: true + completed_at を記録）
      @weekly_reflection.complete!

      # ============================================================
      # Issue #25: ロック中だった場合は「前週の振り返り」も完了にする
      # ============================================================
      # locked? の判定は「前週の振り返りが pending? かどうか」で行われる。
      # つまりロックを解除するには「前週を complete!」する必要がある。
      #
      # 【なぜ今週だけ complete! しても解除されないのか】
      # ロック中のユーザーが今週の振り返りを投稿しても、
      # locked? は「前週（2週間前）の振り返り」を見ているため、
      # 今週を完了しただけでは locked? は false にならない。
      # → 前週の振り返りレコードを見つけて complete! することで初めてロックが解除される。
      #
      # 【なぜ今週も complete! するのか】
      # 今週の振り返りも完了状態にしておかないと is_locked が false のままになり、
      # 一覧に表示されず二重送信防止も効かなくなるため、両方を complete! する。
      if was_locked
        last_week_start = WeeklyReflection.current_week_start_date - 7.days
        last_week = current_user.weekly_reflections
                                .find_by(week_start_date: last_week_start)
        last_week&.complete!
      end
    end

    # complete! 後に current_user のアソシエーションキャッシュをリセットする
    current_user.reload

    # ============================================================
    # Issue #25: ロック中だったか否かでメッセージとリダイレクト先を変える
    # ============================================================
    if was_locked
      redirect_to dashboard_path,
                  flash: { unlock: "🔓 振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！" }
    else
      redirect_to weekly_reflections_path,
                  notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
    end

  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.error("WeeklyReflection create error: #{e.message}")

    @habits = current_user.habits.active
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }

    flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
    render :new, status: :unprocessable_entity
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
end
