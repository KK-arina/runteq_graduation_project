# db/migrate/YYYYMMDDHHMMSS_add_foreign_key_to_ai_analyses_for_user_purpose.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# ai_analyses テーブルの user_purpose_id カラムに外部キー制約を追加する。
#
# 【なぜ別マイグレーションで追加するのか？】
# CreateAiAnalyses マイグレーションの実行時点では
# user_purposes テーブルがまだ存在していない。
# PostgreSQL では「存在しないテーブルへの外部キー」は作成できないため、
# user_purposes テーブル作成後に別マイグレーションで追加する必要がある。
#
# 【外部キー制約がないとどうなるか？】
# 外部キー制約なし → アプリのバグや手動操作で「存在しない user_purpose_id」が
# ai_analyses に保存される可能性がある。
# その後 JOIN や関連データ取得で予期せぬ nil が返り、本番事故につながる。
#
# 【on_delete: :cascade の意味】
# 親レコード（user_purposes）が削除されたとき、
# 紐づいている ai_analyses レコードも自動的に削除する。
# 「PMVV を削除したら、その分析結果も一緒に消える」という自然な挙動を保証する。
# ==============================================================================

class AddForeignKeyToAiAnalysesForUserPurpose < ActiveRecord::Migration[7.2]
  def change
    # ─────────────────────────────────────────────────────────────────────────
    # user_purpose_id へのインデックスを追加
    # ─────────────────────────────────────────────────────────────────────────
    # 外部キー制約を追加する前に、インデックスが存在しないと
    # PostgreSQL が警告を出す場合がある。
    # また「この PMVV の AI 分析結果を取得する」クエリを高速化するためにも必要。
    # if_not_exists: true → 既にインデックスが存在する場合はスキップ（冪等性の確保）
    add_index :ai_analyses,
              :user_purpose_id,
              name: 'index_ai_analyses_on_user_purpose_id_fk',
              if_not_exists: true

    # ─────────────────────────────────────────────────────────────────────────
    # 外部キー制約を追加
    # ─────────────────────────────────────────────────────────────────────────
    # add_foreign_key の引数:
    #   第1引数: 外部キーを持つテーブル（ai_analyses）
    #   第2引数: 参照先のテーブル（user_purposes）
    #   column:  外部キーのカラム名（デフォルトは user_purpose_id なので省略可だが明示する）
    #   on_delete: :cascade → 参照先（user_purposes）が削除されたら、
    #                          このレコード（ai_analyses）も一緒に削除する
    add_foreign_key :ai_analyses,
                    :user_purposes,
                    column: :user_purpose_id,
                    on_delete: :cascade
  end
end