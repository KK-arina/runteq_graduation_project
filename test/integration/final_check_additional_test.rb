# test/integration/final_check_additional_test.rb
#
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   weekly_reflections.create! に reflection_comment を追加する。
# ==============================================================================

require "test_helper"

class FinalCheckAdditionalTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      name:                  "追加確認ユーザー",
      email:                 "additional_check@example.com",
      password:              "password123",
      password_confirmation: "password123",
      first_login_at:        1.month.ago
    )
  end

  def teardown
    travel_back
  end

  test "他のユーザーの週次振り返り詳細にアクセスできないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      other_user = User.create!(
        name:                  "他ユーザー振り返り",
        email:                 "other_reflection@example.com",
        password:              "password123",
        password_confirmation: "password123",
        first_login_at:        1.month.ago
      )
      other_reflection = other_user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 2, 23),
        week_end_date:      Date.new(2026, 3, 1),
        reflection_comment: "他ユーザーの振り返りコメント",
        direct_reason:        "テスト用の直接原因", # E-1追加: presence必須化対応
        background_situation: "テスト用の改善策",   # E-1追加: presence必須化対応
        next_action:          "テスト用の次への展開", # E-1追加: presence必須化対応
        completed_at:       Time.zone.local(2026, 3, 2, 10, 0, 0),
        is_locked:          true
      )
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      get weekly_reflection_path(other_reflection)
      assert_redirected_to weekly_reflections_path
    end
  end

  test "習慣名が空の場合422エラーが返ること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_no_difference "Habit.count" do
        post habits_path, params: { habit: { name: "", weekly_target: 5 } }
      end
      assert_response :unprocessable_entity
    end
  end

  test "週次目標が8の場合422エラーが返ること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_no_difference "Habit.count" do
        post habits_path, params: { habit: { name: "バリデーションテスト習慣", weekly_target: 8 } }
      end
      assert_response :unprocessable_entity
    end
  end

  test "重複メールアドレスで登録すると422エラーが返ること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      assert_no_difference "User.count" do
        post users_path, params: {
          user: {
            name:                  "重複ユーザー",
            email:                 "additional_check@example.com",
            password:              "password123",
            password_confirmation: "password123"
          }
        }
      end
      assert_response :unprocessable_entity
    end
  end

  test "存在しないURLへのPOSTリクエストも404が返ること" do
    post "/this_path_also_does_not_exist"
    assert_response :not_found
  end

  test "存在しないURLへのDELETEリクエストも404が返ること" do
    delete "/this_path_does_not_exist_either"
    assert_response :not_found
  end

  test "習慣名に含まれるスクリプトタグがエスケープされること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      xss_name = "<script>alert('XSS')</script>"
      post habits_path, params: { habit: { name: xss_name, weekly_target: 3 } }
      get habits_path
      assert_response :success
      assert_includes response.body, "&lt;script&gt;"
    end
  end

  test "パスワードが8文字未満では登録できないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      assert_no_difference "User.count" do
        post users_path, params: {
          user: {
            name:                  "短パスワードユーザー",
            email:                 "short_pass@example.com",
            password:              "abc",
            password_confirmation: "abc"
          }
        }
      end
      assert_response :unprocessable_entity
    end
  end

  test "ログアウト後はダッシュボードにアクセスできないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      delete logout_path
      get dashboard_path
      assert_redirected_to %r{/login}
    end
  end

  test "ロック中は習慣を削除できないこと" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      # ── E-1 修正: reflection_comment を追加 ────────────────────────────────
      @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        completed_at:       nil,
        is_locked:          false,
        reflection_comment: "ロック中削除テスト用コメント", # E-1 追加
        direct_reason:        "テスト用の直接原因", # E-1追加
        background_situation: "テスト用の改善策",   # E-1追加
        next_action:          "テスト用の次への展開", # E-1追加
      )
      # ────────────────────────────────────────────────────────────────────────

      habit = @user.habits.create!(name: "削除禁止テスト習慣", weekly_target: 7)
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      delete habit_path(habit)
      habit.reload
      assert_nil habit.deleted_at, "ロック中に習慣が削除されてしまいました"
    end
  end

  test "前週の振り返りが完了済みなら火曜日もロックが発動しないこと" do
    travel_to Time.zone.local(2026, 3, 10, 10, 0, 0) do
      @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        reflection_comment: "完了済み",
        direct_reason:        "テスト用の直接原因", # E-1追加: presence必須化対応
        background_situation: "テスト用の改善策",   # E-1追加: presence必須化対応
        next_action:          "テスト用の次への展開", # E-1追加: presence必須化対応
        completed_at:       Time.zone.local(2026, 3, 9, 10, 0, 0),
        is_locked:          false
      )
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_difference "@user.habits.count", 1 do
        post habits_path, params: { habit: { name: "火曜日の習慣", weekly_target: 5 } }
      end
      assert_redirected_to habits_path
    end
  end
end
