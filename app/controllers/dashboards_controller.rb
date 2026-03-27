# app/controllers/dashboards_controller.rb
#
# ==============================================================================
# DashboardsController（B-1: 数値型習慣対応）
# ==============================================================================
# 【B-1 での変更内容】
#   ① build_habit_stats を数値型対応に更新
#      - チェック型: GROUP BY + COUNT で完了日数を集計（従来通り）
#      - 数値型:    GROUP BY + SUM で numeric_value を集計（B-1 追加）
#
# 【N+1問題への対応（既存通り）】
#   @today_records_hash : 1クエリで一括取得（index_by でハッシュ化）
#   @habit_stats        : GROUP BY で一括集計（habits × SQL N+1 を防ぐ）
# ==============================================================================

class DashboardsController < ApplicationController
  before_action :require_login

  def index
    # AM4:00 基準の「今日」を取得する
    @today      = HabitRecord.today_for_record
    # 今週の月曜日を取得する
    @week_start = @today.beginning_of_week(:monday)
    # 有効な習慣を作成日時の新しい順に取得する
    @habits     = current_user.habits.active.order(created_at: :desc)

    # N+1対策①: 今日の記録を1クエリで一括取得する
    # WHERE user_id=? AND habit_id IN(?) AND record_date=? の SQL が1回だけ発行される。
    # index_by(&:habit_id): 配列を { habit_id => HabitRecord } のハッシュに変換する。
    # ビューで @today_records_hash[habit.id] とアクセスできるため N+1 が起きない。
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    # N+1対策②: 週次進捗を GROUP BY で一括集計する
    # build_habit_stats の詳細は private メソッドのコメントを参照。
    @habit_stats = build_habit_stats(@habits, current_user)

    # 全体達成率: 全習慣の rate の平均値（小数点以下は四捨五入）
    @overall_rate = @habits.empty? ? 0 :
      (@habit_stats.values.map { |s| s[:rate] }.sum.to_f / @habit_stats.size).round

    # ロック状態をインスタンス変数に格納する（ビューで @locked を参照する）
    @locked = locked?
  end

  private

  # build_habit_stats（B-1 で数値型対応に更新）
  # 【役割】習慣ごとの今週の進捗率を一括集計して返す。
  #
  # 【B-1 での変更点】
  #   チェック型と数値型で集計方法が異なるため、
  #   ① チェック型の習慣 ID だけを抽出して COUNT 集計
  #   ② 数値型の習慣 ID だけを抽出して SUM 集計
  #   という2種類のクエリを発行する（それでも合計 3クエリで完結）。
  #
  # 【SQL クエリの流れ】
  #   SQL1: SELECT * FROM habits WHERE ...（@habits の取得。index アクションで実行済み）
  #   SQL2: SELECT habit_id, COUNT(*) FROM habit_records
  #         WHERE completed=true AND habit_id IN (チェック型IDリスト) ...
  #         GROUP BY habit_id
  #   SQL3: SELECT habit_id, SUM(numeric_value) FROM habit_records
  #         WHERE habit_id IN (数値型IDリスト) ...
  #         GROUP BY habit_id
  #
  # 【戻り値】
  #   Hash: { habit_id => { rate: Integer(0〜100), completed_count: Integer/nil, numeric_sum: Float/nil } }
  def build_habit_stats(habits, user)
    # 今週の日付範囲を計算する（AM4:00 基準）
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    # ── チェック型と数値型の習慣 ID をそれぞれ取得する ──────────────────────
    #
    # select は Rails の Enumerable メソッド（SQL の SELECT ではなく Ruby のフィルタ）。
    # 習慣リストをフィルタして、それぞれのタイプの ID リストを作る。
    # .map(&:id) で ID の配列を取得する。
    check_habit_ids   = habits.select(&:check_type?).map(&:id)
    numeric_habit_ids = habits.select(&:numeric_type?).map(&:id)
    # ────────────────────────────────────────────────────────────────────────

    # ── チェック型: GROUP BY + COUNT で完了日数を集計 ────────────────────────
    #
    # check_habit_ids が空の場合は SQL を発行せず空ハッシュを返す（無駄なクエリを防ぐ）。
    # .group(:habit_id).count の戻り値は { habit_id => count } の Hash。
    check_counts = if check_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: check_habit_ids, record_date: week_range, completed: true)
        .group(:habit_id)
        .count
    else
      {}
    end
    # ────────────────────────────────────────────────────────────────────────

    # ── 数値型: GROUP BY + SUM で numeric_value を集計 ───────────────────────
    #
    # .where(deleted_at: nil) → 論理削除された記録は除外する
    # .group(:habit_id).sum(:numeric_value) の戻り値は { habit_id => BigDecimal } の Hash。
    numeric_sums = if numeric_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: numeric_habit_ids, record_date: week_range, deleted_at: nil)
        .group(:habit_id)
        .sum(:numeric_value)
    else
      {}
    end
    # ────────────────────────────────────────────────────────────────────────

    # ── 各習慣の進捗率をメモリ上で計算する（DB アクセスなし）──────────────
    habits.each_with_object({}) do |habit, hash|
      if habit.check_type?
        # チェック型の達成率計算
        completed_count = check_counts[habit.id] || 0
        rate = if habit.weekly_target.zero?
          0
        else
          ((completed_count.to_f / habit.weekly_target) * 100).clamp(0, 100).floor
        end
        hash[habit.id] = { rate: rate, completed_count: completed_count, numeric_sum: nil }

      else
        # 数値型の達成率計算
        # BigDecimal → Float に変換する（一貫した型を保つため）
        numeric_sum = (numeric_sums[habit.id] || 0).to_f
        rate = if habit.weekly_target.zero?
          0
        else
          ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
        end
        hash[habit.id] = { rate: rate, completed_count: nil, numeric_sum: numeric_sum }
      end
    end
    # ────────────────────────────────────────────────────────────────────────
  end
end