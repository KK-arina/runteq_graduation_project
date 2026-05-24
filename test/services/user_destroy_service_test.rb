# test/services/user_destroy_service_test.rb
#
# ==============================================================================
# UserDestroyService のテスト（F-6 確定版・B案統計保持）
#
# 【テスト設計の方針】
#   ① 個人識別情報が匿名化されること（完了条件1）
#   ② 統計データ（習慣・タスク）が保持されること（B案要件）
#   ③ セキュリティデータが物理削除されること
#   ④ 同じメールアドレスで再登録できること（完了条件2）
#   ⑤ 退会後にパスワード認証できないこと
#   ⑥ 成功時の戻り値が正しいこと
# ==============================================================================

require "test_helper"

class UserDestroyServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name:                  "テストユーザー",
      email:                 "destroy_test_#{SecureRandom.hex(4)}@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    @habit = Habit.create!(
      user:             @user,
      name:             "テスト習慣",
      weekly_target:    5,
      measurement_type: :check_type
    )

    @task = Task.create!(
      user:  @user,
      title: "テストタスク"
    )

    # PasswordResetToken のカラムを schema.rb に合わせて修正
    #
    # schema.rb の定義:
    #   t.string   "token_digest", null: false  ← token ではなく token_digest
    #   t.datetime "expires_at",   null: false  ← expired_at ではなく expires_at
    #   t.boolean  "is_used",      default: false
    #
    # token_digest には BCrypt でハッシュ化した値を入れる
    # （PasswordResetsController の実装に合わせた形式）
    raw_token      = SecureRandom.hex(32)
    token_digest   = BCrypt::Password.create(raw_token)

    @reset_token = PasswordResetToken.create!(
      user:         @user,
      token_digest: token_digest,
      expires_at:   Time.current + 1.hour
    )
  end

  # ── ① 個人識別情報が匿名化されること ────────────────────────────────────
  test "退会後に個人識別情報が取得できないこと" do
    result = UserDestroyService.new(user: @user).call
    assert result[:success], "サービスが成功を返すべき: #{result[:error]}"

    @user.reload

    assert_not_nil @user.deleted_at,
                   "deleted_at が設定されるべき"

    assert_equal "退会済みユーザー", @user.name,
                 "name が匿名化されるべき"

    # 汎用パターンで検証（user.id 依存を避ける）
    assert_match(/\Adeleted_.+@deleted\.invalid\z/, @user.email,
                 "email が匿名化アドレスに変わるべき")

    assert_nil @user.line_user_id,
               "line_user_id が nil になるべき"

    assert_equal "deleted", @user.provider,
                 "provider が 'deleted' になるべき"

    assert_nil @user.uid,
               "uid が nil になるべき"
  end

  # ── ② パスワード認証できないこと（実装非依存の振る舞いテスト）─────────────
  test "退会後にパスワードでログインできないこと" do
    UserDestroyService.new(user: @user).call
    @user.reload

    # authenticate の結果で「ログイン不能」を検証する
    # password_digest の値（nil/空/ハッシュ）に依存しない
    assert_not @user.authenticate("password123"),
               "退会後はパスワード認証が失敗するべき"
  end

  # ── ③ 統計データ（習慣・タスク）が保持されること（B案要件）──────────────
  test "退会後も習慣・タスクは統計用に保持されること" do
    habit_id = @habit.id
    task_id  = @task.id

    UserDestroyService.new(user: @user).call

    # B案: 物理削除しないことを確認
    assert Habit.exists?(habit_id),
           "退会後も習慣は統計用に保持されるべき"

    assert Task.exists?(task_id),
           "退会後もタスクは統計用に保持されるべき"
  end

  # ── ④ セキュリティデータが物理削除されること ─────────────────────────────
  test "退会後にパスワードリセットトークンが削除されること" do
    token_id = @reset_token.id
    UserDestroyService.new(user: @user).call

    assert_not PasswordResetToken.exists?(token_id),
               "退会後にパスワードリセットトークンが削除されるべき"
  end

  # ── ⑤ 同じメールアドレスで再登録できること（F-6 完了条件2）──────────────
  test "退会後に同じメールアドレスで再登録できること" do
    original_email = @user.email
    UserDestroyService.new(user: @user).call

    new_user = nil
    assert_nothing_raised do
      new_user = User.create!(
        name:                  "新規ユーザー",
        email:                 original_email,
        password:              "newpassword123",
        password_confirmation: "newpassword123"
      )
    end

    assert new_user.persisted?,
           "同じメールアドレスで再登録できるべき"
  end

  # ── ⑥ 戻り値が正しいこと ─────────────────────────────────────────────────
  test "成功時に success: true を返すこと" do
    result = UserDestroyService.new(user: @user).call

    assert result[:success], "成功時に success: true を返すべき"
    assert_nil result[:error], "成功時に error: nil を返すべき"
  end
end