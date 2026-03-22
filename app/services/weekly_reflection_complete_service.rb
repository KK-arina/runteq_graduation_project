# app/services/weekly_reflection_complete_service.rb
#
# ============================================================
# 【このファイルの役割】
# 週次振り返り完了フローのビジネスロジックを集約するサービスクラス。
#
# 【Issue #A-7 最終修正版】
# ApplicationRecord.with_transaction から rescue が削除されたため、
# このサービスクラス側で rescue を書く。
# ============================================================

class WeeklyReflectionCompleteService
  def initialize(reflection:, user:, was_locked:)
    # @reflection: 保存・完了処理の対象となる WeeklyReflection オブジェクト
    @reflection = reflection
    # @user: 振り返りを行っているログインユーザー
    @user       = user
    # @was_locked: 振り返り保存「前」のロック状態（true/false）
    @was_locked = was_locked
  end

  def call
    # ApplicationRecord.with_transaction
    # → 例外が発生すると Rails が自動ロールバックし、例外を外に伝播させる。
    # → rescue はこのメソッドの外側で書く（with_transaction の外側 = 正しい位置）。
    ApplicationRecord.with_transaction do
      # Step 1: 振り返りを保存する
      # save! → 失敗すると ActiveRecord::RecordInvalid を raise する
      # → with_transaction のロールバックがトリガーされる
      @reflection.save!

      # Step 2: 習慣スナップショットを一括作成する
      # create_all_for_reflection! の内部にも transaction があるが、
      # これは外側の with_transaction の transaction ブロックに「合流」する。
      # with_transaction のネストではないため問題ない。
      WeeklyReflectionHabitSummary.create_all_for_reflection!(@reflection)

      # Step 3: 振り返りを完了状態にする
      @reflection.complete!

      # Step 4: ロック中だった場合の後処理
      complete_last_week_reflection! if @was_locked
    end

    # with_transaction が正常完了した場合のみここに到達する
    { success: true, error: nil }

  rescue ActiveRecord::RecordInvalid => e
    # save! / update! のバリデーションエラー。
    # この時点では with_transaction（transaction ブロック）はロールバック済み。
    Rails.logger.error "[WeeklyReflectionCompleteService] RecordInvalid: #{e.message}"
    { success: false, error: e.record&.errors&.full_messages&.join(", ") || e.message }

  rescue ActiveRecord::RecordNotUnique => e
    # DB の UNIQUE 制約違反（振り返りの二重作成など）。ロールバック済み。
    Rails.logger.error "[WeeklyReflectionCompleteService] RecordNotUnique: #{e.message}"
    { success: false, error: "データが重複しています。時間をおいて再試行してください。" }

  rescue StandardError => e
    # 予期しないエラー全般。ロールバック済み。
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
end