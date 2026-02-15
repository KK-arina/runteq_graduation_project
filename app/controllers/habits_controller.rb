# app/controllers/habits_controller.rb
# 習慣管理のコントローラー
# このコントローラーは習慣の一覧表示を担当します

class HabitsController < ApplicationController
  # ログインしていないユーザーはアクセスできないようにする
  # ApplicationControllerのrequire_loginメソッドを使用
  before_action :require_login

  # GET /habits
  # 習慣一覧ページを表示するアクション
  def index
    # 現在ログインしているユーザーの習慣を取得
    # activeスコープを使用して、論理削除されていない習慣のみを取得
    # created_at: :descで新しい順に並び替え
    @habits = current_user.habits.active.order(created_at: :desc)
    
    # ログに出力（開発時のデバッグ用）
    Rails.logger.debug "Habits count: #{@habits.count}"
  end
end
