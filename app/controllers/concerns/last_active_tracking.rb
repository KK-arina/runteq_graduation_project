# app/controllers/concerns/last_active_tracking.rb
#
# ==============================================================================
# LastActiveTracking: ログイン中のユーザーが画面を開いたら、最終利用日時を記録する
# ==============================================================================
#
# 【このファイルの役割】
#   ApplicationController に include して、すべての画面で track_last_active を実行する。
#   実際の記録（1日1回だけ UPDATE する処理）は User#touch_last_active!
#   （app/models/concerns/last_activity.rb）が行う。
#
# 【「利用」として数えないもの】
#   ・未ログインのアクセス（LP・ログイン画面など）
#   ・Render を起こすための /up
#       → Rails::HealthController は ApplicationController を継承していないため、ここを通らない
#   ・GoodJob の定期ジョブ
#       → コントローラーを通らないため、ここを通らない
#   ・管理者自身のアクセス
#       → 管理画面の集計に自分の利用が混ざらないよう、admin? なら記録しない
#
# 【追加の DB アクセスがほとんどない理由】
#   current_user はもともと、利用規約の確認（redirect_to_terms_agreement_if_needed）で
#   リクエストごとに1回読み込んでいる（メモ化されているので2回目は DB を見ない）。
#   UPDATE は1人1日1回だけ。admin? は環境変数を読むだけで DB を使わない。
# ==============================================================================
module LastActiveTracking
  extend ActiveSupport::Concern

  # included ブロック: include した側のクラス（ApplicationController）で実行される
  #   before_action は書いた順に実行されるため、ApplicationController では
  #   利用規約の確認（redirect_to_terms_agreement_if_needed）の直後で include している。
  #   規約に未同意で同意ページへ移動させられた場合は、そこで処理が止まるので記録されない。
  included do
    before_action :track_last_active
  end

  private

  # track_last_active
  #
  # 【rescue する理由】
  #   最終利用日時の記録は「おまけ」の処理なので、DB の一時的なエラーなどで失敗しても、
  #   利用者が開こうとした画面は表示できるようにする（エラー画面にしない）。
  #   ログには user_id だけを残す（メールアドレスなどの個人情報は出さない）。
  def track_last_active
    return unless logged_in?
    return if current_user.admin?

    current_user.touch_last_active!
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn "[LastActiveTracking] 最終利用日時を記録できませんでした user_id=#{current_user&.id} error=#{e.class}"
  end
end
