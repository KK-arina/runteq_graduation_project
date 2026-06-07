# app/services/csv_export_service.rb
#
# ==============================================================================
# CsvExportService - CSV生成ロジックを一元管理するサービスクラス
# ==============================================================================
#
# 【このクラスの役割】
#   習慣記録・タスク・週次振り返りのCSVデータを生成する。
#   コントローラーやジョブからこのクラスを呼び出すことで、
#   CSV生成ロジックが1箇所にまとまり保守しやすくなる。
#
# 【将来のActiveStorage切り替えについて】
#   現在は generate_csv メソッドがCSV文字列を返す設計。
#   将来、数万件規模でActiveStorageに切り替える場合は:
#   1. このクラスに save_to_storage(csv_string) メソッドを追加
#   2. ジョブ側で generate_csv → save_to_storage の順に呼ぶ
#   3. ダウンロードURLの生成も save_to_storage が返す blob を使う
#   コントローラーとジョブのコードは変更不要。
#
# 【BOM（Byte Order Mark）について】
#   Excelは特定の条件下でCSVファイルをShift-JISで開こうとする。
#   UTF-8 BOM（\xEF\xBB\xBF）をファイル先頭に付けることで
#   「このファイルはUTF-8です」とExcelに伝え、文字化けを防ぐ。
#
# 【CSV.generateの前にBOMを連結する理由】
#   CSV.generate(bom, ...) とBOMを第1引数に渡す方法もあるが、
#   Rubyの実装によってはBOMが正しく扱われない場合がある。
#   bom + CSV.generate(...) で文字列として明示的に連結する方が
#   環境差異がなく確実。
#
# ==============================================================================
require "csv"

class CsvExportService

  # CSVの列ごとのヘッダー定義
  # 【定数にする理由】
  #   ヘッダーはコード全体で統一する必要がある。
  #   定数にすることで変更が1箇所で済む。
  HABIT_RECORDS_HEADERS = %w[記録日 習慣名 記録タイプ 完了 数値 単位 メモ 作成日時].freeze
  TASKS_HEADERS         = %w[タスク名 優先度 種別 ステータス 期限日 見積時間 完了日時 AI生成 作成日時].freeze
  REFLECTIONS_HEADERS   = %w[振り返り週開始日 振り返り週終了日 気分スコア なぜ？ どう？ からの？ 自由コメント 完了日時].freeze

  # LARGE_DATA_THRESHOLD: 即時ダウンロードとバックグラウンド処理の切り替え件数
  # 【なぜ1000件にするのか】
  #   実測で1000件のCSV生成が約0.5秒以内に完了するため。
  #   1000件超になるとHTTPレスポンスタイムアウトのリスクがある。
  LARGE_DATA_THRESHOLD = 1000

  # ==============================================================================
  # initialize - サービスクラスのインスタンス生成
  # ==============================================================================
  #
  # 【引数】
  #   user: CSV対象のUserインスタンス（必須）
  def initialize(user:)
    @user = user
  end

  # ==============================================================================
  # count_for(export_type) - エクスポート対象の件数を返す
  # ==============================================================================
  def count_for(export_type)
    case export_type
    when :habit_records
      # deleted_at: nil で論理削除済みを除外する
      # schema.rb で habit_records.deleted_at カラムが存在することを確認済み
      @user.habit_records.where(deleted_at: nil).count
    when :tasks
      # tasks.deleted_at カラムが存在することを schema.rb で確認済み
      @user.tasks.where(deleted_at: nil).count
    when :weekly_reflections
      # weekly_reflections には deleted_at がないため全件カウント
      @user.weekly_reflections.count
    else
      raise ArgumentError, "不明なexport_type: #{export_type}"
    end
  end

  # ==============================================================================
  # generate_csv(export_type) - 指定種別のCSV文字列を生成して返す
  # ==============================================================================
  #
  # 【戻り値】
  #   UTF-8 BOM付きのCSV文字列（String型）
  def generate_csv(export_type)
    case export_type
    when :habit_records
      generate_habit_records_csv
    when :tasks
      generate_tasks_csv
    when :weekly_reflections
      generate_weekly_reflections_csv
    else
      raise ArgumentError, "不明なexport_type: #{export_type}"
    end
  end

  # ==============================================================================
  # filename_for(export_type) - ダウンロード時のファイル名を返す
  # ==============================================================================
  def filename_for(export_type)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    case export_type
    when :habit_records      then "habitflow_habit_records_#{timestamp}.csv"
    when :tasks              then "habitflow_tasks_#{timestamp}.csv"
    when :weekly_reflections then "habitflow_weekly_reflections_#{timestamp}.csv"
    else                          "habitflow_export_#{timestamp}.csv"
    end
  end

  private

  # ==============================================================================
  # generate_habit_records_csv - 習慣記録のCSV生成
  # ==============================================================================
  def generate_habit_records_csv
    records = @user.habit_records
                   .where(deleted_at: nil)
                   .includes(:habit)
                   .order(:record_date)

    build_csv(HABIT_RECORDS_HEADERS) do |csv|
      records.each do |record|
        csv << [
          record.record_date.strftime("%Y/%m/%d"),
          record.habit&.name || "（削除済み）",
          # measurement_type の enum 値で分岐する
          # schema.rb: measurement_type は integer, 0=check_type, 1=numeric_type
          record.habit&.check_type? ? "チェック型" : "数値型",
          record.completed ? "✓" : "",
          record.numeric_value,
          record.habit&.unit,
          record.memo,
          record.created_at.strftime("%Y/%m/%d %H:%M")
        ]
      end
    end
  end

  # ==============================================================================
  # generate_tasks_csv - タスクのCSV生成
  # ==============================================================================
  def generate_tasks_csv
    # DBには整数で保存されているため、CSV出力時に日本語に変換する
    priority_labels  = { "must" => "Must（必須）", "should" => "Should（推奨）", "could" => "Could（余力）" }
    task_type_labels = { "normal" => "通常", "habit_related" => "習慣関連", "improvement" => "改善" }
    status_labels    = { "todo" => "未着手", "doing" => "進行中", "done" => "完了", "archived" => "アーカイブ" }

    tasks = @user.tasks
                 .where(deleted_at: nil)
                 .order(:created_at)

    build_csv(TASKS_HEADERS) do |csv|
      tasks.each do |task|
        csv << [
          task.title,
          priority_labels[task.priority] || task.priority,
          task_type_labels[task.task_type] || task.task_type,
          status_labels[task.status] || task.status,
          task.due_date&.strftime("%Y/%m/%d"),
          task.estimated_hours,
          task.completed_at&.strftime("%Y/%m/%d %H:%M"),
          task.ai_generated ? "AI生成" : "手動",
          task.created_at.strftime("%Y/%m/%d %H:%M")
        ]
      end
    end
  end

  # ==============================================================================
  # generate_weekly_reflections_csv - 週次振り返りのCSV生成
  # ==============================================================================
  def generate_weekly_reflections_csv
    reflections = @user.weekly_reflections.order(:week_start_date)

    build_csv(REFLECTIONS_HEADERS) do |csv|
      reflections.each do |r|
        csv << [
          r.week_start_date.strftime("%Y/%m/%d"),
          r.week_end_date.strftime("%Y/%m/%d"),
          r.mood,
          r.direct_reason,
          r.background_situation,
          r.next_action,
          r.reflection_comment,
          r.completed_at&.strftime("%Y/%m/%d %H:%M")
        ]
      end
    end
  end

  # ==============================================================================
  # build_csv - CSV文字列を組み立てる共通メソッド
  # ==============================================================================
  #
  # 【BOMの連結方法について】
  #   bom + CSV.generate(...) で明示的に文字列連結する。
  #   CSV.generate(bom, ...) のように引数で渡す方式は
  #   Rubyのバージョンや環境によって動作が異なる場合があるため
  #   明示的な文字列連結の方が確実で環境差異が出ない。
  #
  # 【row_sep: "\r\n" について】
  #   Windows形式の改行（CRLF）。
  #   Excelはこの形式を正しく認識する。
  #   "\n"（LF）だと古いExcelで1行にまとめられてしまう場合がある。
  def build_csv(headers)
    # UTF-8 BOM: Excelが文字化けなく開くために先頭に付ける3バイト
    bom = "\xEF\xBB\xBF"

    # bom + CSV.generate(...) で連結する
    # 【なぜ encoding: "UTF-8" を明示するのか】
    #   Railsの環境によってはデフォルトエンコーディングが異なる場合がある。
    #   明示することで常にUTF-8でCSVを生成することを保証する。
    bom + CSV.generate(encoding: "UTF-8", row_sep: "\r\n") do |csv|
      csv << headers
      yield csv
    end
  end
end