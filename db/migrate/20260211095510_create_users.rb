# ==================== Usersテーブル作成マイグレーション ====================
# このファイルは、usersテーブルをデータベースに作成するための設計図です
# rails db:migrate コマンドで実行され、テーブルが作成されます

class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    # create_table: usersテーブルを作成
    # do |t|: ブロック内でカラム（列）を定義
    create_table :users do |t|
      # ==================== ユーザー基本情報 ====================
      
      # name: ユーザーの表示名（例: 山田太郎）
      # string型: 最大255文字の文字列
      # null: false: NULL（空）を許可しない（必須項目）
      t.string :name, null: false
      
      # email: ログイン認証用のメールアドレス
      # string型: 最大255文字の文字列
      # null: false: NULL（空）を許可しない（必須項目）
      t.string :email, null: false
      
      # password_digest: bcryptでハッシュ化されたパスワード
      # ★重要★: has_secure_passwordを使う場合、カラム名は必ず password_digest にする
      # Railsがこのカラム名を前提として、自動的にパスワードのハッシュ化・認証を行う
      # string型: 最大255文字の文字列
      # null: false: NULL（空）を許可しない（必須項目）
      # 注意: 平文パスワードは保存しない（セキュリティのため）
      t.string :password_digest, null: false

      # ==================== タイムスタンプ ====================
      # created_at: レコード作成日時（自動設定）
      # updated_at: レコード更新日時（自動設定）
      t.timestamps
    end
    
    # ==================== インデックスの追加 ====================
    
    # add_index: インデックス（検索を高速化）を追加
    # [:email]: emailカラムにインデックスを作成
    # unique: true: 同じ値の重複を許可しない（一意性制約）
    # メールアドレスは1つのアカウントにつき1つのみ許可
    add_index :users, :email, unique: true
  end
end
