# ============================================================
# 習慣（habits）テーブルを作成するマイグレーション
# ============================================================
class CreateHabits < ActiveRecord::Migration[7.2]
  def change
    create_table :habits do |t|
      # ユーザーへの外部キー（NOT NULL制約付き）
      # 習慣は必ずユーザーに紐づく必要があるため
      # t.references で user_id に対するインデックスが自動作成されるため
      # 別途 add_index :habits, :user_id は不要（二重作成を防ぐ）
      t.references :user, null: false, foreign_key: true

      # 習慣名（50文字以内、NOT NULL）
      # バリデーションはモデル側でも行うが、DB側でも制約を設ける
      t.string :name, null: false, limit: 50

      # 週次目標値（NOT NULL、デフォルト7）
      # チェック型の場合、週7日で何回実施するかを指定
      # 例: 週7回実施 → weekly_target = 7
      # 1〜7の範囲を想定（バリデーションはモデル側で実施）
      t.integer :weekly_target, null: false, default: 7

      # 論理削除用タイムスタンプ（NULL許可）
      # NULL = 有効、日時が入っている = 削除済み
      # 過去の振り返りデータとの整合性を保つために物理削除は行わない
      t.datetime :deleted_at

      # 作成日時・更新日時（Rails標準）
      t.timestamps
    end

    # インデックス作成
    # 注: user_id のインデックスは t.references で自動作成されるため不要
    
    # 論理削除された習慣を除外する検索を高速化
    # WHERE deleted_at IS NULL の条件で頻繁に検索するため
    add_index :habits, :deleted_at

    # user_idとdeleted_atの複合インデックス
    # 「特定ユーザーの有効な習慣のみ取得」という検索が最も頻繁に行われるため
    # ダッシュボード表示などで使用
    add_index :habits, [:user_id, :deleted_at]
  end
end
