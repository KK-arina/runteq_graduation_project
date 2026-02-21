# app/controllers/weekly_reflections_controller.rb

class WeeklyReflectionsController < ApplicationController
  before_action :require_login

  def index
    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)
    @can_create_reflection    = can_create_reflection?

    @past_reflections = current_user.weekly_reflections
                                    .completed
                                    .recent
                                    # ↓ 修正② habit_summaries の N+1 対策
                                    # ビューで reflection.habit_summaries を参照する際に
                                    # 反復ごとにDBアクセスが走るのを防ぎます。
                                    # includes を付けることで「関連データを最初にまとめて取得」します。
                                    # 振り返り件数が増えても1〜2回のSQLで済む設計になります。
                                    .includes(:habit_summaries)

    @habits = current_user.habits.active.order(created_at: :desc)

    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    # ↓ 修正③ ゼロ除算を防ぎつつ可読性を上げた平均達成率の計算
    # @habits.empty? の one-liner でも防げますが、
    # rates という変数に一度切り出すことで意図がより明確になります。
    # any? で「要素が1件以上あるか」を確認してから割り算を行います。
    rates = @habit_stats.values.map { |s| s[:rate] }
    @overall_rate = if rates.any?
                      (rates.sum.to_f / rates.size).round
                    else
                      0
                    end
  end

  private

  # ===========================================================
  # can_create_reflection?
  # 「今週の振り返りを作成できる状態か」を判定するメソッド
  #
  # 修正① 変更前との違い:
  #   変更前: HabitRecord.today_for_record（Date型）で wday だけ判定していた
  #   変更後: Time.current（DateTime型）で「日曜日 かつ AM4:00以降」を明示的に判定する
  #
  # なぜ Time.current を使うのか:
  #   Time.now はサーバーのローカル時刻を返しますが、
  #   Time.current は Rails の config.time_zone に従ったタイムゾーン補正済みの時刻を返します。
  #   本番環境でサーバーのタイムゾーンがズレていても正確に動作させるためです。
  # ===========================================================
  def can_create_reflection?
    # Time.current でタイムゾーン補正済みの現在時刻を取得します
    now = Time.current

    # wday == 0 は「日曜日」を意味します（0:日, 1:月, ..., 6:土）
    is_sunday = now.wday == 0

    # 「今日の AM4:00」を生成して、現在時刻がそれ以降かを判定します。
    # beginning_of_day は「その日の 00:00:00」を返すメソッドです。
    # そこに 4.hours を足すことで「今日の 04:00:00」が得られます。
    # >= を使うことで「AM4:00ちょうど」も含めて作成可能にしています。
    is_after_4am = now >= now.beginning_of_day + 4.hours

    # new_record?:  DBに保存されていない（= まだ振り返りを作っていない）
    # pending?:     保存済みだが未完了（振り返り途中）
    # どちらでも「まだ今週の振り返りが終わっていない」と判断します
    is_not_completed = @current_week_reflection.new_record? ||
                       @current_week_reflection.pending?

    # 3条件すべてが true の場合のみ、振り返りボタンを表示します
    is_sunday && is_after_4am && is_not_completed
  end
end