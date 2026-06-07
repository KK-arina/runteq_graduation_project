# app/controllers/csv_exports_controller.rb
#
# ==============================================================================
# CsvExportsController - CSVエクスポート処理を制御するコントローラー
# ==============================================================================
#
# 【Turbo と send_data の競合について】
#   Turbo が有効な状態（button_to デフォルト）で直接 send_data を返すと、
#   Turbo がレスポンスをインターセプトしてファイルが正しくダウンロードされない。
#
#   解決策: 1000件以下の即時ダウンロードも、一度トークンを生成して
#   download アクション（GETリクエスト）へ 303 See Other でリダイレクトする。
#   GETリクエストへのリダイレクトはTurboが通常のページ遷移として扱い、
#   その先の send_data がブラウザに届く。
#
#   さらに download アクションでは data-turbo="false" リンクを使うか、
#   format: :csv でリクエストすることで Turbo を完全に回避する。
#
# 【設計の一本化】
#   即時ダウンロード（1000件以下）と非同期処理（1000件超）の
#   ダウンロード処理を download アクションに一本化することで、
#   将来 ActiveStorage に切り替える際も download アクションだけ修正すればよい。
#
# ==============================================================================
class CsvExportsController < ApplicationController

  # require_login: 未ログインユーザーをログインページへリダイレクト
  before_action :require_login

  # ==============================================================================
  # habit_records（POST /settings/export_csv/habit_records）
  # ==============================================================================
  def habit_records
    export(:habit_records)
  end

  # ==============================================================================
  # tasks（POST /settings/export_csv/tasks）
  # ==============================================================================
  def tasks
    export(:tasks)
  end

  # ==============================================================================
  # weekly_reflections（POST /settings/export_csv/weekly_reflections）
  # ==============================================================================
  def weekly_reflections
    export(:weekly_reflections)
  end

  # ==============================================================================
  # download（GET /settings/download_csv?token=xxx）
  # ==============================================================================
  #
  # 【役割】
  #   1000件以下（即時）と1000件超（メールリンク）の両方のダウンロードを
  #   このアクション1つで処理する。
  #   トークンを検証してCSVを生成し、send_data でファイルを返す。
  #
  # 【なぜ GETリクエストにするのか】
  #   Turbo は GET リクエストを通常のページ遷移として扱う。
  #   そのため send_data のバイナリレスポンスがブラウザに正しく届く。
  #   POST + send_data だと Turbo がレスポンスをインターセプトして
  #   ダウンロードされない問題が発生する。
  def download
    token   = params[:token]
    payload = CsvDownloadTokenService.verify(token)

    # トークンが無効（改ざん・期限切れ・nilトークン）の場合
    if payload.nil?
      flash[:alert] = t("csv_exports.download.token_invalid")
      redirect_to settings_path, status: :see_other
      return
    end

    # トークンのuser_idとログインユーザーのIDを照合する
    # 【なぜこのチェックが必要か】
    #   AユーザーのトークンをBユーザーが使って別人のCSVを
    #   ダウンロードできてしまう（情報漏洩）を防ぐため。
    if payload["user_id"] != current_user.id
      Rails.logger.warn "[CsvExportsController#download] 不正なアクセス検知: token_user_id=#{payload['user_id']}, current_user_id=#{current_user.id}"
      flash[:alert] = t("csv_exports.download.token_invalid")
      redirect_to settings_path, status: :see_other
      return
    end

    export_type = payload["export_type"].to_sym

    service    = CsvExportService.new(user: current_user)
    csv_string = service.generate_csv(export_type)
    filename   = service.filename_for(export_type)

    # send_data について
    # 【引数の説明】
    #   csv_string    → レスポンスボディ（CSV文字列）
    #   filename:     → Content-Disposition ヘッダーのファイル名
    #   type:         → Content-Type ヘッダー（ブラウザにCSVと伝える）
    #   disposition:  → "attachment" でダウンロード（ブラウザで開かない）
    send_data csv_string,
              filename:    filename,
              type:        "text/csv; charset=utf-8",
              disposition: "attachment"
  rescue => e
    Rails.logger.error "[CsvExportsController#download] CSV生成エラー: #{e.message}"
    flash[:alert] = t("csv_exports.download.error")
    redirect_to settings_path, status: :see_other
  end

  private

  # ==============================================================================
  # export - エクスポートの共通処理
  # ==============================================================================
  #
  # 【1000件以下の即時ダウンロード設計】
  #   Turbo + send_data の競合を避けるため、
  #   即時ダウンロードもトークンを生成して download アクション（GET）へ
  #   303 See Other でリダイレクトする。
  #   303 = "POST の結果として GET リクエストで別URLを見てください" の意味。
  #   ブラウザは GET でダウンロードURLを取得し、send_data が正しく届く。
  #
  # 【1000件超のバックグラウンド処理】
  #   GoodJob にジョブを登録して非同期でCSVを生成する。
  #   Turbo Stream でボタンを「⏳ 生成中」に更新する。
  def export(export_type)
    service = CsvExportService.new(user: current_user)
    count   = service.count_for(export_type)

    if count <= CsvExportService::LARGE_DATA_THRESHOLD
      # ----------------------------------------------------------
      # 即時ダウンロード（1000件以下）
      # ----------------------------------------------------------
      #
      # 1000件以下でも download アクション経由にする理由:
      #   Turbo が有効な状態でPOSTレスポンスとして直接 send_data を返すと
      #   ブラウザにファイルが届かない（Turboがインターセプトしてしまう）。
      #   GET リダイレクト先の download アクションで send_data することで
      #   Turbo を回避してブラウザにファイルを届けられる。
      #
      # 即時ダウンロード用のトークンは有効期限を5分と短くする。
      # 【なぜ5分か】
      #   即時ダウンロードは今すぐ使うトークン。
      #   長い期限は不要でセキュリティリスクになる。
      #   バックグラウンド処理（24時間）とは別の短い期限にする。
      token = CsvDownloadTokenService.generate(
        user:        current_user,
        export_type: export_type,
        expires_in:  5.minutes
      )

      # 303 See Other でダウンロードURLへリダイレクト
      # Turbo は 303 を受け取ると GET リクエストとして追従する
      redirect_to download_csv_settings_url(token: token), status: :see_other

    else
      # ----------------------------------------------------------
      # バックグラウンド処理（1000件超）
      # ----------------------------------------------------------
      CsvExportJob.perform_later(current_user.id, export_type.to_s)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "csv_export_button_#{export_type}",
            partial: "settings/csv_export_button",
            locals:  {
              export_type: export_type,
              state:       :generating,
              label:       t("csv_exports.button.generating")
            }
          )
        end
        format.html do
          flash[:notice] = t("csv_exports.background.queued")
          redirect_to settings_path, status: :see_other
        end
      end
    end
  rescue => e
    Rails.logger.error "[CsvExportsController#export] エラー: export_type=#{export_type}, #{e.message}"
    handle_export_error(export_type)
  end

  # ==============================================================================
  # handle_export_error - エクスポートエラー時のレスポンス
  # ==============================================================================
  def handle_export_error(export_type)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "csv_export_button_#{export_type}",
          partial: "settings/csv_export_button",
          locals:  {
            export_type: export_type,
            state:       :error,
            label:       t("csv_exports.button.error")
          }
        )
      end
      format.html do
        flash[:alert] = t("csv_exports.error.general")
        redirect_to settings_path, status: :see_other
      end
    end
  end
end