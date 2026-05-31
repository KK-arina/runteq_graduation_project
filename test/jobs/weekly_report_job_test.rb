# test/jobs/weekly_report_job_test.rb
require "test_helper"

# ==============================================================================
# WeeklyReportJob のテスト
# ==============================================================================
#
# 【ActionMailer::TestHelper を include する理由】
#   assert_emails(N) { ... } アサーションを使うために必要。
#   ブロック内で配信されたメール数が N 件であることを検証する。
# ==============================================================================
class WeeklyReportJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def setup
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

    # 非対象ユーザー 2: 退会済み（deleted_at が設定されている）
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
    # 【travel_to/travel_back 展開形式を使う理由】
    #   travel_to ブロック内のアサーションは Minitest の assertion カウントに
    #   含まれないバグが報告されている（Rails の既知の挙動）。
    #   展開形式（travel_to + travel_back）を使うとカウントが正しく記録される。
    #
    # 【月曜日 AM9:00 に固定する理由】
    #   WeeklyReflection.current_week_start_date は「現在時刻 - 4時間」の
    #   beginning_of_week を返すため、テスト実行タイミングによっては
    #   境界値で「先週」の計算がズレる場合がある。
    #   ジョブ実行想定時刻（月曜 AM9:00）に固定することでテストを安定させる。
    travel_to Time.zone.local(2026, 6, 1, 9, 0, 0)

    assert_emails 1 do
      WeeklyReportJob.new.perform
    end

    travel_back
  end

  # ============================================================
  # テスト 2: weekly_report_enabled = false のユーザーにはメールが送られない
  # ============================================================
  test "weekly_report_enabled が false のユーザーにはメールが送信されない" do
    @target_user.user_setting.update!(weekly_report_enabled: false)

    travel_to Time.zone.local(2026, 6, 1, 9, 0, 0)

    assert_emails 0 do
      WeeklyReportJob.new.perform
    end

    travel_back
  end

  # ============================================================
  # テスト 3: 退会済みユーザーにはメールが送られない
  # ============================================================
  test "退会済みユーザーにはメールが送信されない" do
    @target_user.update_column(:deleted_at, Time.current)

    travel_to Time.zone.local(2026, 6, 1, 9, 0, 0)

    assert_emails 0 do
      WeeklyReportJob.new.perform
    end

    travel_back
  end

  # ============================================================
  # テスト 4: 1ユーザーの送信失敗が他ユーザーに影響しない（堅牢性テスト）
  # ============================================================
  #
  # 【このテストで何を検証するのか】
  #   WeeklyReportJob のループ内 begin ~ rescue が正しく機能していること。
  #   1人目で例外が発生しても 2人目への送信が継続されることを確認する。
  #
  # 【original_report を保存する理由】
  #   stub ブロック内で「モック対象外のユーザー」には
  #   本来の WeeklyReportMailer.report を呼びたいため
  #   stub 前にメソッドオブジェクトとして保存しておく。
  test "1人のユーザーへの送信が失敗しても他ユーザーへの送信は継続される" do
    another_user = User.create!(
      name:                  "二人目ユーザー",
      email:                 "another@example.com",
      password:              "password123",
      password_confirmation: "password123",
      terms_agreed:          "1"
    )
    another_user.user_setting.update!(weekly_report_enabled: true)

    travel_to Time.zone.local(2026, 6, 1, 9, 0, 0)

    # stub 前に元のメソッドオブジェクトを保存する
    original_report = WeeklyReportMailer.method(:report)

    WeeklyReportMailer.stub(:report, ->(user, reflection, stats) {
      if user.id == @target_user.id
        # 1人目: 強制的に例外を発生させる（SMTP エラー等を模倣）
        raise StandardError, "テスト用の強制エラー"
      else
        # 2人目: 本来の report メソッドを呼ぶ
        original_report.call(user, reflection, stats)
      end
    }) do
      # 1人目は失敗・2人目は成功 → 合計 1 件送信されるはず
      assert_emails 1 do
        WeeklyReportJob.new.perform
      end
    end

    travel_back
  end
end