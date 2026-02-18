# ==============================================================================
# HabitsController（更新版）
# ==============================================================================
# 【変更点】
#   index アクションで今日の HabitRecord をまとめて取得するロジックを追加。
#   N+1 問題を防ぐため、SQL を 1 回だけ発行してハッシュに変換する。
# ==============================================================================
class HabitsController < ApplicationController
  # ログイン必須
  before_action :require_login

  # destroy アクション実行前に @habit をセットする
  before_action :set_habit, only: [:destroy]

  # ===========================================================================
  # GET /habits
  # index アクション
  # ===========================================================================
  # 【N+1 問題の解消】
  #   NG パターン:
  #     @habits.each { |h| h.habit_records.for_date(today) }
  #     → 習慣の数だけ SQL が発行される（習慣 100 件 → 101 クエリ）
  #
  #   OK パターン（今回の実装）:
  #     1. 今日の全レコードを 1 クエリで取得
  #     2. habit_id をキーにしたハッシュに変換（O(1) アクセス）
  #     3. ビューではハッシュから取得（SQL 発行なし）
  #     → SQL は 2 クエリで完結（習慣一覧 + 今日の記録一覧）
  # ===========================================================================
  def index
    # 有効な習慣を作成日時の降順で取得
    @habits = current_user.habits.active.order(created_at: :desc)

    # AM 4:00 基準の今日の日付を取得
    today = HabitRecord.today_for_record

    # 今日の記録を全習慣分まとめて取得し、habit_id → record のハッシュに変換する。
    # index_by(key) は配列をハッシュに変換する Active Support メソッド。
    # 例: [#<HabitRecord habit_id: 1, ...>, #<HabitRecord habit_id: 2, ...>]
    #   → { 1 => #<HabitRecord ...>, 2 => #<HabitRecord ...> }
    #
    # where(habit_id: @habits.ids) で「今表示する習慣の記録のみ」に絞る（最適化）
    @today_records_hash = current_user.habit_records
                                      .for_date(today)
                                      .where(habit_id: @habits.ids)
                                      .index_by(&:habit_id)
  end

  # ===========================================================================
  # GET /habits/new
  # ===========================================================================
  def new
    @habit = current_user.habits.build
  end

  # ===========================================================================
  # POST /habits
  # ===========================================================================
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

  # ===========================================================================
  # DELETE /habits/:id
  # ===========================================================================
  def destroy
    # @habit は before_action :set_habit でセット済み
    if @habit.soft_delete
      flash[:notice] = "習慣を削除しました"
      redirect_to habits_path, status: :see_other
    else
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  private

  # ---------------------------------------------------------------------------
  # habit_params
  # ---------------------------------------------------------------------------
  # Strong Parameters: name と weekly_target のみ受け付ける。
  # user_id を params に含めていても無視される（セキュリティ）。
  def habit_params
    params.require(:habit).permit(:name, :weekly_target)
  end

  # ---------------------------------------------------------------------------
  # set_habit
  # ---------------------------------------------------------------------------
  # current_user.habits.active で「ログインユーザーの有効な習慣」のみ検索。
  # 他ユーザーの habit_id を URL に入れても RecordNotFound になる（セキュリティ）。
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end
end