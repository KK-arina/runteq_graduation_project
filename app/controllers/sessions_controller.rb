# app/controllers/sessions_controller.rb
#
# ============================================================
# SessionsController
# ============================================================
# このコントローラーは、ログイン・ログアウトに関する処理を担当します。
#
# セッション（Session）とは？
# - ブラウザとサーバー間で状態を保持する仕組み
# - Railsでは、暗号化されたCookieにセッションIDを保存
# - サーバーは、セッションIDを見て「誰がアクセスしているか」を判別
#
# アクション:
# - new    : ログインフォームを表示
# - create : ログイン処理（認証）
# - destroy: ログアウト処理（セッション破棄）
#
# ============================================================
# E-4 変更: ログイン後のディープリンク遷移を追加
# ============================================================
#
# 【変更内容】
#   ログイン成功時に params[:redirect_to] が存在する場合、
#   そのパスへリダイレクトする処理を追加した。
#
# 【変更が必要な理由】
#   LINE通知のURLをタップした未ログインユーザーが
#   /login?redirect_to=/weekly_reflections/new のようなURLにリダイレクトされる。
#   ログイン成功後、そのまま dashboard_path に飛ばすと
#   「LINE通知から開いたページ」に戻れないため UX が悪い。
#
# 【オンボーディング優先の設計（E-4 追加考慮）】
#   初回ログインユーザー（first_login_at が nil）は
#   redirect_to パラメータより先にオンボーディングを完了させる必要がある。
#   理由: オンボーディング未完了のユーザーが振り返りや習慣ページに飛んでも
#         PMVV が未設定で機能が使えないため UX が壊れる。
#
# 【セキュリティ上の注意点】
#   safe_redirect_path? メソッド（ApplicationController に定義）で
#   外部URLへのオープンリダイレクト攻撃を防いでいる。
#   params[:redirect_to] が外部URLだった場合は dashboard_path に飛ばす。
# ============================================================

class SessionsController < ApplicationController
  # ============================================================
  # GET /login
  # ログインフォームを表示する
  # ============================================================
  def new
    # ログイン済みユーザーが /login にアクセスした場合はダッシュボードへリダイレクトする。
    #
    # 【なぜこの処理が必要なのか】
    #   OmniAuth 認証後にブラウザの「戻る」ボタンを押すと、
    #   /login?omniauth_error=true のような URL が表示され、
    #   ログイン済みにもかかわらずエラーメッセージが表示されてしまう。
    #   ログイン済みユーザーにはログインページを表示する必要がないため、
    #   ダッシュボードへリダイレクトする。
    redirect_to dashboard_path if logged_in?
  end

  # ============================================================
  # POST /login
  # ログイン処理（認証とディープリンク遷移）
  # ============================================================
  def create
    # ── ステップ1: メールアドレスを安全に取得する ──────────────────────────
    #
    # params[:session][:email]: フォームから送信されたメールアドレス
    #
    # なぜ to_s を使う？
    #   params[:session] や [:email] が nil の場合、downcase でエラーになる。
    #   to_s を使うことで nil を安全に "" に変換してから downcase できる。
    email = params[:session][:email].to_s.downcase

    # User.find_by(email: email):
    #   メールアドレスでユーザーを検索する。
    #   見つかった場合: Userオブジェクトを返す
    #   見つからない場合: nil を返す（find と違い例外を発生させない）
    user = User.find_by(email: email)

    # ── ステップ2: 認証（ユーザー存在確認 + パスワード照合）────────────────
    #
    # user && user.authenticate(password):
    #   左側 (user): ユーザーが見つかったか？
    #   右側 (authenticate): has_secure_password が提供するメソッド。
    #                        パスワードが正しければ Userオブジェクト（truthy）を返す。
    #   && の短絡評価: 左側が false なら右側（authenticate）は実行されない。
    if user && user.authenticate(params[:session][:password])

      # ── 認証成功: セッション固定攻撃対策 ────────────────────────────────
      #
      # reset_session:
      #   現在のセッションを完全に破棄し、新しいセッションIDを発行する。
      #   「セッション固定攻撃」防止のため、ログイン時に必ず実行する。
      reset_session

      # 新しいセッションにユーザーIDを保存してログイン状態にする
      session[:user_id] = user.id

      # ── E-4 追加: リダイレクト先の決定 ──────────────────────────────────
      #
      # determine_redirect_path メソッドで優先順位に従ってリダイレクト先を決定する。
      # 詳細は private の determine_redirect_path を参照。
      redirect_to determine_redirect_path(user, params[:redirect_to]), notice: "ログインしました"

    else
      # ── 認証失敗 ─────────────────────────────────────────────────────────
      #
      # flash.now[:alert]:
      #   flash.now を使う理由: render は新しいリクエストを発生させないため、
      #   通常の flash だと次のページまでメッセージが残ってしまう。
      #   flash.now は現在のリクエスト内だけで有効。
      flash.now[:alert] = "メールアドレスまたはパスワードが正しくありません"

      # render :new:
      #   同じリクエスト内でログイン画面を再表示する（リダイレクトしない）。
      # status: :unprocessable_entity:
      #   HTTP 422。フォームのバリデーション失敗時の標準ステータスコード。
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # DELETE /logout
  # ログアウト処理（セッション破棄）
  # ============================================================
  def destroy
    # reset_session:
    #   セッション全体を完全にリセットする。
    #   session.delete(:user_id) より確実。CSRF トークンも再生成される。
    reset_session

    # @current_user = nil:
    #   ApplicationController の current_user でメモ化しているため、
    #   ここでリセットしないと同じリクエスト内でログイン状態に見えてしまう。
    @current_user = nil

    # status: :see_other (303): DELETE後のリダイレクトには303が適切
    redirect_to root_path, status: :see_other, notice: "ログアウトしました"
  end

  private

  # ============================================================
  # determine_redirect_path（E-4 追加）
  # ============================================================
  #
  # 【役割】
  #   ログイン後のリダイレクト先を優先度に従って決定する。
  #
  # 【なぜ private メソッドに分離するのか】
  #   create アクションの中でリダイレクト先の分岐ロジックを直接書くと、
  #   コードが長くなって読みにくくなる。
  #   メソッドに分離することで create の処理の流れが追いやすくなる（可読性向上）。
  #   また単体でテストしやすくなる。
  #
  # 【引数】
  #   user             : 認証済みの User インスタンス
  #   redirect_to_param: params[:redirect_to] の値（nil の場合もある）
  #
  # 【優先順位の設計（オンボーディング競合対策）】
  #   優先度1: 初回ログイン（first_login_at が nil）→ オンボーディングへ
  #     理由: PMVV 未設定のユーザーを振り返りや習慣ページに飛ばしても機能しない。
  #           アプリを正しく使えるようにするためオンボーディングを最優先にする。
  #   優先度2: 安全な redirect_to パラメータが存在する → そのパスへ
  #     理由: LINE通知からのディープリンクは元のページに戻すのが UX 上正しい。
  #   優先度3: いずれも条件を満たさない → ダッシュボードへ（従来の動作）
  def determine_redirect_path(user, redirect_to_param)
    # 優先度1: 初回ログインユーザーはオンボーディングへ
    #   first_login_at が nil = オンボーディング未完了のユーザー
    return onboarding_step2_path if user.first_login_at.nil?

    # 優先度2: 安全なアプリ内パスが指定されている場合はそこへ遷移
    #   safe_redirect_path? は ApplicationController に定義したセキュリティチェックメソッド。
    #   外部URL（http://evil.com）やダブルスラッシュ（//evil.com）を弾く。
    if redirect_to_param.present? && safe_redirect_path?(redirect_to_param)
      return redirect_to_param
    end

    # 優先度3: パラメータなし or 外部URL → デフォルトのダッシュボードへ
    dashboard_path
  end
end