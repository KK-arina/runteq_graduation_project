# app/models/weekly_reflection_task_summary.rb
#
# ==============================================================================
# WeeklyReflectionTaskSummary（週次振り返りタスクスナップショット）モデル
# ==============================================================================
#
# 【このモデルの役割】
#   週次振り返り完了時点の「タスク実績スナップショット」を管理する。
#
# 【スナップショット設計とは】
#   タスクは後から削除（論理削除）される場合がある。
#   しかし振り返り詳細ページ（15番）では振り返りを行った時点のタスク一覧を
#   正確に表示し続ける必要がある。
#   そのため「振り返り完了時点のタスクのコピー」をこのテーブルに保存する。
#
#   例:
#     振り返り完了時: タスク「企画書作成（Must・完了）」が記録される
#     後日: タスク「企画書作成」を削除
#     → 振り返り詳細ページには「企画書作成（Must・完了）」が引き続き表示される ✅
#
# 【WeeklyReflectionHabitSummary との設計上の統一】
#   習慣スナップショット（WeeklyReflectionHabitSummary）と同じ設計方針を採用。
#   create_all_for_reflection! クラスメソッドで一括作成するパターンも同じ。
#
# 【カラムとビューの対応】
#   title         → タスク名として詳細ページに表示
#   priority      → 優先度ラベル（Must / Should / Could）として表示
#   task_type     → タスク種別（通常 / 習慣関連 / 改善）として表示
#   was_completed → 完了アイコン（✅ / ⬜）として表示
#   completed_at  → 完了日時として表示（任意）
#   due_date      → 期限日として表示（任意）
# ==============================================================================

class WeeklyReflectionTaskSummary < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :weekly_reflection
  #   このスナップショットは必ず WeeklyReflection に属する。
  #   null: false 制約があるため optional: false（デフォルト）のままでよい。
  belongs_to :weekly_reflection

  # belongs_to :task, optional: true
  #   元のタスクへの参照。
  #   on_delete: :nullify により元タスクが削除されると task_id が NULL になる。
  #   NULL になっても belongs_to バリデーションエラーにならないよう optional: true が必要。
  #   スナップショット（title 等）は task_id が NULL でも残り続けるため表示には影響しない。
  belongs_to :task, optional: true

  # ============================================================
  # Enum 定義
  # ============================================================

  # enum :priority（優先度）
  #   Task モデルと同じ定義にすることで、
  #   スナップショット保存時に Task の値をそのまま使い回せる。
  #
  #   生成されるメソッド:
  #     summary.must?   → priority == 0 か判定
  #     summary.should? → priority == 1 か判定
  #     summary.could?  → priority == 2 か判定
  #     WeeklyReflectionTaskSummary.must → priority == 0 のレコードを取得
  enum :priority, {
    must:   0,
    should: 1,
    could:  2
  }

  # enum :task_type（タスク種別）
  #   Task モデルと同じ定義。
  #
  #   0:normal  → 通常タスク（ユーザーが手動作成）
  #   1:habit   → 習慣関連タスク
  #   2:improve → 改善タスク（AI提案から生成）
  enum :task_type, {
    normal:  0,
    habit:   1,
    improve: 2
  }

  # ============================================================
  # バリデーション
  # ============================================================

  # title: タスク名のスナップショット（必須・100文字以内）
  #   Task モデルのバリデーションと合わせる。
  validates :title,
            presence: { message: "タスク名を入力してください" },
            length:   { maximum: 100, message: "タスク名は100文字以内で入力してください" }

  # priority: 優先度（必須・enum の値のみ許可）
  validates :priority,
            presence:  true,
            inclusion: {
              in:      priorities.keys,
              message: "優先度は Must / Should / Could から選択してください"
            }

  # task_type: 種別（enum の値のみ許可）
  validates :task_type,
            inclusion: {
              in:      task_types.keys,
              message: "が不正です"
            }

  # was_completed: 完了状態（true / false のみ許可・nil 不可）
  #   inclusion で [true, false] を指定することで nil を弾く。
  #   presence: true だけでは false（未完了）のとき「空白」と誤判定されるため
  #   inclusion を使うのが正しい。
  validates :was_completed,
            inclusion: {
              in:      [true, false],
              message: "は true か false を指定してください"
            }

  # UNIQUE 制約の Rails レベルでの二重保証
  #   DBレベルの部分インデックスに加え、Rails レベルでも重複を防ぐ。
  #   allow_nil: true → task_id が NULL の場合はこのバリデーションをスキップ
  #   （NULL 同士は PostgreSQL で「等しくない」扱いのため Rails 側でも除外する）
  validates :task_id,
            uniqueness: {
              scope:   :weekly_reflection_id,
              message: "は既にこの振り返りに含まれています"
            },
            allow_nil: true

  # ============================================================
  # スコープ
  # ============================================================

  # scope :completed_tasks
  #   振り返り時点で完了していたタスクのみを取得する。
  #   was_completed: true のレコードが対象。
  scope :completed_tasks,   -> { where(was_completed: true) }

  # scope :incompleted_tasks
  #   振り返り時点で未完了だったタスクのみを取得する。
  scope :incompleted_tasks, -> { where(was_completed: false) }

  # scope :by_priority
  #   優先度の昇順（must → should → could）でソートする。
  #   must(0) < should(1) < could(2) なので ASC で重要度順になる。
  scope :by_priority, -> { order(priority: :asc) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # create_all_for_reflection!(weekly_reflection)
  #
  # 【役割】
  #   1つの WeeklyReflection に紐づく当週の全タスクの
  #   スナップショットをまとめて作成する。
  #
  # 【呼び出しタイミング】
  #   WeeklyReflectionCompleteService#call の中でトランザクション内に呼ばれる。
  #   WeeklyReflectionHabitSummary.create_all_for_reflection! と同じパターン。
  #
  # 【対象タスク】
  #   振り返り対象週（week_start_date〜week_end_date）に存在した
  #   ユーザーの全タスク（論理削除済みも含む）のうち、
  #   ・当週に作成されたタスク（created_at が週範囲内）、または
  #   ・当週に期限があったタスク（due_date が週範囲内）、または
  #   ・当週に完了したタスク（completed_at が週範囲内）
  #   を対象とする。
  #
  #   「論理削除済みも含む」理由:
  #     振り返り完了後にタスクを削除するケースを考えると、
  #     削除前に振り返りを行っているため deleted_at が設定される前のタスクが対象。
  #     振り返り完了後の削除なので、振り返り完了時点では deleted_at は nil のはず。
  #     ただし安全のため「削除されていない」条件を入れる。
  #
  # 【冪等性の保証】
  #   WeeklyReflectionHabitSummary と同じく、
  #   「next if exists?」でスキップするため2回呼んでも重複しない。
  #
  # 【transaction の役割】
  #   1件でも save! が失敗すると全件ロールバックされる。
  #   「一部だけ保存された」という中途半端な状態を防ぐ。
  def self.create_all_for_reflection!(weekly_reflection)
    user       = weekly_reflection.user
    # ----------------------------------------------------------------
    # week_start / week_end を「時刻込み」で取得する理由:
    #   date 型のカラム（due_date）は日付のみだが、
    #   datetime 型のカラム（created_at / completed_at）は時刻情報が必要。
    #   beginning_of_day で「その日の00:00:00」
    #   end_of_day で「その日の23:59:59」にすることで
    #   その日に作成・完了したタスクを漏れなく取得できる。
    # ----------------------------------------------------------------
    week_start = weekly_reflection.week_start_date
    week_end   = weekly_reflection.week_end_date

    # ----------------------------------------------------------------
    # 【修正前の問題点】
    #   Arel の .constraints.reduce(:or) を使ったクエリは
    #   可読性が低く、Railsのバージョン差異で壊れるリスクがある。
    #
    # 【修正後の書き方】
    #   Rails 標準の named bind variables（:start / :end）を使った
    #   プレースホルダー形式にする。
    #
    #   named bind variables（:start のような書き方）を使う理由:
    #     同じ値（week_start / week_end）を複数箇所で使い回せる。
    #     ? プレースホルダーだと順番通りに引数を並べる必要があり
    #     間違えやすいが、名前付きなら順番を気にしなくてよい。
    #
    #   Arel を使わない理由:
    #     Arel は Rails の内部 API であり、バージョンアップで
    #     挙動が変わることがある。
    #     シンプルな OR 条件は SQL 文字列で書く方が安全で読みやすい。
    #
    #   SQLインジェクション対策:
    #     値を直接文字列に埋め込まず、プレースホルダー形式で渡すことで
    #     悪意ある入力値による SQL インジェクションを防ぐ。
    #     例: "due_date BETWEEN '#{week_start}' AND '#{week_end}'" は NG
    #         "due_date BETWEEN :start AND :end", { start:, end: } は OK
    # ----------------------------------------------------------------
    tasks = user.tasks
                .where(deleted_at: nil)
                .where(
                  "due_date BETWEEN :start AND :end
                   OR created_at BETWEEN :start_dt AND :end_dt
                   OR completed_at BETWEEN :start_dt AND :end_dt",
                  start:    week_start,
                  end:      week_end,
                  start_dt: week_start.beginning_of_day,
                  end_dt:   week_end.end_of_day
                )

    transaction do
      # ----------------------------------------------------------------
      # 【修正前の問題点】
      #   tasks.each は全件をメモリに一度に読み込む。
      #   タスクが数千件になるとメモリを大量消費してサーバーが不安定になる。
      #
      # 【修正後: find_each を使う理由】
      #   find_each はデフォルトで1000件ずつバッチ処理する。
      #   全件を一度にメモリに乗せないため、データ量が増えても安全。
      #   Rails のベストプラクティスとして推奨されている。
      #
      #   注意: find_each は ORDER BY を上書きするため、
      #   ループ内の処理に「順番」が必要な場合は each を使う。
      #   ここでは順番に依存しないため find_each で問題ない。
      # ----------------------------------------------------------------
      tasks.find_each do |task|
        # 冪等性の保証: 既に同じタスクのスナップショットが存在すればスキップ
        next if weekly_reflection.task_summaries.exists?(task: task)

        build_from_task(weekly_reflection, task).save!
      end
    end
  end

  # build_from_task(weekly_reflection, task)
  #
  # 【役割】
  #   Task のデータからスナップショットのインスタンスを組み立てる（DB保存はしない）。
  #   create_all_for_reflection! から呼ばれる内部メソッドだが、
  #   テストからも呼び出せるよう public クラスメソッドとして定義する。
  #
  # 【was_completed の判定ロジック】
  #   task.done? || task.archived? を「完了とみなす」条件にする。
  #   done(2) = 完了済み
  #   archived(3) = アーカイブ済み（完了後にアーカイブされた状態）
  #   どちらも「振り返り時点では完了していた」とみなすのが自然な設計。
  def self.build_from_task(weekly_reflection, task)
    # weekly_reflection.task_summaries.build を使うことで
    # weekly_reflection_id が自動的にセットされる。
    # これは WeeklyReflectionHabitSummary.build_from_habit と同じパターン。
    weekly_reflection.task_summaries.build(
      task:         task,
      title:        task.title,        # スナップショット: 振り返り時点のタスク名
      priority:     task.priority,     # スナップショット: 振り返り時点の優先度
      task_type:    task.task_type,    # スナップショット: 振り返り時点の種別
      was_completed: task.done? || task.archived?, # 振り返り時点での完了状態
      completed_at: task.completed_at, # スナップショット: 完了日時（nil の場合もある）
      due_date:     task.due_date      # スナップショット: 期限日（nil の場合もある）
    )
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # priority_label
  #   優先度を日本語ラベルに変換して返す。
  #   ビューで「Must」「Should」「Could」と表示するために使う。
  def priority_label
    case priority
    when "must"   then "Must"
    when "should" then "Should"
    when "could"  then "Could"
    else priority.to_s.capitalize
    end
  end

  # priority_color_class
  #   優先度に応じた Tailwind CSS のカラークラスを返す。
  #   ビューで優先度バッジの色を決定するために使う。
  #   インラインで条件分岐を書くより、モデルに集約した方が DRY になる。
  def priority_color_class
    case priority
    when "must"   then "bg-red-100 text-red-700"
    when "should" then "bg-blue-100 text-blue-700"
    when "could"  then "bg-green-100 text-green-700"
    else "bg-gray-100 text-gray-700"
    end
  end
end