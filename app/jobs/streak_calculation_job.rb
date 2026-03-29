# app/jobs/streak_calculation_job.rb
#
# ==============================================================================
# StreakCalculationJob（B-3: ストリーク計算ジョブ 本実装）
# ==============================================================================
#
# 【このジョブの役割】
#   毎日 JST AM4:05 に全ユーザーの全習慣のストリークを計算して
#   habits.current_streak と habits.longest_streak を更新する。
#
# 【なぜ AM4:05 に実行するのか】
#   HabitFlow では AM4:00 を「1日の境界」として扱っている。
#   AM4:00 を過ぎた時点で「前日の記録」が確定するため、
#   4:05 に実行することで全ユーザーの前日分の記録が確定した後に
#   正確な値を計算できる。
#
# 【cron 設定（good_job.rb で設定済み）】
#   cron: "5 19 * * *"
#   → UTC 19:05 = JST 04:05（翌日）
#
# 【パフォーマンスへの配慮】
#   全ユーザー × 全習慣を処理するため、ユーザー数・習慣数が多いと
#   処理時間が長くなる。
#   includes(:habit_excluded_days) で N+1 を防止している。
#   将来的にユーザーが増えたら「ユーザーごとに子ジョブを分割」する設計も検討できる。
#
# ==============================================================================
class StreakCalculationJob < ApplicationJob
  # queue_as :default
  # 【理由】
  #   :default キューはすべてのジョブで共有される標準キュー。
  #   ストリーク計算は毎日1回の定期バッチなので
  #   AI分析などの優先度高ジョブと同じキューで問題ない。
  queue_as :default

  def perform
    Rails.logger.info "[StreakCalculationJob] 開始: #{Time.current}"

    # ── 基準日の取得 ─────────────────────────────────────────────────────
    #
    # HabitRecord.today_for_record
    #   AM4:00 境界を考慮した「今日の日付」を返す。
    #   このジョブは AM4:05 に実行されるため、
    #   today_for_record は「今日（AM4:00 以降）」の日付になる。
    reference_date = HabitRecord.today_for_record
    Rails.logger.info "[StreakCalculationJob] 基準日: #{reference_date}"

    # ── 処理対象習慣の取得 ────────────────────────────────────────────────
    #
    # Habit.active: 論理削除されていない習慣のみ対象
    # includes(:habit_excluded_days): N+1 防止
    #   calculate_streak! 内で excluded_day_numbers が habit_excluded_days を参照するため
    #   includes で一括取得する。
    # includes(:user => :user_setting): N+1 防止
    #   on_rest_mode? が user.user_setting を参照するため一括取得する。
    habits = Habit.active
                  .includes(:habit_excluded_days)
                  .includes(user: :user_setting)

    success_count = 0
    error_count   = 0

    habits.find_each do |habit|
      # find_each とは:
      #   大量レコードを一括ロードせず 1000 件ずつバッチ処理するメソッド。
      #   each だと全レコードをメモリに載せるが、
      #   find_each はバッチ分割して処理するためメモリ効率が良い。

      habit.calculate_streak!(reference_date)
      success_count += 1

    rescue => e
      # 個別習慣の計算エラーは全体を止めずにスキップする
      # 1つの習慣のエラーが原因でジョブ全体が失敗するのを防ぐ
      error_count += 1
      Rails.logger.error "[StreakCalculationJob] 習慣ID=#{habit.id} エラー: #{e.message}"
      Rails.logger.error e.backtrace&.first(3)&.join("\n")
    end

    Rails.logger.info "[StreakCalculationJob] 完了: 成功=#{success_count}, エラー=#{error_count}, 基準日=#{reference_date}"
  end
end