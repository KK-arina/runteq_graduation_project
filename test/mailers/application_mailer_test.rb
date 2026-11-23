# test/mailers/application_mailer_test.rb
require "test_helper"

# 全メールの送信元（ApplicationMailer の default from）を確認するテスト
#
# 【このテストを追加した理由】
#   送信元のドメインは Resend で確認したドメインと完全に一致していないと送れない。
#   テスト用アドレス（onboarding@resend.dev）に戻ったり、
#   mail. の付かないドメインに変わったりすると、本番でメールが届かなくなるため、
#   テストで守る。
class ApplicationMailerTest < ActiveSupport::TestCase
  test "送信元は Resend で確認済みの独自ドメインのアドレス" do
    assert_equal "HabitFlow <no-reply@mail.habitflow-arina.com>", ApplicationMailer.default[:from]
  end

  test "送信元は Resend のテスト用アドレスではない" do
    assert_not_includes ApplicationMailer.default[:from], "onboarding@resend.dev"
  end
end
