# app/services/habit_record_save_service.rb
#
# ============================================================
# 【このファイルの役割】
# 習慣記録の保存フローのビジネスロジックを集約するサービスクラス。
#
# 【Issue #A-7 最終修正版】
# rescue をサービスクラス側に移動。
# ============================================================

class HabitRecordSaveService
  def initialize(user:, habit:, completed:, date: HabitRecord.today_for_record)
    @user      = user
    @habit     = habit
    @completed = completed
    @date      = date
  end

  def call
    @habit_record = nil

    ApplicationRecord.with_transaction do
      # Step 1: 今日の HabitRecord を find_or_create する
      @habit_record = HabitRecord.find_or_create_for(@user, @habit, @date)

      # Step 2: completed を更新する
      # update_completed! → 失敗すると ActiveRecord::RecordInvalid を raise する
      @habit_record.update_completed!(@completed)

      # Step 3: ストリーク更新（Issue #B-3 で実装予定）
      # StreakCalculator.new(@habit, @user).update_streak!
    end

    # 正常完了時のみここに到達する
    { success: true, error: nil, habit_record: @habit_record }

  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[HabitRecordSaveService] RecordInvalid: #{e.message}"
    { success: false, error: e.record&.errors&.full_messages&.join(", ") || e.message, habit_record: nil }

  rescue StandardError => e
    Rails.logger.error "[HabitRecordSaveService] StandardError: #{e.message}"
    Rails.logger.error e.backtrace&.first(10)&.join("\n")
    { success: false, error: "予期しないエラーが発生しました。", habit_record: nil }
  end
end