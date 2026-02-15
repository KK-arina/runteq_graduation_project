# ユーザーを管理するモデル
# 認証機能（ログイン・ログアウト）を提供する
class User < ApplicationRecord
  # ===== アソシエーション =====
  # has_many: このユーザーは複数の習慣を持つ（1:Nの関係）
  # habits: Habit モデルとの関連付け
  # dependent: :destroy => ユーザーが削除されたら、紐づく習慣も自動的に削除される
  has_many :habits, dependent: :destroy

  # ===== before_save コールバック =====
  # before_save: モデルが保存される直前に実行される処理
  # ブロック内の処理: email を小文字に変換する
  # 理由: メールアドレスの大文字小文字を統一し、重複チェックを正確にするため
  # 例: "Test@Example.com" → "test@example.com"
  before_save { self.email = email.downcase }

  # ===== バリデーション =====
  # name: ユーザー名のバリデーション
  # presence: true => 必須項目（空欄不可）
  # length: { maximum: 50 } => 最大50文字まで
  validates :name, presence: true, length: { maximum: 50 }

  # email: メールアドレスのバリデーション
  # presence: true => 必須項目（空欄不可）
  # uniqueness: { case_sensitive: false } => 一意性制約（大文字小文字を区別しない）
  # format: 正規表現でメールアドレスの形式をチェック
  #   \A: 文字列の先頭
  #   [\w+\-.]+: 英数字、+、-、. のいずれかが1文字以上
  #   @: @ 記号
  #   [a-z\d\-.]+: 英小文字、数字、-、. のいずれかが1文字以上
  #   \.: . (ドット)
  #   [a-z]+: 英小文字が1文字以上
  #   \z: 文字列の末尾
  #   i: 大文字小文字を区別しない
  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i }

  # ===== has_secure_password =====
  # Rails標準のパスワード認証機能を有効化
  # 
  # 自動的に以下を提供:
  # 1. password と password_confirmation の仮想属性
  # 2. password_digest カラムへの bcrypt ハッシュ化
  # 3. authenticate メソッド（パスワード認証）
  # 4. バリデーション:
  #    - presence: true（新規作成時のみ）
  #    - confirmation: true（password_confirmation が必要）
  #    - length: { maximum: 72 }（bcrypt の制限）
  # 
  # 🔴 重要: has_secure_password は最低文字数バリデーションを含まない
  # そのため、明示的に validates :password を追加する必要がある
  has_secure_password

  # password: パスワードのバリデーション
  # length: { minimum: 8 } => 最小8文字
  # allow_nil: true => nil の場合はスキップ（更新時にパスワードを変更しない場合）
  # 
  # 🔴 重要: このバリデーションがないと、空文字列のパスワードが許可される
  # has_secure_password だけでは最低文字数をチェックしない
  validates :password, length: { minimum: 8 }, allow_nil: true
end
