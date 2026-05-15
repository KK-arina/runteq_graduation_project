# app/controllers/weekly_reflections_controller.rb
#
# ==============================================================================
# WeeklyReflectionsController
# ==============================================================================
# 【変更履歴】
#   D-5: create アクションに危機介入（crisis_detected）分岐を追加
#   D-6: create アクションに AI コスト上限チェックを追加
#        ・上限に達している場合は flash.now[:ai_limit] = true をセットして
#          render :new を実行する（redirect_to ではなく render を使う理由は後述）
#        ・complete_without_ai アクションを新規追加
#          → 振り返りを保存してロック解除するが AI 分析ジョブはエンキューしない
#   E-1: weekly_reflection_params と complete_without_ai_params に :mood を追加
#        mood は気分スコア（1〜5）。フォームの hidden input または
#        星評価UIから送られてくる整数値。
#
# 【D-6 の最重要設計ポイント: render vs redirect_to】
#   NG: redirect_to new_weekly_reflection_path
#     → ユーザーが書いた「振り返りコメント」「なぜ？」等のテキストがすべて消える
#     → 書き直しを強いられるため UX が最悪になる
#
#   OK: render :new, status: :unprocessable_entity
#     → @weekly_reflection のインスタンス変数が保持されるため、
#       フォームに入力済みの内容がそのまま残る
#     → モーダルだけが浮かび上がり、ユーザーは選択するだけでよい
#
# 【flash.now vs flash の使い分け】
#   flash      : 次のリクエスト（リダイレクト先）まで保持される
#   flash.now  : 現在のリクエスト内（render したビュー）だけで有効
#   render :new のときは flash.now を使う。flash を使うと
#   次のページ遷移でも表示されてしまい、モーダルが二重に起動する。
# ==============================================================================

class WeeklyReflectionsController < ApplicationController
  before_action :require_login
  before_action :set_weekly_reflection, only: [:show]

  # ── D-10 追加: AI API レート制限（連打防止）────────────────────────────
  #
  # 【only: [:create] にする理由】
  #   create アクションのみが AI 分析ジョブを投入する。
  #   complete_without_ai は AI を使わないため throttle 不要。
  #   show / index / new にも throttle は不要。
  #
  # 【throttle_ai_request は ApplicationController に定義】
  #   全コントローラーで再利用可能にするため親クラスに配置している。
  # ──────────────────────────────────────────────────────────────────────
  before_action :throttle_ai_request, only: [:create]

  def index
    @weekly_reflections = current_user.weekly_reflections
                                      .completed
                                      .recent
                                      .includes(:habit_summaries)

    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)
    @habits = current_user.habits.active.includes(:habit_excluded_days)
    @habit_stats = build_habit_stats(@habits, current_user)

    # ── E-3 追加: AI提案モーダル用の変数をセットする ─────────────────────────
    #
    # @latest_reflection:
    #   直近の完了済み振り返りレコード。
    #   _ai_proposal_modal_content.html.erb の hidden_field_tag に渡すため別変数で保持する。
    #
    # @latest_ai_analysis:
    #   @latest_reflection に紐付く最新の AI 分析結果。
    #   actions_json が nil のもの（crisis スキップ・パース失敗）は除外する。
    #
    # @current_purpose:
    #   PMVV との整合性表示に使う現在有効な UserPurpose。
    #   nil の場合（PMVV 未設定）は整合性セクションを非表示にする。
    @latest_reflection = @weekly_reflections.first

    if @latest_reflection
      @latest_ai_analysis = @latest_reflection
                              .ai_analyses
                              .latest
                              .where.not(actions_json: nil)
                              .first
    end

    @current_purpose = UserPurpose.current_for(current_user)
    # ────────────────────────────────────────────────────────────────────────
  end

  def new
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    @habits = current_user.habits.active.includes(:habit_excluded_days)
    @habit_stats = build_habit_stats(@habits, current_user)
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

  # ============================================================
  # create アクション（D-6: AI コスト上限チェックを追加）
  # ============================================================
  def create
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    # フォームの入力値を @weekly_reflection にセットする。
    # assign_attributes を先に実行することで、AI上限チェックで
    # render :new になった場合もフォームの入力内容が残る。
    @weekly_reflection.assign_attributes(weekly_reflection_params)

    # ── D-6 追加: AI コスト上限チェック ──────────────────────────────────────
    #
    # 【flash.now を使う理由】
    #   render :new（リダイレクトなし）でビューを描画するため、
    #   flash.now で「このリクエスト内だけ有効」なフラグを立てる。
    #   flash を使うと次のリクエストでもフラグが残りモーダルが二重起動する。
    if ai_limit_exceeded?
      flash.now[:ai_limit] = true
      setup_new_form_variables
      render :new, status: :unprocessable_entity
      return
    end
    # ────────────────────────────────────────────────────────────────────────────

    was_locked = current_user.locked?

    result = WeeklyReflectionCompleteService.new(
      reflection:  @weekly_reflection,
      user:        current_user,
      was_locked:  was_locked,
      corrections: params[:reflection_numeric_corrections]
    ).call

    if result[:success]
      current_user.reload

      # ── D-5: 危機ワード検出時の分岐（変更なし）──────────────────────────
      if result[:crisis_detected]
        Rails.logger.warn "[WeeklyReflectionsController] 危機ワード検出: user_id=#{current_user.id}"
        flash[:crisis] = true

        if was_locked
          flash[:unlock] = "振り返りが完了しました。PDCAロックが解除されました。🔓"
          redirect_to dashboard_path
        else
          redirect_to weekly_reflections_path
        end
        return
      end
      # ────────────────────────────────────────────────────────────────────────

      if was_locked
        flash[:unlock] = "振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！🔓"
        redirect_to dashboard_path
      else
        redirect_to weekly_reflections_path,
                    notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
      end
    else
      Rails.logger.error "WeeklyReflectionCompleteService failed: #{result[:error]}"
      setup_new_form_variables
      flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # complete_without_ai アクション（D-6 新規追加）
  # ============================================================
  def complete_without_ai
    @weekly_reflection = find_pending_last_week_reflection ||
                        WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to weekly_reflections_path, notice: "振り返りは既に完了しています。"
      return
    end

    @weekly_reflection.assign_attributes(complete_without_ai_params)
    was_locked = current_user.locked?

    result = WeeklyReflectionCompleteService.new(
      reflection:  @weekly_reflection,
      user:        current_user,
      was_locked:  was_locked,
      corrections: params[:reflection_numeric_corrections]
    ).call

    if result[:success]
      current_user.reload

      if result[:crisis_detected]
        flash[:crisis] = true
        if was_locked
          flash[:unlock] = "振り返りが完了しました。PDCAロックが解除されました。🔓"
          redirect_to dashboard_path
        else
          redirect_to weekly_reflections_path
        end
        return
      end

      if was_locked
        flash[:unlock] = "振り返りが完了しました！PDCAロックが解除されました。（今月のAI分析回数の上限に達したため、AI分析はスキップされました）🔓"
        redirect_to dashboard_path
      else
        redirect_to weekly_reflections_path,
                    notice: "今週の振り返りを保存しました！（AI分析はスキップされました）お疲れ様でした🎉"
      end
    else
      Rails.logger.error "WeeklyReflectionCompleteService (without AI) failed: #{result[:error]}"
      setup_new_form_variables
      flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
      render :new, status: :unprocessable_entity
    end
  end

  def confirm_proposals
    reflection = current_user.weekly_reflections.find(params[:reflection_id])

    unless reflection.completed?
      redirect_to weekly_reflections_path, alert: "この振り返りはまだ完了していません。"
      return
    end

    # ── 二重送信防止チェック（修正版）────────────────────────────────────
    #
    # 【変更前の問題】
    #   「週の範囲に ai_generated タスクが存在するか」で判定していたため、
    #   目標管理（user_purposes#apply_proposals）から登録した ai_generated タスクも
    #   「確定済み」と誤判定してしまい、振り返りからの確定ができなくなっていた。
    #
    # 【変更後の設計】
    #   この振り返りに紐付く AiAnalysis の actions_json から生成されたタスクが
    #   既に存在するかを判定する。
    #   具体的には「この AiAnalysis が作成された時刻以降に作成された
    #   ai_generated タスクが存在するか」で判定する。
    #   AiAnalysis の created_at を基準にすることで、目標管理からの登録と
    #   振り返りからの登録を区別できる。
    ai_analysis = reflection.ai_analyses.latest.where.not(actions_json: nil).first

    unless ai_analysis&.actions_json.present?
      redirect_to weekly_reflections_path,
                  alert: "AI分析結果が見つかりませんでした。分析完了後に再度お試しください。"
      return
    end

    # ai_analysis が作成されてから確定ボタンを押すまでの間に
    # 同じユーザーが ai_generated タスクを作成していれば「確定済み」とみなす。
    # ai_analysis.created_at を基準にすることで目標管理からの登録と区別する。
    already_confirmed = current_user.tasks
                                    .where(ai_generated: true, task_type: :improve)
                                    .where('created_at > ?', ai_analysis.created_at)
                                    .exists?

    if already_confirmed
      Rails.logger.info "[WeeklyReflectionsController#confirm_proposals] 二重送信を検知: reflection_id=#{reflection.id}"
      redirect_to dashboard_path, notice: "来週の計画は既に確定済みです。"
      return
    end

    # ── インデックスから提案を特定する ────────────────────────────────────
    habit_indices = Array(params[:habit_indices]).map(&:to_i)
    task_indices  = Array(params[:task_indices]).map(&:to_i)

    all_actions   = ai_analysis.actions_json.map { |a| a.with_indifferent_access }
    habit_actions = all_actions.select { |a| a[:type] == "habit" }
    task_actions  = all_actions.select { |a| a[:type] == "task" }

    saved_habit_count = 0
    saved_task_count  = 0

    ApplicationRecord.transaction do
      if reflection.is_locked?
        reflection.update!(is_locked: false)
        Rails.logger.info "[WeeklyReflectionsController#confirm_proposals] is_locked を false に更新: reflection_id=#{reflection.id}"
      end

      habit_indices.each do |idx|
        proposal = habit_actions[idx]
        next unless proposal
        weekly_target = parse_frequency_to_weekly_target(proposal[:frequency])
        habit = current_user.habits.build(
          name:             proposal[:title].to_s.truncate(50),
          weekly_target:    weekly_target,
          measurement_type: :check_type
        )
        habit.save!
        saved_habit_count += 1
      end

      task_indices.each do |idx|
        proposal = task_actions[idx]
        next unless proposal
        priority = %w[must should could].include?(proposal[:priority].to_s.downcase) ?
                     proposal[:priority].to_s.downcase : "should"
        task = current_user.tasks.build(
          title:        proposal[:title].to_s.truncate(100),
          priority:     priority,
          task_type:    :improve,
          ai_generated: true,
          status:       :todo
        )
        task.save!
        saved_task_count += 1
      end
    end

    total = saved_habit_count + saved_task_count
    flash[:notice] = total > 0 ?
      "来週の計画を確定しました！習慣#{saved_habit_count}件・タスク#{saved_task_count}件を追加しました🎉" :
      "来週の計画を確定しました！（提案の選択なし）"

    redirect_to dashboard_path

  rescue ActiveRecord::RecordNotFound
    redirect_to weekly_reflections_path, alert: "振り返りが見つかりませんでした。"

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[WeeklyReflectionsController#confirm_proposals] RecordInvalid: #{e.message}"
    redirect_to weekly_reflections_path, alert: "保存中にエラーが発生しました。再試行してください。"
  end

  def show
    @habit_summaries = @weekly_reflection.habit_summaries
                                         .order(achievement_rate: :desc)
                                         .to_a
    @task_summaries  = @weekly_reflection.task_summaries
                                         .by_priority
                                         .to_a
    @overall_achievement_rate = calculate_overall_achievement_rate
  end

  private

  # complete_without_ai 専用のパラメータ取得メソッド
  # モーダルのフォームは weekly_reflection[] なしで送信されるため
  # weekly_reflection_params とは別に定義する
  def complete_without_ai_params
    # params に weekly_reflection キーがある場合（通常フォームからの送信）
    if params[:weekly_reflection].present?
      weekly_reflection_params
    else
      # モーダルの hidden フィールドからの送信（フラットなパラメータ）
      params.permit(
        :reflection_comment,
        :direct_reason,
        :background_situation,
        :next_action,
        # ── E-1 追加: mood を permit に追加 ─────────────────────────────────
        # AI なしルートでも気分スコアを保存できるようにする。
        # permit しないと mood の値は Strong Parameters にブロックされて保存されない。
        :mood
        # ───────────────────────────────────────────────────────────────────
      )
    end
  end

  # setup_new_form_variables（D-6 新規追加）
  # new ビューのレンダリングに必要な変数を一括セットする。
  # create と complete_without_ai の両方で render :new する際に使う（DRY化）。
  def setup_new_form_variables
    @habits = current_user.habits.active.includes(:habit_excluded_days)
    @habit_stats = build_habit_stats(@habits, current_user)
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

  def calculate_overall_achievement_rate
    return 0 if @habit_summaries.empty?
    (@habit_summaries.map(&:achievement_rate).sum / @habit_summaries.size.to_f).round(1)
  end

  def set_weekly_reflection
    @weekly_reflection = current_user.weekly_reflections.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to weekly_reflections_path, alert: "振り返りが見つかりませんでした。"
  end

  def weekly_reflection_params
    # ── E-1 変更: :mood を permit リストに追加 ────────────────────────────────
    #
    # 【Strong Parameters とは】
    #   Rails のセキュリティ機能。フォームから送られてくるパラメータのうち、
    #   ここで明示的に permit（許可）したものだけをモデルに渡す。
    #   permit しないパラメータは自動的に無視される。
    #
    # 【:mood を追加する理由】
    #   E-1 で気分スコア入力フォームを追加するため、
    #   フォームから送られてくる :mood パラメータを許可する必要がある。
    #   permit しないと「Unpermitted parameter: mood」という警告が出て
    #   値が保存されない。
    params.require(:weekly_reflection).permit(
      :reflection_comment,
      :direct_reason,
      :background_situation,
      :next_action,
      :mood           # E-1 追加: 気分スコア（1〜5の整数）
    )
    # ────────────────────────────────────────────────────────────────────────────
  end

  def find_pending_last_week_reflection
    current_week = WeeklyReflection.current_week_start_date
    last_week    = current_week - 7.days
    current_user.weekly_reflections
                .pending
                .find_by(week_start_date: last_week)
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

  # ── E-3 修正: parse_frequency_to_weekly_target ────────────────────────────
  #
  # 【修正内容】
  #   デフォルト値を 5 → 7 に変更する。
  #
  # 【変更理由】
  #   習慣の新規登録フォームでは check_type のデフォルトが weekly_target: 7（毎日）。
  #   AI提案から登録される習慣も同じ基準に合わせる。
  #   frequency が "毎日" 以外の場合（"週N回" 以外の不明な文字列）も
  #   7（毎日）をデフォルトにすることで、ユーザーが後で減らす方向で調整できる。
  #   「5日のつもりが7日になった」より
  #   「7日のつもりが5日になった」の方が困らないという UX 判断。
  #
  # 【変換ルール】
  #   "毎日"   → 7
  #   "週N回"  → N（1〜7 の範囲に clamp）
  #   それ以外 → 7（変更: 5 → 7）
  def parse_frequency_to_weekly_target(frequency)
    return 7 if frequency.blank?  # 変更: 5 → 7

    freq_str = frequency.to_s
    return 7 if freq_str.include?("毎日")

    # "週N回" のパターンから数値を抽出する
    # /週(\d+)回/ : "週" の後の数字を capture group で取得する
    if freq_str =~ /週(\d+)回/
      $1.to_i.clamp(1, 7)
    else
      7  # 変更: 5 → 7（"週N回" 以外の不明なパターンも毎日をデフォルトにする）
    end
  end
end
