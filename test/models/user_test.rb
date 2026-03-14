require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = User.new(
      name: "Test User",
      email: "user_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "should be valid" do
    assert @user.valid?
  end

  test "name should be present" do
    @user.name = ""
    assert_not @user.valid?
    assert @user.errors.added?(:name, :blank)
  end

  test "name should not be too long" do
    @user.name = "a" * 51
    assert_not @user.valid?
    # too_long は count オプションが必要
    assert @user.errors.added?(:name, :too_long, count: 50)
  end

  test "email should be present" do
    @user.email = ""
    assert_not @user.valid?
    assert @user.errors.added?(:email, :blank)
  end

  test "email should be unique" do
    duplicate_user = @user.dup
    @user.save!
    assert_not duplicate_user.valid?
    # taken は case_sensitive オプション付きで発生
    assert duplicate_user.errors[:email].any?,
           "emailにエラーがありません: #{duplicate_user.errors.full_messages}"
    assert_includes duplicate_user.errors.map(&:type), :taken
  end

  test "email should be unique case insensitive" do
    @user.save!
    duplicate_user = @user.dup
    duplicate_user.email = @user.email.upcase
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors.map(&:type), :taken
  end

  test "email should have valid format" do
    invalid_emails = %w[user@example,com user_at_example.org user.name@example. @example.com]
    invalid_emails.each do |invalid_email|
      @user.email = invalid_email
      assert_not @user.valid?, "#{invalid_email.inspect} should be invalid"
    end
  end

  test "email should be saved as lowercase" do
    mixed_case_email = "MiXeD_#{SecureRandom.hex(4)}@ExAmPlE.cOm"
    user = User.new(
      name: "Test User",
      email: mixed_case_email,
      password: "password123",
      password_confirmation: "password123"
    )
    user.save!
    assert_equal mixed_case_email.downcase, user.reload.email
  end

  test "password should be present" do
    @user.password = @user.password_confirmation = ""
    assert_not @user.valid?
    @user.password = @user.password_confirmation = nil
    assert_not @user.valid?
  end

  test "password should have minimum length" do
    @user.password = @user.password_confirmation = "a" * 7
    assert_not @user.valid?
    # too_short は minimum オプションが必要
    assert @user.errors.added?(:password, :too_short, count: 8)
  end

  test "password should match confirmation" do
    @user.password = "password123"
    @user.password_confirmation = "different"
    assert_not @user.valid?
  end

  test "authenticated? should return false for a user with nil digest" do
    assert_not @user.authenticate("password")
  end
end
