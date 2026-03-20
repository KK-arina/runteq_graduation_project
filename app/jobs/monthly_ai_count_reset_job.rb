# ==============================================================================
# app/jobs/monthly_ai_count_reset_job.rb
# ==============================================================================
#
# 【このジョブの役割】
# 毎月 1 日の JST 00:00 に user_settings.ai_analysis_count を 0 にリセットする。
#
# 【ai_analysis_count とは】
# ユーザーが当月に AI 分析を実行した回数。
# user_settings.ai_analysis_monthly_limit（デフォルト: 10）に達すると
# その月はそれ以上 AI 分析を実行できなくなる（コスト制御）。
# 月初になったらカウンターを 0 に戻す。
#
# 【なぜ毎日実行してジョブ内でチェックするのか】
# cron で「毎月1日」を UTC で正確に指定すると複雑になるため、
# 毎日 JST 00:00 に実行し、ジョブ内で「今日が1日か」を確認してからリセットする。
# この方式の利点:
# - cron 式がシンプルになる
# - タイムゾーンのズレでリセットが翌日に回ることを防げる
# - ジョブ自体のテストが書きやすい（引数で日付を渡せる）
# ==============================================================================
class MonthlyAiCountResetJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[MonthlyAiCountResetJob] 開始: #{Time.current}"

    # Time.current は config.time_zone = "Tokyo" により常に JST で返る
    today = Time.current

    # 月初（1日）でない場合は何もしない
    # この判定により「毎日実行」しても月初以外は空振りになる
    unless today.day == 1
      Rails.logger.info "[MonthlyAiCountResetJob] 今日は月初ではないためスキップ（#{today.strftime('%Y-%m-%d')}）"
      return
    end

    # 月初の場合: 全ユーザーの ai_analysis_count を 0 にリセット
    # update_all で1クエリにまとめて高速処理する
    reset_count = UserSetting.update_all(ai_analysis_count: 0)

    Rails.logger.info "[MonthlyAiCountResetJob] 月次リセット完了: #{reset_count} 件 (#{today.strftime('%Y年%m月')}分)"
  end
end