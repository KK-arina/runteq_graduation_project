# app/controllers/omniauth_callbacks_controller.rb
#
# ==============================================================================
# OmniauthCallbacksController（F-1 新規作成、F-2 LINE アクション追加、F-3 同意フロー追加）
# ==============================================================================
#
# 【F-3 での変更内容】
#   determine_redirect_path_for_omniauth に利用規約同意チェックを追加した。
#   OAuth ユーザーが terms_agreed_at 未設定の場合は /terms_agreement へ誘導する。
#
# 【OAuth 後の遷移優先度（F-3 更新版）】
#   優先度1: terms_agreed_at が nil → /terms_agreement（同意ページ）
#   優先度2: first_login_at が nil  → オンボーディング
#   優先度3: デフォルト             → ダッシュボード
#
# ==============================================================================

class OmniauthCallbacksController < ApplicationController
  # CSRF 検証スキップ（コールバックのみ）
  #
  # 【なぜスキップが必要なのか】
  #   コールバックは外部ドメイン（Google/LINE）からリダイレクトされるため
  #   Rails の authenticity_token が含まれていない。
  #   OAuth2 の state パラメータで CSRF を防ぐため安全にスキップできる。
  skip_before_action :verify_authenticity_token, only: [:google, :line]

  # ============================================================
  # google アクション（GET /auth/google_oauth2/callback）
  # ============================================================
  def google
    auth = request.env["omniauth.auth"]
    @user = User.from_omniauth(auth)

    if @user.persisted?
      reset_session
      session[:user_id] = @user.id

      redirect_to determine_redirect_path_for_omniauth(@user),
                  notice: t("omniauth.google.success")
    else
      Rails.logger.error "[OmniauthCallbacksController#google] " \
                         "ユーザーが persisted? でない: " \
                         "provider=#{auth['provider']}, uid=#{auth['uid']}"
      redirect_to login_path, alert: t("omniauth.google.failure")
    end

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[OmniauthCallbacksController#google] ユーザー作成失敗: #{e.message}"
    redirect_to login_path, alert: t("omniauth.google.failure")
  end

  # ============================================================
  # line アクション（GET /auth/line/callback）
  # ============================================================
  def line
    auth = request.env["omniauth.auth"]
    @user = User.from_omniauth(auth)

    if @user.persisted?
      reset_session
      session[:user_id] = @user.id

      redirect_to determine_redirect_path_for_omniauth(@user),
                  notice: t("omniauth.line.success")
    else
      Rails.logger.error "[OmniauthCallbacksController#line] " \
                         "ユーザーが persisted? でない: " \
                         "provider=#{auth['provider']}, uid=#{auth['uid']}"
      redirect_to login_path, alert: t("omniauth.line.failure")
    end

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[OmniauthCallbacksController#line] ユーザー作成失敗: #{e.message}"
    redirect_to login_path, alert: t("omniauth.line.failure")
  end

  # ============================================================
  # failure アクション（GET /auth/failure）
  # ============================================================
  def failure
    Rails.logger.warn "[OmniauthCallbacksController#failure] " \
                      "OmniAuth 失敗: message=#{params[:message]}"
    redirect_to login_path(omniauth_error: true)
  end

  private

  # ============================================================
  # determine_redirect_path_for_omniauth（F-1 追加、F-2 継続、F-3 更新）
  # ============================================================
  #
  # 【役割】
  #   OmniAuth ログイン後のリダイレクト先を優先度に従って決定する。
  #
  # 【F-3 変更点】
  #   優先度1 に「利用規約同意チェック」を追加した。
  #   terms_agreed_at が nil のユーザーは必ず /terms_agreement を経由させる。
  #   同意完了後に first_login_at チェック（オンボーディング）へ進む。
  #
  # 【優先度】
  #   1. terms_agreed_at が nil → /terms_agreement（法規上必須・最優先）
  #   2. first_login_at が nil  → オンボーディング
  #   3. session[:return_to] が安全なパス → そのパスへ
  #   4. デフォルト             → ダッシュボード
  def determine_redirect_path_for_omniauth(user)
    # 優先度1: 利用規約未同意ユーザーは同意ページへ（F-3 追加）
    #
    # 【なぜ最優先にするのか】
    #   法規対応として、いかなる場合も同意なしでサービスを使わせてはいけない。
    #   オンボーディングより先に同意を取得する必要がある。
    return terms_agreement_path unless user.terms_agreed?

    # 優先度2: 初回ログインユーザーはオンボーディングへ
    return onboarding_step5_path if user.first_login_at.nil?

    # 優先度3: session[:return_to] が安全なパスならそこへ（将来の拡張用）
    stored_path = session[:return_to]
    if stored_path.present? && safe_redirect_path?(stored_path)
      session.delete(:return_to)
      return stored_path
    end

    # 優先度4: デフォルトはダッシュボード
    dashboard_path
  end
end