# app/controllers/settings_controller.rb
#
# ==============================================================================
# SettingsController: アカウント設定・退会処理を担当するコントローラー
# ==============================================================================
#
# 【アクション一覧】
#   GET    /settings → show:    設定ページを表示
#   DELETE /settings → destroy: 退会処理を実行
#
# 【G-5 での変更内容】
#   show アクションに CSV エクスポート用の件数取得を追加。
#   View 側でボタンの data-turbo を動的に切り替えるために使用する。
# ==============================================================================
class SettingsController < ApplicationController

  before_action :require_login
  before_action :set_user

  # ==============================================================================
  # show: 設定ページを表示する
  # GET /settings
  # ==============================================================================
  def show
    # G-4 追加: お休みモードの状態表示に使う
    @user_setting = current_user.user_setting

    # ──────────────────────────────────────────────────────────────────────────
    # G-5 追加: CSV エクスポートボタンの data-turbo を動的に切り替えるために
    # 各データの件数を取得してインスタンス変数に渡す。
    #
    # 【なぜ View ではなくコントローラで件数を取得するのか】
    #   View（ERBテンプレート）の中でDBクエリを発行するのは
    #   責任分離の観点から良くない（FatView アンチパターン）。
    #   コントローラで取得してインスタンス変数で渡すのが Rails の正しい作法。
    #
    # 【なぜ CsvExportService を使わないのか】
    #   サービスクラスのインスタンス化は1回のアクションで1回にすべき。
    #   件数取得だけなら直接クエリを書く方がシンプルで N+1 も起きない。
    #   deleted_at: nil の条件は schema.rb のカラム定義に基づいている。
    # ──────────────────────────────────────────────────────────────────────────
    @habit_record_count        = current_user.habit_records.where(deleted_at: nil).count
    @task_count                = current_user.tasks.where(deleted_at: nil).count
    @weekly_reflection_count   = current_user.weekly_reflections.count
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
      redirect_to root_path, notice: t("settings.destroy.success")
    else
      redirect_to settings_path, alert: result[:error] || t("settings.destroy.failure")
    end
  end

  private

  def set_user
    @user = current_user
  end
end