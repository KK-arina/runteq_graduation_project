# frozen_string_literal: true
# test/integration/habit_record_instant_save_test.rb
# =============================================================
# 習慣記録の即時保存機能（Turbo Stream）の統合テスト
# チェックボックスON/OFFの保存・エラー処理を検証する
# =============================================================

require "test_helper"

class HabitRecordInstantSaveTest < ActionDispatch::IntegrationTest
  def setup
    # fixturesからテスト用データを取得
    @user  = users(:one)
    @habit = habits(:habit_one)
  end

  # ---- 未ログイン時のアクセス制御テスト ----
  test "未ログイン時はログインページにリダイレクトされること" do
    post habit_habit_records_path(@habit),
         params:  { completed: "1" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_redirected_to login_path
  end

  # ---- 新規レコード作成（POST）テスト ----
  test "チェックボックスONで今日の記録が新規作成されること" do
    log_in_as(@user)

    assert_difference "HabitRecord.count", 1 do
      post habit_habit_records_path(@habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # Turbo Stream レスポンスが返ること
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  # ---- 既存レコード更新（PATCH）テスト ----
  test "チェックボックスOFFで既存レコードが更新されること" do
    log_in_as(@user)

    # 事前にレコードを作成しておく
    record = HabitRecord.find_or_create_for(@user, @habit)
    record.update!(completed: true)

    patch habit_habit_record_path(@habit, record),
          params:  { completed: "0" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    # 値が更新されていることをDBで確認
    assert_equal false, record.reload.completed
  end

  # ---- 存在しないIDへのアクセステスト ----
  test "存在しない habit_record id へのアクセスはエラーが返ること" do
    log_in_as(@user)

    patch habit_habit_record_path(@habit, 9999999),
          params:  { completed: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # ------------------------------------------------------------------
    # ✅ 修正ポイント
    # 旧: assert_response :success（200を期待）
    #     → HabitRecordsController#set_habit で head :not_found を返す
    #       実装のため、実際は404が返っていた
    #
    # 新: assert_response :not_found（404を期待）
    #     存在しないIDには404を返すのが正しいセキュリティ設計
    #     他人のレコードIDを推測してアクセスしても404になる
    # ------------------------------------------------------------------
    assert_response :not_found
  end
end