# app/controllers/habits_controller.rb
#
# 【このファイルの役割】
# 習慣管理に関するHTTPリクエストを受け取り、
# モデルに処理を依頼してビューに結果を渡す「橋渡し役」。

class HabitsController < ApplicationController
  # ============================================================
  # before_action（アクション実行前に必ず走る処理）
  # ============================================================

  # 【before_action :require_login】
  # ログインしていないユーザーをログインページへリダイレクトさせる。
  # ApplicationController に定義されている require_login メソッドを呼ぶ。
  before_action :require_login

  # 【before_action :set_habit, only: [:destroy]】
  # destroy アクション実行前だけ set_habit を呼ぶ。
  # @habit インスタンス変数に「現在のユーザーの、有効な習慣」をセットする。
  before_action :set_habit, only: [:destroy]

  # ============================================================
  # GET /habits
  # 習慣一覧ページを表示する
  # ============================================================
  def index
    # current_user.habits → ログイン中ユーザーに紐づく習慣だけを取得
    # .active → 論理削除されていない習慣だけに絞り込む（scopeを使用）
    # .order(created_at: :desc) → 新しく作った順に並べる
    @habits = current_user.habits.active.order(created_at: :desc)

    # -------------------------------------------------------
    # 【N+1問題対策①】今日の HabitRecord を一括取得してハッシュ化
    # -------------------------------------------------------
    # N+1問題とは：ループの中でDBクエリが何度も発行されてしまう問題。
    # 先に「今日の全記録」を1回のクエリで取得し、
    # ハッシュ（キー: habit_id, 値: habit_record）に変換しておく。
    # ビューでは @today_records_hash[habit.id] でO(1)（即座）に取得できる。
    today = HabitRecord.today_for_record
    @today_records_hash = HabitRecord
                            .where(user: current_user, habit: @habits, record_date: today)
                            .index_by(&:habit_id)

    # -------------------------------------------------------
    # 【N+1問題対策②】今週の進捗統計を事前に一括計算（Issue #16）
    # -------------------------------------------------------
    # なぜここで計算するのか：
    # ビューのループ内で habit.weekly_progress_stats を呼ぶと、
    # 習慣の数だけDBクエリが発生してしまう（N+1問題）。
    # そのため、コントローラーで全習慣分を事前計算してハッシュに格納する。
    #
    # 変数名を @progress_rates から @habit_stats に変更した理由：
    # 進捗率（rate）だけでなく完了日数（completed_count）も格納するため、
    # 「統計情報（stats）」という名前の方が内容を正確に表している。
    #
    # 格納されるデータの例:
    # {
    #   1 => { rate: 71, completed_count: 5 },
    #   2 => { rate: 100, completed_count: 7 },
    #   3 => { rate: 0,  completed_count: 0 }
    # }
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      # each_with_object は「空のハッシュを引き継ぎながらループを回すメソッド」。
      # 各習慣のIDをキーにして、統計情報を格納する。
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end
  end

  # ============================================================
  # GET /habits/new
  # 習慣新規作成フォームを表示する
  # ============================================================
  def new
    # current_user.habits.build → user_id が自動でセットされた空の Habit オブジェクトを作る
    @habit = current_user.habits.build
  end

  # ============================================================
  # POST /habits
  # 習慣を新規作成する
  # ============================================================
  def create
    @habit = current_user.habits.build(habit_params)

    if @habit.save
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の登録に失敗しました"
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # DELETE /habits/:id
  # 習慣を論理削除する
  # ============================================================
  def destroy
    if @habit.soft_delete
      flash[:notice] = "習慣を削除しました"
      redirect_to habits_path, status: :see_other
    else
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  # ============================================================
  # private（外部から呼び出されるべきでないメソッド）
  # ============================================================
  private

  # 【habit_params】
  # Strong Parameters: フォームから受け取るパラメータを明示的に許可する。
  # ここに書いていないパラメータ（例: user_id）は無視されるため安全。
  def habit_params
    params.require(:habit).permit(:name, :weekly_target)
  end

  # 【set_habit】
  # before_action から呼ばれ、@habit に「現在のユーザーの有効な習慣」をセットする。
  # current_user.habits.active.find → ログインユーザーの習慣だけを検索対象にすることで
  # 他ユーザーの習慣を操作しようとしても RecordNotFound になり安全。
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end
end