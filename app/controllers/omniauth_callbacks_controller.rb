# app/controllers/omniauth_callbacks_controller.rb
#
# ==============================================================================
# OmniauthCallbacksController（F-1 新規作成）
# ==============================================================================
#
# 【このファイルの役割】
#   Google OAuth2 認証完了後のコールバックを処理するコントローラー。
#   GET /auth/google_oauth2/callback を受け取り、ログインセッションを確立する。
#
# 【認証フローの全体像】
#   1. ユーザーが「Googleでログイン」ボタンをクリック
#      → POST /auth/google_oauth2（omniauth-rails_csrf_protection がここを保護）
#   2. OmniAuth ミドルウェアが Google 認証ページへリダイレクト
#   3. ユーザーが Google でログインを許可
#   4. Google が GET /auth/google_oauth2/callback へリダイレクト
#   5. OmniAuth が認証情報を request.env['omniauth.auth'] にセット
#   6. このコントローラーの google アクションが呼ばれる
#
# ==============================================================================

class OmniauthCallbacksController < ApplicationController
  # ============================================================
  # CSRF 検証のスキップ（コールバックのみ）
  # ============================================================
  #
  # 【なぜスキップが必要なのか】
  #   omniauth-rails_csrf_protection gem は「認証開始リクエスト」
  #   （POST /auth/google_oauth2）を保護する。
  #   しかし「コールバック」（GET /auth/google_oauth2/callback）は
  #   Google（外部ドメイン）からリダイレクトされてくるリクエストのため、
  #   Rails の authenticity_token が含まれていない。
  #   → デフォルトの CSRF 検証をそのまま適用すると 422 エラーになる。
  #
  # 【なぜスキップしても安全なのか】
  #   OAuth2 の仕様では「state パラメータ」を使って CSRF を防ぐ。
  #   OmniAuth はランダムな state 値をセッションに保存し、
  #   コールバックで Google が返す state 値と照合して一致を確認する。
  #   この仕組みにより、第三者が偽造したコールバックは弾かれる。
  #
  # 【only: [:google] で限定する理由】
  #   このコントローラーに将来 LINE 等のアクションを追加した場合でも
  #   スキップ対象が意図せず拡大しないよう、明示的に限定する。
  skip_before_action :verify_authenticity_token, only: [:google]

  # ============================================================
  # google アクション（GET /auth/google_oauth2/callback）
  # ============================================================
  def google
    # ── ① OmniAuth から認証情報を取得する ──────────────────────────────────
    #
    # request.env["omniauth.auth"]:
    #   OmniAuth ミドルウェアが Google から受け取ったユーザー情報をここに格納する。
    #   Hash 形式で provider / uid / info（email・name）等が入っている。
    auth = request.env["omniauth.auth"]

    # ── ② User.from_omniauth でユーザーを取得または作成する ─────────────────
    @user = User.from_omniauth(auth)

    if @user.persisted?
      # ── 認証成功 ───────────────────────────────────────────────────────────

      # reset_session:
      #   ログイン成功時に必ず実行する。
      #   既存のセッション ID を破棄して新しい ID を発行することで
      #   「セッション固定攻撃（Session Fixation Attack）」を防ぐ。
      #   攻撃者が事前に仕込んだセッション ID を無効化できる。
      reset_session

      session[:user_id] = @user.id

      # リダイレクト先を決定する。
      # 初回ログイン（first_login_at が nil）はオンボーディングへ遷移する。
      redirect_to determine_redirect_path_for_omniauth(@user),
                  notice: t("omniauth.google.success")

    else
      # ── 保存されていない場合（通常は起きないが念のため）──────────────────
      Rails.logger.error "[OmniauthCallbacksController#google] " \
                         "ユーザーが persisted? でない: " \
                         "provider=#{auth['provider']}, uid=#{auth['uid']}"
      redirect_to login_path, alert: t("omniauth.google.failure")
    end

  rescue ActiveRecord::RecordInvalid => e
    # User.from_omniauth 内の create! が失敗した場合（バリデーションエラー等）
    Rails.logger.error "[OmniauthCallbacksController#google] ユーザー作成失敗: #{e.message}"
    redirect_to login_path, alert: t("omniauth.google.failure")
  end

  # ============================================================
  # failure アクション（GET /auth/failure）
  # ============================================================
  #
  # 【このアクションの役割】
  #   OmniAuth が認証失敗と判定した場合のフォールバック先。
  #   config/initializers/omniauth.rb の on_failure で設定したリダイレクトが
  #   効かないケースに備えて、ルーティングでも受け皿を用意しておく。
  #
  # 【いつ呼ばれるか】
  #   - Google 認証画面でユーザーがキャンセルした場合（:access_denied）
  #   - state パラメータの検証失敗（CSRF 攻撃の疑い）
  #   - その他 OmniAuth が処理できないエラー
  def failure
    # params[:message]: OmniAuth がエラー種別を文字列でセットする
    # ログに残してデバッグに役立てる
    Rails.logger.warn "[OmniauthCallbacksController#failure] " \
                      "OmniAuth 失敗: message=#{params[:message]}"

    # omniauth_error フラグを付けてログインページへリダイレクト
    # ビュー側でこのパラメータを見てエラーメッセージを表示する
    redirect_to login_path(omniauth_error: true)
  end

  private

  # ============================================================
  # determine_redirect_path_for_omniauth（F-1 追加）
  # ============================================================
  #
  # 【役割】
  #   OmniAuth ログイン後のリダイレクト先を優先度に従って決定する。
  #   SessionsController の determine_redirect_path と同じ設計方針。
  #
  # 【優先度】
  #   1. first_login_at が nil → オンボーディングへ（初回ログイン完了条件）
  #   2. session[:return_to] が存在する → そのパスへ（将来の拡張用）
  #   3. デフォルト → ダッシュボードへ
  def determine_redirect_path_for_omniauth(user)
    return onboarding_step5_path if user.first_login_at.nil?

    if session[:return_to].present? && safe_redirect_path?(session.delete(:return_to))
      return session[:return_to]
    end

    dashboard_path
  end
end