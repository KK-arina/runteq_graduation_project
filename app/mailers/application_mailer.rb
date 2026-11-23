# app/mailers/application_mailer.rb

# ============================================================
# ApplicationMailer - 全メイラーの親クラス
# ============================================================
#
# 【このクラスの役割】
# HabitFlowで送信する全てのメール（パスワードリセット・週次レポートなど）の
# 共通設定を一箇所にまとめる親クラス。
# 個別のメイラー（例: PasswordResetMailer）はこのクラスを継承する。
#
# 【継承の仕組み】
# class PasswordResetMailer < ApplicationMailer
#   → PasswordResetMailerはApplicationMailerの設定を自動で引き継ぐ
#   → defaultのfromアドレスを個別に設定しなくてよい（DRY原則）
class ApplicationMailer < ActionMailer::Base
  # ============================================================
  # 送信元アドレスのデフォルト設定
  # ============================================================
  #
  # 【default from: の意味】
  # ユーザーに届くメールの「差出人（From）」欄に表示される名前とアドレス。
  # ここを一箇所で定義することで、全メールの送信元が統一される。
  #
  # 【書式の説明】
  # "HabitFlow <no-reply@mail.habitflow-arina.com>"
  #   - "HabitFlow"                         → メールクライアントに表示される送信者名
  #   - no-reply@mail.habitflow-arina.com → 実際の送信元メールアドレス
  #   - この形式で書くことでGmailなどで「HabitFlow」と表示される
  #
  # 【独自ドメイン mail.habitflow-arina.com を使う理由】
  # 以前は Resend のテスト用アドレス onboarding@resend.dev を使っていたが、
  # これは Resend アカウントの持ち主にしか届かないため、
  # ほかのユーザーにはパスワードリセットなどのメールが届かなかった。
  # Resend で mail.habitflow-arina.com を確認済み（DKIM / SPF / DMARC 設定済み）にしたため、
  # 全ユーザーに送れるようになり、迷惑メールとも判定されにくい。
  #
  # 【注意】
  # @ の後ろは Resend で確認したドメイン「mail.habitflow-arina.com」と完全に一致させる必要がある。
  # 「@habitflow-arina.com」（mail. なし）は Resend で確認していないため送信できない。
  #
  # 【no-reply にする理由】
  # Resend の受信機能（Enable receiving）は無効にしているため、返信されても受け取れない。
  # 「返信しないでください」という意味が伝わる名前にしている。
  default from: "HabitFlow <no-reply@mail.habitflow-arina.com>"

  # ============================================================
  # レイアウトテンプレートの指定
  # ============================================================
  #
  # 【layout "mailer" の意味】
  # メールのHTML外枠テンプレートとして
  # app/views/layouts/mailer.html.erb を使用する。
  #
  # Webページの layouts/application.html.erb と同じ仕組みで、
  # メール全体のヘッダー・フッター・スタイルをここで定義できる。
  # 個別のメイラービュー（例: password_reset.html.erb）は
  # このレイアウトの yield 部分に挿入される。
  layout "mailer"
end
