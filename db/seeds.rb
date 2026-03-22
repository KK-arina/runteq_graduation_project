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

# ── 先週の振り返り（未完了状態・ロック状態のデモ）────────────
puts "  先週の振り返りを作成しています（未完了・ロック状態のデモ）..."

reflection_last_week = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: last_week_monday,
  week_end_date:   last_week_sunday
)
WeeklyReflectionHabitSummary.create_all_for_reflection!(reflection_last_week)
puts "    ✓ 先週の振り返りを未完了状態で作成しました"
puts "    ⚠️  月曜 AM4:00 以降にアクセスするとロック警告バナーが表示されます"
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

# ==============================================================================
# Step 8: habit_templates（習慣テンプレート）のシードデータ作成
# ==============================================================================
#
# 【このステップの役割】
# オンボーディング（初回ログイン時のガイド画面）で
# ユーザーが習慣を選びやすいように、カテゴリ別のテンプレートを登録します。
#
# 【find_or_initialize_by + assign_attributes + save! を使う理由】
# find_or_create_by! のブロック方式だと「新規作成時のみ」属性がセットされ、
# 既存レコードが永遠に更新されません。
# 例えば description を後から修正しても、本番DBには反映されません。
#
# find_or_initialize_by は「あれば取得・なければ新規インスタンス生成」をします。
# その後 assign_attributes で全属性を上書きし、save! で保存することで
# 新規作成・既存更新の両方を1つのパターンで安全に処理できます。
#
# 【new_record? とは】
# DBに保存されていない新規インスタンスのとき true を返すメソッドです。
# find_or_initialize_by の直後に呼ぶことで
# 「新規作成か・既存更新か」を判定できます。
#
# 【検索キーに name + category を使う理由】
# schema.rb に slug カラムは存在しないため、
# name と category の複合条件で同一レコードを特定します。
# 同じ名前でもカテゴリが異なれば別テンプレートとして扱えます。
# （例: "読書"（health）と "読書（学習）"（study）は別テンプレート）
#
# 【カテゴリ分類の方針】
# health  (健康): 体の健康維持・生活習慣に関する習慣
# fitness (フィットネス): 運動・体力向上に関する習慣
# study   (学習): 知識・スキル習得に関する習慣
# mind    (マインド): 精神的な健康・内省に関する習慣

puts ""
puts "=" * 60
puts "📚 habit_templates（習慣テンプレート）を登録しています..."
puts "=" * 60
puts ""

# ------------------------------------------------------------------------------
# テンプレートデータの定義
# ------------------------------------------------------------------------------
#
# 【データをハッシュの配列で定義する理由】
# データと処理ロジックを分離することで、
# テンプレートの追加・修正がこの配列の編集だけで完結します。
# 処理ロジック（each ブロック内）を触らずに済むため、バグが入りにくくなります。
#
# 【各キーの説明】
# name                  : 習慣名（ユーザーに表示される名前）
# measurement_type      : 測定タイプ（:check_type or :numeric_type）
# default_unit          : 数値型の単位（チェック型は nil）
# default_weekly_target : 週の目標回数（1〜7）
# category              : カテゴリ（:health / :fitness / :study / :mind）
# description           : テンプレートの説明（オンボーディングで表示）
# sort_order            : 表示順（数値が小さいほど先に表示）

template_data = [
  # ============================================================
  # 健康カテゴリ（health）
  # 体の健康維持・生活習慣に関する習慣
  # ============================================================
  {
    name:                  "読書",
    measurement_type:      :check_type,   # やった/やらないで記録
    default_unit:          nil,           # チェック型なので単位なし
    default_weekly_target: 7,             # 毎日読書を目標
    category:              :health,
    description:           "毎日15分以上の読書で知識と集中力を養います。",
    sort_order:            10
  },
  {
    name:                  "瞑想",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 7,
    category:              :health,
    description:           "10分間の瞑想でストレスを軽減し、集中力を高めます。",
    sort_order:            20
  },
  {
    name:                  "睡眠日記",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 7,
    category:              :health,
    description:           "就寝前に睡眠の質を記録して睡眠改善に役立てます。",
    sort_order:            30
  },
  {
    name:                  "水を飲む",
    measurement_type:      :numeric_type, # 量（ml）を記録
    default_unit:          "ml",
    default_weekly_target: 7,
    category:              :health,
    description:           "1日2000ml以上の水分補給で体調を整えます。",
    sort_order:            40
  },
  {
    name:                  "早起き",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 5,
    category:              :health,
    description:           "毎朝6時起きで朝の時間を有効活用します。",
    sort_order:            50
  },

  # ============================================================
  # フィットネスカテゴリ（fitness）
  # 運動・体力向上に関する習慣
  # ============================================================
  {
    name:                  "筋トレ",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 3,             # 休息日を考慮して週3回
    category:              :fitness,
    description:           "自重トレーニングや器具を使った筋力アップトレーニングです。",
    sort_order:            60
  },
  {
    name:                  "ジョギング",
    measurement_type:      :numeric_type, # 走った時間（分）を記録
    default_unit:          "分",
    default_weekly_target: 3,
    category:              :fitness,
    description:           "20〜30分のジョギングで心肺機能と体力を高めます。",
    sort_order:            70
  },
  {
    name:                  "ストレッチ",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 7,
    category:              :fitness,
    description:           "就寝前の10分ストレッチで柔軟性を高め疲労を回復します。",
    sort_order:            80
  },
  {
    name:                  "ウォーキング",
    measurement_type:      :numeric_type, # 歩いた時間（分）を記録
    default_unit:          "分",
    default_weekly_target: 5,
    category:              :fitness,
    description:           "30分のウォーキングで有酸素運動の習慣をつけます。",
    sort_order:            90
  },
  {
    name:                  "体重記録",
    measurement_type:      :numeric_type, # 体重（kg）を記録
    default_unit:          "kg",
    default_weekly_target: 7,
    category:              :fitness,
    description:           "毎朝の体重を記録してダイエットや健康管理に活用します。",
    sort_order:            100
  },

  # ============================================================
  # 学習カテゴリ（study）
  # 知識・スキル習得に関する習慣
  # ============================================================
  {
    name:                  "英語学習",
    measurement_type:      :numeric_type, # 学習時間（分）を記録
    default_unit:          "分",
    default_weekly_target: 5,
    category:              :study,
    description:           "アプリや教材を使った英語学習で語学力を伸ばします。",
    sort_order:            110
  },
  {
    name:                  "プログラミング学習",
    measurement_type:      :numeric_type,
    default_unit:          "分",
    default_weekly_target: 5,
    category:              :study,
    description:           "毎日コードを書いてプログラミングスキルを習得します。",
    sort_order:            120
  },
  {
    name:                  "読書（学習）",
    measurement_type:      :numeric_type, # 読んだページ数を記録
    default_unit:          "ページ",
    default_weekly_target: 5,
    category:              :study,
    description:           "ビジネス書や技術書を読んで専門知識を深めます。",
    sort_order:            130
  },
  {
    name:                  "オンライン講座",
    measurement_type:      :numeric_type, # 受講時間（分）を記録
    default_unit:          "分",
    default_weekly_target: 3,
    category:              :study,
    description:           "動画講座やeラーニングで新しいスキルを習得します。",
    sort_order:            140
  },

  # ============================================================
  # マインドカテゴリ（mind）
  # 精神的な健康・内省に関する習慣
  # ============================================================
  {
    name:                  "日記",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 7,
    category:              :mind,
    description:           "1日の出来事や感情を記録して自己理解を深めます。",
    sort_order:            150
  },
  {
    name:                  "感謝リスト",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 7,
    category:              :mind,
    description:           "今日感謝できることを3つ書き出してポジティブな思考を育てます。",
    sort_order:            160
  },
  {
    name:                  "呼吸法",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 7,
    category:              :mind,
    description:           "深呼吸や腹式呼吸でリラックスしストレスを解消します。",
    sort_order:            170
  },
  {
    name:                  "デジタルデトックス",
    measurement_type:      :check_type,
    default_unit:          nil,
    default_weekly_target: 7,
    category:              :mind,
    description:           "就寝1時間前はスマホをオフにして質の良い睡眠を確保します。",
    sort_order:            180
  }
]

# ------------------------------------------------------------------------------
# テンプレートデータを DB に登録する
# ------------------------------------------------------------------------------
#
# 【find_or_initialize_by とは】
# 「条件に一致するレコードがあれば取得し、なければ新規インスタンスを生成する」
# メソッドです。find_or_create_by と違い、この時点ではまだ DB に保存しません。
#
# 【assign_attributes とは】
# インスタンスに複数の属性をまとめてセットするメソッドです。
# この時点でもまだ DB に保存しません。
# save! を呼んで初めて DB に書き込まれます。
#
# 【new_record? とは】
# DB に保存されていない（まだ id がない）インスタンスのとき true を返します。
# assign_attributes の前に呼ぶことで「新規作成か・既存更新か」を正しく判定できます。
# assign_attributes の後に呼ぶと、インスタンスの状態が変化している可能性があるため
# 必ず assign_attributes の前に is_new を確認します。

template_created_count = 0  # 新規作成した件数のカウンター
template_updated_count  = 0  # 既存を更新した件数のカウンター

template_data.each do |data|
  # 検索キー: name と category の組み合わせでレコードを特定する
  template = HabitTemplate.find_or_initialize_by(
    name:     data[:name],
    category: data[:category]
  )

  # assign_attributes の前に new_record? を確認する（重要）
  # assign_attributes 後は内部状態が変わり正確な判定ができなくなる場合があります
  is_new = template.new_record?

  # 全属性をセット（新規・既存どちらも上書きする）
  # これにより description や sort_order を後から変更したとき
  # db:seed を再実行するだけで本番 DB に反映される
  template.assign_attributes(
    measurement_type:      data[:measurement_type],
    default_unit:          data[:default_unit],
    default_weekly_target: data[:default_weekly_target],
    description:           data[:description],
    sort_order:            data[:sort_order],
    is_active:             true
  )

  # save! で DB に保存する（失敗時は例外を発生させて即気づけるようにする）
  template.save!

  if is_new
    template_created_count += 1
    puts "  ✅ [新規] #{template.name}（#{template.category}）"
  else
    template_updated_count += 1
    puts "  🔄 [更新] #{template.name}（#{template.category}）"
  end
end

puts ""
puts "=" * 60
puts "✅ habit_templates 登録完了！"
puts "=" * 60
puts "  新規作成: #{template_created_count} 件"
puts "  既存更新: #{template_updated_count} 件"
puts "  合計:     #{HabitTemplate.count} 件"
puts ""

# カテゴリ別の内訳を表示する
puts "  📊 カテゴリ別内訳:"
HabitTemplate.active.group(:category).count.each do |category, count|
  puts "    #{category}: #{count} 件"
end
puts ""