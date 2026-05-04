# app/controllers/onboardings_controller.rb
#
# ==============================================================================
# OnboardingsController（D-7 新規作成）
# ==============================================================================
#
# 【このファイルの役割】
#   初回ログインユーザーのオンボーディングフロー（5ステップ）を管理する。
#   5/5 ステップ（PMVV目標入力）を担当する。
#
# 【first_login_at の役割】
#   users.first_login_at が NULL のユーザーは未完了のオンボーディングを持つ。
#   完了またはスキップ時に first_login_at を更新することで再表示を防ぐ。
#
# 【スキップ 422 エラーの解決方法】
#   button_to はデフォルトで Turbo が処理する。
#   Turbo は POST に対して turbo_stream または html を期待する。
#   skip / complete アクションで respond_to を使い
#   html と turbo_stream の両方に対してリダイレクトを返すことで解決。
# ==============================================================================

class OnboardingsController < ApplicationController
  before_action :require_login
  before_action :ensure_needs_onboarding

  # ============================================================
  # step5 アクション（GET /onboarding/step5）
  # ============================================================
  # 【役割】オンボーディング 5/5（PMVV目標入力）ページを表示する。
  def step5
    @user_purpose = UserPurpose.new
  end

  # ============================================================
  # complete アクション（POST /onboarding/complete）
  # ============================================================
  # 【役割】
  #   PMVV データを保存し、AI分析ジョブを投入後、
  #   first_login_at を更新してダッシュボードへ遷移する。
  def complete
    @user_purpose = current_user.user_purposes.build(onboarding_purpose_params)
    @user_purpose.analysis_state = :pending

    if @user_purpose.save
      if @user_purpose.crisis_word_detected?
        Rails.logger.warn "[OnboardingsController#complete] 危機ワード検出: user_id=#{current_user.id}"
        @user_purpose.update_columns(
          analysis_state: UserPurpose.analysis_states[:failed]
        )
        complete_onboarding!
        flash[:crisis] = true
        redirect_to dashboard_path, notice: t("onboarding.completed")
        return
      end

      PurposeAnalysisJob.perform_later(@user_purpose.id)
      complete_onboarding!

      # respond_to で html と turbo_stream の両方に対応する
      # 【理由】form_with local: true でも Turbo がリクエストを
      #   インターセプトすることがある。respond_to で明示することで
      #   どちらの形式のリクエストでも正しくリダイレクトが動く。
      respond_to do |format|
        format.html do
          redirect_to dashboard_path, notice: t("onboarding.completed")
        end
        format.turbo_stream do
          redirect_to dashboard_path, notice: t("onboarding.completed")
        end
      end
    else
      render :step5, status: :unprocessable_entity
    end
  end

  # ============================================================
  # skip アクション（POST /onboarding/skip）
  # ============================================================
  # 【役割】
  #   PMVV を保存せずに first_login_at を更新してダッシュボードへ遷移する。
  #
  # 【なぜ respond_to が必要か】
  #   button_to はデフォルトで Turbo が処理する。
  #   Turbo POST に対して redirect_to だけだと
  #   422 エラーが発生するケースがある。
  #   respond_to で html と turbo_stream の両方に
  #   redirect_to を返すことで確実に動作する。
  def skip
    complete_onboarding!

    respond_to do |format|
      format.html do
        redirect_to dashboard_path, notice: t("onboarding.skipped")
      end
      format.turbo_stream do
        redirect_to dashboard_path, notice: t("onboarding.skipped")
      end
    end
  end

  private

  # ----------------------------------------------------------
  # ensure_needs_onboarding
  # ----------------------------------------------------------
  # 【役割】
  #   first_login_at 設定済みユーザーをダッシュボードへリダイレクトする。
  def ensure_needs_onboarding
    if current_user.first_login_at.present?
      redirect_to dashboard_path, notice: t("onboarding.already_completed")
    end
  end

  # ----------------------------------------------------------
  # complete_onboarding!
  # ----------------------------------------------------------
  # 【役割】
  #   first_login_at に現在時刻をセットしてオンボーディング完了にする。
  #
  # 【update_column を使う理由】
  #   update! だとバリデーション（password 等）が再実行される可能性がある。
  #   update_column は指定カラムのみバリデーションなしで直接更新する。
  def complete_onboarding!
    current_user.update_column(:first_login_at, Time.current)
  end

  # ----------------------------------------------------------
  # onboarding_purpose_params
  # ----------------------------------------------------------
  # 【役割】Strong Parameters でフォームパラメータを制限する。
  def onboarding_purpose_params
    params.require(:user_purpose).permit(
      :purpose,
      :mission,
      :vision,
      :value,
      :current_situation
    )
  end
end