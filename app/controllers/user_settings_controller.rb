# app/controllers/user_settings_controller.rb
#
# ==============================================================================
# UserSettingsController（G-3 新規作成 / G-4 お休みモード追加）
# ==============================================================================
#
# 【このコントローラーの役割】
#   user_settings テーブルの通知設定・お休みモード設定を表示・更新する。
#   SettingsController（アカウント情報・退会）とは責務が異なるため分離する。
#
# 【G-4 での追加内容】
#   rest_mode       : お休みモード設定ページ表示（GET）
#   start_rest_mode : お休みモード開始（POST）
#   stop_rest_mode  : お休みモード終了（DELETE）
#
# 【SettingsController との違い】
#   SettingsController  : @user の表示・退会処理
#   UserSettingsController: user_settings の通知設定・お休みモード管理
# ==============================================================================
class UserSettingsController < ApplicationController

  # require_login: 未ログインユーザーをログインページへリダイレクトする。
  # ApplicationController に定義されている before_action。
  before_action :require_login

  # ==============================================================================
  # notification_settings（GET /settings/notification_settings）
  # ==============================================================================
  #
  # 【役割】通知設定ページ（21番）を表示する。
  def notification_settings
    @user_setting = current_user.user_setting ||
                    UserSetting.find_or_create_by!(user: current_user)

    @line_connected = current_user.line_user_id.present?
  end

  # ==============================================================================
  # update_notification_settings（PATCH /settings/notification_settings）
  # ==============================================================================
  #
  # 【役割】通知設定フォームの内容を user_settings テーブルに保存する。
  def update_notification_settings
    @user_setting = current_user.user_setting ||
                    UserSetting.find_or_create_by!(user: current_user)

    if @user_setting.update(notification_settings_params)
      redirect_to notification_settings_settings_path,
                  notice: t("user_settings.notification_settings.update_success"),
                  status: :see_other
    else
      @line_connected = current_user.line_user_id.present?
      render :notification_settings, status: :unprocessable_entity
    end
  end

  # ==============================================================================
  # G-4 追加: rest_mode（GET /settings/rest_mode）
  # ==============================================================================
  #
  # 【役割】お休みモード設定ページ（22番）を表示する。
  #
  # 【@habits について】
  #   お休みモード設定ページでは「この習慣にお休みモードを適用するか」を
  #   allow_rest_mode カラムで管理している。
  #   ユーザーのアクティブな習慣一覧を表示して、どの習慣が対象かを示す。
  #
  # 【@rest_mode_active について】
  #   現在お休みモード中かどうかを真偽値で渡す。
  #   ビュー側で「開始ボタン」か「終了ボタン」のどちらを表示するかを決める。
  def rest_mode
    @user_setting   = current_user.user_setting ||
                      UserSetting.find_or_create_by!(user: current_user)

    # アクティブな習慣一覧を取得する（allow_rest_mode の状況確認用）
    # includes(:habit_excluded_days) は不要（ここでは表示のみのため）
    @habits         = current_user.habits.active

    # 現在お休みモード中かどうかを判定する
    # UserSetting#rest_mode_active? が既に定義されている（B-3 で実装済み）
    @rest_mode_active = @user_setting.rest_mode_active?
  end

  # ==============================================================================
  # G-4 追加: start_rest_mode（POST /settings/rest_mode）
  # ==============================================================================
  #
  # 【役割】お休みモードを開始する。
  #   rest_mode_until と rest_mode_reason を保存し、
  #   ダッシュボードで「😴 休息中」バッジを表示できるようにする。
  #
  # 【バリデーション】
  #   rest_mode_until が空の場合: エラーを表示してページを再描画する。
  #   rest_mode_until が過去の日付の場合: 同様にエラー。
  #   これはサーバー側でチェックすることで、JS 無効環境でも安全。
  #
  # 【status: :see_other について】
  #   Turbo（Rails 7 デフォルト）では POST/PATCH/DELETE のリダイレクトは
  #   303 See Other が必要。302 だと Turbo が POST のまま追跡してしまう。
  def start_rest_mode
    @user_setting = current_user.user_setting ||
                    UserSetting.find_or_create_by!(user: current_user)

    until_date_str = params[:user_setting]&.fetch(:rest_mode_until, nil)

    # ── バリデーション: rest_mode_until が空の場合 ──────────────────
    # Date.parse は文字列が不正だと ArgumentError を発生させるため
    # rescue で catch して適切にエラー処理する
    begin
      until_date = Date.parse(until_date_str.to_s)
    rescue ArgumentError, TypeError
      until_date = nil
    end

    if until_date.blank? || until_date < Date.current
      @habits         = current_user.habits.active
      @rest_mode_active = @user_setting.rest_mode_active?
      flash.now[:alert] = t("user_settings.rest_mode.invalid_date")
      render :rest_mode, status: :unprocessable_entity
      return
    end

    # rest_mode_until は日付の終わり（23:59:59 JST）を end_of_day で設定する。
    # 【理由】
    #   Date.parse("2026-03-20") は date オブジェクトを返す。
    #   DB には datetime 型（rest_mode_until）で保存するため
    #   in_time_zone.end_of_day で「その日の最後の瞬間」に変換する。
    #   こうすることで「2026-03-20 23:59:59 JST」まで有効になる。
    rest_mode_until_datetime = until_date.in_time_zone.end_of_day

    # rest_mode_reason は任意入力なので presence: true は不要
    rest_mode_reason = params[:user_setting]&.fetch(:rest_mode_reason, nil)&.strip

    if @user_setting.update(
      rest_mode_until:  rest_mode_until_datetime,
      rest_mode_reason: rest_mode_reason
    )
      # 開始後は REM 設定ページ自体にリダイレクトして現在の状態を表示する
      redirect_to rest_mode_settings_path,
                  notice: t("user_settings.rest_mode.started",
                             until_date: l(until_date, format: :long)),
                  status: :see_other
    else
      @habits           = current_user.habits.active
      @rest_mode_active = @user_setting.rest_mode_active?
      render :rest_mode, status: :unprocessable_entity
    end
  end

  # ==============================================================================
  # G-4 追加: stop_rest_mode（DELETE /settings/rest_mode）
  # ==============================================================================
  #
  # 【役割】お休みモードを手動で終了する。
  #   rest_mode_until を nil に設定することで即時解除する。
  #
  # 【REST 設計の観点】
  #   お休みモードの「終了」は「お休み期間の削除」と捉えられるため
  #   HTTP DELETE メソッドを使う。
  #
  # 【修正理由】
  #   update_columns はバリデーション・コールバック・updated_at をすべてスキップする。
  #   将来 after_update コールバックが追加されたとき、
  #   update_columns だとそのコールバックが実行されず本番が壊れる可能性がある。
  #   REST モードの解除は通常の update! で十分。

  def stop_rest_mode
    @user_setting = current_user.user_setting ||
                    UserSetting.find_or_create_by!(user: current_user)

    # update! を使う理由:
    #   バリデーションとコールバックを正常に実行する。
    #   将来 after_update で streak を再計算する処理を追加しても安全。
    #   update_columns と違い updated_at も自動更新される。
    @user_setting.update!(
      rest_mode_until:  nil,
      rest_mode_reason: nil
    )

    redirect_to rest_mode_settings_path,
                notice: t("user_settings.rest_mode.stopped"),
                status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    # update! が失敗した場合（想定外のバリデーションエラー）
    Rails.logger.error "[stop_rest_mode] 更新失敗: #{e.message}"
    redirect_to rest_mode_settings_path,
                alert: "終了処理に失敗しました。もう一度お試しください。",
                status: :see_other
  end

  private

  # ==============================================================================
  # notification_settings_params（Strong Parameters）
  # ==============================================================================
  def notification_settings_params
    params.require(:user_setting).permit(
      :notification_enabled,
      :line_notification_enabled,
      :email_notification_enabled,
      :weekly_report_enabled,
      :daily_notification_limit
    )
  end
end