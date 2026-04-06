# test/integration/memo_flow_test.rb
#
# ==============================================================================
# メモ機能の統合テスト（B-7）
# ==============================================================================
#
# 【このテストファイルの役割】
#   コントローラー・サービス・モデルを通した一連の流れをテストする。
#
# 【fixture 名について】
#   users.yml  → one / two / locked_user
#   habits.yml → habit_one / habit_two / habit_deleted
#
# 【ログインの params 形式について】
#   SessionsController#create は params[:session][:email] という形式を期待している。
#   つまり params: { session: { email: "...", password: "..." } } と渡す必要がある。
#
#   ❌ 誤り: params: { email: "...", password: "..." }
#      → params[:session] が nil になり NoMethodError が発生する
#
#   ✅ 正しい: params: { session: { email: "...", password: "..." } }
#      → params[:session][:email] が正しく取得できる
#
# 【テスト実行コマンド】
#   docker compose exec web bin/rails test test/integration/memo_flow_test.rb
#
# ==============================================================================

require "test_helper"

class MemoFlowTest < ActionDispatch::IntegrationTest
  def setup
    @user  = users(:one)
    @habit = habits(:habit_one)

    # ログイン状態にする
    # SessionsController#create は params[:session][:email] / [:password] を参照する。
    # そのため session: { ... } というネストした形式で渡す必要がある。
    post login_path, params: { session: { email: @user.email, password: "password" } }
  end

  # ============================================================
  # PATCH /habits/:habit_id/habit_records/:id でのメモ更新テスト
  # ============================================================

  test "チェック型習慣のメモを保存できる" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   true,
      memo:        nil
    )

    patch habit_habit_record_path(@habit, record),
          params:  { completed: "1", memo: "今日は調子がよかった" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    record.reload
    assert_equal "今日は調子がよかった", record.memo
  end

  test "メモを空文字で上書きするとメモが削除される" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   true,
      memo:        "以前のメモ"
    )

    patch habit_habit_record_path(@habit, record),
          params:  { completed: "1", memo: "" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    record.reload
    # サービス内で memo.presence を使っているので空文字は nil になる
    assert_nil record.memo
  end

  test "メモが201文字以上の場合は保存できない（バリデーションエラー）" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   true,
      memo:        nil
    )

    patch habit_habit_record_path(@habit, record),
          params:  { completed: "1", memo: "a" * 201 },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # バリデーションエラーで 422 Unprocessable Entity が返ることを確認する
    assert_response :unprocessable_entity

    record.reload
    assert_nil record.memo
  end

  test "スペースのみのメモは nil として保存される" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   false,
      memo:        nil
    )

    patch habit_habit_record_path(@habit, record),
          params:  { completed: "0", memo: "   " },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    record.reload
    # strip.presence で nil になるため、スペースのみは nil 保存される
    assert_nil record.memo
  end

  test "チェック操作をしても既存のメモは消えない（部分更新の確認）" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   false,
      memo:        "大切なメモ"
    )

    # memo パラメータを送らずに completed だけ送る（チェックボックス操作を模倣）
    patch habit_habit_record_path(@habit, record),
          params:  { completed: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    record.reload
    # completed は更新されている
    assert_equal true, record.completed
    # memo は変わっていない（部分更新が正しく動いている）
    assert_equal "大切なメモ", record.memo
  end

  test "メモ保存操作をしてもチェック状態は変わらない（部分更新の確認）" do
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   true,
      memo:        nil
    )

    # memo パラメータだけを送る（completed は送らない）
    patch habit_habit_record_path(@habit, record),
          params:  { memo: "新しいメモ" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success

    record.reload
    # memo は更新されている
    assert_equal "新しいメモ", record.memo
    # completed は変わっていない（true のまま）
    assert_equal true, record.completed
  end
end