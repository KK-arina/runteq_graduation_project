# db/migrate/YYYYMMDDHHMMSS_add_is_latest_to_ai_analyses.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# ai_analyses テーブルに is_latest カラムを追加し、
# UNIQUE 制約の設計を「再実行・再分析に対応できる」形に改善する。
#
# 【既存 UNIQUE 制約の問題点】
# 前のマイグレーションで以下の UNIQUE 制約を追加した:
#   UNIQUE (weekly_reflection_id) WHERE weekly_reflection_id IS NOT NULL
#
# これだと「同じ振り返りで AI を再実行（精度改善・プロンプト変更）したい」
# というユースケースに対応できない。
# 再実行しようとすると UNIQUE 制約違反エラーが発生して詰まってしまう。
#
# 【解決策：is_latest フラグ方式】
# 「現在有効な分析結果か」を示す is_latest カラムを追加する。
#
# 運用ルール:
#   1. AI を再実行するとき → 新しいレコードを is_latest: true で作成する
#   2. 古いレコードを      → is_latest: false に更新する（履歴として保持）
#
# UNIQUE 制約を以下のように変更する:
#   UNIQUE (weekly_reflection_id, is_latest) WHERE is_latest = true
#   → 「最新分析は1つだけ」という制約を保ちつつ、過去分析の履歴も残せる
#
# 【なぜ履歴を残すのか？】
# ai_analyses テーブルには input_snapshot（分析時点のデータスナップショット）がある。
# 「どのプロンプトバージョンで、どんなデータを渡して、何という分析結果が出たか」
# という AI 改善の追跡ログとして非常に価値がある。
# 上書き削除してしまうとこの情報が失われる。
# ==============================================================================

class AddIsLatestToAiAnalyses < ActiveRecord::Migration[7.2]
  def change
    # ─────────────────────────────────────────────────────────────────────────
    # is_latest カラムを追加
    # ─────────────────────────────────────────────────────────────────────────
    # boolean 型: true = 最新の分析結果 / false = 過去の分析結果（履歴）
    # default: true → 新しく作成する分析結果はデフォルトで「最新」
    # null: false   → NULL は不可（必ず true か false のどちらかが必要）
    add_column :ai_analyses, :is_latest, :boolean, null: false, default: true

    # ─────────────────────────────────────────────────────────────────────────
    # 既存の UNIQUE 制約を削除する
    # ─────────────────────────────────────────────────────────────────────────
    # 前のマイグレーションで作成した UNIQUE 制約（再実行に対応できない設計）を削除する。
    # remove_index の name: オプションで削除するインデックスを名前で指定する。
    # （名前を指定しないと削除したいインデックスを特定できない場合がある）
    #
    # 注意: if_exists: true を指定することで、もし何らかの理由でインデックスが
    # 存在しない場合でもエラーにならないようにする（冪等性の確保）
    remove_index :ai_analyses,
                 name: 'index_ai_analyses_on_weekly_reflection_id_unique',
                 if_exists: true

    remove_index :ai_analyses,
                 name: 'index_ai_analyses_on_purpose_and_type_unique',
                 if_exists: true

    # ─────────────────────────────────────────────────────────────────────────
    # 新しい UNIQUE 制約を追加（is_latest = true の行のみを対象にする）
    # ─────────────────────────────────────────────────────────────────────────

    # UNIQUE 制約①: 同じ振り返りの「最新」分析は1件だけ
    # (weekly_reflection_id) の中で is_latest = true は1件のみ許可する
    # WHERE is_latest = true → is_latest = false の過去分析は制約対象外（複数 OK）
    #
    # 例:
    #   weekly_reflection_id=1, is_latest=true  → 1件のみ ← UNIQUE 制約で保護
    #   weekly_reflection_id=1, is_latest=false → 複数 OK（過去分析履歴）
    add_index :ai_analyses,
              :weekly_reflection_id,
              unique: true,
              where: 'weekly_reflection_id IS NOT NULL AND is_latest = true',
              name: 'index_ai_analyses_latest_weekly_reflection_unique'

    # UNIQUE 制約②: 同じ PMVV × 分析タイプの「最新」分析は1件だけ
    # (user_purpose_id, analysis_type) の中で is_latest = true は1件のみ
    add_index :ai_analyses,
              [ :user_purpose_id, :analysis_type ],
              unique: true,
              where: 'user_purpose_id IS NOT NULL AND is_latest = true',
              name: 'index_ai_analyses_latest_purpose_type_unique'

    # ─────────────────────────────────────────────────────────────────────────
    # is_latest へのインデックスを追加
    # ─────────────────────────────────────────────────────────────────────────
    # 「最新の分析結果だけを取得する」クエリ（WHERE is_latest = true）を高速化する
    # 部分インデックス（Partial Index）を使い、is_latest = true の行だけをインデックス対象にする
    # → false の行（履歴データ）はインデックスに含めないためサイズを最小化できる
    add_index :ai_analyses,
              :is_latest,
              where: 'is_latest = true',
              name: 'index_ai_analyses_on_is_latest_true'
  end
end
