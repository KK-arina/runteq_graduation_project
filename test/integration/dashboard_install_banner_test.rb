# test/integration/dashboard_install_banner_test.rb
#
# ==============================================================================
# ダッシュボードの「ホーム画面に追加」バナーの統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① ダッシュボードにバナーがあり、最初は非表示（hidden）で出力されている
#   ② ホーム画面から開いているときに隠すための pwa-guide / browserOnly が付いている
#   ③ ✕ ボタン・設定ページの案内へのリンク・Chrome / Edge 用のボタンがある
#   ④ コントローラーが登録されていて、サーバーへ何も送らない作りになっている
#
# 【表示・非表示の切り替えをここで確かめない理由】
#   切り替えはブラウザの JavaScript（Stimulus）で行うため、
#   統合テスト（HTML を取得するだけ）では動かない。
#   ここでは、JavaScript が正しく動くための HTML の印がそろっていることを確認する。
# ==============================================================================
require "test_helper"

class DashboardInstallBannerTest < ActionDispatch::IntegrationTest
  setup do
    # log_in_as はパスワード "password" でログインするため、同じパスワードの fixture ユーザーを使う
    # （dashboard_test.rb と同じ方法）
    @user = users(:one)
    log_in_as(@user)
  end

  test "ダッシュボードにバナーがあり、最初は非表示で出力されている" do
    get dashboard_path
    assert_response :success

    # 外側: pwa-guide → 真ん中: browserOnly（hidden）→ 内側: install-banner（hidden）
    assert_select "[data-controller='pwa-guide'] > [data-pwa-guide-target='browserOnly'][hidden]" do
      assert_select "section[data-controller='install-banner'][data-testid='dashboard-install-banner'][hidden]"
    end
  end

  test "バナーに見出し・案内へのリンク・追加ボタン・閉じるボタンがある" do
    get dashboard_path

    assert_select "[data-testid='dashboard-install-banner']" do
      assert_select "h2#dashboard-install-banner-title", text: I18n.t("pwa_install.banner.title")

      # 設定ページの案内カード（id="pwa-install-guide"）へ移動するリンク
      assert_select "a[href=?]", settings_path(anchor: "pwa-install-guide"),
                    text: I18n.t("pwa_install.banner.how_to")

      # Chrome / Edge 用のボタン（最初は入れ物ごと非表示）
      assert_select "[data-pwa-guide-target='installArea'][hidden] button[data-action='pwa-guide#install']"

      # ✕ ボタン（スクリーンリーダー向けの名前つき）
      assert_select "button[data-action='install-banner#dismiss'][aria-label=?]",
                    I18n.t("pwa_install.banner.dismiss")
    end
  end

  test "バナーの文言がすべて locale ファイルにある" do
    %w[title body how_to install_button dismiss].each do |key|
      assert I18n.exists?("pwa_install.banner.#{key}", :ja), "pwa_install.banner.#{key} がありません"
    end
  end

  test "install-banner コントローラーが importmap のキーで登録されている" do
    index_js = Rails.root.join("app/javascript/controllers/index.js").read

    assert_includes index_js, 'import InstallBannerController from "controllers/install_banner_controller"'
    assert_includes index_js, 'application.register("install-banner", InstallBannerController)'
  end

  test "install-banner コントローラーはサーバーへ何も送らない（DB へのアクセスを増やさない）" do
    controller_js = Rails.root.join("app/javascript/controllers/install_banner_controller.js").read

    assert_no_match(/fetch\(|XMLHttpRequest|sendBeacon/, controller_js)
    assert_includes controller_js, "localStorage"
  end
end
