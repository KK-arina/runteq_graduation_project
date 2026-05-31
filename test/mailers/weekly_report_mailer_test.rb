# test/mailers/weekly_report_mailer_test.rb
require "test_helper"

class WeeklyReportMailerTest < ActionMailer::TestCase

  def setup
    @user = User.create!(
      name:                  "テストユーザー",
      email:                 "test@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )

    @last_week_start = WeeklyReflection.current_week_start_date - 7.days
    @last_week_end   = @last_week_start + 6.days

    @reflection = WeeklyReflection.create!(
      user:                 @user,
      week_start_date:      @last_week_start,
      week_end_date:        @last_week_end,
      direct_reason:        "テストの直接原因",
      background_situation: "テストの改善策",
      next_action:          "テストの次のアクション",
      mood:                 4,
      completed_at:         Time.current
    )

    @habit_stats = [
      { name: "毎日読書",   rate: 85, completed: 6, target: 7 },
      { name: "ジョギング", rate: 57, completed: 4, target: 7 }
    ]
  end

  test "振り返りありの場合にメールが正しく送信される" do
    mail = WeeklyReportMailer.report(@user, @reflection, @habit_stats)

    assert_equal ["test@example.com"], mail.to
    assert_not_empty mail.from

    # 件名フォーマット: 「【HabitFlow】先週（期間）の振り返りレポートが届きました」
    assert_includes mail.subject, "HabitFlow"
    assert_includes mail.subject, "レポートが届きました"

    html_body = mail.html_part.body.decoded
    assert_includes html_body, "テストユーザー"
    assert_includes html_body, "テストの直接原因"
    assert_includes html_body, "毎日読書"
    assert_includes html_body, "weekly_reflections/new"
    assert_includes mail.text_part.body.decoded, "weekly_reflections/new"
  end

  test "振り返りなしの場合でもメールが送信される" do
    mail = WeeklyReportMailer.report(@user, nil, @habit_stats)

    assert_equal ["test@example.com"], mail.to
    assert_includes mail.html_part.body.decoded, "提出されていません"
  end

  test "習慣なしの場合でもメールが送信される" do
    mail = WeeklyReportMailer.report(@user, @reflection, [])

    assert_equal ["test@example.com"], mail.to
    assert_includes mail.html_part.body.decoded, "登録されていません"
  end
end