# app/controllers/habit_records_controller.rb
# =============================================================
# 習慣の日次記録（HabitRecord）を管理するController
# ネストされたルーティング: /habits/:habit_id/habit_records
# チェックボックスを押したときの即時保存を担当する
# =============================================================

class HabitRecordsController < ApplicationController
  # すべてのアクションの前にログインチェックを行う
  before_action :require_login
  # すべてのアクションの前に @habit を取得する
  before_action :set_habit

  # POST /habits/:habit_id/habit_records
  # チェックボックスをON/OFFしたとき（まだ今日の記録がない場合）に呼ばれる
  def create
    # 今日の記録を取得するか、なければ新規作成する
    # find_or_create_for : HabitRecordモデルのクラスメソッド（AM4:00基準の日付で検索/作成）
    @habit_record = HabitRecord.find_or_create_for(current_user, @habit)
    # params[:completed] == "1" の場合 true、"0" の場合 false として更新する
    @habit_record.update_completed!(params[:completed] == "1")

    # respond_to : リクエストのAcceptヘッダーに応じてレスポンス形式を切り替える
    respond_to do |format|
      # Turbo Streamリクエスト（Stimulusから fetch で呼ばれる場合）
      format.turbo_stream do
        # turbo_stream.replace : 指定したidのDOM要素を新しいHTMLで置き換える
        # "habit_record_row_#{@habit.id}" : パーシャル側のid属性と一致させる
        render turbo_stream: turbo_stream.replace(
          "habit_record_row_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end
      # 通常のHTMLリクエスト（JavaScriptが無効な環境など）
      format.html { redirect_to dashboard_path, notice: "記録を保存しました" }
    end
  end

  # PATCH /habits/:habit_id/habit_records/:id
  # チェックボックスをON/OFFしたとき（今日の記録が既にある場合）に呼ばれる
  def update
    # current_user.habit_records.find : セキュリティ対策
    # 他人のレコードをURLから直接操作できないよう、ログインユーザーの記録のみ取得する
    @habit_record = current_user.habit_records.find(params[:id])
    @habit_record.update_completed!(params[:completed] == "1")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_row_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end
      format.html { redirect_to dashboard_path, notice: "記録を更新しました" }
    end
  end

  private

  # @habit を取得する before_action 用メソッド
  # current_user.habits.active.find : ログインユーザーの有効な習慣のみ検索
  # 他人の習慣IDがURLに指定されても取得できない（セキュリティ対策）
  def set_habit
    @habit = current_user.habits.active.find(params[:habit_id])
  rescue ActiveRecord::RecordNotFound
    # 見つからない場合は 404 を返す
    # head :not_found : ボディなしで 404 レスポンスを返す
    # and return : これ以降の処理を中断する
    head :not_found and return
  end
end