# test/jobs/rest_mode_expiry_job_test.rb（新規作成）
#
# ==============================================================================
# RestModeExpiryJobTest（G-4 新規作成 / Job テストを分離）
# ==============================================================================
#
# 【分離した理由】
#   Job のテストは Controller テストと責務が異なる。
#   test/controllers/ に混在すると失敗原因の特定が難しくなるため分離する。
# ==============================================================================
require "test_helper"

class RestModeExpiryJobTest < ActiveJob::TestCase

  setup do
    @user         = users(:one)
    @user_setting = @user.user_setting ||
                    UserSetting.find_or_create_by!(user: @user)
    # テスト開始前にお休みモードをリセットする
    @user_setting.update_columns(rest_mode_until: nil, rest_mode_reason: nil)
  end

  # ===========================================================================
  # テスト: 期限切れのお休みモードを自動解除する
  # ===========================================================================

  test "期限切れの rest_mode_until を持つ設定を NULL にリセットする" do
    # 1時間前を終了時刻として設定（= 期限切れ）
    # update_columns を使う理由:
    #   テストデータの準備なので callbacks をスキップして直接設定する。
    #   バリデーションが走ると rest_mode_until < Time.current でエラーになる可能性がある。
    @user_setting.update_columns(
      rest_mode_until:  1.hour.ago,
      rest_mode_reason: "テスト用期限切れデータ"
    )

    RestModeExpiryJob.new.perform

    @user_setting.reload
    assert_nil @user_setting.rest_mode_until,
               "期限切れの rest_mode_until は nil になるべき"
    assert_nil @user_setting.rest_mode_reason,
               "期限切れの rest_mode_reason は nil になるべき"
  end

  # ===========================================================================
  # テスト: 有効なお休みモードはリセットしない
  # ===========================================================================

  test "未来の rest_mode_until を持つ設定はリセットしない" do
    future_time = 3.days.from_now
    @user_setting.update_columns(
      rest_mode_until:  future_time,
      rest_mode_reason: "有効なお休み"
    )

    RestModeExpiryJob.new.perform

    @user_setting.reload
    assert_not_nil @user_setting.rest_mode_until,
                   "未来の rest_mode_until はリセットされるべきでない"
    assert_equal "有効なお休み", @user_setting.rest_mode_reason,
                 "未来の rest_mode_reason はリセットされるべきでない"
  end

  # ===========================================================================
  # テスト: rest_mode_until が nil のレコードに影響しない
  # ===========================================================================

  test "rest_mode_until が nil の設定には影響しない" do
    # nil のまま（お休みモードなし）
    assert_nil @user_setting.rest_mode_until

    RestModeExpiryJob.new.perform

    @user_setting.reload
    assert_nil @user_setting.rest_mode_until, "nil のままであるべき"
  end
end