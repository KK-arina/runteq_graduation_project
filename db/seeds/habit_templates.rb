# ==============================================================================
# db/seeds/habit_templates.rb（#I-3: Part A マスタデータ）
# ==============================================================================
#
# 【このファイルの役割】
#   オンボーディング（初回ログイン時のガイド画面）で
#   ユーザーが習慣を選びやすいように、カテゴリ別のテンプレートを登録する。
#   全ユーザー共通のマスタデータで、本番にも必要。
#
# 【安全性（本番でも実行してよい理由）】
#   - 冪等: find_or_initialize_by により「あれば更新・なければ作成」なので、
#           何度実行しても件数が増えたり壊れたりしない。
#   - 非破壊: 既存レコードを delete/destroy しない。
#   よって本番・開発・テストのどの環境でも安全に読み込める。
#
# 【呼び出し元】
#   db/seeds.rb から load される（全環境で必ず実行される）。
#   単体でも `docker compose exec web bin/rails runner 'load "db/seeds/habit_templates.rb"'`
#   のように実行可能。
#
# 【find_or_initialize_by + assign_attributes + save! を使う理由】
#   find_or_create_by! のブロック方式だと「新規作成時のみ」属性がセットされ、
#   既存レコードが永遠に更新されない（description を直しても本番に反映されない）。
#   find_or_initialize_by は「あれば取得・なければ新規インスタンス生成」をし、
#   その後 assign_attributes で全属性を上書き、save! で保存することで
#   新規作成・既存更新の両方を安全に処理できる。
#
# 【検索キーに name + category を使う理由】
#   schema.rb に slug カラムは無いため name と category の複合条件で特定する。
#   同名でもカテゴリが異なれば別テンプレートとして扱える
#   （例: "読書"（health）と "読書（学習）"（study）は別）。
#
# 【カテゴリ分類】
#   health(健康) / fitness(フィットネス) / study(学習) / mind(マインド)
# ==============================================================================

puts ""
puts "=" * 60
puts "📚 habit_templates（習慣テンプレート）を登録しています...（全環境で実行）"
puts "=" * 60
puts ""

# ------------------------------------------------------------------------------
# テンプレートデータの定義（データと処理を分離して追加・修正をしやすくする）
# ------------------------------------------------------------------------------
# name / measurement_type(:check_type|:numeric_type) / default_unit(チェック型はnil)
# default_weekly_target(1〜7) / category / description / sort_order(小さいほど先に表示)
template_data = [
  # ============================================================
  # 健康カテゴリ（health）
  # ============================================================
  { name: "読書",       measurement_type: :check_type,   default_unit: nil,  default_weekly_target: 7, category: :health,  description: "毎日15分以上の読書で知識と集中力を養います。", sort_order: 10 },
  { name: "瞑想",       measurement_type: :check_type,   default_unit: nil,  default_weekly_target: 7, category: :health,  description: "10分間の瞑想でストレスを軽減し、集中力を高めます。", sort_order: 20 },
  { name: "睡眠日記",   measurement_type: :check_type,   default_unit: nil,  default_weekly_target: 7, category: :health,  description: "就寝前に睡眠の質を記録して睡眠改善に役立てます。", sort_order: 30 },
  { name: "水を飲む",   measurement_type: :numeric_type, default_unit: "ml", default_weekly_target: 7, category: :health,  description: "1日2000ml以上の水分補給で体調を整えます。", sort_order: 40 },
  { name: "早起き",     measurement_type: :check_type,   default_unit: nil,  default_weekly_target: 5, category: :health,  description: "毎朝6時起きで朝の時間を有効活用します。", sort_order: 50 },

  # ============================================================
  # フィットネスカテゴリ（fitness）
  # ============================================================
  { name: "筋トレ",       measurement_type: :check_type,   default_unit: nil,  default_weekly_target: 3, category: :fitness, description: "自重トレーニングや器具を使った筋力アップトレーニングです。", sort_order: 60 },
  { name: "ジョギング",   measurement_type: :numeric_type, default_unit: "分", default_weekly_target: 3, category: :fitness, description: "20〜30分のジョギングで心肺機能と体力を高めます。", sort_order: 70 },
  { name: "ストレッチ",   measurement_type: :check_type,   default_unit: nil,  default_weekly_target: 7, category: :fitness, description: "就寝前の10分ストレッチで柔軟性を高め疲労を回復します。", sort_order: 80 },
  { name: "ウォーキング", measurement_type: :numeric_type, default_unit: "分", default_weekly_target: 5, category: :fitness, description: "30分のウォーキングで有酸素運動の習慣をつけます。", sort_order: 90 },
  { name: "体重記録",     measurement_type: :numeric_type, default_unit: "kg", default_weekly_target: 7, category: :fitness, description: "毎朝の体重を記録してダイエットや健康管理に活用します。", sort_order: 100 },

  # ============================================================
  # 学習カテゴリ（study）
  # ============================================================
  { name: "英語学習",           measurement_type: :numeric_type, default_unit: "分",     default_weekly_target: 5, category: :study, description: "アプリや教材を使った英語学習で語学力を伸ばします。", sort_order: 110 },
  { name: "プログラミング学習", measurement_type: :numeric_type, default_unit: "分",     default_weekly_target: 5, category: :study, description: "毎日コードを書いてプログラミングスキルを習得します。", sort_order: 120 },
  { name: "読書（学習）",       measurement_type: :numeric_type, default_unit: "ページ", default_weekly_target: 5, category: :study, description: "ビジネス書や技術書を読んで専門知識を深めます。", sort_order: 130 },
  { name: "オンライン講座",     measurement_type: :numeric_type, default_unit: "分",     default_weekly_target: 3, category: :study, description: "動画講座やeラーニングで新しいスキルを習得します。", sort_order: 140 },

  # ============================================================
  # マインドカテゴリ（mind）
  # ============================================================
  { name: "日記",             measurement_type: :check_type, default_unit: nil, default_weekly_target: 7, category: :mind, description: "1日の出来事や感情を記録して自己理解を深めます。", sort_order: 150 },
  { name: "感謝リスト",       measurement_type: :check_type, default_unit: nil, default_weekly_target: 7, category: :mind, description: "今日感謝できることを3つ書き出してポジティブな思考を育てます。", sort_order: 160 },
  { name: "呼吸法",           measurement_type: :check_type, default_unit: nil, default_weekly_target: 7, category: :mind, description: "深呼吸や腹式呼吸でリラックスしストレスを解消します。", sort_order: 170 },
  { name: "デジタルデトックス", measurement_type: :check_type, default_unit: nil, default_weekly_target: 7, category: :mind, description: "就寝1時間前はスマホをオフにして質の良い睡眠を確保します。", sort_order: 180 }
]

# ------------------------------------------------------------------------------
# テンプレートデータを DB に登録する（冪等・非破壊）
# ------------------------------------------------------------------------------
template_created_count = 0  # 新規作成した件数
template_updated_count = 0  # 既存を更新した件数

template_data.each do |data|
  # 検索キー: name と category の組み合わせでレコードを特定する
  template = HabitTemplate.find_or_initialize_by(
    name:     data[:name],
    category: data[:category]
  )

  # assign_attributes の前に new_record? を確認する（後だと判定が変わるため）
  is_new = template.new_record?

  # 全属性をセット（新規・既存どちらも上書き＝説明文や表示順の修正が再seedで反映される）
  template.assign_attributes(
    measurement_type:      data[:measurement_type],
    default_unit:          data[:default_unit],
    default_weekly_target: data[:default_weekly_target],
    description:           data[:description],
    sort_order:            data[:sort_order],
    is_active:             true
  )

  # save! で保存（失敗時は例外を出して即気づけるようにする）
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
puts "  📊 カテゴリ別内訳:"
HabitTemplate.active.group(:category).count.each do |category, count|
  puts "    #{category}: #{count} 件"
end
puts ""
