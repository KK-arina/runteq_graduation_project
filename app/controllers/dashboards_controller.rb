# app/controllers/dashboards_controller.rb
#
# ダッシュボード画面を表示するコントローラーです。
# ログイン後に最初に表示されるメインページです。
# 今週の習慣達成率と今日の習慣チェックリストを表示します。
#
# 【Issue #42 修正点】
#   @habit_stats の計算を N+1 対策済みの方式に変更。
#   weekly_progress_stats のループから build_habit_stats（GROUP BY）に変更。
#   HabitsController / WeeklyReflectionsController と同じ方式に統一。
class DashboardsController < ApplicationController
  before_action :require_login

  def index
    # AM4:00 基準の「今日」を取得します。
    @today = HabitRecord.today_for_record
    # 今週の月曜日を取得します。
    @week_start = @today.beginning_of_week(:monday)
    # 有効な習慣を新しい順に取得します。
    @habits = current_user.habits.active.order(created_at: :desc)

    # N+1対策①: 今日の記録を1クエリで一括取得します。
    # index_by で { habit_id => HabitRecord } のハッシュに変換します。
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    # N+1対策②: 週次進捗を GROUP BY で一括集計します。
    # 【修正前】habit.weekly_progress_stats を習慣の数だけ呼ぶ（N+1問題）
    #   → 習慣が N件あると habit_records への SQL が N回発行される
    # 【修正後】build_habit_stats で GROUP BY を使った1回のSQLに集約する
    #   → HabitsController / WeeklyReflectionsController と同じ方式に統一
    #   → SQL は habits 取得1回 + records 集計1回 = 計2回で完結する
    @habit_stats = build_habit_stats(@habits, current_user)

    # 全体達成率: 全習慣の rate の平均値（小数点以下は四捨五入）。
    @overall_rate = @habits.empty? ? 0 :
      (@habit_stats.values.map { |s| s[:rate] }.sum.to_f / @habit_stats.size).round

    # ロック状態をインスタンス変数に格納します。
    @locked = locked?
  end

  private

  # build_habit_stats
  # 習慣ごとの今週の進捗率を GROUP BY で一括集計して返します。
  # HabitsController / WeeklyReflectionsController と同じロジックです。
  # 将来的には ApplicationController か Concern に切り出すことを推奨します。
  #
  # 戻り値: { habit_id => { rate: Integer(0〜100), completed_count: Integer } }
  def build_habit_stats(habits, user)
    # AM4:00基準で今週の日付範囲を計算します。
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    # DB側で GROUP BY を使って集計します（ActiveRecordオブジェクトを生成しない）。
    # SQL: SELECT habit_id, COUNT(*) FROM habit_records WHERE ... GROUP BY habit_id
    # 戻り値: { habit_id => count } の軽量なHash。
    records_count_by_habit = HabitRecord
      .where(user: user, habit: habits, record_date: week_range, completed: true)
      .group(:habit_id)
      .count

    # 各習慣の達成率をメモリ上で計算します（DB アクセスゼロ）。
    habits.each_with_object({}) do |habit, hash|
      # 今週1件も完了がない習慣はHashにキーがないため nil → 0 扱い。
      completed_count = records_count_by_habit[habit.id] || 0

      # ゼロ除算ガード（バリデーションで1以上が保証されているが念のため）。
      rate = if habit.weekly_target.zero?
               0
             else
               # .to_f: 整数同士の割り算で小数が切り捨てられるのを防ぐ。
               # .clamp(0, 100): 目標超過時でも100%を上限にする。
               # .floor: 小数点以下を切り捨てて整数にする。
               ((completed_count.to_f / habit.weekly_target) * 100)
                 .clamp(0, 100)
                 .floor
             end

      hash[habit.id] = { rate: rate, completed_count: completed_count }
    end
  end
end
