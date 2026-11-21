# test/integration/stimulus_controller_imports_test.rb
#
# ==============================================================================
# controllers/index.js の import が importmap のキーで書かれていることの統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① index.js に相対パス（"./xxx"）の import が残っていない
#      （相対パスだと importmap を通らず、ハッシュ無しの URL で二重にダウンロードされる）
#   ② index.js が import している "controllers/xxx" が、すべて importmap に存在する
#      （存在しないキーを書くと、ブラウザで読み込みに失敗し、全コントローラーが動かなくなる）
#   ③ 同じく、すべて app/javascript/controllers/ にファイルとして存在する
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/stimulus_controller_imports_test.rb
# ==============================================================================
require "test_helper"

class StimulusControllerImportsTest < ActionDispatch::IntegrationTest
  INDEX_JS = Rails.root.join("app/javascript/controllers/index.js")

  # index.js の import 文から、読み込み先（from "..." の中身）を配列で取り出す
  #   scan: 正規表現に一致した部分をすべて探し、() の中身を配列で返す
  #   ^\s*import: 行の先頭（空白のあと）が import の行だけを対象にする（コメント内の例文は除く）
  def imported_specifiers
    File.read(INDEX_JS).scan(/^\s*import\s.+?\sfrom\s+["']([^"']+)["']/).flatten
  end

  test "index.js に相対パスの import が残っていない" do
    relative = imported_specifiers.select { |specifier| specifier.start_with?(".") }

    assert_empty relative,
                 "相対パスの import があります（\"controllers/...\" で書いてください）: #{relative.join(', ')}"
  end

  test "index.js の import がすべて importmap とファイルに存在する" do
    specifiers = imported_specifiers
    assert specifiers.size > 1, "index.js の import を読み取れませんでした"

    # ページに出力された <script type="importmap"> から、読み込み先の一覧を取り出す
    get login_path
    imports = JSON.parse(css_select("script[type='importmap']").first.text).fetch("imports")

    specifiers.each do |specifier|
      assert imports.key?(specifier), "importmap に #{specifier} がありません"

      # "controllers/flash_controller" → app/javascript/controllers/flash_controller.js
      assert File.exist?(Rails.root.join("app/javascript/#{specifier}.js")),
             "app/javascript/#{specifier}.js がありません"
    end
  end
end
