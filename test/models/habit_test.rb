require "test_helper"

class HabitTest < ActiveSupport::TestCase
  # ===================================================================
  # セットアップ（各テスト実行前に毎回実行される）
  # ===================================================================
  
  def setup
    # テスト用ユーザーを作成
    # fixtures（test/fixtures/users.yml）で定義されたユーザーを取得
    @user = users(:one)
    
    # テスト用の有効な習慣を作成
    @habit = Habit.new(
      user: @user,
      name: "読書",
      weekly_target: 7
    )
  end

  # ===================================================================
  # バリデーションテスト（正常系）
  # ===================================================================
  
  test "有効な習慣は保存できること" do
    # assert → 条件がtrueであることを確認
    # @habit.valid? → バリデーションが通ればtrue
    assert @habit.valid?, "有効な習慣が保存できませんでした"
  end

  # ===================================================================
  # バリデーションテスト（異常系：name）
  # ===================================================================
  
  test "習慣名が空の場合は無効であること" do
    @habit.name = ""
    # assert_not → 条件がfalseであることを確認
    assert_not @habit.valid?, "空の習慣名で保存できてしまいました"
    # errors[:name] → nameフィールドのエラーメッセージ配列
    # include? → 配列に指定の要素が含まれているか確認
    assert_includes @habit.errors[:name], "can't be blank"
  end
  
  test "習慣名がnilの場合は無効であること" do
    @habit.name = nil
    assert_not @habit.valid?
    assert_includes @habit.errors[:name], "can't be blank"
  end
  
  test "習慣名が51文字の場合は無効であること" do
    # "a" * 51 → "a"を51回繰り返した文字列
    @habit.name = "a" * 51
    assert_not @habit.valid?
    assert_includes @habit.errors[:name], "is too long (maximum is 50 characters)"
  end
  
  test "習慣名が50文字の場合は有効であること" do
    @habit.name = "a" * 50
    assert @habit.valid?, "50文字の習慣名が無効になってしまいました"
  end

  # ===================================================================
  # バリデーションテスト（異常系：weekly_target）
  # ===================================================================
  
  test "週次目標値が空の場合は無効であること" do
    @habit.weekly_target = nil
    assert_not @habit.valid?
    assert_includes @habit.errors[:weekly_target], "can't be blank"
  end
  
  test "週次目標値が0の場合は無効であること" do
    @habit.weekly_target = 0
    assert_not @habit.valid?
    assert_includes @habit.errors[:weekly_target], "must be greater than 0"
  end
  
  test "週次目標値が負の数の場合は無効であること" do
    @habit.weekly_target = -1
    assert_not @habit.valid?
    assert_includes @habit.errors[:weekly_target], "must be greater than 0"
  end
  
  test "週次目標値が8の場合は無効であること" do
    @habit.weekly_target = 8
    assert_not @habit.valid?
    assert_includes @habit.errors[:weekly_target], "must be less than or equal to 7"
  end
  
  test "週次目標値が小数の場合は無効であること" do
    @habit.weekly_target = 3.5
    assert_not @habit.valid?
    assert_includes @habit.errors[:weekly_target], "must be an integer"
  end
  
  test "週次目標値が1の場合は有効であること" do
    @habit.weekly_target = 1
    assert @habit.valid?, "週次目標値1が無効になってしまいました"
  end
  
  test "週次目標値が7の場合は有効であること" do
    @habit.weekly_target = 7
    assert @habit.valid?, "週次目標値7が無効になってしまいました"
  end

  # ===================================================================
  # アソシエーションテスト
  # ===================================================================
  
  test "ユーザーとの関連付けが正しく動作すること" do
    # @habit.user → 関連するUserオブジェクトを取得
    assert_equal @user, @habit.user, "ユーザーとの関連付けが正しくありません"
  end
  
  test "ユーザーが削除されたら習慣も削除されること" do
    # テスト用に新しいユーザーと習慣を作成
    # fixtureのユーザーを使うと、既存の習慣（2件）も削除されて期待値がずれるため
    test_user = User.create!(
      name: "テストユーザー",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    test_habit = test_user.habits.create!(name: "テスト習慣", weekly_target: 5)
    
    # assert_difference → ブロック実行前後で指定の値がどれだけ変化したか確認
    # 'Habit.count', -1 → Habit.countが1減ることを期待
    # dependent: :destroy が正しく動作しているかを確認
    assert_difference 'Habit.count', -1 do
      test_user.destroy
    end
  end

  # ===================================================================
  # スコープテスト
  # ===================================================================
  
  test "activeスコープは有効な習慣のみを取得すること" do
    # 有効な習慣を保存
    active_habit = Habit.create!(user: @user, name: "筋トレ", weekly_target: 5)
    
    # 論理削除された習慣を作成
    deleted_habit = Habit.create!(user: @user, name: "ジョギング", weekly_target: 3)
    deleted_habit.soft_delete
    
    # Habit.active → 有効な習慣のみ取得
    active_habits = Habit.active
    
    # include? → 配列に指定の要素が含まれているか確認
    assert_includes active_habits, active_habit, "有効な習慣が含まれていません"
    assert_not_includes active_habits, deleted_habit, "削除済み習慣が含まれています"
  end
  
  test "deletedスコープは削除済みの習慣のみを取得すること" do
    active_habit = Habit.create!(user: @user, name: "筋トレ", weekly_target: 5)
    deleted_habit = Habit.create!(user: @user, name: "ジョギング", weekly_target: 3)
    deleted_habit.soft_delete
    
    deleted_habits = Habit.deleted
    
    assert_includes deleted_habits, deleted_habit
    assert_not_includes deleted_habits, active_habit
  end

  # ===================================================================
  # インスタンスメソッドテスト
  # ===================================================================
  
  test "soft_deleteメソッドでdeleted_atが設定されること" do
    @habit.save
    
    # assert_nil → 値がnilであることを確認
    assert_nil @habit.deleted_at, "保存直後のdeleted_atがnilではありません"
    
    @habit.soft_delete
    
    # assert_not_nil → 値がnil以外であることを確認
    assert_not_nil @habit.deleted_at, "soft_delete後もdeleted_atがnilのままです"
  end
  
  test "active?メソッドが正しく動作すること" do
    @habit.save
    
    # 保存直後は有効
    assert @habit.active?, "保存直後にactive?がfalseになっています"
    
    @habit.soft_delete
    
    # 論理削除後は無効
    assert_not @habit.active?, "soft_delete後もactive?がtrueのままです"
  end
  
  test "deleted?メソッドが正しく動作すること" do
    @habit.save
    
    # 保存直後は削除されていない
    assert_not @habit.deleted?, "保存直後にdeleted?がtrueになっています"
    
    @habit.soft_delete
    
    # 論理削除後は削除済み
    assert @habit.deleted?, "soft_delete後もdeleted?がfalseのままです"
  end
  
  # ===================================================================
  # 論理削除の統合テスト
  # ===================================================================
  
  test "soft_deleteを呼ぶと、Habit.activeからは取得できなくなること" do
    @habit.save
    
    # 論理削除前は active スコープで取得できる
    assert_includes Habit.active, @habit, "保存直後の習慣がactiveに含まれていません"
    
    # assert_difference → ブロック実行前後で指定の値がどれだけ変化したか確認
    # 'Habit.active.count', -1 → active な習慣が1つ減ることを期待
    assert_difference 'Habit.active.count', -1 do
      @habit.soft_delete
    end
    
    # 論理削除後は active スコープで取得できない
    assert_not_includes Habit.active, @habit, "論理削除後もactiveに含まれています"
    
    # 論理削除後は deleted スコープで取得できる
    assert_includes Habit.deleted, @habit, "論理削除後にdeletedに含まれていません"
  end
end
