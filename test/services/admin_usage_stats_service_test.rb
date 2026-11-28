# test/services/admin_usage_stats_service_test.rb
#
# ==============================================================================
# AdminUsageStatsService（管理画面の全体の集計）のテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 集計の対象（User.countable_for_usage）の人だけを数え、予約ドメイン・退会済み・管理者は数えない
#   ② アクティブ数・週ごとの新規登録・ログイン保持・ファネルが正しく数えられる
#   ③ 対象が0人でも、割合の計算で 0 で割るエラーにならない
#
# 【テストの前提】
#   fixture のユーザーはすべて @example.com（予約ドメイン）なので、集計の対象にならない。
#   setup で users(:one) だけをふつうのドメインに書き換え、「対象は1人」の状態から始める。
#   習慣・記録などの件数は fixture の内容によって変わるため、
#   users(:one) の分だけを別の SQL で数えた値と比べる。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/services/admin_usage_stats_service_test.rb
# ==============================================================================
require "test_helper"

class AdminUsageStatsServiceTest < ActiveSupport::TestCase
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]
    ENV.delete("ADMIN_EMAILS")

    @user = users(:one)
    @user.update_columns(email: "real-user@gmail.com")
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  def stats
    AdminUsageStatsService.new.call
  end

  # ── ① 集計の対象 ─────────────────────────────────────────────────
  test "集計の対象の人だけを数える（予約ドメインの fixture ユーザーは数えない）" do
    result = stats

    assert_equal 1, result[:total_users]
    assert_equal({ "email" => 1 }, result[:provider_breakdown])
  end

  test "習慣・記録・振り返りは、集計の対象の人の分だけを数える" do
    result = stats

    assert_equal HabitRecord.where(user_id: @user.id, deleted_at: nil).count, result[:habit_records_total]
    assert_equal WeeklyReflection.where(user_id: @user.id).count, result[:reflections_total]
    assert_equal WeeklyReflection.where(user_id: @user.id).where.not(completed_at: nil).count,
                 result[:reflections_completed]
  end

  test "退会済みのユーザーは数えない" do
    users(:two).update_columns(email: "other-user@gmail.com", deleted_at: Time.current)

    assert_equal 1, stats[:total_users]
  end

  # ── ② 個別の集計 ─────────────────────────────────────────────────
  test "直近7日・30日のアクティブ数を last_active_at から数える" do
    @user.update_columns(last_active_at: 2.days.ago)
    result = stats
    assert_equal 1, result[:active_7d]
    assert_equal 1, result[:active_30d]

    @user.update_columns(last_active_at: 20.days.ago)
    result = stats
    assert_equal 0, result[:active_7d]
    assert_equal 1, result[:active_30d]
  end

  test "週ごとの新規登録は12週分で、今週に登録した人が最後の週に入る" do
    @user.update_columns(created_at: Time.current)

    series = stats[:signups_by_week]

    assert_equal AdminUsageStatsService::WEEKS, series.size
    assert_equal Date.current.beginning_of_week(:monday), series.last[:week_start]
    assert_equal 1, series.last[:count]
  end

  test "ログイン保持中のユーザー数を数える" do
    assert_equal 0, stats[:remember_users]

    RememberToken.issue_for!(@user)

    assert_equal 1, stats[:remember_users]
  end

  test "ファネルは決まった順番で、最初の段階は登録した人数になる" do
    funnel = stats[:funnel]

    assert_equal %i[registered onboarding_passed habit_created first_record recorded_7_days reflection_completed],
                 funnel.map { |step| step[:key] }
    assert_equal 1, funnel.first[:count]
    assert_equal 100.0, funnel.first[:rate]
  end

  # ── ③ 対象が0人 ──────────────────────────────────────────────────
  test "管理者自身は数えず、対象が0人でも割合は 0 になる" do
    ENV["ADMIN_EMAILS"] = @user.email

    result = stats

    assert_equal 0, result[:total_users]
    assert_equal 0.0, result[:onboarding_rate]
    assert_equal 0.0, result[:reflections_completion_rate]
    assert(result[:funnel].all? { |step| step[:rate].zero? })
  end
end
