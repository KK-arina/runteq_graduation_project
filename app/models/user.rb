class User < ApplicationRecord
  # BCryptによるパスワード暗号化
  # password, password_confirmationという仮想属性を提供
  # authenticateメソッドでパスワード認証が可能になる
  has_secure_password

  # ===================================================================
  # アソシエーション（関連付け）
  # ===================================================================
  
  # ユーザーは複数の習慣を持つ（1対多の「1」側）
  # has_many :habits → user.habitsでユーザーの習慣一覧を取得可能
  # dependent: :destroy → ユーザーが削除されたら関連する習慣も削除
  # これにより、ユーザー退会時にゴミデータが残るのを防ぐ
  has_many :habits, dependent: :destroy

  # ===================================================================
  # コールバック（特定のタイミングで自動実行される処理）
  # ===================================================================
  
  # 保存前にメールアドレスを小文字に変換
  # before_save → saveメソッド実行直前に呼ばれる
  # downcase! → 文字列を小文字に変換（!付きは破壊的メソッド）
  before_save { self.email = email.downcase }

  # ===================================================================
  # バリデーション（データの妥当性チェック）
  # ===================================================================
  
  # 名前の必須チェックと文字数制限
  validates :name, presence: true, length: { maximum: 50 }
  
  # メールアドレスの必須チェック
  validates :email, presence: true
  
  # メールアドレスの一意性チェック（大文字小文字を区別しない）
  # uniqueness: true → 重複したメールアドレスを許可しない
  # case_sensitive: false → 大文字小文字を区別しない
  validates :email, uniqueness: { case_sensitive: false }
  
  # メールアドレスの形式チェック
  # format: → 正規表現でパターンマッチング
  # URI::MailTo::EMAIL_REGEXP → Rubyの標準ライブラリが提供するメール形式の正規表現
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  
  # パスワードの文字数制限
  # allow_nil: true → 更新時にパスワードが未指定でもOK（新規作成時はhas_secure_passwordがチェック）
  validates :password, length: { minimum: 8 }, allow_nil: true
end
