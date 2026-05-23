# db/migrate/YYYYMMDDHHMMSS_add_terms_agreed_at_to_users.rb
#
# ==============================================================================
# F-3: users テーブルに terms_agreed_at カラムを追加するマイグレーション
# ==============================================================================
#
# 【なぜ datetime 型で null: true にするのか】
#   - datetime 型: 「いつ同意したか」を記録することで、規約改定時に
#     「この規約バージョンに同意済みか」を将来判定できる。
#     boolean だと同意有無しか分からず、規約改定対応が困難になる。
#   - null: true（NULL許容）: 既存ユーザーには terms_agreed_at が存在しない。
#     NOT NULL にすると既存レコードへのデフォルト値設定が必要になり
#     マイグレーションが複雑になるため NULL 許容にする。
# ==============================================================================
class AddTermsAgreedAtToUsers < ActiveRecord::Migration[7.2]
  def change
    # add_column: 既存テーブルに新しいカラムを追加する。
    # 引数: テーブル名, カラム名, データ型
    # null: true → NULL を許可する（既存ユーザーへの影響を防ぐため）
    add_column :users, :terms_agreed_at, :datetime, null: true

    # add_index: 同意済みユーザーを絞り込む検索のためにインデックスを追加。
    # where: "terms_agreed_at IS NOT NULL" → 同意済みレコードのみインデックス対象にする
    # （NULL のレコードをインデックスに含めないことでインデックスサイズを削減できる）
    add_index :users, :terms_agreed_at,
              name:  "index_users_on_terms_agreed_at",
              where: "terms_agreed_at IS NOT NULL"
  end
end