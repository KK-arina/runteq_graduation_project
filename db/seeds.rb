# ==============================================================================
# db/seeds.rb
# ==============================================================================
#
# 【このファイルの役割】
# デモ用のサンプルデータをデータベースに投入するファイルです。
# 以下のコマンドで実行します:
#
#   docker compose exec web bin/rails db:seed
#
# 【注意】
# このファイルは「開発・デモ確認用」です。
# 本番環境で個人情報を含むデータを投入しないでください。
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
# 本番環境誤実行防止ガード
# ==============================================================================
#
# 【なぜこのガードが必要なのか】
# seeds.rb は全データを削除してから再作成します。
# 本番環境で誤って実行すると、本物のユーザーデータが全て消えてしまいます。
#
# Rails.env.production? は環境変数 RAILS_ENV が "production" のとき true を返します。
# Render などの本番サービスでは RAILS_ENV=production が設定されているため、
# このガードで確実に実行を防げます。
#
# abort: 処理を即座に中断してターミナルにメッセージを表示するメソッドです。
# raise と違い、エラーではなく「意図的な中断」として終了コード 1 を返します。
if Rails.env.production?
  abort("🚫 本番環境では db:seed を実行できません。開発環境で実行してください。")
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
#
# ただし schema.rb を見ると:
#   habit_records には on_delete: :cascade → habits削除で自動削除
#   weekly_reflection_habit_summaries にも cascade/nullify あり
# そのため Habit → HabitRecord の順でも動作しますが、
# 明示的に子から削除する方がコードの意図が明確です。

puts "=" * 60
puts "🗑️  既存データを削除しています..."
puts "=" * 60

# WeeklyReflectionHabitSummary を先に削除する
# 理由: weekly_reflections と habits の両方を外部キーで参照しているため
WeeklyReflectionHabitSummary.destroy_all
puts "  ✓ WeeklyReflectionHabitSummary を削除しました"

# HabitRecord を削除する
# 理由: habits と users を外部キーで参照しているため
HabitRecord.destroy_all
puts "  ✓ HabitRecord を削除しました"

# WeeklyReflection を削除する
# 理由: users を外部キーで参照しているため
WeeklyReflection.destroy_all
puts "  ✓ WeeklyReflection を削除しました"

# Habit を削除する（deleted_at の有無にかかわらず全件削除）
# 理由: users を外部キーで参照しているため
# unscoped: デフォルトスコープ（active スコープ等）を無視して全件対象にする
Habit.unscoped.destroy_all
puts "  ✓ Habit を削除しました"

# User を最後に削除する（他テーブルから参照される親テーブル）
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
# 【なぜ fixed_today を定義するのか】
# seeds.rb 内で「今日」を複数箇所で参照するとき、
# 毎回 Date.today を呼ぶと実行タイミング次第で値がズレる可能性があります。
# 冒頭で一度だけ取得して変数に入れることで全箇所で同じ「今日」を使えます。
#
# 【AM4:00 基準との関係】
# HabitRecord.today_for_record は AM4:00 基準の「今日」を返します。
# seeds.rb では実行時刻を問わず安定した動作を優先するため、
# Date.today をそのまま使います（深夜実行時のズレは許容範囲です）。

puts "📅 日付の基準を設定しています..."

# 今日の日付
fixed_today = Date.today

# 今週の月曜日（Rails の beginning_of_week はデフォルトで月曜始まり）
# 例: 今日が 2026/03/05（木）なら → 2026/03/02（月）
this_week_monday = fixed_today.beginning_of_week(:monday)

# 先週の月曜日・日曜日
# - 1.week: Rails の ActiveSupport 拡張で「1週間前」を計算できる
last_week_monday = this_week_monday - 1.week
last_week_sunday = last_week_monday + 6.days

# 先々週（2週間前）の月曜日・日曜日
two_weeks_ago_monday = this_week_monday - 2.weeks
two_weeks_ago_sunday = two_weeks_ago_monday + 6.days

# 3週間前の月曜日・日曜日（記録データを多めに作るため）
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
#
# 【password と password_confirmation の役割】
# has_secure_password（bcrypt）により、password= を呼ぶと
# 自動的にハッシュ化されて password_digest カラムに保存されます。
# password_confirmation は「パスワード確認欄との一致検証」に使います。
# DB には保存されません（バリデーション用の仮想属性）。

puts "👤 デモユーザーを作成しています..."

demo_user = User.create!(
  name: "山田 太郎",
  email: "test@example.com",
  password: "password",
  # password_confirmation: パスワード確認用（DBには保存されない仮想属性）
  # has_secure_password が password と一致するか検証する
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
#
# 【weekly_target の意味】
# 「1週間に何日実施するか」の目標値です。
# Habit モデルのバリデーションで 1〜7 の整数のみ許可されています。
#
# 【habits 配列に入れて一括管理する理由】
# 後の Step 4（記録データ作成）で全習慣をループして記録を作るため、
# 変数を個別に管理するより配列にまとめた方がコードがシンプルになります。
#
# 【デモとして「リアルな習慣」を選ぶ理由】
# 講師レビューや他の人がデモを見る際に、実際のユースケースを
# イメージしやすくするためです。

puts "📋 習慣データを作成しています..."

# demo_user.habits.create! とすることで、
# user_id が自動的に demo_user の id にセットされます
habits = [
  demo_user.habits.create!(
    name: "読書（15分以上）",
    # weekly_target: 7 → 毎日実施が目標
    weekly_target: 7
  ),
  demo_user.habits.create!(
    name: "筋トレ",
    # weekly_target: 5 → 平日のみ実施が目標
    weekly_target: 5
  ),
  demo_user.habits.create!(
    name: "瞑想（10分）",
    weekly_target: 7
  ),
  demo_user.habits.create!(
    name: "英語学習（Duolingo）",
    # weekly_target: 5 → 週5回が目標
    weekly_target: 5
  ),
  demo_user.habits.create!(
    name: "ジョギング（20分以上）",
    # weekly_target: 3 → 週3回（月・水・金）が目標
    weekly_target: 3
  ),
  demo_user.habits.create!(
    name: "日記を書く",
    weekly_target: 7
  )
]

habits.each { |h| puts "  ✓ #{h.name}（週#{h.weekly_target}回目標）" }
puts ""

# ==============================================================================
# Step 4: 論理削除済みの習慣を作成する（デモ用）
# ==============================================================================
#
# 【論理削除（soft delete）とは】
# レコードをデータベースから物理的に消す（DELETE）のではなく、
# deleted_at カラムに削除日時を記録することで「削除済み」とみなす設計です。
#
# 【なぜ論理削除が必要なのか】
# 過去の週次振り返りスナップショット（weekly_reflection_habit_summaries）が
# habit_id を参照しています。物理削除するとスナップショットの参照先が
# なくなってしまいます（on_delete: :nullify で habit_id は NULL になりますが、
# habit_name 等のスナップショットは残ります）。
#
# 【デモとしての意味】
# 習慣一覧ページでは active スコープ（deleted_at IS NULL）のみ表示されるため、
# この習慣は一覧に表示されません。「論理削除が正しく機能している」ことを
# 確認するためのデータです。

puts "🗑️  論理削除済み習慣を作成しています..."

deleted_habit = demo_user.habits.create!(
  name: "やめた習慣（論理削除済み・一覧に表示されないはず）",
  weekly_target: 7
)

# soft_delete メソッドは Habit モデルに定義されています
# touch(:deleted_at) で deleted_at = Time.current を保存します
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
# seeds.rb 内で何度も同じ処理を書かないようにまとめています。
#
# 【find_or_create_by! を使う理由】
# 同じ (user_id, habit_id, record_date) の組み合わせは
# UNIQUE 制約があるため重複できません。
# find_or_create_by! は「すでに存在すれば取得、なければ作成」します。
# seeds.rb を複数回実行した場合の安全弁にもなります。
#
# 【completed: true の意味】
# habit_records テーブルの completed カラムは boolean です。
# true = その日の習慣を実施した（チェック済み）
# false = その日の習慣を実施しなかった（デフォルト値）

# ローカルメソッド定義: 特定日付の記録を作成する
create_record = lambda do |habit, date, completed|
  # find_or_create_by!: 条件に合うレコードが存在すれば取得、なければ作成
  # ※ seeds.rb を複数回実行しても UNIQUE エラーにならない
  HabitRecord.find_or_create_by!(
    user: demo_user,
    habit: habit,
    record_date: date
  ) do |record|
    # ブロックは「新規作成時のみ」実行される
    # 既存レコードが見つかった場合はブロックをスキップして取得のみ行う
    record.completed = completed
  end
end

puts "📝 習慣記録データを作成しています..."
puts ""

# ── 3週間前の記録 ─────────────────────────────────────────────
# 達成率を高めに設定（モチベーション高い時期のデモ）
puts "  3週間前（#{three_weeks_ago_monday} 〜 #{three_weeks_ago_sunday}）の記録..."

# 3週間前の全7日分のループ
(0..6).each do |day_offset|
  date = three_weeks_ago_monday + day_offset.days

  habits.each_with_index do |habit, index|
    # 曜日によって達成/未達成を切り替え（リアルなパターンを再現）
    # habit.weekly_target に合わせて達成率を調整
    day_of_week = date.wday # 0=日曜, 1=月曜, ..., 6=土曜

    completed = case index
                when 0 # 読書（週7回目標）→ 6/7日達成（土曜だけ休み）
                  day_of_week != 6
                when 1 # 筋トレ（週5回目標）→ 5/5日達成（土日休み）
                  day_of_week.between?(1, 5)
                when 2 # 瞑想（週7回目標）→ 7/7日達成（完璧）
                  true
                when 3 # 英語（週5回目標）→ 4/5日達成（水曜と土日休み）
                  day_of_week.between?(1, 5) && day_of_week != 3
                when 4 # ジョギング（週3回目標）→ 3/3日達成（月水金）
                  [1, 3, 5].include?(day_of_week)
                when 5 # 日記（週7回目標）→ 5/7日達成（土日休み）
                  day_of_week.between?(1, 5)
                end

    create_record.call(habit, date, completed)
  end
end
puts "    ✓ 3週間前の記録を作成しました"

# ── 先々週（2週間前）の記録 ──────────────────────────────────
# 達成率をやや低めに設定（忙しい週のデモ）
puts "  先々週（#{two_weeks_ago_monday} 〜 #{two_weeks_ago_sunday}）の記録..."

(0..6).each do |day_offset|
  date = two_weeks_ago_monday + day_offset.days
  day_of_week = date.wday

  habits.each_with_index do |habit, index|
    completed = case index
                when 0 # 読書 → 5/7日達成（週半ばと土日に休み）
                  [1, 2, 4, 5].include?(day_of_week)
                when 1 # 筋トレ → 3/5日達成（月水金のみ）
                  [1, 3, 5].include?(day_of_week)
                when 2 # 瞑想 → 6/7日達成（日曜休み）
                  day_of_week != 0
                when 3 # 英語 → 3/5日達成（月火木のみ）
                  [1, 2, 4].include?(day_of_week)
                when 4 # ジョギング → 2/3日達成（月金のみ）
                  [1, 5].include?(day_of_week)
                when 5 # 日記 → 4/7日達成（平日前半のみ）
                  [1, 2, 3, 4].include?(day_of_week)
                end

    create_record.call(habit, date, completed)
  end
end
puts "    ✓ 先々週の記録を作成しました"

# ── 先週の記録 ────────────────────────────────────────────────
# 達成率を中程度に設定（振り返りの対象週・ロック状態のデモ）
puts "  先週（#{last_week_monday} 〜 #{last_week_sunday}）の記録..."

(0..6).each do |day_offset|
  date = last_week_monday + day_offset.days
  day_of_week = date.wday

  habits.each_with_index do |habit, index|
    completed = case index
                when 0 # 読書 → 4/7日達成
                  [1, 2, 3, 4].include?(day_of_week)
                when 1 # 筋トレ → 2/5日達成（月火のみ・忙しい週）
                  [1, 2].include?(day_of_week)
                when 2 # 瞑想 → 5/7日達成
                  [1, 2, 3, 4, 5].include?(day_of_week)
                when 3 # 英語 → 3/5日達成
                  [1, 3, 5].include?(day_of_week)
                when 4 # ジョギング → 1/3日達成（月曜のみ）
                  day_of_week == 1
                when 5 # 日記 → 3/7日達成
                  [1, 2, 3].include?(day_of_week)
                end

    create_record.call(habit, date, completed)
  end
end
puts "    ✓ 先週の記録を作成しました"

# ── 今週の記録（月曜〜今日まで）────────────────────────────────
# 今週進行中の状態をデモ（一部達成済み）
puts "  今週（#{this_week_monday} 〜 今日#{fixed_today}）の記録..."

# today との差を計算して「今日まで」のみ記録を作成
days_elapsed = (fixed_today - this_week_monday).to_i

(0..days_elapsed).each do |day_offset|
  date = this_week_monday + day_offset.days
  day_of_week = date.wday

  habits.each_with_index do |habit, index|
    # 今週は「調子が戻ってきた週」として70〜80%達成のリアルなパターンに設定する
    # 全達成（true 固定）は不自然なため、習慣ごとに異なるパターンにしている
    completed = case index
                when 0 # 読書（週7回目標）→ 今週は毎日達成（調子良い）
                  true
                when 1 # 筋トレ（週5回目標）→ 平日のみ達成（土日は休息）
                  day_of_week.between?(1, 5)
                when 2 # 瞑想（週7回目標）→ 毎日達成（短時間なので継続しやすい）
                  true
                when 3 # 英語（週5回目標）→ 月火木のみ（水曜は夜遅くて疲れた）
                  [1, 2, 4].include?(day_of_week)
                when 4 # ジョギング（週3回目標）→ 月曜のみ（まだ本調子でない）
                  day_of_week == 1
                when 5 # 日記（週7回目標）→ 毎日達成（習慣として定着）
                  true
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
# 【週次振り返りの設計（実装コードとの対応）】
# WeeklyReflection モデルのカラム:
#   - week_start_date: 対象週の月曜日（Date型）
#   - week_end_date:   対象週の日曜日（week_start_date + 6日）
#   - reflection_comment: 振り返りコメント（1000文字以内）
#   - is_locked:       振り返り完了フラグ（boolean）
#   - completed_at:    振り返り完了日時（datetime / NULL=未完了）
#
# 【completed? と pending? の判定ロジック】
# WeeklyReflection#completed? → completed_at.present? → nil でなければ true
# WeeklyReflection#pending?   → !completed?
#
# 【PDCAロックとの連携】
# ApplicationController#locked? は:
#   1. 今が月曜 AM4:00 以降かチェック
#   2. 前週の振り返りレコードが存在するかチェック
#   3. 前週の振り返りが completed（completed_at IS NOT NULL）かチェック
# → 先週の振り返りを「未完了」にしておくと、ダッシュボードがロック状態になる
#
# 【デモ用データの設計意図】
# - 3週間前の振り返り: 完了済み（complete!で completed_at を設定）
# - 先々週の振り返り:  完了済み（complete!で completed_at を設定）
# - 先週の振り返り:    未完了（作成しない → ロック状態のデモ）
# ※ 先週の振り返りを未完了にすることで、ダッシュボードの「ロック状態」と
#   「警告バナー」がすぐに確認できます。

puts "🔄 週次振り返りデータを作成しています..."
puts ""

# ── 3週間前の振り返り（完了済み）─────────────────────────────
puts "  3週間前の振り返りを作成しています..."

reflection_3w = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: three_weeks_ago_monday,
  # week_end_date: week_start_date + 6日（モデルのカスタムバリデーションで検証される）
  week_end_date:   three_weeks_ago_sunday,
  reflection_comment: <<~COMMENT
    今週は全体的に調子が良く、ほとんどの習慣を達成できました。
    特に瞑想は毎日継続でき、精神的に落ち着いた1週間でした。
    筋トレも週5回の目標を達成。英語学習は水曜日に飲み会があり1回スキップしましたが、
    全体的には満足できる週でした。来週も同じペースを維持したいです。
  COMMENT
  # is_locked は complete! メソッドで true にするため、ここでは省略（デフォルト: false）
)

# ── 3週間前のスナップショットを作成（complete! の前に実行する）────
#
# 【なぜ complete! の前にスナップショットを作成するのか】
# アプリの実際の動作フロー（WeeklyReflectionsController#create）では:
#   1. 振り返りフォームを保存（reflection_comment 等を DB に書き込む）
#   2. スナップショットを作成（その時点の習慣記録を集計して保存）
#   3. complete! を呼んで「完了済み」状態にする
# という順序になっています。
#
# seeds.rb もこの順序を忠実に再現することで、
# 「コードが実際のアプリ動作と一致している」ことを保証できます。
#
# create_all_for_reflection! は:
#   1. user の有効な習慣（habits.active）を全て取得
#   2. 対象週の記録数・達成率を集計
#   3. スナップショットとして保存
# ※ このメソッドは WeeklyReflectionHabitSummary クラスメソッドとして定義済み
WeeklyReflectionHabitSummary.create_all_for_reflection!(reflection_3w)
puts "    ✓ 3週間前のスナップショットを作成しました"

# complete! メソッドを呼ぶことで:
#   1. completed_at = Time.current（現在時刻）をセット
#   2. is_locked = true をセット
#   3. DB に保存（update!）
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
    朝活にシフトすることで、仕事の忙しさに左右されにくくなるはず。
  COMMENT
)

WeeklyReflectionHabitSummary.create_all_for_reflection!(reflection_2w)
puts "    ✓ 先々週のスナップショットを作成しました"

reflection_2w.complete!
puts "    ✓ 先々週の振り返りを完了済みにしました（completed_at: #{reflection_2w.completed_at}）"
puts ""

# ── 先週の振り返り（未完了状態で作成 → ロック状態のデモ）────────
#
# 【設計の意図】
# ApplicationController#locked? は以下の条件で true（ロック中）を返します:
#   1. 今が月曜 AM4:00 以降である
#   2. 前週の振り返りレコードが「存在する」
#   3. 前週の振り返りが「未完了（completed_at IS NULL）」である
#
# → 先週の振り返りを「未完了状態（completed_at = nil）」で作成することで、
#   月曜 AM4:00 以降にログインするとロック警告バナーが表示されます。
#
# 【⚠️ db:seed 実行前に手動操作をしていた場合の注意】
# db:seed を実行する前に、ブラウザで今週の振り返りを手動で完了させていた場合、
# そのデータは db:seed のクリーンアップで削除されます（Step 0 の destroy_all）。
# ただし、もし何らかの理由で先週の振り返りがロック解除されない場合は、
# 以下のコマンドで先週分を直接完了させることができます:
#
#   docker compose exec web bin/rails runner \
#     "WeeklyReflection.find_by(week_start_date: '#{last_week_monday}').complete!"
#
# 【今日が日曜日の場合はロックバナーが表示されない】
# locked? は「月曜 AM4:00 以降」のみ true を返します。
# 日曜日に db:seed を実行した場合、ロック条件の Step 1 で false になるため
# 警告バナーは表示されません。これはバグではなくアプリ仕様通りの動作です。
# → 翌月曜 AM4:00 以降にアクセスすると自動的にロックバナーが表示されます。

puts "  先週の振り返りを作成しています（未完了・ロック状態のデモ）..."

_reflection_last_week = WeeklyReflection.create!(
  user:            demo_user,
  week_start_date: last_week_monday,
  week_end_date:   last_week_sunday
  # completed_at は設定しない → pending? = true
  # 月曜 AM4:00 以降にアクセスすると locked? = true になりロックバナーが表示される
)

puts "    ✓ 先週の振り返りを未完了状態で作成しました"
puts "    ⚠️  月曜 AM4:00 以降にアクセスするとロック警告バナーが表示されます"
puts "    ⚠️  先週の振り返りを完了させるとロックが解除されます"
puts ""

# ==============================================================================
# Step 7: 作成結果の確認サマリーを表示する
# ==============================================================================
#
# 【puts を使って確認する理由】
# seeds.rb を実行後、どれだけのデータが作成されたかを
# ターミナルで一目確認できるようにします。
# カウントは直接 DB を参照するため、実際に保存された件数が表示されます。

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
puts "  すぐに確認したい場合は以下のコマンドを実行してください:"
puts "  docker compose exec web bin/rails runner \\"
puts "    \"WeeklyReflection.find_by(week_start_date: '#{last_week_monday}').complete!\""
puts ""
