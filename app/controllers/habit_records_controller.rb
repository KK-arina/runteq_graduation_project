# app/controllers/habit_records_controller.rb
#
# ==============================================================================
# HabitRecordsController（B-7 最終修正版）
# ==============================================================================
#
# 【修正内容】
#
#   Service が NOT_PROVIDED を使った部分更新設計になったため、
#   「送られてきた項目だけ」をサービスに渡す。
#
#   NOT_PROVIDED = :not_provided は HabitRecordSaveService で定義した定数。
#   params にキー自体がない場合は NOT_PROVIDED を渡すことで
#   「この項目は更新しない」という意図を Service に伝える。
#
# ==============================================================================

class HabitRecordsController < ApplicationController
  before_action :require_login
  before_action :set_habit

  # ============================================================
  # POST /habits/:habit_id/habit_records
  # ============================================================
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
          render turbo_stream: turbo_stream.replace(
            "habit_record_row_#{@habit.id}",
            partial: "habit_records/habit_record",
            locals:  { habit: @habit, habit_record: @habit_record }
          )
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

  # ============================================================
  # PATCH /habits/:habit_id/habit_records/:id
  # ============================================================
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
          render turbo_stream: turbo_stream.replace(
            "habit_record_row_#{@habit.id}",
            partial: "habit_records/habit_record",
            locals:  { habit: @habit, habit_record: @habit_record }
          )
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

  # ── parse_service_params（最終修正版）──────────────────────────────────────
  #
  # 【修正後の設計】
  #   params にキーが存在するかどうかで「送られてきたか」を判断する。
  #   params.key?(:memo) が false → memo は送られていない → NOT_PROVIDED を渡す
  #   params.key?(:memo) が true  → memo が送られてきた  → その値を渡す
  #
  # 【params.key? を使う理由】
  #   params[:memo] だと、キーがない場合も nil が返るため
  #   「送られなかった」と「空文字で送られた」の区別ができない。
  #   params.key?(:memo) ならキー自体の有無を確認できる。
  def parse_service_params
    # NOT_PROVIDED 定数を Service から参照する
    not_provided = HabitRecordSaveService::NOT_PROVIDED

    # completed: チェック型でのみ送られてくる
    completed =
      if params.key?(:completed)
        params[:completed] == "1"
      else
        not_provided
      end

    # numeric_value: 数値型でのみ送られてくる
    numeric_value =
      if params.key?(:numeric_value)
        parse_numeric_value
      else
        not_provided
      end

    # memo: メモ保存操作のときのみ送られてくる
    memo =
      if params.key?(:memo)
        # &.strip.presence で nil/空文字/スペースのみを nil に変換する
        params[:memo]&.strip.presence
      else
        not_provided
      end

    { completed: completed, numeric_value: numeric_value, memo: memo }
  end
  # ────────────────────────────────────────────────────────────────────────────

  def parse_numeric_value
    raw = params[:numeric_value].presence
    return nil if raw.nil?

    Float(raw)
  rescue ArgumentError, TypeError
    nil
  end
end