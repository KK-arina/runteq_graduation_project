# db/migrate/YYYYMMDDHHMMSS_create_user_purposes.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# user_purposes テーブルを新規作成する。
#
# 【このテーブルの役割】
# ユーザーの PMVV（Purpose / Mission / Vision / Value / Current）目標を管理する。
# 目標を更新するたびに新しいバージョンとして追記し、履歴を保持する。
# （上書きするのではなく新しいレコードを作成する「バージョン管理」方式）
#
# 【5つの要素と質問文】
#   purpose           : 「人生で一番大切にしていることは？」
#   mission           : 「今の自分に最も必要なことは？」
#   vision            : 「1年後どんな自分になっていたいか？」
#   value             : 「絶対に譲れないことは？」
#   current_situation : 「今の自分の現状を教えてください」
#
# 【analysis_state（分析状態）の値】
#   0: pending   → GoodJob に投入済みで、ジョブが実行待ちの状態
#   1: analyzing → ジョブが実行中（AI が分析しています）
#   2: completed → 分析が正常に完了した
#   3: failed    → 分析が失敗した（last_error_message にエラー内容を保存）
# ==============================================================================

class CreateUserPurposes < ActiveRecord::Migration[7.2]
  def change
    create_table :user_purposes do |t|
      # ─────────────────────────────────────────────────────────────────────
      # user_id: このPMVVを所有するユーザー（外部キー）
      # ─────────────────────────────────────────────────────────────────────
      # null: false → 必ずユーザーに紐づく
      # on_delete: :cascade → ユーザー削除時に PMVV も一緒に削除
      t.references :user,
                   null: false,
                   foreign_key: { on_delete: :cascade }

      # ─────────────────────────────────────────────────────────────────────
      # PMVV 5要素（入力テキスト）
      # ─────────────────────────────────────────────────────────────────────

      # purpose: Purpose（目的）
      # 「人生で一番大切にしていることは？」の回答
      # text 型: 長い文章を保存できる（1000文字をモデルでバリデーション）
      # NULL 許可: すべての要素は任意入力（最低1つ入れることを UI で誘導する）
      t.text :purpose

      # mission: Mission（使命）
      # 「今の自分に最も必要なことは？」の回答
      t.text :mission

      # vision: Vision（理想像）
      # 「1年後どんな自分になっていたいか？」の回答
      t.text :vision

      # value: Value（価値観）
      # 「絶対に譲れないことは？」の回答
      t.text :value

      # current_situation: 現状
      # 「今の自分の現状を教えてください」の回答
      # Vision とのギャップを分析するために AI が使用する重要なフィールド
      t.text :current_situation

      # ─────────────────────────────────────────────────────────────────────
      # バージョン管理
      # ─────────────────────────────────────────────────────────────────────

      # version: バージョン番号
      # 目標を更新するたびに新しいレコードを作成し、version を 1 ずつ増やす
      # 初回は 1 からスタート
      # integer 型、null: false
      t.integer :version, null: false, default: 1

      # is_active: 現在有効な（最新の）バージョンか
      # true  → このレコードが現在有効な PMVV（ダッシュボードなどで使用）
      # false → 過去バージョン（履歴として保持するが表示しない）
      # 目標を更新するとき: 新レコードを is_active: true で作成し、
      #   古いレコードを is_active: false に更新する
      t.boolean :is_active, null: false, default: true

      # ─────────────────────────────────────────────────────────────────────
      # AI 分析状態管理
      # ─────────────────────────────────────────────────────────────────────

      # analysis_state: AI 分析の進行状態
      # integer 型: Rails の enum で管理（0: pending / 1: analyzing / 2: completed / 3: failed）
      # default: 0 → 保存直後は「分析待ち」状態でジョブに投入する
      t.integer :analysis_state, null: false, default: 0

      # last_error_message: 分析失敗時のエラーメッセージ
      # analysis_state が failed（3）のときにエラー内容を保存する
      # ユーザーへの「失敗しました。再試行してください」表示にも使用
      # text 型: NULL 許可（成功時は NULL）
      t.text :last_error_message

      # created_at・updated_at を自動で追加する
      t.timestamps
    end

    # ─────────────────────────────────────────────────────────────────────────
    # INDEX の追加
    # ─────────────────────────────────────────────────────────────────────────

    # (user_id, is_active) の複合インデックス
    # 「このユーザーの現在有効な PMVV を取得する」クエリを高速化
    # WHERE user_id = ? AND is_active = true の検索に使用
    # これが最も頻繁に実行されるクエリのため、インデックスが重要
    add_index :user_purposes,
              [ :user_id, :is_active ],
              name: 'index_user_purposes_on_user_id_and_is_active'
  end
end
