# app/controllers/admin/dashboards_controller.rb
#
# ==============================================================================
# Admin::DashboardsController: 管理画面のトップ（GET /admin）
# ==============================================================================
#
# 【BaseController を継承する理由】
#   管理者の確認・ヘッダー・再ログインの確認を、すべて Admin::BaseController に任せるため。
#   このクラスでは「何を表示するか」だけを書く。
# ==============================================================================
module Admin
  class DashboardsController < BaseController
    # show: GET /admin
    #
    # 【AdminUsageStatsService.fetch を使う理由】
    #   集計の結果を Solid Cache に10分間保存して使い回すため。
    #   管理画面を何度開き直しても、10分に1回しか集計の SQL が走らない（Neon の負荷を抑える）。
    #   中身は件数・割合・日付だけで、個人情報は含まない。
    def show
      @stats = AdminUsageStatsService.fetch
    end
  end
end
