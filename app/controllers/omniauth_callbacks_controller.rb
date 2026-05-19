# app/controllers/omniauth_callbacks_controller.rb
#
# ==============================================================================
# OmniauthCallbacksController（F-1 新規作成、F-2 LINE アクション追加）
# ==============================================================================
#
# 【このファイルの役割】
#   OAuth 認証完了後のコールバックを処理するコントローラー。
#   F-1: GET /auth/google_oauth2/callback → google アクション
#   F-2: GET /auth/line/callback          → line アクション
#
# 【認証フローの全体像（LINE の場合）】
#   1. ユーザーが「LINEでログイン」ボタンをクリック
#      → POST /auth/line（omniauth-rails_csrf_protection がここを保護）
#   2. OmniAuth ミドルウェアが LINE の認証ページへリダイレクト
#   3. ユーザーが LINE でログインを許可
#   4. LINE が GET /auth/line/callback へリダイレクト
#   5. OmniAuth が認証情報を request.env['omniauth.auth'] にセット
#   6. このコントローラーの line アクションが呼ばれる
#
# ==============================================================================

class OmniauthCallbacksController < ApplicationController
  # ============================================================
  # CSRF 検証のスキップ（コールバックのみ）
  # ============================================================
  #
  # 【なぜスキップが必要なのか】
  #   コールバック（GET /auth/google_oauth2/callback や GET /auth/line/callback）は
  #   外部ドメイン（Google や LINE）からリダイレクトされてくるリクエストのため、
  #   Rails の authenticity_token が含まれていない。
  #   → デフォルトの CSRF 検証をそのまま適用すると 422 エラーになる。
  #
  # 【なぜスキップしても安全なのか】
  #   OAuth2 の仕組みでは「state パラメータ」を使って CSRF を防ぐ。
  #   OmniAuth はランダムな state 値をセッションに保存し、
  #   コールバックで返る state 値と照合して一致を確認する。
  #
  # 【only: [:google, :line] で限定する理由】
  #   スキップ対象を明示的に限定し、
  #   将来新しいアクションを追加しても意図せずスキップが拡大しないようにする。
  skip_before_action :verify_authenticity_token, only: [:google, :line]

  # ============================================================
  # google アクション（GET /auth/google_oauth2/callback）（F-1 から継続）
  # ============================================================
  def google
    # ── ① OmniAuth から認証情報を取得する ──────────────────────────────────
    #
    # request.env["omniauth.auth"]:
    #   OmniAuth ミドルウェアが Google から受け取ったユーザー情報をここに格納する。
    auth = request.env["omniauth.auth"]

    # ── ② User.from_omniauth でユーザーを取得または作成する ─────────────────
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
  # F-2 追加: line アクション（GET /auth/line/callback）
  # ============================================================
  #
  # 【このアクションの役割】
  #   LINE OAuth2 認証完了後のコールバックを処理する。
  #   User.from_omniauth で既存ユーザー検索または新規作成を行い、
  #   セッションを確立してログイン状態にする。
  #
  # 【google アクションとの違い】
  #   LINE はメールアドレスを返さないため、
  #   User.from_omniauth 内でメールによるマージ処理はスキップされる。
  #   エラーメッセージのロケールキーが "omniauth.line.*" になる。
  #
  def line
    # ── ① OmniAuth から認証情報を取得する ──────────────────────────────────
    #
    # request.env["omniauth.auth"]:
    #   OmniAuth ミドルウェアが LINE から受け取ったユーザー情報をここに格納する。
    #   LINE の auth ハッシュ:
    #     { "provider" => "line", "uid" => "U1234...", "info" => { "name" => "山田太郎" } }
    auth = request.env["omniauth.auth"]

    # ── ② User.from_omniauth でユーザーを取得または作成する ─────────────────
    #
    # from_omniauth は provider + uid で検索し、
    # 見つからない場合は新規ユーザーを create! する。
    # LINE の場合は email が nil になるが、allow_nil: true のため問題ない。
    @user = User.from_omniauth(auth)

    if @user.persisted?
      # ── 認証成功 ───────────────────────────────────────────────────────────

      # reset_session:
      #   ログイン成功時に必ず実行する。
      #   既存のセッション ID を破棄して新しい ID を発行することで
      #   「セッション固定攻撃（Session Fixation Attack）」を防ぐ。
      reset_session

      # セッションにユーザー ID を保存してログイン状態にする
      session[:user_id] = @user.id

      # リダイレクト先を決定する（初回はオンボーディングへ）
      redirect_to determine_redirect_path_for_omniauth(@user),
                  notice: t("omniauth.line.success")

    else
      # ── 保存されていない場合（通常は起きないが念のため）──────────────────
      Rails.logger.error "[OmniauthCallbacksController#line] " \
                         "ユーザーが persisted? でない: " \
                         "provider=#{auth['provider']}, uid=#{auth['uid']}"
      redirect_to login_path, alert: t("omniauth.line.failure")
    end

  rescue ActiveRecord::RecordInvalid => e
    # User.from_omniauth 内の create! が失敗した場合（バリデーションエラー等）
    #
    # 【どんな場合に起きるか】
    #   name バリデーション失敗など（LINE の displayName が 50 文字超え等）。
    #   エラー内容をログに残してログインページへリダイレクトする。
    Rails.logger.error "[OmniauthCallbacksController#line] ユーザー作成失敗: #{e.message}"
    redirect_to login_path, alert: t("omniauth.line.failure")
  end

  # ============================================================
  # failure アクション（GET /auth/failure）
  # ============================================================
  #
  # 【このアクションの役割】
  #   OmniAuth が認証失敗と判定した場合のフォールバック先。
  #   Google / LINE いずれかの認証失敗でもここに来る。
  def failure
    Rails.logger.warn "[OmniauthCallbacksController#failure] " \
                      "OmniAuth 失敗: message=#{params[:message]}"

    redirect_to login_path(omniauth_error: true)
  end

  private

  # ============================================================
  # determine_redirect_path_for_omniauth（F-1 追加、F-2 継続使用）
  # ============================================================
  #
  # 【役割】
  #   OmniAuth ログイン後のリダイレクト先を優先度に従って決定する。
  #   Google / LINE いずれの認証後も同じロジックを使用する。
  #
  # 【優先度】
  #   1. first_login_at が nil → オンボーディングへ（初回ログイン）
  #   2. session[:return_to] が存在する → そのパスへ（将来の拡張用）
  #   3. デフォルト → ダッシュボードへ
  def determine_redirect_path_for_omniauth(user)
    return onboarding_step5_path if user.first_login_at.nil?

    # ── 修正前（バグあり） ─────────────────────────────────────────────────
    # if session[:return_to].present? && safe_redirect_path?(session.delete(:return_to))
    #   return session[:return_to]
    # end
    #
    # ↑ session.delete(:return_to) はセッション値を削除しながら値を返すが、
    #   その後 return session[:return_to] をすると、すでに削除済みのため nil を返す。
    #   そのため stored_path に一度退避してから削除する必要がある。
    #
    # ── 修正後 ──────────────────────────────────────────────────────────────
    #
    # stored_path:
    #   session[:return_to] の値を一時変数に退避する。
    #   safe_redirect_path? の検証と delete を分離するための変数。
    #
    # safe_redirect_path? は ApplicationController で定義済み。
    #   外部URL（http://evil.com）やダブルスラッシュを弾く。
    stored_path = session[:return_to]

    if stored_path.present? && safe_redirect_path?(stored_path)
      session.delete(:return_to)  # 検証後に削除（使い捨て）
      return stored_path
    end

    dashboard_path
  end
end