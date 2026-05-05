# db/migrate/YYYYMMDDXXXXXX_add_last_ai_requested_at_to_user_settings.rb
#
# ==============================================================================
# マイグレーション: user_settings に last_ai_requested_at カラムを追加する
# ==============================================================================
#
# 【このマイグレーションの目的】
#   D-10「AI API レート制限（連打防止）」を実現するために、
#   ユーザーが最後に AI 分析リクエストを送った日時を DB に記録する。
#
# 【なぜ Redis を使わないのか】
#   このプロジェクトは Render 無料プランで稼働しており、
#   Redis（有料アドオン）を使わずに Solid Cache + PostgreSQL で管理する設計方針。
#   last_ai_requested_at カラムを user_settings に追加することで
#   追加インフラなしにレート制限が実現できる。
#
# 【null: true の理由】
#   既存のユーザーはこのカラムが NULL になる。
#   NULL = 「一度もリクエストしたことがない」を意味し、
#   制限なしとして扱う（安全側に倒す設計）。
#
# 【インデックスを追加しない理由】
#   このカラムは WHERE 検索に使わず、
#   「特定ユーザーのレコードを取得した後に値を比較する」だけなので
#   インデックスは不要（user_id のインデックスは既存で存在する）。
# ==============================================================================

class AddLastAiRequestedAtToUserSettings < ActiveRecord::Migration[7.2]
  def change
    # last_ai_requested_at: 最後に AI 分析リクエストを受け付けた日時
    # null: true     → 既存ユーザーは NULL（一度もリクエストなし）を許可する
    # comment: カラムの用途を DB レベルでも記録しておく（PostgreSQL 対応）
    add_column :user_settings, :last_ai_requested_at, :datetime, null: true, comment: "最後にAI分析リクエストを受け付けた日時。D-10レート制限で使用。"
  end
end