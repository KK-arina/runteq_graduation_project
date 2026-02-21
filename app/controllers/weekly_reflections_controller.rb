# app/controllers/weekly_reflections_controller.rb
#
# 【役割】
# WeeklyReflection（週次振り返り）に関するHTTPリクエストを処理するコントローラー
#
# 【担当アクション】
# index  → 振り返り一覧を表示（Issue #21実装済み）
# new    → 振り返り入力フォームを表示（Issue #22）
# create → 振り返りを保存する（Issue #22）

class WeeklyReflectionsController < ApplicationController
  # ==========================================
  # before_action: ログイン必須チェック
  # ==========================================
  # 【なぜ必要か】
  # URLを直接入力すれば認証なしにアクセスできてしまう。
  # before_action で全アクションの前にチェックすることで、
  # 未ログイン状態のアクセスをログインページへ自動的に弾く。
  before_action :require_login

  # ==========================================
  # index: 週次振り返り一覧
  # ==========================================
  def index
    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)
    @can_create_reflection   = can_create_reflection?
    @past_reflections        = current_user.weekly_reflections
                                           .completed
                                           .recent
                                           .includes(:habit_summaries)
    @habits      = current_user.habits.active.order(created_at: :desc)
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end
    rates          = @habit_stats.values.map { |s| s[:rate] }
    @overall_rate  = rates.any? ? (rates.sum.to_f / rates.size).round : 0
  end

  # ==========================================
  # new: 振り返り入力フォームを表示する
  # ==========================================
  # GET /weekly_reflections/new
  #
  # 【処理の流れ】
  # 1. 今週の振り返りインスタンスを取得（なければ新規生成）
  # 2. すでに完了済みなら詳細ページへリダイレクト（二重送信防止）
  # 3. 今週の習慣実績を集計してビューに渡す
  def new
    # 【なぜ find_or_build_for_current_week を使うか】
    # このアプリの設計は「月〜日を1週間として、日曜に今週を振り返る」。
    # current_week_start_date（Issue #19で実装済み）がその週の月曜日を返す。
    # find_or_build は「すでに今週分があればそれを返し、なければ新規インスタンス生成」。
    # これにより、ページを何度開いても重複作成しない冪等性が保たれる。
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    # 【ガード節：二重振り返り防止】
    # すでに今週分の振り返りが「保存済み（persisted?）」かつ「完了済み（completed?）」
    # の場合は、フォームを表示する意味がないので詳細ページへ誘導する。
    # ※ return を明示して以降のコードを実行させない（早期リターン）
    if @weekly_reflection.persisted? && @weekly_reflection.completed?
      redirect_to @weekly_reflection, notice: "今週の振り返りはすでに完了しています"
      return
    end

    # 【共通メソッドで習慣実績を準備】
    # new アクションと create 失敗時の両方で同じ集計が必要なため、
    # private メソッドに切り出してDRY（Don't Repeat Yourself）を実現する。
    prepare_habit_stats
  end

  # ==========================================
  # create: 振り返りをDBへ保存する
  # ==========================================
  # POST /weekly_reflections
  #
  # 【処理の流れ】
  # 1. 今週の振り返りインスタンスを取得（なければ新規生成）
  # 2. フォーム入力値（コメント）を反映
  # 3. トランザクション内で振り返り本体 + スナップショットをまとめて保存
  # 4. 成功 → 一覧へリダイレクト / 失敗 → フォーム再表示
  def create
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    # 【Strong Parameters を適用する理由】
    # フォームから送信されたデータにはユーザーが自由に項目を追加できてしまう。
    # permit で「受け取っていい項目」を明示することで、
    # is_locked や user_id などを外部から勝手に書き換えられるのを防ぐ。
    @weekly_reflection.assign_attributes(weekly_reflection_params)

    # 【なぜ Transaction（トランザクション）を使うか】
    # ① WeeklyReflection（振り返り本体）の保存
    # ② WeeklyReflectionHabitSummary（習慣スナップショット）の保存
    # この2つは「必ず両方成功」か「両方なかったことにする」でないとデータが壊れる。
    # transaction はブロック内で例外が起きると全ての変更を自動的にロールバックする。
    ActiveRecord::Base.transaction do
      # is_locked: true = 振り返り完了フラグ
      # コントローラーで明示的にセットすることで、フォームから勝手にセットされるのを防ぐ
      @weekly_reflection.is_locked = true
      @weekly_reflection.save!

      # 【スナップショットを作る理由】
      # 習慣は後から「削除」や「名前変更」される可能性がある。
      # 振り返り時点の習慣名・目標値・実績をそのまま保存しておくことで、
      # 後から振り返りを見ても当時の状況が正確にわかる。
      # create_all_for_reflection! は冪等性対応のため存在チェック後に作成する（Issue #20実装済み）。
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@weekly_reflection)
    end

    redirect_to weekly_reflections_path, notice: "今週の振り返りを完了しました！お疲れ様でした 🎉"

  rescue ActiveRecord::RecordInvalid => e
    # 【バリデーションエラーの処理】
    # save! はバリデーション失敗時に RecordInvalid を raise する。
    # errors.full_messages で「どの項目が・なぜ失敗したか」をユーザーに伝える。
    # flash.now はこのリクエスト内だけでメッセージを表示する（リダイレクト後は消える）。
    flash.now[:alert] = "保存に失敗しました: #{e.record.errors.full_messages.join(', ')}"
    prepare_habit_stats
    render :new, status: :unprocessable_entity

  rescue ActiveRecord::RecordNotUnique
    # 【DBレベルのUNIQUE制約違反の処理】
    # weekly_reflections テーブルには（user_id, week_start_date）の UNIQUE インデックスが貼られている（Issue #19実装済み）。
    # 並列リクエストなど極めてまれなケースで Rails のロジックをすり抜けた場合に
    # DBが重複を検知して例外を投げる。それをここで受け取り、安全に処理する。
    flash.now[:alert] = "今週の振り返りはすでに存在します"
    prepare_habit_stats
    render :new, status: :unprocessable_entity

  # 【なぜ StandardError を rescue しないか】
  # rescue StandardError は「全ての例外を握りつぶす」ことになり危険。
  # 例えば DB接続エラーや設計上のバグまで隠してしまい、
  # 本番でトラブルが起きても原因がわからなくなる。
  # 想定外のエラーは Rails のデフォルトエラーハンドラーに任せる。
  # 開発中は500エラー画面が出て即座に気づける。本番は config/environments/production.rb で管理する。
  end

  private

  # ==========================================
  # weekly_reflection_params: Strong Parameters
  # ==========================================
  # 【許可する項目】
  # reflection_comment のみ。ユーザーが入力できるのはこれだけ。
  #
  # 【許可しない項目（コントローラーが直接セットする）】
  # is_locked        → create アクション内で true にセット
  # week_start_date  → find_or_build_for_current_week が自動セット
  # week_end_date    → 同上
  # user_id          → current_user から自動セット
  def weekly_reflection_params
    params.require(:weekly_reflection).permit(:reflection_comment)
  end

  # ==========================================
  # prepare_habit_stats: 習慣実績の集計（共通処理）
  # ==========================================
  # 【なぜメソッドに切り出すか】
  # new アクションと create の rescue 節の両方で全く同じ集計が必要。
  # コードの重複を避けるため（DRY原則）private メソッドに切り出す。
  #
  # 【N+1問題について】
  # weekly_progress_stats は Issue #16 で「1回のDBアクセスで完結する」設計で実装済み。
  # 習慣数 × SQL回数 にはならない。
  def prepare_habit_stats
    @habits = current_user.habits.active.order(created_at: :desc)
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id][:rate] || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id][:rate] || 0) >= 100 }
  end

  # ==========================================
  # can_create_reflection?: 振り返りボタン表示判定
  # ==========================================
  # 「日曜日の AM4:00 以降」かつ「今週がまだ完了していない」場合のみ true を返す
  #
  # 【now.hour >= 4 ではなく beginning_of_day + 4.hours を使う理由】
  # hour >= 4 は「4時台以降すべて」を意味するため問題ないが、
  # 厳密に「4:00:00 以降」を表現するなら Time 比較が安全。
  # ここでは可読性重視で hour >= 4 を使用する。
  def can_create_reflection?
    now = Time.current
    now.wday == 0 &&
      now.hour >= 4 &&
      (@current_week_reflection.new_record? || @current_week_reflection.pending?)
  end
end