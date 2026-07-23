# test/integration/sentry_browser_test.rb
#
# ==============================================================================
# Issue #I-5: Sentry Browser SDK（フロントエンドJS監視）の検証
# ==============================================================================
# 【このテストの目的】
#   ① self-host した Sentry バンドルが public/ に配置されていること
#      （＝ダウンロード忘れによる本番404の事故を、テストで事前に発見する）。
#   ② 本番以外（テスト環境）では Sentry の browser スクリプトを出力しないこと
#      （＝開発ノイズ送信ゼロ・無料枠保護の設計が守られていること）。
# ==============================================================================

require "test_helper"

class SentryBrowserTest < ActionDispatch::IntegrationTest
  test "Sentry Browser バンドルが public/sentry に配置されている" do
    bundle_path = Rails.root.join("public", "sentry", "bundle.min.js")
    assert File.exist?(bundle_path),
           "public/sentry/bundle.min.js が未配置です。" \
           "Step 1 の curl でダウンロードしてください（本番で404になり監視が無効化されます）。"
  end

  test "テスト環境では Sentry の browser スクリプトを読み込まない" do
    # トップページ（LP）は未ログインでアクセス可能かつ application レイアウトを使う
    get "/"
    assert_response :success
    assert_no_match %r{/sentry/bundle\.min\.js}, response.body,
                    "本番(production)以外では Sentry browser スクリプトを出力しないこと（ノイズ防止）"
  end
end