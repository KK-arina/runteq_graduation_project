# app/controllers/settings_controller.rb
#
# ==============================================================================
# SettingsController: アカウント設定・退会処理を担当するコントローラー
# ==============================================================================
#
# 【アクション一覧】
#   GET    /settings           → show:            設定ページを表示
#   DELETE /settings           → destroy:         退会処理を実行
#   PATCH  /settings/profile   → update_profile:  ユーザー名を更新（G-6追加）
#   PATCH  /settings/timezone  → update_timezone: タイムゾーンを更新（G-6追加）
#   DELETE /settings/line      → disconnect_line: LINE通知連携を解除（G-6追加）
#
# 【G-5 での変更内容】
#   show アクションに CSV エクスポート用の件数取得を追加。
#
# 【G-6 での変更内容】
#   update_profile / update_timezone / disconnect_line アクションを追加。
#   show アクションに @line_connected / @current_timezone / @ai_usage_rate を追加。
# ==============================================================================
class SettingsController < ApplicationController

  before_action :require_login
  before_action :set_user

  # ==============================================================================
  # show: 設定ページを表示する
  # GET /settings
  # ==============================================================================
  def show
    # G-4 由来: お休みモードの状態表示に使う
    # find_or_create_by! を使う理由:
    #   after_create コールバックで UserSetting を自動生成しているが、
    #   万が一レコードが存在しない場合でも安全にレコードを取得・生成できる。
    @user_setting = current_user.user_setting ||
                    UserSetting.find_or_create_by!(user: current_user)

    # G-6 追加: LINE連携状態を確認する
    # User#line_connected? を使う理由:
    #   「LINEログイン連携」と「LINE通知連携」の2パターンを統合して
    #   判定するロジックをモデルに持たせ、コントローラをシンプルに保つ。
    @line_connected = current_user.line_connected?

    # G-6 追加: タイムゾーン設定の現在値を取得する
    # "Asia/Tokyo" をデフォルトにする理由:
    #   user_settings テーブルの time_zone カラムに値がない場合（初期状態）でも
    #   日本ユーザー向けの適切なデフォルトを表示するため。
    @current_timezone = @user_setting.time_zone.presence || "Asia/Tokyo"

    # G-6 追加: AI使用状況を取得する
    # user_settings テーブルから直接取得する理由:
    #   ai_analysis_count は D-6 で実装済みのカラム。
    #   WeeklyReflection から集計し直すより user_settings の値を読む方が
    #   クエリが1本で済み、かつ実装済みの仕様（月次リセット等）と整合する。
    @ai_analysis_count         = @user_setting.ai_analysis_count
    @ai_analysis_monthly_limit = @user_setting.ai_analysis_monthly_limit

    # プログレスバーの幅（%）を計算する
    # [計算値, 100].min の理由:
    #   万が一 ai_analysis_count が monthly_limit を超えた場合でも
    #   バーが100%を超えて表示が崩れないようにする。
    # ゼロ除算（ZeroDivisionError）防止:
    #   monthly_limit が 0 の場合は 0% を返す。
    @ai_usage_rate = if @ai_analysis_monthly_limit > 0
                       [(@ai_analysis_count.to_f / @ai_analysis_monthly_limit * 100).round, 100].min
                     else
                       0
                     end

    # G-5 由来: CSV エクスポートボタンの表示制御（1000件超で非同期切替）に使う
    # コントローラで件数を取得する理由:
    #   View 内でDBクエリを発行するのは責任分離の観点から望ましくない
    #   （FatView アンチパターン）。コントローラで取得してViewに渡す。
    @habit_record_count      = current_user.habit_records.where(deleted_at: nil).count
    @task_count              = current_user.tasks.where(deleted_at: nil).count
    @weekly_reflection_count = current_user.weekly_reflections.count
  end

  # ==============================================================================
  # G-6 追加: update_profile: ユーザー名をインライン編集する
  # PATCH /settings/profile
  # ==============================================================================
  #
  # 【render :show ではなく redirect_to を使う理由】
  #   render :show を使うと、show アクションで設定する約10個のインスタンス変数を
  #   このアクション内でも全て再定義する必要があり、記述漏れによる
  #   NoMethodError が発生しやすい。
  #   エラー内容は flash で渡してリダイレクトする方が安全で保守しやすい。
  #
  # 【status: :see_other (HTTP 303) を使う理由】
  #   Rails 7 + Turbo Drive の環境では、PATCH/DELETE リクエスト後の
  #   redirect_to に 303 を使わないと Turbo が PATCH のまま追従してしまう。
  #   303 で GET リクエストとして追従させることで正しくページが描画される。
  def update_profile
    if @user.update(profile_params)
      redirect_to settings_path,
                  notice: t("settings.update_profile.success"),
                  status: :see_other
    else
      # バリデーションエラー（空文字・50文字超等）の場合
      # full_messages を join して flash[:alert] で渡す
      redirect_to settings_path,
                  alert: @user.errors.full_messages.join("、"),
                  status: :see_other
    end
  end

  # ==============================================================================
  # G-6 追加: update_timezone: タイムゾーンを更新する
  # PATCH /settings/timezone
  # ==============================================================================
  #
  # 【ActiveSupport::TimeZone[timezone] でホワイトリストチェックする理由】
  #   任意の文字列を time_zone に保存すると Time.use_zone 等で
  #   ArgumentError が発生してアプリ全体がエラーになる危険がある。
  #   ActiveSupport::TimeZone[] は有効なタイムゾーン名なら TimeZone オブジェクトを返し、
  #   無効なら nil を返すので、ホワイトリスト検証として使える。
  def update_timezone
    user_setting = current_user.user_setting ||
                   UserSetting.find_or_create_by!(user: current_user)

    # params[:time_zone] を文字列として安全に取り出す
    # .to_s を使う理由: params の値は nil の場合があり、nil.to_s = "" になるため
    timezone = params[:time_zone].to_s.strip

    unless ActiveSupport::TimeZone[timezone]
      redirect_to settings_path,
                  alert: t("settings.update_timezone.invalid"),
                  status: :see_other
      return
    end

    if user_setting.update(time_zone: timezone)
      redirect_to settings_path,
                  notice: t("settings.update_timezone.success"),
                  status: :see_other
    else
      redirect_to settings_path,
                  alert: t("settings.update_timezone.failure"),
                  status: :see_other
    end
  end

  # ==============================================================================
  # G-6 追加: disconnect_line: LINE通知連携を解除する
  # DELETE /settings/line
  # ==============================================================================
  #
  # 【解除対象について】
  #   このアクションは users.line_user_id（LINE Messaging API通知用）のみを
  #   nil に設定する。
  #   users.provider / users.uid（LINEログイン認証用）は変更しない。
  #   理由: LINEログインと LINE通知は独立した機能であり、
  #         通知だけを解除してもログインには影響しない設計にしている。
  #
  # 【LINEログインユーザーのガード】
  #   provider == "line_v2_1" のユーザーは LINE がログイン手段になっている。
  #   line_user_id は provider=line_v2_1 の uid と同値のため、
  #   nil にしても LINE通知は実質的に無効化される。
  #   ただし誤操作によるロックアウトリスクを避けるため、
  #   LINEログインユーザーには解除を許可しない設計にしている。
  #
  # 【update! ではなく update を使う理由】
  #   line_user_id は null: true なのでバリデーションの問題は起きない。
  #   update は失敗時に false を返し rescue 不要でシンプルに書ける。
  #   ただし予期しない DB エラーに備えて rescue を残す。
  def disconnect_line
    # LINEログインユーザーは解除不可（ロックアウト防止）
    if @user.provider == "line_v2_1"
      redirect_to settings_path,
                  alert: t("settings.disconnect_line.login_user_error"),
                  status: :see_other
      return
    end

    if @user.update(line_user_id: nil)
      redirect_to settings_path,
                  notice: t("settings.disconnect_line.success"),
                  status: :see_other
    else
      redirect_to settings_path,
                  alert: t("settings.disconnect_line.failure"),
                  status: :see_other
    end
  rescue => e
    Rails.logger.error "[SettingsController#disconnect_line] 失敗: #{e.message}"
    redirect_to settings_path,
                alert: t("settings.disconnect_line.failure"),
                status: :see_other
  end

  # ==============================================================================
  # destroy: 退会処理を実行する
  # DELETE /settings
  # ==============================================================================
  def destroy
    result = UserDestroyService.new(user: current_user).call
    if result[:success]
      reset_session
      cookies.delete(:_habitflow_session)
      redirect_to root_path,
                  notice: t("settings.destroy.success"),
                  status: :see_other
    else
      redirect_to settings_path,
                  alert: result[:error] || t("settings.destroy.failure"),
                  status: :see_other
    end
  end

  private

  def set_user
    @user = current_user
  end

  # profile_params: ユーザー名更新に使う Strong Parameters
  #
  # 【permit(:name) だけにする理由】
  #   プロフィール編集フォームでは name のみを更新する。
  #   params.require(:user) で user キー配下の name だけを許可し、
  #   email / password 等への意図しない書き込みを防ぐ（Mass Assignment 防止）。
  def profile_params
    params.require(:user).permit(:name)
  end
end