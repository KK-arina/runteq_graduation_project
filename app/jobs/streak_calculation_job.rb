# ==============================================================================
# app/jobs/streak_calculation_job.rb
# ==============================================================================
#
# 【このジョブの役割】
# 毎日 JST AM4:05 に全ユーザーの「ストリーク（連続達成日数）」を計算して
# habits.current_streak と habits.longest_streak を更新する。
#
# 【ストリークとは】
# 習慣を連続して達成した日数のこと。
# 例: 月〜金の5日間連続で「読書」を達成 → ストリーク = 5
#
# 【なぜ AM4:05 に実行するのか】
# HabitFlow では「AM4:00 を1日の境界」として扱っている。
# AM4:00 を過ぎた時点で「昨日の記録」が確定する。
# 4:05 に実行することで前日分の記録がすべて確定した後に計算できる。
#
# 【Issue #B-3 との関係】
# 本格的なストリーク計算ロジックは Issue #B-3 で実装する。
# このファイルは #A-3 の段階では「GoodJob の cron 設定確認用」として
# 最小限の実装にとどめ、#B-3 で内容を充実させる。
# ==============================================================================
class StreakCalculationJob < ApplicationJob
  # キュー名の設定
  # :default → GoodJob が管理する「default」キューに積まれる
  # キューを分けると「AI分析は高優先度」「バッチは低優先度」のように
  # 優先度を制御できる。現時点はすべて :default で統一。
  queue_as :default

  def perform
    # ログに実行記録を残す
    # Rails.logger は本番では Render の Logs タブに出力される
    Rails.logger.info "[StreakCalculationJob] 開始: #{Time.current}"

    # -------------------------------------------------------------------
    # 本実装は Issue #B-3 で行う
    # -------------------------------------------------------------------
    # Issue #B-3 では以下を実装予定:
    # - Habit モデルの streak 計算メソッドを呼び出す
    # - AM4:00 基準で「昨日達成したか」を判定
    # - 除外日（habit_excluded_days）を考慮した計算
    # - お休みモード（allow_rest_mode）中はストリークを維持
    # - habits.current_streak と habits.longest_streak を更新
    #
    # 現時点では処理の存在確認のみ実施する
    habit_count = Habit.where(deleted_at: nil).count
    Rails.logger.info "[StreakCalculationJob] 対象習慣数: #{habit_count}"
    Rails.logger.info "[StreakCalculationJob] 完了（#B-3 実装待ち）: #{Time.current}"
  end
end