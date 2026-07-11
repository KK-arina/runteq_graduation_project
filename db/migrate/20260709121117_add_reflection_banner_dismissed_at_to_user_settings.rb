# db/migrate/XXXXXXXXXXXXXX_add_reflection_banner_dismissed_at_to_user_settings.rb
#
# ==============================================================================
# H-9（追加）: 振り返り完了バナーの「閉じた日時」を保存する列を追加する
# ==============================================================================
# 【なぜこの列が必要か】
#   振り返り完了バナー（_reflection_completion_banner）は、これまで
#   dashboards_controller が @reflection_ai_analysis の有無だけで無条件に復元描画しており、
#   ✖ で閉じてもリロードすると必ず復活していた。
#   PMVV完了バナーに追加した pmvv_banner_dismissed_at と同じ設計で、
#   振り返り側にも「閉じた記憶」を持たせ、✖ を押すまで残す挙動に統一する。
#
# 【判定ロジック（dashboards_controller で使用）】
#   最新の振り返りAI分析の created_at が reflection_banner_dismissed_at より新しければ
#   「未確認」→ バナーを表示。✖ を押すと現在時刻が保存され、リロードしても出なくなる。
#   再分析すると新しい分析の created_at が上回るため再表示される（PMVVと同じ）。
# ==============================================================================
class AddReflectionBannerDismissedAtToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :reflection_banner_dismissed_at, :datetime, null: true,
               comment: "ダッシュボードの振り返り完了バナーを✖で閉じた日時。最新の振り返りAI分析のcreated_atがこれより新しければバナーを表示する。"
  end
end