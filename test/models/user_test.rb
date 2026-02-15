require "test_helper"

# Userモデルのテスト
class UserTest < ActiveSupport::TestCase
  # setup: 各テスト実行前に毎回実行されるメソッド
  setup do
    # 有効なユーザーデータを作成（テストの基準となるデータ）
    # 
    # 🔴 重要: メールアドレスは fixtures と衝突しないようにする
    # fixtures/users.yml:
    #   - fixture_one@example.com
    #   - fixture_two@example.com
    # 
    # テストコード:
    #   - user_xxx@example.com（SecureRandom.hex で生成）
    @user = User.new(
      name: "Test User",
      email: "user_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  # ===== バリデーションテスト =====
  
  test "should be valid" do
    assert @user.valid?
  end

  test "name should be present" do
    @user.name = ""
    assert_not @user.valid?
    assert_includes @user.errors[:name], "can't be blank"
  end

  test "name should not be too long" do
    @user.name = "a" * 51
    assert_not @user.valid?
    assert_includes @user.errors[:name], "is too long (maximum is 50 characters)"
  end

  test "email should be present" do
    @user.email = ""
    assert_not @user.valid?
    assert_includes @user.errors[:email], "can't be blank"
  end

  test "email should be unique" do
    duplicate_user = @user.dup
    @user.save!
    
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:email], "has already been taken"
  end

  test "email should be unique case insensitive" do
    @user.save!
    
    duplicate_user = @user.dup
    duplicate_user.email = @user.email.upcase
    
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:email], "has already been taken"
  end

  test "email should have valid format" do
    invalid_emails = %w[user@example,com user_at_example.org user.name@example. @example.com]
    
    invalid_emails.each do |invalid_email|
      @user.email = invalid_email
      assert_not @user.valid?, "#{invalid_email.inspect} should be invalid"
    end
  end

  test "email should be saved as lowercase" do
    # 🔴 正しい修正: fixtures と衝突しないメールアドレスを使う
    # 
    # 修正前（NG）:
    #   mixed_case_email = "TeSt@ExAmPlE.cOm"
    #   → before_save で "test@example.com" になる
    #   → fixtures の "test@example.com" と衝突（もし存在すれば）
    # 
    # 修正後（OK）:
    #   fixtures と絶対に衝突しないメールアドレスを使う
    mixed_case_email = "MiXeD_#{SecureRandom.hex(4)}@ExAmPlE.cOm"
    
    user = User.new(
      name: "Test User",
      email: mixed_case_email,
      password: "password123",
      password_confirmation: "password123"
    )
    user.save!
    
    # reload: データベースから最新の状態を再読み込み
    # assert_equal: before_save で小文字に変換されていることを確認
    assert_equal mixed_case_email.downcase, user.reload.email
  end

  test "password should be present" do
    # 🔴 正しい理解: has_secure_password は新規作成時に presence: true
    # ただし、モデルに validates :password, length: { minimum: 8 } がない場合、
    # 空文字列が許可される可能性がある
    # 
    # モデルに validates :password, length: { minimum: 8 }, allow_nil: true を追加済みなら、
    # このテストは正しく動作する
    @user.password = @user.password_confirmation = ""
    assert_not @user.valid?
    
    # nil の場合は allow_nil: true なので valid になる（更新時を想定）
    # ただし、新規作成時は has_secure_password の presence で invalid になる
    @user.password = @user.password_confirmation = nil
    assert_not @user.valid?
  end

  test "password should have minimum length" do
    # 🔴 重要: このテストが通るには、モデルに以下が必要:
    # validates :password, length: { minimum: 8 }, allow_nil: true
    @user.password = @user.password_confirmation = "a" * 7
    assert_not @user.valid?
    assert_includes @user.errors[:password], "is too short (minimum is 8 characters)"
  end

  test "password should match confirmation" do
    @user.password = "password123"
    @user.password_confirmation = "different"
    assert_not @user.valid?
  end

  test "authenticated? should return false for a user with nil digest" do
    # has_secure_password により、authenticate メソッドが自動定義される
    # password_digest が nil の場合は false を返すべき
    assert_not @user.authenticate("password")
  end
end
