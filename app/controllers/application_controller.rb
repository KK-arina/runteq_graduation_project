# ==================== ApplicationController ====================
# このコントローラーは、全てのコントローラーの親クラスです
# ここに定義したメソッドは、全てのコントローラーで使用できます

class ApplicationController < ActionController::Base
# ==================== ブラウザ制限 ====================
  # Rails 7.2の標準機能：古いブラウザ（IEなど）をブロックします
  # versions: :modern と指定することで、最新のブラウザのみ許可します
  allow_browser versions: :modern
  
  # ==================== ヘルパーメソッド ====================
  # helper_method: コントローラーのメソッドをビュー（HTMLテンプレート）でも使えるようにする
  # 例: app/views/layouts/application.html.erb で current_user を使用可能
  helper_method :current_user, :logged_in?
  
  private
  
  # ==================== 現在ログインしているユーザーを取得 ====================
  # current_user: 現在ログインしているユーザーを返す
  # 
  # 使用例:
  # - ビュー: <%= current_user.name %> （ログインユーザーの名前を表示）
  # - コントローラー: if current_user.admin? （管理者権限チェック）
  def current_user
    # ||=: 代入演算子（メモ化）
    # @current_user がnilまたはfalseの場合のみ、右辺を実行して代入
    # すでに@current_userに値がある場合は、右辺を実行しない（データベースへの問い合わせを1回だけにする）
    # 
    # 例:
    # 1回目: @current_user = User.find_by(id: session[:user_id])
    # 2回目: @current_user（既に値があるのでfind_byを実行しない）
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    
    # session[:user_id]: セッションに保存されたユーザーID
    # if session[:user_id]: セッションにuser_idが存在する場合のみ実行
    # User.find_by(id: ...): 指定されたIDのユーザーをDBから検索
    #   - 見つかった場合: Userオブジェクトを返す
    #   - 見つからない場合: nil を返す
  end
  
  # ==================== ログイン状態をチェック ====================
  # logged_in?: ログインしているかどうかを真偽値で返す
  # 
  # 使用例:
  # - ビュー: <% if logged_in? %> （ログイン中のみ表示）
  # - コントローラー: redirect_to login_path unless logged_in?
  def logged_in?
    # current_user.present?: current_userがnilでない（= ログイン中）
    # present?: Railsが提供するメソッド
    #   - nil または 空文字列 → false
    #   - それ以外 → true
    current_user.present?
  end
end
