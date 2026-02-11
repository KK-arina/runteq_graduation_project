# ==================== Userモデル ====================
# このモデルは、usersテーブルと対応するRubyクラスです
# ユーザーの認証、バリデーション、パスワード管理を担当します

class User < ApplicationRecord
  # ==================== パスワード暗号化機能 ====================
  
  # has_secure_password: bcrypt gemを使用してパスワードを暗号化
  # ★重要★: このメソッドは password_digest カラムが存在することを前提とする
  # この1行で以下の機能が自動的に追加されます：
  # 1. password属性（仮想属性、DBには保存されない）
  # 2. password_confirmation属性（確認用、DBには保存されない）
  # 3. authenticateメソッド（パスワード認証用）
  # 4. password_digestカラムに自動的にハッシュ化して保存
  # 5. 新規作成時の presence バリデーション（password必須）
  has_secure_password
  
  # ==================== バリデーション ====================
  
  # --- name（ユーザー名）のバリデーション ---
  # presence: true: 必須項目（空欄不可）
  # length: { maximum: 50 }: 最大50文字まで
  validates :name, 
            presence: true,
            length: { maximum: 50 }
  
  # --- email（メールアドレス）のバリデーション ---
  # presence: true: 必須項目（空欄不可）
  # uniqueness: { case_sensitive: false }: 大文字小文字を区別せず一意
  #   例: "User@Example.com" と "user@example.com" は同一と見なす
  # format: { with: URI::MailTo::EMAIL_REGEXP }: メールアドレス形式をチェック
  #   Rails 7.2標準の正規表現を使用（RFC準拠）
  #   例: "test@example.com" → OK
  #   例: "invalid-email" → NG
  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  
  # --- password（パスワード）のバリデーション ---
  # allow_nil: true: 更新時にパスワードを変更しない場合はnilを許可
  #   新規作成時は has_secure_password が自動的に presence チェックするため問題なし
  # length: { minimum: 8 }: 最小8文字（セキュリティのため）
  # ★完璧な設定★:
  #   - 新規作成時: has_secure_password → password必須
  #   - 更新時: allow_nil: true → パスワード変更しない場合はスキップ可能
  validates :password,
            allow_nil: true,
            length: { minimum: 8 }
  
  # ==================== コールバック ====================
  
  # before_save: データベースに保存する直前に実行されるメソッド
  # :downcase_email: 下記で定義したメソッドを実行
  before_save :downcase_email
  
  private
  
  # downcase_email: メールアドレスを小文字に統一
  # 理由: データベース検索時の一貫性を保つため
  # 例: "User@Example.COM" → "user@example.com"
  # self.email: 現在のUserインスタンスのemailを参照
  # downcase: 文字列を小文字に変換するRubyメソッド
  def downcase_email
    self.email = email.downcase if email.present?
  end
end
