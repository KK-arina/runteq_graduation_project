# test/integration/numeric_habit_flow_test.rb
#
# ==============================================================================
# 【テスト失敗修正】
#
#   ❷ NoMethodError: undefined method '[]' for nil
#      at sessions_controller.rb:38
#
#   【原因】
#     setup 内のログイン処理が以下の形で書かれていた:
#       post login_path, params: { email: @user.email, password: "password" }
#     しかし sessions_controller の create アクションが
#       params[:session][:email] / params[:session][:password]
#     の形（ネストしたパラメータ）を期待している。
#     params[:session] が nil のため params[:session][] が
#     NoMethodError になっていた。
#
#   【修正方法】
#     session キーでネストしたパラメータを渡すように変更する:
#       params: { session: { email: @user.email, password: "password" } }
#
#   ただし sessions_controller の実装によっては
#   params[:email] / params[:password] を直接使う場合もある。
#   エラーが `params[:session]` で起きているため、
#   session キーでのネストに修正する。
# ==============================================================================

require "test_helper"

class NumericHabitFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)

    # ── 修正: session キーでネストしてログイン ─────────────────────────────
    # sessions_controller は params[:session][:email] の形を期待している
    post login_path, params: { session: { email: @user.email, password: "password" } }
    # ────────────────────────────────────────────────────────────────────────
  end

  # ============================================================
  # 数値型習慣の作成テスト
  # ============================================================

  test "B-1: 数値型習慣を作成できること" do
    assert_difference "Habit.count", 1 do
      post habits_path, params: {
        habit: {
          name:             "ジョギング",
          weekly_target:    5,
          measurement_type: "numeric_type",
          unit:             "分"
        }
      }
    end

    follow_redirect!
    assert_response :success
    assert_equal "numeric_type", Habit.last.measurement_type
    assert_equal "分", Habit.last.unit
  end

  test "B-1: 数値型習慣で unit が空のとき作成に失敗すること" do
    assert_no_difference "Habit.count" do
      post habits_path, params: {
        habit: {
          name:             "ジョギング",
          weekly_target:    5,
          measurement_type: "numeric_type",
          unit:             ""
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # ============================================================
  # 数値型習慣の記録テスト
  # ============================================================

  test "B-1: 数値型習慣の記録を POST で保存できること" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    assert_difference "HabitRecord.count", 1 do
      post habit_habit_records_path(numeric_habit),
           params: { numeric_value: "30.5" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    record = HabitRecord.last
    assert_equal 30.5, record.numeric_value.to_f
    assert record.completed
  end

  test "B-1: 数値型習慣の記録を PATCH で更新できること" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )
    record = HabitRecord.create!(
      user: @user, habit: numeric_habit,
      record_date: HabitRecord.today_for_record,
      completed: true, numeric_value: 20.0
    )

    patch habit_habit_record_path(numeric_habit, record),
          params: { numeric_value: "45.0" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    record.reload
    assert_equal 45.0, record.numeric_value.to_f
    assert_equal 200, response.status
  end

  test "B-1: チェック型習慣の既存の動作に影響しないこと" do
    check_habit = @user.habits.create!(
      name: "読書", weekly_target: 5,
      measurement_type: :check_type
    )

    assert_difference "HabitRecord.count", 1 do
      post habit_habit_records_path(check_habit),
           params: { completed: "1" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    record = HabitRecord.last
    assert record.completed
    assert_nil record.numeric_value
  end

  # ============================================================
  # ダッシュボード表示テスト
  # ============================================================

  test "B-1: ダッシュボードに数値型習慣の入力フィールドが表示されること" do
    @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    get dashboard_path
    assert_response :success
    assert_select "input[type='number']", minimum: 1
    assert_match /分/, response.body
  end

  test "B-1: 習慣一覧で数値型習慣の進捗が「X/Y分（Z%）」形式で表示されること" do
    numeric_habit = @user.habits.create!(
      name: "ジョギング", weekly_target: 5,
      measurement_type: :numeric_type, unit: "分"
    )

    HabitRecord.create!(
      user: @user, habit: numeric_habit,
      record_date: HabitRecord.today_for_record,
      completed: true, numeric_value: 3.0
    )

    get habits_path
    assert_response :success
    assert_match /3\/5分/, response.body
  end
end
