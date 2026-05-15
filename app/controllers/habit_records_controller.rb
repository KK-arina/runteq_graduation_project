# app/controllers/habit_records_controller.rb
#
# ==============================================================================
# HabitRecordsController（E-3 修正: ページ別 Turbo Stream 対応）
# ==============================================================================
#
# 【E-3 修正内容】
#   リクエスト元のページ（/habits or /dashboard）を判定して
#   Turbo Stream の応答を切り替える。
#
#   /habits ページ:
#     turbo_stream.replace("habit_record_#{@habit.id}", partial: "habits/habit_card", ...)
#     → カード全体（プログレスバー含む）を置き換える
#     → id="habit_record_#{habit.id}" が habits/_habit_card.html.erb のラッパーと一致
#
#   /dashboard ページ（その他）:
#     turbo_stream.replace("habit_record_row_#{@habit.id}", partial: "habit_records/habit_record", ...)
#     → チェックボックス/数値入力部分だけを置き換える（既存の動作を維持）
#     → ダッシュボードにプログレスバーは個別カードとして存在しないため不要
#
#   【なぜ referer で判定するのか】
#     Turbo Stream リクエストは Accept ヘッダーで識別できるが、
#     「どのページから来たか」は request.referer で判定する。
#     params に page: "habits" を含める方法もあるが、
#     既存の JS（habit_record_controller.js）を変更せずに済む referer 判定を採用。
# ==============================================================================

class HabitRecordsController < ApplicationController
  before_action :require_login
  before_action :set_habit

  def create
    service_params = parse_service_params

    result = HabitRecordSaveService.new(
      user:          current_user,
      habit:         @habit,
      completed:     service_params[:completed],
      numeric_value: service_params[:numeric_value],
      memo:          service_params[:memo]
    ).call

    if result[:success]
      @habit_record = result[:habit_record]
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: build_turbo_stream_response(@habit_record)
        end
        format.html { redirect_to dashboard_path, notice: "記録を保存しました" }
      end
    else
      Rails.logger.error "HabitRecordSaveService failed: #{result[:errors]}"
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to dashboard_path, alert: result[:errors].first }
      end
    end
  end

  def update
    @habit_record = current_user.habit_records.find(params[:id])

    unless @habit_record.habit_id == @habit.id
      render_404 and return
    end

    service_params = parse_service_params

    result = HabitRecordSaveService.new(
      user:          current_user,
      habit:         @habit,
      completed:     service_params[:completed],
      numeric_value: service_params[:numeric_value],
      memo:          service_params[:memo]
    ).call

    if result[:success]
      @habit_record = result[:habit_record]
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: build_turbo_stream_response(@habit_record)
        end
        format.html { redirect_to dashboard_path, notice: "記録を更新しました" }
      end
    else
      Rails.logger.error "HabitRecordSaveService failed: #{result[:errors]}"
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to dashboard_path, alert: result[:errors].first }
      end
    end
  end

  private

  def set_habit
    @habit = current_user.habits.active.find(params[:habit_id])
  rescue ActiveRecord::RecordNotFound
    head :not_found and return
  end

  # ── E-3 修正: build_turbo_stream_response ─────────────────────────────────
  #
  # 【修正内容】
  #   ダッシュボードの「今週の習慣達成率」カードも更新対象に追加する。
  #
  # 【返す Turbo Stream の数】
  #   /habits ページ: 1件（habit_card 全体の置き換え）
  #   それ以外:       2件（habit_record_row + dashboard_habit_stat）
  #
  # 【配列で複数の Turbo Stream を返す方法】
  #   render turbo_stream: [stream1, stream2] で複数の置き換えを1回のレスポンスで送れる。
  #   Turbo はレスポンス内の全ての <turbo-stream> 要素を順番に処理する。
  def build_turbo_stream_response(habit_record)
    from_habits_page = request.referer&.include?("/habits")

    if from_habits_page
      # /habits ページ: カード全体（プログレスバー含む）を置き換える
      turbo_stream.replace(
        "habit_record_#{@habit.id}",
        partial: "habits/habit_card",
        locals:  {
          habit:        @habit,
          stats:        build_habit_stats(@habit, current_user),
          habit_record: habit_record,
          locked:       locked?
        }
      )
    else
      # ダッシュボード等: チェックボックス部分 + 達成率バーの2件を更新する
      #
      # 【なぜ配列で返すのか】
      #   ダッシュボードには2つの更新対象がある:
      #   1. id="habit_record_row_#{habit.id}": 今日の習慣チェックエリア
      #   2. id="dashboard_habit_stat_#{habit.id}": 今週の習慣達成率バー
      #   両方を1回のリクエストで同時に更新するために配列で返す。
      stats = build_habit_stats(@habit, current_user)

      [
        # 今日の習慣チェックエリア（既存の動作を維持）
        turbo_stream.replace(
          "habit_record_row_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: habit_record }
        ),
        # 今週の習慣達成率バー（新規追加）
        turbo_stream.replace(
          "dashboard_habit_stat_#{@habit.id}",
          partial: "dashboards/habit_stat_row",
          locals:  { habit: @habit, stats: stats }
        )
      ]
    end
  end

  # ── E-3 追加: build_habit_stats ───────────────────────────────────────────
  #
  # 【役割】
  #   1件の習慣の今週の達成統計を計算して返す。
  #   チェック/数値変更後に最新のプログレスバー用データを生成する。
  def build_habit_stats(habit, user)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    if habit.check_type?
      target          = habit.effective_weekly_target
      completed_count = HabitRecord
                          .where(user: user, habit: habit, record_date: week_range, completed: true)
                          .count
      rate = target.zero? ? 0 : ((completed_count.to_f / target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: completed_count, numeric_sum: nil, effective_target: target }
    else
      numeric_sum = HabitRecord
                     .where(user: user, habit: habit, record_date: week_range, deleted_at: nil)
                     .sum(:numeric_value)
                     .to_f
      rate = habit.weekly_target.zero? ? 0 : ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: nil, numeric_sum: numeric_sum, effective_target: habit.weekly_target }
    end
  end

  def parse_service_params
    not_provided = HabitRecordSaveService::NOT_PROVIDED

    completed =
      if params.key?(:completed)
        params[:completed] == "1"
      else
        not_provided
      end

    numeric_value =
      if params.key?(:numeric_value)
        parse_numeric_value
      else
        not_provided
      end

    memo =
      if params.key?(:memo)
        params[:memo]&.strip.presence
      else
        not_provided
      end

    { completed: completed, numeric_value: numeric_value, memo: memo }
  end

  def parse_numeric_value
    raw = params[:numeric_value].presence
    return nil if raw.nil?
    Float(raw)
  rescue ArgumentError, TypeError
    nil
  end
end