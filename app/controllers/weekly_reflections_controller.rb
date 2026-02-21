# app/controllers/weekly_reflections_controller.rb
#
# ═══════════════════════════════════════════════════════════════════
# 【このファイルの役割】
#   週次振り返り（WeeklyReflection）に関するHTTPリクエストを受け取り、
#   適切なデータ処理とビュー表示を担当するコントローラー。
#   Rails の MVC アーキテクチャにおける "C（Controller）" の部分。
# ═══════════════════════════════════════════════════════════════════

class WeeklyReflectionsController < ApplicationController
  # ---------------------------------------------------------------
  # before_action :require_login
  #
  # 【なぜ使うのか】
  #   すべてのアクション（index, new, create, show）が実行される前に
  #   「ログイン済みか？」をチェックする。
  #   未ログインのユーザーがURLを直打ちしてアクセスしてきた場合も弾ける。
  #   require_login メソッドは ApplicationController に定義されている。
  # ---------------------------------------------------------------
  before_action :require_login

  # ---------------------------------------------------------------
  # before_action :set_weekly_reflection, only: [:show]
  #
  # 【なぜ使うのか】
  #   show アクションの冒頭で毎回「対象の振り返りを DB から取得する」
  #   処理が必要になる。それを before_action に切り出すことで、
  #   show メソッド本体をシンプルに保ち、コードの重複を防ぐ。
  #   only: [:show] で show アクションのみに適用を限定している。
  # ---------------------------------------------------------------
  before_action :set_weekly_reflection, only: [:show]

  # ---------------------------------------------------------------
  # index アクション
  # GET /weekly_reflections
  #
  # 【なぜ使うのか】
  #   ログイン中のユーザーの週次振り返り一覧を表示するための処理。
  #   週次振り返りが完了しているものだけを新しい順に取得する。
  # ---------------------------------------------------------------
  def index
    # current_user ... ApplicationController で定義されているログイン中のユーザー
    # .weekly_reflections ... そのユーザーの週次振り返りを取得（アソシエーション）
    # .completed ... is_locked: true のもの（WeeklyReflection モデルのスコープ）
    # .recent ... 新しい順に並べる（WeeklyReflection モデルのスコープ）
    # .includes(:habit_summaries) ... 習慣サマリーを一括取得して N+1 問題を防ぐ
    @weekly_reflections = current_user.weekly_reflections
                                      .completed
                                      .recent
                                      .includes(:habit_summaries)

    # 今週の振り返り（未完了のもの）も取得しておく
    # → 一覧ページで「今週を振り返る」ボタンを出すかどうかの判定に使う
    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    # 今週の習慣一覧と進捗サマリーを取得（一覧ページ上部の「今週の達成率」表示用）
    @habits = current_user.habits.active

    # each_with_object: 配列をループしながらハッシュを作るメソッド
    # habit.id をキーにして進捗データを格納することで、ビューで O(1) アクセスできる
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end
  end

  # ---------------------------------------------------------------
  # new アクション
  # GET /weekly_reflections/new
  #
  # 【なぜ使うのか】
  #   振り返り入力フォームを表示するためのアクション。
  #   既に今週の振り返りが完了済みなら詳細ページへリダイレクトする。
  # ---------------------------------------------------------------
  def new
    # find_or_build_for_current_week:
    #   今週の振り返りが既存なら取得、なければ新規オブジェクトを構築する
    #   WeeklyReflection モデルに定義されているクラスメソッド
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    # 既に完了済み（is_locked: true）なら詳細ページへリダイレクト
    # 二重送信防止 & 完了済みフォームの再表示防止
    if @weekly_reflection.persisted? && @weekly_reflection.is_locked?
      redirect_to @weekly_reflection, notice: "今週の振り返りは既に完了しています。"
      return
    end

    # 今週の習慣一覧を取得（フォームで達成率を見せるために使う）
    @habits = current_user.habits.active

    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    # @achieved_habits / @not_achieved_habits:
    #   new.html.erb が「達成済み」「未達成」を分けて表示するために使う。
    #   achievement_rate >= 100 を達成済みと判定する。
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

  # ---------------------------------------------------------------
  # create アクション
  # POST /weekly_reflections
  #
  # 【なぜ使うのか】
  #   フォーム送信（POST）を受け取り、振り返りデータを DB に保存する。
  #   トランザクションで「振り返り本体 + 習慣スナップショット」を一括保存し、
  #   どちらかが失敗したら両方ロールバックして整合性を保つ。
  # ---------------------------------------------------------------
  def create
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    # 既に完了済みなら詳細ページへリダイレクト（二重送信防止）
    if @weekly_reflection.persisted? && @weekly_reflection.is_locked?
      redirect_to @weekly_reflection, notice: "今週の振り返りは既に完了しています。"
      return
    end

    # Strong Parameters: フォームから受け取るパラメータを明示的に許可する
    # 許可していないパラメータは無視されるため、不正なデータ書き込みを防ぐ
    @weekly_reflection.assign_attributes(weekly_reflection_params)

    # is_locked を true にすることで「完了」扱いにする
    @weekly_reflection.is_locked = true

    # ActiveRecord::Base.transaction: ブロック内の DB 操作を一つのトランザクションにまとめる
    # どこかで例外が発生したら全ての変更がロールバックされる
    ActiveRecord::Base.transaction do
      @weekly_reflection.save!

      # 今週のアクティブな習慣をスナップショットとして保存
      # create_all_for_reflection! は WeeklyReflectionHabitSummary モデルのクラスメソッド
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@weekly_reflection)
    end

    # 保存成功 → 一覧ページへリダイレクト
    # テスト（weekly_reflection_create_test.rb）が weekly_reflections_path を期待している
    redirect_to weekly_reflections_path, notice: "今週の振り返りを保存しました！お疲れ様でした🎉"

  # rescue: トランザクション内で例外が発生した場合の処理
  # ActiveRecord::RecordInvalid: バリデーションエラー
  # ActiveRecord::RecordNotUnique: UNIQUE 制約違反（同じ週に2回送信など）
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.error("WeeklyReflection create error: #{e.message}")

    @habits = current_user.habits.active
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }

    flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
    render :new, status: :unprocessable_entity
  end

  # ---------------------------------------------------------------
  # show アクション ← 【Issue #23 メイン実装】
  # GET /weekly_reflections/:id
  #
  # 【なぜ使うのか】
  #   過去の振り返り詳細を表示するためのアクション。
  #   before_action :set_weekly_reflection で @weekly_reflection は設定済み。
  # ---------------------------------------------------------------
  def show
    # @weekly_reflection は before_action :set_weekly_reflection で設定済み
    #
    # includes(:habit):
    #   【なぜ使うのか】
    #   現在は habit_name_snapshot（スナップショット）だけ参照するため
    #   N+1 は発生しない。しかし将来 summary.habit.name のように
    #   関連テーブルにアクセスした瞬間に N+1 が発生する。
    #   今のうちに includes しておくことで将来安全な設計にしている。
    #
    # .order(achievement_rate: :desc):
    #   【なぜハッシュ形式にするのか】
    #   文字列形式（"achievement_rate DESC"）より安全。
    #   カラム名をシンボルで指定することで SQLインジェクションのリスクがなく、
    #   Rails の標準スタイルに沿っている。
    @habit_summaries = @weekly_reflection.habit_summaries
                                         .includes(:habit)
                                         .order(achievement_rate: :desc)

    # 全体の平均達成率を計算（プライベートメソッドに切り出して責務を分離）
    # 【なぜメソッドに切り出すのか】
    #   計算ロジックをアクション本体から分離することで、
    #   show アクションが「何を準備しているか」だけを表現できる。
    #   テストや将来の修正時もこのメソッドだけを変えればよい。
    @overall_achievement_rate = calculate_overall_achievement_rate
  end

  private

  # ---------------------------------------------------------------
  # calculate_overall_achievement_rate（プライベートメソッド）
  #
  # 【なぜ切り出すのか】
  #   show アクション内に計算ロジックを書くと責務が混在して読みにくくなる。
  #   プライベートメソッドに分離することで：
  #   ・show アクションは「どんな変数を準備するか」に集中できる
  #   ・計算ロジックの修正が1箇所で済む（保守性UP）
  #
  # 【計算方法】
  #   全習慣の achievement_rate を合計して件数で割る（単純平均）。
  #   .to_f ... 整数同士の割り算で端数が消えないようにする
  #   .round(1) ... 小数点1桁に丸める（例: 85.5%）
  #   .size ... length と同じ。ActiveRecord Relation が既にロード済みの場合は
  #             追加 SQL を発行しない（.count は常に SQL を発行するため .size が推奨）
  # ---------------------------------------------------------------
  def calculate_overall_achievement_rate
    return 0 if @habit_summaries.empty?

    (@habit_summaries.map(&:achievement_rate).sum / @habit_summaries.size.to_f).round(1)
  end

  # ---------------------------------------------------------------
  # set_weekly_reflection（プライベートメソッド）
  #
  # 【なぜ使うのか】
  #   URL の :id パラメータ（例: /weekly_reflections/5）から
  #   対象の WeeklyReflection レコードを取得する。
  #
  #   .where(user: current_user) を使う理由：
  #   current_user のデータのみを検索対象にすることで、
  #   他のユーザーの振り返りに ID 直打ちでアクセスされることを防ぐ。
  #   （セキュリティ対策：認可チェック）
  #
  #   .find(params[:id]) がなければ ActiveRecord::RecordNotFound を raise し、
  #   Rails が自動で 404 ページを表示してくれる。
  # ---------------------------------------------------------------
  def set_weekly_reflection
    @weekly_reflection = current_user.weekly_reflections.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # 他ユーザーの振り返りや存在しない ID へのアクセス → 一覧ページへリダイレクト
    redirect_to weekly_reflections_path, alert: "振り返りが見つかりませんでした。"
  end

  # ---------------------------------------------------------------
  # weekly_reflection_params（プライベートメソッド）
  #
  # 【なぜ使うのか】
  #   Strong Parameters: フォームから POST されるパラメータのうち、
  #   DB への書き込みを許可するキーを明示的にホワイトリスト化する。
  #   :reflection_comment のみ許可することで、
  #   is_locked や user_id などを外部から書き換えられることを防ぐ。
  # ---------------------------------------------------------------
  def weekly_reflection_params
    params.require(:weekly_reflection).permit(:reflection_comment)
  end
end
