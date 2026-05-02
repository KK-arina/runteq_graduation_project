# app/services/weekly_reflection_complete_service.rb
#
# ==============================================================================
# WeeklyReflectionCompleteService（振り返り完了サービス）
# ==============================================================================
# 【D-5 での変更内容】
#   ① call メソッド内で crisis_word_detected? を確認する
#   ② 危機検出時: AI分析ジョブをスキップし、crisis_detected=true で
#      AiAnalysis レコードを作成する（ロック解除は通常通り実行する）
#   ③ enqueue_analysis_job_if_eligible に crisis チェックを追加する
#
# 【D-5 設計の重要ポイント】
#   - 振り返りの「保存」自体は crisis でも通常通り実行する
#   - ロック解除も通常通り実行する（ユーザーを詰まらせない）
#   - AI 分析ジョブだけスキップして crisis_detected=true を記録する
#   - 危機介入モーダルの表示は controller 側で行う（service は記録のみ）
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

    # ── D-5 変更: crisis 検出時とそれ以外で分岐する ──────────────────────
    #
    # 【なぜトランザクションの外で判定するか】
    #   save! が成功した後の @reflection には before_validation で
    #   セットされた crisis_word_detected フラグが残っている。
    #   トランザクション外での処理（ジョブエンキュー）の分岐に使う。
    if @reflection.crisis_word_detected?
      # 危機ワードが検出された場合:
      #   AI 分析ジョブをスキップして crisis_detected=true を記録する
      record_crisis_analysis!

      # コントローラーが crisis を判断できるよう success の中に
      # crisis_detected: true を含めて返す
      { success: true, error: nil, crisis_detected: true }
    else
      # 通常の場合: AI 分析ジョブをエンキューする
      enqueue_analysis_job_if_eligible
      { success: true, error: nil, crisis_detected: false }
    end
    # ────────────────────────────────────────────────────────────────────────

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[WeeklyReflectionCompleteService] RecordInvalid: #{e.message}"
    { success: false, error: e.record&.errors&.full_messages&.join(", ") || e.message, crisis_detected: false }

  rescue ActiveRecord::RecordNotUnique => e
    Rails.logger.error "[WeeklyReflectionCompleteService] RecordNotUnique: #{e.message}"
    { success: false, error: "データが重複しています。時間をおいて再試行してください。", crisis_detected: false }

  rescue StandardError => e
    Rails.logger.error "[WeeklyReflectionCompleteService] StandardError: #{e.message}"
    Rails.logger.error e.backtrace&.first(10)&.join("\n")
    { success: false, error: "予期しないエラーが発生しました。時間をおいて再試行してください。", crisis_detected: false }
  end

  private

  # ── D-5 追加: record_crisis_analysis! ────────────────────────────────────
  #
  # 【役割】
  #   危機ワードが検出された場合に呼ばれる。
  #   AI 分析ジョブはスキップし、crisis_detected=true の AiAnalysis を作成する。
  #
  # 【なぜ AiAnalysis を作成するか】
  #   crisis_detected フラグを DB に残すことで、運営者が
  #   「サポートが必要なユーザー」を把握できる。
  #   将来的には crisis_detected=true のユーザーに
  #   フォローアップ通知を送る機能にも使える。
  #
  # 【create! ではなく create を使う理由】
  #   crisis の記録に失敗しても振り返り保存は成功扱いにしたい。
  #   create! は例外を発生させるため、ここでは create でログだけ残す。
  def record_crisis_analysis!
    Rails.logger.warn "[WeeklyReflectionCompleteService] 危機ワードを検出しました: weekly_reflection_id=#{@reflection.id}, user_id=#{@user.id}"

    result = AiAnalysis.create(
      weekly_reflection_id: @reflection.id,
      analysis_type:        :weekly_reflection,
      # crisis_detected: true → このレコードが危機介入のトリガーだったことを示す
      crisis_detected:      true,
      # is_latest: true → 最新の分析結果として記録する
      is_latest:            true,
      # input_snapshot: この時点の振り返りデータを保存する（追跡用）
      input_snapshot: {
        weekly_reflection_id: @reflection.id,
        week_start_date:      @reflection.week_start_date.to_s,
        week_end_date:        @reflection.week_end_date.to_s,
        crisis_detected_at:   Time.current.iso8601,
        # 実際の入力内容は記録しない（プライバシー保護）
        note: "危機ワード検出によりAI分析をスキップしました"
      },
      # analysis_comment: 危機介入による記録であることを示す
      analysis_comment: "危機ワードが検出されたため、AI分析をスキップしました。",
      prompt_version:   "crisis_skip"
    )

    unless result.persisted?
      Rails.logger.error "[WeeklyReflectionCompleteService] crisis AiAnalysis の保存に失敗: #{result.errors.full_messages.join(', ')}"
    end
  end
  # ────────────────────────────────────────────────────────────────────────────

  # enqueue_analysis_job_if_eligible（D-4 実装済み・変更なし）
  def enqueue_analysis_job_if_eligible
    user_setting = @user.user_setting

    unless user_setting
      Rails.logger.warn "[WeeklyReflectionCompleteService] user_setting が存在しないため AI 分析をスキップ: user_id=#{@user.id}"
      return
    end

    if user_setting.ai_analysis_count >= user_setting.ai_analysis_monthly_limit
      Rails.logger.info "[WeeklyReflectionCompleteService] AI分析の月次上限のためスキップ: user_id=#{@user.id}"
      return
    end

    WeeklyReflectionAnalysisJob.perform_later(@reflection.id)
    Rails.logger.info "[WeeklyReflectionCompleteService] WeeklyReflectionAnalysisJob をエンキューしました: weekly_reflection_id=#{@reflection.id}"
  end

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