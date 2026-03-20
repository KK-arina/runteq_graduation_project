# ==============================================================================
# app/jobs/daily_notification_count_reset_job.rb
# ==============================================================================
#
# 【このジョブの役割】
# 毎日 JST 00:05 に user_settings.daily_notification_count を 0 にリセットする。
#
# 【daily_notification_count とは】
# LINE や メールの通知を「1日に何回送ったか」のカウンター。
# user_settings.daily_notification_limit（デフォルト: 5）を超えると
# その日はそれ以上通知を送らない（スパム防止）。
# 翌日になったらカウンターを 0 に戻す必要がある。
#
# 【なぜ JST 00:00 にリセットするのか】
# 「今日」の通知上限は「カレンダー上の1日（0:00〜23:59）」で管理するのが
# ユーザーにとって自然なため。
# HabitFlow では習慣記録の日跨ぎ基準は AM4:00 だが、
# 通知カウントはカレンダー日付基準でリセットする。
# ==============================================================================
class DailyNotificationCountResetJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[DailyNotificationCountResetJob] 開始: #{Time.current}"

    # update_all を使う理由:
    # ActiveRecord の update_all は SQL の UPDATE を1クエリで発行する。
    # 全ユーザーを1件ずつ update すると N 回の SQL が発生するが、
    # update_all なら1回のみ。数千ユーザーいても高速で安全。
    #
    # reset_count: リセットしたレコード数（ログ確認用）
    reset_count = UserSetting.update_all(
      daily_notification_count: 0,
      # notification_count_reset_at: リセットを実行した日時を記録する。
      # 「最後にリセットしたのはいつか」をデバッグ時に確認できるようにする。
      notification_count_reset_at: Time.current
    )

    Rails.logger.info "[DailyNotificationCountResetJob] #{reset_count} 件をリセット完了: #{Time.current}"
  end
end