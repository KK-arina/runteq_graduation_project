# app/controllers/user_settings_controller.rb
#
# ==============================================================================
# UserSettingsController（G-3 新規作成）
# ==============================================================================
#
# 【このコントローラーの役割】
#   user_settings テーブルの通知設定を表示・更新する。
#   SettingsController（アカウント情報・退会）とは責務が異なるため分離する。
#
# 【SettingsController との違い】
#   SettingsController  : @user の表示・退会処理
#   UserSettingsController: user_settings の通知設定管理
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
  #
  # 【@user_setting の取得方法について】
  #   user_settings レコードは User#after_create で自動作成されるため
  #   通常は必ず存在する。
  #   ただし古いアカウントや何らかの事情でレコードがない場合に備えて
  #   || 演算子で「なければ作る」ようにする。
  #
  #   【なぜ GETアクション内で create! でなく find_or_create_by を使うのか】
  #     create! は GETリクエスト（画面を開いただけ）でDBに書き込むため
  #     RESTful の原則（GETは副作用なし）に反する。
  #     find_or_create_by はレコードが存在すれば取得、なければ作成する
  #     1メソッドで完結する安全な方法。
  #     ただし同時リクエストが重なると稀に重複作成する可能性があるため
  #     DB に UNIQUE 制約（user_settings.user_id）があることが前提。
  def notification_settings
    @user_setting = current_user.user_setting ||
                    UserSetting.find_or_create_by!(user: current_user)

    # LINE 通知連携済みかどうかを判定する。
    #
    # 【line_user_id について】
    #   G-1 の OmniauthCallbacksController#save_line_user_id で
    #   LINE ログイン時に users.line_user_id に LINE の userId が保存される。
    #   line_user_id が存在する = LINE ログイン済み = LINE 通知が送れる状態。
    #
    #   ※ LINE ログイン（users.uid）と LINE 通知（users.line_user_id）は
    #     G-1 の設計で同一の LINE userId を使うため、
    #     LINE ログインさえすれば通知も使える。
    @line_connected = current_user.line_user_id.present?
  end

  # ==============================================================================
  # update_notification_settings（PATCH /settings/notification_settings）
  # ==============================================================================
  #
  # 【役割】通知設定フォームの内容を user_settings テーブルに保存する。
  #
  # 【成功時】同じページにリダイレクトして flash[:notice] でトースト通知を表示。
  # 【失敗時】バリデーションエラーを表示して同じページを再描画（422）。
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

  private

  # ==============================================================================
  # notification_settings_params（Strong Parameters）
  # ==============================================================================
  #
  # 【役割】フォームから送られてくるパラメータのうち、更新を許可するものだけを指定する。
  #
  # 【なぜ Strong Parameters が必要なのか（セキュリティ）】
  #   悪意あるユーザーがブラウザの開発者ツール等で
  #   ai_analysis_count（AI使用回数）などを改ざんして送信してきても
  #   DB に書き込まれないようにするための防御策。
  #   ここで許可した5つのカラムのみ更新可能とする。
  #
  # 【各パラメータの説明】
  #   notification_enabled:       通知全体の ON/OFF（マスタスイッチ）
  #   line_notification_enabled:  LINE 通知の ON/OFF
  #   email_notification_enabled: メール通知の ON/OFF
  #   weekly_report_enabled:      週次レポートメールの ON/OFF
  #   daily_notification_limit:   1日の最大通知数（integer: 1〜10）
  #
  # 【boolean カラムとチェックボックスの関係】
  #   Rails の check_box ヘルパーは「チェックなし」でも
  #   hidden input で "0" を送信するため、
  #   未チェック = false が確実に DB に保存される。
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