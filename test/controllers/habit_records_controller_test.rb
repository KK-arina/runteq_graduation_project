# ==============================================================================
# habit_records_controller_test.rb（Issue #15 修正版）
# ==============================================================================
# 【追加テスト内容】
#   ① 同日二重作成がされないこと（find_or_create_for の動作確認）
#   ② 他ユーザーのレコードは更新できないこと（セキュリティ確認）
#   ③ AM 4:00 境界値テスト（深夜3:59 → 前日扱い / AM4:01 → 当日扱い）
#
# 【AM 4:00 境界テストについて】
#   travel_to は Rails 標準の時刻固定ヘルパー。
#   Gemfile に timecop は不要。ActiveSupport::Testing::TimeHelpers を使う。
#   （Rails 4.1 以降は標準で使える）
#
# 【テストの命名規則】
#   「〜こと」で終わる日本語テスト名にすることで、
#   テスト失敗時にどの仕様が壊れたか一目でわかる。
# ==============================================================================
require "test_helper"

class HabitRecordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user        = users(:one)
    @other_user  = users(:two)
    @habit       = habits(:one)
    @other_habit = habits(:two)

    # ログイン
    post login_path, params: {
      session: { email: @user.email, password: "password" }
    }
  end

  # ============================================================================
  # create アクションのテスト
  # ============================================================================

  test "POST create でレコードが作成され completed が true になること" do
    assert_difference("HabitRecord.count", 1) do
      post habit_habit_records_path(@habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success

    record = HabitRecord.last
    assert     record.completed,                            "completed が true になること"
    assert_equal @user.id,  record.user_id,                "ログインユーザーに紐づくこと"
    assert_equal @habit.id, record.habit_id,               "対象習慣に紐づくこと"
    assert_equal HabitRecord.today_for_record, record.record_date, "AM4:00基準の日付になること"
  end

  test "POST create でレコードが作成され completed が false になること" do
    assert_difference("HabitRecord.count", 1) do
      post habit_habit_records_path(@habit),
           params:  { completed: "0" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_not HabitRecord.last.completed, "completed が false になること"
  end

  # --------------------------------------------------------------------------
  # 【追加テスト①】同日二重作成されないこと
  # --------------------------------------------------------------------------
  # 【テストの意図】
  #   find_or_create_for が正しく動作しているかを確認する。
  #   2回 POST しても HabitRecord が1件しか作られないこと、
  #   かつ2回目のリクエストで completed の値が更新されることを検証する。
  # --------------------------------------------------------------------------
  test "同日に2回 POST しても HabitRecord が1件だけ作成され2回目の値で更新されること" do
    # 1回目: チェックあり
    assert_difference("HabitRecord.count", 1) do
      post habit_habit_records_path(@habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success

    # 2回目: チェックなし（レコード数が増えないこと）
    assert_no_difference("HabitRecord.count") do
      post habit_habit_records_path(@habit),
           params:  { completed: "0" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success

    # 2回目のリクエストで completed が false に更新されていること
    record = HabitRecord.find_by(
      user:        @user,
      habit:       @habit,
      record_date: HabitRecord.today_for_record
    )
    assert_not record.completed, "2回目のリクエストで completed が false に更新されること"
  end

  # --------------------------------------------------------------------------
  # 【追加テスト②-A】他ユーザーの習慣には create できないこと
  # --------------------------------------------------------------------------
  test "他ユーザーの習慣に POST create しても成功しないこと" do
    assert_no_difference("HabitRecord.count") do
      post habit_habit_records_path(@other_habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    # 404 または リダイレクトになること（200 にならないこと）
    assert_not_equal 200, response.status,
                     "他ユーザーの習慣への create は成功しないこと"
  end

  # --------------------------------------------------------------------------
  # 認証テスト
  # --------------------------------------------------------------------------
  test "未ログイン時は POST create でログインページにリダイレクトされること" do
    delete logout_path

    post habit_habit_records_path(@habit),
         params: { completed: "1" }

    assert_redirected_to login_path
  end

  # ============================================================================
  # update アクションのテスト
  # ============================================================================

  test "PATCH update で completed が true から false に切り替わること" do
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

  test "PATCH update で completed が false から true に切り替わること" do
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
    assert record.reload.completed, "completed が true になること"
  end

  # --------------------------------------------------------------------------
  # 【追加テスト②-B】他ユーザーのレコードは更新できないこと
  # --------------------------------------------------------------------------
  # 【テストの意図】
  #   current_user.habit_records.find(params[:id]) のセキュリティ確認。
  #   他ユーザーのレコード ID を URL に含めてもエラーになることを確認する。
  # --------------------------------------------------------------------------
  test "他ユーザーのレコードを PATCH update しようとすると失敗すること" do
    # 他ユーザーのレコードを作成
    other_record = HabitRecord.create!(
      user:        @other_user,
      habit:       @other_habit,
      record_date: HabitRecord.today_for_record,
      completed:   false
    )

    # 他ユーザーの habit のネストに他ユーザーのレコード ID を指定
    patch habit_habit_record_path(@other_habit, other_record),
          params:  { completed: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    # 成功してはいけない
    assert_not_equal 200, response.status,
                     "他ユーザーのレコードへの操作は成功しないこと"

    # レコードの値が変更されていないこと
    assert_not other_record.reload.completed,
               "他ユーザーのレコードの completed が変更されていないこと"
  end

  # ============================================================================
  # 【追加テスト③】AM 4:00 境界値テスト
  # ============================================================================
  # 【テストの意図】
  #   AM 3:59 のアクセス → 前日の record_date で記録されること
  #   AM 4:01 のアクセス → 当日の record_date で記録されること
  #
  # 【travel_to について】
  #   Rails の ActiveSupport::Testing::TimeHelpers が提供するヘルパー。
  #   テスト内で「現在時刻」を任意の時刻に固定できる。
  #   Timecop gem は不要（Rails 4.1 以降は標準搭載）。
  #   travel_to の引数には Time、DateTime、String などを渡せる。
  # ============================================================================

  test "AM 3:59 のアクセスは前日の日付で記録されること" do
    # travel_to で「今日の AM 3:59」に時刻を固定する
    # Time.current.change で「今日の 3:59:00」を作成
    travel_to Time.current.change(hour: 3, min: 59, sec: 0) do
      assert_difference("HabitRecord.count", 1) do
        post habit_habit_records_path(@habit),
             params:  { completed: "1" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end

      record = HabitRecord.last
      # AM 3:59 は「昨日」扱い → record_date が昨日の日付になること
      assert_equal Date.current - 1.day, record.record_date,
                   "AM 3:59 のアクセスは前日の日付で記録されること"
    end
  end

  test "AM 4:01 のアクセスは当日の日付で記録されること" do
    # travel_to で「今日の AM 4:01」に時刻を固定する
    travel_to Time.current.change(hour: 4, min: 1, sec: 0) do
      assert_difference("HabitRecord.count", 1) do
        post habit_habit_records_path(@habit),
             params:  { completed: "1" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end

      record = HabitRecord.last
      # AM 4:01 は「今日」扱い → record_date が今日の日付になること
      assert_equal Date.current, record.record_date,
                   "AM 4:01 のアクセスは当日の日付で記録されること"
    end
  end

  test "AM 4:00 ちょうどは当日の日付で記録されること" do
    # AM 4:00 ちょうどは「今日」扱い（境界値: boundary と同値）
    # today_for_record のロジック: now < boundary なら前日
    # AM 4:00 ちょうどは now == boundary → < ではないため今日扱い
    travel_to Time.current.change(hour: 4, min: 0, sec: 0) do
      assert_difference("HabitRecord.count", 1) do
        post habit_habit_records_path(@habit),
             params:  { completed: "1" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end

      record = HabitRecord.last
      assert_equal Date.current, record.record_date,
                   "AM 4:00 ちょうどは当日の日付で記録されること"
    end
  end
end