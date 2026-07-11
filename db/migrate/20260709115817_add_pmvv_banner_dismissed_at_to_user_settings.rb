# db/migrate/XXXXXXXXXXXXXX_add_pmvv_banner_dismissed_at_to_user_settings.rb
#
# ==============================================================================
# H-9（追加）: PMVV完了バナーの「閉じた日時」を保存する列を追加する
# ==============================================================================
# 【なぜこの列が必要か】
#   ダッシュボードのPMVV完了バナーは、これまで Turbo Stream のライブ配信専用で、
#   ページをリロードすると消える設計だった。
#   「✖ を押すまではリロード後も残す」を実現するには、
#   「ユーザーがこのバナーを✖で閉じた日時」をサーバー側に永続化する必要がある。
#
# 【判定ロジック（dashboards_controller で使用）】
#   最新のPMVV分析の created_at が pmvv_banner_dismissed_at より新しければ「未確認」
#   → バナーを表示。✖ を押すと pmvv_banner_dismissed_at が現在時刻に更新され、
#   リロードしても表示されなくなる。再分析すると新しい分析の created_at が
#   dismissed_at を上回るため、再びバナーが表示される。
#
# 【null: true にする理由】
#   一度も完了バナーを閉じたことがないユーザーは nil（＝未確認扱い）でよいため、
#   デフォルト値は設けず nil 許容にする。既存の last_analytics_viewed_at と同じ設計。
# ==============================================================================
class AddPmvvBannerDismissedAtToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :pmvv_banner_dismissed_at, :datetime, null: true,
               comment: "ダッシュボードのPMVV完了バナーを✖で閉じた日時。最新PMVV分析のcreated_atがこれより新しければバナーを表示する。"
  end
end