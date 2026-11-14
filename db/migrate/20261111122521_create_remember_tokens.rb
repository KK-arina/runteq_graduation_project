# db/migrate/XXXXXXXXXXXXXX_create_remember_tokens.rb
#
# ==============================================================================
# 「ログインしたままにする」用のトークンを保存するテーブルを作る
# ==============================================================================
#
# 【なぜ users にカラムを足すのではなく、新しいテーブルにするのか】
#   users に1カラムだけ足す方式だと、1ユーザーにつき1台分しか記録できない。
#   スマホとパソコンの両方で「ログインしたまま」にしたり、
#   「この端末だけ解除」「すべての端末を解除」を選べるようにするには、
#   1端末 = 1行 で記録できる専用テーブルが必要になる。
#
# 【このテーブルに「生のトークン」を保存しない理由】
#   Cookie に入れる生のトークンは「合言葉」そのもの。
#   DB には SHA-256 で変換した値（token_digest）だけを保存する。
#   万一 DB の中身が漏れても、digest から元の合言葉は計算で戻せないため、
#   なりすましに使われない。
# ==============================================================================
class CreateRememberTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :remember_tokens do |t|
      # user: どのユーザーのトークンか。
      #   null: false          → ユーザーのいないトークンは存在させない
      #   foreign_key          → 存在しないユーザーIDを入れられないよう DB が守る
      #   on_delete: :cascade  → テストなどでユーザーを物理削除したとき、
      #                          トークンも DB が自動で一緒に消す（外部キー違反を防ぐ）
      #   t.references は user_id の検索用インデックスも自動で作る
      t.references :user, null: false, foreign_key: { on_delete: :cascade }

      # token_digest: 生のトークンを SHA-256 で変換した値（64文字の16進数）。
      #   自動ログインのたびに「この値で1行を探す」ため、下でユニークインデックスを張る。
      t.string :token_digest, null: false

      # expires_at: このトークンの有効期限。
      #   使うたびに延長されるが、最初の発行から180日を超えることはない（モデルで制御）。
      t.datetime :expires_at, null: false

      # last_used_at: 最後に自動ログインで使われた日時。
      #   「1日に1回だけ期限を延長する」判定に使い、DB への書き込み回数を抑える。
      t.datetime :last_used_at, null: false

      # created_at / updated_at を自動で作る。
      #   created_at は「最長180日」の起点としても使う。
      t.timestamps
    end

    # token_digest のユニークインデックス
    #   ① 自動ログイン時の検索を速くする（全件を順番に見ずに済む）
    #   ② 同じ digest が2行できる事故を DB レベルで防ぐ
    add_index :remember_tokens, :token_digest, unique: true
  end
end