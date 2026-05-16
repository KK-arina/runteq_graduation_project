# app/jobs/task_alarm_job.rb
#
# ==============================================================================
# TaskAlarmJob - タスクアラーム通知ジョブ
# ==============================================================================
#
# 【E-4 変更点】
#   通知処理を NotificationService に委譲するよう変更した。
#   変更前: このジョブ内に直接 LINE/メール送信ロジックを書いていた
#   変更後: NotificationService.new(user: user).send_alarm(task: task) に委譲
#
#   【変更の理由】
#     NotificationService に deep_link_url の生成・管理・ログ記録を集約することで、
#     将来 LINE通知（G-1）やメール通知の変更が1箇所で済むようになる（DRY原則）。
# ==============================================================================

class TaskAlarmJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task         = Task.find(task_id)
    user         = task.user
    user_setting = user.user_setting

    # ============================================================
    # 通知条件チェック（スキップ判定）
    # ============================================================

    # ① アラームが無効になっていたらスキップ
    unless task.alarm_enabled?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: alarm_enabled=false のためスキップ"
      return
    end

    # ② scheduled_at が未設定ならスキップ
    unless task.scheduled_at.present?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: scheduled_at=nil のためスキップ"
      return
    end

    # ③ タスクがすでに完了・アーカイブされていたらスキップ
    if task.done? || task.archived?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: status=#{task.status} のためスキップ"
      return
    end

    # ④ 通知設定が無効ならスキップ
    unless user_setting&.notification_enabled?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: notification_enabled=false のためスキップ"
      return
    end

    # ⑤ daily_notification_count が上限に達していたらスキップ
    if user_setting.daily_notification_count >= user_setting.daily_notification_limit
      NotificationLog.record_skip(
        user:              user,
        notification_type: :alarm,
        channel:           user_setting.line_notification_enabled? ? :line : :email,
        target:            task,
        deep_link_url:     "/tasks/#{task.id}",
        reason:            "daily_notification_count が上限（#{user_setting.daily_notification_limit}）に達しているためスキップ"
      )
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: 日次通知上限に達したためスキップ"
      return
    end

    # ============================================================
    # E-4 変更: NotificationService に通知処理を委譲する
    # ============================================================
    #
    # 【変更前】このジョブ内に直接送信ロジックを書いていた
    # 【変更後】NotificationService に委譲することで責務を分離する
    #
    # NotificationService の内部で:
    #   - LINE or メールのどちらを使うか判定する
    #   - deep_link_url を生成してメッセージに埋め込む
    #   - notification_logs に記録する
    NotificationService.new(user: user).send_alarm(task: task)

    # ============================================================
    # daily_notification_count のインクリメント
    # ============================================================
    #
    # 【なぜ NotificationService の外でインクリメントするのか】
    #   NotificationService は「送信」だけを担当するシングルレスポンシビリティ設計。
    #   カウント管理はジョブ側（呼び出し元）が責任を持つことで責務を分離する。
    #   NotificationService が例外を発生させた場合は increment が呼ばれないため、
    #   失敗時に誤ってカウントが増えることもない。
    increment_notification_count!(user_setting)
  end

  private

  # ============================================================
  # increment_notification_count!（修正版: プレースホルダー方式）
  # ============================================================
  #
  # 【修正前の問題（SQL文字列埋め込みの危険性）】
  #   update_all("..., last_notification_sent_at = '#{Time.current.utc.iso8601}'")
  #   この書き方は SQL 文字列に Ruby の式を直接展開している。
  #   問題点:
  #     1. 時刻フォーマットが DB 種別（PostgreSQL/MySQL）によって動作が変わる場合がある
  #     2. Rails の sanitization 機能を通さないためセキュリティ的に良くない
  #
  # 【修正後: プレースホルダー方式（? による安全な値の渡し方）】
  #   update_all(["..., last_notification_sent_at = ?", Time.current])
  #   ? の部分に渡した値は Rails が自動的にエスケープ・型変換してSQLに組み込む。
  #   これにより:
  #     - DB種別を問わず正しい時刻フォーマットで保存される
  #     - Rails の sanitization 機能が有効になる
  #
  # 【atomic 更新（レースコンディション対策）は変更なし】
  #   "daily_notification_count = daily_notification_count + 1" という
  #   DB側での計算は維持する。
  #   Ruby側で count + 1 を計算すると複数ジョブ同時実行時に競合する。
  #   DB側で計算させることで原子的操作になり競合しない。
  def increment_notification_count!(user_setting)
    UserSetting
      .where(id: user_setting.id)
      .update_all(
        # 配列の第1要素: SQL文字列（? が値の挿入箇所）
        # 配列の第2要素: ? に当てはめる値（Rails が自動で型変換・エスケープ）
        [
          "daily_notification_count = daily_notification_count + 1, last_notification_sent_at = ?",
          Time.current
        ]
      )

    Rails.logger.info "[TaskAlarmJob] daily_notification_count を +1 しました: user_setting_id=#{user_setting.id}"
  end
end