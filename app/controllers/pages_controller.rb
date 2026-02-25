# app/controllers/pages_controller.rb
#
# 【このファイルの役割】
#   静的ページ（トップページ）と、開発環境でのエラーページ確認用アクションを管理する。

class PagesController < ApplicationController
  # ============================================================
  # トップページ
  # ============================================================
  # GET /
  # ログイン済みならダッシュボードへリダイレクト。
  # 未ログインならランディングページを表示。
  def index
    if logged_in?
      redirect_to dashboard_path
    end
  end

  # ============================================================
  # Issue #27: エラーページ確認用アクション（開発環境のみ使用）
  # ============================================================
  # routes.rb の if Rails.env.development? ブロック内にのみ定義されているため、
  # 本番環境ではこれらのURLは存在しない。

  # GET /errors/404
  def error_404
    # render_404 は ApplicationController で定義したメソッド。
    # 404ページの見た目を開発環境で確認するために呼び出す。
    render_404
  end

  # GET /errors/422
  def error_422
    render_422
  end

  # GET /errors/500
  def error_500
    # 【重要】render file: ではなく render template: を使う。
    #
    # render file: との違い:
    #   render file:     → ファイルをそのままテキストとして返す場合がある。
    #                       ERB として処理されず、コードが画面にそのまま表示されてしまう。
    #   render template: → Rails が ERB テンプレートとして正しく処理して HTML を生成する。
    #
    # なぜ render_500 を直接呼ばないのか:
    #   render_500 は Rails.env.development? のとき raise するため、
    #   開発環境でこのアクションから呼ぶとデバッグ画面になってしまう。
    #   ここでは「500ページの見た目だけを確認したい」ので
    #   render template: で直接ビューを表示する。
    render template: "errors/internal_server_error",
           layout: "application",
           status: :internal_server_error
  end
end