# test/integration/pdca_lock_test.rb
#
# PDCA強制ロック機能の統合テストです。
#
# 【重要】月曜AM4:00以降という時間条件があるため、
# travel_to を使って「月曜AM4:00以降」の時刻に固定してテストします。
# travel_to を使わないと、テストを実行する曜日・時間によって
# テスト結果が変わってしまう「不安定なテスト」になります。
#
# 【Issue #25 での変更点】
# create_last_week_reflection の引数を変更した:
#
#   変更前: is_locked: true/false
#     → WeeklyReflection の is_locked カラム（boolean）を直接指定していた
#
#   変更後: completed: true/false
#     → completed: true  のとき completed_at に現在時刻を設定する（完了済み）
#     → completed: false のとき completed_at を nil にする（未完了 = ロック対象）
#
# 【なぜ変更が必要なのか？】
# application_controller.rb の locked? メソッドは
# last_week_reflection.pending? を呼んでロック判定する。
# pending? は「completed_at が nil かどうか」を見る。
# is_locked カラムは locked? の判定に使われていないため、
# is_locked: true を渡しても locked? は「ロック中（true）」を返してしまう。
#
# completed_at を使って「完了済み」を表現することで、
# pending? → locked? が正しく連動するようになる。

require "test_helper"

class PdcaLockTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストの前に実行される共通処理
  # ============================================================
  setup do
    @user  = users(:one)
    @habit = habits(:habit_one)

    # 重複レコードによるUNIQUE制約エラーを防ぐため、事前にクリア
    HabitRecord.where(user: @user).delete_all

    # ----------------------------------------------------------
    # 時刻を「月曜 AM4:01」に固定する
    # ----------------------------------------------------------
    # travel_to は Rails のテストヘルパーで、テスト中の「現在時刻」を
    # 指定した時刻に固定できます。
    # ロック機能は「月曜AM4:00以降」を条件にしているため、
    # この時刻に固定することで、どの曜日・時間にテストを実行しても
    # 同じ結果になります（テストの再現性を保証します）。
    next_monday = Date.current.beginning_of_week(:monday)
    travel_to next_monday.in_time_zone.change(hour: 4, min: 1) + 1.week
  end

  # setup の travel_to をリセットする
  teardown do
    travel_back
  end

  # ============================================================
  # ヘルパー: 前週の振り返りレコードを作成
  # ============================================================
  def login
    log_in_as(@user)
  end

  # create_last_week_reflection(completed: true/false)
  #   → 前週の振り返りレコードを作成するヘルパーメソッド
  #
  # 【引数の意味】
  #   completed: true  → 完了済み（completed_at に現在時刻を設定）
  #                       locked? が false になる → ロック解除状態
  #   completed: false → 未完了（completed_at は nil のまま）
  #                       locked? が true になる  → ロック中状態
  #
  # 【なぜ is_locked から completed に変えたのか？】
  # application_controller.rb の locked? は pending? を呼ぶ。
  # pending? は completed_at が nil かどうかを見る。
  # is_locked カラムは locked? の判定に使われていないため、
  # completed_at を使って「完了済み」を表現する必要がある。
  def create_last_week_reflection(completed:)
    last_week_start = Date.current.beginning_of_week(:monday) - 1.week

    WeeklyReflection.create!(
      user:               @user,
      week_start_date:    last_week_start,
      week_end_date:      last_week_start + 6.days,
      reflection_comment: "テスト用振り返り",
      # completed: true のとき completed_at に現在時刻を入れる（完了済み）
      # completed: false のとき nil のまま（未完了 = pending? が true = ロック対象）
      completed_at:       completed ? Time.current : nil
    )
  end

  # ============================================================
  # テスト1: ダッシュボードの警告バナー表示
  # ============================================================

  test "前週未完了かつ月曜AM4:00以降→ダッシュボードに警告バナーが表示される" do
    # completed: false → completed_at が nil → pending? = true → locked? = true
    create_last_week_reflection(completed: false)
    login

    get dashboard_path
    assert_response :success
    assert_select "p", text: /先週の振り返りが未完了のため、一部の操作が制限されています/
  end

  test "前週完了済み→ダッシュボードに警告バナーは表示されない" do
    # completed: true → completed_at に時刻あり → pending? = false → locked? = false
    create_last_week_reflection(completed: true)
    login

    get dashboard_path
    assert_response :success
    assert_select "p",
      text: /先週の振り返りが未完了のため、一部の操作が制限されています/,
      count: 0
  end

  test "前週の振り返りが存在しない（初週）→ダッシュボードに警告バナーは表示されない" do
    login

    get dashboard_path
    assert_response :success
    assert_select "p",
      text: /先週の振り返りが未完了のため、一部の操作が制限されています/,
      count: 0
  end

  # ============================================================
  # テスト2: 月曜AM4:00「前」はロックしないことの確認
  # ============================================================

  test "月曜AM3:59（AM4:00前）は前週未完了でもロックされない" do
    create_last_week_reflection(completed: false)
    login

    # travel_to で月曜 AM3:59 に上書きします（setup の AM4:01 を一時的に変更）
    this_monday = Date.current.beginning_of_week(:monday)
    travel_to this_monday.in_time_zone.change(hour: 3, min: 59)

    get dashboard_path
    assert_response :success
    assert_select "p",
      text: /先週の振り返りが未完了のため、一部の操作が制限されています/,
      count: 0

    travel_back
  end

  # ============================================================
  # テスト3: ロック中は習慣の新規作成ができない
  # ============================================================

  test "ロック中は習慣を新規作成できない" do
    create_last_week_reflection(completed: false)
    login

    assert_no_difference("Habit.count") do
      post habits_path, params: { habit: { name: "ロック中の習慣", weekly_target: 7 } }
    end

    assert_response :redirect
    follow_redirect!
    assert_select "div", text: /先週の振り返りが未完了のため、この操作はできません/
  end

  test "ロック解除中は習慣を新規作成できる" do
    create_last_week_reflection(completed: true)
    login

    assert_difference("Habit.count", 1) do
      post habits_path, params: { habit: { name: "新しい習慣", weekly_target: 7 } }
    end

    assert_redirected_to habits_path
  end

  # ============================================================
  # テスト4: ロック中は習慣の削除ができない
  # ============================================================

  test "ロック中は習慣を削除できない" do
    create_last_week_reflection(completed: false)
    login

    assert_no_difference("Habit.active.count") do
      delete habit_path(@habit)
    end

    assert_response :redirect
    follow_redirect!
    assert_select "div", text: /先週の振り返りが未完了のため、この操作はできません/
  end

  test "ロック解除中は習慣を削除できる" do
    create_last_week_reflection(completed: true)
    login

    assert_difference("Habit.active.count", -1) do
      delete habit_path(@habit)
    end

    assert_redirected_to habits_path
  end

  # ============================================================
  # テスト5: ロック中でも即時保存はできる
  # ============================================================

  test "ロック中でも習慣の日次記録（即時保存）はできる" do
    create_last_week_reflection(completed: false)
    login

    assert_difference("HabitRecord.count", 1) do
      post habit_habit_records_path(@habit),
           params:  { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    record = HabitRecord.last
    assert_equal HabitRecord.today_for_record, record.record_date
    assert record.completed
  end
end
