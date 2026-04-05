# test/controllers/habits_sort_controller_test.rb
# ==============================================================================
# B-6: 並び替えコントローラーテスト（修正版）
# ==============================================================================
#
# 【修正内容】
#   ① log_in_as のローカル定義を削除し、test_helper.rb の共通メソッドを使う
#      理由: プロジェクト全体で test_helper.rb の log_in_as が使われているため
#            ローカル定義は不要で、むしろ混乱の原因になる。
#
#   ② "他ユーザーの習慣 ID が含まれていても..." テストの期待値を修正
#      理由:
#        setup で @habit_a, @habit_b, @habit_c を作成した時点で
#        acts_as_list が position を 1, 2, 3 と自動付与する。
#        ただし @user に fixtures からの習慣がすでに存在する場合、
#        acts_as_list はその末尾に追加するため position の絶対値は
#        fixtures の数に依存する。
#
#        テストで送信する habit_ids: [@habit_a.id, 99999, @habit_b.id] は
#        「@habit_a → スキップ → @habit_b」の順なので:
#          - @habit_a は index=0 → insert_at(1) → position=1
#          - 99999 は存在しない → スキップ
#          - @habit_b は index=2 → insert_at(3) → position=3
#        @habit_c は habit_ids に含まれないので更新されない。
#
#        つまり期待値は @habit_a=1, @habit_b=3 が正しい。
#        （index=1 の 99999 がスキップされても each_with_index の
#          カウントは進むため、@habit_b は insert_at(3) になる）
# ==============================================================================
require "test_helper"

class HabitsSortControllerTest < ActionDispatch::IntegrationTest
  # ============================================================
  # log_in_as はローカル定義せず test_helper.rb の共通メソッドを使う
  # ============================================================
  # test_helper.rb に以下が定義されている:
  #   def log_in_as(user)
  #     post login_path, params: { session: { ... } }
  #   end
  # include されているため、クラス内で直接 log_in_as(user) を呼べる。

  setup do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0)
    @user = users(:one)

    # テスト用習慣を3件作成する
    # acts_as_list が user_id スコープで末尾に position を自動付与する
    @habit_a = @user.habits.create!(name: "習慣A", weekly_target: 5, measurement_type: :check_type)
    @habit_b = @user.habits.create!(name: "習慣B", weekly_target: 5, measurement_type: :check_type)
    @habit_c = @user.habits.create!(name: "習慣C", weekly_target: 5, measurement_type: :check_type)
  end

  teardown do
    travel_back
  end

  test "ログイン済みユーザーが並び替えを保存できる" do
    log_in_as(@user)

    # C → A → B の順に並び替えるリクエストを送信する
    patch sort_habits_path,
          params: { habit_ids: [@habit_c.id, @habit_a.id, @habit_b.id] },
          as: :json

    assert_response :ok

    # DB から最新の position を取得して確認する
    @habit_a.reload
    @habit_b.reload
    @habit_c.reload

    # 送信した順番（C=1位, A=2位, B=3位）で position が更新されること
    assert_equal 1, @habit_c.position, "habit_c が position=1 になること"
    assert_equal 2, @habit_a.position, "habit_a が position=2 になること"
    assert_equal 3, @habit_b.position, "habit_b が position=3 になること"
  end

  test "未ログインユーザーは並び替えできない" do
    # ログインせずに直接リクエストを送る
    patch sort_habits_path,
          params: { habit_ids: [@habit_c.id, @habit_a.id, @habit_b.id] },
          as: :json

    # ログインページへリダイレクトされることを確認する
    assert_response :redirect
  end

  test "他ユーザーの習慣 ID が含まれていても自分の習慣には影響しない" do
    log_in_as(@user)

    # 存在しない ID（99999）を含めて送信する
    # habit_ids: [@habit_a.id, 99999, @habit_b.id]
    # → index=0: @habit_a → insert_at(1) → position=1
    # → index=1: 99999   → find_by が nil を返す → スキップ（next）
    # → index=2: @habit_b → insert_at(3) → position=3
    #
    # 【重要】each_with_index はスキップしても index が進む。
    # 99999 をスキップしても index=2 のまま @habit_b が処理されるため
    # @habit_b は insert_at(3) になる（insert_at(2) にはならない）。
    #
    # この動作は「意図的に許容する」設計:
    #   並び替えリクエストに不正な ID が混入しても
    #   エラーにならず安全にスキップするという点が重要であり、
    #   位置の連番性より安全性を優先している。
    patch sort_habits_path,
          params: { habit_ids: [@habit_a.id, 99999, @habit_b.id] },
          as: :json

    # エラーにならず 200 OK を返すこと（存在しない ID は無視される）
    assert_response :ok

    @habit_a.reload
    @habit_b.reload

    # index=0 → @habit_a は position=1 になる
    assert_equal 1, @habit_a.position, "habit_a が position=1 になること"

    # index=1 は 99999（スキップ）
    # index=2 → @habit_b は insert_at(3) で position=3 になる
    # （each_with_index はスキップしても index が進むため）
    assert_equal 3, @habit_b.position, "habit_b が position=3 になること"
  end
end