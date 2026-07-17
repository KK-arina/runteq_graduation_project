# app/controllers/user_purposes_controller.rb
#
# 【D-5 での変更内容】
#   create / update アクションで crisis_word_detected? を確認し、
#   true の場合は PurposeAnalysisJob をスキップして
#   flash[:crisis] をセットして 16番ページにリダイレクトする。
#
# （他のアクションは変更なし。変更箇所のみ抜粋して示す）
# ==============================================================================

class UserPurposesController < ApplicationController
  before_action :require_login

  # ── D-10 追加: AI API レート制限（連打防止）────────────────────────────
  #
  # 【only: [:create, :update, :retry_analysis] にする理由】
  #   create / update: 新しい PMVV を保存して PurposeAnalysisJob を投入する
  #   retry_analysis:  「再試行する」ボタンから PurposeAnalysisJob を再投入する
  #   → この3アクションのみ AI 分析ジョブが発生するため throttle を適用する。
  #
  # 【show / edit / apply_proposals / ai_result には適用しない理由】
  #   これらのアクションは AI 分析ジョブを投入しない閲覧・後処理アクション。
  # ──────────────────────────────────────────────────────────────────────
  before_action :throttle_ai_request, only: [:create, :update, :retry_analysis]

  def show
    @current_purpose = UserPurpose.current_for(current_user)
    if @current_purpose
      @ai_analysis = AiAnalysis.where(
        user_purpose_id: @current_purpose.id,
        is_latest:       true,
        analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
      ).first
    end
    @past_purposes = current_user.user_purposes
                                 .where(is_active: false)
                                 .order(version: :desc)
  end

  def new
    @user_purpose = UserPurpose.new
  end

  def create
    @user_purpose = current_user.user_purposes.build(user_purpose_params)
    @user_purpose.analysis_state = :pending

    if @user_purpose.save
      # ── 古い UserPurpose を非アクティブ化する ────────────────────────────
      current_user.user_purposes
                  .where(is_active: true)
                  .where.not(id: @user_purpose.id)
                  .update_all(is_active: false)
      # ────────────────────────────────────────────────────────────────────────

      if @user_purpose.crisis_word_detected?
        Rails.logger.warn "[UserPurposesController#create] 危機ワード検出: user_id=#{current_user.id}"
        @user_purpose.update_columns(analysis_state: UserPurpose.analysis_states[:failed])
        record_crisis_analysis_for_purpose(@user_purpose)
        flash[:crisis] = true
        redirect_to user_purpose_path, notice: "目標を保存しました。"
        return
      end

      PurposeAnalysisJob.perform_later(@user_purpose.id)
      redirect_to user_purpose_path,
                  notice: "目標を保存しました。AIによる分析を開始しています..."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @user_purpose = UserPurpose.current_for(current_user)
    unless @user_purpose
      redirect_to new_user_purpose_path,
                  alert: "まだ目標が登録されていません。新規登録してください。"
    end
  end

  def update
    @user_purpose = current_user.user_purposes.build(user_purpose_params)
    @user_purpose.analysis_state = :pending

    if @user_purpose.save
      # ── 古い UserPurpose を非アクティブ化する ────────────────────────────
      #
      # 【なぜ必要か】
      #   update アクションは既存レコードを更新せず、
      #   新しいレコードを build + save して「バージョン管理」する設計。
      #   しかし保存後に古いレコードを is_active: false にしないと、
      #   UserPurpose.current_for（active_for スコープ）が複数件返してしまい
      #   「最新の目標」が正しく取得できない。
      #
      # 【update_all を使う理由】
      #   each { update! } は N+1 更新になる。
      #   update_all は1回の SQL UPDATE で全件処理できる。
      #   自分自身（@user_purpose.id）は除外する。
      current_user.user_purposes
                  .where(is_active: true)
                  .where.not(id: @user_purpose.id)
                  .update_all(is_active: false)
      # ────────────────────────────────────────────────────────────────────────

      if @user_purpose.crisis_word_detected?
        Rails.logger.warn "[UserPurposesController#update] 危機ワード検出: user_id=#{current_user.id}"
        @user_purpose.update_columns(analysis_state: UserPurpose.analysis_states[:failed])
        record_crisis_analysis_for_purpose(@user_purpose)
        flash[:crisis] = true
        redirect_to user_purpose_path, notice: "目標を更新しました。"
        return
      end

      PurposeAnalysisJob.perform_later(@user_purpose.id)
      redirect_to user_purpose_path,
                  notice: "目標を更新しました。AIによる再分析を開始しています..."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def retry_analysis
    @user_purpose = UserPurpose.current_for(current_user)
    unless @user_purpose
      redirect_to new_user_purpose_path, alert: "目標が登録されていません。"
      return
    end
    @user_purpose.update!(
      analysis_state:     :pending,
      last_error_message: nil
    )
    PurposeAnalysisJob.perform_later(@user_purpose.id)
    redirect_to user_purpose_path,
                notice: "再分析を開始しました。しばらくお待ちください。"
  end

  def ai_result
    @current_purpose = UserPurpose.current_for(current_user)
    unless @current_purpose
      redirect_to new_user_purpose_path, alert: "目標が登録されていません。"
      return
    end
    @ai_analysis = AiAnalysis.where(
      user_purpose_id: @current_purpose.id,
      is_latest:       true,
      analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
    ).first
    unless @ai_analysis
      redirect_to user_purpose_path,
                  alert: "AI分析結果がまだ存在しません。分析が完了するまでお待ちください。"
      return
    end
    snapshot = (@ai_analysis.input_snapshot || {}).with_indifferent_access
    @snapshot_purpose           = snapshot[:purpose]
    @snapshot_mission           = snapshot[:mission]
    @snapshot_vision            = snapshot[:vision]
    @snapshot_value             = snapshot[:value]
    @snapshot_current_situation = snapshot[:current_situation]
    @snapshot_version           = snapshot[:version]
    actions = (@ai_analysis.actions_json || []).map { |a|
      a.is_a?(Hash) ? a.with_indifferent_access : a
    }
    @habit_proposals = actions.select { |a| a[:type] == "habit" }
    @task_proposals  = actions.select { |a| a[:type] == "task" }
  end

  def apply_proposals
    @current_purpose = UserPurpose.current_for(current_user)
    unless @current_purpose
      redirect_to new_user_purpose_path, alert: "目標が登録されていません。"
      return
    end

    @ai_analysis = AiAnalysis.where(
      user_purpose_id: @current_purpose.id,
      is_latest:       true,
      analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
    ).first

    unless @ai_analysis
      redirect_to user_purpose_path, alert: "AI分析結果が見つかりません。"
      return
    end

    # ── 二重送信防止チェック ─────────────────────────────────────────────
    #
    # 【判定ロジック】
    #   この AI 分析が作成された時刻以降に
    #   ai_generated: true かつ task_type: improve のタスクが存在すれば確定済みとみなす。
    #   weekly_reflections#confirm_proposals と同じ設計方針。
    already_confirmed = current_user.tasks
                                    .where(ai_generated: true, task_type: :improve)
                                    .where('created_at > ?', @ai_analysis.created_at)
                                    .exists?

    if already_confirmed
      redirect_to dashboard_path, notice: "提案は既に反映済みです。"
      return
    end

    actions = (@ai_analysis.actions_json || []).map { |a|
      a.is_a?(Hash) ? a.with_indifferent_access : a
    }
    habit_proposals = actions.select { |a| a[:type] == "habit" }
    task_proposals  = actions.select { |a| a[:type] == "task" }

    selected_habit_indices = Array(params[:habit_indices]).map(&:to_i)
    selected_task_indices  = Array(params[:task_indices]).map(&:to_i)

    if selected_habit_indices.empty? && selected_task_indices.empty?
      redirect_to ai_result_user_purpose_path,
                  alert: "少なくとも1つの提案を選択してください。"
      return
    end

    created_habits = 0
    created_tasks  = 0

    ActiveRecord::Base.transaction do
      selected_habit_indices.each do |idx|
        proposal = habit_proposals[idx]
        next unless proposal

        # ── weekly_target を frequency から計算する（修正: 5 → 動的計算）──
        # 変更前: weekly_target: 5 のハードコード
        # 変更後: frequency 文字列から weekly_target を計算する
        #         WeeklyReflectionsController と同じロジックを使う
        weekly_target = parse_frequency_to_weekly_target(proposal[:frequency])

        current_user.habits.create!(
          name:             proposal[:title].to_s.truncate(50),
          measurement_type: :check_type,
          weekly_target:    weekly_target
        )
        created_habits += 1
      end

      selected_task_indices.each do |idx|
        proposal = task_proposals[idx]
        next unless proposal

        priority_value = case proposal[:priority].to_s.downcase
                         when "must"   then :must
                         when "should" then :should
                         when "could"  then :could
                         else               :should
                         end

        current_user.tasks.create!(
          title:        proposal[:title].to_s.truncate(100),
          priority:     priority_value,
          task_type:    :improve,
          ai_generated: true
        )
        created_tasks += 1
      end
    end

    parts = []
    parts << "習慣 #{created_habits} 件" if created_habits > 0
    parts << "タスク #{created_tasks} 件" if created_tasks > 0
    redirect_to dashboard_path, notice: "#{parts.join('、')}をダッシュボードに追加しました！"

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[apply_proposals] RecordInvalid: #{e.message}"
    redirect_to ai_result_user_purpose_path,
                alert: "提案の登録中にエラーが発生しました。もう一度お試しください。"
  end

  # ============================================================
  # H-9 追加: dismiss_completion_banner
  # ============================================================
  # 【役割】
  #   ダッシュボードのPMVV完了バナーの✖ボタン（dismissible_controller.js）から
  #   PATCH で呼ばれ、user_setting の pmvv_banner_dismissed_at を現在時刻に更新する。
  #   これにより、リロードしてもバナーが復元されなくなる（=✖で閉じた状態が永続化）。
  #
  # 【throttle_ai_request の対象外である理由】
  #   before_action :throttle_ai_request は create/update/retry_analysis のみ対象。
  #   このアクションは AI ジョブを投入しない軽量な状態更新のため throttle は不要。
  #
  # 【head :no_content（204）を返す理由】
  #   JS 側は fetch で叩くだけで画面遷移しない（✖押下時にJSが即座に hidden 済み）。
  #   返すべきビューが無いため、ボディなしの 204 No Content を返す。
  #
  # 【user_setting が nil の場合の &. ガード】
  #   通常は全ユーザーに user_setting が存在するが、万一 nil でも
  #   NoMethodError にせず 204 を返してUIを壊さない。
  def dismiss_completion_banner
    current_user.user_setting&.touch_pmvv_banner_dismissed_at!
    head :no_content
  end

  private

  # ── D-5 追加 / I-1 修正: record_crisis_analysis_for_purpose ────────────────
  #
  # 【役割】
  #   PMVV 入力で危機ワードが検出されたときに
  #   crisis_detected=true の AiAnalysis レコードを作成する（危機検出の監査記録）。
  #
  # 【なぜ create（!なし）を使うか】
  #   crisis の記録に失敗しても PMVV の保存は成功扱いにするため。
  #   create! は例外を発生させるので使わない。
  #
  # 【I-1 修正の要点（重要）】
  #   この分析は analysis_type: :purpose_breakdown なので、AiAnalysis の
  #   D-9 バリデーション input_snapshot_schema_valid により
  #   input_snapshot に purpose / mission / vision / value / current_situation の
  #   5キーが必須になる。修正前はこの5キーを入れていなかったため検証で弾かれ、
  #   create（非bang）が保存に失敗し「危機の監査レコードが残らない」不具合があった。
  #   → input_snapshot に PMVV の5キーを含めて検証を満たし、確実に保存されるようにする。
  def record_crisis_analysis_for_purpose(user_purpose)
    result = AiAnalysis.create(
      user_purpose_id:  user_purpose.id,
      analysis_type:    :purpose_breakdown,
      crisis_detected:  true,
      is_latest:        true,
      input_snapshot: {
        # D-9 スキーマ検証（purpose_breakdown は5キー必須）を満たすためのPMVV5キー。
        # 値は nil でも「キーが存在すれば可」の設計なのでそのまま渡してよい。
        purpose:            user_purpose.purpose,
        mission:            user_purpose.mission,
        vision:             user_purpose.vision,
        value:              user_purpose.value,
        current_situation:  user_purpose.current_situation,
        # 危機検出の監査用メタ情報（従来どおり保持）
        user_purpose_id:    user_purpose.id,
        version:            user_purpose.version,
        crisis_detected_at: Time.current.iso8601,
        note: "危機ワード検出によりAI分析をスキップしました"
      },
      analysis_comment: "危機ワードが検出されたため、AI分析をスキップしました。",
      prompt_version:   "crisis_skip"
    )

    unless result.persisted?
      Rails.logger.error "[UserPurposesController] crisis AiAnalysis 保存失敗: #{result.errors.full_messages.join(', ')}"
    end
  end
  # ────────────────────────────────────────────────────────────────────────────

  def user_purpose_params
    params.require(:user_purpose).permit(
      :purpose,
      :mission,
      :vision,
      :value,
      :current_situation
    )
  end

    # ── E-3 追加: parse_frequency_to_weekly_target ────────────────────────────
  #
  # 【役割】
  #   AI が返す frequency 文字列（"毎日", "週3回" など）を
  #   Habit の weekly_target（整数）に変換する。
  #   WeeklyReflectionsController と同じロジックを共有する。
  #
  # 【変換ルール】
  #   "毎日"   → 7
  #   "週N回"  → N（1〜7 の範囲に clamp）
  #   それ以外 → 7（毎日をデフォルトにする）
  def parse_frequency_to_weekly_target(frequency)
    return 7 if frequency.blank?
    freq_str = frequency.to_s
    return 7 if freq_str.include?("毎日")
    if freq_str =~ /週(\d+)回/
      $1.to_i.clamp(1, 7)
    else
      7
    end
  end
end