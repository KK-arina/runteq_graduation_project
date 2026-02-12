# ==================== UsersController ====================
# このコントローラーは、ユーザー登録に関する処理を担当します
# 
# アクション:
# - new: 新規登録フォームを表示
# - create: ユーザーを作成してデータベースに保存

class UsersController < ApplicationController
  # ==================== 新規登録フォーム表示 ====================
  # GET /users/new
  # 目的: 新規ユーザー登録フォームを表示
  def new
    # @user: インスタンス変数（@が付く変数）
    # インスタンス変数はコントローラーからビュー（HTMLテンプレート）に値を渡すために使う
    # User.new: 空のUserオブジェクトを作成（まだDBには保存されていない）
    # これをフォームに渡すことで、form_withヘルパーが適切なHTMLを生成できる
    @user = User.new
  end

  # ==================== ユーザー作成処理 ====================
  # POST /users
  # 目的: フォームから送信されたデータでユーザーを作成
  def create
    # @user = User.new(user_params): フォームから送信されたデータで新しいUserオブジェクトを作成
    # user_params: Strong Parametersで許可されたパラメータのみを取得（セキュリティ対策）
    @user = User.new(user_params)

    # if @user.save: ユーザーをデータベースに保存
    # save: バリデーションを実行し、問題なければDBに保存
    # 成功時: true を返す
    # 失敗時: false を返す（バリデーションエラーがある場合）
    if @user.save
      # ==================== 保存成功時の処理 ====================
      
      # session[:user_id] = @user.id: セッションにユーザーIDを保存（自動ログイン）
      # session: Railsが提供するハッシュ（辞書）のような変数
      # ブラウザのCookieに暗号化して保存される
      # サーバーは次回以降のリクエストでこのuser_idを見て、誰がアクセスしているか判別できる
      session[:user_id] = @user.id
      
      # flash[:notice]: フラッシュメッセージ（一度だけ表示されるメッセージ）
      # notice: 成功メッセージ用（緑色で表示されることが多い）
      # 次のページ（root_path）で表示され、その後自動的に消える
      flash[:notice] = "ユーザー登録が完了しました"
      
      # redirect_to root_path: TOPページにリダイレクト（画面遷移）
      # redirect_to: 別のURLに遷移する（新しいHTTPリクエストが発生）
      # root_path: config/routes.rbで定義したルートパス（/）
      redirect_to root_path
    else
      # ==================== 保存失敗時の処理 ====================
      
      # flash.now[:alert]: フラッシュメッセージ（今回のレンダリングでのみ表示）
      # alert: エラーメッセージ用（赤色で表示されることが多い）
      # flash.now: リダイレクトではなくrenderの場合に使用
      # 理由: renderは新しいリクエストを発生させないため、通常のflashだと次のページまで残ってしまう
      flash.now[:alert] = "ユーザー登録に失敗しました"
      
      # render :new: newアクションのビュー（app/views/users/new.html.erb）を表示
      # render: 同じリクエスト内でビューを表示（リダイレクトしない）
      # @userにはバリデーションエラー情報が含まれているため、フォームでエラーメッセージを表示できる
      # status: :unprocessable_entity: ステータスコード422
      # 422: リクエストの形式は正しいが、内容に問題がある（バリデーションエラー）
      # Rails 7 / Turbo では必須の設定
      render :new, status: :unprocessable_entity
    end
  end

  private

  # ==================== Strong Parameters ====================
  # Strong Parameters: セキュリティ対策のため、許可されたパラメータのみを受け取る仕組み
  # 
  # なぜ必要？
  # ユーザーが悪意を持って、想定外のパラメータを送信する可能性がある
  # 例: { user: { name: "太郎", email: "...", admin: true } }
  # adminパラメータを許可していないのに、管理者権限を付与しようとする攻撃
  # 
  # Strong Parametersがない場合、このような攻撃を防げない
  def user_params
    # params: コントローラーが受け取ったパラメータ（フォームから送信されたデータ）
    # 例: { user: { name: "太郎", email: "taro@example.com", password: "password123", ... } }
    
    # require(:user): paramsの中から:userキーのハッシュを取り出す
    # 必須: :userキーが存在しない場合はエラーになる
    
    # permit(:name, :email, :password, :password_confirmation): 
    # 指定されたキーのみを許可（ホワイトリスト方式）
    # これ以外のキーは無視される（セキュリティ対策）
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
