# app/controllers/habits_controller.rb
#
# =============================================================
# 【このファイルの役割】
# 習慣（Habit）に関するHTTPリクエストを処理するコントローラー。
# index   → 習慣一覧の表示
# new     → 新規作成フォームの表示
# create  → 新規作成の保存処理
# destroy → 論理削除処理
# =============================================================
#
# 【Issue #41 修正点】
#   index アクションの @habit_stats 計算を N+1 対策済みの方式に変更。
#
#   【修正前の問題点】
#     @habit_stats = @habits.each_with_object({}) do |habit, hash|
#       hash[habit.id] = habit.weekly_progress_stats(current_user)
#     end
#     → habits が N件あると habit.weekly_progress_stats が N回呼ばれ、
#       habit_records へのSQLが N回発行される（N+1問題）。
#     → 習慣が10件あれば10回のSQLが発行される。
#
#   【修正後の方式】
#     build_habit_stats(@habits, current_user) を使う。
#     → 今週分の habit_records を GROUP BY で1回のSQLにまとめる。
#     → SQLは habits 取得1回 + records 集計1回 = 計2回で完結する。
#
#   WeeklyReflectionsController の build_habit_stats と完全に同じロジックのため、
#   将来的には ApplicationController か concern に切り出すことを推奨する。

class HabitsController < ApplicationController
  # ============================================================
  # before_action（アクション実行前に必ず呼ばれる処理）
  # ============================================================

  # require_login: 全アクションに対してログイン必須チェック。
  # ApplicationController で定義されている。
  # ログインしていない場合は flash[:alert] をセットして login_path にリダイレクトする。
  before_action :require_login

  # require_unlocked: create と destroy の前にロック状態をチェック。
  # only: [:create, :destroy] で対象アクションを限定している。
  # index や new はロック中でも表示できる（閲覧はOK、書き込みはNG）。
  before_action :require_unlocked, only: [ :create, :destroy ]

  # set_habit: destroy の前に @habit を取得する。
  # only: [:destroy] で destroy アクションのみを対象にしている。
  before_action :set_habit, only: [ :destroy ]

  # ============================================================
  # GET /habits
  # ============================================================
  # 習慣一覧ページを表示する。
  #
  # インスタンス変数の一覧:
  #   @habits             → ログインユーザーの有効な習慣（削除されていないもの）
  #   @habit_stats        → { habit_id => { rate:, completed_count: } } の進捗ハッシュ
  #   @today_records_hash → { habit_id => HabitRecord } の今日の記録ハッシュ
  #   @locked             → PDCAロック状態（true/false）
  def index
    # active スコープ: deleted_at が nil（論理削除されていない）習慣だけを取得する。
    # order(created_at: :desc): 新しく作成した習慣が一覧の上に来るよう並び替える。
    @habits = current_user.habits.active.order(created_at: :desc)

    # ── N+1対策①: 今日の記録を一括取得 ────────────────────────────
    # today_for_record: AM4:00基準の「今日」の Date を返すモデルメソッド。
    # .index_by(&:habit_id): [record1, record2, ...] を { habit_id => record } の
    # ハッシュに変換する。ビューで @today_records_hash[habit.id] と書くだけで取得できる。
    # SQL は1回のみ発行される（WHERE habit_id IN (...)）。
    today = HabitRecord.today_for_record
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: today)
      .index_by(&:habit_id)

    # ── N+1対策②: 週次進捗を一括集計（Issue #41 修正）───────────────
    # 【修正前】habit.weekly_progress_stats を習慣の数だけ呼ぶ（N+1問題）
    # 【修正後】build_habit_stats で GROUP BY を使った1回のSQLに集約する
    #
    # build_habit_stats の詳細は private メソッドのコメントを参照。
    # WeeklyReflectionsController にも同名メソッドがある（同じロジック）。
    @habit_stats = build_habit_stats(@habits, current_user)

    # locked?: ApplicationController で定義したPDCAロック判定メソッド。
    # ビューでは @locked を参照してボタンの活性/非活性を切り替える。
    @locked = locked?
  end

  # ============================================================
  # GET /habits/new
  # ============================================================
  # 新規作成フォームを表示する。
  # before_action :require_unlocked は new には設定していないため、
  # ロック中でもフォームページ自体は表示される。
  # （ただし送信（create）はロックされている）
  def new
    # current_user.habits.build: user_id が自動でセットされた新規 Habit インスタンスを作る。
    # DB には保存されない（build は new と同じ意味。save が呼ばれるまでDBに入らない）。
    @habit = current_user.habits.build
  end

  # ============================================================
  # POST /habits
  # ============================================================
  # 習慣の新規作成処理。
  # before_action :require_unlocked によりロック中は実行されない。
  def create
    # current_user.habits.build(habit_params): Strong Parameters でフィルタリングした
    # パラメータを使って Habit インスタンスを作る。user_id は自動でセットされる。
    @habit = current_user.habits.build(habit_params)

    if @habit.save
      # flash[:notice]: 次のリクエストでも表示されるフラッシュメッセージ（1回限り）。
      # layout の flash.each でトースト通知として表示される。
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      # flash.now[:alert]: 現在のリクエストのみ有効なフラッシュメッセージ。
      # render を使う場合は flash.now を使う（redirect_to の場合は flash を使う）。
      flash.now[:alert] = "習慣の登録に失敗しました"
      # status: :unprocessable_entity (422): Turbo Drive がフォームエラーを
      # 正しく処理するために 422 を返す必要がある。200 を返すと Turbo が
      # エラーとして扱わずページを置き換えてしまう。
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # DELETE /habits/:id
  # ============================================================
  # 習慣の論理削除処理。
  # before_action :require_unlocked によりロック中は実行されない。
  # before_action :set_habit により @habit が事前にセットされている。
  def destroy
    if @habit.soft_delete
      flash[:notice] = "習慣を削除しました"
      # status: :see_other (303): Turbo 対応の DELETE 後リダイレクトに使う。
      # Rails 7 では DELETE の後のリダイレクトは 303 を使うのが推奨（RFC 7231 準拠）。
      # 302 を使うと Turbo が DELETE リクエストとしてリダイレクト先を叩いてしまう場合がある。
      redirect_to habits_path, status: :see_other
    else
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # ----------------------------------------------------------
  # habit_params
  # ----------------------------------------------------------
  # Strong Parameters: フォームから送られるパラメータのうち
  # :name と :weekly_target のみを許可する（ホワイトリスト方式）。
  # :user_id などを意図的に除外することで、
  # 攻撃者がフォームから user_id を書き換えることを防ぐ。
  def habit_params
    params.require(:habit).permit(:name, :weekly_target)
  end

  # ----------------------------------------------------------
  # set_habit
  # ----------------------------------------------------------
  # destroy アクションの前に実行される。@habit をセットする。
  #
  # current_user.habits.active.find:
  #   「ログインユーザーの論理削除されていない習慣」の中から検索する。
  #   → 他ユーザーの習慣IDや削除済み習慣のIDを指定しても取得できない。
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # 見つからない場合: flash[:alert] をセットして一覧にリダイレクトする。
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end

  # ----------------------------------------------------------
  # build_habit_stats（Issue #41 追加）
  # ----------------------------------------------------------
  # 習慣ごとの今週の進捗率を GROUP BY で一括集計して返す。
  #
  # 【なぜ weekly_progress_stats のループから変更したか】
  #   変更前: habits.each { habit.weekly_progress_stats(user) }
  #     → 習慣の数だけ habit_records への SQL が発行される（N+1問題）。
  #   変更後: build_habit_stats
  #     → habit_records を GROUP BY habit_id で1回のSQLで集計する。
  #     → SQL は2回（habits 取得 + records 集計）で完結する。
  #
  # 【引数】
  #   habits - 集計対象の習慣（ActiveRecord::Relation）
  #   user   - 集計対象のユーザー（current_user を渡す）
  #
  # 【戻り値】
  #   Hash: { habit_id => { rate: Integer(0〜100), completed_count: Integer } }
  #   例:   { 1 => { rate: 71, completed_count: 5 },
  #            2 => { rate: 100, completed_count: 7 } }
  #
  # 【WeeklyReflectionsController との関係】
  #   同じロジックが WeeklyReflectionsController にも存在する。
  #   将来的には ApplicationController か Concern に切り出すことを推奨する。
  def build_habit_stats(habits, user)
    # ── Step 1: AM4:00基準で今週の日付範囲を計算する ─────────────
    # today_for_record: 深夜0:00〜3:59は前日として扱う AM4:00 基準の「今日」。
    # beginning_of_week(:monday): Rails の ActiveSupport メソッド。
    #   例: 2026-03-11(水) → 2026-03-09(月)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    # week_start..today: 今週の月曜日から今日までの Range（両端含む）。
    week_range = week_start..today

    # ── Step 2: DBで GROUP BY を使って集計する ───────────────────
    # .group(:habit_id).count:
    #   SQL: SELECT habit_id, COUNT(*) FROM habit_records
    #        WHERE user_id=? AND habit_id IN(?) AND record_date BETWEEN ? AND ?
    #        AND completed=true
    #        GROUP BY habit_id
    #   戻り値: { habit_id => count } の軽量なHash。
    #   ActiveRecord オブジェクトを生成しないのでメモリ効率が高い。
    records_count_by_habit = HabitRecord
      .where(user: user, habit: habits, record_date: week_range, completed: true)
      .group(:habit_id)
      .count

    # ── Step 3: 各習慣の達成率をメモリ上で計算する ──────────────
    # ここからは DB アクセスゼロ。records_count_by_habit を参照するだけ。
    habits.each_with_object({}) do |habit, hash|
      # records_count_by_habit[habit.id]: この習慣の今週の完了件数。
      # || 0: 今週1件も完了がない習慣はHashにキーがないため nil になる。nil || 0 で 0 扱い。
      completed_count = records_count_by_habit[habit.id] || 0

      # ゼロ除算ガード: weekly_target は validates で1以上が保証されているが念のため。
      rate = if habit.weekly_target.zero?
               0
      else
               # .to_f: 整数同士の割り算では小数が切り捨てられる（3/7 → 0）ため float に変換。
               # .clamp(0, 100): 目標を超過しても 100% を上限とする。
               # .floor: 小数点以下を切り捨て（42.8 → 42）。
               ((completed_count.to_f / habit.weekly_target) * 100)
                 .clamp(0, 100)
                 .floor
      end

      # { habit_id => { rate:, completed_count: } } の形でハッシュに積み上げる。
      hash[habit.id] = { rate: rate, completed_count: completed_count }
    end
  end
end
