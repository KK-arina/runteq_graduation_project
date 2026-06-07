# test/controllers/csv_exports_controller_test.rb
#
# ==============================================================================
# CsvExportsController のテスト（設計変更対応版）
# ==============================================================================
#
# 【設計変更の反映】
#   View側で件数を判定して data-turbo を切り替える方式に変更したため、
#   1000件以下のテストでは:
#   - Turbo非経由（as HTML）のリクエストになる
#   - コントローラーで303リダイレクト → download アクションへ
#   - download アクションも as HTML → send_data がブラウザに届く
#   のフローを確認する。
#
# ==============================================================================
require "test_helper"

class CsvExportsControllerTest < ActionDispatch::IntegrationTest

  setup do
    @user = users(:one)
    post login_path, params: { session: { email: @user.email, password: "password" } }
  end

  # ==============================================================================
  # 未ログイン時のリダイレクトテスト
  # ==============================================================================

  test "未ログインで habit_records エクスポートにアクセスするとログインページにリダイレクト" do
    delete logout_path
    post export_csv_habit_records_settings_path
    assert_response :redirect
    assert_match(/login/, response.location)
  end

  # ==============================================================================
  # 即時ダウンロードのテスト（1000件以下・data-turbo="false"経由）
  # ==============================================================================
  #
  # 【テスト方針の変更】
  #   data-turbo="false" ボタンからのリクエストは as HTML になる。
  #   そのためテストでも Turbo ヘッダーを付けずに POST する。
  #   コントローラーは303リダイレクト → download アクション → send_data の流れ。
  #
  # fixture のデータは通常1000件未満のため、そのままテストできる。

  test "習慣記録が1000件以下の場合は download アクションへ 303 リダイレクトされる" do
    # data-turbo="false" ボタンからのリクエスト = 通常HTMLリクエスト
    # Turboヘッダーなしで POST する
    post export_csv_habit_records_settings_path

    assert_response :see_other
    assert_match(/download_csv/, response.location)
    assert_match(/token=/, response.location)
  end

  test "タスクが1000件以下の場合は download アクションへ 303 リダイレクトされる" do
    post export_csv_tasks_settings_path

    assert_response :see_other
    assert_match(/download_csv/, response.location)
    assert_match(/token=/, response.location)
  end

  test "週次振り返りが1000件以下の場合は download アクションへ 303 リダイレクトされる" do
    post export_csv_weekly_reflections_settings_path

    assert_response :see_other
    assert_match(/download_csv/, response.location)
    assert_match(/token=/, response.location)
  end

  # ==============================================================================
  # バックグラウンド処理のテスト（1000件超・通常Turboボタン経由）
  # ==============================================================================
  #
  # テスト用サブクラス: count_for が常に 1001 を返す
  class LargeDataCsvExportService < CsvExportService
    def count_for(_export_type)
      1001
    end
  end

  test "習慣記録が1000件超の場合は CsvExportJob がエンキューされる" do
    CsvExportService.stub(:new, LargeDataCsvExportService.new(user: @user)) do
      assert_enqueued_with(job: CsvExportJob,
                           args: [@user.id, "habit_records"]) do
        post export_csv_habit_records_settings_path,
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
  end

  test "タスクが1000件超の場合は CsvExportJob がエンキューされる" do
    CsvExportService.stub(:new, LargeDataCsvExportService.new(user: @user)) do
      assert_enqueued_with(job: CsvExportJob,
                           args: [@user.id, "tasks"]) do
        post export_csv_tasks_settings_path,
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
  end

  # ==============================================================================
  # ダウンロードエンドポイントのテスト
  # ==============================================================================

  test "有効なトークンで download にアクセスするとCSVがダウンロードされる" do
    token = CsvDownloadTokenService.generate(
      user:        @user,
      export_type: :habit_records,
      expires_in:  5.minutes
    )
    get download_csv_settings_path, params: { token: token }

    assert_response :success
    assert_includes response.content_type, "text/csv"
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert response.body.start_with?("\xEF\xBB\xBF"),
           "CSVはUTF-8 BOMで始まる必要があります"
  end

  test "無効なトークンで download にアクセスすると設定ページにリダイレクト" do
    get download_csv_settings_path, params: { token: "invalid_token_xxx" }
    assert_redirected_to settings_path
    assert_equal I18n.t("csv_exports.download.token_invalid"), flash[:alert]
  end

  test "他のユーザーのトークンでアクセスすると設定ページにリダイレクト" do
    other_user = users(:two)
    token = CsvDownloadTokenService.generate(
      user:        other_user,
      export_type: :tasks,
      expires_in:  5.minutes
    )
    get download_csv_settings_path, params: { token: token }
    assert_redirected_to settings_path
    assert_equal I18n.t("csv_exports.download.token_invalid"), flash[:alert]
  end

  test "期限切れトークンで download にアクセスすると設定ページにリダイレクト" do
    token = CsvDownloadTokenService.generate(
      user:        @user,
      export_type: :tasks,
      expires_in:  5.minutes
    )
    travel_to(6.minutes.from_now) do
      get download_csv_settings_path, params: { token: token }
    end
    assert_redirected_to settings_path
    assert_equal I18n.t("csv_exports.download.token_invalid"), flash[:alert]
  end
end