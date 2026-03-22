# app/mailers/test_mailer.rb

# ============================================================
# TestMailer - Resend動作確認用メイラー
# ============================================================
#
# 【このクラスの目的】
# Resendの設定が正しく動作するかを確認するための一時的なメイラー。
# 本番確認後は削除するか、このコメントのまま残して参照用にする。
#
# 【使用方法】
# rails runner "TestMailer.send_test('your@email.com').deliver_now"
class TestMailer < ApplicationMailer
  # ============================================================
  # テストメール送信メソッド
  # ============================================================
  #
  # 【引数】
  # to_address: 送信先メールアドレス（文字列）
  #
  # 【mail()メソッドの役割】
  # Action Mailerが提供するメール組み立てメソッド。
  # to:      → 宛先アドレス
  # subject: → 件名（メールボックスに表示される）
  # body:    → 本文（シンプルなテキストのみのメールを送る場合）
  #
  # 【deliver_now vs deliver_later】
  # deliver_now    → 即時送信（動作確認に使用）
  # deliver_later  → GoodJobのキューに積んで非同期送信（本番での推奨）
  def send_test(to_address)
    mail(
      to:      to_address,
      subject: "【HabitFlow】Resendメール送信テスト",
      body:    "このメールはHabitFlowのResend設定テストです。\n受信できていれば設定は成功です。"
    )
  end
end