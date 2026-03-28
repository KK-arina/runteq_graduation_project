# app/controllers/habits_controller.rb
#
# ==============================================================================
# HabitsController（B-2: 除外日設定対応）
# ==============================================================================
# 【B-2 での変更内容】
#
#   ① habit_params に :excluded_day_numbers（配列）を追加
#      フォームから送られる除外日の曜日番号配列を受け取る。
#
#   ② create アクションで除外日を保存する処理を追加
#      ハビット保存後に save_excluded_days! を呼び出す。
#
#   ③ build_habit_stats を除外日対応（effective_weekly_target 使用）に更新
#      チェック型の分母を 7 から（7 - 除外日数）に変更する。
#
#   ④ index で習慣を取得するとき habit_excluded_days を eager load する
#      N+1 クエリを防ぐために includes(:habit_excluded_days) を追加。
# ==============================================================================

class HabitsController < ApplicationController
  before_action :require_login
  before_action :require_unlocked, only: [ :create, :update, :destroy ]
  before_action :set_habit, only: [ :edit, :update, :destroy ]

  # ============================================================
  # GET /habits
  # ============================================================
  def index
    # includes(:habit_excluded_days)（B-2 追加）
    # 【理由】
    #   excluded_day_numbers メソッドと effective_weekly_target メソッドが
    #   habit_excluded_days を参照する。
    #   includes を付けないと @habits.each のループ内で習慣ごとに
    #   SELECT * FROM habit_excluded_days WHERE habit_id = ? が発行され
    #   N+1 問題が起きる。
    #   includes を付けることで 1 クエリで全除外日を先読みできる。
    @habits = current_user.habits.active
                          .includes(:habit_excluded_days)
                          .order(created_at: :desc)

    today = HabitRecord.today_for_record
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: today)
      .index_by(&:habit_id)

    @habit_stats = build_habit_stats(@habits, current_user)
    @locked      = locked?
  end

  # ============================================================
  # GET /habits/new
  # ============================================================
  def new
    @habit = current_user.habits.build
  end

  # ============================================================
  # GET /habits/:id/edit
  # ============================================================
  def edit
    # @habit は before_action :set_habit で設定済み
    # ビューで既存の除外日をチェック済み状態で表示するために
    # @existing_excluded_days を渡す
    # 【理由】
    #   edit フォームでは「現在設定されている除外日」をチェック済みで表示する必要がある。
    #   @habit.excluded_day_numbers を使ってビューで判定する。
  end

  # ============================================================
  # PATCH /habits/:id
  # ============================================================
  def update
    # save_excluded_days! 内で destroy_all → 再登録するため
    # トランザクションで習慣の更新と除外日の更新を一体として扱う
    # 【理由】
    #   「習慣名の変更」と「除外日の変更」が同時に失敗した場合に
    #   中途半端な状態にならないようにする（A-7 のトランザクション設計に準拠）
    result = ApplicationRecord.with_transaction do
      @habit.update!(habit_params)
      save_excluded_days!(@habit, params[:excluded_day_numbers])
      true
    end

    if result
      flash[:notice] = "習慣を更新しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の更新に失敗しました"
      render :edit, status: :unprocessable_entity
    end

  rescue ActiveRecord::RecordInvalid => e
    # バリデーションエラー時はフォームを再表示する
    flash.now[:alert] = "習慣の更新に失敗しました"
    render :edit, status: :unprocessable_entity
  end

  # ============================================================
  # POST /habits
  # ============================================================
  def create
    @habit = current_user.habits.build(habit_params)

    # save_excluded_days! をトランザクション内で実行するために
    # ApplicationRecord.with_transaction でラップする
    # 【理由】
    #   習慣の保存と除外日の保存を一体として扱うことで、
    #   「習慣は作成されたが除外日の保存に失敗した」という
    #   中途半端な状態を防ぐ（A-7 のトランザクション設計に準拠）。
    result = ApplicationRecord.with_transaction do
      @habit.save!
      save_excluded_days!(@habit, params[:excluded_day_numbers])
      true
    end

    if result
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の登録に失敗しました"
      render :new, status: :unprocessable_entity
    end

  rescue ActiveRecord::RecordInvalid => e
    # バリデーションエラー時はフォームを再表示する
    # e.record.errors.full_messages で日本語エラーメッセージが取得できる
    flash.now[:alert] = "習慣の登録に失敗しました"
    render :new, status: :unprocessable_entity
  end

  # ============================================================
  # DELETE /habits/:id
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
  # Private メソッド
  # ============================================================
  private

  # habit_params
  # 【Strong Parameters】
  #   フォームから送られるパラメータのうち許可するものをホワイトリストで指定する。
  #   excluded_day_numbers は habit モデルのカラムではないため
  #   ここには含めず、別途 params[:excluded_day_numbers] で受け取る。
  def habit_params
    params.require(:habit).permit(:name, :weekly_target, :measurement_type, :unit)
  end

  # set_habit: destroy の前に @habit をセットする
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end

  # save_excluded_days!（B-2 修正版）
  # ==============================================================================
  # 【修正内容】
  #   修正前: nil または空の場合は return していたため、
  #           編集時に「チェックを全て外す」操作が無視されていた。
  #           → 既存の除外日がそのまま残るバグがあった。
  #
  #   修正後: 処理の先頭で必ず destroy_all（全削除）してから保存し直す。
  #           これにより「チェックを外した」操作も確実に DB に反映される。
  #
  # 【destroy_all を先頭に置く理由】
  #   「リセット＆セーブ」方式を採用することで、
  #   追加・削除・変更のすべてのパターンを1つのロジックで処理できる。
  #   差分管理（どれが増えてどれが減ったか）より実装がシンプルになる。
  #
  # 【なぜ create でなく new + habit_excluded_days.build なのか】
  #   destroy_all で既存レコードを消した後に create! を呼ぶので、
  #   UNIQUE 制約に引っかかることはない。
  # ==============================================================================
  def save_excluded_days!(habit, excluded_day_params)
    # 【修正ポイント】
    # まず既存の除外日を全削除する（更新時にチェックを外す操作に対応するため）
    # 【理由】
    #   destroy_all の前に return してしまうと、
    #   excluded_day_params が nil（全チェックを外した状態）のとき
    #   既存データが削除されずに残ってしまう。
    #   必ず destroy_all を実行してから、新しい設定を保存する。
    habit.habit_excluded_days.destroy_all

    # nil や空の場合はここで終了（= 除外日を全て解除した状態で完了）
    return if excluded_day_params.blank?

    # 文字列配列を整数配列に変換し、0〜6 の有効な値だけを残す
    day_numbers = Array(excluded_day_params)
                    .map(&:to_i)
                    .select { |d| d.between?(0, 6) }
                    .uniq

    day_numbers.each do |day|
      habit.habit_excluded_days.create!(day_of_week: day)
    end
  end

  # build_habit_stats（B-2: 除外日対応に更新）
  # チェック型の分母を effective_weekly_target（除外日考慮後）に変更する。
  #
  # 【B-2 での変更点】
  #   チェック型: 分母が weekly_target から effective_weekly_target に変わる
  #               例: 目標5日・除外土日 → 分母は min(5, 5) = 5
  #   数値型:     変更なし（分母は weekly_target のまま）
  #
  # 【N+1 対策】
  #   index アクションで includes(:habit_excluded_days) を付けているため、
  #   effective_weekly_target が habit_excluded_days.size を呼んでも
  #   追加のクエリは発生しない。
  def build_habit_stats(habits, user)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    check_habit_ids   = habits.select(&:check_type?).map(&:id)
    numeric_habit_ids = habits.select(&:numeric_type?).map(&:id)

    check_counts = if check_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: check_habit_ids, record_date: week_range, completed: true)
        .group(:habit_id)
        .count
    else
      {}
    end

    numeric_sums = if numeric_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: numeric_habit_ids, record_date: week_range, deleted_at: nil)
        .group(:habit_id)
        .sum(:numeric_value)
    else
      {}
    end

    habits.each_with_object({}) do |habit, hash|
      if habit.check_type?
        # 【B-2 変更】分母を effective_weekly_target に変更
        # effective_weekly_target = min(weekly_target, 7 - 除外日数)
        target          = habit.effective_weekly_target
        completed_count = check_counts[habit.id] || 0
        rate = target.zero? ? 0 :
          ((completed_count.to_f / target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: completed_count, numeric_sum: nil,
                           effective_target: target }
      else
        numeric_sum = (numeric_sums[habit.id] || 0).to_f
        rate = habit.weekly_target.zero? ? 0 :
          ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: nil, numeric_sum: numeric_sum,
                           effective_target: habit.weekly_target }
      end
    end
  end
end