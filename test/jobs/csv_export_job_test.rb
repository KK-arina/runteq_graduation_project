# test/jobs/csv_export_job_test.rb
#
# ==============================================================================
# CsvExportJob テスト（I-1: 非同期CSVフローのジョブ実行部分）
# ==============================================================================
#
# 【このテストの役割】
#   1000件超のCSVはバックグラウンドで生成→ダウンロードURL入りのメールを送る。
#   CsvExportsController のテストは「ジョブが積まれる」ところまでを担保しているため、
#   ここでは「積まれたジョブを実際に実行したときにメールが送られる」ことを検証する。
#
# 【メール送信の検証方法】
#   test環境は delivery_method が :test のため、送信したメールは
#   ActionMailer::Base.deliveries に溜まる。
#   assert_emails / assert_no_emails（ActionMailer::TestHelper）で件数を検証する。
# ==============================================================================
require "test_helper"

class CsvExportJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
  end

  test "perform: CSV生成後にダウンロードURL入りの完了メールを1通送信する" do
    # perform_now でジョブを同期実行する（キューに積まず即実行）
    assert_emails 1 do
      CsvExportJob.perform_now(@user.id, "habit_records")
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @user.email ], mail.to,            "送信先はリクエストユーザー"
    assert_match(/HabitFlow/, mail.subject)
    assert_match(/習慣記録/,   mail.subject,          "件名に種別ラベルが入る")

    # 【修正】本文はマルチパート(text/html)かつ Base64 エンコードされているため、
    #   mail.body.encoded（生のMIME文字列＝Base64のまま）ではURLに一致しない。
    #   text_part / html_part を decoded（復号）してから中身を検証する。
    decoded_body = [
      mail.text_part&.body&.decoded,
      mail.html_part&.body&.decoded
    ].compact.join("\n")
    assert_match(/download_csv/, decoded_body, "本文にダウンロードURLが含まれる")
  end

  test "perform: email未設定(LINEログイン等)のユーザーにはメールを送らず正常終了する" do
    # LINEログインユーザーは email が nil のことがある（送りようがない）
    line_user = User.create!(
      name:     "LINEユーザー",
      provider: "line_v2_1",
      uid:      "line_#{SecureRandom.hex(4)}",
      email:    nil
    )

    # メールは1通も送られない（ログだけ残して正常終了する設計）
    assert_no_emails do
      CsvExportJob.perform_now(line_user.id, "tasks")
    end
  end
end