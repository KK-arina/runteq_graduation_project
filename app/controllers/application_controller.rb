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
  # ヘルパーメソッドの登録
  # ============================================================
  # helper_method に登録すると、ビュー(ERBファイル)でも
  # このメソッドを呼び出せるようになります。
  # 例: views/dashboards/index.html.erb で locked? を使いたいため登録しています。
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
  #
  # ||= (または等) を使ってメモ化しています。
  # 同じリクエスト内で2回以上呼ばれてもDBへの問い合わせは1回だけです。
  #
  # session[:user_id] が nil の場合（未ログイン）は nil を返します。
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # ----------------------------------------------------------
  # logged_in?
  # ----------------------------------------------------------
  # ログイン済みかどうかを true/false で返します。
  # current_user が nil でなければ true です。
  # present? は「nilでも空でもない」ことを確認するRailsメソッドです。
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

  # ----------------------------------------------------------
  # locked?
  # ----------------------------------------------------------
  # 現在「ロック状態」かどうかを true/false で返します。
  #
  # ロック条件（以下の3つを全て満たす場合にロック）:
  #   1. 現在時刻が「今週月曜日 AM4:00 以降」であること
  #      → AM4:00 を過ぎるまでは日曜の深夜扱いなので、まだロックしない
  #   2. 前週の WeeklyReflection レコードが存在すること
  #   3. その振り返りが「未完了（pending?）」であること
  #
  # ロックしない場合（false を返す場合）の例:
  #   - 未ログイン
  #   - 今週月曜 AM4:00 をまだ過ぎていない（日曜深夜 〜 月曜 AM3:59）
  #   - 前週の振り返りレコードが存在しない（アプリ初週など）
  #   - 前週の振り返りが完了済み
  #
  # helper_method に登録済みのため、ビュー(ERB)からも呼べます。
  def locked?
    # 未ログインの場合はロック不要
    return false unless logged_in?

    # ----------------------------------------------------------
    # ① 現在時刻を取得（Railsのタイムゾーン設定を考慮）
    # ----------------------------------------------------------
    # Time.current は config/application.rb で設定したタイムゾーンで
    # 現在時刻を返します。Time.now（Ruby標準）はシステム時刻を返すため、
    # Railsアプリでは必ず Time.current を使います。
    now = Time.current

    # ----------------------------------------------------------
    # ② 今週の月曜日 AM4:00 を計算
    # ----------------------------------------------------------
    # Date.current で「今日の日付」を取得し、
    # beginning_of_week(:monday) で今週月曜日の Date を取得します。
    # Date に対して .beginning_of_week を呼ぶことでタイムゾーン混在を避けています。
    # in_time_zone で Railsのタイムゾーンの Time に変換してから
    # change(hour: 4) で AM4:00 を指定します。
    this_monday_4am = Date.current
                          .beginning_of_week(:monday)
                          .in_time_zone
                          .change(hour: 4, min: 0, sec: 0)

    # ----------------------------------------------------------
    # ③ まだ月曜 AM4:00 に到達していない場合はロックしない
    # ----------------------------------------------------------
    # 例: 日曜23:00 → this_monday_4am（翌月曜4:00）より前なのでロックしない
    # 例: 月曜3:59  → まだ AM4:00 前なのでロックしない
    # 例: 月曜4:00  → AM4:00 ちょうどなのでロック判定に進む
    return false if now < this_monday_4am

    # ----------------------------------------------------------
    # ④ 前週の開始日（前週月曜日）を計算
    # ----------------------------------------------------------
    # HabitRecord.today_for_record → AM4:00 基準の「今日」(Date型)
    # beginning_of_week(:monday)   → その週の月曜日
    # - 1.week                     → 1週間前 = 前週月曜日
    last_week_start = HabitRecord.today_for_record
                                 .beginning_of_week(:monday) - 1.week

    # ----------------------------------------------------------
    # ⑤ 前週の WeeklyReflection を検索
    # ----------------------------------------------------------
    last_week_reflection = current_user.weekly_reflections
                                       .find_by(week_start_date: last_week_start)

    # ----------------------------------------------------------
    # ⑥ 前週のレコードが存在しない場合はロックしない（アプリ初週など）
    # ----------------------------------------------------------
    return false if last_week_reflection.nil?

    # ----------------------------------------------------------
    # ⑦ 振り返りが未完了（pending?）ならロック
    # ----------------------------------------------------------
    # pending? が true → locked? は true（ロック）
    # pending? が false（完了済み）→ locked? は false（ロックしない）
    last_week_reflection.pending?
  end

  # ----------------------------------------------------------
  # require_unlocked
  # ----------------------------------------------------------
  # ロック中の場合に操作を拒否する before_action 用メソッドです。
  #
  # 使い方: HabitsController の create / destroy に設定します。
  # HTML リクエスト → リダイレクト＋エラーメッセージ
  # Turbo Stream / JSON リクエスト → 423 (Locked) を返す
  def require_unlocked
    return unless locked?

    respond_to do |format|
      # 通常のHTMLリクエスト（フォーム送信など）の場合
      format.html do
        flash[:alert] = "先週の振り返りが未完了のため、この操作はできません。先に振り返りを完了してください。"
        redirect_back fallback_location: habits_path
      end
      # Turbo StreamやJSONリクエストの場合（Ajax通信など）
      format.turbo_stream do
        head :locked  # HTTP 423 Locked を返す
      end
      format.json do
        render json: { error: "locked" }, status: :locked
      end
    end
  end
end