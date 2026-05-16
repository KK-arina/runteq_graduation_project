# app/controllers/application_controller.rb
#
# ============================================================
# 【このファイルの役割】
# ApplicationController は全コントローラーの親クラスです。
# ここに定義したメソッドはアプリ全体で共有されます。
# helper_method に登録したメソッドはビュー(ERBファイル)からも呼び出せます。
#
# ============================================================
# Issue #28: セキュリティ対策の実装状況まとめ
# ============================================================
#
# 【1. CSRF対策】
#   Rails の ActionController::Base を継承すると、
#   CSRF保護が自動的に有効になる。
#   具体的には:
#   - フォーム送信時に authenticity_token（ランダムなトークン）を埋め込む
#   - サーバーはトークンを検証し、不正なリクエストを 422 で拒否する
#   - application.html.erb の csrf_meta_tags がそのトークンを HTML に出力している
#   - SessionsController#create / #destroy で reset_session を呼んでいるため、
#     ログイン時にセッション固定攻撃も防いでいる
#
# 【2. SQLインジェクション対策】
#   Active Record のクエリメソッド（where, find, find_by など）は
#   内部でプレースホルダー（? や :name）を使ってSQLを組み立てるため、
#   ユーザー入力が SQL として実行されることはない。
#   このアプリでは生SQL（execute や find_by_sql）を使っていないため安全。
#
# 【3. XSS対策（クロスサイトスクリプティング）】
#   Rails の ERB テンプレートは <%= %> で出力する文字列を
#   自動的に HTML エスケープする。
#   例: <script>alert('XSS')</script> → &lt;script&gt;...&lt;/script&gt;
#   raw() や html_safe を意図的に使わない限り、XSSは発生しない。
#   また config/environments/production.rb で X-XSS-Protection ヘッダーも設定済み。
#
# 【4. Strong Parameters】
#   各コントローラーで params.require().permit() を使い、
#   許可するパラメータを明示的に指定している（ホワイトリスト方式）。
#   これにより、攻撃者が意図しないカラム（admin: true など）を
#   フォームから書き換えることを防いでいる。
#
# 【5. セッション管理】
#   - config/application.rb で Cookie のセキュリティ設定を明示化
#     (secure, httponly, same_site: :lax, expire_after: 30.days)
#   - ログイン時: reset_session でセッション固定攻撃を防止
#   - ログアウト時: reset_session でセッションデータを完全消去
#   - current_user は session[:user_id] からのみ取得（JWT等は使わない）
# ============================================================

class ApplicationController < ActionController::Base
  # ============================================================
  # セキュリティ設定
  # ============================================================

  # allow_browser versions: :modern
  #   古いブラウザ（セキュリティアップデートが止まったもの）からの
  #   アクセスをブロックする Rails 7.1 以降の機能。
  #   モダンブラウザのみを許可することで、
  #   古いブラウザの脆弱性を突いた攻撃リスクを低減する。
  allow_browser versions: :modern

  # ============================================================
  # Issue #27: カスタムエラーハンドリングの設定
  # ============================================================
  # rescue_from: 指定した例外が発生したときに呼び出すメソッドを登録する。
  # 例外がコントローラー内のどこで発生しても、ここで一括して捕まえることができる。

  # ActiveRecord::RecordNotFound:
  #   find(id) で該当レコードがDBに存在しない場合に Rails が発生させる例外。
  #   例: /habits/99999 にアクセスしたが id=99999 の習慣が存在しない場合。
  rescue_from ActiveRecord::RecordNotFound,               with: :render_404

  # ActionController::InvalidAuthenticityToken:
  #   CSRFトークンが不正なときに発生する例外。
  rescue_from ActionController::InvalidAuthenticityToken, with: :render_422

  # StandardError（本番環境のみ）:
  #   上記以外の予期しないエラー全般。
  #   開発・テスト環境では Rails デフォルトのデバッグ画面を使うほうがデバッグしやすい。
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
  #
  # 【セキュリティ上の意味】
  # session[:user_id] は Rails が暗号化した Cookie から取得する。
  # 攻撃者が Cookie を改ざんしても、復号に失敗するため user_id を
  # 書き換えることはできない（Rails の暗号化セッションの恩恵）。
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
  # require_login（E-4 変更: redirect_to パラメータ対応を追加）
  # ----------------------------------------------------------
  # ログインしていないユーザーをログインページへリダイレクトします。
  #
  # 【E-4 変更内容】
  #   未ログインユーザーがアクセスしようとしたパス（request.fullpath）を
  #   クエリパラメータ redirect_to として /login に付与する。
  #   例: /weekly_reflections/new にアクセス
  #       → /login?redirect_to=%2Fweekly_reflections%2Fnew にリダイレクト
  #
  # 【なぜ request.fullpath を使うのか】
  #   request.fullpath は現在アクセスしようとしているパスとクエリ文字列を
  #   すべて含む文字列を返す。
  #   例: "/weekly_reflections/new" や "/tasks?tab=must" など。
  #
  # 【なぜ safe_redirect_path? チェックが必要なのか（オープンリダイレクト防止）】
  #   redirect_to パラメータは URL に含まれるため、攻撃者が
  #   /login?redirect_to=http://evil.com のように外部URLを指定できてしまう。
  #   ログイン後に外部の悪意あるサイトへ飛ばされる「オープンリダイレクト攻撃」を防ぐため、
  #   必ず「自アプリ内のパスかどうか」を検証してから遷移する。
  #
  # 【D-7 追加: 初回ログインユーザーをオンボーディングへリダイレクト】
  #   ログイン済みかつ first_login_at が NULL のユーザーを
  #   オンボーディングページへリダイレクトする処理は変更なし。
  def require_login
    unless logged_in?
      flash[:alert] = "ログインしてください"

      # ── E-4 追加: アクセスしようとしたパスをクエリパラメータとして付与する ──
      #
      # login_path(redirect_to: request.fullpath):
      #   Rails のルーティングヘルパーにキーワード引数を渡すと、
      #   自動的にクエリパラメータとして URL に追加してくれる。
      #   結果: "/login?redirect_to=%2Fweekly_reflections%2Fnew"
      #   (%2F は / を URL エンコードしたもの。Rails が自動で行う)
      redirect_to login_path(redirect_to: request.fullpath)
      return
    end

    # D-7 追加: 初回ログインユーザーをオンボーディングへリダイレクトする
    redirect_to_onboarding_if_needed
  end

  # ============================================================
  # PDCA強制ロック判定
  # ============================================================

  # locked?
  #   月曜AM4:00以降かつ前週の振り返りが未完了の場合に true を返す。
  #
  # 【最終的なSQLの流れ】
  #   1. SELECT 1 FROM weekly_reflections WHERE user_id=? AND week_start_date=? LIMIT 1
  #      → 前週レコードの存在確認（EXISTS）
  #   2. SELECT 1 FROM weekly_reflections WHERE user_id=? AND week_start_date=?
  #      AND completed_at IS NOT NULL LIMIT 1
  #      → 完了済みかの確認（EXISTS）
  #   両方とも SELECT 1 なのでレコードをメモリにロードしない（高速）
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

    last_week_exists = current_user.weekly_reflections
                                   .for_week(last_week_start)
                                   .exists?
    return false unless last_week_exists

    last_week_completed = current_user.weekly_reflections
                                      .for_week(last_week_start)
                                      .completed
                                      .exists?
    !last_week_completed
  end

  # ----------------------------------------------------------
  # require_unlocked
  # ----------------------------------------------------------
  # before_action として使用します。
  # ロック中は create / destroy などの書き込み操作を禁止します。
  def require_unlocked
    return unless locked?

    respond_to do |format|
      format.html do
        flash[:alert] = "先週の振り返りが未完了のため、この操作はできません。先に振り返りを完了してください。"
        redirect_back fallback_location: habits_path
      end
      format.turbo_stream { head :locked }
      format.json { render json: { error: "locked" }, status: :locked }
    end
  end

  # ============================================================
  # ai_limit_exceeded?（D-6 新規追加）
  # ============================================================
  #
  # 【役割】
  #   現在ログイン中のユーザーが AI 分析の月次上限に達しているかを返す。
  #
  # 【戻り値】
  #   true  : 上限に達している（今月はこれ以上 AI 分析できない）
  #   false : まだ余裕がある or user_setting が存在しない（安全側に倒す）
  def ai_limit_exceeded?
    # current_user&.user_setting:
    #   &. は Safe Navigation Operator（ぼっち演算子）。
    #   current_user が nil（未ログイン）の場合、user_setting を呼ばずに nil を返す。
    return false unless current_user&.user_setting

    current_user.user_setting.ai_analysis_count >= current_user.user_setting.ai_analysis_monthly_limit
  end
  helper_method :ai_limit_exceeded?

  # ============================================================
  # D-10 追加: AI API レート制限（連打防止）
  # ============================================================
  def throttle_ai_request
    return unless current_user

    setting = current_user.user_setting
    return unless setting

    if setting.ai_recently_requested?
      flash[:notice] = I18n.t("ai_throttle.too_soon")
      redirect_back fallback_location: root_path
      return
    end

    if current_user.user_purposes.where(analysis_state: [:pending, :analyzing]).exists?
      flash[:notice] = I18n.t("ai_throttle.already_processing")
      redirect_back fallback_location: root_path
      return
    end

    setting.touch_ai_requested_at!
  end

  # ============================================================
  # Issue #27: カスタムエラーページ表示メソッド
  # ============================================================

  def render_404(exception = nil)
    Rails.logger.info "404 Not Found: #{exception&.message}"
    render_error_page("errors/not_found", :not_found)
  end

  def render_422(exception = nil)
    Rails.logger.warn "422 Unprocessable Entity: #{exception&.message}"
    render_error_page("errors/unprocessable", :unprocessable_entity)
  end

  def render_500(exception = nil)
    Rails.logger.error "500 Internal Server Error: #{exception&.message}"
    Rails.logger.error exception&.backtrace&.first(5)&.join("\n")
    render_error_page("errors/internal_server_error", :internal_server_error)
  end

  # render_error_page（共通ヘルパー）
  def render_error_page(template, status)
    respond_to do |format|
      format.turbo_stream { head status }
      format.html { render template: template, layout: "application", status: status }
      format.json { render json: { error: status.to_s }, status: status }
      format.any { head status }
    end
  end

  # ----------------------------------------------------------
  # redirect_to_onboarding_if_needed（D-7 追加）
  # ----------------------------------------------------------
  # 【役割】
  #   first_login_at が NULL のログイン済みユーザーを
  #   オンボーディングページ（5/5 PMVV入力）へリダイレクトする。
  #
  # 【無限ループ防止の仕組み】
  #   controller_name で除外リストを確認し、
  #   オンボーディング・認証関連コントローラーでは実行しない。
  def redirect_to_onboarding_if_needed
    return if controller_name.in?(%w[onboardings sessions users errors pages])
    return unless current_user&.first_login_at.nil?

    redirect_to onboarding_step5_path, notice: t("onboarding.welcome")
  end

  # ============================================================
  # E-4 追加: safe_redirect_path?（オープンリダイレクト防止）
  # ============================================================
  #
  # 【役割】
  #   redirect_to パラメータとして渡されたパスが、
  #   自アプリ内のパスかどうかを検証する。
  #
  # 【なぜこのチェックが必要なのか（オープンリダイレクト攻撃の説明）】
  #   攻撃者が以下のような URL を作成してユーザーにクリックさせる:
  #     https://habitflow.example.com/login?redirect_to=http://evil.com/phishing
  #   ユーザーがログインすると http://evil.com/phishing に飛ばされてしまう。
  #   これを「オープンリダイレクト攻撃」と呼ぶ。
  #
  # 【検証方法の詳細（すべての条件を満たす必要がある）】
  #   1. path が nil や空文字でないこと
  #   2. path が "//" で始まっていないこと（ダブルスラッシュ攻撃対策）
  #      → "//evil.com" はブラウザによっては外部ホスト指定として解釈される
  #      → URI.parse("//evil.com").host が "evil.com" を返すため先に弾く必要がある
  #   3. URI.parse が例外なく解析できること
  #   4. uri.host が nil であること
  #      → ホスト名がない = 相対パス（/tasks や /weekly_reflections/new）
  #      → ホスト名がある = 絶対URL（http://evil.com）→ 拒否
  #   5. path が "/" で始まること
  #      → "javascript:alert(1)" のような攻撃を拒否
  #
  # 【各入力値の結果】
  #   "/tasks"              → host: nil → ✅ 安全（true）
  #   "/tasks?tab=must"     → host: nil → ✅ 安全（true）
  #   "http://evil.com"     → host: "evil.com" → ❌ 危険（false）
  #   "//evil.com"          → ② で先に弾く → ❌ 危険（false）
  #   "javascript:alert(1)" → 例外発生 → ❌ 危険（false）
  #   nil / ""              → ① blank?チェックで弾く → ❌ 危険（false）
  def safe_redirect_path?(path)
    # ① path が nil や空文字の場合は安全でないとみなす
    return false if path.blank?

    # ② ダブルスラッシュ始まりは外部ホスト指定として悪用できるため先に弾く
    #    URI.parse("//evil.com").host が "evil.com" を返してしまうブラウザがある。
    #    この1行で "//evil.com" を確実に排除できる。
    return false if path.start_with?("//")

    # ③ URI.parse でパスを解析する
    #    解析に失敗した場合（不正な URI）は例外が発生するため rescue で false を返す
    uri = URI.parse(path)

    # ④ ホスト名がない（相対パス）かつ "/" で始まるパスのみ安全とみなす
    #    uri.host.nil?           → "/tasks" のような相対パスは host が nil になる
    #    path.start_with?("/")   → "javascript:alert()" のような攻撃を弾く
    uri.host.nil? && path.start_with?("/")
  rescue URI::InvalidURIError
    # URI.parse が例外を発生させた場合（不正な URI）は安全でない
    false
  end
end