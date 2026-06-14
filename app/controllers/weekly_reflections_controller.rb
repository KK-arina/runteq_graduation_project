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

# 【G-9 での変更内容】
#   confirm_proposals に以下の4種類の新 type の処理を追加:
#     - "habit_modify"  : 習慣の weekly_target 等を更新
#     - "habit_delete"  : 習慣を論理削除（archived_at を設定）
#     - "task_modify"   : タスクの priority 等を更新
#     - "goal_review"   : DBへの変更なし（ユーザーをPMVVページへ誘導するのみ）
#
#   【既存の "habit" / "task" type の処理は変更しない（後方互換性）】
#     G-9 完了条件「既存の "habit" / "task" type の動作が変わらない」を満たすため。
#
#   【マッチング戦略：名前の完全一致】
#     habit_name / task_title で既存レコードを検索する。
#     マッチしない場合はスキップ（エラーにしない）。
#     理由: AIが若干異なる名前を返す可能性があり、その場合もアプリをクラッシュさせない。
#
#   【トランザクション境界】
#     既存の transaction ブロック内に全処理を含める（A-7 トランザクション原則）。
#     habit_modify / habit_delete / task_modify を transaction で包むことで、
#     途中でエラーが起きても中途半端な状態にならない。

  def confirm_proposals
    reflection = current_user.weekly_reflections.find(params[:reflection_id])

    unless reflection.completed?
      redirect_to weekly_reflections_path, alert: "この振り返りはまだ完了していません。"
      return
    end

    # 二重送信防止チェック（変更なし）
    ai_analysis = reflection.ai_analyses.latest.where.not(actions_json: nil).first

    unless ai_analysis&.actions_json.present?
      redirect_to weekly_reflections_path,
                  alert: "AI分析結果が見つかりませんでした。分析完了後に再度お試しください。"
      return
    end

    already_confirmed = current_user.tasks
                                    .where(ai_generated: true, task_type: :improve)
                                    .where('created_at > ?', ai_analysis.created_at)
                                    .exists?

    if already_confirmed
      Rails.logger.info "[WeeklyReflectionsController#confirm_proposals] 二重送信を検知: reflection_id=#{reflection.id}"
      redirect_to dashboard_path, notice: "来週の計画は既に確定済みです。"
      return
    end

    # インデックスから提案を特定する
    habit_indices        = Array(params[:habit_indices]).map(&:to_i)
    task_indices         = Array(params[:task_indices]).map(&:to_i)
    # ── G-9 追加: 新 type 用のインデックスを受け取る ────────────────────
    habit_modify_indices = Array(params[:habit_modify_indices]).map(&:to_i)
    habit_delete_indices = Array(params[:habit_delete_indices]).map(&:to_i)
    task_modify_indices  = Array(params[:task_modify_indices]).map(&:to_i)
    # goal_review は DB変更なし・インデックス不要（リンクで遷移するだけ）
    # ──────────────────────────────────────────────────────────────────────

    all_actions   = ai_analysis.actions_json.map { |a| a.with_indifferent_access }

    # 既存 type（後方互換性のため変更なし）
    habit_actions = all_actions.select { |a| a[:type] == "habit" }
    task_actions  = all_actions.select { |a| a[:type] == "task" }

    # ── G-9 追加: 新 type 別に配列を分ける ───────────────────────────────
    #
    # 【なぜ type ごとに別配列にするのか】
    #   各 type はそれぞれ異なる DB 操作を行うため、
    #   個別の配列で管理することでコードが明確になる。
    #   also_actions.select { |a| a[:type] == "habit_modify" } で
    #   habit_modify のものだけを取り出す。
    habit_modify_actions = all_actions.select { |a| a[:type] == "habit_modify" }
    habit_delete_actions = all_actions.select { |a| a[:type] == "habit_delete" }
    task_modify_actions  = all_actions.select { |a| a[:type] == "task_modify" }
    # goal_review は表示だけ（DBへの変更なし）なので確定時の処理は不要
    # ──────────────────────────────────────────────────────────────────────

    saved_habit_count        = 0
    saved_task_count         = 0
    # ── G-9 追加: 変更件数カウンター ────────────────────────────────────
    modified_habit_count     = 0
    deleted_habit_count      = 0
    modified_task_count      = 0
    # ──────────────────────────────────────────────────────────────────────

    goal_review_requested = params[:goal_review_requested] == "1"

    ApplicationRecord.transaction do
      if reflection.is_locked?
        reflection.update!(is_locked: false)
        Rails.logger.info "[WeeklyReflectionsController#confirm_proposals] is_locked を false に更新: reflection_id=#{reflection.id}"
      end

      # ── 既存: 新規習慣の追加（変更なし）──────────────────────────────
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

      # ── 既存: 新規タスクの追加（変更なし）──────────────────────────────
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

      # ── G-9 追加: 既存習慣の修正（habit_modify）──────────────────────
      #
      # 【処理の流れ】
      #   1. habit_modify_indices からチェックされた提案を取得する
      #   2. proposal[:habit_name] で現在のユーザーの習慣を名前検索する
      #   3. マッチした場合: proposal[:changes] の内容で update する
      #   4. マッチしない場合: スキップ（エラーにしない）
      #
      # 【なぜ find_by を使うのか】
      #   find だとマッチしない場合に RecordNotFound 例外が発生してロールバックする。
      #   スキップしたい場合は find_by（マッチしない場合は nil を返す）が適切。
      habit_modify_indices.each do |idx|
        proposal = habit_modify_actions[idx]
        next unless proposal

        habit_name = proposal[:habit_name].to_s.strip
        next if habit_name.blank?

        # 【完全一致で検索する理由】
        #   AIがプロンプトで「完全一致させてください」と指示しているため。
        #   部分一致（LIKE検索）だと意図しない習慣を修正してしまうリスクがある。
        habit = current_user.habits.active.find_by(name: habit_name)
        if habit.nil?
          Rails.logger.warn "[WeeklyReflectionsController#confirm_proposals] habit_modify: 習慣が見つかりません: #{habit_name}"
          next
        end

        changes = proposal[:changes].to_h.with_indifferent_access

        # 【更新可能なフィールドをホワイトリスト管理する理由】
        #   AIが返す changes は自由なキーを含む可能性があるため、
        #   意図しないカラムを更新しないようホワイトリストで制限する。
        update_attrs = {}
        if changes[:weekly_target].present?
          wt = changes[:weekly_target].to_i
          # 1〜7 の範囲に clamp して不正な値を防ぐ
          update_attrs[:weekly_target] = wt.clamp(1, 7)
        end

        next if update_attrs.empty?

        habit.update!(update_attrs)
        modified_habit_count += 1
        Rails.logger.info "[WeeklyReflectionsController#confirm_proposals] habit_modify 適用: #{habit_name} → #{update_attrs.inspect}"
      end

      # ── G-9 追加: 既存習慣の削除（habit_delete）──────────────────────
      #
      # 【論理削除（soft_delete）を使う理由】
      #   物理削除すると「過去の記録」も消えてしまう。
      #   deleted_at を設定する論理削除なら過去データが残り、
      #   振り返り詳細ページでも正確な記録が表示できる。
      #
      # 【アーカイブ（archive!）ではなく soft_delete を使う理由】
      #   ISSUEリスト G-9 に「習慣の削除提案」と記載されており、
      #   「卒業した習慣→アーカイブ」ではなく「不要な習慣→削除」の操作として実装する。
      #   AIが判断した「削除すべき習慣」はユーザーが確認してチェックしてから実行するため
      #   誤操作リスクは低いが、soft_delete（deleted_at設定）にすることで
      #   万が一の場合にもDBからデータが残る。
      habit_delete_indices.each do |idx|
        proposal = habit_delete_actions[idx]
        next unless proposal

        habit_name = proposal[:habit_name].to_s.strip
        next if habit_name.blank?

        habit = current_user.habits.active.find_by(name: habit_name)
        if habit.nil?
          Rails.logger.warn "[WeeklyReflectionsController#confirm_proposals] habit_delete: 習慣が見つかりません: #{habit_name}"
          next
        end

        habit.soft_delete
        deleted_habit_count += 1
        Rails.logger.info "[WeeklyReflectionsController#confirm_proposals] habit_delete 適用: #{habit_name}"
      end

      # ── G-9 追加: 既存タスクの修正（task_modify）────────────────────
      #
      # 【処理の流れ】
      #   1. task_modify_indices からチェックされた提案を取得する
      #   2. proposal[:task_title] で現在のユーザーのタスクを名前検索する
      #   3. マッチした場合: proposal[:changes] の内容で update する
      #   4. マッチしない場合: スキップ
      task_modify_indices.each do |idx|
        proposal = task_modify_actions[idx]
        next unless proposal

        task_title = proposal[:task_title].to_s.strip
        next if task_title.blank?

        task = current_user.tasks.active.not_archived.find_by(title: task_title)
        if task.nil?
          Rails.logger.warn "[WeeklyReflectionsController#confirm_proposals] task_modify: タスクが見つかりません: #{task_title}"
          next
        end

        changes = proposal[:changes].to_h.with_indifferent_access

        # priority の変更のみ許可（ホワイトリスト）
        # 【なぜ priority だけなのか】
        #   ISSUEリスト G-9 の要件に「優先度等の変更」と記載されており、
        #   最初のリリースでは priority の変更のみをサポートする。
        #   due_date・estimated_hours 等の変更は将来の拡張で対応。
        update_attrs = {}
        if changes[:priority].present?
          new_priority = changes[:priority].to_s.downcase
          if %w[must should could].include?(new_priority)
            update_attrs[:priority] = new_priority
          end
        end

        next if update_attrs.empty?

        task.update!(update_attrs)
        modified_task_count += 1
        Rails.logger.info "[WeeklyReflectionsController#confirm_proposals] task_modify 適用: #{task_title} → #{update_attrs.inspect}"
      end

      # goal_review は DB 変更なし: ここでは何もしない
      # ユーザーは「目標管理ページへ」リンクから自分で遷移する
    end

    # ── フラッシュメッセージの組み立て ─────────────────────────────────
    #
    # 各操作の件数をまとめてユーザーにフィードバックする。
    # 何も操作しなかった場合でもロック解除は完了しているため
    # 「確定しました」メッセージを表示する。
    message_parts = []
    message_parts << "習慣#{saved_habit_count}件を追加"    if saved_habit_count > 0
    message_parts << "タスク#{saved_task_count}件を追加"   if saved_task_count > 0
    message_parts << "習慣#{modified_habit_count}件を修正" if modified_habit_count > 0
    message_parts << "習慣#{deleted_habit_count}件を削除"  if deleted_habit_count > 0
    message_parts << "タスク#{modified_task_count}件を修正" if modified_task_count > 0

    if message_parts.any?
      flash[:notice] = "来週の計画を確定しました！#{message_parts.join('・')}しました🎉"
    else
      flash[:notice] = "来週の計画を確定しました！（変更なし）"
    end

    # goal_review がリクエストされていた場合は目標管理ページへ誘導する
    # 【なぜ goal_review_requested フラグを使うのか】
    #   DB変更はないが「ユーザーがPMVV見直しを希望した」という意思を
    #   フォームの hidden_field で受け取る設計にする。
    #   goal_review チェック + 確定 → 確定後に user_purpose_path へリダイレクト
    if goal_review_requested
      redirect_to user_purpose_path, notice: flash[:notice] + " 目標の見直しをしましょう。"
    else
      redirect_to dashboard_path
    end

  rescue ActiveRecord::RecordNotFound
    redirect_to weekly_reflections_path, alert: "振り返りが見つかりませんでした。"

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[WeeklyReflectionsController#confirm_proposals] RecordInvalid: #{e.message}"
    redirect_to weekly_reflections_path, alert: "保存中にエラーが発生しました。再試行してください。"
  end

  def show
    # ─────────────────────────────────────────────────────────────────────
    # @habit_summaries:
    #   この振り返りに紐づく習慣スナップショットを達成率の高い順で取得する。
    #   order(achievement_rate: :desc) → 達成率が高い習慣から表示することで
    #   ユーザーが「今週うまくいった習慣」を先に確認できる。
    #   .to_a → ActiveRecord::Relation を配列に変換する。
    #   配列にしておくと、ビューで複数回参照するときに SQL が重複発行されない。
    # ─────────────────────────────────────────────────────────────────────
    @habit_summaries = @weekly_reflection.habit_summaries
                                         .order(achievement_rate: :desc)
                                         .to_a

    # ─────────────────────────────────────────────────────────────────────
    # @task_summaries:
    #   この振り返りに紐づくタスクスナップショットを優先度順で取得する。
    #   by_priority スコープ → must(0) → should(1) → could(2) の昇順。
    #   数値が小さい方が重要度が高い（Must が最優先）。
    #   .to_a → 配列に変換してビューでの N+1 を防ぐ。
    # ─────────────────────────────────────────────────────────────────────
    @task_summaries  = @weekly_reflection.task_summaries
                                         .by_priority
                                         .to_a

    # ─────────────────────────────────────────────────────────────────────
    # @overall_achievement_rate:
    #   全習慣の達成率の平均値（0〜100の小数）。
    #   セクション①の「今週の総合達成率」に使う。
    #   @habit_summaries.empty? の場合は 0 を返す（ゼロ除算防止）。
    # ─────────────────────────────────────────────────────────────────────
    @overall_achievement_rate = calculate_overall_achievement_rate

    # =========================================================================
    # @ai_analysis（E-5 追加）
    #
    # 【なぜ .latest スコープを使うのか】
    #   AiAnalysis モデルの scope :latest は is_latest: true のレコードのみを
    #   返す。before_create コールバック(deactivate_previous_analyses)が
    #   古い分析を is_latest: false に更新するため、常に最新の1件だけが
    #   is_latest: true になる設計になっている。
    #
    # 【なぜ .order(created_at: :desc) を追加するのか】
    #   .latest は「is_latest: true でフィルタする」だけのスコープであり、
    #   並び順を保証しない。理論上は1件しか存在しないが、ジョブの
    #   二重実行などで複数件になった場合に最新のものが取れるよう
    #   明示的に降順ソートを付加して安全を担保する。
    #
    # 【なぜ .where.not(analysis_comment: nil) を付けないのか】
    #   analysis_comment が nil = AI分析ジョブが処理中（待機状態）を意味する。
    #   ここで除外してしまうと待機中の状態を画面に表示できず、
    #   ユーザーには「何も起きていない」ように見える。
    #   nil か否かの判定はビュー側で行い、待機中UIと完了UIを出し分ける。
    # =========================================================================
    @ai_analysis = @weekly_reflection
                     .ai_analyses
                     .latest
                     .order(created_at: :desc)
                     .first

    # G-9 追加: AI提案モーダルに user_purpose を渡すために取得する
    # show ページに _ai_proposal_modal パーシャルを render するため必要。
    # nil でも問題ない（user_purpose が nil の場合は goal_review セクションが非表示になる）
    @current_purpose = UserPurpose.current_for(current_user)
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