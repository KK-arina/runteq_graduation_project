# db/migrate/xxxx_remove_not_null_from_users_email.rb
#
# ==============================================================================
# F-2: users.email の NOT NULL 制約を解除するマイグレーション
# ==============================================================================
#
# 【なぜこのマイグレーションが必要なのか】
#
#   LINE ログインではメールアドレスを取得できないため、
#   users.email カラムは NULL になる。
#
#   Rails モデルの allow_nil: true はあくまで「Railsレベルのバリデーション」のみ。
#   PostgreSQL の NOT NULL 制約はRailsのバリデーションとは別に存在し、
#   INSERT 時にDBレベルで NULL を拒否するためエラーになる。
#
#   → DB の NOT NULL 制約（null: false）を解除する必要がある。
#
# 【schema.rb での現状】
#   t.string "email", null: false   ← これが LINE ユーザーの email=nil を弾く
#
# 【このマイグレーション後】
#   t.string "email", null: true    ← NULL を許容する（LINE ユーザー対応）
#
# 【既存のメールログインユーザーへの影響】
#   User モデルの presence: true バリデーションが email の空文字を弾くため、
#   既存のメールログインユーザーは引き続きメールアドレスが必須のまま。
#   DB制約を緩めるだけで、アプリの動作ロジックは変わらない。
#
# ==============================================================================
class RemoveNotNullFromUsersEmail < ActiveRecord::Migration[7.2]
  def change
    # change_column_null:
    #   カラムの NULL 許容/非許容を変更するメソッド。
    #   第3引数 true = NULL を許容する（NOT NULL 制約を解除）
    #   第3引数 false = NOT NULL 制約を追加する
    change_column_null :users, :email, true
  end
end