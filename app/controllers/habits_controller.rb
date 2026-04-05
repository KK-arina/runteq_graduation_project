# app/controllers/habits_controller.rb
# （変更点のみ抜粋: sort アクション追加、habit_params に color/icon 追加）
#
# ==============================================================================
# HabitsController（B-6: カラー・アイコン・並び替え追加）
# ==============================================================================
#
# 【B-6 での変更内容】
#
#   ① sort アクションを新規追加（PATCH /habits/sort）
#      Drag & Drop 後に Stimulus が AJAX で呼び出すエンドポイント。
#      並び替え後の habit_ids 配列を受け取り、position を更新する。
#
#   ② habit_params に :color / :icon を追加
#      フォームから送られてくるカラーコードと絵文字アイコンを
#      Strong Parameters で許可する。
#
#   ③ require_unlocked の対象に :sort を追加
#      PDCAロック中は並び替えも制限する。
#
# ==============================================================================

class HabitsController < ApplicationController
  before_action :require_login
  before_action :require_unlocked, only: [ :create, :update, :destroy, :archive, :sort ]
  before_action :set_habit, only: [ :edit, :update, :destroy, :archive, :unarchive ]

  # ============================================================
  # GET /habits
  # ============================================================
  def index
    @habits = current_user.habits.active
                          .includes(:habit_excluded_days)
    # 注意: acts_as_list の scope :active に order(position ASC NULLS LAST) を
    # 追加したため、ここでの order 指定は不要になった。
    # モデルの scope :active が order を持っているので自動的に position 順になる。

    today = HabitRecord.today_for_record
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: today)
      .index_by(&:habit_id)

    @habit_stats = build_habit_stats(@habits, current_user)
    @locked      = locked?
  end

  # ============================================================
  # GET /habits/archived（変更なし）
  # ============================================================
  def archived
    @archived_habits = current_user.habits.archived
                                   .includes(:habit_excluded_days)
                                   .order(archived_at: :desc)
  end

  # ============================================================
  # GET /habits/new（変更なし）
  # ============================================================
  def new
    @habit = current_user.habits.build
  end

  # ============================================================
  # GET /habits/:id/edit（変更なし）
  # ============================================================
  def edit
  end

  # ============================================================
  # PATCH /habits/:id（変更なし）
  # ============================================================
  def update
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
    flash.now[:alert] = "習慣の更新に失敗しました"
    render :edit, status: :unprocessable_entity
  end

  # ============================================================
  # POST /habits（変更なし）
  # ============================================================
  def create
    @habit = current_user.habits.build(habit_params)

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
    flash.now[:alert] = "習慣の登録に失敗しました"
    render :new, status: :unprocessable_entity
  end

  # ============================================================
  # DELETE /habits/:id（変更なし）
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
  # POST /habits/:id/archive（変更なし）
  # ============================================================
  def archive
    @habit.archive!
    flash[:notice] = "「#{@habit.name}」をアーカイブしました"
    redirect_to habits_path, status: :see_other
  rescue ActiveRecord::RecordInvalid
    flash[:alert] = "アーカイブに失敗しました"
    redirect_to habits_path, status: :see_other
  end

  # ============================================================
  # PATCH /habits/:id/unarchive（変更なし）
  # ============================================================
  def unarchive
    @habit.unarchive!
    flash[:notice] = "「#{@habit.name}」を復元しました"
    redirect_to archived_habits_path, status: :see_other
  rescue RuntimeError => e
    flash[:alert] = e.message
    redirect_to archived_habits_path, status: :see_other
  rescue ActiveRecord::RecordInvalid
    flash[:alert] = "復元に失敗しました"
    redirect_to archived_habits_path, status: :see_other
  end

  # ============================================================
  # PATCH /habits/sort（B-6 新規追加）
  # ============================================================
  # 【役割】
  #   Drag & Drop 後に Stimulus（habit_sort_controller.js）が
  #   AJAX（fetch）で呼び出すエンドポイント。
  #   ドラッグ後の習慣ID配列を受け取り、その順番で position を更新する。
  #
  # 【HTTP メソッドを PATCH にする理由】
  #   並び替えは「既存リソースの部分的な更新」なので PATCH が適切。
  #   POST（新規作成）でも DELETE（削除）でもない。
  #
  # 【params[:habit_ids] の構造】
  #   Stimulus から送られてくる JSON:
  #     { "habit_ids": ["3", "1", "2"] }
  #   habit_ids は並び替え後の表示順（先頭から順）の ID 配列。
  #
  # 【each_with_index で position を更新する理由】
  #   配列のインデックス（0始まり）に +1 した値を position にする。
  #   例: ["3","1","2"] → habit_id=3 の position=1、id=1 は position=2...
  #   acts_as_list は 1 始まりの連番を前提としているため +1 する。
  #
  # 【update_column を使う理由】
  #   update_column は:
  #     ① バリデーションをスキップする（position 変更だけのためバリデーション不要）
  #     ② updated_at を更新しない（並び替えを「更新」として扱わないため）
  #     ③ コールバックをスキップする（高速化）
  #   並び替えは頻繁に呼ばれる可能性があるため、軽量な update_column が適切。
  #
  # 【セキュリティ: current_user で絞り込む理由】
  #   他のユーザーの習慣 ID が habit_ids に混入しても
  #   current_user.habits.find_by(id:) は nil を返すため安全。
  #   他ユーザーの position は絶対に変更されない。
  #
  # 【head :ok を返す理由】
  #   Stimulus（fetch）は成功したかどうかだけを確認したい。
  #   レスポンスボディは不要なので head :ok（ボディなし 200 OK）を返す。
  def sort
    # params[:habit_ids] は "3", "1", "2" のような文字列配列。
    # Array() でラップして nil の場合も安全に空配列にする。
    habit_ids = Array(params[:habit_ids])

    habit_ids.each_with_index do |habit_id, index|
      # current_user.habits で絞り込むことで、
      # 他ユーザーの習慣 ID が混入しても無視される（セキュリティ対策）。
      habit = current_user.habits.find_by(id: habit_id)

      # find_by は見つからなければ nil を返す。
      # nil チェック（next）で存在しない ID を安全にスキップする。
      next unless habit

      # insert_at を使って position を更新する。
      # acts_as_list の insert_at(n) は 1 始まりで position を設定する。
      # index は 0 始まりなので +1 して 1 始まりに変換する。
      habit.insert_at(index + 1)
    end

    # ボディなし 200 OK を返す。
    # Stimulus の fetch 呼び出しは response.ok（true/false）だけを確認する。
    head :ok
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # habit_params（B-6 変更: :color / :icon を追加）
  # 【理由】
  #   フォームから送られてくる color（カラーコード）と
  #   icon（絵文字）を Strong Parameters で許可する。
  #   Strong Parameters は「許可したパラメータ以外は無視する」Rails のセキュリティ機能。
  #   .permit に追加しないとフォームから値が送られても保存されない。
  def habit_params
    params.require(:habit).permit(:name, :weekly_target, :measurement_type, :unit, :color, :icon)
  end

  def set_habit
    @habit = current_user.habits.where(deleted_at: nil).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end

  def save_excluded_days!(habit, excluded_day_params)
    habit.habit_excluded_days.destroy_all
    return if excluded_day_params.blank?
    day_numbers = Array(excluded_day_params)
                    .map(&:to_i)
                    .select { |d| d.between?(0, 6) }
                    .uniq
    day_numbers.each do |day|
      habit.habit_excluded_days.create!(day_of_week: day)
    end
  end

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