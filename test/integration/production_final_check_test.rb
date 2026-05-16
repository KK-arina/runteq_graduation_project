# test/integration/production_final_check_test.rb
#
# ==============================================================================
# 【E-1 修正内容】
#   reflection_comment に presence: true バリデーションを追加したため、
#   weekly_reflections.create! に reflection_comment を追加する。
#   該当箇所: ロック状態を作るための create! が複数テストに存在する。
# ==============================================================================

require "test_helper"

class ProductionFinalCheckTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      name:                  "最終確認ユーザー",
      email:                 "final_check@example.com",
      password:              "password123",
      password_confirmation: "password123",
      first_login_at:        1.month.ago
    )
  end

  def teardown
    travel_back
  end

  test "ユーザー登録が正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      assert_difference "User.count", 1 do
        post users_path, params: {
          user: {
            name:                  "新規テストユーザー",
            email:                 "new_user_test@example.com",
            password:              "password123",
            password_confirmation: "password123"
          }
        }
      end
      assert_redirected_to dashboard_path
    end
  end

  test "ログインが正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_redirected_to dashboard_path
    end
  end

  test "誤ったパスワードではログインできないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "wrong_password" } }
      assert_response :unprocessable_entity
    end
  end

  test "ログアウトが正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      delete logout_path
      assert_redirected_to root_path
    end
  end

  test "習慣の作成が正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_difference "Habit.count", 1 do
        post habits_path, params: { habit: { name: "テスト習慣", weekly_target: 5 } }
      end
      assert_redirected_to habits_path
    end
  end

  test "習慣の論理削除が正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      habit = @user.habits.create!(name: "削除テスト習慣", weekly_target: 7)
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      delete habit_path(habit)
      assert_redirected_to habits_path
      habit.reload
      assert_not_nil habit.deleted_at
    end
  end

  test "未ログイン状態では習慣一覧にアクセスできないこと" do
    get habits_path
    assert_redirected_to %r{/login}
  end

  test "ダッシュボードが正常に表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      @user.habits.create!(name: "読書", weekly_target: 7)
      @user.habits.create!(name: "筋トレ", weekly_target: 5)
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      get dashboard_path
      assert_response :success
    end
  end

  test "習慣がない状態でもダッシュボードが表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      get dashboard_path
      assert_response :success
    end
  end

  test "習慣が10件あってもダッシュボードが正常に表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      10.times { |i| @user.habits.create!(name: "習慣#{i + 1}", weekly_target: 7) }
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      get dashboard_path
      assert_response :success
    end
  end

  test "週次振り返りを作成できること" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      @user.habits.create!(name: "読書", weekly_target: 7)
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_difference "WeeklyReflection.count", 1 do
        post weekly_reflections_path, params: {
          weekly_reflection: {
            reflection_comment:   "今週は読書を7日間達成できました。",
            direct_reason:        "読書の習慣が定着してきた",       # E-1追加
            background_situation: "朝の時間を有効活用した",         # E-1追加
            next_action:          "他の習慣にも同様の工夫を広げる"   # E-1追加
          }
        }
      end
      assert_response :redirect
    end
  end

  test "週次振り返り一覧ページが表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      get weekly_reflections_path
      assert_response :success
    end
  end

  test "週次振り返り詳細ページが表示されること" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      reflection = @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        reflection_comment: "テスト振り返りコメント",
        direct_reason:        "テスト用の直接原因", # E-1追加: presence必須化対応
        background_situation: "テスト用の改善策",   # E-1追加: presence必須化対応
        next_action:          "テスト用の次への展開", # E-1追加: presence必須化対応
        completed_at:       Time.zone.local(2026, 3, 9, 9, 0, 0),
        is_locked:          true
      )
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      get weekly_reflection_path(reflection)
      assert_response :success
    end
  end

  test "ロック中は習慣を作成できないこと" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      # ── E-1 修正: reflection_comment を追加 ────────────────────────────────
      @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        completed_at:       nil,
        is_locked:          false,
        reflection_comment: "ロックテスト用コメント", # E-1 追加
        direct_reason:        "テスト用の直接原因", # E-1追加
        background_situation: "テスト用の改善策",   # E-1追加
        next_action:          "テスト用の次への展開", # E-1追加
      )
      # ────────────────────────────────────────────────────────────────────────

      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_no_difference "Habit.count" do
        post habits_path, params: { habit: { name: "ロック中の習慣", weekly_target: 7 } }
      end
      assert_response :redirect
    end
  end

  test "月曜AM3:59はロックが発動しないこと" do
    travel_to Time.zone.local(2026, 3, 9, 3, 59, 0) do
      # ── E-1 修正: reflection_comment を追加 ────────────────────────────────
      @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        completed_at:       nil,
        is_locked:          false,
        reflection_comment: "AM3:59テスト用コメント", # E-1 追加
        direct_reason:        "テスト用の直接原因", # E-1追加
        background_situation: "テスト用の改善策",   # E-1追加
        next_action:          "テスト用の次への展開", # E-1追加
      )
      # ────────────────────────────────────────────────────────────────────────

      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_difference "Habit.count", 1 do
        post habits_path, params: { habit: { name: "AM4時前の習慣", weekly_target: 7 } }
      end
      assert_redirected_to habits_path
    end
  end

  test "月曜AM4:00ちょうどでロックが発動すること" do
    travel_to Time.zone.local(2026, 3, 9, 4, 0, 0) do
      # ── E-1 修正: reflection_comment を追加 ────────────────────────────────
      @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        completed_at:       nil,
        is_locked:          false,
        reflection_comment: "AM4:00境界値テスト用コメント", # E-1 追加
        direct_reason:        "テスト用の直接原因", # E-1追加
        background_situation: "テスト用の改善策",   # E-1追加
        next_action:          "テスト用の次への展開", # E-1追加
      )
      # ────────────────────────────────────────────────────────────────────────

      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_no_difference "Habit.count" do
        post habits_path, params: { habit: { name: "境界値テスト習慣", weekly_target: 7 } }
      end
      assert_response :redirect
    end
  end

  test "振り返り完了でロックが解除されること" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      # ── E-1 修正: reflection_comment を追加 ────────────────────────────────
      @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        completed_at:       nil,
        is_locked:          false,
        reflection_comment: "ロック解除テスト用コメント", # E-1 追加
        direct_reason:        "テスト用の直接原因", # E-1追加
        background_situation: "テスト用の改善策",   # E-1追加
        next_action:          "テスト用の次への展開", # E-1追加
      )
      # ────────────────────────────────────────────────────────────────────────

      post login_path, params: { session: { email: @user.email, password: "password123" } }
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "ロック解除テスト用の振り返りコメント。" }
      }
      assert_redirected_to dashboard_path
      follow_redirect!
      assert_select "body", text: /PDCAロックが解除されました/
    end
  end

  test "存在しないURLにアクセスすると404が返ること" do
    get "/this_path_does_not_exist"
    assert_response :not_found
  end

  test "他のユーザーの習慣は削除できないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      other_user = User.create!(
        name:                  "他ユーザー",
        email:                 "other_user@example.com",
        password:              "password123",
        password_confirmation: "password123",
        first_login_at:        1.month.ago
      )
      other_habit = other_user.habits.create!(name: "他ユーザーの習慣", weekly_target: 7)
      post login_path, params: { session: { email: @user.email, password: "password123" } }
      assert_no_difference "Habit.count" do
        delete habit_path(other_habit)
      end
      other_habit.reload
      assert_nil other_habit.deleted_at
    end
  end
end
