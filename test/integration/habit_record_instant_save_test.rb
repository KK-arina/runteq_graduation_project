# ==============================================================================
# test/integration/habit_record_instant_save_test.rb（最終確定版）
# ==============================================================================
# 【修正内容】
#   toggle_completed_habit_record_path（存在しないルート）を
#   正しいネストされたルートに修正:
#     PATCH habit_habit_record_path(@habit, record)
#
# 【ルート確認方法】
#   docker compose exec web bin/rails routes | grep habit_record
#   → habit_habit_record PATCH /habits/:habit_id/habit_records/:id
#
# 【params 構造について】
#   このコントローラーは require(:habit_record) を使わないため
#   params: { completed: "1" } の形式でOK（ネスト不要）。
# ==============================================================================
require "test_helper"

class HabitRecordInstantSaveTest < ActionDispatch::IntegrationTest
  setup do
    @user        = users(:one)
    @other_user  = users(:two)
    @habit       = habits(:habit_one)
    @other_habit = habits(:habit_two)

    # ログイン
    post login_path, params: {
      session: { email: @user.email, password: "password" }
    }
  end

  # ----------------------------------------------------------------------------
  # チェックボックスをクリックすると completed が切り替わる（false → true）
  # ----------------------------------------------------------------------------
  test "チェックボックスをクリックすると completed が切り替わる（false → true）" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   false
    )

    # PATCH: 正しいネストされたルートを使う
    patch habit_habit_record_path(@habit, record),
          params:  { completed: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert record.reload.completed, "completed が true になること"
  end

  # ----------------------------------------------------------------------------
  # チェックボックスを再度クリックすると completed が元に戻る（true → false）
  # ----------------------------------------------------------------------------
  test "チェックボックスを再度クリックすると completed が元に戻る（true → false）" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   true
    )

    patch habit_habit_record_path(@habit, record),
          params:  { completed: "0" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_not record.reload.completed, "completed が false になること"
  end

  # ----------------------------------------------------------------------------
  # レスポンスが Turbo Stream 形式で返ること
  # ----------------------------------------------------------------------------
  # 【テストの意図】
  #   Accept ヘッダーに turbo-stream を指定した場合、
  #   Content-Type が text/vnd.turbo-stream.html で返ることを確認する。
  # ----------------------------------------------------------------------------
  test "レスポンスが Turbo Stream 形式で返ること" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   false
    )

    patch habit_habit_record_path(@habit, record),
          params:  { completed: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # turbo-stream が Content-Type に含まれることを確認
    assert_includes response.content_type, "turbo-stream",
                    "Content-Type に turbo-stream が含まれること"
  end

  # ----------------------------------------------------------------------------
  # 他のユーザーのレコードは 404 Not Found が返ること
  # ----------------------------------------------------------------------------
  # 【テストの意図】
  #   set_habit で他ユーザーの習慣は RecordNotFound になり
  #   head :not_found が返ることを確認する。
  # ----------------------------------------------------------------------------
  test "他のユーザーのレコードは 404 Not Found が返ること" do
    other_record = HabitRecord.create!(
      user:        @other_user,
      habit:       @other_habit,
      record_date: HabitRecord.today_for_record,
      completed:   false
    )

    # 他ユーザーの習慣・レコードへのアクセス
    # → set_habit で @other_habit が current_user のものでないため 404
    patch habit_habit_record_path(@other_habit, other_record),
          params:  { completed: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found, "他ユーザーのリソースへのアクセスは 404 になること"
    assert_not other_record.reload.completed, "他ユーザーのレコードが変更されていないこと"
  end

# ----------------------------------------------------------------------------
# 存在しない habit_record id へのアクセスはエラーが返ること
# ----------------------------------------------------------------------------
test "存在しない habit_record id へのアクセスはエラーが返ること" do
  patch habit_habit_record_path(@habit, 9999999),
        params:  { completed: "1" },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

  # Turbo Stream エラーが返る（HTTP 200 は正常）
  assert_response :success

  # エラーパーシャルの内容が含まれていることを確認
  assert_includes response.body, "記録が見つかりませんでした",
                  "エラーメッセージがレスポンスに含まれること"
end

  # ----------------------------------------------------------------------------
  # 未ログイン状態では操作できない
  # ----------------------------------------------------------------------------
  test "未ログイン状態では操作できない" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   false
    )

    delete logout_path

    patch habit_habit_record_path(@habit, record),
          params: { completed: "1" }

    assert_redirected_to login_path, "未ログイン時はログインページにリダイレクトされること"
  end
end