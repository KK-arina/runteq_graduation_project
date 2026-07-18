# app/controllers/analytics_controller.rb
#
# ==============================================================================
# AnalyticsController（H-4: グラフ・進捗分析ページ）
# ==============================================================================
#
# 【このコントローラーの役割】
#   19番画面「グラフ・進捗分析ページ」のデータを準備する。
#   - 習慣別の週次達成率推移（折れ線グラフ用）
#   - 週次振り返りの気分スコア推移（棒グラフ用）
#   - 習慣別のストリーク（現在/最高）一覧
#   - 当月の達成率・最長ストリーク・平均気分のサマリーカード
#
# 【N+1対策の設計方針（最重要）】
#   このページは「習慣 × 週」の組み合わせでグラフを描画するため、
#   素朴に実装すると「習慣の数 × 週の数」だけクエリが発行されてしまう
#   典型的なN+1問題が起きやすい画面になる。
#
#   そこで以下の方針を徹底する:
#     ① habit_records は「期間全体」を1回の pluck で取得し、
#        Ruby（メモリ上）で habit_id と週ごとにグルーピングする。
#        → 習慣数・週数に関わらずクエリは常に1回。
#     ② habit.effective_weekly_target は内部で habit_excluded_days.size を
#        使っており、.includes(:habit_excluded_days) 済みなら
#        追加クエリなしで呼び出せる（ActiveRecordの仕様）。
#        ただし「週ごとのループの中」で呼ぶと習慣数×週数回計算してしまう
#        無駄があるため、習慣ごとに1回だけ計算してループの外に出す。
#     ③ habit_excluded_days を直接参照する際は、モデルの
#        excluded_day_numbers（内部で .pluck を使用）ではなく、
#        preload 済みの habit.habit_excluded_days.map(&:day_of_week) を使う。
#        .pluck は preload 済みでも必ずDBに問い合わせてしまうため、
#        N+1を避けるには preload済み配列を直接 map する必要がある。
#
# 【期間フィルターの設計】
#   4w（4週間）/ 12w（12週間）/ all（全期間・最大52週=1年でキャップ）の
#   3種類をクエリパラメータ ?period= で受け取る。
#   ホワイトリスト方式（PERIOD_KEYS に含まれる値のみ許可）にすることで
#   不正な値が渡された場合も安全にデフォルト値（4w）にフォールバックする。
#
# ==============================================================================

class AnalyticsController < ApplicationController
  before_action :require_login

  # PERIOD_KEYS: 期間フィルターとして許可する値のホワイトリスト
  #
  # 【なぜホワイトリスト方式にするのか（変更なし）】
  #   params[:period] はユーザーが自由に書き換えられるクエリパラメータ。
  #   想定外の値（例: ?period=DROP TABLE 等）が来ても、
  #   presence_in でこの配列に含まれる値以外は弾かれて
  #   デフォルト値（4w）にフォールバックするため安全。
  #
  # 【#I-6 変更: 定義元を ApplicationRecord に移した理由】
  #   habit_record や weekly_reflection が保存されたとき、
  #   モデルの after_commit が「4w / 12w / all すべてのキャッシュ」を消す必要がある。
  #   モデル側から AnalyticsController::PERIOD_KEYS を参照すると
  #   「モデルがコントローラーに依存する」という依存関係の逆流が起きるため、
  #   定義そのものを ApplicationRecord に移動し、こちらが参照する形にした。
  #
  #   これにより「期間の種類」の定義はアプリ内で1箇所だけになり、
  #   将来 24w を追加したときにキャッシュの消し忘れが起きない。
  #   値（%w[4w 12w all]）は従来と完全に同一のため、既存の動作・テストに影響はない。
  PERIOD_KEYS = ApplicationRecord::ANALYTICS_PERIOD_KEYS

  # CHART_COLOR_PALETTE: 習慣にカラーが未設定の場合に使う既定の配色
  # 【なぜ必要か】
  #   habits.color は任意入力（B-6で追加）のため未設定の習慣もある。
  #   未設定の習慣が複数あると全部同じ色になり折れ線グラフが見分けづらくなるため、
  #   habit.id を基準に巡回的に色を割り当てる。
  CHART_COLOR_PALETTE = %w[#3b82f6 #10b981 #f59e0b #ef4444 #8b5cf6 #ec4899 #14b8a6 #f97316].freeze

  # MAX_ALL_PERIOD_WEEKS: 「全期間」フィルターの上限週数
  # 【レビュー対応】
  #   当初は 52週（1年）でキャップしていたが、タスク要件「全期間」の
  #   文字通りの意味を尊重し、より長期間のユーザーでもグラフが破綻しないよう
  #   余裕を持たせた 260週（約5年）に拡張する。
  #   それでも上限を設ける理由は、万一データ異常（不正な created_at 等）で
  #   週数が際限なく膨らみ build_week_starts のループや
  #   描画パフォーマンスが破綻するのを防ぐ安全装置として残すため。
  MAX_ALL_PERIOD_WEEKS = 260

  def index
    # ── H-4: グラフページを開いた日時を記録する ──────────────────────────
    #
    # 【なぜ index の最初に呼ぶのか】
    #   このページを開いた「時点」を記録したいため、データ集計の前に実行する。
    #   &. は user_setting が万が一 nil（通常は after_create で必ず作られるが
    #   念のための防御）の場合に NoMethodError を防ぐ。
    #
    # 【この呼び出しが Bottom Navigation のバッジに与える効果】
    #   この行が実行された直後、同じリクエスト内でレイアウトが
    #   _bottom_navigation.html.erb をレンダリングする際に bn_ai_analysis_count が
    #   呼ばれる。current_user.user_setting は Rails の has_one アソシエーション
    #   キャッシュにより「今まさに touch_analytics_viewed_at! を呼んだのと
    #   同じオブジェクト」を参照するため、更新後の最新の
    #   last_analytics_viewed_at がそのままバッジ判定に使われる。
    #   結果として「グラフタブを開いた瞬間にバッジが消える」が実現できる。
    current_user.user_setting&.touch_analytics_viewed_at!

    # ── 期間フィルターの決定 ──────────────────────────────────────────────
    # presence_in: 「PERIOD_KEYS に含まれていれば自分自身を、
    #               含まれていなければ nil を返す」ActiveSupportのメソッド。
    # params[:period] が nil（初回アクセス）でも安全に動作する。
    @period = params[:period].presence_in(PERIOD_KEYS) || "4w"

    # today_for_record: AM4:00を1日の境界とするこのアプリ独自の「今日」。
    # 他の全コントローラー（DashboardsController等）と同じ基準を使うことで
    # 日付計算の一貫性を保つ。
    @today = HabitRecord.today_for_record

    # ── アクティブな習慣を取得（N+1対策: habit_excluded_days を事前読み込み）──
    # includes(:habit_excluded_days) がないと、習慣ごとに
    # effective_weekly_target を呼ぶたびに追加クエリが発生してしまう。
    # .to_a で配列化することで、以降の map/select/sum 等はメモリ上の操作になり
    # 「ループのたびにDBへ再アクセスする」事故を防げる。
    @habits = current_user.habits.active.includes(:habit_excluded_days).to_a

    @has_habits      = @habits.any?
    @has_reflections = current_user.weekly_reflections.completed.exists?
    @has_data        = @has_habits || @has_reflections

    # ── Empty State の場合はここで処理を終える ──────────────────────────
    # 習慣も振り返りも0件のユーザーには集計用クエリを一切発行しない。
    # ビュー側は @has_data が false のときだけ Empty State を表示する。
    return unless @has_data

    # ── #I-6: 集計結果をキャッシュから取得する ────────────────────────────
    #
    # 【なぜこのページのキャッシュが最も効果的なのか】
    #   このページは3つのSQLに加えて、
    #     「習慣の数 × 週の数」のネストしたRubyループ（build_habit_chart_data）
    #     「月の日数 × 習慣の数」のループ（build_monthly_summary）
    #   を毎回実行している。全期間（最大260週＝約5年）を選ぶと
    #   数千件の習慣記録に対してRubyの計算が走る、アプリで最も重い画面。
    #   完成したグラフ用データをそのままキャッシュすることで、
    #   2回目以降はSQLもRubyの計算も丸ごとスキップできる。
    #
    # 【expires_in: 6.hours（ISSUE の指定どおり）】
    #   after_commit による明示的な削除が主役で、これは保険。
    #   グラフは「振り返って眺めるページ」でありリアルタイム性を要求しないため、
    #   ダッシュボード（1時間）より長い6時間を設定している。
    #
    # 【キャッシュに入れるもの・入れないものの線引き】
    #   ○ 入れる: @habit_chart_data / @monthly_summary / @mood_chart_data
    #             → 数値・文字列・配列だけで構成された素のHash（Marshal 可能）
    #   ✗ 入れない: @habits
    #             → ActiveRecord のインスタンス。キャッシュすると
    #               「習慣名を変えたのにグラフの下の一覧だけ古い」といった
    #               不整合が起きるうえ、Marshal のサイズも無駄に大きくなる。
    #               毎回DBから取得する（元々1クエリなので影響はごく小さい）。
    #
    # 【キーに current_user.id を含める重要性】
    #   含め忘れると他人のグラフが表示される重大な情報漏洩になる。
    #   ApplicationRecord.analytics_cache_key が必ず user_id を含めて組み立てる。
    cached = Rails.cache.fetch(
      ApplicationRecord.analytics_cache_key(current_user.id, @period, @today),
      expires_in: 6.hours
    ) do
      build_chart_payload
    end

    # キャッシュから取り出した値をビュー用のインスタンス変数に展開する。
    # 【なぜ @週変数を減らしたのか】
    #   @weeks_count / @week_starts はビュー（analytics/index.html.erb）では
    #   使われていない内部計算用の変数だったため、
    #   build_chart_payload の中のローカル変数に格下げした。
    #   キャッシュに入れる必要がないデータを減らすことで、
    #   保存サイズと「何がキャッシュされているか」の分かりにくさを削減する。
    @habit_chart_data = cached[:habit_chart_data]
    @monthly_summary  = cached[:monthly_summary]
    @mood_chart_data  = cached[:mood_chart_data]
  end

  private

  # ── #I-6 追加: build_chart_payload ────────────────────────────────────────
  #
  # 【役割】
  #   グラフページに必要な3種類のデータを組み立てて1つのHashで返す。
  #   このメソッドの中身がまるごとキャッシュされる。
  #
  # 【なぜ1つのHashにまとめるのか】
  #   Rails.cache.fetch を3回に分けると、キャッシュの読み書きも3回になる
  #   （＝Solid Cache では SELECT が3回に増える）。
  #   3つのデータは常にセットで必要になるため、1つのキーにまとめることで
  #   キャッシュアクセスを1回に抑えられる。
  #
  # 【H-4 の N+1 対策はそのまま維持している】
  #   ・habit_records は期間全体を1回の pluck でまとめて取得
  #   ・bulk_range_start でグラフ用と当月サマリー用の範囲を統合して1クエリに集約
  #   ・target は習慣ごとに1回だけ計算してループの外に出す
  #   これらの設計は一切変更していない。
  #   （キャッシュが効かない初回アクセス時のクエリ数は今までと同一）
  def build_chart_payload
    # weeks_count / chart_period_start / month_start / bulk_range_start / week_starts は
    # このメソッドの中でしか使わないためローカル変数にする（元は @ 付きだった）。
    weeks_count = resolve_weeks_count(@period)

    # チャートに表示する期間の開始日（必ず月曜日になる）
    chart_period_start = @today.beginning_of_week(:monday) - (weeks_count - 1).weeks

    # 当月サマリー用の月初日
    month_start = @today.beginning_of_month

    # ── 習慣記録の一括取得（N+1対策の核心部分・H-4 から変更なし）──────────
    #
    # 【bulk_range_start の意味】
    #   チャート期間の開始日と「当月の月初日」のうち、より早い方を
    #   取得範囲の開始点にする。これにより、
    #     ① 折れ線グラフ用のデータ（chart_period_start 〜 today）
    #     ② 当月サマリー用のデータ（month_start 〜 today）
    #   の両方を「1回のクエリ」でカバーできる。
    bulk_range_start = [ chart_period_start, month_start ].min

    week_starts = build_week_starts(chart_period_start, @today)

    habit_records =
      if @has_habits
        HabitRecord
          .where(
            user:        current_user,
            habit_id:    @habits.map(&:id),
            record_date: bulk_range_start..@today,
            deleted_at:  nil
          )
          .pluck(:habit_id, :record_date, :completed, :numeric_value)
      else
        []
      end

    # ── 気分スコアの推移データ（棒グラフ用・H-4 から変更なし）──────────────
    # mood が nil の振り返り（気分スコア未入力）はグラフに含めない。
    reflections = current_user.weekly_reflections
                              .completed
                              .where(week_start_date: chart_period_start..@today)
                              .where.not(mood: nil)
                              .order(:week_start_date)
                              .pluck(:week_start_date, :mood)

    # 【戻り値がキャッシュされる】
    #   シンボルキーのHashで返す。Marshal でシリアライズされ、
    #   solid_cache_entries.value（bytea）に保存される。
    #   中身は数値・文字列・Date・配列のみのため安全に復元できる。
    {
      habit_chart_data: build_habit_chart_data(@habits, week_starts, habit_records),
      monthly_summary:  build_monthly_summary(@habits, habit_records, month_start),
      mood_chart_data:  build_mood_chart_data(reflections)
    }
  end
  # ──────────────────────────────────────────────────────────────────────────

  # ============================================================
  # resolve_weeks_count: 期間フィルターに対応する週数を返す
  # ============================================================
  #
  # 【"all"（全期間）の計算ロジック】
  #   ユーザーが習慣を作成した日、または最初に振り返りを行った週のうち
  #   より早い方を起点とし、そこから現在までの週数を計算する。
  #   何もデータがない場合（理論上は @has_data チェックで弾かれるため
  #   到達しないが、念のため）は 4 にフォールバックする。
  #
  # 【clamp(1, 52) で上限を設ける理由】
  #   非常に古いアカウント（数年分のデータ）の場合、週数が際限なく
  #   大きくなるとグラフが見づらくなる上、build_week_starts の
  #   ループ回数も増えてしまう。1年（52週）を上限にすることで
  #   パフォーマンスと可読性の両方を担保する。
  def resolve_weeks_count(period)
    case period
    when "12w"
      12
    when "all"
      earliest_habit      = current_user.habits.minimum(:created_at)&.to_date
      earliest_reflection = current_user.weekly_reflections.minimum(:week_start_date)
      earliest = [ earliest_habit, earliest_reflection ].compact.min

      return 4 if earliest.nil?

      weeks = ((Date.current - earliest).to_i / 7.0).ceil + 1
      weeks.clamp(1, MAX_ALL_PERIOD_WEEKS)
    else
      # "4w" または不正な値の場合は常に4週間
      4
    end
  end

  # ============================================================
  # build_week_starts: 期間内の「各週の月曜日」の配列を作る
  # ============================================================
  # 例: period_start が 6/1（月）、today が 6/17（水）なら
  #     [6/1, 6/8, 6/15] という3週分の配列を返す。
  # この配列がそのままグラフのX軸ラベルの元になる。
  def build_week_starts(period_start, today)
    current_week_start = today.beginning_of_week(:monday)
    weeks  = []
    cursor = period_start
    while cursor <= current_week_start
      weeks << cursor
      cursor += 7.days
    end
    weeks
  end

  # ============================================================
  # build_habit_chart_data: 折れ線グラフ用データを組み立てる
  # ============================================================
  #
  # 【戻り値の形】
  #   { labels: ["6/1", "6/8", ...], datasets: [ { label:, data:, color: }, ... ] }
  #   Chart.js にそのまま渡せる形式（JSON化してビューに渡す）。
  #
  # 【grouped ハッシュの設計】
  #   habit_records（pluckで取得した生データ）を
  #   [habit_id, 週の月曜日] をキーにしたハッシュへ変換する。
  #   これにより「特定の習慣の特定の週のレコード一覧」を
  #   O(1) に近い速度で取り出せるようになり、
  #   習慣×週のネストしたループの中でDBに一切アクセスせずに済む。
  def build_habit_chart_data(habits, week_starts, habit_records)
    return { labels: [], datasets: [] } if habits.empty? || week_starts.empty?

    chart_start = week_starts.first
    chart_end   = week_starts.last + 6.days

    grouped = Hash.new { |hash, key| hash[key] = [] }
    habit_records.each do |habit_id, record_date, completed, numeric_value|
      # bulk_range_start はチャート期間より前（月初）から取得している場合があるため、
      # チャート表示範囲外のレコードはここでスキップする。
      next if record_date < chart_start || record_date > chart_end

      week_start = record_date.beginning_of_week(:monday)
      grouped[[ habit_id, week_start ]] << [ completed, numeric_value ]
    end

    labels = week_starts.map { |ws| ws.strftime("%-m/%-d") }

    datasets = habits.each_with_index.map do |habit, index|
      # ── target（分母）は習慣ごとに1回だけ計算する（N+1対策）──────────
      # check_type の effective_weekly_target は habit_excluded_days.size を
      # 使っており、内容は「週によって変わらない固定値」のため、
      # week_starts.map の「外」で1回だけ計算してループ内で使い回す。
      target = habit.check_type? ? habit.effective_weekly_target : habit.weekly_target

      data = week_starts.map do |week_start|
        next 0 if target.zero?

        entries = grouped[[ habit.id, week_start ]]

        if habit.check_type?
          completed_count = entries.count { |completed, _| completed }
          ((completed_count.to_f / target) * 100).clamp(0, 100).round
        else
          numeric_sum = entries.sum { |_, numeric_value| numeric_value.to_f }
          ((numeric_sum / target) * 100).clamp(0, 100).round
        end
      end

      {
        label: habit.name,
        data:  data,
        # habit.color が未設定（nil・空文字）ならパレットから巡回的に色を割り当てる
        color: habit.color.presence || CHART_COLOR_PALETTE[index % CHART_COLOR_PALETTE.size]
      }
    end

    { labels: labels, datasets: datasets }
  end

  # ============================================================
  # build_mood_chart_data: 気分スコアの棒グラフ用データを組み立てる
  # ============================================================
  def build_mood_chart_data(reflections)
    {
      labels: reflections.map { |week_start, _mood| week_start.strftime("%-m/%-d") },
      data:   reflections.map { |_week_start, mood| mood }
    }
  end

  # ============================================================
  # build_monthly_summary: 当月サマリーカード用データを組み立てる
  # ============================================================
  #
  # 【avg_rate（当月の平均達成率）の計算方針】
  #   チェック型: 「月初から今日までの実施可能日数のうち何日達成したか」
  #   数値型:     「1日あたりの目標値 × 経過日数」を分母にした達成率
  #   全アクティブ習慣の単純平均を取る。
  #
  # 【habit.habit_excluded_days.map(&:day_of_week) を使う理由（N+1対策）】
  #   Habit モデルの excluded_day_numbers メソッドは内部で
  #   habit_excluded_days.pluck(:day_of_week) を使っているが、
  #   .pluck は preload 済みのアソシエーションであっても
  #   「必ずDBに問い合わせる」という ActiveRecord の仕様がある。
  #   一方 .map はメモリ上の preload 済み配列に対して動作するため
  #   追加クエリが発生しない。N+1を確実に防ぐため、ここでは
  #   excluded_day_numbers を使わず habit_excluded_days.map(&:day_of_week) を
  #   直接呼び出す設計にしている。
  #
  # 【excluded_days をループの外で1回だけ計算する理由】
  #   (month_start..today).count { ... } のブロック内で
  #   habit.habit_excluded_days を毎回呼ぶと「月の日数」回 同じ計算を
  #   繰り返す無駄が生じる（DBは叩かないがCPU上は非効率）。
  #   1習慣につき1回だけ計算してローカル変数に保持する。
  def build_monthly_summary(habits, habit_records, month_start)
    today = HabitRecord.today_for_record

    # ── 当月の平均気分スコア ──────────────────────────────────────────────
    # 習慣の有無に関わらず計算できるため habits.empty? のガードより先に出す。
    avg_mood_raw = current_user.weekly_reflections
                               .completed
                               .where(week_start_date: month_start..today)
                               .where.not(mood: nil)
                               .average(:mood)
    avg_mood = avg_mood_raw.present? ? avg_mood_raw.round(1) : nil

    if habits.empty?
      return {
        avg_rate:       0,
        longest_streak: 0,
        avg_mood:       avg_mood,
        month_label:    month_start.strftime("%Y年%-m月")
      }
    end

    # habit_id ごとにレコードをグルーピングする（メモリ内処理・追加クエリなし）
    records_by_habit = habit_records.group_by { |habit_id, *_rest| habit_id }

    habit_rates = habits.map do |habit|
      entries = (records_by_habit[habit.id] || [])
                  .select { |_habit_id, record_date, *_rest| record_date >= month_start }

      if habit.check_type?
        excluded_days = habit.habit_excluded_days.map(&:day_of_week)
        elapsed_days  = (month_start..today).count { |d| !excluded_days.include?(d.wday) }
        next 0 if elapsed_days.zero?

        completed_count = entries.count { |_h, _d, completed, _n| completed }
        ((completed_count.to_f / elapsed_days) * 100).clamp(0, 100).round
      else
        elapsed_days  = (today - month_start).to_i + 1
        daily_target  = habit.weekly_target / 7.0
        target_so_far = daily_target * elapsed_days
        next 0 if target_so_far <= 0

        numeric_sum = entries.sum { |_h, _d, _c, numeric_value| numeric_value.to_f }
        ((numeric_sum / target_so_far) * 100).clamp(0, 100).round
      end
    end

    {
      avg_rate:       (habit_rates.sum / habit_rates.size.to_f).round,
      longest_streak: habits.map(&:longest_streak).max || 0,
      avg_mood:       avg_mood,
      month_label:    month_start.strftime("%Y年%-m月")
    }
  end
end