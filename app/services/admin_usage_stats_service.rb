# app/services/admin_usage_stats_service.rb
#
# ==============================================================================
# AdminUsageStatsService: 管理画面（/admin）に表示する全体の集計
# ==============================================================================
#
# 【このファイルの役割】
#   「何人が登録しているか」「どのくらい使われているか」「どこで離脱しているか」を
#   数字で返す。画面（Admin::DashboardsController）からは fetch を呼ぶ。
#
# 【集計の対象】
#   必ず User.countable_for_usage（app/models/concerns/usage_countable.rb）の人だけを数える。
#   退会済み・デモ／テスト用アカウント・管理者自身は含めない。
#
# 【プライバシー】
#   返すのは件数・割合・日付だけ。振り返りのコメント・PMVV・メモなどの「入力内容」は読まない。
#   危機ワードの検出（ai_analyses.crisis_detected）も、人数が少ないと誰のことか推測できるため数えない。
#
# 【DB（Neon）の負荷を抑える工夫】
#   ① すべて COUNT の SQL で数え、レコードを Ruby に読み込まない（N+1 も起きない）
#   ② 結果を Solid Cache に10分間保存する（fetch）。10分以内に開き直しても集計の SQL は走らない
#   ③ キャッシュに入れるのは数字と日付だけ（個人情報を solid_cache_entries に複製しない）
# ==============================================================================
class AdminUsageStatsService
  # キャッシュのキー（中身の形を変えたら v2 のように番号を上げ、古いキャッシュを使わないようにする）
  CACHE_KEY = "admin:usage_stats:v1".freeze

  # キャッシュを使う時間（管理画面の数字は数分遅れても困らないため）
  CACHE_TTL = 10.minutes

  # 週ごとのグラフに出す週の数
  WEEKS = 12

  # ファネルの「続けて記録している」とみなす日数
  STREAK_DAYS_FOR_FUNNEL = 7

  # fetch
  #
  # 【役割】キャッシュがあればそれを返し、なければ集計してキャッシュに保存してから返す。
  def self.fetch
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.call }
  end

  # call
  #
  # 【役割】集計をすべて実行し、画面で使う形のハッシュにまとめて返す。
  #   キーは Symbol、値は数字・日付・数字のハッシュだけにしている（キャッシュに入れやすくするため）。
  def call
    total = base_users.count

    {
      generated_at: Time.current,
      total_users: total,
      provider_breakdown: base_users.group(:provider).count,
      signups_by_week: weekly_series(signup_counts_by_week),
      weekly_recording_users: weekly_series(recording_user_counts_by_week),
      active_7d: base_users.where(last_active_at: 7.days.ago..).count,
      active_30d: base_users.where(last_active_at: 30.days.ago..).count,
      onboarding_passed: onboarding_passed_count,
      onboarding_rate: percent(onboarding_passed_count, total),
      pmvv_registered: base_users.where(id: UserPurpose.select(:user_id)).count,
      habits_active: habits.where(deleted_at: nil, archived_at: nil).count,
      habit_records_total: habit_records.count,
      habit_records_7d: habit_records.where(record_date: (Date.current - 6.days)..).count,
      reflections_total: reflections.count,
      reflections_completed: reflections_completed_count,
      reflections_completion_rate: percent(reflections_completed_count, reflections.count),
      reflections_completed_without_ai: reflections.completed.where.not(ai_skipped_at: nil).count,
      ai_analyses_total: ai_analyses_count,
      line_connected: base_users.where.not(line_user_id: nil).count,
      line_notification_enabled: line_notification_enabled_count,
      remember_users: RememberToken.active.where(user_id: user_ids).distinct.count(:user_id),
      funnel: funnel(total)
    }
  end

  private

  # ── 集計の土台（すべての集計はここから始める）─────────────────────────

  # 集計の対象のユーザー
  #   @base_users ||= で、同じ集計の中では同じ条件のものを使い回す（SQL はまだ実行されない）
  def base_users
    @base_users ||= User.countable_for_usage
  end

  # 対象のユーザーの id だけを取り出す「サブクエリ」
  #   where(user_id: user_ids) と書くと、SQL の中で IN (SELECT id FROM users WHERE ...) になる。
  #   id を Ruby に読み込まないので、人数が増えても1本の SQL のまま。
  def user_ids
    @user_ids ||= base_users.select(:id)
  end

  # 対象のユーザーの習慣（削除・アーカイブ済みも含む。用途ごとに絞り込む）
  #   Habit.active は画面用の並び順（order）が付いているため使わない
  #   （並び順付きで COUNT や GROUP BY をすると、PostgreSQL のエラーや警告になる）
  def habits
    Habit.where(user_id: user_ids)
  end

  # 対象のユーザーの習慣の記録（削除済みの記録は数えない）
  def habit_records
    HabitRecord.where(user_id: user_ids, deleted_at: nil)
  end

  # 対象のユーザーの週次振り返り
  def reflections
    WeeklyReflection.where(user_id: user_ids)
  end

  # ── 個別の集計 ────────────────────────────────────────────────────

  # オンボーディングを通過した人数（完了・スキップのどちらでも first_login_at が入る）
  #   rate の計算でも使うため、@ で覚えて SQL を1回にする
  def onboarding_passed_count
    @onboarding_passed_count ||= base_users.where.not(first_login_at: nil).count
  end

  # 完了した振り返りの数（completion_rate の計算でも使う）
  def reflections_completed_count
    @reflections_completed_count ||= reflections.completed.count
  end

  # AI 分析の実行数（再分析も1回として数える）
  #   ai_analyses には user_id がないため、振り返り・PMVV を通して対象のユーザーのものに絞る
  def ai_analyses_count
    by_reflection = AiAnalysis.where(weekly_reflection_id: reflections.select(:id))
    by_purpose    = AiAnalysis.where(user_purpose_id: UserPurpose.where(user_id: user_ids).select(:id))
    by_reflection.or(by_purpose).count
  end

  # LINE と連携していて、LINE 通知も ON にしている人数
  def line_notification_enabled_count
    base_users.where.not(line_user_id: nil)
              .joins(:user_setting)
              .where(user_settings: { line_notification_enabled: true })
              .count
  end

  # ── 週ごとの集計 ──────────────────────────────────────────────────

  # グラフに出す12週分の「週の始まり（月曜日）」の日付
  def week_starts
    @week_starts ||= begin
      this_week = Date.current.beginning_of_week(:monday)
      (0...WEEKS).map { |i| this_week - (WEEKS - 1 - i).weeks }
    end
  end

  # 週ごとの新規登録数
  #   DATE_TRUNC('week', ...) は PostgreSQL の関数で、日時を「その週の月曜日の0時」に切り捨てる
  #   （PostgreSQL の週は月曜日始まり）。created_at は東京の時刻で保存している
  #   （config/application.rb の default_timezone = :local）ため、そのまま切り捨てられる。
  def signup_counts_by_week
    base_users.where(created_at: week_starts.first.beginning_of_day..)
              .group(Arel.sql("DATE_TRUNC('week', users.created_at)"))
              .count
  end

  # 週ごとの「習慣を記録した人数」（同じ人は1週に1人として数える）
  #   record_date は日付（date 型）。::timestamp で日時の型にしてから切り捨てる
  #   （date のまま渡すと、タイムゾーン付きの型になり、日付がずれることがあるため）
  def recording_user_counts_by_week
    habit_records.where(record_date: week_starts.first..)
                 .group(Arel.sql("DATE_TRUNC('week', habit_records.record_date::timestamp)"))
                 .distinct
                 .count(:user_id)
  end

  # { 週の始まりの日時 => 件数 } を、12週分の [{ week_start:, count: }] にそろえる
  #   データのない週も 0 として入れ、グラフの横軸が抜けないようにする
  def weekly_series(counts_by_time)
    counts_by_date = counts_by_time.transform_keys(&:to_date)
    week_starts.map { |week_start| { week_start: week_start, count: counts_by_date.fetch(week_start, 0) } }
  end

  # ── 離脱が分かるファネル ──────────────────────────────────────────

  # どの段階まで進んだ人が何人いるかを、順番どおりの配列で返す
  #   distinct.count(:user_id): 同じ人の習慣や記録が何件あっても、1人として数える
  def funnel(total)
    steps = [
      [ :registered,           total ],
      [ :onboarding_passed,    onboarding_passed_count ],
      [ :habit_created,        habits.distinct.count(:user_id) ],
      [ :first_record,         habit_records.distinct.count(:user_id) ],
      [ :recorded_7_days,      users_recorded_at_least(STREAK_DAYS_FOR_FUNNEL) ],
      [ :reflection_completed, reflections.completed.distinct.count(:user_id) ]
    ]
    steps.map { |key, count| { key: key, count: count, rate: percent(count, total) } }
  end

  # 記録した日が days 日以上ある人数
  #   GROUP BY user_id + HAVING で「記録した日の数が days 以上の人」に絞り、その人数を数える。
  #   .count はグループごとの件数のハッシュを返すので、.size で人数にする（人数分の数字だけを読む）
  def users_recorded_at_least(days)
    habit_records.group(:user_id)
                 .having("COUNT(DISTINCT habit_records.record_date) >= ?", days)
                 .count
                 .size
  end

  # ── 計算の部品 ────────────────────────────────────────────────────

  # 割合（%）を小数第1位まで返す。分母が 0 のときは 0（0 で割るエラーを防ぐ）
  def percent(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator * 100.0 / denominator).round(1)
  end
end
