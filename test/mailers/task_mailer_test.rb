# test/mailers/task_mailer_test.rb
#
# ==============================================================================
# TaskMailer のテスト
# ==============================================================================
#
# 【このファイルの役割】
#   TaskMailer#alarm_notification が正しいメールを生成するかを確認する。
#   実際には送信せず、メールオブジェクトの内容（宛先・件名・本文）を検証する。
#
# 【自動生成ファイルからの修正点】
#   bin/rails generate mailer で自動生成されたコードは
#   引数なしで alarm_notification を呼んでいたためエラーになった。
#   alarm_notification は task インスタンスを引数に必要とするため、
#   setup でテスト用データを作成して渡すよう修正した。
# ==============================================================================
require "test_helper"

class TaskMailerTest < ActionMailer::TestCase
  def setup
    @user = User.create!(
      name:     "メールテストユーザー",
      email:    "mailer_test@example.com",
      password: "password123"
    )

    UserSetting.create!(
      user:      @user,
      time_zone: "Asia/Tokyo"
    )

    @task = Task.create!(
      user:                 @user,
      title:                "メールテストタスク",
      priority:             :must,
      alarm_enabled:        true,
      scheduled_at:         1.hour.from_now,
      alarm_minutes_before: 30
    )
  end

  def test_alarm_notification
    mail = TaskMailer.alarm_notification(@task)

    assert_includes mail.subject, @task.title,
                    "件名にタスク名が含まれるべきです"

    assert_includes mail.to, @user.email,
                    "宛先がユーザーのメールアドレスであるべきです"

    assert_includes mail.from, "onboarding@resend.dev",
                    "送信元が HabitFlow のアドレスであるべきです"
  end
end
