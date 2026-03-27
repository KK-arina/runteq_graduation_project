# app/controllers/habit_records_controller.rb
#
# ==============================================================================
# HabitRecordsController（B-1: レビュー修正版）
# ==============================================================================
# 【レビュー指摘による修正内容】
#
#   ① parse_numeric_value を安全な Float() 変換に変更（最重要修正）
#      修正前: raw_value.to_f
#             → "abc".to_f が 0.0 になる（不正な文字列が 0 として保存される）
#      修正後: Float(raw_value) + rescue ArgumentError
#             → "abc" は nil として扱い、サーバーで弾く
#
# 【Float() と .to_f の違い（重要）】
#   "30.5".to_f  → 30.5    （OK）
#   "abc".to_f   → 0.0     （サイレントに 0 になる = バグの温床）
#   Float("30.5") → 30.5   （OK）
#   Float("abc")  → ArgumentError が発生する
#              → rescue で nil に変換 → モデルのバリデーションで弾かれる
#
# 【なぜ Controller でバリデーションするのか】
#   JS 側で min="0" や parseFloat チェックがあっても、
#   curl などで直接 HTTP リクエストを送れば不正な値が届く。
#   Controller で型変換エラーを nil に変換し、
#   モデルのバリデーション（greater_than_or_equal_to: 0）で弾く。
#   「フロント + Controller + Model」の三重防御が堅牢な設計。
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
      numeric_value: service_params[:numeric_value]
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
      numeric_value: service_params[:numeric_value]
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

  # ── parse_service_params（レビュー修正版）──────────────────────────────────
  #
  # 【役割】params から必要な値を取り出し、型変換して返す。
  #
  # 【修正ポイント: parse_numeric_value メソッドを導入】
  #   修正前: raw_value.to_f
  #           → "abc".to_f が 0.0 になるため、不正な文字列が 0 として保存される
  #   修正後: Float(raw_value) を使い、変換失敗時は nil を返す
  #           → nil はモデルのバリデーションで弾かれる（三重防御）
  def parse_service_params
    if @habit.check_type?
      {
        completed:     params[:completed] == "1",
        numeric_value: nil
      }
    else
      {
        completed:     false,
        numeric_value: parse_numeric_value
      }
    end
  end

  # parse_numeric_value
  # 【役割】params[:numeric_value] を安全に Float へ変換する。
  #
  # 【Float() と .to_f の違い】
  #   .to_f   : 変換失敗時にサイレントで 0.0 を返す（危険）
  #   Float() : 変換失敗時に ArgumentError を発生させる（安全）
  #
  # 【rescue ArgumentError, TypeError の理由】
  #   ArgumentError: "abc" など数値でない文字列が渡された場合
  #   TypeError:     nil が渡された場合（Float(nil) は TypeError を発生させる）
  #   どちらも「変換できない = 未入力扱い」として nil を返す。
  #   nil は HabitRecord モデルの numeric_value_required_for_numeric_type
  #   カスタムバリデーションでエラーになる。
  def parse_numeric_value
    raw = params[:numeric_value].presence
    return nil if raw.nil?

    Float(raw)
  rescue ArgumentError, TypeError
    # 不正な文字列（例: "abc", "30abc"）は nil として扱う
    # nil → モデルのバリデーションでエラー → クライアントに 422 が返る
    nil
  end
  # ────────────────────────────────────────────────────────────────────────────
end
