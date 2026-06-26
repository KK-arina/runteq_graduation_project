# app/controllers/omniauth_callbacks_controller.rb
#
# ==============================================================================
# OmniauthCallbacksController（G-1 更新）
# ==============================================================================
#
# 【G-1 での変更内容】
#   line アクションに line_user_id の保存処理を追加した。
#
# 【設計の核心: LINE Login の uid = LINE Messaging API の userId】
#
#   LINE は「同一プロバイダ（Provider）内なら、LINE Login の sub と
#   Messaging API の userId は同じ値」という仕様になっている。
#   （参考: https://developers.line.biz/en/docs/messaging-api/getting-user-ids/）
#
#   つまり OmniAuth コールバックで取得できる auth["uid"]（= LINE Login の sub）を
#   そのまま users.line_user_id として保存すれば、
#   後から LINE Messaging API でプッシュ通知を送るときに使える。
#
#   【前提条件】
#     LINE Login チャネルと Messaging API チャネルが
#     同一の LINE Provider 下に作成されていること。
#     別 Provider だと userId が異なる値になり通知が届かない。
#
# ==============================================================================

class OmniauthCallbacksController < ApplicationController
  # CSRF 検証スキップ（コールバックのみ）
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
  # line アクション（GET /auth/line_v2_1/callback）- G-1更新 / G-6更新
  # ============================================================
  #
  # 【G-1 変更点】
  #   save_line_user_id(@user, auth) の呼び出しを追加した。
  #
  # 【G-6 変更点】
  #   origin パラメータで呼び出し元を判定する分岐を追加。
  #
  #   origin="notification" かつログイン済み:
  #     通知設定ページからの連携 → provider を変更せず line_user_id のみ保存。
  #   それ以外:
  #     設定ページまたはログインページからの連携 → 通常の LINE ログイン処理。
  #
  # 【なぜ URLクエリパラメータで origin を渡すのか】
  #   hidden_field_tag で POST ボディに origin を含めても、
  #   OmniAuth ミドルウェアがボディを読む前に処理するため
  #   request.env["omniauth.origin"] に届かないことがある。
  #   URLの ?origin=notification ならミドルウェアが確実に認識する。
  def line
    auth   = request.env["omniauth.auth"]
    origin = request.env["omniauth.origin"]

    # ── G-6 追加: 通知設定ページからの LINE 通知連携 ──────────────────
    #
    # 通知設定ページのフォームは /auth/line_v2_1?origin=notification を使う。
    # OmniAuth はクエリパラメータを omniauth.origin として引き渡す。
    # logged_in? も確認することで、未ログイン状態での誤動作を防ぐ。
    #
    # 【provider を変更しない理由】
    #   provider を "line_v2_1" に書き換えると
    #   メールアドレス+パスワードでのログインができなくなる危険がある。
    #   通知のみ連携では provider は元の値（"email" 等）のまま維持する。
    if origin == "notification" && logged_in?
      save_line_user_id(current_user, auth)

      # LINE 通知連携と同時に line_notification_enabled を true にする
      #
      # line_notification_enabled のデフォルトは false のため、
      # 連携した瞬間から通知が受け取れる状態にする。
      # 通知を止めたい場合は通知設定ページから OFF にできる。
      user_setting = current_user.user_setting ||
                     UserSetting.find_or_create_by!(user: current_user)
      user_setting.update(line_notification_enabled: true)

      redirect_to notification_settings_settings_path,
                  notice: "LINE通知連携が完了しました ✅"
      return
    end

    # ── 通常の LINE ログイン処理（G-1 由来）─────────────────────────
    @user = User.from_omniauth(auth)
    if @user.persisted?
      reset_session
      session[:user_id] = @user.id
      # auth["uid"] には LINE Login の sub（= Messaging API の userId）が入っている。
      # 同一プロバイダ内なら LINE Login sub = Messaging API userId のため、
      # これを line_user_id として保存することで通知送信に使える。
      save_line_user_id(@user, auth)
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
  # save_line_user_id（G-1 追加）
  # ============================================================
  #
  # 【役割】
  #   LINE ログイン後に users.line_user_id を保存する。
  #   LINE Login の sub（auth["uid"]）をそのまま line_user_id に使う。
  #
  # 【なぜ auth["uid"] = line_user_id になるのか】
  #   omniauth-line-v2_1 gem は LINE Login の ID トークンから sub（ユーザー識別子）を
  #   取得して auth["uid"] にセットしている。
  #   LINE の仕様として「同一プロバイダ内では LINE Login の sub と
  #   Messaging API の userId は同じ値」が保証されている。
  #   したがって auth["uid"] = Messaging API の userId として使用できる。
  #
  # 【update_columns を使う理由】
  #   update! だとバリデーション・コールバックが全て走る（重い）。
  #   line_user_id の保存だけが目的のため update_columns で直接更新する。
  #   update_columns は SQL を1本だけ発行するため高速かつ安全。
  #
  # 【既に同じ値なら更新しない理由（早期リターン）】
  #   同一ユーザーが毎回 LINE ログインするたびに UPDATE を発行するのは無駄。
  #   既に正しい line_user_id が設定済みなら何もしない。
  #
  # 【rescue の理由】
  #   line_user_id の保存失敗でもログイン自体を失敗させてはいけない。
  #   保存失敗はログに記録して静かに処理する。
  #   次回 LINE ログイン時に再度保存が試みられる。
  def save_line_user_id(user, auth)
    line_uid = auth["uid"]

    # 既に同じ値が設定済みなら何もしない（不要な DB 更新を防ぐ）
    return if user.line_user_id == line_uid

    Rails.logger.debug "[OmniauthCallbacksController] line_user_id は変更なし: user_id=#{user.id}" if user.line_user_id == line_uid

    # update_column を使う理由:
    #   update_columns（複数形）は updated_at を自動更新しないため明示が必要で危険。
    #   update_column（単数形）は指定の1カラムのみ更新し、
    #   Rails がバリデーションをスキップしつつ updated_at も自動更新してくれる。
    #   line_user_id という単一カラムの保存のみが目的のため単数形が適切。
    user.update_column(:line_user_id, line_uid)

    Rails.logger.info(
      "[OmniauthCallbacksController] line_user_id を保存しました: " \
      "user_id=#{user.id} line_user_id=#{line_uid}"
    )

  rescue => e
    Rails.logger.error(
      "[OmniauthCallbacksController] line_user_id 保存失敗: " \
      "user_id=#{user.id} error=#{e.message}"
    )
  end

  # ============================================================
  # determine_redirect_path_for_omniauth（変更なし）
  # ============================================================
  #
  # 【優先度】
  #   1. terms_agreed_at が nil → /terms_agreement（法規上必須・最優先）
  #   2. first_login_at が nil  → オンボーディング
  #   3. session[:return_to] が安全なパス → そのパスへ
  #   4. デフォルト             → ダッシュボード
  def determine_redirect_path_for_omniauth(user)
    return terms_agreement_path unless user.terms_agreed?
    return onboarding_step2_path if user.first_login_at.nil?

    stored_path = session[:return_to]
    if stored_path.present? && safe_redirect_path?(stored_path)
      session.delete(:return_to)
      return stored_path
    end

    dashboard_path
  end
end