# ==================== SessionsController ====================
# このコントローラーは、ログイン・ログアウトに関する処理を担当します
# 
# セッション（Session）とは？
# - ブラウザとサーバー間で状態を保持する仕組み
# - Railsでは、暗号化されたCookieにセッションIDを保存
# - サーバーは、セッションIDを見て「誰がアクセスしているか」を判別
# 
# アクション:
# - new: ログインフォームを表示
# - create: ログイン処理（認証）
# - destroy: ログアウト処理（セッション破棄）

class SessionsController < ApplicationController
  # ==================== ログインフォーム表示 ====================
  # GET /login
  # 目的: ログインフォームを表示
  def new
    # new.html.erb を表示するだけなので、特に処理は不要
    # Railsは自動的に app/views/sessions/new.html.erb を探して表示する
  end

  # ==================== ログイン処理 ====================
  # POST /login
  # 目的: メールアドレスとパスワードで認証し、ログイン状態にする
  def create
    # ==================== ステップ1: メールアドレスを安全に取得 ====================
    # params[:session][:email]: フォームから送信されたメールアドレス
    # 
    # なぜ to_s を使う？
    # - params[:session] や [:email] が nil の場合、downcase でエラーになる
    # - to_s を使うことで nil を安全に "" に変換
    # - セキュリティ強化: フォーム改ざん対策
    # 
    # 例:
    # nil.to_s → ""
    # "Test@Example.com".to_s.downcase → "test@example.com"
    email = params[:session][:email].to_s.downcase
    
    # User.find_by(email: email): メールアドレスでユーザーを検索
    #   - 見つかった場合: Userオブジェクトを返す
    #   - 見つからない場合: nil を返す
    user = User.find_by(email: email)
    
    # ==================== ステップ2: ユーザーが存在し、パスワードが正しいかチェック ====================
    # if user && user.authenticate(params[:session][:password]):
    # 
    # user: ユーザーが見つかったか？
    #   - nil の場合: 左側が false なので、右側（authenticate）は実行されない
    #   - Userオブジェクトの場合: 右側（authenticate）を実行
    # 
    # &&: AND演算子（論理積）
    #   - 左側が true で、かつ右側も true の場合のみ true
    #   - 左側が false の場合、右側は実行されない（短絡評価）
    # 
    # user.authenticate(params[:session][:password]):
    #   - has_secure_password が提供するメソッド
    #   - パスワードが正しい場合: Userオブジェクトを返す（truthy）
    #   - パスワードが間違っている場合: false を返す
    # 
    # params[:session][:password]: フォームから送信されたパスワード
    if user && user.authenticate(params[:session][:password])
      # ==================== ログイン成功時の処理 ====================
      
      # reset_session: セッション固定攻撃対策
      # 
      # セッション固定攻撃とは？
      #   1. 攻撃者が、被害者に特定のセッションIDを使わせる
      #   2. 被害者がそのセッションIDでログイン
      #   3. 攻撃者が同じセッションIDでアクセス → 被害者になりすます
      # 
      # reset_session を実行すると、新しいセッションIDが発行される
      # これにより、攻撃者が事前に知っているセッションIDは無効になる
      # 
      # ログイン時に必ず実行するのがRailsのベストプラクティス
      reset_session
      
      # session[:user_id] = user.id: セッションにユーザーIDを保存
      # これにより、次回以降のリクエストで「このユーザーがログインしている」と判別できる
      # session: Railsが提供するハッシュ（辞書）のような変数
      # ブラウザのCookieに暗号化して保存される
      session[:user_id] = user.id
      
      # flash[:notice]: フラッシュメッセージ（成功メッセージ）
      # notice: 成功メッセージ用（緑色で表示されることが多い）
      flash[:notice] = "ログインしました"
      
      # redirect_to root_path: TOPページにリダイレクト
      # ログイン後は通常、ダッシュボードやTOPページに遷移する
      redirect_to root_path
    else
      # ==================== ログイン失敗時の処理 ====================
      
      # flash.now[:alert]: フラッシュメッセージ（エラーメッセージ）
      # flash.now: リダイレクトではなくrenderの場合に使用
      # 理由: renderは新しいリクエストを発生させないため、通常のflashだと次のページまで残ってしまう
      flash.now[:alert] = "メールアドレスまたはパスワードが正しくありません"
      
      # render :new: newアクションのビュー（app/views/sessions/new.html.erb）を再表示
      # render: 同じリクエスト内でビューを表示（リダイレクトしない）
      # status: :unprocessable_entity: ステータスコード422
      # 422 Unprocessable Entity: リクエストの形式は正しいが、内容に問題がある（認証失敗）
      render :new, status: :unprocessable_entity
    end
  end

  # ==================== ログアウト処理 ====================
  # DELETE /logout
  # 目的: セッションを破棄し、ログアウト状態にする
  def destroy
    # reset_session: セッション全体をリセット
    # 
    # ログアウト時もセキュリティのため、セッション全体をリセットするのが推奨
    # これにより、セッションハイジャック攻撃のリスクを減らせる
    # 
    # session.delete(:user_id) ではなく reset_session を使う理由:
    # - より確実にセッションデータを削除
    # - CSRF トークンなども再生成される
    reset_session
    
    # @current_user = nil: インスタンス変数をリセット
    # ApplicationControllerの current_user メソッドでメモ化しているため、
    # ここでリセットしないと、同じリクエスト内でまだログイン状態に見える
    @current_user = nil
    
    # flash[:notice]: フラッシュメッセージ（成功メッセージ）
    flash[:notice] = "ログアウトしました"
    
    # redirect_to root_path: TOPページにリダイレクト
    # status: :see_other: HTTPステータスコード 303
    # 
    # なぜ status: :see_other が必要？
    # - Rails 7 + Turbo の環境では、DELETE リクエスト後のリダイレクトに推奨
    # - 303 See Other: POSTやDELETEの後、GETでリダイレクトすることを明示
    # - これにより、ブラウザの「戻る」ボタンで再度DELETEリクエストが送られるのを防ぐ
    # 
    # Turboが有効な環境では、このステータスコードがないと正しくリダイレクトされない場合がある
    redirect_to root_path, status: :see_other
  end
end
