# app/jobs/csv_export_job.rb
#
# ==============================================================================
# CsvExportJob - 大量データのCSVをバックグラウンドで生成してメール通知するジョブ
# ==============================================================================
#
# 【このジョブが実行される条件】
#   エクスポート対象データが 1000件を超えた場合に
#   CsvExportsController から perform_later で非同期実行される。
#
# 【処理の流れ】
#   1. ユーザーとメールアドレスの確認
#   2. CsvExportService でCSV文字列を生成する
#   3. CsvDownloadTokenService でダウンロードURLを生成する（24時間有効）
#   4. CsvExportMailer でユーザーにメール通知する
#
# ==============================================================================
class CsvExportJob < ApplicationJob
  queue_as :default

  # 対象レコードが削除された場合はリトライしても無意味なため即座に破棄する
  discard_on ActiveRecord::RecordNotFound

  # ==============================================================================
  # perform - ジョブのメイン処理
  # ==============================================================================
  #
  # 【引数】
  #   user_id:     CSVを要求したユーザーのID（整数）
  #   export_type: "habit_records" / "tasks" / "weekly_reflections"（文字列）
  def perform(user_id, export_type)
    Rails.logger.info "[CsvExportJob] 開始: user_id=#{user_id}, export_type=#{export_type}"

    user = User.find(user_id)

    # ----------------------------------------------------------
    # メールアドレスのnilチェック
    # ----------------------------------------------------------
    #
    # 【なぜこのチェックが必要か】
    #   LINEログインユーザーは email が nil の場合がある（User モデルの仕様）。
    #   email が nil の状態でメール送信すると ActionMailer がエラーになる。
    #   設定ページでも「未設定（LINEログイン）」と表示していることからも
    #   このケースは明示的にハンドリングする必要がある。
    #
    # 【なぜジョブを停止してエラーにしないのか】
    #   emailがないユーザーへのCSV通知は「そもそも送れない」ため
    #   リトライしても意味がない。ログだけ残して正常終了する。
    if user.email.blank?
      Rails.logger.warn "[CsvExportJob] emailが未設定のためメール送信をスキップ: user_id=#{user_id}"
      return
    end

    # CSV文字列とファイル名を生成する
    service    = CsvExportService.new(user: user)
    csv_string = service.generate_csv(export_type.to_sym)
    filename   = service.filename_for(export_type.to_sym)

    Rails.logger.info "[CsvExportJob] CSV生成完了: #{filename}, #{csv_string.bytesize} bytes"

    # ダウンロード用トークンを生成する（24時間有効）
    token = CsvDownloadTokenService.generate(
      user:        user,
      export_type: export_type,
      expires_in:  24.hours
    )

    # ダウンロードURLを組み立てる
    # 【ジョブ内でURLヘルパーを使うための設定】
    #   ジョブはHTTPリクエストのコンテキスト外で実行されるため
    #   config/environments/production.rb の default_url_options を参照する。
    # action_mailer.default_url_options をそのまま展開して使う
    # 【なぜ **mailer_url_options で展開するのか】
    #   development.rb: { host: "localhost", port: 3000 }
    #   production.rb:  { host: "habitflow-web.onrender.com", protocol: "https" }
    #   環境ごとの設定をそのまま使うことで環境差異がなくなる。
    #   以前は protocol のデフォルトを "https" にしていたため
    #   開発環境で https://localhost/... という不正なURLが生成されていた。
    mailer_url_options = Rails.application.config.action_mailer.default_url_options || {}
    download_url = Rails.application.routes.url_helpers.download_csv_settings_url(
      token: token,
      **mailer_url_options
    )

    # メール送信（deliver_now: ジョブ内なので同期送信）
    CsvExportMailer.ready(
      user:         user,
      download_url: download_url,
      filename:     filename,
      export_type:  export_type
    ).deliver_now

    Rails.logger.info "[CsvExportJob] メール送信完了: user_id=#{user_id}"
  rescue => e
    Rails.logger.error "[CsvExportJob] エラー: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end
end