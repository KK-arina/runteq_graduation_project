require "test_helper"

# ==================== Userモデルのテスト ====================
# このファイルは、Userモデルが正しく動作するかをテストします
# テストを書くことで、リファクタリング時やコード変更時のバグ防止になります

class UserTest < ActiveSupport::TestCase
  # ==================== セットアップ ====================
  
  # setup: 各テストの実行前に毎回実行されるメソッド
  # @user: テスト用のUserインスタンスを作成
  def setup
    @user = User.new(
      name: "テストユーザー",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end
  
  # ==================== 基本的なバリデーションテスト ====================
  
  # test: テストケースを定義
  # "should be valid": 正しいデータでUserが有効であることをテスト
  # assert: 条件が真（true）であることを検証
  # @user.valid?: Userインスタンスのバリデーションが通るか確認
  test "should be valid" do
    assert @user.valid?
  end
  
  # ==================== name（ユーザー名）のバリデーションテスト ====================
  
  # "name should be present": nameが必須であることをテスト
  # @user.name = " ": nameを空白文字列に設定
  # assert_not: 条件が偽（false）であることを検証
  test "name should be present" do
    @user.name = "   "
    assert_not @user.valid?
  end
  
  # "name should not be too long": nameが50文字以下であることをテスト
  # "a" * 51: "a"を51回繰り返した文字列を生成
  test "name should not be too long" do
    @user.name = "a" * 51
    assert_not @user.valid?
  end
  
  # ==================== email（メールアドレス）のバリデーションテスト ====================
  
  # "email should be present": emailが必須であることをテスト
  test "email should be present" do
    @user.email = "   "
    assert_not @user.valid?
  end
  
  # "email validation should accept valid addresses": 
  # 有効なメールアドレス形式を受け入れることをテスト
  test "email validation should accept valid addresses" do
    # valid_addresses: テストする有効なメールアドレスのリスト
    valid_addresses = %w[user@example.com USER@foo.COM A_US-ER@foo.bar.org
                         first.last@foo.jp alice+bob@baz.cn]
    # each: リストの各要素に対してブロック内の処理を実行
    valid_addresses.each do |valid_address|
      @user.email = valid_address
      # assert: バリデーションが通ることを確認
      # "#{valid_address.inspect} should be valid": エラー時のメッセージ
      assert @user.valid?, "#{valid_address.inspect} should be valid"
    end
  end
  
  # "email validation should reject invalid addresses":
  # 無効なメールアドレス形式を拒否することをテスト
  test "email validation should reject invalid addresses" do
    # invalid_addresses: テストする無効なメールアドレスのリスト
    invalid_addresses = %w[user@example,com user_at_foo.org user.name@example.
                           foo@bar_baz.com foo@bar+baz.com]
    invalid_addresses.each do |invalid_address|
      @user.email = invalid_address
      # assert_not: バリデーションが通らないことを確認
      assert_not @user.valid?, "#{invalid_address.inspect} should be invalid"
    end
  end
  
  # "email addresses should be unique":
  # メールアドレスが一意（重複不可）であることをテスト
  test "email addresses should be unique" do
    # dup: @userのコピーを作成
    duplicate_user = @user.dup
    # @userを先に保存
    @user.save
    # 同じメールアドレスのユーザーを保存しようとする
    # assert_not: バリデーションエラーで保存できないことを確認
    assert_not duplicate_user.valid?
  end
  
  # "email addresses should be saved as lowercase":
  # メールアドレスが小文字で保存されることをテスト
  test "email addresses should be saved as lowercase" do
    # 大文字と小文字が混在したメールアドレスを設定
    mixed_case_email = "Foo@ExAmPle.CoM"
    @user.email = mixed_case_email
    @user.save
    # reload: データベースから最新の値を再読み込み
    # assert_equal: 2つの値が等しいことを検証
    # mixed_case_email.downcase: 小文字に変換した期待値
    # @user.reload.email: データベースに保存された実際の値
    assert_equal mixed_case_email.downcase, @user.reload.email
  end
  
  # ==================== password（パスワード）のバリデーションテスト ====================
  
  # "password should be present (nonblank)":
  # パスワードが必須であることをテスト
  test "password should be present (nonblank)" do
    # password と password_confirmation の両方を空白に設定
    @user.password = @user.password_confirmation = " " * 6
    assert_not @user.valid?
  end
  
  # "password should have a minimum length":
  # パスワードが最小8文字であることをテスト
  test "password should have a minimum length" do
    # 7文字のパスワードを設定（8文字未満）
    @user.password = @user.password_confirmation = "a" * 7
    assert_not @user.valid?
  end
  
  # ==================== パスワード暗号化のテスト ====================
  
  # "password should be encrypted":
  # パスワードが暗号化されて保存されることをテスト
  # ★修正★: encrypted_password → password_digest
  test "password should be encrypted" do
    @user.save
    # assert_not_equal: 2つの値が等しくないことを検証
    # "password123": 平文パスワード
    # @user.password_digest: データベースに保存された暗号化パスワード
    # 平文パスワードがそのまま保存されていないことを確認
    assert_not_equal "password123", @user.password_digest
  end
  
  # "authenticated user should return true with correct password":
  # authenticateメソッドが正しいパスワードでtrueを返すことをテスト
  test "authenticated user should return true with correct password" do
    @user.save
    # authenticate: has_secure_passwordが提供するメソッド
    # 正しいパスワードを渡すとUserインスタンスを返す
    # 間違ったパスワードを渡すとfalseを返す
    assert @user.authenticate("password123")
  end
  
  # "authenticated user should return false with incorrect password":
  # authenticateメソッドが間違ったパスワードでfalseを返すことをテスト
  test "authenticated user should return false with incorrect password" do
    @user.save
    # assert_not: 条件が偽であることを検証
    # 間違ったパスワードを渡すとfalseが返ることを確認
    assert_not @user.authenticate("wrongpassword")
  end
end
