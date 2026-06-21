# db/migrate/【自動生成された日時】_add_last_analytics_viewed_at_to_user_settings.rb
#
# ==============================================================================
# H-4: user_settings に last_analytics_viewed_at カラムを追加するマイグレーション
# ==============================================================================
#
# 【このカラムの役割】
#   ユーザーが「グラフ・進捗分析ページ（19番 / AnalyticsController#index）」を
#   最後に開いた日時を記録する。
#
#   Bottom Navigation のグラフタブには「AI分析完了（未確認）」を示す
#   青いバッジが表示される（bn_ai_analysis_count メソッドが判定）。
#   このカラムがあることで「グラフページを開いた後に完了した分析だけ」を
#   未確認としてカウントできるようになり、
#   「一度確認したのにバッジが消えない」という不具合を防げる。
#
# 【NULL許容にする理由】
#   一度もグラフページを開いたことがない新規ユーザーは nil になる。
#   nil の場合は bn_ai_analysis_count 側で「7日前を基準にする」という
#   安全なフォールバック処理を行う（後述の application_controller.rb 参照）。
class AddLastAnalyticsViewedAtToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :last_analytics_viewed_at, :datetime,
               comment: "グラフ・進捗分析ページ(H-4)を最後に開いた日時。Bottom Navigationの未確認AI分析バッジのリセット判定に使用。"
  end
end