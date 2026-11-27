# test/integration/admin_dashboard_test.rb
#
# ==============================================================================
# 管理画面のトップ（/admin）の表示の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 集計の数字のカード・グラフ・ファネル・ログイン方法の内訳が表示される
#   ② 集計の対象の人だけが数えられている（予約ドメインの fixture ユーザーは数えない）
#   ③ 名前・メールアドレス・振り返りのコメントなどの入力内容は、画面に出ない
#
# 【テストの前提】
#   管理者は users(:two)（test2@example.com）。users(:one) をふつうのドメインに書き換え、
#   集計の対象は users(:one) の1人だけにする。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/admin_dashboard_test.rb
# ==============================================================================
require "test_helper"

class AdminDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]

    @admin = users(:two)
    ENV["ADMIN_EMAILS"] = @admin.email

    @counted_user = users(:one)
    @counted_user.update_columns(email: "counted-user@gmail.com", last_active_at: 1.day.ago)
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  test "数字のカード・グラフ・ファネル・ログイン方法の内訳が表示される" do
    log_in_as(@admin)

    get admin_root_path

    assert_response :success
    assert_select "[data-testid='admin-stat-total-users'] dd", "1人"
    assert_select "[data-testid='admin-stat-active-7d'] dd", "1人"
    assert_select "[data-controller='admin-usage-chart'] canvas", 2
    assert_select "[data-testid='admin-funnel'] > li", 6
    assert_select "[data-testid='admin-provider-email'] dd", "1人"
  end

  test "グラフのデータは12週分の JSON で渡される" do
    log_in_as(@admin)

    get admin_root_path

    chart = css_select("[data-controller='admin-usage-chart']").first
    signups = JSON.parse(chart["data-admin-usage-chart-signups-value"])
    assert_equal AdminUsageStatsService::WEEKS, signups["labels"].size
    assert_equal AdminUsageStatsService::WEEKS, signups["data"].size
  end

  test "名前・メールアドレス・振り返りのコメントは画面に出ない" do
    reflection = WeeklyReflection.where(user_id: @counted_user.id).first
    secret_comment = "管理画面に出てはいけない振り返りのコメント"
    reflection&.update_columns(reflection_comment: secret_comment)
    log_in_as(@admin)

    get admin_root_path

    assert_response :success
    assert_not_includes response.body, @counted_user.name
    assert_not_includes response.body, @counted_user.email
    assert_not_includes response.body, secret_comment
  end
end
