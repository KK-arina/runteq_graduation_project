# app/controllers/weekly_reflections_controller.rb
#
# ═══════════════════════════════════════════════════════════════════
# 【このファイルの役割】
#   週次振り返り（WeeklyReflection）に関するHTTPリクエストを受け取り、
#   適切なデータ処理とビュー表示を担当するコントローラー。
#   Rails の MVC アーキテクチャにおける "C（Controller）" の部分。
# ═══════════════════════════════════════════════════════════════════
#
# 【Issue #29 での変更箇所】
#
#   index / new / create の @habit_stats 計算方法を変更。
#
#   変更前:
#     @habit_stats = @habits.each_with_object({}) do |habit, hash|
#       hash[habit.id] = habit.weekly_progress_stats(current_user)
#     end
#     → habits が N件あると habit_records へのSQLが N回発行される（N+1問題）
#
#   変更後:
#     @habit_stats = build_habit_stats(@habits, current_user)
#     → private メソッドで今週の habit_records を1回のSQLで一括取得し、
#       メモリ上で集計するため SQLは常に2回（habits取得 + records一括取得）で済む
#
#   index / new / create / rescue 節すべての @habit_stats 計算を
#   build_habit_stats メソッドに統一した（DRY原則）。
#
# 【Issue #25 での変更箇所（create アクションのみ）】
#   （変更内容は以前のコメントを参照）

class WeeklyReflectionsController < ApplicationController
  before_action :require_login
  before_action :set_weekly_reflection, only: [:show]

  # ---------------------------------------------------------------
  # index アクション
  # GET /weekly_reflections
  # ---------------------------------------------------------------
  def index
    # completed: 振り返り完了済みのものだけ取得
    # recent:    week_start_date の新しい順に並べる
    # includes(:habit_summaries): habit_summaries を一括取得（N+1防止）
    #   → 振り返り一覧ページで各振り返りの habit_summaries を表示するとき、
    #     includes なしでは振り返りの数だけSQLが発行されてしまう
    @weekly_reflections = current_user.weekly_reflections
                                      .completed
                                      .recent
                                      .includes(:habit_summaries)

    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    @habits = current_user.habits.active

    # ============================================================
    # Issue #29: N+1対策 - build_habit_stats に統一
    # ============================================================
    # 変更前は habit ごとに weekly_progress_stats を呼んでいたため
    # habits の件数だけ habit_records への SQL が発行されていた（N+1）。
    # build_habit_stats では今週分の habit_records を1回まとめて取得し、
    # Rubyのメモリ上で集計するため SQL は2回で済む。
    @habit_stats = build_habit_stats(@habits, current_user)
  end

  # ---------------------------------------------------------------
  # new アクション
  # GET /weekly_reflections/new
  # ---------------------------------------------------------------
  def new
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.is_locked?
      redirect_to @weekly_reflection, notice: "今週の振り返りは既に完了しています。"
      return
    end

    @habits = current_user.habits.active

    # Issue #29: build_habit_stats に統一（N+1対策）
    @habit_stats = build_habit_stats(@habits, current_user)

    # 達成済み・未達成の振り分け（ビューで2つのリストを表示するため）
    # @habit_stats から rate を取り出して比較するだけなので、追加のSQLは不要
    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
  end

  # ---------------------------------------------------------------
  # create アクション
  # POST /weekly_reflections
  # ---------------------------------------------------------------
  def create
    @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    if @weekly_reflection.persisted? && @weekly_reflection.is_locked?
      redirect_to @weekly_reflection, notice: "今週の振り返りは既に完了しています。"
      return
    end

    @weekly_reflection.assign_attributes(weekly_reflection_params)

    # Issue #25: ロック状態を「保存前に」記録する
    was_locked = current_user.locked?

    ActiveRecord::Base.transaction do
      @weekly_reflection.save!
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@weekly_reflection)
      @weekly_reflection.complete!

      if was_locked
        last_week_start = WeeklyReflection.current_week_start_date - 7.days
        last_week = current_user.weekly_reflections
                                .find_by(week_start_date: last_week_start)
        last_week&.complete!
      end
    end

    current_user.reload

    if was_locked
      redirect_to dashboard_path,
                  flash: { unlock: "🔓 振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！" }
    else
      redirect_to weekly_reflections_path,
                  notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
    end

  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.error("WeeklyReflection create error: #{e.message}")

    @habits = current_user.habits.active

    # Issue #29: rescue 節でも build_habit_stats に統一（N+1対策）
    @habit_stats = build_habit_stats(@habits, current_user)

    @achieved_habits     = @habits.select { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }
    @not_achieved_habits = @habits.reject { |h| (@habit_stats[h.id]&.dig(:rate) || 0) >= 100 }

    flash.now[:alert] = "保存に失敗しました。入力内容を確認してください。"
    render :new, status: :unprocessable_entity
  end

  # ---------------------------------------------------------------
  # show アクション
  # GET /weekly_reflections/:id
  # ---------------------------------------------------------------
  def show
    # includes(:habit): habit_summaries から habit を参照するとき
    # includes なしでは summaries の数だけ habits への SQL が発行される（N+1）
    # includes(:habit) で habit_summaries と habits を一括取得する
    @habit_summaries = @weekly_reflection.habit_summaries
                                         .includes(:habit)
                                         .order(achievement_rate: :desc)

    @overall_achievement_rate = calculate_overall_achievement_rate
  end

  private

  def calculate_overall_achievement_rate
    return 0 if @habit_summaries.empty?

    (@habit_summaries.map(&:achievement_rate).sum / @habit_summaries.size.to_f).round(1)
  end

  def set_weekly_reflection
    @weekly_reflection = current_user.weekly_reflections.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to weekly_reflections_path, alert: "振り返りが見つかりませんでした。"
  end

  def weekly_reflection_params
    params.require(:weekly_reflection).permit(:reflection_comment)
  end

  # ============================================================
  # Issue #29: N+1対策用ヘルパーメソッド（レビュー反映版）
  # ============================================================
  # build_habit_stats
  #
  # 【変更履歴】
  #   レビュー指摘を受けて group_by → .group(:habit_id).count に変更。
  #
  # 【変更前の問題点】
  #   .group_by(&:habit_id) はRuby側（メモリ上）でグループ化していた。
  #   これは「全レコードをメモリにロードしてからRubyで仕分ける」処理なので
  #   習慣数×週の記録件数分のActiveRecordオブジェクトが生成されていた。
  #
  # 【変更後の改善点】
  #   .group(:habit_id).count はDB側（SQL）でGROUP BY + COUNTを実行する。
  #   → ActiveRecordオブジェクトを1つも生成しない
  #   → メモリに全レコードをロードしない
  #   → { habit_id => count } の軽量なHashだけが返ってくる
  #
  # 【発行されるSQLの違い】
  #   変更前:
  #     SELECT * FROM habit_records WHERE user_id=? AND habit_id IN(?) AND ...
  #     → 全レコードのデータをメモリに取得してRubyで仕分ける
  #
  #   変更後:
  #     SELECT habit_id, COUNT(*) FROM habit_records
  #     WHERE user_id=? AND habit_id IN(?) AND record_date BETWEEN ? AND ?
  #     AND completed=true
  #     GROUP BY habit_id
  #     → DBが集計して { habit_id => 件数 } だけを返す。データ転送量が最小。
  #
  # 【引数】
  #   habits  - 集計対象の習慣の ActiveRecord::Relation
  #   user    - 集計対象のユーザー
  #
  # 【戻り値】
  #   Hash: { habit_id => { rate: Integer, completed_count: Integer } }
  #   例:   { 1 => { rate: 71, completed_count: 5 },
  #            2 => { rate: 100, completed_count: 7 } }
  def build_habit_stats(habits, user)
    # ── Step 1: 今週の日付範囲を計算する ──────────────────────────
    # HabitRecord.today_for_record: AM4:00基準の「今日」を返すモデルメソッド
    # beginning_of_week(:monday): 今週の月曜日（ActiveSupportのメソッド）
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    # ── Step 2: DB側で集計する（ここが最大の最適化ポイント）──────────
    # .group(:habit_id).count
    #   → SQL: SELECT habit_id, COUNT(*) FROM habit_records
    #          WHERE ... GROUP BY habit_id
    #   → 戻り値: { habit_id(Integer) => count(Integer) }
    #     例: { 1 => 5, 3 => 7 }
    #
    # 【なぜ group_by(&:habit_id) ではなくこちらが優れているか】
    #   group_by は「全レコードをメモリに取ってからRubyで仕分ける」
    #   .group.count は「DBが集計してから件数だけを返す」
    #   習慣が10個・週7日なら最大70件のオブジェクト生成 vs 件数のHashだけ
    #   → メモリ使用量・処理速度ともに .group.count が大幅に優れる
    records_count_by_habit = HabitRecord
      .where(user: user, habit: habits, record_date: week_range, completed: true)
      .group(:habit_id)
      .count
    # → { 1 => 5, 2 => 3, 4 => 7 } のようなHashが返る

    # ── Step 3: 各習慣の達成率をメモリ上で計算する ─────────────────
    # この時点でDBへのアクセスはゼロ。records_count_by_habit を参照するだけ。
    habits.each_with_object({}) do |habit, hash|
      # records_count_by_habit[habit.id]
      #   → DBが返したHashからこの習慣の完了数を取り出す
      # || 0
      #   → 今週1件も記録がない習慣はHashにキーが存在しないため
      #     nil になる。nil || 0 で 0 として扱う。
      #     （group_by版の .to_a.size より意図が明確）
      completed_count = records_count_by_habit[habit.id] || 0

      # ゼロ除算ガード: weekly_target が 0 の場合は rate = 0 を返す
      # （バリデーションで1以上が保証されているが念のため）
      rate = if habit.weekly_target.zero?
               0
             else
               # .to_f: 整数同士の割り算で小数が切り捨てられるのを防ぐ
               # .clamp(0, 100): 目標超過時でも100%を上限にする
               # .floor: 小数点以下を切り捨てて整数にする（表示用）
               ((completed_count.to_f / habit.weekly_target) * 100)
                 .clamp(0, 100)
                 .floor
             end

      # { habit_id => { rate:, completed_count: } } の形でハッシュに追加
      hash[habit.id] = { rate: rate, completed_count: completed_count }
    end
  end
end