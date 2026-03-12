# app/controllers/habit_records_controller.rb
#
# =============================================================
# 【このファイルの役割】
# 習慣の日次記録（HabitRecord）を管理するController。
# ネストされたルーティング: /habits/:habit_id/habit_records
# チェックボックスを押したときの即時保存を担当する。
# =============================================================
#
# 【Issue #41 修正点】
#   update アクションにクロス習慣アクセスの検証を追加。
#
#   【修正前の問題点】
#     @habit_record = current_user.habit_records.find(params[:id])
#     → ログインユーザーの記録であることはチェックしているが、
#       URLで指定した :habit_id（@habit）と @habit_record の habit_id が
#       一致するかどうかの検証がなかった。
#
#     具体的な攻撃シナリオ:
#       PATCH /habits/1/habit_records/99
#       → habit_id=1 の習慣コントローラーとして呼ばれる
#       → @habit = 習慣1（set_habitで取得）
#       → @habit_record = record 99（習慣2の記録）でも取得できてしまう
#       → 習慣1の Turbo Stream でレンダリングされ、習慣2の記録が書き換えられる
#
#   【修正後の対応】
#     @habit_record.habit_id == @habit.id の検証を追加。
#     一致しない場合は 404 を返して処理を中断する。

class HabitRecordsController < ApplicationController

  # すべてのアクションの前にログインチェックを行う。
  # require_login は ApplicationController で定義されている。
  # ログインしていない場合はログインページにリダイレクトされる。
  before_action :require_login

  # すべてのアクションの前に @habit を取得する。
  # set_habit は private メソッドとして下部に定義されている。
  # URLの :habit_id パラメータを使ってログインユーザーの習慣を取得する。
  before_action :set_habit

  # ============================================================
  # POST /habits/:habit_id/habit_records
  # ============================================================
  # チェックボックスをON/OFFしたとき（まだ今日の記録がない場合）に呼ばれる。
  # 「記録がなければ作成、あれば更新」を HabitRecord モデル側のメソッドで処理する。
  def create
    # find_or_create_for: HabitRecord モデルのクラスメソッド。
    # AM4:00基準の「今日」の日付で record_date を設定し、
    # 既存レコードがあればそれを返し、なければ新規作成する。
    # user と habit の組み合わせで UNIQUE 制約があるため、
    # 同じ日に2件作成されることはない。
    @habit_record = HabitRecord.find_or_create_for(current_user, @habit)

    # update_completed!: completed カラムを更新するモデルメソッド。
    # params[:completed] == "1" → true（チェックON）
    # params[:completed] != "1" → false（チェックOFF）
    @habit_record.update_completed!(params[:completed] == "1")

    # respond_to: リクエストの Accept ヘッダーに応じてレスポンス形式を切り替える。
    respond_to do |format|
      # Turbo Stream リクエスト（Stimulus から fetch で呼ばれる場合）の処理。
      # headers: { "Accept" => "text/vnd.turbo-stream.html" } を含むリクエストがここに入る。
      format.turbo_stream do
        # turbo_stream.replace: 指定した id の DOM 要素を新しい HTML で置き換える。
        # "habit_record_row_#{@habit.id}": パーシャル側の id 属性と一致させること。
        # 習慣カードのチェックボックス部分だけが差し替えられ、ページ全体は再読み込みされない。
        render turbo_stream: turbo_stream.replace(
          "habit_record_row_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end

      # 通常の HTML リクエスト（JavaScript が無効な環境など）の処理。
      # Turbo が動作しない環境でも最低限の動作を保証するフォールバック。
      format.html { redirect_to dashboard_path, notice: "記録を保存しました" }
    end
  end

  # ============================================================
  # PATCH /habits/:habit_id/habit_records/:id
  # ============================================================
  # チェックボックスをON/OFFしたとき（今日の記録が既にある場合）に呼ばれる。
  # create と update の使い分けは HabitRecord 側のロジックで制御されており、
  # 既存レコードが存在する場合はこの update アクションが呼ばれる。
  def update
    # ── 【Issue #41 修正】クロス習慣アクセスの検証 ─────────────────
    #
    # 【なぜこの検証が必要か】
    # set_habit で @habit（URLの :habit_id に対応する習慣）を取得しているが、
    # current_user.habit_records.find(params[:id]) は「ログインユーザーの記録」という
    # チェックしかしていない。
    # 悪意あるユーザーが「習慣Aの URL」に「習慣Bの record_id」を指定すると、
    # 別の習慣のレコードを書き換えられてしまう可能性がある。
    #
    # 【修正内容】
    # @habit_record を取得した後で habit_id の一致を検証する。
    # 一致しない場合は render_404 を呼んで処理を中断する。
    #
    # current_user.habit_records.find:
    #   ログインユーザーの記録のみを検索する。
    #   他人のレコード ID を指定しても ActiveRecord::RecordNotFound になる。
    @habit_record = current_user.habit_records.find(params[:id])

    # habit_id の一致チェック（Issue #41 追加）
    # @habit_record.habit_id: DBに保存されている「この記録が属する習慣のID」
    # @habit.id: URLの :habit_id から取得した習慣のID
    # 両者が一致しない = URLを細工して別習慣の記録にアクセスしようとしている
    unless @habit_record.habit_id == @habit.id
      # render_404: ApplicationController で定義したカスタム404メソッド。
      # ボディなしで HTTP 404 を返し、処理を中断する。
      # and return: render_404 の後に続くコードが実行されないようにする。
      render_404 and return
    end

    # update_completed!: completed カラムを更新するモデルメソッド。
    # "0" 以外はすべて false として扱われるため、
    # "1" → true（チェックON）、"0" → false（チェックOFF）となる。
    @habit_record.update_completed!(params[:completed] == "1")

    # respond_to: リクエスト形式に応じてレスポンスを切り替える（create と同じ処理）。
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_row_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end
      format.html { redirect_to dashboard_path, notice: "記録を更新しました" }
    end
  end

  # ============================================================
  # Private メソッド（コントローラー内部でのみ使用）
  # ============================================================
  private

  # ----------------------------------------------------------
  # set_habit
  # ----------------------------------------------------------
  # before_action として全アクションの前に実行される。
  # URLの :habit_id パラメータを使って @habit を取得する。
  #
  # current_user.habits.active.find:
  #   「ログインユーザーの有効な習慣（論理削除されていない）」の中から検索する。
  #   他ユーザーの習慣IDや、削除済み習慣のIDを指定しても取得できない。
  #   これによりセキュリティ上の認可（Authorization）を担保している。
  def set_habit
    @habit = current_user.habits.active.find(params[:habit_id])
  rescue ActiveRecord::RecordNotFound
    # 習慣が見つからない場合: head :not_found でボディなし 404 を返す。
    # and return: この後の処理（アクション本体）を実行しないようにする。
    # Turbo Stream リクエストでもテンプレートなしで 404 を返せる。
    head :not_found and return
  end
end