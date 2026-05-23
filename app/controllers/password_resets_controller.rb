# app/controllers/password_resets_controller.rb
#
# ==============================================================================
# PasswordResetsController - パスワードリセット機能
# ==============================================================================
#
# 【このコントローラーの役割】
#   ユーザーがパスワードを忘れた場合に、メール経由でリセットするフローを担当する。
#
# 【画面フロー】
#   23番画面: GET  /password_resets/new      → new    （メアドフォーム表示）
#   24番画面: POST /password_resets          → create  （メール送信→ログイン画面リダイレクト）
#   26番画面: GET  /password_resets/:id/edit → edit    （新パスワード入力フォーム）
#   27番画面: PATCH/PUT /password_resets/:id → update  （パスワード変更処理）
#   29番画面: トークン無効エラー → errors/token_invalid テンプレートを表示
#
# 【セキュリティ設計】
#   ・メール列挙攻撃防止: 存在しないメールでも同じレスポンスを返す
#   ・トークンは BCrypt ハッシュで DB に保存（生の値は DB に保存しない）
#   ・トークンは24時間で自動失効
#   ・使用済みトークンは is_used=true で再利用不可
#   ・パスワード変更完了時に同一ユーザーの全未使用トークンを無効化
#   ・パスワード変更後に reset_session でセッション固定攻撃を防止
#
# 【before_action の流れ】
#   edit / update → set_token_by_id で URL の :id からトークン検索
#                 → validate_token で有効性チェック（無効なら29番画面）
#
# ==============================================================================
class PasswordResetsController < ApplicationController
  # ============================================================
  # before_action の設定
  # ============================================================
  #
  # 【なぜ require_login を設定しないのか】
  #   パスワードリセットは「ログインできない人」が使う機能のため、
  #   ログインチェックは不要。
  #   ApplicationController の redirect_to_terms_agreement_if_needed は
  #   未ログインユーザー（current_user が nil）の場合は自然にスキップされる。

  # edit と update では URL の :id からトークンを特定する
  before_action :set_token_by_id, only: [:edit, :update]

  # トークンが有効か（期限内・未使用）をチェックする
  before_action :validate_token,  only: [:edit, :update]

  # ============================================================
  # GET /password_resets/new
  # 23番画面: メールアドレス入力フォームを表示
  # ============================================================
  def new
    # ログイン済みユーザーはパスワードリセット不要なのでダッシュボードへ
    redirect_to dashboard_path if logged_in?
  end

  # ============================================================
  # POST /password_resets
  # メール送信処理
  # ============================================================
  def create
    # ログイン済みユーザーはダッシュボードへ
    redirect_to dashboard_path and return if logged_in?

    # ============================================================
    # params.dig を使う理由:
    #   通常の params[:password_reset][:email] だと、
    #   :password_reset キー自体が存在しない不正リクエストが来た場合に
    #   NoMethodError（undefined method `[]' for nil）が発生して500エラーになる。
    #   dig は途中のキーが nil でも例外を出さずに nil を返すため安全。
    # ============================================================
    email = params.dig(:password_reset, :email).to_s.downcase.strip

    # メールアドレスでユーザーを検索する
    user = User.find_by(email: email)

    # ============================================================
    # 【重要】メール列挙攻撃（Email Enumeration Attack）の防止
    # ============================================================
    #
    # 攻撃者がメールアドレスを片っ端から入力して
    # レスポンスの違いから「登録済みアドレス」を特定する攻撃を防ぐため、
    # アドレスの存在有無に関わらず同じレスポンスを返す。
    #
    # ユーザーが見つかり、かつメール登録ユーザー（OAuthユーザーではない）の場合のみ
    # 内部でトークン生成・メール送信を行う。
    # それ以外（存在しない・OAuthユーザー）はメール送信せず同じ画面に戻す。
    if user && user.email.present?
      # ============================================================
      # provider の判定について:
      #   User.provider が blank または "email" → メール登録ユーザー → リセット可
      #   "google_oauth2" や "line_v2_1"        → OAuthユーザー → パスワード不要
      # ============================================================
      if user.provider.blank? || user.provider == "email"
        # トークンを生成してDBに保存し、生トークンを取得する
        raw_token = PasswordResetToken.generate_token_for(user)

        # 非同期でメール送信（GoodJob のキューに登録）
        #
        # 【deliver_later を使う理由】
        #   deliver_now は Resend API へのリクエスト完了まで画面がブロックされる。
        #   deliver_later でキューに積むことでレスポンスを即座に返せる（UX向上）。
        PasswordMailer.reset_password(user, raw_token).deliver_later
      end
    end

    # アドレスの存在有無に関わらず同じメッセージを表示（列挙攻撃防止）
    redirect_to login_path,
                notice: t("password_reset.sent")
  end

  # ============================================================
  # GET /password_resets/:id/edit
  # 26番画面: 新しいパスワード入力フォームを表示
  # ============================================================
  #
  # 【:id について】
  #   URL の :id には生のトークン文字列が入る。
  #   before_action の set_token_by_id / validate_token が通過済みなので
  #   @token_record は有効なレコードが保証されている。
  def edit
    # @token_record は before_action で設定済み
    @user = @token_record.user
  end

  # ============================================================
  # PATCH/PUT /password_resets/:id
  # 27番画面: パスワード変更処理
  # ============================================================
  def update
    @user = @token_record.user

    # assign_attributes:
    #   DB には保存せず、メモリ上の @user 属性だけを更新する。
    #   これにより save の前にバリデーション状態を制御できる。
    @user.assign_attributes(password_params)

    # ============================================================
    # transaction でパスワード保存とトークン無効化を一体化する
    # ============================================================
    #
    # 【なぜ transaction が必要か】
    #   @user.save と PasswordResetToken.update_all を別々に実行すると、
    #   その間でサーバーがクラッシュした場合に:
    #     ・パスワードだけ変更済み＆トークンが有効のまま（再利用可能）
    #   という不整合が起きる可能性がある。
    #   transaction で一体化することで、どちらかが失敗したら全てロールバックされる。
    #
    # 【ApplicationRecord.with_transaction を使う理由】
    #   このプロジェクトでは ApplicationRecord.with_transaction が
    #   共通トランザクションラッパーとして定義済み。
    #   ActiveRecord::Base.transaction と同等だが、プロジェクトの作法に従う。
    saved = false

    begin
      ApplicationRecord.with_transaction do
        # パスワードのバリデーションを実行して保存する
        #
        # 【save! を使う理由（save ではなく）】
        #   save はバリデーション失敗時に false を返すだけで例外を出さない。
        #   transaction ブロック内では例外が発生しないとロールバックが起きないため、
        #   save! で例外を発生させてロールバックを確実にトリガーする。
        @user.save!

        # パスワード変更完了後に同一ユーザーの未使用トークンを全て無効化する
        #
        # 【update_all を使う理由】
        #   複数レコードをループなしで一括更新する ActiveRecord メソッド。
        #   バリデーション・コールバックなしで直接 SQL UPDATE を実行するため高速。
        #   updated_at も明示的に指定して監査ログに残す。
        #
        # 【なぜ updated_at を明示するのか】
        #   update_all は updated_at を自動更新しない。
        #   いつトークンが無効化されたかを後から確認できるよう明示的に記録する。
        PasswordResetToken
          .where(user: @user, is_used: false)
          .update_all(is_used: true, updated_at: Time.current)

        saved = true
      end
    rescue ActiveRecord::RecordInvalid
      # バリデーション失敗（パスワードが短い・確認不一致など）
      # → transaction がロールバックされ、saved は false のまま
    end

    if saved
      # セッションをリセットしてセッション固定攻撃を防止する
      #
      # 【なぜパスワード変更後にセッションをリセットするのか】
      #   万が一攻撃者が古いセッション ID を持っていた場合、
      #   reset_session で無効化することで不正アクセスを遮断できる。
      reset_session

      redirect_to login_path,
                  notice: t("password_reset.success")
    else
      # バリデーション失敗 → フォームを再表示
      #
      # 【render :edit を使う理由】
      #   redirect_to だとパラメータが消えてエラーメッセージが表示できない。
      #   render :edit で同じリクエスト内に edit ビューを表示し、
      #   @user.errors のエラーメッセージをビューで表示する。
      render :edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # set_token_by_id
  #
  # 【役割】
  #   URL の :id パラメータ（生トークン文字列）から
  #   PasswordResetToken レコードを検索して @token_record にセットする。
  def set_token_by_id
    @token_record = PasswordResetToken.find_by_raw_token(params[:id])
  end

  # validate_token
  #
  # 【役割】
  #   @token_record が存在するかつ有効か（期限内・未使用）をチェックする。
  #   無効な場合は 29番画面（トークン無効エラーページ）を表示する。
  #
  # 【render template: と status: :not_found を組み合わせる理由】
  #   render template: だけでは HTTP ステータスが 200 になってしまう。
  #   status: :not_found を明示することで404が返り、
  #   テストの assert_response :not_found が通る。
  def validate_token
    unless @token_record&.valid_token?
      render template: "errors/token_invalid",
             layout:   "application",
             status:   :not_found
    end
  end

  # password_params
  #
  # 【役割】
  #   Strong Parameters でパスワード関連のパラメータのみを許可する。
  #
  # 【なぜ :password_reset スコープを使うのか】
  #   form_with scope: :password_reset で送信されるパラメータ構造:
  #   { password_reset: { password: "...", password_confirmation: "..." } }
  def password_params
    params.require(:password_reset).permit(:password, :password_confirmation)
  end
end