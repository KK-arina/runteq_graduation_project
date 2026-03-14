class AddUniqueIndexToUsersEmail < ActiveRecord::Migration[7.2]
  def change
    # 既存のインデックスを確認して重複を避ける
    remove_index :users, :email, if_exists: true
    add_index :users, :email, unique: true
  end
end
