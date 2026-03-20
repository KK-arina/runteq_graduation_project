# test/integration/habit_daily_record_test.rb
# ============================================================
# Issue #17: 日次記録機能 統合テスト（補完版）
#
# 【既存テストとの関係】
# habit_record_instant_save_test.rb にTurbo Streams関連のテストが
# すでに存在します。このファイルでは、それを補完する形で
# 「記録フロー全体」の統合テストを追加します。
#
# 【テスト内容】
# - AM4:00境界値での記録日付
# - 同一日付の重複記録防止
# - セキュリティ（他ユーザーの記録操作不可）
# ============================================================

require "test_helper"

class HabitDailyRecordTest < ActionDispatch::IntegrationTest
  setup do
    @user        = users(:one)
    @other_user  = users(:two)
    # キー名変更: habit_one / habit_two に合わせて参照を更新
    @habit       = habits(:habit_one)
    @other_habit = habits(:habit_two)
  end

  private

  def log_in_as(user)
    post login_path, params: {
      session: { email: user.email, password: "password" }
    }
  end

  public

  # ===========================================================
  # ■ 日次記録 作成テスト
  # ===========================================================

  # ---------------------------------------------------------
  # 正常系: 習慣記録を作成できること
  # ---------------------------------------------------------
  test "ログイン後に習慣の日次記録を作成できること" do
    log_in_as(@user)

    # 今日の記録がまだない状態でPOSTする
    # habit_habit_records_path(@habit) → POST /habits/:habit_id/habit_records
    assert_difference("HabitRecord.count", 1) do
      post habit_habit_records_path(@habit), params: { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # 作成された記録が完了状態であることを確認
    record = HabitRecord.order(created_at: :desc).first
    assert record.completed,
      "completed: '1' を送信したので completed = true になるはず"
    assert_equal @user.id, record.user_id,
      "ログインユーザーのIDで記録が作成されるはず"
  end

  # ---------------------------------------------------------
  # 正常系: 同一日に2回POSTしても記録が重複しないこと（find_or_create）
  # 【なぜ重複しないか？】
  # habit_records テーブルには UNIQUE制約(user_id, habit_id, record_date) があります。
  # コントローラー側で find_or_create_by を使うことで、
  # 2回目以降は新規作成ではなく「更新」になります。
  # ---------------------------------------------------------
  test "同じ日に2回POSTしても HabitRecord が1件しか作成されないこと" do
    log_in_as(@user)

    # 1回目の記録作成
    post habit_habit_records_path(@habit), params: { completed: "1" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # 2回目は新規作成ではなく更新になるため件数は増えない
    assert_no_difference("HabitRecord.count") do
      post habit_habit_records_path(@habit), params: { completed: "0" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  # ---------------------------------------------------------
  # セキュリティ: 他ユーザーの習慣に記録を作成できないこと
  # ---------------------------------------------------------
  test "他ユーザーの習慣に記録を作成できないこと" do
    log_in_as(@user)

    # @other_habit はユーザー2の習慣
    assert_no_difference("HabitRecord.count") do
      post habit_habit_records_path(@other_habit), params: { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # 404 が返ること（他ユーザーの存在を漏らさない設計）
    assert_response :not_found
  end

  # ---------------------------------------------------------
  # セキュリティ: 他ユーザーのHabitRecordを更新できないこと
  # ---------------------------------------------------------
  test "他ユーザーの習慣記録を更新できないこと" do
    log_in_as(@other_user)

    # ユーザー1の記録をDBに直接作成（テスト用の下準備）
    record = HabitRecord.create!(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record,
      completed:   false
    )

    # ユーザー2がユーザー1のrecordを更新しようとする
    patch habit_habit_record_path(@habit, record),
          params:  { completed: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # 更新されていないこと
    record.reload
    assert_not record.completed,
      "他ユーザーのレコードは更新されてはいけない"
  end

  # ===========================================================
  # ■ AM4:00 境界値テスト
  # ===========================================================

  # ---------------------------------------------------------
  # AM3:59 は「前日」として扱われること
  # ---------------------------------------------------------
  test "AM3:59 は前日として記録されること" do
    log_in_as(@user)

    # travel_to: 指定した時刻にシステムを一時的に移動させるRailsのヘルパー
    # これにより「テスト実行時刻」を AM3:59 に設定できます
    # test_helper.rb で include ActiveSupport::Testing::TimeHelpers が必要です
    travel_to Time.zone.parse("2026-02-19 03:59:00") do
      today_for_record = HabitRecord.today_for_record
      # AM3:59 なので「前日」の日付になるはず
      assert_equal Date.new(2026, 2, 18), today_for_record,
        "AM4:00より前なので前日 (2026-02-18) が返るはず"
    end
  end

  # ---------------------------------------------------------
  # AM4:00 は「当日」として扱われること
  # ---------------------------------------------------------
  test "AM4:00 は当日として記録されること" do
    log_in_as(@user)

    travel_to Time.zone.parse("2026-02-19 04:00:00") do
      today_for_record = HabitRecord.today_for_record
      # AM4:00 ちょうどなので「当日」の日付
      assert_equal Date.new(2026, 2, 19), today_for_record,
        "AM4:00以降なので当日 (2026-02-19) が返るはず"
    end
  end

  # ---------------------------------------------------------
  # AM4:01 は「当日」として扱われること
  # ---------------------------------------------------------
  test "AM4:01 は当日として記録されること" do
    travel_to Time.zone.parse("2026-02-19 04:01:00") do
      today_for_record = HabitRecord.today_for_record
      assert_equal Date.new(2026, 2, 19), today_for_record,
        "AM4:01なので当日 (2026-02-19) が返るはず"
    end
  end
end
