# app/services/ai_proposal_confirm_service.rb
#
# ============================================================
# 【このファイルの役割】
# AI提案確定フローのビジネスロジックを集約するサービスクラス（骨格）。
#
# 【Issue #A-7 時点での実装状況】
# AI提案機能（ai_proposed_habits / ai_proposed_tasks テーブルへのデータ挿入）は
# Issue #D-3〜#D-4 で実装予定。
# 現時点では Task モデル・AiAnalysis モデルが未実装のため、
# このサービスはトランザクション境界の「設計図」として骨格のみ作成する。
#
# 【このサービスが担当する予定のフロー（Issue #D-3〜#D-4 で実装）】
# 1. ai_proposed_habits の is_accepted を true に更新する
# 2. ai_proposed_tasks の is_accepted を true に更新する
# 3. 実際の Habit レコードを作成する（ai_generated: true）
# 4. 実際の Task レコードを作成する（ai_generated: true）
# 5. ロックを解除する（WeeklyReflection#complete! を呼ぶ）
# すべてを1つのトランザクションで実行する。
# ============================================================

class AiProposalConfirmService
  # ==========================================================
  # initialize（コンストラクタ）
  # ==========================================================
  # 【引数】（Issue #D-3〜#D-4 で確定予定）
  #   ai_analysis  - 確定するAI分析レコード（AiAnalysis）
  #   user         - 操作を行うユーザー（current_user）
  #   reflection   - 紐づく週次振り返り（ロック解除に使用）
  def initialize(ai_analysis:, user:, reflection:)
    @ai_analysis = ai_analysis
    @user        = user
    @reflection  = reflection
  end

  # ==========================================================
  # call（メインの実行メソッド）
  # ==========================================================
  # 【現在の動作】
  # Issue #D-3〜#D-4 で実装されるまで、この call メソッドは
  # トランザクションの「設計図」としてコメントのみ記載する。
  # 実装時はコメントを削除して各ステップのコードを書く。
  def call
    ApplicationRecord.with_transaction do
      # ── Step 1: ai_proposed_habits の is_accepted 更新 ──────────
      # 【Issue #D-3 で実装予定】
      # @ai_analysis.proposed_habits.each do |proposed|
      #   proposed.update!(is_accepted: true)
      # end

      # ── Step 2: ai_proposed_tasks の is_accepted 更新 ───────────
      # 【Issue #D-3 で実装予定】
      # @ai_analysis.proposed_tasks.each do |proposed|
      #   proposed.update!(is_accepted: true)
      # end

      # ── Step 3: 実際の Habit を作成する ─────────────────────────
      # 【Issue #D-3 で実装予定】
      # @ai_analysis.proposed_habits.accepted.each do |proposed|
      #   @user.habits.create!(
      #     name:         proposed.name,
      #     weekly_target: proposed.weekly_target,
      #     ai_generated: true
      #   )
      # end

      # ── Step 4: 実際の Task を作成する ──────────────────────────
      # 【Issue #D-4 で実装予定】
      # @ai_analysis.proposed_tasks.accepted.each do |proposed|
      #   @user.tasks.create!(
      #     title:        proposed.title,
      #     priority:     proposed.priority,
      #     ai_generated: true
      #   )
      # end

      # ── Step 5: ロックを解除する ─────────────────────────────────
      # 【常に必要な処理 - 実装済み complete! を呼ぶだけ】
      # @reflection.complete!

      # 現在は未実装のため NotImplementedError を raise して
      # 誤って呼ばれた場合に気づけるようにする
      raise NotImplementedError, "AiProposalConfirmService は Issue #D-3〜#D-4 で実装予定です"
    end
  end
end