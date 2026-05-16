# app/services/notification_service.rb
#
# ==============================================================================
# NotificationService - 通知送信の共通サービスクラス
# ==============================================================================
#
# 【このクラスの役割】
#   LINE通知・メール通知を送信するための共通インターフェースを提供する。
#   deep_link_url を通知メッセージに埋め込む処理をここに集約する。
#
# 【なぜサービスクラスにするのか】
#   コントローラーやジョブに通知ロジックを直接書くと、
#   同じコードが複数箇所に散らばって保守が困難になる（DRY 原則違反）。
#   サービスクラスに集約することで:
#     - 通知ロジックの変更箇所が1ヶ所になる
#     - テストが書きやすくなる
#     - ジョブ・コントローラーどちらからでも同じ方法で呼べる
#
# 【G-1 との関係】
#   G-1（LINE Messaging API 通知基盤）が実装されたとき、
#   このクラスの send_line_notification メソッドに実際のAPI呼び出しコードを追加する。
#   現時点では LINE が未実装のため、メール通知にフォールバックする設計にしている。
#
# 【使い方】
#   NotificationService.new(user: user).send_alarm(task: task)
#   → LINE or メールでアラーム通知を送り、notification_logs に記録する
# ==============================================================================
class NotificationService
  # ============================================================
  # 初期化
  # ============================================================
  #
  # 【引数】
  #   user : 通知を受け取るユーザー（Userインスタンス）
  def initialize(user:)
    @user = user
  end

  # ============================================================
  # send_alarm（タスクアラーム通知）
  # ============================================================
  #
  # 【役割】
  #   タスクのアラーム時刻になったときに呼ばれる。
  #   LINE または メールで通知を送り、notification_logs に記録する。
  #
  # 【引数】
  #   task : 通知対象の Task インスタンス（必ず Task クラスであること）
  #
  # 【deep_link_url の意味】
  #   "/tasks/#{task.id}" というパスを通知メッセージに埋め込む。
  #   LINE通知のURLをタップすると、ログイン後にタスクページへ遷移する。
  #   E-4 で実装した redirect_to パラメータと組み合わせることで、
  #   未ログイン時は /login?redirect_to=/tasks/123 にリダイレクトされ、
  #   ログイン後に /tasks/123 へ自動遷移する。
  def send_alarm(task:)
    # 【型保証】task は必ず Task インスタンスでなければならない
    #   なぜ ArgumentError を使うのか:
    #     ArgumentError は「引数が不正」を示す Ruby の標準例外クラス。
    #     「呼び出し側のコードが間違っている」ことを明確に伝える。
    #     RuntimeError より意味が明確で、デバッグしやすい。
    #   なぜ型チェックが必要か:
    #     TaskMailer.alarm_notification は Task インスタンスを期待する。
    #     誤って WeeklyReflection などが渡されると曖昧なエラーで詰まるため、
    #     入り口で明確に弾く（フェイルファスト原則）。
    raise ArgumentError, "task は Task インスタンスである必要があります（受け取った型: #{task.class}）" unless task.is_a?(Task)

    # deep_link_url: 通知タップ時の遷移先パス
    # "/tasks/#{task.id}" でタスクページへ遷移させる
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
      # どちらも無効な場合はログのみ記録する
      Rails.logger.info "[NotificationService] 有効な通知チャネルがありません: user_id=#{user.id}"
    end
  end

  # ============================================================
  # send_weekly_report（週次レポート通知）
  # ============================================================
  #
  # 【deep_link_url の意味】
  #   "/weekly_reflections/new" へ誘導することで、
  #   通知タップ → ログイン → 振り返り入力ページへの流れを実現する。
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

  # ============================================================
  # send_ai_result（AI分析完了通知）
  # ============================================================
  #
  # 【deep_link_url の意味】
  #   "/user_purposes/#{user_purpose.id}" で PMVV 詳細ページへ誘導する。
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

  # private の下に書いたものはすべて private になる。
  # user メソッドを外部から呼ばれないようにするため private ブロックの中に定義する。
  attr_reader :user

  # ============================================================
  # app_host（DRY化: 共通のベースURL生成メソッド）
  # ============================================================
  #
  # 【なぜメソッドに切り出すのか（DRY原則）】
  #   build_alarm_message / build_weekly_report_message / build_ai_result_message の
  #   3ヶ所に同じ app_host の生成ロジックを書くと、
  #   将来URLを変更したときに3ヶ所を直さなければならない（DRY 原則違反）。
  #   メソッドに切り出すことで変更が1ヶ所で済む。
  #
  # 【||= によるメモ化】
  #   同一インスタンス内で複数回呼ばれても ENV アクセスは1回だけになる。
  #   @app_host に一度代入したら次回以降はキャッシュした値を返す。
  #
  # 【ENV.fetch の安全性】
  #   ENV.fetch('APP_HOST', 'habitflow-web.onrender.com'):
  #     環境変数 APP_HOST が設定されていれば使う。
  #     設定されていなければ第2引数のデフォルト値を使う。
  def app_host
    @app_host ||= if Rails.env.production?
                    "https://#{ENV.fetch('APP_HOST', 'habitflow-web.onrender.com')}"
                  else
                    "http://localhost:3000"
                  end
  end

  # ============================================================
  # use_line?（LINE通知を使うか判定）
  # ============================================================
  #
  # 【条件】
  #   1. user_setting が存在する
  #   2. line_notification_enabled? が true（LINE通知が ON）
  #   3. user.line_user_id が存在する（LINE連携済み）
  def use_line?
    user.user_setting&.line_notification_enabled? && user.line_user_id.present?
  end

  # ============================================================
  # use_email?（メール通知を使うか判定）
  # ============================================================
  def use_email?
    user.user_setting&.email_notification_enabled? && user.email.present?
  end

  # ============================================================
  # send_line_notification（LINE通知の送信）
  # ============================================================
  #
  # 【G-1 実装後にここに LINE API 呼び出しコードを追加する】
  #   現時点では LINE が未実装のため、メール通知にフォールバックする。
  #
  # 【fallback 時のログ（レビュー指摘対応）】
  #   「LINE設定ON → 実際はメール送信」という状態を明確にログに残す。
  #   original_channel=line / actual_channel=email を記録することで、
  #   運用時に「LINE→メール fallback が発生している」と把握できる。
  def send_line_notification(target:, message:, deep_link_url:, notification_type:)
    Rails.logger.info(
      "[NotificationService] LINE通知はG-1実装後に有効化されます。" \
      "メール通知にフォールバックします。" \
      " original_channel=line actual_channel=email" \
      " user_id=#{user.id} notification_type=#{notification_type}"
    )

    send_email_notification(
      target:            target,
      deep_link_url:     deep_link_url,
      notification_type: notification_type
    )
  end

  # ============================================================
  # send_email_notification（メール通知の送信）
  # ============================================================
  #
  # 【deliver_now を使う理由】
  #   このサービスクラスは GoodJob のジョブ内から呼ばれることを想定している。
  #   ジョブ内で deliver_later にすると「ジョブの中でさらにジョブを積む」二重非同期になる。
  #   ジョブ内では deliver_now（即時送信）が正しい選択。
  def send_email_notification(target:, deep_link_url:, notification_type:)
    case notification_type
    when :alarm
      # タスクアラーム通知: TaskMailer を使う（C-5 で実装済み）
      TaskMailer.alarm_notification(target).deliver_now

      # 送信成功を notification_logs に記録する
      # deep_link_url を記録することで、どのページへ誘導しようとしたかを追跡できる
      NotificationLog.record_success(
        user:              user,
        notification_type: notification_type,
        channel:           :email,
        target:            target,
        deep_link_url:     deep_link_url
      )

      Rails.logger.info "[NotificationService] アラームメール送信成功: target_id=#{target.id}, user_id=#{user.id}"

    when :weekly_report
      # 週次レポート通知: G-2 で実装予定
      Rails.logger.info "[NotificationService] 週次レポートメールはG-2実装後に有効化されます。"

    when :ai_result
      # AI分析完了通知: 将来実装予定
      Rails.logger.info "[NotificationService] AI分析完了通知は将来実装予定です。"

    else
      Rails.logger.warn "[NotificationService] 未対応の通知タイプ: #{notification_type}"
    end

  rescue StandardError => e
    # 【rescue StandardError を使う理由（レビュー指摘対応）】
    #   明示的に StandardError と書くことで
    #   「意図的に広範囲な例外を捕まえている」ことがコードを読んだ人に伝わる。
    #   本来は Resend::Error など特定の例外クラスを指定するのが理想だが、
    #   現時点ではメイラーの実装詳細に依存しないよう StandardError を使う。
    NotificationLog.record_failure(
      user:              user,
      notification_type: notification_type,
      channel:           :email,
      target:            target,
      deep_link_url:     deep_link_url,
      error_message:     e.message
    )

    Rails.logger.error "[NotificationService] メール送信失敗: error=#{e.message}"

    # raise で例外を再スローする。
    # これにより呼び出し元（GoodJob ジョブ）の retry_on が機能してリトライされる。
    raise
  end

  # ============================================================
  # メッセージビルダー（LINE通知用テキスト生成）
  # ============================================================
  #
  # 【ERB::Util.url_encode を使う理由（CGI.escape からの変更）】
  #   CGI.escape はスペースを「+」に変換するが、URLパラメータでは「%20」が正しい。
  #   ERB::Util.url_encode は Rails 標準のURLエンコードメソッドで:
  #     - スペースを「%20」に変換する（URLとして正しい）
  #     - UTF-8 を安全に扱える
  #     - Rails のビュー・コントローラー全体で統一できる

  # build_alarm_message: タスクアラーム通知のメッセージを生成する
  def build_alarm_message(task, deep_link_url)
    # app_host は共通メソッド（DRY化済み）を呼ぶ
    # ERB::Util.url_encode: Rails標準のURLエンコード（スペース → %20）
    <<~MSG
      【HabitFlow】タスクのアラームです！

      📋 #{task.title}

      タスクを確認する:
      #{app_host}/login?redirect_to=#{ERB::Util.url_encode(deep_link_url)}
    MSG
  end

  # build_weekly_report_message: 週次レポートのメッセージを生成する
  def build_weekly_report_message(deep_link_url)
    <<~MSG
      【HabitFlow】今週の振り返りをしましょう！

      先週の達成状況を確認して、今週の計画を立てましょう。

      振り返りを始める:
      #{app_host}/login?redirect_to=#{ERB::Util.url_encode(deep_link_url)}
    MSG
  end

  # build_ai_result_message: AI分析完了のメッセージを生成する
  def build_ai_result_message(deep_link_url)
    <<~MSG
      【HabitFlow】PMVV目標のAI分析が完了しました！

      🤖 AIが目標を分析しました。結果を確認してください。

      分析結果を見る:
      #{app_host}/login?redirect_to=#{ERB::Util.url_encode(deep_link_url)}
    MSG
  end
end