# ==============================================================================
# db/seeds/demo_data.rb（#I-3: Part B デモデータ・開発環境専用）
# ==============================================================================
#
# 【このファイルの役割】
#   開発時の見た目確認や講師レビュー用のサンプルデータを投入する。
#   デモユーザー1名・習慣6個（＋論理削除1個）・過去3週分の記録・
#   過去2週分の完了済み振り返り・先週分の未完了振り返り（ロック状態デモ）。
#
# 【⚠️ このファイルは破壊的です】
#   冒頭で User をはじめ全データを削除してから作り直します。
#   そのため本番環境では絶対に実行してはいけません。
#   通常は db/seeds.rb が「development のときだけ」このファイルを読み込むので、
#   本番の実行経路には登場しませんが、万一直接読み込まれても事故が起きないよう、
#   ファイル先頭にも安全装置（開発環境以外なら中断）を置いています。
# ==============================================================================

# ------------------------------------------------------------------------------
# 安全装置: 開発環境以外では実行させない（多重ロック）
# ------------------------------------------------------------------------------
# 【なぜ raise で止めるのか】
#   このファイルは全データを削除する。もし本番やテストで誤って読み込まれた場合、
#   静かに実行されてしまうと取り返しがつかない。raise で即座に処理を止め、
#   「開発専用のファイルが誤った環境で呼ばれた」と明確に知らせる。
unless Rails.env.development?
  raise "db/seeds/demo_data.rb は開発環境（development）専用です。" \
        "現在の環境: #{Rails.env}。本番・テストでは実行できません。"
end

# ==============================================================================
# Step 0: 既存データの削除（子 → 親の順で削除する）
# ==============================================================================
#
# 外部キー制約があるため、参照している側（子）から先に削除する。
# 順序: WeeklyReflectionHabitSummary → HabitRecord → WeeklyReflection → Habit → User

puts "=" * 60
puts "🗑️  既存データを削除しています...（デモ再構築のため / 開発環境のみ）"
puts "=" * 60

WeeklyReflectionHabitSummary.destroy_all
puts "  ✓ WeeklyReflectionHabitSummary を削除しました"

HabitRecord.destroy_all
puts "  ✓ HabitRecord を削除しました"

WeeklyReflection.destroy_all
puts "  ✓ WeeklyReflection を削除しました"

# unscoped: デフォルトスコープ（active 等）を無視して全件対象にする
Habit.unscoped.destroy_all
puts "  ✓ Habit を削除しました"

# delete_all: コールバック（prevent_physical_destroy）を発火させずSQLで直接削除する
# （destroy_all だと before_destroy :prevent_physical_destroy で例外になるため）
User.unscoped.delete_all
puts "  ✓ User を削除しました"

puts ""

# ==============================================================================
# Step 1: 日付の基準を設定する
# ==============================================================================
puts "📅 日付の基準を設定しています..."

fixed_today            = Date.today
this_week_monday       = fixed_today.beginning_of_week(:monday)
last_week_monday       = this_week_monday - 1.week
last_week_sunday       = last_week_monday + 6.days
two_weeks_ago_monday   = this_week_monday - 2.weeks
two_weeks_ago_sunday   = two_weeks_ago_monday + 6.days
three_weeks_ago_monday = this_week_monday - 3.weeks
three_weeks_ago_sunday = three_weeks_ago_monday + 6.days

puts "  今日:               #{fixed_today}"
puts "  今週月曜:           #{this_week_monday}"
puts "  先週 (#{last_week_monday} 〜 #{last_week_sunday})"
puts "  先々週 (#{two_weeks_ago_monday} 〜 #{two_weeks_ago_sunday})"
puts "  3週間前 (#{three_weeks_ago_monday} 〜 #{three_weeks_ago_sunday})"
puts ""

# ==============================================================================
# Step 2: デモユーザーの作成
# ==============================================================================
puts "👤 デモユーザーを作成しています..."

demo_user = User.create!(
  name: "山田 太郎",
  email: "test@example.com",
  password: "password",
  password_confirmation: "password"
)

puts "  ✓ ユーザー作成完了"
puts "    名前:     #{demo_user.name}"
puts "    メール:   #{demo_user.email}"
puts "    パスワード: password"
puts ""

# ==============================================================================
# Step 3: 習慣データの作成（有効な習慣 6個）
# ==============================================================================
puts "📋 習慣データを作成しています..."

habits = [
  demo_user.habits.create!(name: "読書（15分以上）",      weekly_target: 7),
  demo_user.habits.create!(name: "筋トレ",               weekly_target: 5),
  demo_user.habits.create!(name: "瞑想（10分）",          weekly_target: 7),
  demo_user.habits.create!(name: "英語学習（Duolingo）",   weekly_target: 5),
  demo_user.habits.create!(name: "ジョギング（20分以上）", weekly_target: 3),
  demo_user.habits.create!(name: "日記を書く",            weekly_target: 7)
]

habits.each { |h| puts "  ✓ #{h.name}（週#{h.weekly_target}回目標）" }
puts ""

# ==============================================================================
# Step 4: 論理削除済みの習慣を作成する（デモ用）
# ==============================================================================
puts "🗑️  論理削除済み習慣を作成しています..."

deleted_habit = demo_user.habits.create!(
  name: "やめた習慣（論理削除済み・一覧に表示されないはず）",
  weekly_target: 7
)
deleted_habit.soft_delete

puts "  ✓ #{deleted_habit.name}"
puts "    deleted_at: #{deleted_habit.deleted_at}"
puts ""

# ==============================================================================
# Step 5: 習慣記録データの作成（過去3週分 + 今週分）
# ==============================================================================
#
# create_record: 特定の日付に「チェック済み」記録を作るヘルパー。
# find_or_create_by! を使うため複数回実行しても UNIQUE 制約エラーにならない。
create_record = lambda do |habit, date, completed|
  HabitRecord.find_or_create_by!(
    user: demo_user,
    habit: habit,
    record_date: date
  ) do |record|
    record.completed = completed
  end
end

puts "📝 習慣記録データを作成しています..."
puts ""

# ── 3週間前の記録 ─────────────────────────────────────────────
puts "  3週間前（#{three_weeks_ago_monday} 〜 #{three_weeks_ago_sunday}）の記録..."

(0..6).each do |day_offset|
  date        = three_weeks_ago_monday + day_offset.days
  day_of_week = date.wday

  habits.each_with_index do |habit, index|
    completed = case index
    when 0 then day_of_week != 6
    when 1 then day_of_week.between?(1, 5)
    when 2 then true
    when 3 then day_of_week.between?(1, 5) && day_of_week != 3
    when 4 then [ 1, 3, 5 ].include?(day_of_week)
    when 5 then day_of_week.between?(1, 5)
    end
    create_record.call(habit, date, completed)
  end
end
puts "    ✓ 3週間前の記録を作成しました"

# ── 先々週（2週間前）の記録 ──────────────────────────────────
puts "  先々週（#{two_weeks_ago_monday} 〜 #{two_weeks_ago_sunday}）の記録..."

(0..6).each do |day_offset|
  date        = two_weeks_ago_monday + day_offset.days
  day_of_week = date.wday

  habits.each_with_index do |habit, index|
    completed = case index
    when 0 then [ 1, 2, 4, 5 ].include?(day_of_week)
    when 1 then [ 1, 3, 5 ].include?(day_of_week)
    when 2 then day_of_week != 0
    when 3 then [ 1, 2, 4 ].include?(day_of_week)
    when 4 then [ 1, 5 ].include?(day_of_week)
    when 5 then [ 1, 2, 3, 4 ].include?(day_of_week)
    end
    create_record.call(habit, date, completed)
  end
end
puts "    ✓ 先々週の記録を作成しました"

# ── 先週の記録 ────────────────────────────────────────────────
puts "  先週（#{last_week_monday} 〜 #{last_week_sunday}）の記録..."

(0..6).each do |day_offset|
  date        = last_week_monday + day_offset.days
  day_of_week = date.wday

  habits.each_with_index do |habit, index|
    completed = case index
    when 0 then [ 1, 2, 3, 4 ].include?(day_of_week)
    when 1 then [ 1, 2 ].include?(day_of_week)
    when 2 then [ 1, 2, 3, 4, 5 ].include?(day_of_week)
    when 3 then [ 1, 3, 5 ].include?(day_of_week)
    when 4 then day_of_week == 1
    when 5 then [ 1, 2, 3 ].include?(day_of_week)
    end
    create_record.call(habit, date, completed)
  end
end
puts "    ✓ 先週の記録を作成しました"

# ── 今週の記録（月曜〜今日まで）────────────────────────────────
puts "  今週（#{this_week_monday} 〜 今日#{fixed_today}）の記録..."

days_elapsed = (fixed_today - this_week_monday).to_i

(0..days_elapsed).each do |day_offset|
  date        = this_week_monday + day_offset.days
  day_of_week = date.wday

  habits.each_with_index do |habit, index|
    completed = case index
    when 0 then true
    when 1 then day_of_week.between?(1, 5)
    when 2 then true
    when 3 then [ 1, 2, 4 ].include?(day_of_week)
    when 4 then day_of_week == 1
    when 5 then true
    end
    create_record.call(habit, date, completed)
  end
end
puts "    ✓ 今週の記録を作成しました"
puts ""

# ==============================================================================
# Step 6: 週次振り返りデータの作成
# ==============================================================================
#   3週間前: 完了済み / 先々週: 完了済み / 先週: 未完了（ロック状態のデモ）
puts "🔄 週次振り返りデータを作成しています..."
puts ""

# ── 3週間前の振り返り（完了済み）─────────────────────────────
puts "  3週間前の振り返りを作成しています..."

reflection_3w = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: three_weeks_ago_monday,
  week_end_date:   three_weeks_ago_sunday,
  reflection_comment: <<~COMMENT,
    今週は全体的に調子が良く、ほとんどの習慣を達成できました。
    特に瞑想は毎日継続でき、精神的に落ち着いた1週間でした。
    筋トレも週5回の目標を達成。英語学習は水曜日に飲み会があり1回スキップしましたが、
    全体的には満足できる週でした。来週も同じペースを維持したいです。
  COMMENT
  direct_reason:        "習慣を継続できたことで、自信がついてきた。",
  background_situation: "睡眠時間を確保することで、集中力が上がった。",
  next_action:          "来週も同じペースを維持し、英語学習を毎日続ける。"
)

WeeklyReflectionHabitSummary.create_all_for_reflection!(reflection_3w)
puts "    ✓ 3週間前のスナップショットを作成しました"

reflection_3w.complete!
puts "    ✓ 3週間前の振り返りを完了済みにしました（completed_at: #{reflection_3w.completed_at}）"
puts ""

# ── 先々週（2週間前）の振り返り（完了済み）──────────────────
puts "  先々週の振り返りを作成しています..."

reflection_2w = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: two_weeks_ago_monday,
  week_end_date:   two_weeks_ago_sunday,
  direct_reason:        "仕事が忙しく帰宅時間が遅くなったため達成率が下がった。",
  background_situation: "朝の時間を活用すれば習慣を維持できると気づいた。",
  next_action:          "来週は朝活を取り入れて習慣をこなす。",
  reflection_comment: <<~COMMENT
    先週より達成率が下がってしまいました。
    主な原因は仕事が忙しく、帰宅時間が遅くなったことです。
    特に筋トレは週3回しかできませんでした（目標は週5回）。
    ジョギングも2回にとどまりました。
    来週は朝の時間を活用して習慣をこなすように工夫したいと思います。
  COMMENT
)

WeeklyReflectionHabitSummary.create_all_for_reflection!(reflection_2w)
puts "    ✓ 先々週のスナップショットを作成しました"

reflection_2w.complete!
puts "    ✓ 先々週の振り返りを完了済みにしました（completed_at: #{reflection_2w.completed_at}）"
puts ""

# ── 先週の振り返り（未完了状態・ロック状態のデモ）────────────
puts "  先週の振り返りを作成しています（未完了・ロック状態のデモ）..."

reflection_last_week = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: last_week_monday,
  week_end_date:   last_week_sunday,
  direct_reason:        "今週は体調不良で習慣を継続できなかった。",
  background_situation: "体調管理の重要性を再認識した。",
  next_action:          "体調を整えてから習慣を再開する。"
)
WeeklyReflectionHabitSummary.create_all_for_reflection!(reflection_last_week)
puts "    ✓ 先週の振り返りを未完了状態で作成しました"
puts "    ⚠️  月曜 AM4:00 以降にアクセスするとロック警告バナーが表示されます"
puts ""

# ==============================================================================
# Step 7: 作成結果の確認サマリー
# ==============================================================================
puts "=" * 60
puts "✅ デモデータ投入完了！（開発環境）"
puts "=" * 60
puts ""
puts "📊 作成されたデータのサマリー:"
puts ""
puts "  👤 ユーザー数:          #{User.count} 名"
puts "  📋 有効な習慣数:        #{Habit.active.count} 個"
puts "  🗑️  論理削除済み習慣数: #{Habit.deleted.count} 個"
puts "  ✅ 習慣記録数:          #{HabitRecord.count} 件"
puts "  🔄 週次振り返り数:      #{WeeklyReflection.count} 件"
puts "     うち完了済み:        #{WeeklyReflection.completed.count} 件"
puts "     うち未完了:          #{WeeklyReflection.pending.count} 件"
puts "  📸 スナップショット数:  #{WeeklyReflectionHabitSummary.count} 件"
puts ""
puts "=" * 60
puts "🔑 ログイン情報:"
puts "=" * 60
puts "  メールアドレス: test@example.com"
puts "  パスワード:     password"
puts "=" * 60
puts ""
