# app/mailers/password_mailer.rb
#
# ==============================================================================
# PasswordMailer - パスワードリセットメール送信
# ==============================================================================
#
# 【このメイラーの役割】
#   ユーザーにパスワードリセット用のメールを送信する。
#   メール内のURLにトークンを含め、クリックするとパスワード変更画面に遷移する。
#
# 【Resend経由での送信について】
#   config/environments/production.rb に delivery_method: :resend が設定済み。
#   開発環境では delivery_method: :letter_opener でブラウザに表示される。
#   このメイラー自体は環境を意識せず deliver_later を呼ぶだけでよい。
#
# 【deliver_later について】
#   GoodJob のキューにジョブを登録して非同期で送信する。
#   ユーザーのリクエストをブロックせず、画面レスポンスを即座に返せる。
#   deliver_now は同期送信（メール送信完了を待ってからレスポンスを返す）。
#   ポートフォリオ用途では deliver_later を推奨（本番 UX の良さをアピールできる）。
#
# ==============================================================================
class PasswordMailer < ApplicationMailer
  # reset_password(user, raw_token)
  #
  # 【役割】
  #   パスワードリセット用メールを作成して返す。
  #   コントローラーで .reset_password(user, raw_token).deliver_later と呼ぶ。
  #
  # 【引数】
  #   user      : パスワードリセットを申請した User インスタンス
  #   raw_token : PasswordResetToken.generate_token_for(user) が返した生トークン
  #
  # 【mail メソッドの引数】
  #   to:      → 送信先メールアドレス
  #   subject: → 件名（メールクライアントの受信トレイに表示される）
  #
  # 【インスタンス変数 @user, @reset_url をビューに渡す理由】
  #   Rails のメイラーはコントローラーと同じ仕組みで、
  #   インスタンス変数を定義するとビュー（ERB テンプレート）から参照できる。
  #   @user      → ビューでユーザー名を表示するために使う
  #   @reset_url → ビューでリセットリンクを表示するために使う
  def reset_password(user, raw_token)
    @user = user

    # edit_password_reset_url(raw_token) について
    #
    # 【なぜ _path ではなく _url を使うのか】
    #   メール内のリンクは「絶対URL」が必要。
    #   _path は "/password_resets/abc123/edit" のような相対パスを返す。
    #   メールクライアントは相対パスを解釈できないため、
    #   _url を使って "https://habitflow.onrender.com/password_resets/abc123/edit"
    #   のような絶対URLを生成する。
    #   ドメイン部分は config/environments/production.rb の
    #   config.action_mailer.default_url_options で設定済み。
    @reset_url = edit_password_reset_url(raw_token)

    mail(
      to:      @user.email,
      subject: "【HabitFlow】パスワードをリセットしてください"
    )
  end
end