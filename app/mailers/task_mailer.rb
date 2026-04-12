# app/mailers/task_mailer.rb
#
# ==============================================================================
# TaskMailer - タスクアラーム通知メイラー
# ==============================================================================
#
# 【このクラスの役割】
#   タスクのアラーム通知メールを送信するメイラー。
#   alarm_notification メソッドが呼ばれると、
#   指定のタスク情報をメール本文に含めて送信する。
#
# 【呼び出し方（TaskAlarmJob から）】
#   TaskMailer.alarm_notification(task).deliver_now
#   → deliver_now は同期送信（ジョブ内で使うため非同期は不要）
#
# 【ApplicationMailer を継承する理由】
#   from アドレスなどの共通設定を自動で引き継ぐことができる。
#   全メイラーで同じ from 設定を繰り返し書く必要がなくなる（DRY 原則）。
# ==============================================================================

class TaskMailer < ApplicationMailer
  # ============================================================
  # alarm_notification
  # ============================================================
  #
  # 【役割】
  #   タスクのアラーム時刻が近づいたことをメールで通知する。
  #
  # 【引数】
  #   task : 通知対象の Task インスタンス
  #          task.user, task.title, task.scheduled_at などを参照する
  #
  # 【mail() メソッドの各オプション】
  #   to:      宛先メールアドレス（task.user.email から取得）
  #   subject: メールの件名（受信ボックスに表示される）
  #
  # 【なぜ @task インスタンス変数を使うのか】
  #   mail() を呼ぶ前に @task = task とセットすることで、
  #   ビューファイル（alarm_notification.html.erb）から
  #   @task としてタスク情報にアクセスできるようになる。
  #   これは Rails のコントローラー → ビュー への変数受け渡しと同じ仕組み。
  def alarm_notification(task)
    # ビューで使用するインスタンス変数をセット
    @task = task
    @user = task.user

    # scheduled_at をユーザーのタイムゾーンで表示する
    # 【user_setting の time_zone を使う理由】
    #   DB には UTC で保存されているが、
    #   ユーザーには自分のタイムゾーン（JST など）で時刻を表示したい。
    #   user_setting が存在しない場合は "Asia/Tokyo" をデフォルトとして使う。
    tz = @user.user_setting&.time_zone || "Asia/Tokyo"
    @scheduled_at_local = task.scheduled_at.in_time_zone(tz)

    mail(
      to:      @user.email,
      subject: "【HabitFlow】「#{task.title}」の予定時刻が近づいています"
    )
  end
end