# app/controllers/pages_controller.rb
# =============================================================
# 静的ページ（ランディングページなど）を管理するController
# =============================================================

class PagesController < ApplicationController
  def index
    # ログイン済みのユーザーがルートパス（"/"）にアクセスした場合は
    # ダッシュボードへリダイレクトする
    # 未ログインユーザーはそのままランディングページを表示する
    if logged_in?
      redirect_to dashboard_path
    end
    # logged_in?がfalseの場合は何もしない → app/views/pages/index.html.erb を表示する
  end
end
