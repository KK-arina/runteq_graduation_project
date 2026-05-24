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

  # ============================================================
  # F-2 追加: LINE OmniAuth テスト
  # ============================================================

  test "from_omniauth creates a new LINE user without email" do
    auth = {
      "provider" => "line_v2_1",   # :line_v21 プロバイダなので "line_v21" が入る
      "uid"      => "sub_#{SecureRandom.hex(8)}",
      "info"     => {
        "name"  => "LINE ユーザー太郎",
        "image" => "https://profile.line.me/sample.png"
      }
    }

    assert_difference "User.count", 1 do
      user = User.from_omniauth(auth)

      assert_equal auth["uid"], user.uid
      assert_equal "line_v2_1",          user.provider  # "line_v21" で保存される
      assert_equal "LINE ユーザー太郎", user.name
      assert_nil user.email
      assert user.persisted?
    end
  end

  test "from_omniauth returns existing LINE user on second login" do
    uid = "sub_existing_#{SecureRandom.hex(8)}"
    auth = {
      "provider" => "line_v2_1",   # 修正
      "uid"      => uid,
      "info"     => { "name" => "LINE ユーザー二郎" }
    }

    first_user = User.from_omniauth(auth)
    assert first_user.persisted?

    assert_no_difference "User.count" do
      second_user = User.from_omniauth(auth)
      assert_equal first_user.id, second_user.id
    end
  end

  test "from_omniauth uses LINE User as fallback name when LINE name is blank" do
    auth = {
      "provider" => "line_v2_1",   # 修正
      "uid"      => "sub_noname_#{SecureRandom.hex(8)}",
      "info"     => { "name" => nil }
    }

    user = User.from_omniauth(auth)
    assert_equal "LINE User", user.name
    assert user.persisted?
  end

  test "LINE user is valid without password" do
    line_user = User.new(
      provider: "line_v21",        # 修正
      uid:      "sub_valid_#{SecureRandom.hex(8)}",
      name:     "LINE テストユーザー",
      email:    nil,
      password: nil
    )

    assert line_user.valid?,
           "LINE ユーザーがパスワードなしで invalid になっています: #{line_user.errors.full_messages}"
  end

  # ============================================================
  # F-6 追加: 論理削除・再登録関連テスト
  # ============================================================

  test "scope :active は deleted_at が nil のユーザーのみ返すこと" do
    active_user = User.create!(
      name:                  "有効ユーザー",
      email:                 "active_#{SecureRandom.hex(4)}@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    deleted_user = User.create!(
      name:                  "退会済み",
      email:                 "deleted_tmp_#{SecureRandom.hex(4)}@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )
    deleted_user.update_columns(
      deleted_at: Time.current,
      email:      "deleted_#{deleted_user.id}@deleted.invalid"
    )

    assert User.active.exists?(active_user.id),
           "active スコープに有効ユーザーが含まれるべき"

    assert_not User.active.exists?(deleted_user.id),
               "active スコープに退会済みユーザーが含まれるべきでない"
  end

  test "退会済みユーザーと同じメールで新規登録できること" do
    original_email = "reregister_#{SecureRandom.hex(4)}@example.com"

    old_user = User.create!(
      name:                  "旧ユーザー",
      email:                 original_email,
      password:              "password123",
      password_confirmation: "password123"
    )
    old_user.update_columns(
      deleted_at: Time.current,
      email:      "deleted_#{old_user.id}@deleted.invalid"
    )

    new_user = User.new(
      name:                  "新ユーザー",
      email:                 original_email,
      password:              "password123",
      password_confirmation: "password123"
    )

    assert new_user.valid?,
           "退会済みユーザーと同じメールで新規登録できるべき: #{new_user.errors.full_messages}"
  end
end
