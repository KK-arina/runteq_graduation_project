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
      # ── D-5 追加: 危機ワード検出時の分岐 ────────────────────────────────
      #
      # 【なぜ save 後に確認するのか】
      #   before_validation コールバックで crisis_word_detected が
      #   セットされるため、save（バリデーション実行後）のタイミングで
      #   このフラグを確認できる。
      if @user_purpose.crisis_word_detected?
        Rails.logger.warn "[UserPurposesController#create] 危機ワード検出: user_id=#{current_user.id}"

        # crisis_detected=true の AiAnalysis を記録する
        record_crisis_analysis_for_purpose(@user_purpose)

        # flash[:crisis]: JavaScript がモーダルを表示するためのトリガー
        flash[:crisis] = true
        redirect_to user_purpose_path,
                    notice: "目標を保存しました。"
        return
      end
      # ────────────────────────────────────────────────────────────────────────

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
      # ── D-5 追加: 危機ワード検出時の分岐 ────────────────────────────────
      if @user_purpose.crisis_word_detected?
        Rails.logger.warn "[UserPurposesController#update] 危機ワード検出: user_id=#{current_user.id}"
        record_crisis_analysis_for_purpose(@user_purpose)
        flash[:crisis] = true
        redirect_to user_purpose_path,
                    notice: "目標を更新しました。"
        return
      end
      # ────────────────────────────────────────────────────────────────────────

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
        current_user.habits.create!(
          name:             proposal[:title].to_s.truncate(50),
          measurement_type: :check_type,
          weekly_target:    5
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

  private

  # ── D-5 追加: record_crisis_analysis_for_purpose ──────────────────────────
  #
  # 【役割】
  #   PMVV 入力で危機ワードが検出されたときに
  #   crisis_detected=true の AiAnalysis レコードを作成する。
  #
  # 【なぜ create（!なし）を使うか】
  #   crisis の記録に失敗しても PMVV の保存は成功扱いにするため。
  #   create! は例外を発生させるので使わない。
  def record_crisis_analysis_for_purpose(user_purpose)
    result = AiAnalysis.create(
      user_purpose_id:  user_purpose.id,
      analysis_type:    :purpose_breakdown,
      crisis_detected:  true,
      is_latest:        true,
      input_snapshot: {
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
end