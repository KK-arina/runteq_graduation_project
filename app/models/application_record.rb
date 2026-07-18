# app/models/application_record.rb
#
# ============================================================
# 【このファイルの役割】
# 全てのモデルの親クラス。共通のトランザクションメソッドを定義する。
#
# 【Issue #A-7 最終修正版】
#
# 【設計方針の変更】
# with_transaction は「例外をキャッチしない」シンプルなラッパーにする。
# 例外のハンドリング（rescue）はサービスクラス側で行う。
#
# 【なぜ with_transaction 内で rescue しないのか】
#
#   問題のあった設計:
#     def with_transaction
#       transaction { yield }
#       { success: true }
#     rescue => e
#       { success: false }   ← ここで例外を握りつぶす
#     end
#
#   ネスト時に何が起きるか:
#     外側 transaction do
#       習慣1を作成
#       内側 with_transaction do     ← 内側の with_transaction を呼ぶ
#         習慣2を作成
#         例外発生
#       end                          ← 内側の rescue が例外をキャッチ → Hash 返す
#     end                            ← 外側は例外を知らない → COMMIT される
#
#   → 習慣1も習慣2もDBに保存されてしまう（ロールバックなし）
#
# 【正しい設計】
# with_transaction は transaction ブロックを提供するだけ。
# 例外はそのまま外に伝播させ、サービスクラス側の rescue で処理する。
#
#   サービスクラス:
#     def call
#       ApplicationRecord.with_transaction do
#         ...  ← ここで例外が発生すると
#       end    ← transaction を抜ける前に Rails がロールバック
#       { success: true }
#     rescue ActiveRecord::RecordInvalid => e
#       { success: false, error: e.message }  ← ロールバック後にここに来る
#     end
#
# 【with_transaction のネスト使用は禁止】
# with_transaction の中で with_transaction を呼ばないこと。
# WeeklyReflectionHabitSummary.create_all_for_reflection! の内部 transaction は
# 外側の with_transaction の transaction ブロックに「合流」するため問題ない。
# これは with_transaction のネストとは異なる。
# ============================================================

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # ============================================================
  # Issue #I-6: キャッシュキーの命名規則を1箇所に集約する
  # ============================================================
  #
  # 【なぜ ApplicationRecord に置くのか】
  #   キャッシュキーは「作る側（コントローラー）」と「消す側（モデルの after_commit）」の
  #   2箇所で必要になる。両者が別々に文字列を組み立てると、
  #   片方だけ書き換えたときに「キャッシュが永久に消えない」という
  #   最も発見しにくいバグが生まれる。
  #   全モデルの親であり、かつコントローラーからも
  #   ApplicationRecord.xxx で呼べる ApplicationRecord に集約することで
  #   「キーの作り方はこの1ファイルにしか存在しない」状態を保証する。
  #
  # 【❗Solid Cache の重大な制約: delete_matched が使えない】
  #   Redis や MemoryStore なら
  #     Rails.cache.delete_matched("dashboard:5:*")
  #   のようにワイルドカードでまとめて消せる。
  #   しかし SolidCache::Store はこのメソッドを実装していないため、
  #   呼ぶと NotImplementedError で 500 エラーになる。
  #
  #   したがって #I-6 のキャッシュキーは
  #   「消す側が、DBを引かずに完全に組み立て直せる材料」だけで
  #   構成しなければならない。この制約が下記のキー設計の理由になっている。
  # ============================================================

  # ANALYTICS_PERIOD_KEYS: グラフページ（19番）の期間フィルターの全種類
  #
  # 【なぜモデル側に定数を置くのか】
  #   グラフのキャッシュキーには period（4w/12w/all）が含まれる。
  #   habit_record を保存したとき、消す側は「どの period のキャッシュが
  #   作られているか」を知らないため、3種類すべてを消す必要がある。
  #   AnalyticsController::PERIOD_KEYS を参照すると
  #   「モデルがコントローラーに依存する」という逆流した設計になるため、
  #   定義をこちら（ApplicationRecord）に移し、
  #   AnalyticsController 側がこの定数を参照する形にする。
  #   これで「期間の種類」の定義はアプリ内で唯一1箇所だけになる。
  ANALYTICS_PERIOD_KEYS = %w[4w 12w all].freeze

  class << self
    # ==========================================================
    # cache_key_for（#I-6 追加）: キー命名規則の唯一の実装
    # ==========================================================
    # 【役割】
    #   ISSUE で定められた "#{model}:#{user_id}:#{cache_version}" の
    #   命名規則に従ったキー文字列を組み立てる。
    #
    # 【なぜ join(":") なのか】
    #   "#{model}:#{user_id}:#{version}" と式展開で書いても同じだが、
    #   区切り文字を変えたくなったときに1箇所の修正で済む。
    #
    # 【実際に生成されるキーの例】
    #   "dashboard_habit_stats:12:2026-07-13"
    #   "analytics:12:4w:2026-07-17"
    #   なお Solid Cache は config/cache.yml の namespace 設定により
    #   実際のDB上では "production:dashboard_habit_stats:12:2026-07-13" として保存される。
    def cache_key_for(model, user_id, version)
      [ model, user_id, version ].join(":")
    end

    # ==========================================================
    # dashboard_habit_stats_cache_key（#I-6 追加）
    # ==========================================================
    # 【役割】
    #   ダッシュボードの「今週の習慣記録の集計値」を保存するキーを返す。
    #
    # 【❗なぜ Date.today.cweek を使わないのか（ISSUE本文からの意図的な変更）】
    #   ISSUE には Date.today.cweek と書かれているが、これは
    #   本プロジェクトの規約に2つ違反している:
    #
    #     ① Date.today はサーバーのシステムタイムゾーンを見るため、
    #        config.time_zone = "Tokyo" を無視する。
    #        Render の本番サーバーは UTC で動くため、JST の朝9時が
    #        UTC の前日0時と解釈され、日付が1日ズレる。
    #        README の教訓「必ず Date.current / Time.current を使う」に反する。
    #
    #     ② このアプリの「1日の境界」は AM0:00 ではなく AM4:00。
    #        深夜3:59 の記録は「前日の記録」として扱う仕様のため、
    #        cweek をそのまま使うと 0:00〜3:59 の間だけ
    #        キャッシュキーが翌週にジャンプしてしまう。
    #
    #   HabitRecord.today_for_record が AM4:00 境界を考慮した「今日」を返すため、
    #   これを基準にすることで全画面と同じ日付判定に揃う。
    #
    # 【なぜ cweek（週番号）ではなく週の開始日（日付文字列）なのか】
    #   cweek は「1〜53」の数字で、年をまたぐと 52 → 1 に戻る。
    #   2026年の第3週と2027年の第3週が同じキーになり、
    #   年末年始に前年のキャッシュを読んでしまう危険がある。
    #   "2026-07-13" のような週開始日なら年も含むため衝突しない。
    #
    # 【なぜ「今日」ではなく「週の開始日」なのか】
    #   ダッシュボードが表示するのは「今週（月曜〜今日）の集計」。
    #   日付をキーにすると毎日キャッシュが作り直されるが、
    #   週開始日をキーにすると同じ週の間はキーが変わらない。
    #   その週の記録が増えたときは after_commit が明示的に消すため、
    #   古いデータが表示されることはない。
    def dashboard_habit_stats_cache_key(user_id, today = HabitRecord.today_for_record)
      cache_key_for("dashboard_habit_stats", user_id, today.beginning_of_week(:monday).to_s)
    end

    # ==========================================================
    # analytics_cache_key（#I-6 追加）
    # ==========================================================
    # 【役割】
    #   グラフページ（19番）の集計結果を保存するキーを返す。
    #
    # 【なぜ period をキーに含めるのか】
    #   4週間・12週間・全期間で表示するデータがまったく異なるため。
    #   含めないと「4週間で見た後に12週間に切り替えても4週間のグラフが出る」
    #   という致命的なバグになる。
    #
    # 【なぜ「週開始日」ではなく「今日」をキーに含めるのか】
    #   ダッシュボードと違い、グラフの当月サマリーカードは
    #   「月初から今日までの経過日数」を分母に使う（build_monthly_summary）。
    #   つまり日付が変わると計算結果も変わるため、日単位でキーを分ける必要がある。
    #   前日のキーは誰も読まなくなり、config/cache.yml の max_age（7日）で
    #   自動的に掃除される。
    def analytics_cache_key(user_id, period, today = HabitRecord.today_for_record)
      cache_key_for("analytics", user_id, "#{period}:#{today}")
    end

    # ==========================================================
    # expire_dashboard_habit_stats_cache（#I-6 追加）
    # ==========================================================
    # 【役割】
    #   指定ユーザーのダッシュボード集計キャッシュを削除する。
    #   HabitRecord / Habit の after_commit から呼ばれる。
    #
    # 【なぜ「今週のキー」だけを消せば十分なのか】
    #   ダッシュボードが表示するのは常に「今週」の集計のみ。
    #   週次振り返りの数値補正で先週の habit_record が更新された場合でも、
    #   ダッシュボードは先週の集計を表示しないため消す必要がない。
    #   （先週のキーは max_age で自然に消える）
    #
    # 【Rails.cache.delete が存在しないキーに対して呼ばれた場合】
    #   false を返すだけで例外にはならない。安全に呼び捨てできる。
    def expire_dashboard_habit_stats_cache(user_id)
      Rails.cache.delete(dashboard_habit_stats_cache_key(user_id))
    end

    # ==========================================================
    # expire_analytics_cache（#I-6 追加）
    # ==========================================================
    # 【役割】
    #   指定ユーザーのグラフページのキャッシュを削除する。
    #   HabitRecord / Habit / WeeklyReflection の after_commit から呼ばれる。
    #
    # 【なぜ3種類すべての period を消すのか】
    #   ユーザーがどの期間フィルターで閲覧したかは、消す側からは分からない。
    #   4w だけ消して 12w を残すと「12週間表示にしたときだけ古いグラフが出る」
    #   という再現性の低いバグになる。
    #   ANALYTICS_PERIOD_KEYS をループして確実に全部消す。
    #
    # 【DELETE が3回発行されるコストについて】
    #   solid_cache_entries の key_hash にはユニークインデックスがあるため、
    #   1件あたりのDELETEはインデックスの一点削除で完了する（数ミリ秒）。
    #   習慣のチェック1回につき合計4回（ダッシュボード1＋グラフ3）の
    #   軽量な DELETE が増えるが、グラフページで削減できる
    #   重い pluck ＋ Ruby ループのコストに比べれば十分に見合う。
    def expire_analytics_cache(user_id)
      ANALYTICS_PERIOD_KEYS.each do |period|
        Rails.cache.delete(analytics_cache_key(user_id, period))
      end
    end

    # ==========================================================
    # with_transaction（Issue #A-7 最終版）
    # ==========================================================
    # 【役割】
    # ActiveRecord::Base.transaction のシンプルなラッパー。
    # 例外はキャッチせずそのまま外に伝播させる。
    #
    # 【重要: このメソッドはネストして使わないこと】
    # with_transaction の中で with_transaction を呼ぶと、
    # 内側の例外が外側に伝播しない問題が起きる。
    # rescue はサービスクラス側でのみ書く。
    #
    # 【使い方（サービスクラス内）】
    #   def call
    #     ApplicationRecord.with_transaction do
    #       record1.save!    ← 失敗すると例外が外に出る
    #       record2.save!    ← record1 の保存もロールバックされる
    #     end
    #     { success: true, error: nil }
    #   rescue ActiveRecord::RecordInvalid => e
    #     { success: false, error: e.message }
    #   rescue StandardError => e
    #     { success: false, error: "予期しないエラーが発生しました" }
    #   end
    #
    # 【なぜ yield だけなのか】
    # Rails の ActiveRecord::Base.transaction は、ブロック内で例外が発生すると
    # 自動的にロールバックして例外を再 raise する。
    # with_transaction はこの動作を「そのまま活かす」だけのラッパー。
    # rescue を書かないことで、呼び出し元（サービスクラス）に
    # 「何が起きたか」を正確に伝えることができる。
    def with_transaction(&block)
      # ActiveRecord::Base.transaction
      # → ブロック内の全 DB 操作を1つのトランザクションとして実行する。
      # → ブロック内で例外が発生した場合:
      #   1. Rails がロールバックを実行する
      #   2. 例外をそのまま再 raise する（外に伝播させる）
      # → ブロックが正常終了した場合: COMMIT する
      #
      # &block
      # → yield と同じ意味だが、ブロックを明示的に受け取って transaction に渡す。
      # → ActiveRecord::Base.transaction(&block) と書くことで
      #   ブロックを直接 transaction に渡せる（最も明確な書き方）。
      ActiveRecord::Base.transaction(&block)
    end
  end
end