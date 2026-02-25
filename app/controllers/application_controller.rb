# app/controllers/application_controller.rb
#
# ApplicationController は全コントローラーの親クラスです。
# ここに定義したメソッドはアプリ全体で共有されます。
# helper_method に登録したメソッドはビュー(ERBファイル)からも呼び出せます。

class ApplicationController < ActionController::Base
  # ============================================================
  # セキュリティ設定
  # ============================================================

  # モダンなブラウザのみアクセスを許可するRails標準の設定
  allow_browser versions: :modern

  # ============================================================
  # Issue #27: カスタムエラーハンドリングの設定
  # ============================================================
  # rescue_from: 指定した例外が発生したときに呼び出すメソッドを登録する。
  # 例外がコントローラー内のどこで発生しても、ここで一括して捕まえることができる。

  # ActiveRecord::RecordNotFound:
  #   find(id) で該当レコードがDBに存在しない場合に Rails が発生させる例外。
  #   例: /habits/99999 にアクセスしたが id=99999 の習慣が存在しない場合。
  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  # ActionController::InvalidAuthenticityToken:
  #   CSRFトークンが不正なときに発生する例外。
  #   例: 古いタブからフォームを送信した場合。
  rescue_from ActionController::InvalidAuthenticityToken, with: :render_422

  # StandardError（本番環境のみ）:
  #   上記以外の予期しないエラー全般。
  #
  # 【なぜ本番環境限定にするのか】
  #   rescue_from StandardError を全環境で有効にすると、
  #   開発中のバグ（typoやnilエラーなど）まで全部 500ページとして表示されてしまい、
  #   どの行でどんなエラーが起きたかが分からなくなる。
  #   開発・テスト環境では Rails デフォルトのデバッグ画面（行番号・スタックトレース付き）
  #   を使うほうが圧倒的にデバッグしやすい。
  #   そのため production のみ有効にするのが実務の標準的な設計。
  rescue_from StandardError, with: :render_500 if Rails.env.production?

  # ============================================================
  # ヘルパーメソッドの登録
  # ============================================================
  # helper_method に登録すると、ビュー(ERBファイル)でも
  # このメソッドを呼び出せるようになります。
  helper_method :current_user, :logged_in?, :locked?

  # ============================================================
  # Private メソッド（コントローラー内部でのみ使用）
  # ============================================================
  private

  # ----------------------------------------------------------
  # current_user
  # ----------------------------------------------------------
  # セッションに保存された user_id を元に、現在ログイン中の
  # ユーザーを取得して返します。
  # ||= を使ってメモ化しています。同じリクエスト内で2回以上呼ばれても
  # DBへの問い合わせは1回だけです。
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # ----------------------------------------------------------
  # logged_in?
  # ----------------------------------------------------------
  # ログイン済みかどうかを true/false で返します。
  def logged_in?
    current_user.present?
  end

  # ----------------------------------------------------------
  # require_login
  # ----------------------------------------------------------
  # before_action として使用します。
  # ログインしていない場合はログインページにリダイレクトします。
  def require_login
    unless logged_in?
      flash[:alert] = "ログインしてください"
      redirect_to login_path
    end
  end

  # ============================================================
  # PDCA強制ロック判定
  # ============================================================

  def locked?
    return false unless logged_in?

    now = Time.current
    this_monday_4am = Date.current
                          .beginning_of_week(:monday)
                          .in_time_zone
                          .change(hour: 4, min: 0, sec: 0)
    return false if now < this_monday_4am

    last_week_start = HabitRecord.today_for_record
                                 .beginning_of_week(:monday) - 1.week

    last_week_reflection = current_user.weekly_reflections
                                       .find_by(week_start_date: last_week_start)
    return false if last_week_reflection.nil?

    last_week_reflection.pending?
  end

  # ----------------------------------------------------------
  # require_unlocked
  # ----------------------------------------------------------
  def require_unlocked
    return unless locked?

    respond_to do |format|
      format.html do
        flash[:alert] = "先週の振り返りが未完了のため、この操作はできません。先に振り返りを完了してください。"
        redirect_back fallback_location: habits_path
      end
      format.turbo_stream do
        head :locked
      end
      format.json do
        render json: { error: "locked" }, status: :locked
      end
    end
  end

  # ============================================================
  # Issue #27: カスタムエラーページ表示メソッド
  # ============================================================

  # ----------------------------------------------------------
  # render_404
  # ----------------------------------------------------------
  # 404 Not Found エラー時に呼ばれます。
  # rescue_from ActiveRecord::RecordNotFound と
  # routes.rb の catch-all（match "*path"）から呼ばれます。
  def render_404(exception = nil)
    # Rails.logger.info:
    #   ログレベル「info」で記録する。
    #   Renderのログや開発環境のターミナルで確認できる。
    #   exception&.message の & はnilセーフ演算子で、
    #   exception が nil でも NoMethodError にならないようにする。
    Rails.logger.info "404 Not Found: #{exception&.message}"
    render_error_page("errors/not_found", :not_found)
  end

  # ----------------------------------------------------------
  # render_422
  # ----------------------------------------------------------
  # 422 Unprocessable Entity エラー時に呼ばれます。
  # セキュリティ上重要なイベントなので logger.warn（警告レベル）で記録します。
  def render_422(exception = nil)
    Rails.logger.warn "422 Unprocessable Entity: #{exception&.message}"
    render_error_page("errors/unprocessable", :unprocessable_entity)
  end

  # ----------------------------------------------------------
  # render_500
  # ----------------------------------------------------------
  # 500 Internal Server Error エラー時に呼ばれます。
  # rescue_from StandardError（本番環境のみ有効）から呼ばれます。
  # 開発・テスト環境では rescue_from 自体が無効なので、このメソッドは呼ばれません。
  def render_500(exception = nil)
    # logger.error:
    #   ログレベル「error」で記録する。予期しないエラーが起きたときに
    #   すぐに気づけるよう、最も高い重要度でログを残す。
    # backtrace&.first(5):
    #   エラーが発生したファイルと行番号を最大5行記録する。
    #   スタックトレース全体は長すぎるので先頭5行だけ取得する。
    Rails.logger.error "500 Internal Server Error: #{exception&.message}"
    Rails.logger.error exception&.backtrace&.first(5)&.join("\n")
    render_error_page("errors/internal_server_error", :internal_server_error)
  end

  # ----------------------------------------------------------
  # render_error_page（共通ヘルパー）
  # ----------------------------------------------------------
  # render_404 / render_422 / render_500 から呼ばれる共通処理。
  # DRY（Don't Repeat Yourself）の原則に従い、
  # 同じ render の書き方を3回書かないために切り出している。
  #
  # template: "errors/not_found" のような文字列
  #           → app/views/errors/not_found.html.erb を指す
  # status:   :not_found / :unprocessable_entity / :internal_server_error など
  #           → HTTP ステータスコードをシンボルで指定する
  def render_error_page(template, status)
    render template: template, layout: "application", status: status
  end
end