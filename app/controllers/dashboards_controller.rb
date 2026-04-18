# app/controllers/dashboards_controller.rb
#
# ==============================================================================
# DashboardsController
# ==============================================================================
# 【変更履歴】
#   B-2: @habits 取得時に includes(:habit_excluded_days) を追加（N+1防止）
#        build_habit_stats のチェック型の分母を effective_weekly_target に変更
#   C-1: @today_tasks（今日が期限のタスク最大5件）を追加
#   C-6: @task_priority_stats（Must/Should/Could 別の週次達成率）を追加
#        今週（月曜〜今日）のタスクを優先度別に集計し、達成率を計算する
# ==============================================================================

class DashboardsController < ApplicationController
  # ログインしていないユーザーはアクセスできないように制限する
  before_action :require_login

  def index
    @today      = HabitRecord.today_for_record
    @week_start = @today.beginning_of_week(:monday)

    # ── 習慣データの取得 ────────────────────────────────────────────────
    # includes(:habit_excluded_days) により、除外日データを一括で読み込む。
    # これがないと habit.effective_weekly_target を呼ぶたびに
    # habit_excluded_days への SELECT が発行される（N+1問題）。
    @habits = current_user.habits.active
                          .includes(:habit_excluded_days)
                          .order(created_at: :desc)

    # 今日の記録をハッシュ化して高速参照できるようにする。
    # index_by(&:habit_id) により { habit_id => HabitRecord } の形になる。
    # ビューで @today_records_hash[habit.id] と O(1) で参照できる。
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    @habit_stats = build_habit_stats(@habits, current_user)

    # 全習慣の達成率の平均を全体達成率として計算する。
    # 習慣が0件のときは 0 を返す（0除算を防ぐ）。
    @overall_rate = @habits.empty? ? 0 :
      (@habit_stats.values.map { |s| s[:rate] }.sum.to_f / @habit_stats.size).round

    @locked = locked?

    # ── C-1: 今日のタスク ────────────────────────────────────────────────
    # 今日が期限（due_date = 今日）のタスクを最大5件取得する。
    # .active       → deleted_at が nil のもの（論理削除されていないもの）。
    # .not_archived → status が archived のものを除く。
    # .today        → due_date が AM4:00基準の「今日」に一致するもの。
    # .order(priority: :asc) → must(0) → should(1) → could(2) の重要度順。
    # .limit(5) → ダッシュボードには最大5件のみ表示する（画面の見やすさのため）。
    @today_tasks = current_user.tasks
                               .active
                               .not_archived
                               .today
                               .order(priority: :asc)
                               .limit(5)

    # ── C-6: Must/Should/Could 別の週次タスク達成率 ──────────────────────
    # ダッシュボードに優先度別のプログレスバーを表示するための統計データを計算する。
    # 計算ロジックは build_task_priority_stats メソッドに切り出して見通しをよくする。
    #
    # @task_priority_stats の構造（例）:
    #   {
    #     "must"   => { total: 3, done: 2, rate: 66 },
    #     "should" => { total: 5, done: 5, rate: 100 },
    #     "could"  => { total: 0, done: 0, rate: 0 }
    #   }
    @task_priority_stats = build_task_priority_stats(current_user)
  end

  private

  # ============================================================
  # C-6: build_task_priority_stats（タイムゾーン修正版）
  # ============================================================
  # 今週（月曜〜今日）の削除されていないタスクを優先度別に集計し、
  # 達成率（done件数 / 総件数 × 100）を返す。
  #
  # 【N+1を起こさない設計（2クエリのみ）】
  #   1回目: group(:priority).count → 全タスクの優先度別件数
  #   2回目: group(:priority).count → done + archived のみの件数
  #   ループの中でDBを叩かないため、タスクが何件あっても常に2クエリで済む。
  #
  # 【タイムゾーン修正のポイント】
  #   HabitRecord.today_for_record は Date 型を返す。
  #   Date 型に対して .beginning_of_day / .end_of_day を呼ぶと、
  #   ActiveSupport の Date 拡張により Time.zone 基準の時刻になるが、
  #   PostgreSQL に渡るとき UTC 変換がかかる。
  #
  #   created_at（datetime型）との BETWEEN 比較を正確にするため、
  #   .in_time_zone.beginning_of_day / .end_of_day で
  #   明示的に JST 基準の Time オブジェクトに変換してから渡す。
  #
  #   due_date（date型）は文字列 "YYYY-MM-DD" として DB に保存されているため
  #   Date 型のまま渡して問題ない（タイムゾーン変換不要）。
  #
  # 【引数】
  #   user: current_user（User インスタンス）
  #
  # 【戻り値】
  #   Hash（キー: "must" / "should" / "could"）
  #   各値は { total:, done:, rate: } のハッシュ
  def build_task_priority_stats(user)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)

    # created_at（datetime型）との BETWEEN 比較を正確にするため
    # Date 型を in_time_zone 経由で JST 基準の Time 型に変換する。
    # Date#beginning_of_day / end_of_day をそのまま使うと
    # UTC 変換がズレる場合があるため、明示的に in_time_zone を挟む。
    week_start_time = week_start.in_time_zone.beginning_of_day
    today_end_time  = today.in_time_zone.end_of_day

    # 今週（月曜〜今日）に関係するタスクを絞り込む。
    # .active: deleted_at が nil のタスクのみ。
    # BETWEEN OR 条件: 今週作成 または 今週期限 のどちらかを対象にする。
    base_scope = user.tasks
                     .active
                     .where(
                       "(created_at BETWEEN :start AND :end_time) OR (due_date BETWEEN :due_start AND :due_end)",
                       start:     week_start_time,
                       end_time:  today_end_time,
                       due_start: week_start,
                       due_end:   today
                     )

    # ── 優先度別の総件数を1クエリで取得する ──────────────────────────
    # Rails の enum を使ったカラムを group(:priority).count すると
    # キーは整数（0/1/2）ではなく enum 名の文字列（"must"/"should"/"could"）で返る。
    # 例: { "must" => 3, "should" => 5 }
    # そのため priority_map による整数→文字列変換は不要。
    # 直接 total_counts["must"] のようにアクセスできる。
    total_counts = base_scope.unscope(:order).group(:priority).count

    # ── 優先度別の完了件数を1クエリで取得する ────────────────────────
    # done と archived の両方を「完了」として扱う。
    # archived は「done 後に整理したもの」なので達成実績に含める。
    done_counts = base_scope.unscope(:order)
                            .where(status: [ Task.statuses[:done], Task.statuses[:archived] ])
                            .group(:priority)
                            .count

    # ── 優先度ごとの達成率を計算してハッシュにまとめる ────────────────
    # group(:priority).count のキーが文字列（"must"等）で返るため
    # transform_keys による変換は不要。直接キー名でアクセスする。
    # %w[must should could]: 3種類の優先度を文字列の配列で定義する。
    # each_with_object({}): 空のハッシュに順番に詰めていくイディオム。
    %w[must should could].each_with_object({}) do |priority_name, result|
      total = total_counts[priority_name] || 0
      done  = done_counts[priority_name]  || 0

      # total が 0 なら 0 を返す（0除算を防ぐ）。
      # .clamp(0, 100): 万が一100%を超えた場合も100に収める安全策。
      # .floor: 小数点以下を切り捨てる（66.7% → 66%）。
      rate = total.zero? ? 0 : ((done.to_f / total) * 100).clamp(0, 100).floor

      result[priority_name] = { total: total, done: done, rate: rate }
    end
  end

  # ============================================================
  # build_habit_stats（B-2: 除外日対応。C-6では変更なし）
  # ============================================================
  # 習慣ごとの今週の達成率を計算する。
  # タスクの集計は build_task_priority_stats で行うため、
  # このメソッドは習慣のみを対象とする（変更なし）。
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
        # B-2: 分母を effective_weekly_target（除外日考慮後の実施予定日数）に変更
        target          = habit.effective_weekly_target
        completed_count = check_counts[habit.id] || 0
        rate = target.zero? ? 0 :
          ((completed_count.to_f / target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: completed_count, numeric_sum: nil,
                           effective_target: target }
      else
        numeric_sum = (numeric_sums[habit.id] || 0).to_f
        rate = habit.weekly_target.zero? ? 0 :
          ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: nil, numeric_sum: numeric_sum,
                           effective_target: habit.weekly_target }
      end
    end
  end
end