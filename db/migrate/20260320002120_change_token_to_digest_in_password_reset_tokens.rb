# db/migrate/YYYYMMDDHHMMSS_change_token_to_digest_in_password_reset_tokens.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# password_reset_tokens テーブルの token カラムを
# より安全な token_digest カラムに変更する。
#
# 【なぜ token → token_digest に変更するのか？】
#
# ■ 現状の問題（token をそのまま保存するリスク）
# 仮に DB が漏洩した場合（SQLインジェクション・バックアップファイルの流出など）、
# token カラムの平文文字列がそのまま攻撃者に読まれてしまう。
# 攻撃者は「https://habitflow.app/password_reset?token=流出した値」という
# URLを作るだけで、任意のユーザーのパスワードをリセットできてしまう。
#
# ■ 解決策（token_digest にハッシュ化して保存する）
# Devise と同じアプローチ:
#   1. ランダムなトークン（平文）を生成する → メールのURLに含めてユーザーに送る
#   2. そのトークンを bcrypt または SHA-256 でハッシュ化（digest）する
#   3. DB には「ハッシュ化した値（token_digest）」だけを保存する
#
# 認証フロー:
#   ユーザーがURLのトークン（平文）を持ってアクセス
#   → サーバーがハッシュ化して token_digest と比較
#   → 一致すれば認証成功
#
# DB が漏洩しても token_digest（ハッシュ値）からは平文トークンを逆算できないため
# 攻撃者はパスワードリセットURLを作れない。
#
# 【変更の影響】
# password_reset_tokens テーブルを新規作成したばかりで本番データはゼロのため、
# カラム名変更によるデータ損失リスクはない。
# ==============================================================================

class ChangeTokenToDigestInPasswordResetTokens < ActiveRecord::Migration[7.2]
  def up
    # ─────────────────────────────────────────────────────────────────────────
    # 既存の token カラムと UNIQUE インデックスを削除する
    # ─────────────────────────────────────────────────────────────────────────
    # まずインデックスを削除してから、カラムを削除する順番が重要。
    # インデックスが残ったままカラムを削除しようとすると PostgreSQL がエラーを出すことがある。
    #
    # if_exists: true → インデックスが存在しない場合もエラーにならない（冪等性の確保）
    remove_index :password_reset_tokens,
                 name: 'index_password_reset_tokens_on_token_unique',
                 if_exists: true

    # token カラムを削除する
    # remove_column の引数:
    #   第1引数: テーブル名
    #   第2引数: 削除するカラム名
    #   第3引数: カラムの型（down メソッドで復元できるように型情報を渡す）
    remove_column :password_reset_tokens, :token, :string

    # ─────────────────────────────────────────────────────────────────────────
    # token_digest カラムを追加する
    # ─────────────────────────────────────────────────────────────────────────
    # string 型: SHA-256 や bcrypt のハッシュ値（固定長の文字列）を保存する
    # null: false → ハッシュなしのレコードは作成できない（必須）
    add_column :password_reset_tokens, :token_digest, :string, null: false

    # ─────────────────────────────────────────────────────────────────────────
    # token_digest の UNIQUE インデックスを追加する
    # ─────────────────────────────────────────────────────────────────────────
    # ハッシュ値も一意である必要がある（衝突が起きても DB レベルで防ぐ）
    # unique: true → 重複を DB レベルで禁止する
    add_index :password_reset_tokens,
              :token_digest,
              unique: true,
              name: 'index_password_reset_tokens_on_token_digest_unique'

    # ─────────────────────────────────────────────────────────────────────────
    # user_id の UNIQUE インデックスを追加する
    # ─────────────────────────────────────────────────────────────────────────
    # 【なぜ user_id を UNIQUE にするのか？】
    # 1人のユーザーに対してリセットトークンは1件のみ存在すべき。
    # もし「リセットメールを2回送った」という場合は：
    #   - 古いトークンを is_used: true にしてから
    #   - 新しいトークンを作成する
    # という運用にすることで多重発行・多重リセットを防ぐ。
    #
    # これにより「古いリンクでリセットしようとしたが、新しいリンクを発行したから無効」
    # という自然な挙動が実現できる。
    add_index :password_reset_tokens,
              :user_id,
              unique: true,
              name: 'index_password_reset_tokens_on_user_id_unique'
  end

  def down
    # ─────────────────────────────────────────────────────────────────────────
    # ロールバック時の処理（up の逆順で元に戻す）
    # ─────────────────────────────────────────────────────────────────────────
    remove_index :password_reset_tokens,
                 name: 'index_password_reset_tokens_on_user_id_unique',
                 if_exists: true
    remove_index :password_reset_tokens,
                 name: 'index_password_reset_tokens_on_token_digest_unique',
                 if_exists: true
    remove_column :password_reset_tokens, :token_digest, :string

    # token カラムを元に戻す
    add_column :password_reset_tokens, :token, :string, null: false
    add_index :password_reset_tokens,
              :token,
              unique: true,
              name: 'index_password_reset_tokens_on_token_unique'
  end
end