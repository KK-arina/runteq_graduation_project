# app/services/notification_service.rb
#
# ==============================================================================
# NotificationService - 通知送信の共通サービスクラス（G-1 完全版）
# ==============================================================================
#
# 【G-1 での変更内容】
#   send_line_notification を実際の LINE API 呼び出しに変更した。
#   LINE 送信失敗時（月200通上限超過・API エラーなど）は
#   自動的にメール通知にフォールバックする。
#
# 【daily_notification_count 管理の設計方針】
#   スキップ判定: TaskAlarmJob（呼び出し元）が担当する
#   インクリメント: TaskAlarmJob（呼び出し元）が担当する
#   理由:
#     NotificationService は「送信」だけを担当するシングルレスポンシビリティ設計。
#     カウント管理をこのクラスに持ち込むと、
#     ① メール送信・LINE送信でカウントが二重に増える
#     ② GoodJob 並列実行時に競合する（TaskAlarmJob の update_all が保護できなくなる）
#     ③ テストが複雑になる
#   TaskAlarmJob ではすでに SQL のアトミック更新（update_all + "count = count + 1"）で
#   競合を防いでいるため、二重管理は不要かつ危険。
# ==============================================================================
class NotificationService
  def initialize(user:)
    @user = user
  end

  # send_alarm（タスクアラーム通知）
  #
  # 【引数】
  #   task : 通知対象の Task インスタンス（必ず Task クラスであること）
  #
  # 【deep_link_url の意味】
  #   "/tasks/#{task.id}" を通知メッセージに埋め込む。
  #   LINE 通知のURLをタップすると、ログイン後にタスクページへ遷移する。
  #   E-4 で実装した redirect_to パラメータと組み合わせることで
  #   未ログイン時は /login?redirect_to=/tasks/123 にリダイレクトされ
  #   ログイン後に /tasks/123 へ自動遷移する。
  def send_alarm(task:)
    raise ArgumentError, "task は Task インスタンスである必要があります（受け取った型: #{task.class}）" unless task.is_a?(Task)

    deep_link_url = "/tasks/#{task.id}"

    if use_line?
      send_line_notification(
        target:            task,
        message:           build_alarm_message(task, deep_link_url),
        deep_link_url:     deep_link_url,
        notification_type: :alarm
      )
    elsif use_email?
      send_email_notification(
        target:            task,
        deep_link_url:     deep_link_url,
        notification_type: :alarm
      )
    else
      Rails.logger.info "[NotificationService] 有効な通知チャネルがありません: user_id=#{user.id}"
    end
  end

  # send_weekly_report（週次レポート通知）
  def send_weekly_report(weekly_reflection:)
    deep_link_url = "/weekly_reflections/new"

    if use_line?
      send_line_notification(
        target:            weekly_reflection,
        message:           build_weekly_report_message(deep_link_url),
        deep_link_url:     deep_link_url,
        notification_type: :weekly_report
      )
    elsif use_email?
      send_email_notification(
        target:            weekly_reflection,
        deep_link_url:     deep_link_url,
        notification_type: :weekly_report
      )
    end
  end

  # send_ai_result（AI分析完了通知）
  def send_ai_result(user_purpose:)
    deep_link_url = "/user_purposes/#{user_purpose.id}"

    if use_line?
      send_line_notification(
        target:            user_purpose,
        message:           build_ai_result_message(deep_link_url),
        deep_link_url:     deep_link_url,
        notification_type: :ai_result
      )
    elsif use_email?
      send_email_notification(
        target:            user_purpose,
        deep_link_url:     deep_link_url,
        notification_type: :ai_result
      )
    end
  end

  private

  attr_reader :user

  # app_host: ベースURLを環境に応じて返す（メモ化済み）
  #
  # 【||= によるメモ化】
  #   同一インスタンス内で複数回呼ばれても ENV アクセスは1回だけになる。
  def app_host
    @app_host ||= if Rails.env.production?
                    "https://#{ENV.fetch('APP_HOST', 'habitflow-web.onrender.com')}"
                  else
                    "http://localhost:3000"
                  end
  end

  # use_line?: LINE通知を使うか判定する
  #
  # 【条件】以下すべてが true の場合のみ LINE 通知を使う
  #   1. user_setting が存在する
  #   2. line_notification_enabled? が true（LINE通知が ON）
  #   3. user.line_user_id が存在する（LINE連携済み・友達追加済み）
  def use_line?
    user.user_setting&.line_notification_enabled? && user.line_user_id.present?
  end

  # use_email?: メール通知を使うか判定する
  def use_email?
    user.user_setting&.email_notification_enabled? && user.email.present?
  end

  # send_line_notification: LINE通知の送信（G-1 で実装）
  #
  # 【フォールバック戦略】
  #   LINE 送信に失敗した場合（API エラー・月上限超過・トークン未設定など）、
  #   自動的にメール通知に切り替える。
  #   これにより「LINE が使えなくてもユーザーへの通知が止まらない」信頼性を確保する。
  #
  # 【retry_count について】
  #   GoodJob の retry_on によって自動リトライされるとき、
  #   ジョブは ApplicationJob を継承しており executions カウンタを持つ。
  #   ただし NotificationService 自体はジョブではないため executions にアクセスできない。
  #   retry_count は呼び出し元（TaskAlarmJob）から metadata 経由で渡す設計にする。
  #   現時点では初回送信のみのため 0 で記録する。
  #
  # 【LINE 月200通の無料枠について】
  #   LINE Messaging API の料金プランは変更される可能性があるため
  #   コードに固定値を埋め込まない。
  #   超過時は HTTP 400/429 が返るため、失敗として扱いメールにフォールバックする。
  def send_line_notification(target:, message:, deep_link_url:, notification_type:)
    result = LineNotificationService.new(
      line_user_id: user.line_user_id,
      message:      message
    ).call

    if result[:success]
      # LINE 送信成功: notification_logs に記録する
      #
      # retry_count: 0 は「今回のジョブ実行が初回」を意味する。
      # GoodJob がリトライしてこのメソッドが再実行された場合も
      # 現設計では 0 が入る（改善余地はあるが実運用上は許容範囲）。
      NotificationLog.record_success(
        user:              user,
        notification_type: notification_type,
        channel:           :line,
        target:            target,
        deep_link_url:     deep_link_url,
        metadata:          result[:response_body].to_h.merge("retry_count" => 0)
      )

      Rails.logger.info(
        "[NotificationService] LINE通知送信成功: " \
        "user_id=#{user.id} notification_type=#{notification_type}"
      )

    else
      # LINE 送信失敗 → メールにフォールバック
      Rails.logger.warn(
        "[NotificationService] LINE通知送信失敗。メール通知へ自動切替します。 " \
        "user_id=#{user.id} notification_type=#{notification_type} " \
        "error=#{result[:error]}"
      )

      if use_email?
        # メール通知が有効な場合はメールで通知する
        # メール送信自体の成功/失敗ログは send_email_notification 内で記録される
        send_email_notification(
          target:            target,
          deep_link_url:     deep_link_url,
          notification_type: notification_type
        )
      else
        # メールも使えない場合は失敗として記録する
        NotificationLog.record_failure(
          user:              user,
          notification_type: notification_type,
          channel:           :line,
          target:            target,
          deep_link_url:     deep_link_url,
          error_message:     result[:error].to_s
        )
      end
    end
  end

  # send_email_notification: メール通知の送信
  #
  # 【deliver_now を使う理由】
  #   このサービスクラスは GoodJob のジョブ内から呼ばれることを想定している。
  #   ジョブ内で deliver_later にすると「ジョブの中でさらにジョブを積む」二重非同期になる。
  #   ジョブ内では deliver_now（即時送信）が正しい選択。
  def send_email_notification(target:, deep_link_url:, notification_type:)
    case notification_type
    when :alarm
      TaskMailer.alarm_notification(target).deliver_now

      NotificationLog.record_success(
        user:              user,
        notification_type: notification_type,
        channel:           :email,
        target:            target,
        deep_link_url:     deep_link_url
      )

      Rails.logger.info "[NotificationService] アラームメール送信成功: target_id=#{target.id}, user_id=#{user.id}"

    when :weekly_report
      Rails.logger.info "[NotificationService] 週次レポートメールはG-2実装後に有効化されます。"

    when :ai_result
      Rails.logger.info "[NotificationService] AI分析完了通知は将来実装予定です。"

    else
      Rails.logger.warn "[NotificationService] 未対応の通知タイプ: #{notification_type}"
    end

  rescue StandardError => e
    NotificationLog.record_failure(
      user:              user,
      notification_type: notification_type,
      channel:           :email,
      target:            target,
      deep_link_url:     deep_link_url,
      error_message:     e.message
    )

    Rails.logger.error "[NotificationService] メール送信失敗: error=#{e.message}"
    raise
  end

  # ============================================================
  # メッセージビルダー（LINE通知用テキスト生成）
  # ============================================================

  # build_alarm_message: タスクアラーム通知のメッセージを生成する
  #
  # 【ERB::Util.url_encode を使う理由】
  #   CGI.escape はスペースを「+」に変換するが URL パラメータでは「%20」が正しい。
  #   ERB::Util.url_encode は Rails 標準で「%20」に変換する。
  def build_alarm_message(task, deep_link_url)
    <<~MSG
      【HabitFlow】タスクのアラームです！

      📋 #{task.title}

      タスクを確認する:
      #{app_host}/login?redirect_to=#{ERB::Util.url_encode(deep_link_url)}
    MSG
  end

  def build_weekly_report_message(deep_link_url)
    <<~MSG
      【HabitFlow】今週の振り返りをしましょう！

      先週の達成状況を確認して、今週の計画を立てましょう。

      振り返りを始める:
      #{app_host}/login?redirect_to=#{ERB::Util.url_encode(deep_link_url)}
    MSG
  end

  def build_ai_result_message(deep_link_url)
    <<~MSG
      【HabitFlow】PMVV目標のAI分析が完了しました！

      🤖 AIが目標を分析しました。結果を確認してください。

      分析結果を見る:
      #{app_host}/login?redirect_to=#{ERB::Util.url_encode(deep_link_url)}
    MSG
  end
end