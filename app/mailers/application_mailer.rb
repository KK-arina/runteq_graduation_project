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
  # "HabitFlow <onboarding@resend.dev>"
  #   - "HabitFlow"           → メールクライアントに表示される送信者名
  #   - onboarding@resend.dev → 実際の送信元メールアドレス
  #   - この形式で書くことでGmailなどで「HabitFlow」と表示される
  #
  # 【独自ドメインがある場合の変更例】
  # "HabitFlow <noreply@yourdomain.com>"
  #   → SPF/DKIM設定済みの独自ドメインを使うとスパム判定されにくい
  #
  # 【現在 onboarding@resend.dev を使う理由】
  # Resendが提供するテスト用アドレス。
  # 独自ドメインのDNS設定（SPF/DKIM）が完了するまでの暫定対応として使用。
  # 将来的には独自ドメインのアドレスに変更することを推奨。
  default from: "HabitFlow <onboarding@resend.dev>"

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