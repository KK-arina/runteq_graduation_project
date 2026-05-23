# app/controllers/pages_controller.rb
#
# 【このファイルの役割】
#   静的ページ（トップページ・利用規約・プライバシーポリシー）と、
#   開発環境でのエラーページ確認用アクションを管理する。
#
# 【F-3 での変更内容】
#   /terms と /privacy の静的ページアクションを追加した。
#   未ログインでも閲覧できるよう before_action を設定しない（デフォルト）。

class PagesController < ApplicationController
  # ============================================================
  # トップページ
  # ============================================================
  # GET /
  def index
    if logged_in?
      redirect_to dashboard_path
    end
  end

  # ============================================================
  # F-3 追加: 利用規約ページ
  # ============================================================
  # GET /terms
  #
  # 【なぜ before_action :require_login を付けないのか】
  #   利用規約は「登録前のユーザー」「未ログインユーザー」も
  #   閲覧できる必要がある（法規上の要件）。
  #   ApplicationController の redirect_to_onboarding_if_needed は
  #   controller_name で "pages" を除外済みのため未ログインでもアクセス可能。
  #   redirect_to_terms_agreement_if_needed も terms_path を許可リストに入れているため
  #   未同意ユーザーもアクセスできる。
  def terms
    # ビューを表示するだけ（インスタンス変数の設定は不要）
  end

  # ============================================================
  # F-3 追加: プライバシーポリシーページ
  # ============================================================
  # GET /privacy
  #
  # 利用規約と同じ理由で未ログインでも閲覧可能にする。
  def privacy
    # ビューを表示するだけ（インスタンス変数の設定は不要）
  end

  # ============================================================
  # Issue #27: エラーページ確認用アクション（開発環境のみ使用）
  # ============================================================
  def error_404
    render_404
  end

  def error_422
    render_422
  end

  def error_500
    render template: "errors/internal_server_error",
           layout: "application",
           status: :internal_server_error
  end
end