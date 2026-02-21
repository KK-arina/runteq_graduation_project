# app/controllers/application_controller.rb
# =============================================================
# すべてのControllerの親クラス
# ここに書いたメソッドはアプリ全体で使えるようになる
# =============================================================

class ApplicationController < ActionController::Base
  # モダンブラウザのみ許可するRails 7のセキュリティ機能
  allow_browser versions: :modern

  # helper_method: ビュー（HTML）からも使えるようにするメソッドを指定する
  # current_user と logged_in? はヘッダーなどのビューでも使いたいので登録する
  helper_method :current_user, :logged_in?

  private

  # 現在ログインしているユーザーを返すメソッド
  # @current_user ||= ... : 同じリクエスト内では一度だけDBに問い合わせる（メモ化）
  # session[:user_id] : ログイン時にセッションに保存したユーザーID
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # ログイン状態を返すメソッド（true / false）
  # present? : nilでも空でもなければtrue
  def logged_in?
    current_user.present?
  end

  # ログインが必要なページへのアクセスを制御するメソッド
  # before_action :require_login で各Controllerから呼び出す
  def require_login
    unless logged_in?
      flash[:alert] = "ログインしてください"
      redirect_to login_path
    end
  end
end