# test/helpers/admin/users_helper_test.rb
#
# ==============================================================================
# Admin::UsersHelper#masked_email（メールアドレスの伏せ字）のテスト
# ==============================================================================
require "test_helper"

module Admin
  class UsersHelperTest < ActionView::TestCase
    test "@ より前を1文字だけ残して伏せ字にする" do
      assert_equal "t***@gmail.com", masked_email("taro.yamada@gmail.com")
    end

    test "1文字のアドレスでもドメインは残す" do
      assert_equal "a***@example.org", masked_email("a@example.org")
    end

    test "メールがない（LINE ログイン）ときは nil を返す" do
      assert_nil masked_email(nil)
      assert_nil masked_email("")
    end
  end
end
