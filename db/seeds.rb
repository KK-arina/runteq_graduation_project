# db/seeds.rb
# データベースの初期データを作成するファイル
# 開発環境でのテストや動作確認に使用します

# 既存のデータを削除してクリーンな状態にする
# 開発環境でのみ実行することを想定
puts "Cleaning database..."

# ⚠️ HabitRecordモデルはIssue #14で作成予定のため、現時点ではコメントアウト
# HabitRecord.destroy_all

# 習慣を先に削除（外部キー制約を考慮）
Habit.destroy_all
# ユーザーを削除
User.destroy_all

# サンプルユーザーの作成
puts "Creating sample user..."
user = User.create!(
  name: "山田太郎",
  email: "test@example.com",
  password: "password123",
  password_confirmation: "password123"
)
puts "Created user: #{user.email}"

# サンプル習慣の作成
puts "Creating sample habits..."

# 習慣1: 読書
habit1 = user.habits.create!(
  name: "読書（15分以上）",
  weekly_target: 7  # 週7回実施が目標
)
puts "Created habit: #{habit1.name}"

# 習慣2: 筋トレ
habit2 = user.habits.create!(
  name: "筋トレ",
  weekly_target: 5  # 週5回実施が目標
)
puts "Created habit: #{habit2.name}"

# 習慣3: 瞑想
habit3 = user.habits.create!(
  name: "瞑想（10分）",
  weekly_target: 7
)
puts "Created habit: #{habit3.name}"

# 習慣4: 英語学習
habit4 = user.habits.create!(
  name: "英語学習",
  weekly_target: 5
)
puts "Created habit: #{habit4.name}"

# 習慣5: ジョギング
habit5 = user.habits.create!(
  name: "ジョギング",
  weekly_target: 3  # 週3回実施が目標
)
puts "Created habit: #{habit5.name}"

# 論理削除された習慣（テスト用）
# 一覧ページに表示されないことを確認するため
deleted_habit = user.habits.create!(
  name: "削除された習慣（表示されないはず）",
  weekly_target: 7
)
# 論理削除を実行（deleted_atに現在時刻を設定）
deleted_habit.soft_delete
puts "Created and soft-deleted habit: #{deleted_habit.name}"

puts ""
puts "=" * 50
puts "Seeds completed successfully! 🎉"
puts "=" * 50
puts "Login credentials:"
puts "  Email: test@example.com"
puts "  Password: password123"
puts "=" * 50
