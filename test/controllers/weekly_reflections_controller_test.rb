# test/controllers/weekly_reflections_controller_test.rb
#
# 【このファイルの役割】
# WeeklyReflectionsController の各アクションが正しく動作するかを確認するテスト。
#
# 【テスト対象アクション】
# new    → 振り返り入力フォームの表示
# create → 振り返りの保存処理
#
# 【テストの日時設定】
# travel_to で 2026-02-22（日曜 AM5:00）に固定する。
# この週の week_start_date = 2026-02-16。
# fixtures の weekly_reflections は 2026-02-02 と 2026-02-09 始まりのため重複しない。

require "test_helper"

class WeeklyReflectionsControllerTest < ActionDispatch::IntegrationTest
  # ==========================================
  # setup: 各テスト実行前の前処理
  # ==========================================
  setup do
    @user = users(:one)
    log_in_as(@user)

    # テスト対象の日時: 2026-02-22（日曜）AM5:00
    # wday=0（日曜）かつ hour=5（AM4:00以降）→ 振り返り可能な時間帯
    @test_time = Time.zone.local(2026, 2, 22, 5, 0, 0)
  end

  # ==========================================
  # new アクション テスト
  # ==========================================

  test "new: ログイン済みユーザーが振り返りフォームにアクセスできること" do
    travel_to @test_time do
      get new_weekly_reflection_path
      assert_response :success
    end
  end

  test "new: 未ログインユーザーはログインページにリダイレクトされること" do
    delete logout_path
    travel_to @test_time do
      get new_weekly_reflection_path
      assert_redirected_to login_path
    end
  end

  test "new: 今週がすでに完了している場合は詳細ページにリダイレクトされること" do
    travel_to @test_time do
      # 今週分（week_start_date = 2026-02-16）の完了済み振り返りを作成する
      # fixtures の週とは重複しないため create! で直接作成できる
      week_start = WeeklyReflection.current_week_start_date
      completed  = WeeklyReflection.create!(
        user:               @user,
        week_start_date:    week_start,
        week_end_date:      week_start + 6.days,
        reflection_comment: "完了済みコメント",
        is_locked:          true
      )

      get new_weekly_reflection_path
      assert_redirected_to weekly_reflection_path(completed)
    end
  end

  # ==========================================
  # create アクション テスト
  # ==========================================

  test "create: 正常なパラメーターで振り返りが保存されること" do
    travel_to @test_time do
      # assert_difference でユーザー単位のカウントが +1 されることを確認する
      # 【なぜ @user.weekly_reflections.count を使うか】
      # WeeklyReflection.count（全ユーザー分）より @user.weekly_reflections.count の方が
      # テストの意図が明確になる。「このユーザーの振り返りが1件増えた」ことを確認できる。
      assert_difference "@user.weekly_reflections.count", 1 do
        post weekly_reflections_path, params: {
          weekly_reflection: {
            reflection_comment: "今週は読書を毎日継続できた。来週も継続する。"
          }
        }
      end
      assert_redirected_to weekly_reflections_path
    end
  end

  test "create: reflection_comment が空でも保存できること（任意項目）" do
    travel_to @test_time do
      assert_difference "@user.weekly_reflections.count", 1 do
        post weekly_reflections_path, params: {
          weekly_reflection: { reflection_comment: "" }
        }
      end
      assert_redirected_to weekly_reflections_path
    end
  end

  test "create: 保存後は is_locked が true になること" do
    travel_to @test_time do
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "テスト" }
      }
      # 今週分の振り返りを取得して is_locked を確認する
      saved = @user.weekly_reflections.find_by(
        week_start_date: WeeklyReflection.current_week_start_date
      )
      assert saved.is_locked, "振り返り完了後は is_locked が true になること"
    end
  end

  test "create: 同じ週に2回 create を呼んでも1件しか作成されないこと" do
    travel_to @test_time do
      # 1回目
      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "1回目" }
      }
      count_after_first = @user.weekly_reflections.count

      # 2回目（同じ週）→ 既存レコードを更新するため件数は増えない
      # assert_no_difference でカウントが変化しないことを確認する
      assert_no_difference "@user.weekly_reflections.count" do
        post weekly_reflections_path, params: {
          weekly_reflection: { reflection_comment: "2回目" }
        }
      end

      assert_equal count_after_first, @user.weekly_reflections.count
    end
  end

  test "create: 習慣数と同じ数のスナップショットが作成されること" do
    travel_to @test_time do
      # 習慣数を事前に取得する（ハードコードしないことで fixtures 変更に強くなる）
      habit_count = @user.habits.active.count

      post weekly_reflections_path, params: {
        weekly_reflection: { reflection_comment: "テストコメント" }
      }

      # 今週分の振り返りを取得
      reflection = @user.weekly_reflections.find_by(
        week_start_date: WeeklyReflection.current_week_start_date
      )

      # 習慣数とスナップショット数が一致することを確認する
      assert_equal habit_count, reflection.habit_summaries.count,
        "習慣 #{habit_count} 件分のスナップショットが作成されること"
    end
  end
end