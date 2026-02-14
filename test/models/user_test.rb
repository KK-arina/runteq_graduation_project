require "test_helper"

# ==================== Userモデルのテスト ====================
# このファイルは、Userモデルのバリデーションや機能が正しく動作するかをテストします
# モデルテスト: データベースに保存する前の検証ロジックをテスト

class UserTest < ActiveSupport::TestCase
  # ==================== テスト用データの準備 ====================
  # setup: 各テストの前に実行されるメソッド
  # テスト用の有効なユーザーを作成
  def setup
    # @user: テスト用のユーザーインスタンスを作成（まだ保存していない）
    # 有効なデータを持つユーザーを作成し、各テストでこのデータを使用
    @user = User.new(
      name: "テストユーザー",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  # ==================== 正常系テスト ====================
  # test: テストケースを定義
  # "should be valid":
  # 有効なデータを持つユーザーが保存できることをテスト
  test "should be valid" do
    # assert: 条件が真（true）であることを検証
    # @user.valid?: ユーザーが有効かどうかをチェック
    # 有効な場合: true、無効な場合: false
    assert @user.valid?
  end

  # ==================== nameバリデーションテスト ====================
  # "name should be present":
  # nameが空の場合、バリデーションエラーになることをテスト
  test "name should be present" do
    # @user.name = "": nameを空文字列に設定
    @user.name = ""
    
    # assert_not: 条件が偽（false）であることを検証
    # @user.valid?は false を返すはず（バリデーションエラー）
    assert_not @user.valid?
  end

  # "name should not be too long":
  # nameが50文字を超える場合、バリデーションエラーになることをテスト
  test "name should not be too long" do
    # "a" * 51: "a"を51回繰り返す（51文字の文字列）
    @user.name = "a" * 51
    
    assert_not @user.valid?
  end

  # ==================== emailバリデーションテスト ====================
  # "email should be present":
  # emailが空の場合、バリデーションエラーになることをテスト
  test "email should be present" do
    @user.email = ""
    assert_not @user.valid?
  end

  # "email validation should accept valid addresses":
  # 有効なメールアドレス形式が受け入れられることをテスト
  test "email validation should accept valid addresses" do
    # 有効なメールアドレスのリスト
    valid_addresses = %w[
      user@example.com
      USER@foo.COM
      A_US-ER@foo.bar.org
      first.last@foo.jp
      alice+bob@baz.cn
    ]
    
    # each: 配列の各要素に対して処理を実行
    valid_addresses.each do |valid_address|
      # @user.email = valid_address: 有効なメールアドレスを設定
      @user.email = valid_address
      
      # assert: 有効であることを検証
      # "#{valid_address.inspect} should be valid": エラーメッセージ
      # inspect: オブジェクトを文字列に変換（デバッグ用）
      assert @user.valid?, "#{valid_address.inspect} should be valid"
    end
  end

  # "email validation should reject invalid addresses":
  # 無効なメールアドレス形式が拒否されることをテスト
  test "email validation should reject invalid addresses" do
    # 無効なメールアドレスのリスト
    invalid_addresses = %w[
      user@example,com
      user_at_foo.org
      user.name@example.
      foo@bar_baz.com
      foo@bar+baz.com
    ]
    
    invalid_addresses.each do |invalid_address|
      @user.email = invalid_address
      assert_not @user.valid?, "#{invalid_address.inspect} should be invalid"
    end
  end

  # "email addresses should be unique":
  # 同じメールアドレスのユーザーは登録できないことをテスト
  test "email addresses should be unique" do
    # @user.save: テスト用のユーザーをデータベースに保存
    @user.save
    
    # duplicate_user: 同じメールアドレスを持つ別のユーザーを作成
    # dup: オブジェクトを複製
    duplicate_user = @user.dup
    
    # assert_not: 重複ユーザーは保存できない（valid?が false）
    assert_not duplicate_user.valid?
  end

  # "email addresses should be unique regardless of case":
  # 大文字小文字を区別せずに一意性が保証されることをテスト
  # 
  # なぜこのテストが重要？
  # - データベースによっては大文字小文字を区別する場合がある
  # - "Test@Example.com" と "test@example.com" が別のユーザーとして登録されるのを防ぐ
  # - before_save コールバックで email を小文字に変換しているため、これが正しく動作することを検証
  test "email addresses should be unique regardless of case" do
    @user.save
    
    # duplicate_user: 同じメールアドレスを大文字に変換したユーザーを作成
    duplicate_user = @user.dup
    duplicate_user.email = @user.email.upcase
    
    # assert_not: 大文字小文字が異なっても重複として検出される
    assert_not duplicate_user.valid?
  end

  # "email addresses should be saved as lower-case":
  # メールアドレスが小文字で保存されることをテスト
  test "email addresses should be saved as lower-case" do
    # 大文字を含むメールアドレスを設定
    mixed_case_email = "Foo@ExAMPle.CoM"
    @user.email = mixed_case_email
    
    # @user.save: データベースに保存
    @user.save
    
    # @user.reload: データベースから最新のデータを再読み込み
    # before_save コールバックで小文字に変換されているはず
    @user.reload
    
    # assert_equal: 2つの値が等しいことを検証
    # @user.email: データベースに保存されたメールアドレス
    # mixed_case_email.downcase: 期待される値（小文字）
    assert_equal mixed_case_email.downcase, @user.email
  end

  # ==================== passwordバリデーションテスト ====================
  # "password should be present (nonblank)":
  # パスワードが空の場合、バリデーションエラーになることをテスト
  test "password should be present (nonblank)" do
    # " " * 6: 6つの空白文字
    @user.password = @user.password_confirmation = " " * 6
    assert_not @user.valid?
  end

  # "password should have a minimum length":
  # パスワードが8文字未満の場合、バリデーションエラーになることをテスト
  test "password should have a minimum length" do
    @user.password = @user.password_confirmation = "a" * 7
    assert_not @user.valid?
  end

  # ==================== パスワード暗号化テスト ====================
  # "password should be encrypted":
  # パスワードが暗号化されて保存されることをテスト
  test "password should be encrypted" do
    @user.save
    
    # assert_not_nil: 値がnilでないことを検証
    # @user.password_digest: 暗号化されたパスワード
    assert_not_nil @user.password_digest
    
    # assert_not_equal: 2つの値が等しくないことを検証
    # パスワードは平文では保存されない
    assert_not_equal "password123", @user.password_digest
  end

  # "authenticate should return user for correct password":
  # 正しいパスワードで認証できることをテスト
  test "authenticate should return user for correct password" do
    @user.save
    
    # @user.authenticate("password123"): パスワード認証
    # 正しいパスワードの場合: Userオブジェクトを返す
    assert_equal @user, @user.authenticate("password123")
  end

  # "authenticate should return false for incorrect password":
  # 間違ったパスワードで認証できないことをテスト
  test "authenticate should return false for incorrect password" do
    @user.save
    
    # @user.authenticate("wrong"): 間違ったパスワードで認証
    # 間違ったパスワードの場合: false を返す
    assert_not @user.authenticate("wrong")
  end
end
