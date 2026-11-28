# app/controllers/admin/users_controller.rb
#
# ==============================================================================
# Admin::UsersController: 管理画面のユーザー一覧（GET /admin/users）
# ==============================================================================
#
# 【BaseController を継承する理由】
#   管理者の確認・キャッシュ禁止のヘッダー・再ログインの確認を、
#   すべて Admin::BaseController に任せるため（入れ忘れを防ぐ）。
#
# 【読み取り専用】
#   一覧（index）だけを用意し、ユーザーの編集・削除はしない。
# ==============================================================================
module Admin
  class UsersController < BaseController
    # index: GET /admin/users?filter=dormant&page=2
    #
    # 【params をそのまま渡しても安全な理由】
    #   AdminUserListService が、filter は決まった値（FILTERS）以外を "all" に、
    #   page は整数にしてから使うため、SQL に直接入ることはない。
    def index
      @result = AdminUserListService.new(filter: params[:filter], page: params[:page]).call
    end
  end
end
