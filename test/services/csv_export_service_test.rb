# test/services/csv_export_service_test.rb
#
# ==============================================================================
# CsvExportService のテスト
# ==============================================================================
require "test_helper"

class CsvExportServiceTest < ActiveSupport::TestCase

  # setup: 各テスト実行前に共通の準備を行う
  # fixture の users(:one) でテストユーザーを取得する。
  # @service: テスト対象のサービスインスタンス
  setup do
    @user    = users(:one)
    @service = CsvExportService.new(user: @user)
  end

  # ==============================================================================
  # count_for のテスト
  # ==============================================================================

  test "count_for は habit_records の件数を返す" do
    # 【なぜ assert_kind_of Integer を使うのか】
    #   件数が整数であることを確認する。
    #   具体的な数値はfixtureのデータ量に依存するため、
    #   型チェックのみ行う。
    assert_kind_of Integer, @service.count_for(:habit_records)
  end

  test "count_for は tasks の件数を返す" do
    assert_kind_of Integer, @service.count_for(:tasks)
  end

  test "count_for は weekly_reflections の件数を返す" do
    assert_kind_of Integer, @service.count_for(:weekly_reflections)
  end

  test "count_for に不明な種別を渡すと ArgumentError が発生する" do
    # 【assert_raises の使い方】
    #   ブロック内のコードが指定した例外を発生させることを確認する。
    #   例外が発生しない、または別の例外が発生した場合はテスト失敗。
    assert_raises(ArgumentError) do
      @service.count_for(:unknown_type)
    end
  end

  # ==============================================================================
  # generate_csv のテスト
  # ==============================================================================

  test "generate_csv は habit_records の CSV 文字列を返す" do
    csv = @service.generate_csv(:habit_records)

    # BOM付きで始まることを確認する
    # "\xEF\xBB\xBF" は UTF-8 BOM のバイト列
    assert csv.start_with?("\xEF\xBB\xBF"),
           "CSV は UTF-8 BOM で始まる必要があります"

    # ヘッダー行が含まれることを確認する
    assert_includes csv, "記録日"
    assert_includes csv, "習慣名"
  end

  test "generate_csv は tasks の CSV 文字列を返す" do
    csv = @service.generate_csv(:tasks)

    assert csv.start_with?("\xEF\xBB\xBF"),
           "CSV は UTF-8 BOM で始まる必要があります"
    assert_includes csv, "タスク名"
    assert_includes csv, "優先度"
  end

  test "generate_csv は weekly_reflections の CSV 文字列を返す" do
    csv = @service.generate_csv(:weekly_reflections)

    assert csv.start_with?("\xEF\xBB\xBF"),
           "CSV は UTF-8 BOM で始まる必要があります"
    assert_includes csv, "振り返り週開始日"
  end

  test "generate_csv に不明な種別を渡すと ArgumentError が発生する" do
    assert_raises(ArgumentError) do
      @service.generate_csv(:unknown_type)
    end
  end

  # ==============================================================================
  # filename_for のテスト
  # ==============================================================================

  test "filename_for は習慣記録のファイル名を返す" do
    filename = @service.filename_for(:habit_records)

    # 【assert_match の使い方】
    #   正規表現でファイル名のパターンを検証する。
    #   "habitflow_habit_records_" で始まり ".csv" で終わることを確認する。
    assert_match(/\Ahabitflow_habit_records_\d{8}_\d{6}\.csv\z/, filename)
  end

  test "filename_for はタスクのファイル名を返す" do
    filename = @service.filename_for(:tasks)
    assert_match(/\Ahabitflow_tasks_\d{8}_\d{6}\.csv\z/, filename)
  end

  test "filename_for は週次振り返りのファイル名を返す" do
    filename = @service.filename_for(:weekly_reflections)
    assert_match(/\Ahabitflow_weekly_reflections_\d{8}_\d{6}\.csv\z/, filename)
  end
end