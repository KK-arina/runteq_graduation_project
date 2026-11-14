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
#
# 【AI分析状態の修正での変更内容】
#   ① skip_ai: 引数を追加した。
#      「AIなしで振り返りを完了する」（complete_without_ai）から true で呼ばれる。
#      true のときは AI分析ジョブを登録せず、ai_skipped_at に日時を記録する。
#      これまでは上限チェックに任せていたため、上限を下回っていると
#      「AIなし」を選んでも AI分析が動いてしまう可能性があった。
#   ② 月の上限・user_setting 無しでジョブを登録しなかったときも
#      ai_skipped_at を記録する（「分析中」が出続けないようにする）。
# ==============================================================================

class WeeklyReflectionCompleteService
  # skip_ai: true のとき、AI分析ジョブを登録しない（AIなしで完了）
  # 省略時は false なので、既存の呼び出し（create アクション）の動きは変わらない。
  def initialize(reflection:, user:, was_locked:, corrections: nil, skip_ai: false)
    @reflection  = reflection
    @user        = user
    @was_locked  = was_locked
    @corrections = corrections&.to_h || {}
    @skip_ai     = skip_ai
  end

  def call
    ApplicationRecord.with_transaction do
      # ── AI分析状態の修正で追加 ─────────────────────────────────────────
      # AIなしで完了する場合は、保存と同時に「AI分析をしなかった日時」を記録する。
      # save! の前にセットするので、追加の UPDATE は発生しない。
      @reflection.ai_skipped_at = Time.current if @skip_ai
      # ──────────────────────────────────────────────────────────────────────
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
      # ── AI分析状態の修正で変更 ───────────────────────────────────────
      # AIなしで完了する場合は、ジョブを登録しない。
      # それ以外は、これまでどおり条件を満たせばジョブを登録する。
      if @skip_ai
        Rails.logger.info "[WeeklyReflectionCompleteService] AIなしで完了したため AI 分析ジョブを登録しません: weekly_reflection_id=#{@reflection.id}"
      else
        enqueue_analysis_job_if_eligible
      end
      # ──────────────────────────────────────────────────────────────────
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

  # enqueue_analysis_job_if_eligible（D-4 実装済み）
  # 【AI分析状態の修正での変更】
  #   ジョブを登録しなかった2つのケースで mark_ai_skipped! を呼ぶようにした。
  def enqueue_analysis_job_if_eligible
    user_setting = @user.user_setting

    unless user_setting
      Rails.logger.warn "[WeeklyReflectionCompleteService] user_setting が存在しないため AI 分析をスキップ: user_id=#{@user.id}"
      mark_ai_skipped!
      return
    end

    if user_setting.ai_analysis_count >= user_setting.ai_analysis_monthly_limit
      Rails.logger.info "[WeeklyReflectionCompleteService] AI分析の月次上限のためスキップ: user_id=#{@user.id}"
      mark_ai_skipped!
      return
    end

    WeeklyReflectionAnalysisJob.perform_later(@reflection.id)
    Rails.logger.info "[WeeklyReflectionCompleteService] WeeklyReflectionAnalysisJob をエンキューしました: weekly_reflection_id=#{@reflection.id}"

    # ── H-8 追加: 振り返り完了後にパーソナライズAIプロファイルを非同期更新する ──
    #
    # 【なぜ WeeklyReflectionAnalysisJob の後に呼ぶのか】
    #   プロファイルの更新は「今回の振り返りデータを含めた状態」で行いたい。
    #   振り返りデータは save! 後には既に DB に保存されているため、
    #   この時点で呼んでも最新データを参照できる。
    #
    # 【なぜ AI分析上限チェックの外側に置くのか】
    #   プロファイル更新は AI API を呼ばない（UserContextBuilderService は
    #   DB集計のみ）。月次上限とは無関係に常に実行して良い。
    #
    # 【perform_later を使う理由】
    #   プロファイル更新はユーザーの体験に直接影響しない。
    #   非同期で実行することでレスポンスタイムを短縮する。
    UpdateAiProfileJob.perform_later(@user.id)
    Rails.logger.info "[WeeklyReflectionCompleteService] UpdateAiProfileJob をエンキューしました: user_id=#{@user.id}"
    # ──────────────────────────────────────────────────────────────────────────
  end

  # ── AI分析状態の修正で追加: mark_ai_skipped! ──────────────────────────────
  #
  # 【役割】
  #   AI分析ジョブを登録しなかったことを ai_skipped_at に記録する。
  #   記録しないと、結果が来ないのに「AI分析中です…」が表示されてしまう。
  #
  # 【update_column を使う理由】
  #   振り返りはトランザクション内で保存済み。ここでは1列だけを書き換えればよく、
  #   バリデーションやコールバック（キャッシュ削除）をもう一度走らせる必要がない。
  #   書き込みは振り返り完了時の1回だけなので、Neon の負荷はほぼ増えない。
  def mark_ai_skipped!
    @reflection.update_column(:ai_skipped_at, Time.current)
  end
  # ────────────────────────────────────────────────────────────────────────────

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