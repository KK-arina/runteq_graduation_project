# test/integration/sentry_source_map_test.rb
#
# 【このテストの目的】
#   public/sentry/bundle.min.js（Sentry 公式のブラウザ SDK を自前で配信しているファイル）の
#   最終行には「//# sourceMappingURL=bundle.min.js.map」と書かれている。
#   ブラウザの DevTools を開くと、この行を見てソースマップを取りに来る。
#   ソースマップが無いと、そのリクエストは Rails の「全部を受けるルート」（match "*path"）まで届き、
#   ErrorsController が 404 を返す。ログイン中はユーザーを調べるため、DB への問い合わせも 1 回発生していた。
#   同じバージョンのソースマップを隣に置き、静的ファイルとして返すことで、これを無くした。
#   このテストは「置いたソースマップが消えていないこと」「正しい中身であること」
#   「Rails の 404 ではなく静的ファイルとして返ること」を確かめる。

require "test_helper"

class SentrySourceMapTest < ActionDispatch::IntegrationTest
  # テストで使うファイルの場所（Rails.root はプロジェクトのルートフォルダ）
  BUNDLE_PATH = Rails.root.join("public", "sentry", "bundle.min.js")
  MAP_PATH = Rails.root.join("public", "sentry", "bundle.min.js.map")

  test "bundle.min.js が指すソースマップのファイルが同じフォルダに存在する" do
    # bundle.min.js の末尾にある「//# sourceMappingURL=ファイル名」からファイル名だけを取り出す
    # \S+ … 空白以外の文字の並び（＝ファイル名）
    # \s*\z … そのあとに改行などがあってもよく、そこでファイルが終わること
    map_name = File.read(BUNDLE_PATH)[%r{//# sourceMappingURL=(\S+)\s*\z}, 1]

    assert map_name.present?,
           "bundle.min.js の末尾に sourceMappingURL が見つかりません。SDK を更新した場合は、このテストも見直してください。"

    # bundle.min.js と同じフォルダに、そのファイル名のソースマップがあるか
    assert File.exist?(BUNDLE_PATH.dirname.join(map_name)),
           "public/sentry/#{map_name} がありません。bundle.min.js と同じバージョンのソースマップを Sentry 公式 CDN から取得して置いてください。"
  end

  test "ソースマップは正しい JSON（Source Map バージョン 3）である" do
    # 取得に失敗してエラー画面などを保存していないかを確かめるため、JSON として読めるかを見る
    json = JSON.parse(File.read(MAP_PATH))

    # Source Map の仕様では version は 3 と決まっている
    assert_equal 3, json["version"]
    # mappings … 圧縮後のコードと元のコードの対応表。空ならソースマップとして役に立たない
    assert json["mappings"].present?, "ソースマップの mappings が空です。"
  end

  test "ソースマップは静的ファイルとして 200 で返り、Rails の 404 にならない" do
    # public/ 配下のファイルは ActionDispatch::Static が Rails のルーティングより前に返す。
    # ここで 200 になれば、ErrorsController（404）まで届いていないことが分かる
    get "/sentry/bundle.min.js.map"

    assert_response :ok
  end
end