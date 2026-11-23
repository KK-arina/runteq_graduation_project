# test/mailers/reserved_domain_interceptor_test.rb
require "test_helper"

# 予約ドメイン宛てのメールを止めるインターセプターのテスト
class ReservedDomainInterceptorTest < ActiveSupport::TestCase
  # ============================================================
  # reserved? の判定
  # ============================================================
  test "予約ドメインは予約扱いになる" do
    %w[
      user@example.com
      user@EXAMPLE.COM
      user@sub.example.org
      user@example.net
      user@foo.test
      user@foo.invalid
      user@localhost
      user@example.com.
    ].each do |address|
      assert ReservedDomainInterceptor.reserved?(address), "#{address} は予約扱いになるべき"
    end
  end

  test "実在するドメインや、名前が似ているだけのドメインは予約扱いにならない" do
    %w[
      user@gmail.com
      user@yahoo.co.jp
      no-reply@mail.habitflow-arina.com
      user@myexample.com
      user@contest.com
      user@example.com.evil
    ].each do |address|
      assert_not ReservedDomainInterceptor.reserved?(address), "#{address} は予約扱いにならないべき"
    end
  end

  test "@ がない値や空の値は予約扱いにならない（判定でエラーにならない）" do
    assert_not ReservedDomainInterceptor.reserved?("invalid-address")
    assert_not ReservedDomainInterceptor.reserved?(nil)
  end

  # ============================================================
  # delivering_email の動き
  # ============================================================
  test "予約ドメインだけが宛先のメールは送信が中止される" do
    message = Mail.new(to: "demo@example.com", subject: "テスト")

    ReservedDomainInterceptor.delivering_email(message)

    assert_not message.perform_deliveries
  end

  test "実在するドメイン宛てのメールはそのまま送られる" do
    message = Mail.new(to: "user@gmail.com", subject: "テスト")

    ReservedDomainInterceptor.delivering_email(message)

    assert message.perform_deliveries
    assert_equal [ "user@gmail.com" ], message.to
  end

  test "宛先が混ざっている場合は、届く宛先だけに絞って送られる" do
    message = Mail.new(to: [ "demo@example.com", "user@gmail.com" ], subject: "テスト")

    ReservedDomainInterceptor.delivering_email(message)

    assert message.perform_deliveries
    assert_equal [ "user@gmail.com" ], message.to
  end

  # ============================================================
  # 登録設定（本番だけで登録されること）
  # ============================================================
  #
  # 【ファイルの中身で確認する理由】
  #   登録は本番環境でしか実行されないため、テスト環境では動きを確かめられない。
  #   設定ファイルに「本番だけで登録する」記述があることを確認する。
  test "インターセプターは本番環境だけで登録される設定になっている" do
    initializer = Rails.root.join("config/initializers/mail_interceptors.rb").read

    assert_includes initializer,
                    "ActionMailer::Base.register_interceptor(ReservedDomainInterceptor) if Rails.env.production?"
  end
end
