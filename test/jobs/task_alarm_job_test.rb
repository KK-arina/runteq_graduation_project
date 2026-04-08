# test/jobs/task_alarm_job_test.rb
#
# ==============================================================================
# TaskAlarmJob のテスト
# ==============================================================================
#
# 【テストの方針】
#   実際にメールを送信するのではなく、
#   ActionMailer::Base.deliveries（テスト時のメール格納配列）を確認する。
#   開発/テスト環境では delivery_method が :test になっており、
#   メールが deliveries 配列に追加されるだけで実際には送信されない。
# ==============================================================================
require "test_helper"

class TaskAlarmJobTest < ActiveJob::TestCase
  # ============================================================
  # セットアップ
  # ============================================================
  def setup
    # テスト用のユーザーとタスクを作成する
    # fixtures を使わずに create! で作ることで各テストが独立した状態になる
    @user = User.create!(
      name:     "テストユーザー",
      email:    "alarm_test@example.com",
      password: "password123"
    )

    # ユーザー設定を作成する（通知有効・メール通知 ON）
    @user_setting = UserSetting.create!(
      user:                       @user,
      notification_enabled:       true,
      line_notification_enabled:  false,
      email_notification_enabled: true,
      daily_notification_limit:   5,
      daily_notification_count:   0
    )

    # テスト用のタスクを作成する（アラーム有効・1時間後に予定）
    @task = Task.create!(
      user:                 @user,
      title:                "テストタスク",
      priority:             :must,
      alarm_enabled:        true,
      scheduled_at:         1.hour.from_now,
      alarm_minutes_before: 30
    )

    # テスト前にメール配信リストをクリアする
    ActionMailer::Base.deliveries.clear
  end

  # ============================================================
  # テスト 1: 正常系 - メール通知が送信される
  # ============================================================
  def test_メール通知が正常に送信される
    # ジョブを同期実行する（perform_now で即時実行）
    TaskAlarmJob.perform_now(@task.id)

    # メールが 1 通送信されていることを確認する
    assert_equal 1, ActionMailer::Base.deliveries.size,
                 "アラームメールが 1 通送信されるべきです"

    mail = ActionMailer::Base.deliveries.first

    # 宛先がユーザーのメールアドレスであることを確認する
    assert_includes mail.to, @user.email,
                    "宛先が #{@user.email} であるべきです"

    # 件名にタスク名が含まれることを確認する
    assert_includes mail.subject, @task.title,
                    "件名にタスク名が含まれるべきです"
  end

  # ============================================================
  # テスト 2: notification_logs に記録が残る
  # ============================================================
  def test_通知成功時にnotification_logsに記録される
    assert_difference "NotificationLog.count", 1 do
      TaskAlarmJob.perform_now(@task.id)
    end

    log = NotificationLog.last

    assert_equal @user.id,  log.user_id,           "user_id が一致するべきです"
    assert_equal "alarm",   log.notification_type,  "notification_type が alarm であるべきです"
    assert_equal "email",   log.channel,            "channel が email であるべきです"
    assert_equal "success", log.status,             "status が success であるべきです"
    assert_equal "Task",    log.target_type,        "target_type が Task であるべきです"
    assert_equal @task.id,  log.target_id,          "target_id が一致するべきです"
    assert_includes log.deep_link_url, @task.id.to_s, "deep_link_url にタスクIDが含まれるべきです"
  end

  # ============================================================
  # テスト 3: alarm_enabled=false のときはスキップされる
  # ============================================================
  def test_alarm_disabledのときはメールを送らない
    @task.update!(alarm_enabled: false)

    TaskAlarmJob.perform_now(@task.id)

    assert_equal 0, ActionMailer::Base.deliveries.size,
                 "alarm_enabled=false のときはメールを送るべきではありません"
  end

  # ============================================================
  # テスト 4: タスクが完了済みのときはスキップされる
  # ============================================================
  def test_完了済みタスクはスキップされる
    @task.update!(status: :done, completed_at: Time.current)

    TaskAlarmJob.perform_now(@task.id)

    assert_equal 0, ActionMailer::Base.deliveries.size,
                 "完了済みタスクのアラームは送信されるべきではありません"
  end

  # ============================================================
  # テスト 5: 日次通知上限に達したときはスキップされる
  # ============================================================
  def test_日次通知上限超過時はスキップされnotification_logsに記録される
    # 上限まで達した状態にする
    @user_setting.update!(
      daily_notification_count: 5,
      daily_notification_limit: 5
    )

    assert_difference "NotificationLog.count", 1 do
      TaskAlarmJob.perform_now(@task.id)
    end

    assert_equal 0, ActionMailer::Base.deliveries.size,
                 "上限超過時はメールを送るべきではありません"

    log = NotificationLog.last
    assert_equal "skipped", log.status, "status が skipped であるべきです"
  end

  # ============================================================
  # テスト 6: コントローラー経由でジョブがエンキューされる（create）
  # ============================================================
  #
  # 【なぜモデル直接作成ではなくコントローラーを通してテストするのか】
  #   enqueue_alarm_job_if_needed は TasksController の private メソッドのため
  #   コントローラーテストを通じてのみ確認できる。
  #   このテストはジョブ単体テストとして「ジョブ自体が正しく動くか」を確認するもの。
  #   コントローラーでのエンキュー確認は tasks_controller_test.rb で行う。
  def test_ジョブが正常に終了する（正常系全体の流れ）
    # perform_now でジョブを即時実行して、例外なく完了することを確認
    assert_nothing_raised do
      TaskAlarmJob.perform_now(@task.id)
    end
  end

  # ============================================================
  # テスト 7: notification_enabled=false のときはスキップされる
  # ============================================================
  def test_通知全体無効のときはスキップされる
    @user_setting.update!(notification_enabled: false)

    TaskAlarmJob.perform_now(@task.id)

    assert_equal 0, ActionMailer::Base.deliveries.size,
                 "notification_enabled=false のときはメールを送るべきではありません"
  end

  # ============================================================
  # テスト 8: 削除済みタスクの場合はジョブが静かに破棄される
  # ============================================================
  #
  # 【なぜ assert_raises ではなく assert_nothing_raised なのか】
  #   ApplicationJob に discard_on ActiveRecord::RecordNotFound が設定されている。
  #   discard_on は「この例外が発生したらリトライせずにジョブを破棄する」設定で、
  #   例外をキャッチして外部には伝播させない。
  #   そのため perform_now を呼んでも例外は出ない（静かに終了する）。
  #   「例外が外に出ないこと」= 正しく破棄されたこと、と確認するのが正しいテスト。
  def test_存在しないtask_idを渡すとジョブが静かに破棄される
    # 存在しない ID（999999）を渡しても例外が外に出ないことを確認する
    assert_nothing_raised do
      TaskAlarmJob.perform_now(999_999)
    end

    # メールも送信されていないことを確認する（副作用がないことの確認）
    assert_equal 0, ActionMailer::Base.deliveries.size,
                 "存在しないタスクに対してメールは送信されるべきではありません"
  end
end