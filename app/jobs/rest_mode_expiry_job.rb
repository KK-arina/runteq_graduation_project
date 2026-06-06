# app/jobs/rest_mode_expiry_job.rb
#
# ==============================================================================
# RestModeExpiryJob（G-4 新規作成）
# ==============================================================================
#
# 【このジョブの役割】
#   rest_mode_until が現在時刻を過ぎた user_settings レコードを見つけ、
#   rest_mode_until と rest_mode_reason を NULL にリセットする。
#
# 【なぜバッチ処理にするのか】
#   ユーザーがお休みモードの終了日を過ぎてもアプリを開かない場合でも
#   自動的にリセットされるようにするため。
#   「次回ログイン時にリセット」では、ログインしないユーザーはずっと
#   お休みモードのままになってしまう。
#
# 【cron 設定】
#   good_job.rb の cron に追加して毎日 JST 04:05 に実行する。
#   ストリーク計算ジョブ（streak_daily_calculation）の直後が望ましい。
#   AM4:00 が「1日の境界」なので、境界後すぐに期限切れチェックを行う。
#
# 【パフォーマンスへの配慮】
#   1クエリ（update_all）で一括更新するため、ユーザー数が多くても高速。
#   個別に update すると N 回の SQL になるが、update_all は1回のみ。
# ==============================================================================
class RestModeExpiryJob < ApplicationJob
  # queue_as :default
  # 【理由】
  #   ストリーク計算と同じ :default キューで問題ない。
  #   優先度の高いジョブではないため :default で適切。
  queue_as :default

  def perform
    Rails.logger.info "[RestModeExpiryJob] 開始: #{Time.current}"

    # ── 期限切れのお休みモードをリセットする ────────────────────────────
    #
    # 【条件の説明】
    #   where.not(rest_mode_until: nil): rest_mode_until が NULL でないもの
    #     → お休みモード中のレコードのみを対象にする
    #   where("rest_mode_until < ?", Time.current): 終了日時が現在時刻より前
    #     → 期限切れのレコードのみを対象にする
    #
    # 【update_all の引数】
    #   Hash 形式で { カラム名 => 値 } を指定する。
    #   rest_mode_until: nil → NULL を設定してお休みモードを解除
    #   rest_mode_reason: nil → 理由もクリアする
    #
    # 【updated_at が自動更新されない問題について】
    #   update_all は updated_at を自動更新しない。
    #   お休みモードの解除は「サービス内部の自動処理」であり、
    #   ユーザーが意図的に変更したわけではないため updated_at の更新は不要。
    expired_count = UserSetting
      .where.not(rest_mode_until: nil)
      .where("rest_mode_until < ?", Time.current)
      .update_all(
        rest_mode_until:  nil,
        rest_mode_reason: nil
      )

    Rails.logger.info "[RestModeExpiryJob] #{expired_count} 件のお休みモードを自動解除: #{Time.current}"
  end
end