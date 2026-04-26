# app/services/weekly_reflection_complete_service.rb
#
# ==============================================================================
# WeeklyReflectionCompleteService（振り返り完了サービス）
# ==============================================================================
# 【D-4 での変更内容】
#   振り返り完了後に WeeklyReflectionAnalysisJob をエンキューする処理を追加。
#
# 【なぜトランザクションの外でエンキューするか】
#   A-7 の設計原則「トランザクション内は DB アクセスのみ。
#   外部 API・GoodJob エンキューは外に出す」に従う。
#   トランザクション内でエンキューすると、ジョブが実行されたときに
#   DB のコミットが完了していない可能性がある（競合状態の防止）。
# ==============================================================================

class WeeklyReflectionCompleteService
  def initialize(reflection:, user:, was_locked:, corrections: nil)
    @reflection  = reflection
    @user        = user
    @was_locked  = was_locked
    @corrections = corrections&.to_h || {}
  end

  def call
    ApplicationRecord.with_transaction do
      @reflection.save!
      apply_numeric_corrections! unless @corrections.blank?
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)
      WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
      @reflection.complete!
      complete_last_week_reflection! if @was_locked
    end

    # ── D-4 追加 ──────────────────────────────────────────────────────────────
    # enqueue_analysis_job_if_eligible
    #
    # 【なぜトランザクションの外に置くか】
    #   A-7 で定めた設計原則「トランザクション内は DB アクセスのみ。
    #   外部 API・GoodJob エンキューは外に出す」に従う。
    #   トランザクション内でエンキューすると、ジョブが実行されたときに
    #   DB のコミットが完了していない可能性がある。
    #
    # 【perform_later を使う理由】
    #   perform_later → GoodJob キューに積んで非同期実行（Puma の別スレッドで動く）
    #   perform_now   → 同期実行（テスト用・デバッグ用）
    #   本番では perform_later を使うことでリクエストをブロックしない。
    enqueue_analysis_job_if_eligible
    # ──────────────────────────────────────────────────────────────────────────

    { success: true, error: nil }

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[WeeklyReflectionCompleteService] RecordInvalid: #{e.message}"
    { success: false, error: e.record&.errors&.full_messages&.join(", ") || e.message }

  rescue ActiveRecord::RecordNotUnique => e
    Rails.logger.error "[WeeklyReflectionCompleteService] RecordNotUnique: #{e.message}"
    { success: false, error: "データが重複しています。時間をおいて再試行してください。" }

  rescue StandardError => e
    Rails.logger.error "[WeeklyReflectionCompleteService] StandardError: #{e.message}"
    Rails.logger.error e.backtrace&.first(10)&.join("\n")
    { success: false, error: "予期しないエラーが発生しました。時間をおいて再試行してください。" }
  end

  private

  # ── D-4 追加 ──────────────────────────────────────────────────────────────
  # enqueue_analysis_job_if_eligible
  # 【役割】
  #   月次 AI 利用回数の上限を事前チェックしてからジョブをエンキューする。
  #
  # 【なぜここでも上限チェックするか】
  #   ジョブ側（WeeklyReflectionAnalysisJob#perform）でも上限チェックを行うが、
  #   エンキュー前に確認することで不要なジョブを DB に積まない最適化になる。
  #   二重チェックは冗長に見えるが、安全性のための多層防御として有効。
  def enqueue_analysis_job_if_eligible
    user_setting = @user.user_setting

    # user_setting が存在しない場合はスキップ（ログだけ残す）
    unless user_setting
      Rails.logger.warn "[WeeklyReflectionCompleteService] user_setting が存在しないため AI 分析をスキップ: user_id=#{@user.id}"
      return
    end

    # 月次上限チェック
    if user_setting.ai_analysis_count >= user_setting.ai_analysis_monthly_limit
      Rails.logger.info "[WeeklyReflectionCompleteService] AI分析の月次上限のためスキップ: user_id=#{@user.id}"
      return
    end

    # ジョブをキューに積む
    # @reflection.id を渡す理由:
    #   GoodJob はジョブ引数を JSON で DB に保存するため、
    #   ActiveRecord インスタンスは渡せない。ID（整数）を渡す。
    WeeklyReflectionAnalysisJob.perform_later(@reflection.id)
    Rails.logger.info "[WeeklyReflectionCompleteService] WeeklyReflectionAnalysisJob をエンキューしました: weekly_reflection_id=#{@reflection.id}"
  end
  # ──────────────────────────────────────────────────────────────────────────

  def complete_last_week_reflection!
    last_week_start = WeeklyReflection.current_week_start_date - 7.days
    last_week = @user.weekly_reflections.find_by(week_start_date: last_week_start)
    last_week&.complete!
  end

  def apply_numeric_corrections!
    week_range = @reflection.week_start_date..@reflection.week_end_date

    @corrections.each do |key, value|
      unless key.to_s.match?(/\Ahabit_\d+\z/)
        Rails.logger.warn "[WeeklyReflectionCompleteService] 不正なキー形式をスキップ: #{key.inspect}"
        next
      end

      habit_id   = key.to_s.delete_prefix("habit_").to_i
      target_sum = parse_correction_value(value)
      next if target_sum.nil?

      habit = @user.habits.find_by(id: habit_id)
      next if habit.nil?
      next unless habit.numeric_type?

      current_sum = HabitRecord
        .where(user: @user, habit: habit, record_date: week_range, deleted_at: nil)
        .where(is_manual_input: [false, nil])
        .sum(:numeric_value)
        .to_f

      diff = (target_sum - current_sum).round(2)
      next if diff.zero?

      end_record = HabitRecord
        .create_with(numeric_value: 0.0, completed: false)
        .find_or_create_by!(
          user:        @user,
          habit:       habit,
          record_date: @reflection.week_end_date
        )

      new_value = (end_record.numeric_value.to_f + diff).round(2)
      new_value = 0.0 if new_value < 0

      end_record.update!(
        numeric_value:   new_value,
        completed:       new_value > 0,
        is_manual_input: true
      )
    end
  end

  def parse_correction_value(value)
    raw = value.presence
    return nil if raw.nil?

    Float(raw)
  rescue ArgumentError, TypeError
    Rails.logger.warn "[WeeklyReflectionCompleteService] 無効な補正値をスキップ: #{value.inspect}"
    nil
  end
end