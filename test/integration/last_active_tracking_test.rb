# test/integration/last_active_tracking_test.rb
#
# ==============================================================================
# 最終利用日時の記録（app/controllers/concerns/last_active_tracking.rb）の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① ログイン中のユーザーが画面を開くと記録され、同じ日の2回目以降は変わらない
#   ② 次の日に開くと、その日の時刻で更新される
#   ③ 未ログインのアクセス・/up・管理者自身のアクセスは記録されない
#
# 【travel_to を使う理由】
#   「同じ日」「次の日」をはっきり作るため、テストの中だけ現在時刻を固定する。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/last_active_tracking_test.rb
# ==============================================================================
require "test_helper"

class LastActiveTrackingTest < ActionDispatch::IntegrationTest
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]
    # 管理者は誰もいない状態から始める（管理者のテストでだけ設定する）
    ENV.delete("ADMIN_EMAILS")

    @user = users(:one)
    @user.update_columns(last_active_at: nil)
    @morning = Time.zone.local(2026, 11, 27, 10, 0, 0)
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  test "ログイン中に画面を開くと記録され、同じ日の2回目以降は変わらない" do
    travel_to @morning do
      log_in_as(@user)
      get dashboard_path
    end
    assert_equal @morning, @user.reload.last_active_at

    travel_to @morning.change(hour: 18) do
      get dashboard_path
    end
    assert_equal @morning, @user.reload.last_active_at
  end

  test "次の日に開くと、その日の時刻で更新される" do
    travel_to @morning do
      log_in_as(@user)
      get dashboard_path
    end

    next_day = @morning + 1.day
    travel_to next_day do
      get dashboard_path
    end
    assert_equal next_day, @user.reload.last_active_at
  end

  test "未ログインのアクセスでは記録されない" do
    get root_path
    get login_path

    assert_nil @user.reload.last_active_at
  end

  test "Render を起こすための /up では記録されない" do
    # log_in_as は POST /login だけを送り、ログイン後の画面は開かない
    #   （POST の時点ではまだ未ログインなので、ここでは記録されない）
    log_in_as(@user)

    get rails_health_check_path

    assert_response :success
    assert_nil @user.reload.last_active_at
  end

  test "管理者自身のアクセスは記録されない" do
    ENV["ADMIN_EMAILS"] = @user.email
    log_in_as(@user)

    get admin_root_path
    get dashboard_path

    assert_response :success
    assert_nil @user.reload.last_active_at
  end
end
