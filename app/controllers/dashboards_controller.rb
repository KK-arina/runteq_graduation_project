# app/controllers/dashboards_controller.rb
# =============================================================
# ダッシュボード画面を管理するController
# ログインユーザーのホーム画面として機能する
# =============================================================

class DashboardsController < ApplicationController
  # before_action : indexアクションの前に必ずrequire_loginを実行する
  # 未ログインユーザーはログインページへリダイレクトされる
  before_action :require_login

  def index
    # -------------------------------------------------------
    # 1. 今日の「習慣記録用の日付」を取得する（AM4:00基準）
    #    例: 深夜3:59なら「昨日」、午前4:00以降なら「今日」
    # -------------------------------------------------------
    @today = HabitRecord.today_for_record

    # -------------------------------------------------------
    # 2. 今週の開始日（月曜日）を計算する
    #    beginning_of_week(:monday) : 今週の月曜日の日付を返す
    # -------------------------------------------------------
    @week_start = @today.beginning_of_week(:monday)

    # -------------------------------------------------------
    # 3. ログインユーザーの有効な習慣を一覧取得する
    #    active : deleted_atがnilの習慣だけ取得（論理削除対応）
    #    order(created_at: :desc) : 新しく作成した順に並べる
    # -------------------------------------------------------
    @habits = current_user.habits.active.order(created_at: :desc)

    # -------------------------------------------------------
    # 4. 今日の習慣記録をハッシュで一括取得（N+1問題対策）
    #    N+1問題: ループの中でDBにアクセスするとパフォーマンスが落ちる問題
    #    → @habits.count 回のクエリ発行を防ぐため、1回のクエリで全習慣分の記録を取得
    #    index_by(&:habit_id) : { habit_id => HabitRecord } 形式のハッシュに変換
    #    例: { 1 => <HabitRecord id:5>, 2 => <HabitRecord id:8> }
    # -------------------------------------------------------
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    # -------------------------------------------------------
    # 5. 今週の進捗統計を習慣ごとにハッシュで計算（N+1問題対策）
    #    each_with_object : ハッシュを作りながら各習慣の統計を格納する
    #    weekly_progress_stats(current_user) : Habitモデルのメソッド（既実装）
    #    戻り値例: { 1 => { rate: 71, completed_count: 5 }, 2 => { rate: 43, ... } }
    # -------------------------------------------------------
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    # -------------------------------------------------------
    # 6. 今週全体の達成率を計算する
    #    全習慣の達成率の平均を出す
    #    @habits.empty? の場合は 0 を返して ZeroDivisionError を防ぐ
    # -------------------------------------------------------
    @overall_rate = if @habits.empty?
      0
    else
      rates = @habit_stats.values.map { |s| s[:rate] }
      (rates.sum.to_f / rates.size).round
    end
  end
end