# test/models/user_countable_test.rb
#
# ==============================================================================
# User.countable_for_usage（app/models/concerns/usage_countable.rb）のモデルテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① ふつうのユーザーは含め、退会済み・予約ドメインのユーザーは外す
#   ② メールアドレスが NULL（LINE ログイン）のユーザーは外さない
#   ③ 管理者（ADMIN_EMAILS）は外す。ADMIN_EMAILS が空でも、全員が外れてしまわない
#   ④ SQL の予約ドメインの判定が、メールを止める仕組み（Ruby の判定）と同じ結果になる
#
# 【fixture のメールアドレスについて】
#   fixture のユーザーはすべて @example.com（予約ドメイン）なので、そのままだと集計から外れる。
#   「含まれる」ことを確かめるテストでは、update_columns でふつうのドメインに書き換えて使う。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/models/user_countable_test.rb
# ==============================================================================
require "test_helper"

class UserCountableTest < ActiveSupport::TestCase
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]
    ENV.delete("ADMIN_EMAILS")

    @real_user = users(:one)
    @real_user.update_columns(email: "real-user@gmail.com")
    @demo_user = users(:two) # test2@example.com のまま（予約ドメイン）
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  # 集計の対象に含まれるかどうかを、1人ずつ確かめるためのヘルパー
  def countable?(user)
    User.countable_for_usage.exists?(id: user.id)
  end

  # ── ① 基本 ──────────────────────────────────────────────────────────
  test "ふつうのドメインのユーザーは含め、予約ドメインのユーザーは外す" do
    assert countable?(@real_user)
    assert_not countable?(@demo_user)
  end

  test "退会済みのユーザーは外す" do
    @real_user.update_columns(deleted_at: Time.current)

    assert_not countable?(@real_user)
  end

  # ── ② メールなし ────────────────────────────────────────────────────
  test "メールアドレスがない LINE ユーザーは外さない" do
    @real_user.update_columns(email: nil, provider: "line_v2_1")

    assert countable?(@real_user)
  end

  # ── ③ 管理者 ────────────────────────────────────────────────────────
  test "ADMIN_EMAILS のアドレスのユーザーは、大文字小文字に関係なく外す" do
    ENV["ADMIN_EMAILS"] = " Real-User@Gmail.com "

    assert_not countable?(@real_user)
  end

  test "ADMIN_EMAILS が設定されていても、メールのない LINE ユーザーは外さない" do
    ENV["ADMIN_EMAILS"] = "someone@gmail.com"
    @real_user.update_columns(email: nil, provider: "line_v2_1")

    assert countable?(@real_user)
  end

  test "ADMIN_EMAILS が空（カンマだけ）でも、全員が外れてしまわない" do
    ENV["ADMIN_EMAILS"] = " , "

    assert countable?(@real_user)
  end

  # ── ④ Ruby の判定と SQL の判定が同じになること ───────────────────────
  test "予約ドメインの判定は、メールを止める仕組み（Ruby）と SQL で同じ結果になる" do
    samples = %w[
      a@example.com a@EXAMPLE.org a@sub.example.net a@foo.test a@x.invalid
      a@localhost a@example a@example.com.
      a@myexample.com a@example.com.evil a@gmail.com a@test.co.jp a@mail.habitflow-arina.com
    ]

    samples.each do |address|
      sql = ActiveRecord::Base.sanitize_sql_array(
        [ "SELECT LOWER(SPLIT_PART(?, '@', 2)) ~ ?", address, ReservedDomainInterceptor::RESERVED_DOMAIN_SQL_PATTERN ]
      )
      sql_result = ActiveRecord::Base.connection.select_value(sql)

      assert_equal ReservedDomainInterceptor.reserved?(address), sql_result,
                   "#{address} の判定が Ruby と SQL で違います"
    end
  end
end
