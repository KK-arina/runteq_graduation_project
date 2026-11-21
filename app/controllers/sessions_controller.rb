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
#
# ============================================================
# ログイン保持（remember me）での変更
# ============================================================
#
# 【変更内容】
#   ① create: 「ログインしたままにする」チェックボックスの値を受け取り、
#      共通メソッド log_in（concerns/remember_login.rb）でログインする。
#      チェックありなら、この端末用のログイン保持トークンを発行する。
#   ② destroy: 共通メソッド log_out でログアウトする。
#      この端末のログイン保持トークンも削除する（ほかの端末は残す）。
#
# 【なぜ共通メソッドにまとめたのか】
#   reset_session（セッション固定攻撃対策）とログイン保持の処理を
#   ログイン方法（メール・Google・LINE・新規登録）ごとに書くと、入れ忘れが起きやすい。
#   log_in / log_out に1か所でまとめ、どの入口でも同じ安全対策がかかるようにした。
#
# ============================================================
# 古い画面からのログアウト（CSRF トークンの不一致）への対応
# ============================================================
#
# 【起きていたこと】
#   同じブラウザで、タブ（またはホーム画面アプリのウィンドウ）を2つ開き、
#   片方でログインし直すと、log_in の reset_session でセッションが作り直され、
#   CSRF トークンも新しくなる。もう片方の画面には古いトークンが残っているため、
#   そこで「ログアウト」を押すと InvalidAuthenticityToken になり、
#   422 の「セッションが期限切れです」画面が表示されていた。
#
# 【対応（CSRF の検証そのものは外さない）】
#   ログアウトのときだけ、この例外を受け止めて分かりやすく案内する。
#   ・まだログインしている → ログアウトせずに元の画面へ戻し、
#     「もう一度ログアウトを押してください」と表示する。
#     戻った画面は新しいトークンで描き直されるので、2回目は成功する。
#   ・すでにログアウトしている → 通常のログアウトと同じくトップページへ。
#   ログイン（create）など、ほかの操作は今までどおり 422 の画面にする。
#
# 【CSRF の検証を外さない（skip_forgery_protection を使わない）理由】
#   検証を外すと、悪意のあるサイトが利用者のブラウザから DELETE /logout を送り、
#   勝手にログアウトさせることができてしまう（ログアウト CSRF）。
#   トークンが合わないときは「何もしないで案内だけする」ことで、安全性は今のまま保つ。
# ============================================================

class SessionsController < ApplicationController
  # ============================================================
  # CSRF トークンの不一致を、このコントローラーで受け止める
  # ============================================================
  #
  # 【rescue_from を ApplicationController と重ねて書いてよい理由】
  #   rescue_from は「あとから登録したもの」が優先される。
  #   子クラス（このコントローラー）で登録すると、ApplicationController の
  #   rescue_from ActionController::InvalidAuthenticityToken（render_422）より先に使われる。
  #   ほかのコントローラーには影響しない。
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_authenticity_token

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
    #
    # 【ログイン保持との関係】
    #   logged_in? の中で current_user が呼ばれ、ログイン保持の Cookie があれば
    #   ここで自動ログインされる。そのため「ログインしたまま」の人が
    #   /login を開いても、ログイン画面ではなくダッシュボードが表示される。
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

      # ── 認証成功: ログイン（ログイン保持対応で変更）──────────────────────
      #
      # remember_me_param_checked?（concerns/remember_login.rb）:
      #   チェックボックスの値（チェックあり "1" / なし "0"）を true / false に変換する。
      #   params.dig を使う理由: params[:session] が無い不正なリクエストでも
      #   例外にせず nil として扱い、「保持しない」側に倒すため。
      #
      # log_in（concerns/remember_login.rb）の中で行うこと:
      #   ① この端末に古いログイン保持トークンがあれば削除する
      #   ② reset_session でセッションIDを作り直す（セッション固定攻撃対策）
      #   ③ session[:user_id] と session[:auth_version] を記録する
      #   ④ チェックありなら新しいログイン保持トークンを発行して Cookie に保存する
      log_in(user, remember: remember_me_param_checked?(params.dig(:session, :remember_me)))

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
      #   ビュー側で params からチェックボックスの状態を復元する。
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
    # log_out（concerns/remember_login.rb）の中で行うこと:
    #   ① この端末のログイン保持トークンを DB から削除し、Cookie も削除する
    #      （ログアウトしたのに、次に開いたら自動ログインされる、という事態を防ぐ）
    #   ② reset_session でセッション全体を完全にリセットする
    #      （session.delete(:user_id) より確実。CSRF トークンも再生成される）
    #   ③ @current_user = nil でメモ化をリセットする
    #      （同じリクエスト内でログイン状態に見えてしまうのを防ぐ）
    #
    # 【ほかの端末のログイン保持を消さない理由】
    #   ログアウトは「今使っているこの端末」の操作のため。
    #   すべての端末を解除したい場合は、設定画面の「すべての端末からログアウトする」を使う。
    log_out

    # status: :see_other (303): DELETE後のリダイレクトには303が適切
    redirect_to root_path, status: :see_other, notice: "ログアウトしました"
  end

  private

  # ============================================================
  # handle_invalid_authenticity_token（古い画面からのログアウト対応で追加）
  # ============================================================
  #
  # 【役割】
  #   CSRF トークンが一致しないときに呼ばれる（rescue_from で登録）。
  #   ログアウトのときだけ分かりやすく案内し、ほかは今までどおり 422 の画面にする。
  #
  # 【この時点の状態】
  #   CSRF の検証は、どの before_action よりも先に実行される。
  #   そのため destroy の中身（log_out）は一切実行されていない（＝ログアウトしていない）。
  def handle_invalid_authenticity_token(exception)
    # ログアウト以外（ログインの送信など）は、ApplicationController の render_422 に任せる
    return render_422(exception) unless action_name == "destroy"

    # ログには事実だけを残す（トークンの値などは出さない）
    Rails.logger.info "[SessionsController#destroy] CSRF トークンが一致しないため、ログアウトせずに案内を表示しました"

    # ── すでにログアウトしている場合 ──────────────────────────────
    #   例: ほかのウィンドウでログアウトしたあと、古い画面でログアウトを押した。
    #   利用者の目的（ログアウト）はもう達成されているので、通常のログアウト後と同じ表示にする。
    #   logged_in? は、ログイン保持の Cookie があればここで自動ログインする点に注意
    #   （その場合は「まだログインしている」側の処理になる）。
    unless logged_in?
      redirect_to root_path, status: :see_other, notice: "ログアウトしました"
      return
    end

    # ── まだログインしている場合 ──────────────────────────────────
    # redirect_back_or_to（Rails 7 以降の標準メソッド）:
    #   前の画面（Referer ヘッダーの URL）に戻す。
    #   Referer が無い場合や、自分のサイト以外の URL の場合は、
    #   第1引数の dashboard_path に戻す（外部サイトへ飛ばされない＝オープンリダイレクト対策）。
    # status: :see_other（303）:
    #   DELETE のあとに Turbo が GET で画面を読み直すようにする。
    #   読み直した画面には新しい CSRF トークンが入るので、もう一度押せばログアウトできる。
    # flash: { warning: ... }:
    #   layout の flash 表示で、黄色の ⚠️（warning）として表示する。
    #   エラー（alert・赤）ではなく「もう一度押してください」という案内のため。
    redirect_back_or_to dashboard_path,
                        status: :see_other,
                        flash: { warning: t("sessions.destroy.stale_page") }
  end

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
