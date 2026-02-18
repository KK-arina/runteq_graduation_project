# ==============================================================================
# HabitRecordsController（最終確定版）
# ==============================================================================
# 【設計方針】
#   Controller は「流れの制御」だけを担当する。
#   「どのように変更するか」のロジックは全てモデルに任せる。
#
# 【params 構造について】
#   このコントローラーは Strong Parameters（require/permit）を使わない。
#   理由: completed という単一の値を受け取るだけであり、
#         Habit モデルの属性を一括代入するわけではないため。
#   受け取る params: { completed: "1" } または { completed: "0" }
#   → params[:completed] == "1" で Boolean に変換して使う。
# ==============================================================================
class HabitRecordsController < ApplicationController
  before_action :require_login

  # set_habit: @habit をセットする（全アクションで実行）
  # セキュリティ: current_user.habits.active.find で
  #   「ログインユーザーの有効な習慣のみ」に絞る。
  #   他ユーザーの habit_id を URL に入れると RecordNotFound → 404 になる。
  before_action :set_habit

  # ===========================================================================
  # POST /habits/:habit_id/habit_records
  # create アクション
  # ===========================================================================
  # 【役割】
  #   今日の HabitRecord を「取得または新規作成」し、完了状態を更新する。
  #
  # 【モデルメソッドを使う理由】
  #   HabitRecord.find_or_create_for: 「どの条件で作成するか」をモデルに任せる。
  #   update_completed!:              「どのカラムを更新するか」をモデルに任せる。
  #   → Controller はカラム名（completed）を直接知らなくてよい設計（疎結合）。
  # ===========================================================================
  def create
    # モデルメソッドで「今日のレコード」を取得または作成する
    @habit_record = HabitRecord.find_or_create_for(current_user, @habit)

    # モデルメソッドで完了状態を更新する
    # params[:completed] == "1" で Stimulus から送信された文字列を Boolean に変換
    @habit_record.update_completed!(params[:completed] == "1")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end
      format.html { redirect_to habits_path, notice: "記録を保存しました" }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_#{@habit.id}",
          partial: "habit_records/habit_record_error",
          locals:  { habit: @habit, error_message: e.message }
        )
      end
      format.html { redirect_to habits_path, alert: "記録の保存に失敗しました" }
    end
  end

  # ===========================================================================
  # PATCH /habits/:habit_id/habit_records/:id
  # update アクション
  # ===========================================================================
  # 【役割】
  #   既存の HabitRecord の完了状態を更新する。
  #
  # 【セキュリティ】
  #   current_user.habit_records.find(params[:id]) で
  #   「ログインユーザーのレコードのみ」を検索する。
  #   他ユーザーのレコード ID を URL に入れると RecordNotFound → エラーになる。
  #   ※ HabitRecord.find(params[:id]) だと他ユーザーのレコードも取れてしまう（NG）
  # ===========================================================================
  def update
    # セキュリティ: current_user のレコードのみ取得（他ユーザーは RecordNotFound）
    @habit_record = current_user.habit_records.find(params[:id])

    # モデルメソッドで完了状態を更新する
    @habit_record.update_completed!(params[:completed] == "1")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end
      format.html { redirect_to habits_path, notice: "記録を更新しました" }
    end
  rescue ActiveRecord::RecordNotFound
    # 他ユーザーのレコードや存在しない ID へのアクセス
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_#{@habit.id}",
          partial: "habit_records/habit_record_error",
          locals:  { habit: @habit, error_message: "記録が見つかりませんでした" }
        )
      end
      format.html { redirect_to habits_path, alert: "記録が見つかりませんでした" }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_#{@habit.id}",
          partial: "habit_records/habit_record_error",
          locals:  { habit: @habit, error_message: e.message }
        )
      end
      format.html { redirect_to habits_path, alert: "記録の更新に失敗しました" }
    end
  end

  private

  # ===========================================================================
  # set_habit（private メソッド）
  # ===========================================================================
  # 【役割】
  #   @habit インスタンス変数をセットする。
  #
  # 【head :not_found and return について】
  #   head :not_found → HTTP 404 ステータスのみ返す（ボディなし、パーシャル不要）
  #   and return      → メソッドを即座に終了する（アクション本体への継続を防ぐ）
  #
  # 【なぜ respond_to { format.turbo_stream ... } をやめたか】
  #   共通パーシャル shared/_flash_message を render しようとすると、
  #   そのパーシャルが存在しない場合に MissingTemplate エラーになる。
  #   head :not_found なら外部パーシャルに依存しないため安全で堅牢。
  # ===========================================================================
  def set_habit
    @habit = current_user.habits.active.find(params[:habit_id])
  rescue ActiveRecord::RecordNotFound
    head :not_found and return
  end
end