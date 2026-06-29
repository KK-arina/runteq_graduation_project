# app/services/user_context_builder_service.rb
#
# ==============================================================================
# UserContextBuilderService（パーソナライズAIコンテキスト生成サービス）
# ==============================================================================
#
# 【このサービスの役割】
#   過去8週間の行動データを分析し、AIプロンプトに注入する
#   パーソナライズコンテキスト（context_summary）を生成して
#   ai_user_profiles テーブルに保存する。
#
# 【インコンテキスト学習とは】
#   モデルのファインチューニング（GPU・大量データ・莫大なコスト）をせずに、
#   蓄積された行動データをプロンプトに含めることで
#   AIがユーザー個人の傾向を踏まえた提案をできるようにする手法。
# ==============================================================================
class UserContextBuilderService
  # ============================================================
  # 定数定義
  # ============================================================

  # 70%以上 → 「継続できている習慣」とみなす閾値
  HIGH_ACHIEVEMENT_THRESHOLD = 70

  # 40%未満 → 「継続が難しい習慣」とみなす閾値
  LOW_ACHIEVEMENT_THRESHOLD  = 40

  # 分析対象の週数（過去8週間）
  ANALYSIS_WEEKS = 8

  # プロファイルが「古い」と判定する日数
  # 【AiUserProfile#stale? もこの定数を参照する（二重管理を防ぐ）】
  STALE_DAYS = 7

  # context_summary の最大文字数
  # 【理由】将来的にサマリーが際限なく長くなるのを防ぎ、
  #   プロンプトのトークン数（=API課金）が増えすぎないようにする
  MAX_SUMMARY_LENGTH = 3000

  # ネガティブキーワード（形態素解析不要・文字列マッチング方式）
  NEGATIVE_KEYWORDS = %w[
    疲れ 疲労 しんどい つらい 辛い きつい 続かない やる気
    モチベーション 時間がない 仕事 残業 体調 眠れない 睡眠
  ].freeze

  # ポジティブキーワード
  POSITIVE_KEYWORDS = %w[
    達成 できた 良かった 嬉しい 楽しい 続けられた 頑張れた
    改善 成長 習慣化 充実
  ].freeze

  # ============================================================
  # クラスメソッド
  # ============================================================

  # self.context_text_for(user)
  # ----------------------------------------------------------
  # 【役割】
  #   WeeklyReflectionAnalysisJob 等のプロンプト生成時に呼ばれる。
  #   プロファイルが存在すれば context_summary を、
  #   存在しなければ空文字を返す（フォールバック）。
  #
  # 【user.nil? チェックを最初に行う理由】
  #   user が nil のまま user.ai_user_profile を呼ぶと
  #   NoMethodError が発生するため、事前にガードする。
  # ----------------------------------------------------------
  def self.context_text_for(user)
    # user が nil の場合は早期リターンで空文字を返す
    return "" if user.nil?

    profile = user.ai_user_profile
    return "" if profile.nil?
    return "" if profile.context_summary.blank?

    profile.context_summary
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  def initialize(user:)
    @user = user
  end

  # call
  # ----------------------------------------------------------
  # 【戻り値の設計について】
  #   UpdateAiProfileJob から呼ばれるのみで、呼び出し側は
  #   success/failure の判定にしか使わない。
  #   { success: true/false, error: } というシンプルなハッシュを返す。
  #   profile オブジェクト自体は返さない（呼び出し元が使わないため）。
  # ----------------------------------------------------------
  def call
    eight_weeks_ago = ANALYSIS_WEEKS.weeks.ago.to_date

    habit_patterns    = analyze_habit_patterns(eight_weeks_ago)
    reflection_trends = analyze_reflection_trends(eight_weeks_ago)
    proposal_adoption = analyze_proposal_adoption

    summary = generate_context_summary(
      habit_patterns:    habit_patterns,
      reflection_trends: reflection_trends,
      proposal_adoption: proposal_adoption
    )

    # context_summary の最大長を制限する
    # 【理由】将来的に習慣・振り返りデータが大量になっても
    #   プロンプトのトークン数が MAX_SUMMARY_LENGTH 文字を超えないようにする。
    #   truncate は Rails の String 拡張メソッド。
    truncated_summary = summary.truncate(MAX_SUMMARY_LENGTH, omission: "\n（以下省略）")

    profile = AiUserProfile.find_or_initialize_by(user: @user)
    profile.assign_attributes(
      habit_patterns:    habit_patterns,
      reflection_trends: reflection_trends,
      proposal_adoption: proposal_adoption,
      context_summary:   truncated_summary,
      analyzed_at:       Time.current
    )
    profile.save!

    Rails.logger.info "[UserContextBuilderService] 分析完了: user_id=#{@user.id}, summary_length=#{truncated_summary.length}"

    { success: true }

  rescue ActiveRecord::RecordInvalid => e
    # バリデーションエラー（uniqueness 違反など）
    Rails.logger.error "[UserContextBuilderService] バリデーションエラー: user_id=#{@user.id}, error=#{e.message}"
    { success: false, error: e.message }

  rescue ActiveRecord::StatementInvalid => e
    # DB の制約違反や SQL エラー（UNIQUE インデックス競合など）
    Rails.logger.error "[UserContextBuilderService] DBエラー: user_id=#{@user.id}, error=#{e.message}"
    { success: false, error: e.message }

  rescue => e
    # 上記以外の予期しないエラー
    Rails.logger.error "[UserContextBuilderService] 予期しないエラー: user_id=#{@user.id}, error=#{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    { success: false, error: e.message }
  end

  private

  # ============================================================
  # analyze_habit_patterns(since_date)
  # ============================================================
  # 【役割】
  #   過去8週間の習慣別達成率を集計して分類する。
  #
  # 【TODO: H-9 で N+1 を最適化する】
  #   現在 habits.map の中で毎回 HabitRecord.where を呼んでいるため、
  #   習慣が N 件あると N 回 SQL が発行される（N+1 問題）。
  #   H-9 で bullet gem を使って検知し、includes で最適化する。
  # ============================================================
  def analyze_habit_patterns(since_date)
    habits = @user.habits.active.includes(:habit_excluded_days)

    habit_stats = habits.map do |habit|
      rate = calculate_habit_achievement_rate(habit, since_date)
      { name: habit.name, rate: rate }
    end

    sorted = habit_stats.sort_by { |h| -h[:rate] }

    {
      strong: sorted.select { |h| h[:rate] >= HIGH_ACHIEVEMENT_THRESHOLD },
      weak:   sorted.select { |h| h[:rate] < LOW_ACHIEVEMENT_THRESHOLD },
      all:    sorted
    }
  end

  # ============================================================
  # calculate_habit_achievement_rate(habit, since_date)
  # ============================================================
  def calculate_habit_achievement_rate(habit, since_date)
    today = HabitRecord.today_for_record
    weeks = ((today - since_date).to_f / 7).ceil
    excluded_days_count = habit.habit_excluded_days.size
    available_days_per_week = 7 - excluded_days_count

    if habit.check_type?
      completed_count = HabitRecord.where(
        user:        @user,
        habit:       habit,
        record_date: since_date..today,
        completed:   true,
        deleted_at:  nil
      ).count

      expected_days = [weeks * available_days_per_week, 1].max
      ((completed_count.to_f / expected_days) * 100).clamp(0, 100).round
    else
      actual_sum = HabitRecord.where(
        user:        @user,
        habit:       habit,
        record_date: since_date..today,
        deleted_at:  nil
      ).sum(:numeric_value).to_f

      expected_total = [weeks * habit.weekly_target, 1].max
      ((actual_sum / expected_total) * 100).clamp(0, 100).round
    end
  end

  # ============================================================
  # analyze_reflection_trends(since_date)
  # ============================================================
  def analyze_reflection_trends(since_date)
    reflections = @user.weekly_reflections
      .where("week_start_date >= ?", since_date)
      .completed
      .order(week_start_date: :asc)

    completion_count = reflections.count
    completion_rate  = ((completion_count.to_f / ANALYSIS_WEEKS) * 100).clamp(0, 100).round

    moods    = reflections.where.not(mood: nil).pluck(:mood)
    avg_mood = moods.any? ? (moods.sum.to_f / moods.size).round(1) : nil

    all_text = reflections.map do |r|
      [r.direct_reason, r.background_situation, r.next_action, r.reflection_comment]
        .compact.join(" ")
    end.join(" ")

    found_negative = NEGATIVE_KEYWORDS.select { |kw| all_text.include?(kw) }
    found_positive = POSITIVE_KEYWORDS.select { |kw| all_text.include?(kw) }

    {
      completion_count:  completion_count,
      completion_rate:   completion_rate,
      avg_mood:          avg_mood,
      negative_keywords: found_negative,
      positive_keywords: found_positive
    }
  end

  # ============================================================
  # analyze_proposal_adoption
  # ============================================================
  def analyze_proposal_adoption
    ai_tasks  = @user.tasks.where(ai_generated: true, deleted_at: nil)
    total     = ai_tasks.count
    completed = ai_tasks.where(status: [:done, :archived]).count
    rate      = total > 0 ? ((completed.to_f / total) * 100).clamp(0, 100).round : 0

    {
      total_ai_tasks:     total,
      completed_ai_tasks: completed,
      adoption_rate:      rate
    }
  end

  # ============================================================
  # generate_context_summary
  # ============================================================
  def generate_context_summary(habit_patterns:, reflection_trends:, proposal_adoption:)
    if habit_patterns[:all].empty? && reflection_trends[:completion_count].zero?
      return ""
    end

    habit_section      = build_habit_section(habit_patterns)
    reflection_section = build_reflection_section(reflection_trends)
    adoption_section   = build_adoption_section(proposal_adoption)

    # セクションを固定化することでLLMの読み取り精度を向上させる
    <<~TEXT
      ## このユーザーの過去#{ANALYSIS_WEEKS}週間の傾向データ

      #{habit_section}

      #{reflection_section}

      #{adoption_section}

      ※ この傾向データを参考に、このユーザーに最適化された提案をしてください。
    TEXT
  end

  # ============================================================
  # build_habit_section / build_reflection_section / build_adoption_section
  # ============================================================

  def build_habit_section(habit_patterns)
    lines = ["### 習慣達成パターン（過去#{ANALYSIS_WEEKS}週間）"]

    if habit_patterns[:all].empty?
      lines << "- アクティブな習慣がまだありません。"
      return lines.join("\n")
    end

    if habit_patterns[:strong].any?
      strong_list = habit_patterns[:strong].map { |h| "#{h[:name]}（#{h[:rate]}%）" }.join("、")
      lines << "- 継続できている習慣: #{strong_list}"
    end

    if habit_patterns[:weak].any?
      weak_list = habit_patterns[:weak].map { |h| "#{h[:name]}（#{h[:rate]}%）" }.join("、")
      lines << "- 継続が難しい習慣: #{weak_list}"
    end

    all_rates = habit_patterns[:all].map { |h| h[:rate] }
    if all_rates.any?
      avg_rate = (all_rates.sum.to_f / all_rates.size).round
      lines << "- 全習慣の平均達成率: #{avg_rate}%"
    end

    lines.join("\n")
  end

  def build_reflection_section(reflection_trends)
    lines = ["### 振り返りの傾向（過去#{ANALYSIS_WEEKS}週間）"]
    lines << "- 振り返り完了率: #{reflection_trends[:completion_rate]}%（#{reflection_trends[:completion_count]}/#{ANALYSIS_WEEKS}週）"

    if reflection_trends[:avg_mood].present?
      lines << "- 平均気分スコア: #{reflection_trends[:avg_mood]}/5"
    end

    if reflection_trends[:negative_keywords].any?
      lines << "- 繰り返し出てくる課題キーワード: #{reflection_trends[:negative_keywords].join('、')}"
    end

    if reflection_trends[:positive_keywords].any?
      lines << "- ポジティブなキーワード: #{reflection_trends[:positive_keywords].join('、')}"
    end

    lines.join("\n")
  end

  def build_adoption_section(proposal_adoption)
    lines = ["### AI提案の採用状況"]

    if proposal_adoption[:total_ai_tasks].zero?
      lines << "- AI提案タスクはまだありません。"
      return lines.join("\n")
    end

    lines << "- AI提案タスクの実行率: #{proposal_adoption[:adoption_rate]}%（#{proposal_adoption[:completed_ai_tasks]}/#{proposal_adoption[:total_ai_tasks]}件完了）"

    rate = proposal_adoption[:adoption_rate]
    if rate >= 70
      lines << "- このユーザーはAIの提案をよく実行しています。具体的で実行可能な提案が効果的です。"
    elsif rate < 30
      lines << "- このユーザーはAIの提案をあまり実行できていません。より小さく達成しやすい提案が適切です。"
    end

    lines.join("\n")
  end
end