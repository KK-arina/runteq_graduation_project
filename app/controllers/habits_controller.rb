# 習慣管理のコントローラー
# ユーザーの習慣の作成・表示・削除を担当
class HabitsController < ApplicationController
  # すべてのアクション実行前にログインチェックを行う
  # before_action: コントローラーのアクション実行前に特定のメソッドを実行する仕組み
  # require_login: ApplicationControllerで定義されたログイン必須チェックメソッド
  before_action :require_login

  # GET /habits
  # 習慣一覧ページの表示
  def index
    # current_user: ApplicationControllerで定義、現在ログイン中のユーザーを取得
    # .habits: Userモデルの has_many :habits アソシエーションで定義された関連
    # .active: Habitモデルで定義されたスコープ（deleted_at が NULL の有効な習慣のみ取得）
    # .order(created_at: :desc): 作成日時の降順（新しい順）で並び替え
    @habits = current_user.habits.active.order(created_at: :desc)
  end

  # GET /habits/new
  # 新規習慣作成フォームの表示
  def new
    # current_user.habits.build: 現在のユーザーに紐づく新しいHabitオブジェクトを作成
    # build メソッド: user_id が自動的に設定される（ログイン中のユーザーIDが入る）
    # Habit.new との違い: user_id が自動設定されるため、より安全
    # @habit: インスタンス変数（@が付く変数）はビュー（HTMLテンプレート）で使える
    # フォームヘルパー form_with でこのオブジェクトを使ってフォームを生成
    @habit = current_user.habits.build
  end

  # POST /habits
  # 新規習慣の作成処理
  def create
    # current_user.habits.build: 現在のユーザーに紐づく新しいHabitオブジェクトを作成
    # build メソッド: user_id が自動的に設定される（ログイン中のユーザーIDが入る）
    # habit_params: 後述の private メソッド、Strong Parameters でフォームから送られてきた値を安全に取得
    @habit = current_user.habits.build(habit_params)

    # @habit.save: データベースに保存を試みる
    # 保存成功時は true、バリデーションエラー時は false を返す
    if @habit.save
      # 保存成功時の処理

      # flash[:notice]: 一時的なメッセージを保存（次のページ表示時に1回だけ表示される）
      # notice: 成功メッセージ用（緑色で表示される）
      flash[:notice] = "習慣を登録しました"
      
      # redirect_to: 指定したURLにリダイレクト（ページ遷移）
      # habits_path: /habits への パス（習慣一覧ページ）
      # Rails の routes.rb で定義された名前付きルート
      redirect_to habits_path
    else
      # 保存失敗時の処理（バリデーションエラー）

      # flash.now[:alert]: 現在のページ表示時のみ有効なメッセージ
      # リダイレクトしない場合は flash.now を使う
      # alert: エラーメッセージ用（赤色で表示される）
      flash.now[:alert] = "習慣の登録に失敗しました"
      
      # render :new: new.html.erb テンプレートを再表示
      # redirect と違い、@habit の内容（入力値とエラー情報）が保持される
      # status: :unprocessable_entity: HTTPステータスコード 422 を返す
      # これによりブラウザに「処理できなかった」ことを正しく伝える
      # Turbo（Hotwire）と正しく連携するために必須
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Strong Parameters: セキュリティ対策
  # フォームから送られてきたパラメータのうち、許可したものだけを取得する仕組み
  # これにより、悪意のあるユーザーが不正なデータを送信するのを防ぐ
  def habit_params
    # params: フォームから送られてきたすべてのパラメータ
    # .require(:habit): habit キーが必須（なければエラー）
    # .permit(:name, :weekly_target): name と weekly_target のみ許可
    # それ以外のパラメータ（例: user_id, deleted_at など）は無視される
    # 
    # セキュリティの重要性:
    #   悪意のあるユーザーが params[:habit][:user_id] を送信しても
    #   permit で許可していないため無視される
    #   これにより、他のユーザーの習慣として登録されることを防ぐ
    params.require(:habit).permit(:name, :weekly_target)
  end
end
