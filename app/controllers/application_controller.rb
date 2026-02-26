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
  #
  #   【セキュリティ上の意味】
  #   404を返すことで、存在しないリソースへのアクセスに対して
  #   「存在しない」とだけ伝え、DBの内部構造などを漏らさない。
  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  # ActionController::InvalidAuthenticityToken:
  #   CSRFトークンが不正なときに発生する例外。
  #   例: 古いタブからフォームを送信した場合や、
  #       外部サイトからフォームを偽装して送信しようとした場合。
  #
  #   【セキュリティ上の意味】
  #   CSRF攻撃を検知した場合に 422 を返し、処理を中断する。
  rescue_from ActionController::InvalidAuthenticityToken, with: :render_422

  # StandardError（本番環境のみ）:
  #   上記以外の予期しないエラー全般。
  #
  #   【なぜ本番環境限定にするのか】
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
  # require_login
  # ----------------------------------------------------------
  # before_action として使用します。
  # ログインしていない場合はログインページにリダイレクトします。
  #
  # 【セキュリティ上の意味】
  # 認証が必要なアクション（習慣管理、ダッシュボード等）の前に
  # 必ずこのチェックを挟むことで、未ログインユーザーが
  # 直接URLを叩いてもデータにアクセスできないようにしている。
  def require_login
    unless logged_in?
      flash[:alert] = "ログインしてください"
      redirect_to login_path
    end
  end

  # ============================================================
  # PDCA強制ロック判定
  # ============================================================

  # locked?
  #   月曜AM4:00以降かつ前週の振り返りが未完了の場合に true を返す。
  #
  # ============================================================
  # Issue #29: クエリ最適化（修正版）
  # ============================================================
  # 【問題の経緯】
  #   初版の .completed.exists? 変更では「前週レコードが存在しない場合」の
  #   考慮が不足していた。
  #
  #   exists? は「完了済みレコードが存在するか」を返すため:
  #   - 前週レコードが存在しない → exists? = false → !false = true（ロックあり）❌
  #   - 前週レコードが未完了    → exists? = false → !false = true（ロックあり）✅
  #   → 初週ユーザー（前週レコードなし）が誤ってロックされてしまう
  #
  # 【解決方法】
  #   「前週レコードが存在するか」を先に確認し、存在しない場合は初週として
  #   ロックしない（return false）。
  #   存在する場合のみ「完了済みか」を確認する。
  #
  # 【最終的なSQLの流れ】
  #   1. SELECT 1 FROM weekly_reflections WHERE user_id=? AND week_start_date=? LIMIT 1
  #      → 前週レコードの存在確認（EXISTS）
  #   2. SELECT 1 FROM weekly_reflections WHERE user_id=? AND week_start_date=?
  #      AND completed_at IS NOT NULL LIMIT 1
  #      → 完了済みかの確認（EXISTS）
  #   両方とも SELECT * ではなく SELECT 1 なのでレコードをメモリにロードしない（高速）
  def locked?
    return false unless logged_in?

    # ── Step 1: 現在が「月曜日のAM4:00以降」かどうかを確認する ────────
    # change(hour: 4, min: 0, sec: 0): 今週月曜日の AM4:00 を計算する
    # now < this_monday_4am: まだ AM4:00 前ならロック条件を満たさないので即 false
    now = Time.current
    this_monday_4am = Date.current
                          .beginning_of_week(:monday)
                          .in_time_zone
                          .change(hour: 4, min: 0, sec: 0)
    return false if now < this_monday_4am

    # ── Step 2: 前週の月曜日を計算する ─────────────────────────────
    # HabitRecord.today_for_record: AM4:00基準の「今日」を返すモデルメソッド
    # .beginning_of_week(:monday) - 1.week: 前週の月曜日
    last_week_start = HabitRecord.today_for_record
                                 .beginning_of_week(:monday) - 1.week

    # ── Step 3: 前週のレコード自体が存在するか確認する ─────────────
    # 【なぜ存在確認が必要か】
    # 初週ユーザーは前週の振り返りレコードが存在しない。
    # この場合「振り返りを完了していない」ではなく「まだ振り返りの対象期間がない」
    # ため、ロックすべきではない（ユーザー体験として不合理）。
    #
    # .for_week(last_week_start): week_start_date = 前週月曜日 で絞り込むスコープ
    # .exists?: レコードが1件でも存在すれば true（SELECT 1 ... LIMIT 1）
    last_week_exists = current_user.weekly_reflections
                                   .for_week(last_week_start)
                                   .exists?

    # 前週レコードが存在しない = 初週ユーザー → ロックしない
    return false unless last_week_exists

    # ── Step 4: 前週の振り返りが「完了済み」かどうかを確認する ──────
    # .completed: completed_at が NOT NULL のもの（WeeklyReflection に定義済みスコープ）
    # .exists?: 完了済みレコードが存在すれば true（メモリロードなし）
    #
    # last_week_completed が true  → 前週は完了済み → ロックなし（false）
    # last_week_completed が false → 前週は未完了   → ロックあり（true）
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
  #
  # 【セキュリティ上の意味】
  # ロック判定をコントローラー層で行うことで、
  # ビューのボタン非活性化だけに頼らない多重防御になっている。
  # （ビューのボタン非活性は見た目だけで、HTTPリクエストを直接送れば
  #   バイパスできてしまうため、サーバー側でも必ずチェックする）
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

  # render_404
  #   404 Not Found エラー時に呼ばれます。
  #   【セキュリティ上の意味】
  #   詳細なエラーメッセージを返さないことで、
  #   DBの構造やデータの存在有無を攻撃者に教えない。
  def render_404(exception = nil)
    Rails.logger.info "404 Not Found: #{exception&.message}"
    render_error_page("errors/not_found", :not_found)
  end

  # render_422
  #   422 Unprocessable Entity エラー時に呼ばれます。
  #   CSRFトークン不正など、セキュリティ上重要なイベントを
  #   logger.warn（警告レベル）で記録します。
  def render_422(exception = nil)
    Rails.logger.warn "422 Unprocessable Entity: #{exception&.message}"
    render_error_page("errors/unprocessable", :unprocessable_entity)
  end

  # render_500
  #   500 Internal Server Error エラー時に呼ばれます。
  #   本番環境のみ有効（開発環境ではRailsのデバッグ画面を使う）。
  #   【セキュリティ上の意味】
  #   スタックトレースをユーザーに見せないことで、
  #   内部実装の詳細が攻撃者に漏れることを防ぐ。
  def render_500(exception = nil)
    Rails.logger.error "500 Internal Server Error: #{exception&.message}"
    Rails.logger.error exception&.backtrace&.first(5)&.join("\n")
    render_error_page("errors/internal_server_error", :internal_server_error)
  end

  # render_error_page（共通ヘルパー）
  #   render_404 / render_422 / render_500 から呼ばれる共通処理。
  #
  # ============================================================
  # Issue #29: turbo_stream 形式への対応を追加
  # ============================================================
  # 【問題の経緯】
  #   Turbo Stream リクエスト（headers: { Accept: "text/vnd.turbo-stream.html" }）に対して
  #   render template: "errors/not_found", layout: "application" を実行すると、
  #   Rails が turbo_stream 形式のテンプレート（errors/not_found.turbo_stream.erb）を
  #   探しに行くが存在しないため MissingTemplate エラーが発生していた。
  #
  # 【解決方法】
  #   respond_to で形式を分岐する。
  #   - turbo_stream の場合: head :status のみを返す（ボディなし）
  #     → テンプレート不要で確実に動作する
  #     → Turbo はステータスコードを見てエラーを判断できる
  #   - html の場合: 既存のエラーページをレンダリング（変更なし）
  #
  # 【head :status とは？】
  #   ボディ（HTML）を含まずにHTTPステータスコードだけを返すメソッド。
  #   例: head :not_found → HTTP/1.1 404 Not Found のレスポンスだけを返す
  #   テンプレートを必要としないため MissingTemplate エラーが起きない。
  def render_error_page(template, status)
    respond_to do |format|
      # turbo_stream リクエスト（Stimulusからのfetchなど）の場合
      # テンプレートなしでステータスコードだけを返す
      format.turbo_stream { head status }

      # 通常の HTML リクエストの場合
      # 既存のエラーページテンプレートをレンダリングする（変更なし）
      format.html { render template: template, layout: "application", status: status }

      # JSON リクエストの場合（APIからのアクセスや将来の拡張を考慮）
      # シンプルなエラーメッセージをJSONで返す
      format.json { render json: { error: status.to_s }, status: status }
    end
  end
end