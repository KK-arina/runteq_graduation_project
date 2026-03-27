# app/services/habit_record_save_service.rb
#
# ==============================================================================
# HabitRecordSaveService（B-1: レビュー修正版）
# ==============================================================================
# 【レビュー指摘による修正内容】
#
#   ① nil と 0 の区別を明確化（最重要修正）
#      修正前: @numeric_value.to_f → nil が 0.0 に変換されて「未入力と0入力」の区別が消えた
#      修正後: nil は nil のまま扱い、意味を保持する
#
#   ② completed の判定ロジックを nil/0/正数の3パターンで明示
#      nil → 未入力 → false
#      0   → 実績なし → false
#      >0  → 実績あり → true
#
# 【nil と 0 の違いが重要な理由】
#   nil = 「その日は記録しなかった」（未入力）
#   0.0 = 「その日は記録したが実績ゼロ」（意図的な0入力）
#   この区別があると将来の分析で「入力忘れ日」と「実績なし日」を分けられる。
# ==============================================================================

class HabitRecordSaveService
  # initialize
  # 【引数】
  #   user:          ログインユーザー
  #   habit:         対象の習慣（measurement_type を確認するため必要）
  #   completed:     Boolean（チェック型で使用）
  #   numeric_value: Float/nil（数値型で使用。nil = 未入力）
  def initialize(user:, habit:, completed: false, numeric_value: nil)
    @user          = user
    @habit         = habit
    @completed     = completed
    @numeric_value = numeric_value
  end

  # call
  # 【戻り値】
  #   成功: { success: true,  habit_record: HabitRecord, errors: [] }
  #   失敗: { success: false, habit_record: nil,         errors: [エラー文字列] }
  #
  # 【errors を配列で返す理由（レビュー提案による改善）】
  #   フロント側でエラーを一覧表示しやすくするため。
  #   単一の error 文字列より、配列の方が将来の拡張（複数エラー表示）に対応しやすい。
  def call
    ApplicationRecord.with_transaction do
      habit_record = HabitRecord.find_or_create_for(@user, @habit)

      if @habit.check_type?
        # チェック型: completed のみ更新
        habit_record.update_completed!(@completed)
      else
        # 数値型: numeric_value を更新し、completed を自動計算する
        #
        # 【修正前の問題】
        #   value = @numeric_value.to_f
        #   → nil.to_f が 0.0 になり、「未入力」と「0入力」の区別が消えていた
        #
        # 【修正後】
        #   nil は nil のまま保持する。
        #   nil かどうかの判定を明示的に行い、意味のある区別を維持する。
        value = @numeric_value.nil? ? nil : @numeric_value.to_f

        # completed の自動計算（3パターンを明示）
        # nil  → 未入力     → false（記録していない）
        # 0.0  → 実績ゼロ   → false（やったが実績なし）
        # >0   → 実績あり   → true（何かを記録した）
        completed =
          if value.nil?
            false       # nil（未入力）は未完了扱い
          else
            value > 0   # 0より大きければ完了、0なら未完了
          end

        habit_record.update!(
          numeric_value: value,
          completed:     completed
        )
      end

      { success: true, habit_record: habit_record, errors: [] }
    end

  rescue ActiveRecord::RecordInvalid => e
    # バリデーションエラー（例: numeric_value が負の数、数値型で nil）
    # e.record.errors.full_messages で日本語エラーメッセージの配列を取得する
    errors = e.record&.errors&.full_messages || [ e.message ]
    { success: false, habit_record: nil, errors: errors }

  rescue ActiveRecord::RecordNotFound
    { success: false, habit_record: nil, errors: [ "習慣が見つかりませんでした" ] }

  rescue StandardError => e
    Rails.logger.error "HabitRecordSaveService error: #{e.message}"
    Rails.logger.error e.backtrace&.first(5)&.join("\n")
    { success: false, habit_record: nil, errors: [ "保存中にエラーが発生しました" ] }
  end
end
