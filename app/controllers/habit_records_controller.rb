# app/controllers/habit_records_controller.rb
#
# =============================================================
# 【このファイルの役割】
# 習慣の日次記録（HabitRecord）を管理するController。
# =============================================================
#
# 【Issue #A-7 での変更箇所】
#   create / update アクションのビジネスロジックを
#   HabitRecordSaveService に委譲するように変更。
#
#   変更前: コントローラーが find_or_create_for / update_completed! を
#           直接呼んでいた。
#   変更後: HabitRecordSaveService.new(...).call を呼ぶだけ。
#           ストリーク更新が Issue #B-3 で追加されても
#           コントローラーを変更する必要がなくなる。

class HabitRecordsController < ApplicationController
  before_action :require_login
  before_action :set_habit

  # ============================================================
  # POST /habits/:habit_id/habit_records
  # ============================================================
  def create
    # ── Issue #A-7: サービスクラスに委譲 ─────────────────────────
    # params[:completed] == "1"
    # → チェックボックスが ON のとき "1" が送られてくる（HTML の仕様）
    # → == "1" で true/false の Boolean に変換してサービスに渡す
    result = HabitRecordSaveService.new(
      user:      current_user,
      habit:     @habit,
      completed: params[:completed] == "1"
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
      # サービスから失敗が返ってきた場合
      Rails.logger.error "HabitRecordSaveService failed: #{result[:error]}"
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to dashboard_path, alert: "記録の保存に失敗しました" }
      end
    end
  end

  # ============================================================
  # PATCH /habits/:habit_id/habit_records/:id
  # ============================================================
  def update
    @habit_record = current_user.habit_records.find(params[:id])

    # クロス習慣アクセスのチェック（Issue #41 から継続）
    unless @habit_record.habit_id == @habit.id
      render_404 and return
    end

    # ── Issue #A-7: サービスクラスに委譲 ─────────────────────────
    # 既存レコードが存在する場合の更新もサービス経由で行う。
    # HabitRecordSaveService は find_or_create_for を使うため、
    # 既存レコードが存在する場合は find して update する。
    result = HabitRecordSaveService.new(
      user:      current_user,
      habit:     @habit,
      completed: params[:completed] == "1"
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
      Rails.logger.error "HabitRecordSaveService failed: #{result[:error]}"
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to dashboard_path, alert: "記録の更新に失敗しました" }
      end
    end
  end

  private

  def set_habit
    @habit = current_user.habits.active.find(params[:habit_id])
  rescue ActiveRecord::RecordNotFound
    head :not_found and return
  end
end