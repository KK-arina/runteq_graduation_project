# app/controllers/dashboards_controller.rb
#
# ダッシュボード画面を表示するコントローラーです。
# ログイン後に最初に表示されるメインページです。
# 今週の習慣達成率と今日の習慣チェックリストを表示します。

class DashboardsController < ApplicationController
  # ============================================================
  # before_action
  # ============================================================

  # ログインしていないユーザーはダッシュボードを見られません。
  # ApplicationController で定義した require_login を使います。
  before_action :require_login

  # ============================================================
  # GET /dashboard
  # ============================================================
  def index
    # AM4:00 基準の「今日」を取得します。
    # 例: 深夜3:59 → 昨日の日付 / AM4:00以降 → 今日の日付
    @today = HabitRecord.today_for_record

    # 今週の月曜日を取得します（週次進捗の計算起点）。
    @week_start = @today.beginning_of_week(:monday)

    # 現在のユーザーの有効な習慣を取得します。
    # active: deleted_at が nil のもの
    # order: 新しい順
    @habits = current_user.habits.active.order(created_at: :desc)

    # N+1対策①: 今日の記録を1クエリで一括取得
    # { habit_id => HabitRecord } のハッシュ形式にします。
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    # N+1対策②: 全習慣の週次統計を事前計算
    # { habit_id => { rate: 整数, completed_count: 整数 } } のハッシュ形式にします。
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    # 全体達成率: 全習慣の rate の平均値（小数点以下は四捨五入）
    # @habits が空の場合は 0 を返します。
    @overall_rate = @habits.empty? ? 0 :
      (@habit_stats.values.map { |s| s[:rate] }.sum.to_f / @habit_stats.size).round

    # ロック状態をインスタンス変数に格納します。
    # ビューで @locked を参照して警告バナーの表示/非表示を制御します。
    # locked? は ApplicationController で定義したメソッドです。
    @locked = locked?
  end
end