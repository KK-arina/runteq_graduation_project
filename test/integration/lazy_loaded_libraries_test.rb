# test/integration/lazy_loaded_libraries_test.rb
#
# ==============================================================================
# chart.js / SortableJS を「使うページだけで読み込む」設定の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① どのページでも、chart.js と SortableJS を先読み（modulepreload）していない
#      （config/importmap.rb の preload: false が効いている）
#   ② それでも importmap（読み込み先の一覧）には chart.js と Sortable が残っている
#      （コントローラーの import("chart.js") / import("Sortable") が読み込み先を見つけられる）
#
# 【modulepreload とは】
#   javascript_importmap_tags が <head> に出力する
#   <link rel="modulepreload" href="/assets/xxx.js"> のこと。
#   ブラウザに「このファイルを今すぐ取ってきておいて」と伝えるため、
#   使わないページでもダウンロードが発生する。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/lazy_loaded_libraries_test.rb
# ==============================================================================
require "test_helper"

class LazyLoadedLibrariesTest < ActionDispatch::IntegrationTest
  # chart.js と SortableJS のファイル名に一致する正規表現
  #   "analytics_chart_controller-xxx.js" や "habit_sort_controller-xxx.js" は
  #   "chart.js" / "sortable" を含まないため、コントローラー自体は一致しない
  LAZY_LIBRARY_PATTERN = /chart\.js|sortable/i

  # 表示中のページの modulepreload の URL を配列で返す
  def modulepreload_hrefs
    css_select("link[rel='modulepreload']").map { |link| link["href"] }
  end

  test "ログイン画面では chart.js と SortableJS を先読みしない" do
    get login_path
    assert_response :success

    preloaded = modulepreload_hrefs.grep(LAZY_LIBRARY_PATTERN)
    assert_empty preloaded, "先読みされています: #{preloaded.join(', ')}"
  end

  test "ログイン後のページでも chart.js と SortableJS を先読みしない" do
    log_in_as(users(:one))

    # 設定ページはオンボーディング前でも表示されるため、fixture の状態に左右されない
    get settings_path
    assert_response :success

    preloaded = modulepreload_hrefs.grep(LAZY_LIBRARY_PATTERN)
    assert_empty preloaded, "先読みされています: #{preloaded.join(', ')}"
  end

  test "importmap には chart.js と Sortable の読み込み先が残っている" do
    get login_path

    # <script type="importmap"> の中身（JSON）を取り出して、読み込み先の一覧を確認する
    importmap_json = css_select("script[type='importmap']").first&.text
    assert importmap_json.present?, "importmap が出力されていません"

    imports = JSON.parse(importmap_json).fetch("imports")
    assert imports.key?("chart.js"), "importmap に chart.js がありません"
    assert imports.key?("Sortable"), "importmap に Sortable がありません"
  end
end
