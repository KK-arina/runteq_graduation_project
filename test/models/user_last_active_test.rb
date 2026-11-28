# test/models/user_last_active_test.rb
#
# ==============================================================================
# User#touch_last_active!（app/models/concerns/last_activity.rb）のモデルテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 記録がない・前の日の記録しかないときは、今の時刻を記録する
#   ② 今日すでに記録していれば、何もしない（UPDATE しない）
#   ③ 手元の値が古くても、DB がすでに今日の値なら上書きしない（同時アクセス対策）
#   ④ updated_at は変えない
#
# 【実行方法】
#   docker compose exec web bin/rails test test/models/user_last_active_test.rb
# ==============================================================================
require "test_helper"

class UserLastActiveTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    # Time.zone.local: アプリのタイムゾーン（東京）の時刻を作る
    @now = Time.zone.local(2026, 11, 27, 15, 0, 0)
  end

  test "記録がなければ今の時刻を記録して true を返す" do
    @user.update_columns(last_active_at: nil)

    assert @user.touch_last_active!(@now)
    assert_equal @now, @user.reload.last_active_at
  end

  test "前の日の記録しかなければ今の時刻で更新する" do
    @user.update_columns(last_active_at: @now - 1.day)

    assert @user.touch_last_active!(@now)
    assert_equal @now, @user.reload.last_active_at
  end

  test "今日すでに記録していれば何もせず false を返す" do
    earlier_today = @now.change(hour: 9)
    @user.update_columns(last_active_at: earlier_today)

    assert_not @user.touch_last_active!(@now)
    assert_equal earlier_today, @user.reload.last_active_at
  end

  test "手元の値が古くても、DB がすでに今日の値なら上書きしない" do
    @user.update_columns(last_active_at: @now - 1.day)
    # 別のリクエスト（別の Worker）が先に今日の値を書き込んだ状態を作る
    #   update_all は手元の @user を変えないので、@user には前の日の値が残る
    earlier_today = @now.change(hour: 9)
    User.where(id: @user.id).update_all(last_active_at: earlier_today)

    assert_not @user.touch_last_active!(@now)
    assert_equal earlier_today, @user.reload.last_active_at
  end

  test "記録しても updated_at は変わらない" do
    @user.update_columns(last_active_at: nil)
    updated_at_before = @user.reload.updated_at

    @user.touch_last_active!(@now)

    assert_equal updated_at_before, @user.reload.updated_at
  end
end
