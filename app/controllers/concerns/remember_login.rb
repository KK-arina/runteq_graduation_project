# app/controllers/concerns/remember_login.rb
#
# ==============================================================================
# RememberLogin: ログイン・ログアウト・ログイン保持（remember me）の共通処理
# ==============================================================================
#
# 【このファイルの役割】
#   ログインまわりの処理を1か所にまとめた「concern（共通部品）」。
#   ApplicationController に include することで、すべてのコントローラーから使える。
#
#   これまで SessionsController・OmniauthCallbacksController・UsersController の
#   それぞれに「reset_session → session[:user_id] = ...」が書かれていた。
#   ここに log_in メソッドとしてまとめることで、
#   ログイン保持やセッション固定攻撃対策の入れ忘れを防ぐ。
#
# 【ログイン保持の仕組み（全体像）】
#   ① 「ログインしたままにする」でログインすると、
#      ランダムなトークンを作って Cookie に保存し、DB にはその SHA-256 値を保存する。
#   ② 後日セッションが切れた状態でアクセスすると、
#      Cookie のトークンを DB と照合し、一致すれば自動でログインする。
#   ③ ログアウト・設定画面での解除などで、DB の行と Cookie を削除する。
#
# 【Cookie を encrypted（暗号化）にする理由】
#   Rails の暗号化 Cookie（AES-256-GCM）は中身を読めず、改ざんも検知できる。
#   改ざんされた Cookie は復号の段階で nil になるため、DB に問い合わせずに弾ける。
#   また expires を指定すると、Rails が有効期限を暗号化した中身にも記録するため、
#   ブラウザ側で期限を書き換えても延長できない。
# ==============================================================================
module RememberLogin
  extend ActiveSupport::Concern

  # ログイン保持用 Cookie の名前
  #   セッション Cookie（_habitflow_session）と区別できる名前にする。
  REMEMBER_COOKIE_NAME = :_habitflow_remember

  # included ブロック: include した側のクラス（ApplicationController）で実行される
  included do
    # helper_method: ビュー（ERB）からも呼べるようにする
    #   設定画面で「この端末でログイン保持中か」を表示するために使う。
    helper_method :remembered_on_this_device?
  end

  private

  # ============================================================
  # ログイン・ログアウト
  # ============================================================

  # log_in
  #
  # 【役割】
  #   ユーザーをログイン状態にする。すべてのログイン処理はこのメソッドを通す。
  #
  # 【引数 remember の3つの値】
  #   true  : この端末でログインを保持する（新しいトークンを発行する）
  #   false : この端末ではログインを保持しない（既存のトークンがあれば削除する）
  #   :keep : 今の保持状態を変えない
  #           → 設定画面から Google / LINE を「連携」するときなど、
  #             ログイン画面を通らない再認証で保持状態が勝手に消えないようにする。
  #             ただし保持中のトークンが「別のユーザー」のものなら削除する。
  def log_in(user, remember: false)
    # 今この端末にある有効なトークン（なければ nil）
    existing_token = current_remember_token

    # :keep で、かつ同じユーザーのトークンなら、そのまま残す
    keep_existing = remember == :keep && existing_token&.user_id == user.id

    # 残さない場合は、この端末の古いトークンと Cookie を削除する
    #   例: 別のアカウントに切り替えたとき、前のアカウントのトークンが残らないようにする
    forget_this_device unless keep_existing

    # セッション固定攻撃対策（reset_session）をしてからログイン状態にする
    start_session_for(user)

    # このリクエストの中でも、すぐにログイン済みとして扱えるようにする
    @current_user = user

    # 「ログインしたままにする」が選ばれていればトークンを発行する
    remember_this_device(user) if remember == true
  end

  # log_out
  #
  # 【役割】
  #   この端末をログアウトさせる。この端末のログイン保持も解除する。
  #   ほかの端末のログイン保持は残す（ログアウトは「この端末だけ」の操作のため）。
  def log_out
    forget_this_device
    reset_session
    @current_user = nil
  end

  # start_session_for
  #
  # 【役割】新しいセッションを作り、ユーザーIDとログインの世代番号を記録する。
  #
  # 【reset_session を必ず先に呼ぶ理由（セッション固定攻撃対策）】
  #   攻撃者が事前に用意したセッションIDを被害者に使わせ、
  #   被害者のログイン後にそのIDで乗っ取る攻撃を防ぐため、
  #   ログインのたびにセッションIDを新しくする。
  #
  # 【auth_version を記録する理由】
  #   「すべての端末からログアウト」やパスワードリセットのとき、
  #   users.auth_version が増えると、この値と一致しなくなり自動でログアウトされる。
  def start_session_for(user)
    reset_session
    session[:user_id]      = user.id
    session[:auth_version] = user.auth_version
  end

  # ============================================================
  # current_user から呼ばれる、ログイン中ユーザーの取得処理
  # ============================================================

  # user_from_session
  #
  # 【役割】セッションに記録されたユーザーIDから、ログイン中のユーザーを取得する。
  #
  # 【ログアウト扱いにする条件】
  #   ① ユーザーが見つからない、または退会済み（User.active で除外）
  #   ② ログインの世代番号がセッションと DB で違う
  #      （すべての端末からログアウト・パスワードリセット・退会のあと）
  #   どちらの場合も reset_session で古いセッションを消して nil を返す。
  #
  # 【session[:auth_version].to_i を使う理由】
  #   この機能を入れる前からログインしている人のセッションには値がない（nil）。
  #   nil.to_i は 0 になり、DB の初期値 0 と一致するので、
  #   デプロイ直後に全員が強制ログアウトされることはない。
  def user_from_session
    user_id = session[:user_id]
    return nil if user_id.blank?

    user = User.active.find_by(id: user_id)
    return user if user && session[:auth_version].to_i == user.auth_version

    reset_session
    nil
  end

  # user_from_remember_cookie
  #
  # 【役割】
  #   セッションがないときに、ログイン保持の Cookie を使って自動ログインする。
  #
  # 【処理の流れ】
  #   ① Cookie がなければ、DB を見ずにすぐ nil を返す（ほとんどのアクセスはここで終わる）
  #   ② Cookie を復号してトークンを取り出し、DB の digest と照合する
  #      （改ざん・期限切れの Cookie は復号の段階で nil になり、DB には問い合わせない）
  #   ③ 見つからない・退会済みなら、ゴミになった Cookie を削除して nil を返す
  #   ④ 見つかれば reset_session をしてから新しいセッションを作る（固定攻撃対策）
  #   ⑤ 前回の延長から1日以上たっていれば期限を延長し、Cookie の期限も合わせて更新する
  def user_from_remember_cookie
    # cookies[...]（復号しない生の値）で「Cookie があるか」だけを確認する
    return nil if cookies[REMEMBER_COOKIE_NAME].blank?

    token = current_remember_token
    user  = token&.user

    # トークンが無効、またはユーザーが退会済みの場合
    if token.nil? || user.deleted_at.present?
      # 退会済みユーザーのトークンが残っていた場合は DB からも消す
      RememberToken.where(id: token.id).delete_all if token
      # 毎回 DB を見に行かないよう、使えなくなった Cookie を削除する
      delete_remember_cookie
      @current_remember_token = nil
      return nil
    end

    # 自動ログインでも reset_session でセッションIDを新しくする
    start_session_for(user)

    # 延長した場合だけ、Cookie の期限も DB と同じ日時に更新する
    #   （延長しなかった場合は Cookie を書き直す必要がない）
    if token.slide_expiration!
      write_remember_cookie(cookies.encrypted[REMEMBER_COOKIE_NAME], token.expires_at)
    end

    # ログには user_id だけを記録する（メールアドレスなどの個人情報は出さない）
    Rails.logger.info "[RememberLogin] ログイン保持トークンで自動ログインしました user_id=#{user.id}"
    user
  end

  # ============================================================
  # この端末のログイン保持（トークンと Cookie）
  # ============================================================

  # current_remember_token
  #
  # 【役割】この端末の Cookie に対応する、有効なトークンのレコードを返す（なければ nil）。
  #
  # 【defined? でメモ化する理由】
  #   ||= だと結果が nil のときに毎回 DB を見に行ってしまう。
  #   defined? を使うと「nil だった」という結果も覚えておけるため、
  #   1回のリクエストで SQL が1回だけになる。
  def current_remember_token
    return @current_remember_token if defined?(@current_remember_token)

    raw_token = cookies.encrypted[REMEMBER_COOKIE_NAME]
    @current_remember_token = RememberToken.find_active_by_raw_token(raw_token)
  end

  # remembered_on_this_device?
  #
  # 【役割】ログイン中のユーザーが、この端末でログイン保持中かどうかを返す。
  #   設定画面の表示（保持中／保持していない）に使う。
  def remembered_on_this_device?
    return false unless logged_in?

    current_remember_token&.user_id == current_user.id
  end

  # remember_this_device
  #
  # 【役割】新しいトークンを発行し、生のトークンを暗号化 Cookie に保存する。
  def remember_this_device(user)
    record, raw_token = RememberToken.issue_for!(user)
    write_remember_cookie(raw_token, record.expires_at)
    @current_remember_token = record
  end

  # forget_this_device
  #
  # 【役割】この端末のトークンを DB から削除し、Cookie も削除する。
  #
  # 【delete_all を使う理由】
  #   コールバックなしの DELETE 文1本で削除できる。
  #   すでに削除されていた場合でもエラーにならない。
  def forget_this_device
    token = current_remember_token
    RememberToken.where(id: token.id).delete_all if token
    delete_remember_cookie
    @current_remember_token = nil
  end

  # write_remember_cookie
  #
  # 【各オプションの意味】
  #   expires:   DB のトークンと同じ有効期限にする（ブラウザもこの日時で Cookie を消す）
  #   httponly:  JavaScript から読めなくする（XSS で Cookie を盗まれにくくする）
  #   secure:    本番では HTTPS 通信のときだけ送る（通信の盗み見を防ぐ）。
  #              開発環境は http://localhost なので false にする
  #   same_site: :lax にする理由:
  #              LINE やメールの通知リンク（別サイトからの移動）で開いたときにも
  #              Cookie が送られ、ログイン状態のまま目的のページを表示できるようにする。
  #              別サイトからの POST などでは送られないため、CSRF 対策の一部にもなる。
  #              （:strict だと通知リンクから開いたときにログアウト状態に見えてしまう）
  def write_remember_cookie(raw_token, expires_at)
    cookies.encrypted[REMEMBER_COOKIE_NAME] = {
      value:     raw_token,
      expires:   expires_at,
      httponly:  true,
      secure:    Rails.env.production?,
      same_site: :lax
    }
  end

  # delete_remember_cookie
  #
  # 【役割】ブラウザにログイン保持の Cookie を削除させる。
  #   期限切れの Cookie を送り返すことで、ブラウザがその Cookie を消す。
  def delete_remember_cookie
    cookies.delete(REMEMBER_COOKIE_NAME)
  end

  # remember_me_param_checked?
  #
  # 【役割】フォームやクエリから来た値（"1" / "0" / nil など）を true / false にそろえる。
  #   ActiveModel::Type::Boolean は "1"・"true" を true、"0"・"false" を false に変換する。
  #   == true で比較して、nil や想定外の値は必ず false として扱う（安全側に倒す）。
  def remember_me_param_checked?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end
end