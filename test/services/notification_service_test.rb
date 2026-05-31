# test/services/notification_service_test.rb
#
# ==============================================================================
# NotificationService のテスト（G-1 更新）
# ==============================================================================
#
# 【主な修正点（レビュー対応）】
#   1. require "ostruct" を追加
#   2. User.create! → fixtures 流用 + update_column で安全に設定
#      （User の複雑なバリデーション・コールバックによる create! 失敗を防ぐ）
#   3. user_setting の nil ガードを追加
#   4. teardown の順序を修正（Task 先・User 後）
#   5. assert_difference の対象を NotificationLog.count に統一
#      （channel/status を条件に入れると環境差分で不安定になるため）
# ==============================================================================
require "test_helper"
require "ostruct"

class NotificationServiceTest < ActiveSupport::TestCase
  setup do
    # ── テスト用ユーザー（LINE連携済み）──
    #
    # 【なぜ User.create! ではなく fixtures を流用するのか】
    #   HabitFlow の User モデルには provider / terms_agreed_at /
    #   password_confirmation などの複雑なバリデーションがある。
    #   create! で全バリデーションを通す実装は壊れやすく保守コストが高い。
    #   fixtures(:one) をベースに line_user_id だけ update_column で設定する方が
    #   確実かつシンプル。
    @user_with_line = users(:one)
    @user_with_line.update_column(:line_user_id, "U1234567890abcdef1234567890abcdef")

    # user_setting の nil ガード
    # 【理由】
    #   after_create コールバックで UserSetting が自動作成されるが、
    #   テスト環境ではコールバックが動作しないケースがある。
    #   確実に存在させるため、なければここで作成する。
    unless @user_with_line.user_setting
      @user_with_line.create_user_setting!(
        notification_enabled:      true,
        line_notification_enabled: true,
        daily_notification_limit:  5,
        daily_notification_count:  0
      )
    end

    @user_with_line.user_setting.update!(
      line_notification_enabled:  true,
      notification_enabled:       true,
      email_notification_enabled: true,
      daily_notification_limit:   5,
      daily_notification_count:   0
    )

    # テスト用タスク
    @task = Task.create!(
      user:          @user_with_line,
      title:         "テストタスク",
      priority:      1,
      task_type:     0,
      status:        0,
      alarm_enabled: true,
      scheduled_at:  1.hour.from_now
    )
  end

  teardown do
    # 【teardown の順序: Task → User の順で削除する】
    #
    # Task は User に belongs_to しているため、
    # User を先に削除しようとすると外部キー制約違反が起きる可能性がある。
    # Task を先に削除することで依存関係の衝突を防ぐ。
    # &. (ぼっち演算子) で nil の場合は何もしない（二重削除エラー防止）。
    @task&.destroy
    # User を元の状態に戻す（line_user_id をクリア）
    @user_with_line&.update_column(:line_user_id, nil)
  end

  # ============================================================
  # テスト1: LINE連携済みユーザーへの通知
  # ============================================================
  test "LINE連携済みユーザーに send_alarm を呼ぶと LINE 通知が送られ記録される" do
    mock_result = { success: true, response_body: { "sentMessages" => [] } }

    LineNotificationService.stub(
      :new,
      ->(**_kwargs) { OpenStruct.new(call: mock_result) }
    ) do
      # 【assert_difference の対象について】
      #   NotificationLog.count で総数を見ることで、
      #   channel/status の条件によるテストの不安定さを避ける。
      assert_difference "NotificationLog.count", 1 do
        NotificationService.new(user: @user_with_line).send_alarm(task: @task)
      end

      # 記録内容の詳細確認
      log = NotificationLog.last
      assert_equal "line",    log.channel
      assert_equal "success", log.status
      assert_equal @task.id,  log.target_id
      assert_equal "Task",    log.target_type
    end
  end

  # ============================================================
  # テスト2: LINE送信失敗 → メールフォールバック
  # ============================================================
  test "LINE送信失敗時にメール通知にフォールバックする" do
    mock_result = { success: false, error: "HTTP 429: Too Many Requests" }

    LineNotificationService.stub(
      :new,
      ->(**_kwargs) { OpenStruct.new(call: mock_result) }
    ) do
      mail_stub = OpenStruct.new(deliver_now: true)
      TaskMailer.stub(:alarm_notification, ->(_task) { mail_stub }) do
        assert_difference "NotificationLog.count", 1 do
          NotificationService.new(user: @user_with_line).send_alarm(task: @task)
        end

        log = NotificationLog.last
        # フォールバック先はメールになること
        assert_equal "email",   log.channel
        assert_equal "success", log.status
      end
    end
  end

  # ============================================================
  # テスト3: LINE未連携ユーザーはメール通知になる
  # ============================================================
  test "LINE未連携ユーザーは send_alarm でメール通知になる" do
    # line_user_id を nil にしてLINE未連携状態にする
    @user_with_line.update_column(:line_user_id, nil)

    mail_stub = OpenStruct.new(deliver_now: true)
    TaskMailer.stub(:alarm_notification, ->(_task) { mail_stub }) do
      assert_difference "NotificationLog.count", 1 do
        NotificationService.new(user: @user_with_line).send_alarm(task: @task)
      end

      log = NotificationLog.last
      assert_equal "email", log.channel
    end
  end
end