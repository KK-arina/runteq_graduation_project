# test/integration/admin_users_test.rb
#
# ==============================================================================
# 管理画面のユーザー一覧（/admin/users）の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 一般ユーザー・未ログインには 404（Admin::BaseController の認可が効いている）
#   ② 管理者には一覧が表示され、メールアドレスは伏せ字で、入力内容は出ない
#   ③ 管理画面のトップから一覧へのリンクがある
# ==============================================================================
require "test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]

    @admin = users(:two)
    ENV["ADMIN_EMAILS"] = @admin.email

    @listed_user = users(:one)
    @listed_user.update_columns(email: "listed-user@gmail.com")
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  test "未ログインと一般ユーザーには 404 を返す" do
    get admin_users_path
    assert_response :not_found

    log_in_as(users(:locked_user))
    get admin_users_path
    assert_response :not_found
  end

  test "管理者には一覧が表示され、メールアドレスは伏せ字になる" do
    log_in_as(@admin)

    get admin_users_path

    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_select "[data-testid='admin-user-row-#{@listed_user.id}']" do
      assert_select "th", @listed_user.name
      assert_select "td", "l***@gmail.com"
    end
    assert_not_includes response.body, "listed-user@gmail.com"
  end

  test "振り返りのコメントなどの入力内容は一覧に出ない" do
    secret_comment = "一覧に出てはいけない振り返りのコメント"
    WeeklyReflection.where(user_id: @listed_user.id).update_all(reflection_comment: secret_comment)
    log_in_as(@admin)

    get admin_users_path

    assert_response :success
    assert_not_includes response.body, secret_comment
  end

  test "絞り込みのタブがあり、選んだタブに aria-current が付く" do
    log_in_as(@admin)

    get admin_users_path(filter: "unused")

    assert_select "[data-testid='admin-users-filter-unused'][aria-current='page']"
    assert_select "[data-testid='admin-users-filter-all']:not([aria-current])"
  end

  test "管理画面のトップから一覧へのリンクがある" do
    log_in_as(@admin)

    get admin_root_path

    assert_select "a[href='#{admin_users_path}']"
  end

  test "該当者が0人のときは「0人中」の行を出さず、該当者がいないことだけを表示する" do
    # last_active_at を空にして、「継続中（7日以内に利用）」に当てはまる人がいない状態にする
    @listed_user.update_columns(last_active_at: nil)
    log_in_as(@admin)

    get admin_users_path(filter: "active")

    assert_response :success
    assert_select "[data-testid='admin-users-summary']", 0
    assert_select "[data-testid='admin-users-empty']", I18n.t("admin.users.index.empty")
  end
end
