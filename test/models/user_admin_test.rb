# test/models/user_admin_test.rb
#
# ==============================================================================
# User#admin?（管理者の判定・app/models/concerns/admin_role.rb）のモデルテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① ADMIN_EMAILS が未設定・空・カンマだけのときは、誰も管理者にならない
#   ② 前後の空白・大文字小文字の違いがあっても、同じアドレスなら管理者になる
#   ③ 退会済み・メールなし・LINE ログインのユーザーは、アドレスが一致しても管理者にならない
#   ④ Google ログインのユーザーは、アドレスが一致すれば管理者になる
#
# 【ENV を元に戻す理由】
#   ENV（環境変数）はテストの間で共有される。書き換えたままにすると、
#   あとに実行されるテストの結果まで変わってしまうため、
#   setup で元の値を控え、teardown で必ず元に戻す。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/models/user_admin_test.rb
# ==============================================================================
require "test_helper"

class UserAdminTest < ActiveSupport::TestCase
  setup do
    # 元の値を控えておく（未設定なら nil）
    @original_admin_emails = ENV["ADMIN_EMAILS"]

    # users(:one): fixture のユーザー（email: test1@example.com・provider は初期値の "email"）
    @user = users(:one)
  end

  teardown do
    # 元が未設定（nil）なら削除し、値があったならその値に戻す
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  # ── ① 誰も管理者にならないケース ────────────────────────────────────
  test "ADMIN_EMAILS が未設定なら管理者にならない" do
    ENV.delete("ADMIN_EMAILS")

    assert_not @user.admin?
  end

  test "ADMIN_EMAILS が空文字なら管理者にならない" do
    ENV["ADMIN_EMAILS"] = ""

    assert_not @user.admin?
  end

  test "ADMIN_EMAILS がカンマと空白だけなら管理者にならず、一覧も空になる" do
    ENV["ADMIN_EMAILS"] = " , ,, "

    assert_not @user.admin?
    assert_empty User.admin_emails
  end

  test "ADMIN_EMAILS に別のアドレスしかなければ管理者にならない" do
    ENV["ADMIN_EMAILS"] = "someone-else@example.org"

    assert_not @user.admin?
  end

  # ── ② 一致するケース ────────────────────────────────────────────────
  test "ADMIN_EMAILS に同じアドレスがあれば管理者になる" do
    ENV["ADMIN_EMAILS"] = "test1@example.com"

    assert @user.admin?
  end

  test "前後の空白と大文字小文字の違いは無視し、複数のアドレスから一致を探す" do
    ENV["ADMIN_EMAILS"] = " someone-else@example.org ,  Test1@Example.COM  "

    assert @user.admin?
    assert_equal Set["someone-else@example.org", "test1@example.com"], User.admin_emails
  end

  # ── ③ アドレスが一致しても管理者にならないケース ─────────────────────
  test "退会済みのユーザーは管理者にならない" do
    ENV["ADMIN_EMAILS"] = "test1@example.com"
    # DB には保存せず、このテストの中のオブジェクトだけを退会済みにする
    @user.deleted_at = Time.current

    assert_not @user.admin?
  end

  test "メールアドレスがない（LINE でメールを取得できなかった）ユーザーは管理者にならない" do
    ENV["ADMIN_EMAILS"] = "test1@example.com"
    @user.email = nil

    assert_not @user.admin?
  end

  test "LINE ログインのユーザーは、アドレスが一致しても管理者にならない" do
    ENV["ADMIN_EMAILS"] = "test1@example.com"
    @user.provider = "line_v2_1"

    assert_not @user.admin?
  end

  test "退会処理で provider が deleted になったユーザーは管理者にならない" do
    ENV["ADMIN_EMAILS"] = "test1@example.com"
    @user.provider = "deleted"

    assert_not @user.admin?
  end

  # ── ④ Google ログイン ───────────────────────────────────────────────
  test "Google ログインのユーザーは、アドレスが一致すれば管理者になる" do
    ENV["ADMIN_EMAILS"] = "test1@example.com"
    @user.provider = "google_oauth2"

    assert @user.admin?
  end
end
