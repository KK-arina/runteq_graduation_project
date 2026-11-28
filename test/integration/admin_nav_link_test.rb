# test/integration/admin_nav_link_test.rb
require "test_helper"

# ヘッダーの「管理画面」リンク（app/views/shared/_header.html.erb）のテスト
#
# 【このテストで確かめること】
#   ① 管理者には、PC 用ナビとモバイル用メニューの両方に「管理画面」のリンクが表示される
#   ② 管理者ではないユーザーには表示されない（管理画面があることを知らせない）
#   ③ 管理画面を開いているときは「管理画面」が今のページ（aria-current="page"）になり、
#      「ダッシュボード」はならない（Admin::DashboardsController の controller_name も
#      "dashboards" になるため、controller_path で判定していることの確認）
#
# 【ADMIN_EMAILS を setup で保存し、teardown で元に戻す理由】
#   ENV はテスト全体で共有されるため、変えたままにすると、ほかのテストの結果が変わってしまう。
class AdminNavLinkTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]
    @admin = users(:one)
    @other = users(:two)
    ENV["ADMIN_EMAILS"] = @admin.email
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  test "管理者には、PC 用ナビとモバイル用メニューの両方に「管理画面」のリンクが表示される" do
    log_in_as(@admin)
    get dashboard_path

    assert_select "nav[aria-label='メインナビゲーション'] a[href='#{admin_root_path}']", text: "管理画面", count: 1
    assert_select "nav[aria-label='モバイルナビゲーション'] a[href='#{admin_root_path}']", text: "管理画面", count: 1
  end

  test "管理者ではないユーザーには「管理画面」のリンクが表示されない" do
    log_in_as(@other)
    get dashboard_path

    assert_select "header a[href='#{admin_root_path}']", count: 0
  end

  test "管理画面では「管理画面」が今のページになり、「ダッシュボード」はならない" do
    log_in_as(@admin)
    get admin_root_path
    assert_response :success

    assert_select "header a[href='#{admin_root_path}'][aria-current='page']", count: 2
    assert_select "header a[href='#{dashboard_path}'][aria-current]", count: 0
  end

  test "ダッシュボードでは「ダッシュボード」が今のページになり、「管理画面」はならない" do
    log_in_as(@admin)
    get dashboard_path

    assert_select "header a[href='#{dashboard_path}'][aria-current='page']", count: 2
    assert_select "header a[href='#{admin_root_path}'][aria-current]", count: 0
  end

  # 下部のナビ（_bottom_navigation.html.erb・スマホ幅で表示）の「ホーム」も、
  # 管理画面では選ばれた状態（aria-current="page"）にならないこと。
  # 「ホーム」のリンク先は root_path（"/"）。ヘッダーのロゴも "/" へのリンクだが、aria-current は付かない。
  test "管理画面では、下部のナビの「ホーム」が今のページにならない" do
    log_in_as(@admin)

    get admin_root_path
    assert_select "a[href='#{root_path}'][aria-current]", count: 0

    # 比べるために、ダッシュボードでは「ホーム」が今のページになることも確かめる
    get dashboard_path
    assert_select "a[href='#{root_path}'][aria-current='page']", count: 1
  end
end
