# app/jobs/hello_good_job.rb
# ==============================================================================
# 【このファイルの役割】
# GoodJob が正常に動作しているかを確認するためのテスト用ジョブ。
# #A-3 の動作確認が完了したら削除してよい。
#
# 【使い方】
# Rails コンソールから以下を実行:
#   HelloGoodJob.perform_later
# → good_jobs テーブルにレコードが作成され、実行後にログが出力されれば成功
# ==============================================================================
class HelloGoodJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "========================================"
    Rails.logger.info "[HelloGoodJob] GoodJob が正常に動作しています！"
    Rails.logger.info "[HelloGoodJob] 実行時刻（JST）: #{Time.current}"
    Rails.logger.info "[HelloGoodJob] GoodJob::Job 総数: #{GoodJob::Job.count}"
    Rails.logger.info "========================================"
  end
end