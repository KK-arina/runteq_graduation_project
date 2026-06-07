# app/helpers/settings_helper.rb
#
# ==============================================================================
# SettingsHelper - 設定ページ関連のビューヘルパー
# ==============================================================================
#
# 【このヘルパーの役割】
#   設定ページ（settings/show.html.erb）や
#   CSVエクスポートボタンパーシャル（settings/_csv_export_button.html.erb）で
#   使うヘルパーメソッドを定義する。
#
# 【なぜ ApplicationHelper ではなく SettingsHelper にするのか】
#   ApplicationHelper は全コントローラー・全ビューで読み込まれる。
#   CSVエクスポート専用の export_path_for メソッドを
#   全ビューに公開する必要はないため、スコープを SettingsHelper に限定する。
#   SettingsHelper は SettingsController のビューとその配下のパーシャルで使われる。
#
# ==============================================================================
module SettingsHelper

  # ==============================================================================
  # export_path_for(export_type) - エクスポート種別に対応するパスを返す
  # ==============================================================================
  #
  # 【役割】
  #   _csv_export_button.html.erb パーシャルで button_to の action に使う。
  #   export_type シンボルから対応するルートパスを返す。
  #
  # 【引数】
  #   export_type: :habit_records / :tasks / :weekly_reflections（シンボル）
  #
  # 【戻り値】
  #   ルートパス文字列（例: "/settings/export_csv/habit_records"）
  #
  # 【なぜ case 文でルートヘルパーを使うのか】
  #   文字列補間（"/settings/export_csv/#{export_type}"）で動的にパスを作ると
  #   存在しないパスを指定した場合のエラーが実行時まで気づけない。
  #   ルートヘルパーを明示することで「このパスが routes.rb に定義済み」と
  #   静的に確認できる。
  def export_path_for(export_type)
    case export_type.to_sym
    when :habit_records
      export_csv_habit_records_settings_path
    when :tasks
      export_csv_tasks_settings_path
    when :weekly_reflections
      export_csv_weekly_reflections_settings_path
    else
      raise ArgumentError, "不明なexport_type: #{export_type}"
    end
  end
end