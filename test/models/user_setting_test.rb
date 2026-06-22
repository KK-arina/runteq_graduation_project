# test/models/user_setting_test.rb
#
# ==============================================================================
# UserSetting モデルテスト（H-4: touch_analytics_viewed_at! の単体検証）
# ==============================================================================

require "test_helper"

class UserSettingTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "touch_analytics_viewed_at! は last_analytics_viewed_at を現在時刻に更新する" do
    travel_to Time.zone.local(2026, 6, 24, 12, 30, 0) do
      assert_nil @user.user_setting.last_analytics_viewed_at

      @user.user_setting.touch_analytics_viewed_at!

      assert_equal Time.zone.local(2026, 6, 24, 12, 30, 0),
                   @user.user_setting.last_analytics_viewed_at
    end
  end

  test "touch_analytics_viewed_at! はバリデーションをスキップしてDBに即時反映される" do
    travel_to Time.zone.local(2026, 6, 24, 12, 30, 0) do
      @user.user_setting.touch_analytics_viewed_at!

      # reload してもDBから取得した値が一致することを確認する
      # （メモリ上の値とDB上の値が乖離していないことの検証）
      @user.user_setting.reload
      assert_equal Time.zone.local(2026, 6, 24, 12, 30, 0),
                   @user.user_setting.last_analytics_viewed_at
    end
  end
end