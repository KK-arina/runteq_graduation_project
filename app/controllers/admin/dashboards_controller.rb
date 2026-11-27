# app/controllers/admin/dashboards_controller.rb
#
# ==============================================================================
# Admin::DashboardsController: 管理画面のトップ（GET /admin）
# ==============================================================================
#
# 【BaseController を継承する理由】
#   管理者の確認・ヘッダー・再ログインの確認を、すべて Admin::BaseController に任せるため。
#   このクラスでは「何を表示するか」だけを書く。
#
# 【今の状態】
#   このコミットでは、認可の仕組みだけを先に作り、画面は仮のものにしている。
#   全体の集計とグラフは、あとのコミットで追加する。
# ==============================================================================
module Admin
  class DashboardsController < BaseController
    # show: GET /admin
    #   中身は app/views/admin/dashboards/show.html.erb で表示する。
    def show
    end
  end
end
