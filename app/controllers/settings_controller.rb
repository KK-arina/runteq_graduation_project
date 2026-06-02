# app/controllers/settings_controller.rb
#
# ==============================================================================
# SettingsController: アカウント設定・退会処理を担当するコントローラー
# ==============================================================================
#
# 【アクション一覧】
#   GET    /settings → show:    設定ページを表示
#   DELETE /settings → destroy: 退会処理を実行
# ==============================================================================

class SettingsController < ApplicationController
  # before_action :require_login
  #   ログインしていないユーザーをログインページへリダイレクトする。
  #   ApplicationController で定義された共通メソッド。
  before_action :require_login

  # ==============================================================================
  # show: 設定ページを表示する
  # GET /settings
  # ==============================================================================
  def show
    # @user: 現在ログイン中のユーザーオブジェクト
    # current_user は ApplicationController で定義されたヘルパーメソッド
    @user = current_user
  end

  # ==============================================================================
  # destroy: 退会処理を実行する
  # DELETE /settings
  # ==============================================================================
  #
  # 【処理フロー】
  #   1. UserDestroyService で個人情報の匿名化・セキュリティデータ削除を実行
  #   2. 成功時: セッション・Cookie を全削除してトップページへリダイレクト
  #   3. 失敗時: 設定ページへリダイレクトしてエラーを表示
  def destroy
    result = UserDestroyService.new(user: current_user).call

    if result[:success]
      # ─── 退会成功時の処理 ────────────────────────────────────────────────────

      # reset_session でセッションを全削除する
      reset_session

      # Cookie削除: each_key は CookieJar では使えないため
      # 既知のCookieキーを個別に削除する
      #
      # 【なぜ each_key が使えないのか】
      #   ActionDispatch::Cookies::CookieJar は each_key を実装していない。
      #   セッションは reset_session で削除済みなので
      #   追加のCookie削除は不要だが、念のため _habitflow_session を明示削除する。
      cookies.delete(:_habitflow_session)

      redirect_to root_path, notice: t("settings.destroy.success")
    else
      redirect_to settings_path, alert: result[:error] || t("settings.destroy.failure")
    end
  end

  before_action :set_user

  private

  def set_user
    @user = current_user
  end
end