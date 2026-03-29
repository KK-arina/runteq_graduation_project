# app/controllers/habits_controller.rb
#
# ==============================================================================
# HabitsController（B-4: アーカイブ機能追加）
# ==============================================================================
#
# 【B-4 での変更内容】
#
#   ① before_action :set_habit のみ対象アクションに :archive / :unarchive を追加
#      理由: archive / unarchive アクションでも @habit を事前にセットする必要がある。
#
#   ② require_unlocked の対象に :archive を追加
#      理由: PDCAロック中はアーカイブ（= 習慣の状態変更）もできないようにする。
#            unarchive（復元）はロック中でも許可する。
#            「復元」はアクティブな習慣を増やす操作であり、
#            「削除・追加」とは性質が異なるが、
#            シンプルな設計として ISSUEリストの方針（ロック中は変更不可）に従う。
#            ※ 要件に応じて unarchive をロック不要にする変更も容易。
#
#   ③ archive アクション（POST /habits/:id/archive）を新規追加
#      対象習慣の archived_at に現在時刻をセットしてアーカイブする。
#
#   ④ unarchive アクション（PATCH /habits/:id/unarchive）を新規追加
#      archived_at を nil に戻してアクティブ状態に復元する。
#
#   ⑤ archived アクション（GET /habits/archived）を新規追加
#      アーカイブ済み習慣の一覧を表示する（8-2番画面）。
#
#   ⑥ set_habit を修正
#      修正前: current_user.habits.active.find(params[:id])
#      修正後: current_user.habits.find(params[:id])
#      理由: archive / unarchive は active でも archived でもどちらの状態の習慣も
#            操作対象になり得るため、スコープを外した状態で検索する。
#            セキュリティは current_user. で絞り込む（他ユーザーの習慣は取得不可）。
#
# ==============================================================================

class HabitsController < ApplicationController
  before_action :require_login

  # require_unlocked の対象アクション（B-4 修正: :archive を追加）
  # 【理由】
  #   PDCAロック中は :create / :update / :destroy に加えて :archive も禁止する。
  #   :unarchive（復元）はロック対象外とする（アクティブ習慣を増やす操作のため）。
  before_action :require_unlocked, only: [ :create, :update, :destroy, :archive ]

  # set_habit を対象とするアクション（B-4 修正: :archive / :unarchive を追加）
  # 【理由】
  #   archive・unarchive アクションでも @habit.id でアーカイブ対象を特定するため。
  before_action :set_habit, only: [ :edit, :update, :destroy, :archive, :unarchive ]

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
  # GET /habits/archived（B-4 新規追加）
  # ============================================================
  # 【役割】
  #   8-2. 習慣アーカイブ一覧ページを表示する。
  #
  # 【scope :archived の利用】
  #   Habit モデルに定義した scope :archived を使うことで
  #   deleted_at: nil かつ archived_at が設定されている習慣だけを取得できる。
  #
  # 【order(archived_at: :desc)】
  #   最近アーカイブした習慣から順に表示する（新しいものが上）。
  #
  # 【includes(:habit_excluded_days)】
  #   アーカイブ一覧でも effective_weekly_target を使う可能性があるため
  #   N+1 対策として先読みする。

  def archived
    @archived_habits = current_user.habits.archived
                                   .includes(:habit_excluded_days)
                                   .order(archived_at: :desc)
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
  end

  # ============================================================
  # PATCH /habits/:id
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
  # POST /habits
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
  # POST /habits/:id/archive（B-4 新規追加）
  # ============================================================
  # 【役割】
  #   習慣を「卒業アーカイブ」状態にする。
  #   archived_at に現在時刻をセットする。
  #
  # 【HTTP メソッドを POST にする理由】
  #   アーカイブはリソースの「状態変更」であり、
  #   GET（参照）でも DELETE（削除）でもない。
  #   Rails の慣例として「状態変更」には POST または PATCH を使う。
  #   今回は既存リソースへの部分的な変更なので PATCH でも良いが、
  #   ルーティングでは member do ... end 内で post :archive を使うことが多い。
  #
  # 【status: :see_other（303）を使う理由】
  #   Turbo（Hotwire）では POST / PATCH / DELETE の後のリダイレクトに
  #   302 ではなく 303 See Other を使う必要がある。
  #   303 は「別の URL を GET で参照してください」という意味のステータスコードで、
  #   Turbo が正しくリダイレクト後のページを GET で取得するために必要。

  def archive
    @habit.archive!
    flash[:notice] = "「#{@habit.name}」をアーカイブしました"
    redirect_to habits_path, status: :see_other
  rescue ActiveRecord::RecordInvalid
    flash[:alert] = "アーカイブに失敗しました"
    redirect_to habits_path, status: :see_other
  end

  # ============================================================
  # PATCH /habits/:id/unarchive（B-4 新規追加）
  # ============================================================
  # 【役割】
  #   アーカイブを解除してアクティブ状態に復元する。
  #   archived_at を nil に戻す。
  #
  # 【require_unlocked の対象外にした理由】
  #   復元（unarchive）は「アクティブな習慣を増やす」操作だが、
  #   PDCAロック中に習慣を「追加」するのと同等と見なせる場合は
  #   ロック対象に含めることも検討できる。
  #   今回は設計の一貫性よりも「卒業した習慣を間違えてアーカイブしてしまった場合に
  #   すぐ戻せる」というUXを優先して、ロック対象外にしている。

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
  # Private メソッド
  # ============================================================
  private

  def habit_params
    params.require(:habit).permit(:name, :weekly_target, :measurement_type, :unit)
  end

  # set_habit（B-4 修正・再修正）
  # ==============================================================================
  # 【変更履歴】
  #   MVP版:  current_user.habits.active.find(params[:id])
  #           → active スコープ（deleted_at: nil, archived_at: nil）で検索
  #
  #   B-4 初版: current_user.habits.find(params[:id])
  #           → スコープなしに変更（archive / unarchive 対応のため）
  #           → 問題: 論理削除済み習慣も find できてしまい、
  #                   「削除済み習慣は再削除できない」テストが失敗した
  #
  #   B-4 再修正: current_user.habits.where(deleted_at: nil).find(params[:id])
  #           → deleted_at が nil のもの（削除されていない習慣）だけを対象にする
  #           → archived_at は問わない
  #             （アーカイブ済み・アクティブの両方を操作できるようにする）
  #
  # 【この設計の意図】
  #   習慣の状態は3種類ある:
  #     1. アクティブ:     deleted_at = nil, archived_at = nil
  #     2. アーカイブ済み: deleted_at = nil, archived_at = 設定済み
  #     3. 削除済み:       deleted_at = 設定済み
  #
  #   set_habit が取得すべき対象:
  #     ・edit / update:   1 のみ（アクティブ）※ destroy も実質 1 のみ
  #     ・archive:         1 のみ（アクティブを archive する）
  #     ・unarchive:       2 のみ（アーカイブ済みを戻す）
  #
  #   1 と 2 はどちらも deleted_at = nil なので、
  #   「deleted_at: nil で絞り込む」だけで両方カバーできる。
  #   3（削除済み）は find 対象から外れるため、
  #   削除済み習慣への操作は RecordNotFound → habits_path へリダイレクト される。
  # ==============================================================================

  def set_habit
    # where(deleted_at: nil) で削除済み習慣を除外する。
    # archived_at は条件に含めない（アーカイブ済み習慣も操作対象のため）。
    # current_user. で絞り込むことで他ユーザーの習慣は取得不可（セキュリティ）。
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