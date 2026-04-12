# app/jobs/task_alarm_job.rb
#
# ==============================================================================
# TaskAlarmJob - タスクアラーム通知ジョブ
# ==============================================================================
#
# 【このジョブの役割】
#   タスクのアラーム時刻（scheduled_at - alarm_minutes_before 分前）に
#   GoodJob によって自動実行され、LINE またはメールで通知を送る。
#
# 【実行タイミング】
#   TasksController#create / #update でタスクが保存されるとき、
#   alarm_enabled = true かつ scheduled_at が設定されていれば
#   このジョブが特定の未来時刻にスケジュールされる。
#   GoodJob は good_jobs テーブルの scheduled_at を参照し、
#   その時刻になったらジョブを実行する。
#
# 【ApplicationJob を継承する理由】
#   retry_on / discard_on などの共通設定を自動で引き継ぐ。
#   一時的なエラーは最大3回まで指数バックオフでリトライされる。
#   RecordNotFound（タスクやユーザーが削除済み）は即座に破棄される。
# ==============================================================================

class TaskAlarmJob < ApplicationJob
  # queue_as :default
  # 【キューの意味】
  #   GoodJob はキュー名ごとに優先度を変えられる。
  #   :default は標準的な優先度のキュー。
  #   将来的に :urgent（高優先）や :low（低優先）などを使い分けることもできる。
  queue_as :default

  # ============================================================
  # perform メソッド（ジョブの本体）
  # ============================================================
  #
  # 【引数】
  #   task_id : 通知対象の Task の id（インスタンスではなく id を渡す理由は後述）
  #
  # 【なぜ Task インスタンスではなく task_id を渡すのか】
  #   GoodJob はジョブの引数を JSON 形式で good_jobs テーブルに保存する。
  #   ActiveRecord のインスタンスは JSON シリアライズできないため、
  #   id（整数）を渡して perform 内で再取得する設計が標準的。
  #   また、ジョブ実行時点でタスクが削除されていた場合、
  #   find が RecordNotFound を発生させ、ApplicationJob の discard_on が
  #   即座にジョブを破棄してくれる（リトライしない正しい動作）。
  def perform(task_id)
    # タスクを取得する
    # 【find を使う理由】
    #   find は対象が存在しない場合に ActiveRecord::RecordNotFound を発生させる。
    #   ApplicationJob で discard_on ActiveRecord::RecordNotFound を設定しているため、
    #   タスクが削除済みの場合はリトライせずにジョブを終了できる。
    task = Task.find(task_id)

    # ユーザーと設定を取得する
    user         = task.user
    user_setting = user.user_setting

    # ============================================================
    # 通知条件チェック（スキップ判定）
    # ============================================================
    # 以下の条件のいずれかに該当する場合は通知をスキップして早期リターンする。
    # 【なぜ早期リターンするのか】
    #   ガード節（Guard Clause）パターン。
    #   条件が満たされない場合を最初に弾くことで、
    #   以降のコードが「通知すべき状態」であることを保証する。
    #   ネストが深くなるのを防いでコードを読みやすくする効果もある。

    # ① アラームが無効になっていたらスキップ
    #   タスク作成後にユーザーがアラームを OFF にした場合を考慮する。
    unless task.alarm_enabled?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: alarm_enabled=false のためスキップ"
      return
    end

    # ② scheduled_at が未設定ならスキップ
    #   scheduled_at なしでジョブが積まれた場合の安全弁。
    unless task.scheduled_at.present?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: scheduled_at=nil のためスキップ"
      return
    end

    # ③ タスクがすでに完了・アーカイブされていたらスキップ
    #   アラーム前にタスクを完了させた場合は通知不要。
    if task.done? || task.archived?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: status=#{task.status} のためスキップ"
      return
    end

    # ④ 通知設定が無効ならスキップ
    #   user_setting が存在しない、または通知全体が OFF の場合。
    unless user_setting&.notification_enabled?
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: notification_enabled=false のためスキップ"
      return
    end

    # ⑤ daily_notification_count が上限に達していたらスキップ
    #   1日に送りすぎないようにする上限チェック。
    if daily_limit_reached?(user_setting)
      # スキップした事実を notification_logs に記録する
      NotificationLog.record_skip(
        user:              user,
        notification_type: :alarm,
        channel:           determine_channel(user_setting),
        target:            task,
        deep_link_url:     "/tasks/#{task.id}",
        reason:            "daily_notification_count が上限（#{user_setting.daily_notification_limit}）に達しているためスキップ"
      )
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: 日次通知上限に達したためスキップ"
      return
    end

    # ============================================================
    # 通知を送信する
    # ============================================================
    # LINE 通知と メール通知のどちらを使うかを判定して送信する。
    # 優先順位: LINE 通知 > メール通知
    #   LINE が有効な場合は LINE で送り、そうでない場合はメールで送る。
    if user_setting.line_notification_enabled? && user.line_user_id.present?
      send_line_notification(task, user, user_setting)
    elsif user_setting.email_notification_enabled? && user.email.present?
      send_email_notification(task, user, user_setting)
    else
      # どの通知手段も使えない場合はスキップを記録する
      Rails.logger.info "[TaskAlarmJob] task_id=#{task_id}: 有効な通知チャネルがないためスキップ"
    end
  end

  private

  # ============================================================
  # determine_channel
  # ============================================================
  # 【役割】
  #   ユーザー設定から送信チャネルを判定して返す。
  #   NotificationLog の record_skip で channel を記録するために使う。
  def determine_channel(user_setting)
    if user_setting.line_notification_enabled?
      :line
    else
      :email
    end
  end

  # ============================================================
  # daily_limit_reached?
  # ============================================================
  # 【役割】
  #   今日の通知送信数が上限に達しているかを判定する。
  #
  # 【daily_notification_count と daily_notification_limit の比較】
  #   daily_notification_count : 今日すでに送った通知の数（GoodJob が日次リセット）
  #   daily_notification_limit : 1日に送ってよい最大数（ユーザーが設定）
  def daily_limit_reached?(user_setting)
    user_setting.daily_notification_count >= user_setting.daily_notification_limit
  end

  # ============================================================
  # increment_notification_count!（C-5 修正: atomic 更新に変更）
  # ============================================================
  #
  # 【修正前の問題（レースコンディション）】
  #   user_setting.daily_notification_count + 1 という書き方は
  #   以下の手順で動作する:
  #     1. Ruby が DB から count の値を読み込む（例: 3）
  #     2. Ruby が 3 + 1 = 4 を計算する
  #     3. DB に 4 を書き込む
  #
  #   もし複数のジョブが同時に実行された場合:
  #     ジョブA: 読み込み=3 → 計算=4 → 書き込み=4
  #     ジョブB: 読み込み=3 → 計算=4 → 書き込み=4（本来は5になるべき）
  #   → 通知カウントが正しく加算されない（数が少なくなる）
  #
  # 【修正後（atomic 更新）】
  #   update_all("daily_notification_count = daily_notification_count + 1")
  #   この書き方では SQL が直接 DB 上で計算する:
  #     UPDATE user_settings SET daily_notification_count = daily_notification_count + 1
  #   DB が計算するためロックなしでも正確にインクリメントできる（原子的操作）。
  #
  # 【update_columns ではなく update_all を使う理由】
  #   update_columns(count: count + 1) は Ruby 側で計算するため競合の余地がある。
  #   update_all("count = count + 1") は DB 側で計算するため競合しない。
  def increment_notification_count!(user_setting)
    UserSetting
      .where(id: user_setting.id)
      .update_all(
        # SQL の式として DB 側で計算させることで競合を防ぐ
        "daily_notification_count = daily_notification_count + 1,
         last_notification_sent_at = '#{Time.current.utc.iso8601}'"
      )

    Rails.logger.info "[TaskAlarmJob] daily_notification_count を +1 しました: user_setting_id=#{user_setting.id}"
  end

  # ============================================================
  # send_line_notification
  # ============================================================
  # 【役割】
  #   LINE Messaging API を使ってアラーム通知を送信する。
  #   成功・失敗を notification_logs に記録し、
  #   成功時は daily_notification_count を増やす。
  #
  # 【LINE API は G-1 で本格実装予定】
  #   C-5 では LINE 通知の骨格（ログ記録・カウント管理）を実装する。
  #   実際の API 呼び出しは G-1（LINE Messaging API 通知基盤）で実装する。
  #   現時点では LINE が設定されている場合でも自動的にメール通知にフォールバックする。
  def send_line_notification(task, user, user_setting)
    # deep_link_url: タップ時に遷移させるパス
    # "/tasks/#{task.id}" でタスク一覧ページへ遷移させる
    deep_link_url = "/tasks/#{task.id}"

    # 【G-1 実装後にここの実際の API 呼び出しコードを追加する】
    # G-1 完了前は LINE 通知が有効でもメール通知にフォールバックする。
    # これによって C-5 のメール通知が先に動作確認できる。
    Rails.logger.info "[TaskAlarmJob] LINE通知はG-1実装後に有効化されます。メール通知にフォールバックします。"
    send_email_notification(task, user, user_setting)
  end

  # ============================================================
  # send_email_notification
  # ============================================================
  # 【役割】
  #   Resend（TaskMailer）を使ってアラーム通知メールを送信する。
  #   成功・失敗を notification_logs に記録し、
  #   成功時は daily_notification_count を増やす。
  def send_email_notification(task, user, user_setting)
    deep_link_url = "/tasks/#{task.id}"

    # TaskMailer でメールを送信する
    # 【deliver_now を使う理由】
    #   このメソッドはすでに GoodJob のバックグラウンドジョブ内で実行されている。
    #   deliver_later にすると「ジョブの中でさらにジョブを積む」二重非同期になる。
    #   ジョブ内では deliver_now（即時送信）が正しい選択。
    TaskMailer.alarm_notification(task).deliver_now

    # 送信成功を notification_logs に記録する
    NotificationLog.record_success(
      user:              user,
      notification_type: :alarm,
      channel:           :email,
      target:            task,
      deep_link_url:     deep_link_url
    )

    # 日次通知カウントを増やす
    increment_notification_count!(user_setting)

    Rails.logger.info "[TaskAlarmJob] メール通知送信成功: task_id=#{task.id}, user_id=#{user.id}"

  rescue => e
    # 送信失敗を notification_logs に記録する
    # 【rescue で拾う理由】
    #   Resend API がダウンしているなどのエラーが発生した場合も
    #   必ず notification_logs に記録を残すことで、
    #   「通知しようとしたが失敗した」ことを追跡できるようにする。
    NotificationLog.record_failure(
      user:              user,
      notification_type: :alarm,
      channel:           :email,
      target:            task,
      deep_link_url:     deep_link_url,
      error_message:     e.message
    )

    Rails.logger.error "[TaskAlarmJob] メール通知送信失敗: task_id=#{task.id}, error=#{e.message}"

    # rescue した後に再度例外を raise することで
    # ApplicationJob の retry_on が機能してリトライされる。
    # raise しないとエラーが握りつぶされてリトライが起きない。
    raise
  end
end