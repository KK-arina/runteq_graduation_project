# app/mailers/csv_export_mailer.rb
#
# ==============================================================================
# CsvExportMailer - CSVエクスポート完了通知メイラー
# ==============================================================================
#
# 【このメイラーの役割】
#   1000件超のCSVがバックグラウンドで生成完了したとき、
#   ユーザーにダウンロードURLをメールで通知する。
#
# 【ApplicationMailer を継承する理由】
#   from アドレスなどの共通設定を自動で引き継ぐ（DRY原則）。
#   全メイラーで同じ from 設定を繰り返し書く必要がない。
# ==============================================================================
class CsvExportMailer < ApplicationMailer

  # helper :application を明示する理由:
  # WeeklyReportMailer と同様に ApplicationHelper のメソッドを
  # ビューテンプレートで使えるようにするため。
  helper :application

  # ==============================================================================
  # ready - CSV生成完了通知メール
  # ==============================================================================
  #
  # 【引数】
  #   user:         Userインスタンス（メール送信先）
  #   download_url: 24時間有効なダウンロードURL（文字列）
  #   filename:     CSVファイル名（例: "habitflow_habit_records_20260101_120000.csv"）
  #   export_type:  "habit_records" / "tasks" / "weekly_reflections"（文字列）
  def ready(user:, download_url:, filename:, export_type:)
    # ビューで使用するインスタンス変数をセット
    # 【@ を付ける理由】
    #   Railsのメイラーはコントローラーと同じ仕組みで、
    #   インスタンス変数（@xxx）をビューから自動参照できる。
    @user         = user
    @download_url = download_url
    @filename     = filename
    # export_type の日本語ラベル変換
    # ビューで "習慣記録" のように表示するために変換する。
    @export_label = export_type_label(export_type)

    mail(
      to:      @user.email,
      subject: "【HabitFlow】#{@export_label}のCSVファイルが生成されました"
    )
  end

  private

  # export_type の日本語ラベルを返す
  def export_type_label(export_type)
    case export_type.to_s
    when "habit_records"      then "習慣記録"
    when "tasks"              then "タスク"
    when "weekly_reflections" then "週次振り返り"
    else "データ"
    end
  end
end