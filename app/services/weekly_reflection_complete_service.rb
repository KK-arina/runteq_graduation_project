# app/services/weekly_reflection_complete_service.rb
#
# ============================================================
# 【テスト失敗修正】
#
#   ❶ find_or_create_by! で numeric_value: 0 を初期値として渡す
#
#      【問題の原因】
#      find_or_create_by! で新規作成するとき、
#      numeric_value が nil のまま create が走る。
#      HabitRecord モデルの数値型バリデーション:
#        validates :numeric_value,
#                  numericality: { greater_than_or_equal_to: 0 },
#                  if: -> { habit.present? && habit.numeric_type? }
#      → nil は numericality バリデーションを通るが、
#        さらに numeric_value_required_for_numeric_type カスタムバリデーションで
#        「数値型では nil 不可」としてはじかれる。
#
#      【修正方法】
#      find_or_create_by! の create_with を使って
#      新規作成時だけ numeric_value: 0.0 を初期値にセットする。
#      既存レコードが見つかった場合は create_with の値は無視される。
#
#      【completed: false も初期値にする理由】
#      numeric_value: 0 のとき completed は false が正しい状態。
#      バリデーション `validates :completed, inclusion: { in: [true, false] }` も
#      nil を弾くため明示的に false を渡す。
# ============================================================

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

      # ── C-4 追加 ──────────────────────────────────────────────────────────
      # WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
      #
      # 【追加する理由】
      #   習慣スナップショット（WeeklyReflectionHabitSummary）と同じタイミングで
      #   タスクスナップショットも保存する。
      #
      # 【トランザクション内に含める理由】
      #   ApplicationRecord.with_transaction ブロック内に書くことで、
      #   習慣スナップショット保存とタスクスナップショット保存が
      #   「全部成功 or 全部ロールバック」となる。
      #   どちらか一方だけ保存されるという中途半端な状態を防ぐ。
      #
      # 【呼び出し順序について】
      #   WeeklyReflectionHabitSummary の直後に呼ぶことで、
      #   習慣・タスクの両スナップショットが同じトランザクションで完結する。
      WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)
      # ──────────────────────────────────────────────────────────────────────

      @reflection.complete!
      complete_last_week_reflection! if @was_locked
    end

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

      # current_sum: is_manual_input ではない（日々の実記録）のみを集計する
      # → 補正レコード自体を current_sum に含めないことで再補正が安定する
      current_sum = HabitRecord
        .where(user: @user, habit: habit, record_date: week_range, deleted_at: nil)
        .where(is_manual_input: [false, nil])
        .sum(:numeric_value)
        .to_f

      diff = (target_sum - current_sum).round(2)
      next if diff.zero?

      # ── 修正: find_or_create_by! に create_with で初期値を渡す ──────────────
      #
      # 【create_with とは】
      #   find_or_create_by! は「検索条件に合うレコードを探し、なければ作成する」。
      #   create_with で指定した値は「新規作成時だけ」セットされる。
      #   既存レコードが見つかった場合は create_with の値は使われない。
      #
      # 【numeric_value: 0.0 を初期値にする理由】
      #   数値型習慣では numeric_value が nil のまま保存できない
      #   （numeric_value_required_for_numeric_type バリデーションで弾かれる）。
      #   新規作成時に 0.0 を入れておき、直後の update! で正しい値に上書きする。
      #
      # 【completed: false を初期値にする理由】
      #   completed は nil 不可のため、新規作成時に false を明示的に渡す。
      end_record = HabitRecord
        .create_with(numeric_value: 0.0, completed: false)
        .find_or_create_by!(
          user:        @user,
          habit:       habit,
          record_date: @reflection.week_end_date
        )
      # ────────────────────────────────────────────────────────────────────────

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
