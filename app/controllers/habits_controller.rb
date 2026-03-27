# app/controllers/habits_controller.rb
#
# ==============================================================================
# HabitsController（B-1: 数値型習慣対応）
# ==============================================================================
# 【B-1 での変更内容】
#   ① habit_params に :unit と :measurement_type を追加
#      （数値型習慣の作成に unit と measurement_type が必要）
#
#   ② build_habit_stats を数値型対応に更新
#      （DashboardsController と同じロジックを適用）
#
# 【将来の課題】
#   build_habit_stats は HabitsController と DashboardsController に
#   同じコードが重複している。Issue #H-9 などで ApplicationController か
#   Concern に切り出すことを推奨する。
# ==============================================================================

class HabitsController < ApplicationController
  before_action :require_login
  before_action :require_unlocked, only: [ :create, :destroy ]
  before_action :set_habit, only: [ :destroy ]

  # ============================================================
  # GET /habits
  # ============================================================
  def index
    @habits = current_user.habits.active.order(created_at: :desc)

    today = HabitRecord.today_for_record
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: today)
      .index_by(&:habit_id)

    @habit_stats = build_habit_stats(@habits, current_user)
    @locked      = locked?
  end

  # ============================================================
  # GET /habits/new
  # ============================================================
  def new
    @habit = current_user.habits.build
  end

  # ============================================================
  # POST /habits
  # ============================================================
  def create
    @habit = current_user.habits.build(habit_params)

    if @habit.save
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の登録に失敗しました"
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # DELETE /habits/:id
  # ============================================================
  def destroy
    if @habit.soft_delete
      flash[:notice] = "習慣を削除しました"
      redirect_to habits_path, status: :see_other
    else
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # habit_params（B-1 で :unit と :measurement_type を追加）
  # 【Strong Parameters】
  #   フォームから送られるパラメータのうち許可するものをホワイトリストで指定する。
  #
  # 【B-1 で追加した理由】
  #   :measurement_type → 数値型かチェック型かを保存するために必要
  #   :unit             → 数値型習慣の単位（例: 分、冊）を保存するために必要
  def habit_params
    params.require(:habit).permit(:name, :weekly_target, :measurement_type, :unit)
  end

  # set_habit: destroy の前に @habit をセットする
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end

  # build_habit_stats（B-1 で数値型対応に更新）
  # DashboardsController と同じロジック（将来的に Concern に切り出し予定）
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
