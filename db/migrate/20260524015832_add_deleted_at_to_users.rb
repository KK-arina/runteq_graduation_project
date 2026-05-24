# db/migrate/20260524000001_add_deleted_at_to_users.rb
#
# ==============================================================================
# マイグレーション: users テーブルへ deleted_at カラムを追加 + 部分インデックス設計
# ==============================================================================
#
# 【このマイグレーションで行うこと】
#   ① deleted_at カラムを追加する（論理削除フラグ）
#   ② email の unique 制約を「退会していないユーザー間のみ」の部分インデックスに変更
#   ③ provider + uid の unique 制約も同様に変更
#   ④ up/down を明示的に分けることで db:rollback が安全に動作するようにする
#
# 【change メソッドではなく up/down を使う理由】
#   change メソッド内で remove_index を使うと、Rails は
#   「元のインデックスがどんな設定だったか」を自動で復元できない。
#   up/down に分けることで rollback 時に元のインデックスを正確に再作成できる。
# ==============================================================================

class AddDeletedAtToUsers < ActiveRecord::Migration[7.2]
  # up: db:migrate 実行時に呼ばれる（適用）
  def up
    # ─── ① deleted_at カラムを追加する ──────────────────────────────────────
    #
    # null: true にする理由:
    #   有効なユーザー（退会していない）は deleted_at が NULL の状態。
    #   「NULL = 有効」「値あり = 退会済み」として扱う。
    #   null: false にすると既存ユーザー全員に初期値が必要になり意味がおかしくなる。
    add_column :users, :deleted_at, :datetime, null: true

    # ─── ② deleted_at に部分インデックスを追加する ──────────────────────────
    #
    # where: "deleted_at IS NULL" にする理由:
    #   有効ユーザー（deleted_at=NULL）だけをインデックス対象にすることで
    #   インデックスのサイズを小さく保ち、検索を高速化できる。
    add_index :users, :deleted_at,
              name:  "index_users_on_deleted_at",
              where: "deleted_at IS NULL"

    # ─── ③ email の unique 制約を部分インデックスに変更する ──────────────────
    #
    # 【変更前】全行対象の unique → 退会アドレスと同じアドレスで再登録不可
    # 【変更後】deleted_at IS NULL の行のみ対象 → 退会済みアドレスで再登録可能
    remove_index :users, name: "index_users_on_email"

    add_index :users, :email,
              unique: true,
              name:   "index_users_on_email_active",
              where:  "deleted_at IS NULL"

    # ─── ④ provider + uid の unique 制約も部分インデックスに変更する ─────────
    #
    # OAuth アカウントも退会後に同じプロバイダ・uid で再登録できるようにする。
    remove_index :users, name: "index_users_on_provider_and_uid"

    add_index :users, [ :provider, :uid ],
              unique: true,
              name:   "index_users_on_provider_and_uid_active",
              where:  "deleted_at IS NULL"
  end

  # down: db:rollback 実行時に呼ばれる（元に戻す）
  #
  # 【なぜ down を明示するのか】
  #   up の逆順で完全に元に戻すことで、ロールバック後も
  #   schema.rb が up 適用前と完全に一致することを保証する。
  def down
    # up で追加したものを逆順に削除する
    remove_index :users, name: "index_users_on_provider_and_uid_active"
    remove_index :users, name: "index_users_on_email_active"
    remove_index :users, name: "index_users_on_deleted_at"
    remove_column :users, :deleted_at

    # 元々存在していた全行対象のインデックスを再作成して元通りに戻す
    add_index :users, :email,
              unique: true,
              name:   "index_users_on_email"

    add_index :users, [ :provider, :uid ],
              unique: true,
              name:   "index_users_on_provider_and_uid"
  end
end