# test/jobs/weekly_report_job_test.rb
require "test_helper"

class WeeklyReportJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def setup
    # ----------------------------------------------------------
    # 【重要】fixture ユーザーの weekly_report_enabled を全て false にリセットする
    # ----------------------------------------------------------
    #
    # 【なぜリセットが必要か】
    #   fixtures :all により test/fixtures/user_settings.yml の全データが
    #   テスト DB に読み込まれる。
    #   fixture の user_settings には weekly_report_enabled: true のレコードが
    #   複数存在するため、このテストで作る @target_user 以外にも
    #   メールが送られてしまい assert_emails の件数が合わなくなる。
    #
    # 【update_all を使う理由】
    #   全レコードを1本の SQL で一括更新できるため高速。
    #   バリデーション・コールバックをスキップするため副作用がない。
    UserSetting.update_all(weekly_report_enabled: false)

    # 送信対象ユーザー（weekly_report_enabled: true・メールアドレスあり）
    @target_user = User.create!(
      name:                  "対象ユーザー",
      email:                 "target@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    # after_create で UserSetting が自動生成される（default: true）
    # 明示的に true を設定してテストの意図を明確にする
    @target_user.user_setting.update!(weekly_report_enabled: true)

    # 非対象ユーザー 1: weekly_report_enabled = false
    @disabled_user = User.create!(
      name:                  "無効ユーザー",
      email:                 "disabled@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    @disabled_user.user_setting.update!(weekly_report_enabled: false)

    # 非対象ユーザー 2: 退会済み
    @deleted_user = User.create!(
      name:                  "退会ユーザー",
      email:                 "deleted@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    @deleted_user.update_column(:deleted_at, Time.current)
  end

  # ============================================================
  # テスト 1: 対象ユーザーにメールが 1 件送信される
  # ============================================================
  test "weekly_report_enabled が true のユーザーにメールが送信される" do
    assert_emails 1 do
      WeeklyReportJob.new.perform
    end
  end

  # ============================================================
  # テスト 2: weekly_report_enabled = false のユーザーにはメールが送られない
  # ============================================================
  test "weekly_report_enabled が false のユーザーにはメールが送信されない" do
    @target_user.user_setting.update!(weekly_report_enabled: false)

    assert_emails 0 do
      WeeklyReportJob.new.perform
    end
  end

  # ============================================================
  # テスト 3: 退会済みユーザーにはメールが送られない
  # ============================================================
  test "退会済みユーザーにはメールが送信されない" do
    @target_user.update_column(:deleted_at, Time.current)

    assert_emails 0 do
      WeeklyReportJob.new.perform
    end
  end

  # ============================================================
  # テスト 4: 1ユーザーの送信失敗が他ユーザーに影響しない（堅牢性テスト）
  # ============================================================
  test "1人のユーザーへの送信が失敗しても他ユーザーへの送信は継続される" do
    another_user = User.create!(
      name:                  "二人目ユーザー",
      email:                 "another@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    another_user.user_setting.update!(weekly_report_enabled: true)

    original_report = WeeklyReportMailer.method(:report)

    WeeklyReportMailer.stub(:report, ->(user, reflection, stats) {
      if user.id == @target_user.id
        raise StandardError, "テスト用の強制エラー"
      else
        original_report.call(user, reflection, stats)
      end
    }) do
      # @target_user は失敗・another_user は成功 → 合計 1 件
      assert_emails 1 do
        WeeklyReportJob.new.perform
      end
    end
  end
end