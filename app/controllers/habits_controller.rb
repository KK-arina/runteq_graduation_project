# app/controllers/habits_controller.rb
#
# 習慣（Habit）に関するHTTPリクエストを処理するコントローラーです。
# index  → 習慣一覧の表示
# new    → 新規作成フォームの表示
# create → 新規作成の保存処理
# destroy→ 論理削除処理

class HabitsController < ApplicationController
  # ============================================================
  # before_action（アクション実行前に必ず呼ばれる処理）
  # ============================================================

  # require_login: 全アクションに対してログイン必須チェック
  # ApplicationController で定義済みのメソッドを呼び出しています。
  before_action :require_login

  # require_unlocked: create と destroy の実行前にロックチェック
  # ロック中はこれらのアクションを実行させません。
  # only: [:create, :destroy] で対象アクションを限定しています。
  # index や new はロック中でも表示できます（閲覧はOK）。
  before_action :require_unlocked, only: [:create, :destroy]

  # set_habit: destroy の実行前に @habit を取得
  # params[:id] で指定された習慣を「現在のユーザーの習慣の中から」探します。
  # 他のユーザーの習慣は取得できないようにセキュリティ制御しています。
  before_action :set_habit, only: [:destroy]

  # ============================================================
  # GET /habits
  # ============================================================
  # 習慣一覧ページを表示します。
  # @habits     → 現在のユーザーの有効な習慣（論理削除されていない）
  # @habit_stats → 習慣ごとの今週の進捗率ハッシュ
  # @today_records_hash → 今日の習慣記録ハッシュ（N+1対策）
  # @locked     → ロック状態（ビューでボタンの活性/非活性に使用）
  def index
    # active スコープ: deleted_at が nil（論理削除されていない）習慣のみ
    # order(created_at: :desc): 新しく作った習慣が上に来るよう並び替え
    @habits = current_user.habits.active.order(created_at: :desc)

    # N+1問題対策①:
    # 今日の HabitRecord を1回のSQLで一括取得して habit_id をキーにしたハッシュを作成
    # ビュー内のループで毎回DBを叩かないようにするための工夫です。
    today = HabitRecord.today_for_record
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: today)
      .index_by(&:habit_id)

    # N+1問題対策②:
    # 全習慣の週次進捗を事前計算して { habit_id => { rate:, completed_count: } } のハッシュに格納
    # ビュー内で @habit_stats[habit.id] と書くだけで取得できます。
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    # ロック状態をインスタンス変数に格納します。
    # ビューでは @locked で参照できます。
    # locked? は ApplicationController で定義したメソッドです。
    @locked = locked?
  end

  # ============================================================
  # GET /habits/new
  # ============================================================
  # 新規作成フォームを表示します。
  # before_action :require_unlocked は new には設定していないため、
  # ロック中でもフォームページ自体は表示されます。
  # （ただし送信（create）はロックされています）
  def new
    # current_user.habits.build → user_id が自動でセットされた新規 Habit インスタンス
    @habit = current_user.habits.build
  end

  # ============================================================
  # POST /habits
  # ============================================================
  # 習慣の新規作成処理です。
  # before_action :require_unlocked により、ロック中は実行されません。
  def create
    @habit = current_user.habits.build(habit_params)

    if @habit.save
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の登録に失敗しました"
      # status: :unprocessable_entity (422) を返すのは
      # Turbo Drive がフォームエラーを正しく扱うために必要です。
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # DELETE /habits/:id
  # ============================================================
  # 習慣の論理削除処理です。
  # before_action :require_unlocked により、ロック中は実行されません。
  # before_action :set_habit により、@habit が事前にセットされています。
  def destroy
    if @habit.soft_delete
      flash[:notice] = "習慣を削除しました"
      # status: :see_other (303) はTurbo対応のリダイレクトに必要です。
      # DELETE後のリダイレクトは303を使うのがRails 7の推奨です。
      redirect_to habits_path, status: :see_other
    else
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # ----------------------------------------------------------
  # habit_params
  # ----------------------------------------------------------
  # Strong Parameters: フォームから送られてくるパラメータのうち、
  # :name と :weekly_target のみを許可します。
  # :user_id などは意図的に除外することでセキュリティを担保しています。
  def habit_params
    params.require(:habit).permit(:name, :weekly_target)
  end

  # ----------------------------------------------------------
  # set_habit
  # ----------------------------------------------------------
  # destroy アクションの前に実行され、@habit をセットします。
  # current_user.habits.active.find → 「現在のユーザーの有効な習慣の中から」探すため、
  # 他ユーザーの習慣や論理削除済みの習慣にはアクセスできません。
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # 習慣が見つからない場合（他ユーザーの習慣 or 削除済み）はエラーを表示して一覧へ
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end
end