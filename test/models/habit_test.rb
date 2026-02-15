require "test_helper"

# Habitモデルのテスト
class HabitTest < ActiveSupport::TestCase
  # setup: 各テスト実行前に毎回実行されるメソッド
  setup do
    # テスト用ユーザーを作成
    # users(:one): test/fixtures/users.yml で定義されたテストデータ
    @user = users(:one)
    
    # 有効な習慣データを作成（テストの基準となるデータ）
    # @user.habits.build: user_id が自動的に設定される
    @habit = @user.habits.build(
      name: "読書",
      weekly_target: 7
    )
  end

  # ===== バリデーションテスト =====
  
  test "有効な習慣データであること" do
    # assert: 条件が真であることを確認
    # @habit.valid?: バリデーションをチェック（true = 有効、false = 無効）
    assert @habit.valid?
  end

  test "習慣名が空欄の場合は無効であること" do
    @habit.name = ""
    # assert_not: 条件が偽であることを確認
    assert_not @habit.valid?
    # assert_includes: 配列に特定の要素が含まれていることを確認
    # @habit.errors[:name]: name 属性のエラーメッセージの配列
    assert_includes @habit.errors[:name], "can't be blank"
  end

  test "習慣名がnilの場合は無効であること" do
    @habit.name = nil
    assert_not @habit.valid?
    assert_includes @habit.errors[:name], "can't be blank"
  end

  test "習慣名が51文字の場合は無効であること" do
    # "a" * 51: "a" を51個連結した文字列（51文字）
    @habit.name = "a" * 51
    assert_not @habit.valid?
    # エラーメッセージ: "is too long (maximum is 50 characters)"
    assert_includes @habit.errors[:name], "is too long (maximum is 50 characters)"
  end

  test "習慣名が50文字の場合は有効であること" do
    @habit.name = "a" * 50
    # 50文字ちょうどは有効（上限値テスト）
    assert @habit.valid?
  end

  test "週次目標値が空欄の場合は無効であること" do
    @habit.weekly_target = nil
    assert_not @habit.valid?
    assert_includes @habit.errors[:weekly_target], "can't be blank"
  end

  test "週次目標値が0の場合は無効であること" do
    @habit.weekly_target = 0
    assert_not @habit.valid?
    # 🔴 重要: エラーメッセージをバリデーションルールに合わせる
    # 
    # バリデーション:
    #   validates :weekly_target, numericality: { greater_than_or_equal_to: 1 }
    # 
    # エラーメッセージ:
    #   "must be greater than or equal to 1"
    # 
    # 修正前（NG）: "must be greater than 0"
    # 修正後（OK）: "must be greater than or equal to 1"
    assert_includes @habit.errors[:weekly_target], "must be greater than or equal to 1"
  end

  test "週次目標値が負の数の場合は無効であること" do
    @habit.weekly_target = -1
    assert_not @habit.valid?
    # 🔴 重要: エラーメッセージを統一
    assert_includes @habit.errors[:weekly_target], "must be greater than or equal to 1"
  end

  test "週次目標値が8の場合は無効であること" do
    @habit.weekly_target = 8
    assert_not @habit.valid?
    # エラーメッセージ: "must be less than or equal to 7"
    assert_includes @habit.errors[:weekly_target], "must be less than or equal to 7"
  end

  test "週次目標値が1の場合は有効であること" do
    @habit.weekly_target = 1
    # 下限値テスト
    assert @habit.valid?
  end

  test "週次目標値が7の場合は有効であること" do
    @habit.weekly_target = 7
    # 上限値テスト
    assert @habit.valid?
  end

  test "週次目標値が小数の場合は無効であること" do
    @habit.weekly_target = 3.5
    assert_not @habit.valid?
    # エラーメッセージ: "must be an integer"
    assert_includes @habit.errors[:weekly_target], "must be an integer"
  end

  # ===== アソシエーションテスト =====
  
  test "ユーザーに紐づいていること" do
    # @habit.user: belongs_to :user で定義されたアソシエーション
    # @user: setup で作成したユーザー
    assert_equal @user, @habit.user
  end

  test "ユーザーが削除されたら習慣も削除されること" do
    # 🔴 正しい修正: fixtures の影響を考慮する
    # 
    # 修正前の誤診:
    #   「他のテストの影響」→ これは間違い（各テストはロールバックされる）
    # 
    # 本当の原因:
    #   fixtures/habits.yml に users(:one) に紐づく習慣が複数ある
    #   例: one, two, three が全て user: one だった場合
    #   → users(:one).destroy で3件削除される
    # 
    # 正しい修正方法①: relation ベースで assert_difference
    test_user = users(:one)
    habit_count = test_user.habits.count  # fixtures で定義された習慣の数を取得
    
    # テスト用の習慣を1件追加
    test_user.habits.create!(name: "テスト習慣", weekly_target: 7)
    
    # ユーザーに紐づく習慣の総数を取得（fixtures + 追加した1件）
    total_count = test_user.habits.count
    
    # assert_difference: 全体の Habit.count が total_count 減ることを期待
    assert_difference("Habit.count", -total_count) do
      test_user.destroy
    end
  end

  # ===== スコープテスト =====
  
  test "activeスコープで有効な習慣のみ取得できること" do
    # 有効な習慣を作成
    active_habit = @user.habits.create!(name: "有効な習慣", weekly_target: 7)
    
    # 削除済みの習慣を作成
    deleted_habit = @user.habits.create!(name: "削除済み習慣", weekly_target: 7)
    # soft_delete: deleted_at に現在時刻を設定（論理削除）
    deleted_habit.soft_delete
    
    # Habit.active: deleted_at が NULL の習慣のみ取得
    active_habits = Habit.active
    
    # assert_includes: 配列に特定の要素が含まれていることを確認
    assert_includes active_habits, active_habit
    # assert_not_includes: 配列に特定の要素が含まれていないことを確認
    assert_not_includes active_habits, deleted_habit
  end

  test "deletedスコープで削除済み習慣のみ取得できること" do
    # 有効な習慣を作成
    active_habit = @user.habits.create!(name: "有効な習慣", weekly_target: 7)
    
    # 削除済みの習慣を作成
    deleted_habit = @user.habits.create!(name: "削除済み習慣", weekly_target: 7)
    deleted_habit.soft_delete
    
    # Habit.deleted: deleted_at が NOT NULL の習慣のみ取得
    deleted_habits = Habit.deleted
    
    assert_includes deleted_habits, deleted_habit
    assert_not_includes deleted_habits, active_habit
  end

  # ===== インスタンスメソッドテスト =====
  
  test "soft_deleteメソッドで論理削除されること" do
    @habit.save!
    
    # assert_nil: 値が nil であることを確認
    # @habit.deleted_at: 初期状態では nil（削除されていない）
    assert_nil @habit.deleted_at
    
    # soft_delete: 論理削除を実行
    @habit.soft_delete
    
    # assert_not_nil: 値が nil でないことを確認
    # 論理削除後は deleted_at に現在時刻が設定される
    assert_not_nil @habit.deleted_at
  end

  test "active?メソッドで有効状態を判定できること" do
    @habit.save!
    
    # 初期状態: 有効
    assert @habit.active?
    
    # 論理削除後: 無効
    @habit.soft_delete
    assert_not @habit.active?
  end

  test "deleted?メソッドで削除状態を判定できること" do
    @habit.save!
    
    # 初期状態: 削除されていない
    assert_not @habit.deleted?
    
    # 論理削除後: 削除済み
    @habit.soft_delete
    assert @habit.deleted?
  end

  # ===== 論理削除の統合テスト =====
  
  test "論理削除後もデータベースにレコードが残ること" do
    @habit.save!
    habit_id = @habit.id
    
    # 論理削除を実行
    @habit.soft_delete
    
    # find_by: 指定した条件でレコードを検索
    # Habit.find_by(id: habit_id): ID で習慣を検索
    # assert_not_nil: レコードが存在することを確認（物理削除されていない）
    assert_not_nil Habit.find_by(id: habit_id)
  end

  test "論理削除後はactiveスコープで取得できないこと" do
    @habit.save!
    
    # 論理削除前: active スコープで取得できる
    assert_includes Habit.active, @habit
    
    # 論理削除を実行
    @habit.soft_delete
    
    # 論理削除後: active スコープで取得できない
    assert_not_includes Habit.active, @habit
  end

  test "論理削除後はdeletedスコープで取得できること" do
    @habit.save!
    
    # 論理削除前: deleted スコープで取得できない
    assert_not_includes Habit.deleted, @habit
    
    # 論理削除を実行
    @habit.soft_delete
    
    # 論理削除後: deleted スコープで取得できる
    assert_includes Habit.deleted, @habit
  end
end
