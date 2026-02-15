class HabitsController < ApplicationController
  # ログインしていないユーザーはアクセスできないようにする
  before_action :require_login
  
  # destroy アクション実行前に @habit を取得
  # set_habit メソッドで current_user の習慣のみを取得するため、
  # 他のユーザーの習慣を削除しようとしても NotFound エラーになる
  before_action :set_habit, only: [:destroy]
  
  # GET /habits
  def index
    # 現在ログインしているユーザーの習慣を取得
    # activeスコープで論理削除されていない習慣のみを取得
    # created_at: :descで新しい順に並び替え
    @habits = current_user.habits.active.order(created_at: :desc)
  end

  # GET /habits/new
  def new
    # 新規習慣オブジェクトを作成（フォーム表示用）
    @habit = current_user.habits.build
  end

  # POST /habits
  def create
    # current_user.habits.build で user_id を自動設定
    # Strong Parameters で :name, :weekly_target のみ許可
    @habit = current_user.habits.build(habit_params)
    
    if @habit.save
      # 保存成功時: フラッシュメッセージを設定して一覧ページへリダイレクト
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      # 保存失敗時: エラーメッセージを設定してフォームを再表示
      # status: :unprocessable_entity は Rails 7 / Turbo 対応
      # 422エラーを返すことで、Turboが適切にエラーを処理できる
      flash.now[:alert] = "習慣の登録に失敗しました"
      render :new, status: :unprocessable_entity
    end
  end
  
  # DELETE /habits/:id
  def destroy
    # @habit は before_action :set_habit で取得済み
    
    # 論理削除を実行（deleted_at に現在時刻を設定）
    # soft_delete メソッドは Habit モデルで定義済み
    if @habit.soft_delete
      # 削除成功時: 成功メッセージを表定して一覧ページへリダイレクト
      flash[:notice] = "習慣を削除しました"
      redirect_to habits_path, status: :see_other
    else
      # 削除失敗時: エラーメッセージを設定して一覧ページへリダイレクト
      # 通常、soft_delete は失敗しないが、万が一のためのエラーハンドリング
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  private

  # Strong Parameters
  # params から :habit キーを必須とし、:name, :weekly_target のみ許可
  # これにより、不正なパラメータ（例: user_id の上書き）を防ぐ
  def habit_params
    params.require(:habit).permit(:name, :weekly_target)
  end
  
  # @habit を取得するメソッド
  # current_user.habits.active で現在のユーザーの有効な習慣のみを検索
  # find(params[:id]) で指定された id の習慣を取得
  # 他のユーザーの習慣や論理削除済みの習慣は取得できない
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # 習慣が見つからない場合（他のユーザーの習慣 or 削除済み）
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end
end
