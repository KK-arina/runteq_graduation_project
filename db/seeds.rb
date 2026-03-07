# ==============================================================================
# db/seeds.rb
# ==============================================================================
#
# 【このファイルの役割】
# デモ用のサンプルデータをデータベースに投入するファイルです。
# 以下のコマンドで実行します:
#
#   開発環境（Docker）:
#     docker compose exec web bin/rails db:seed
#
#   本番環境（Render の Shell から、意図的に許可する場合のみ）:
#     SEED_IN_PRODUCTION=true bin/rails db:seed
#
# 【注意】
# 本番環境での実行は「講師レビュー用デモデータ投入」の用途を想定しています。
# 本番に実際のユーザーが存在する状態で実行すると全データが削除されるため、
# 十分に注意してください。
#
# 【冪等性（べきとうせい）について】
# 冪等性とは「何度実行しても同じ結果になる」性質のことです。
# このファイルでは最初に既存データを全削除してから再作成するため、
# db:seed を複数回実行してもデータが重複しません。
#
# 【作成されるデータの概要】
# - デモユーザー: 1名
# - 習慣: 6個（有効）+ 1個（論理削除済み）
# - 習慣記録: 過去3週分（week1〜week3）のチェック記録
# - 週次振り返り: 過去2週分（完了済み）
#   ※ 今週分の振り返りは作成しない（ロック状態をデモするため）
# ==============================================================================

# ==============================================================================
# 本番環境誤実行防止ガード（環境変数フラグ方式）
# ==============================================================================
#
# 【変更前の設計（無条件 abort 方式）】
# 以前は本番環境で無条件に abort していたため、
# 講師レビュー用のデモデータを本番 DB に投入できなかった。
#
# 【変更後の設計（環境変数フラグ方式）】
# 環境変数 SEED_IN_PRODUCTION=true を明示的に設定した場合のみ
# 本番環境での実行を許可する。
#
# 【なぜ環境変数フラグ方式が安全なのか】
# - フラグを設定しない限り、本番では絶対に実行されない（二重ロック）
# - フラグを設定するには Render Shell を開いて意図的に入力する操作が必要
# - 「うっかり bin/rails db:seed を実行してしまう」事故を確実に防げる
#
# 【本番で実行する場合の手順】
# Render ダッシュボード → habitflow-web → Shell タブ → 以下を入力:
#   SEED_IN_PRODUCTION=true bin/rails db:seed
#
# 【Rails.env.production? とは】
# 環境変数 RAILS_ENV が "production" のとき true を返す Rails のメソッド。
# Render には RAILS_ENV=production が設定されているため、本番環境では true になる。
#
# 【ENV["SEED_IN_PRODUCTION"].blank? とは】
# 環境変数 "SEED_IN_PRODUCTION" が設定されていない（nil）か
# 空文字のとき true を返す Rails のメソッド。
# コマンドで SEED_IN_PRODUCTION=true を指定しない限り blank? は true になる。
if Rails.env.production? && ENV["SEED_IN_PRODUCTION"].blank?
  abort(<<~MSG)
    🚫 本番環境では通常 db:seed を実行できません。

    【本番でデモデータを投入する場合の手順】
    Render の Shell から以下のコマンドを実行してください:

      SEED_IN_PRODUCTION=true bin/rails db:seed

    ⚠️  実行すると本番 DB の全データが削除されます。
    ⚠️  本物のユーザーデータが存在する場合は実行しないでください。
  MSG
end

# ==============================================================================
# 本番環境実行時の最終警告表示
# ==============================================================================
#
# 本番環境でフラグを立てて実行した場合、処理開始前に警告を3秒間表示する。
# sleep 3 により「意図せず本番で実行してしまった」場合に Ctrl+C で中断できる。
if Rails.env.production?
  puts "=" * 60
  puts "⚠️  【警告】本番環境で db:seed を実行しています！"
  puts "⚠️  本番 DB の全データが削除されます。"
  puts "⚠️  意図しない場合は Ctrl+C で中断してください。"
  puts "=" * 60
  puts "3秒後に処理を開始します..."
  # sleep: 指定した秒数だけ処理を一時停止するメソッド
  # 3秒の猶予を与えることで、誤実行に気づいて中断できる
  sleep 3
  puts ""
end

# ==============================================================================
# Step 0: 既存データの削除（クリーンな状態にする）
# ==============================================================================
#
# 【削除順序がなぜ重要なのか】
# データベースには「外部キー制約」があります。
# 例えば habit_records テーブルは habits テーブルを参照しているため、
# habits を先に削除しようとすると「参照先がない」エラーになります。
#
# そのため、参照している側（子）→ 参照される側（親）の順に削除します。
#
# 削除順序（子から親へ）:
# 1. WeeklyReflectionHabitSummary（weekly_reflections と habits を参照）
# 2. HabitRecord（habits と users を参照）
# 3. WeeklyReflection（users を参照）
# 4. Habit（users を参照）
# 5. User（他から参照される親）

puts "=" * 60
puts "🗑️  既存データを削除しています..."
puts "=" * 60

WeeklyReflectionHabitSummary.destroy_all
puts "  ✓ WeeklyReflectionHabitSummary を削除しました"

HabitRecord.destroy_all
puts "  ✓ HabitRecord を削除しました"

WeeklyReflection.destroy_all
puts "  ✓ WeeklyReflection を削除しました"

# unscoped: デフォルトスコープ（active スコープ等）を無視して全件対象にする
Habit.unscoped.destroy_all
puts "  ✓ Habit を削除しました"

User.destroy_all
puts "  ✓ User を削除しました"

puts ""

# ==============================================================================
# Step 1: 日付の基準を設定する
# ==============================================================================
#
# 【なぜ Time.current ではなく Date を使うのか】
# habit_records の record_date カラムは date 型（時刻なし・日付のみ）です。
# seeds.rb では「今日」「先週の月曜日」などの日付を計算するため
# Date オブジェクトを使います。
#
# 【AM4:00 基準との関係】
# HabitRecord.today_for_record は AM4:00 基準の「今日」を返します。
# seeds.rb では実行時刻を問わず安定した動作を優先するため、
# Date.today をそのまま使います（深夜実行時のズレは許容範囲です）。

puts "📅 日付の基準を設定しています..."

fixed_today        = Date.today
this_week_monday   = fixed_today.beginning_of_week(:monday)
last_week_monday   = this_week_monday - 1.week
last_week_sunday   = last_week_monday + 6.days
two_weeks_ago_monday = this_week_monday - 2.weeks
two_weeks_ago_sunday = two_weeks_ago_monday + 6.days
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
#
# 【create! と create の違い】
# create  → 失敗してもエラーを発生させず nil を返す（失敗に気づきにくい）
# create! → 失敗すると ActiveRecord::RecordInvalid 例外を発生させる
# seeds.rb では「作成失敗に即気づけるよう」create! を使います。

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
# 【create_record ローカルメソッドの役割】
# 特定の日付に「チェック済み」記録を作成するヘルパーです。
# find_or_create_by! を使うため、seeds.rb を複数回実行しても
# UNIQUE 制約エラーになりません。

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
                when 4 then [1, 3, 5].include?(day_of_week)
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
                when 0 then [1, 2, 4, 5].include?(day_of_week)
                when 1 then [1, 3, 5].include?(day_of_week)
                when 2 then day_of_week != 0
                when 3 then [1, 2, 4].include?(day_of_week)
                when 4 then [1, 5].include?(day_of_week)
                when 5 then [1, 2, 3, 4].include?(day_of_week)
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
                when 0 then [1, 2, 3, 4].include?(day_of_week)
                when 1 then [1, 2].include?(day_of_week)
                when 2 then [1, 2, 3, 4, 5].include?(day_of_week)
                when 3 then [1, 3, 5].include?(day_of_week)
                when 4 then day_of_week == 1
                when 5 then [1, 2, 3].include?(day_of_week)
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
                when 3 then [1, 2, 4].include?(day_of_week)
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
#
# 【デモ用データの設計意図】
# - 3週間前の振り返り: 完了済み
# - 先々週の振り返り:  完了済み
# - 先週の振り返り:    未完了（月曜AM4:00以降にロック状態をデモするため）

puts "🔄 週次振り返りデータを作成しています..."
puts ""

# ── 3週間前の振り返り（完了済み）─────────────────────────────
puts "  3週間前の振り返りを作成しています..."

reflection_3w = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: three_weeks_ago_monday,
  week_end_date:   three_weeks_ago_sunday,
  reflection_comment: <<~COMMENT
    今週は全体的に調子が良く、ほとんどの習慣を達成できました。
    特に瞑想は毎日継続でき、精神的に落ち着いた1週間でした。
    筋トレも週5回の目標を達成。英語学習は水曜日に飲み会があり1回スキップしましたが、
    全体的には満足できる週でした。来週も同じペースを維持したいです。
  COMMENT
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

# ── 先週の振り返り（完了済み）────────────────────────────────
puts "  先週の振り返りを作成しています（完了済み）..."

reflection_last_week = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: last_week_monday,
  week_end_date:   last_week_sunday
)
WeeklyReflectionHabitSummary.create_all_for_reflection!(reflection_last_week)
reflection_last_week.update!(
  reflection_comment: "習慣の継続は順調。来週は読書時間を増やしたい。"
)
reflection_last_week.complete!
puts "    ✓ 先週の振り返りを完了済みにしました（completed_at: #{reflection_last_week.completed_at}）"
puts ""

# ==============================================================================
# Step 7: 作成結果の確認サマリー
# ==============================================================================

puts "=" * 60
puts "✅ Seeds 実行完了！"
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
puts "🎯 デモで確認できること:"
puts "  1. ダッシュボード → 今週の達成率（プログレスバー）"
puts "  2. 習慣一覧 → 6個の習慣が表示（論理削除済みは非表示）"
puts "  3. ダッシュボード → ⚠️  ロック中の警告バナー ※月曜AM4:00以降に表示"
puts "  4. 週次振り返り一覧 → 3週間前・先々週の完了済み振り返りを確認"
puts "  5. 先週の振り返りを完了 → ロック解除"
puts ""
puts "💡 ロックバナーが表示されない場合:"
puts "  今日が日曜の場合は仕様上バナーは表示されません。"
puts "  翌月曜 AM4:00 以降にアクセスすると自動的に表示されます。"
puts ""