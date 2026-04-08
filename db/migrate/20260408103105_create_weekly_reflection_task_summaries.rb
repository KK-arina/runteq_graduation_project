# db/migrate/YYYYMMDDHHMMSS_create_weekly_reflection_task_summaries.rb
#
# ==============================================================================
# weekly_reflection_task_summaries テーブルの作成
# ==============================================================================
#
# 【このマイグレーションの目的】
#   週次振り返り完了時に「当週のタスク実績スナップショット」を保存するテーブルを作成する。
#
# 【なぜスナップショットテーブルが必要なのか】
#   タスクは後から削除（deleted_at による論理削除）される。
#   しかし「振り返り詳細ページ（15番）」では、振り返りを行った時点のタスク一覧を
#   正確に表示し続ける必要がある。
#
#   → タスクが削除されても「振り返り時点のコピー」がこのテーブルに残るため、
#     詳細ページが壊れない。
#
# 【習慣スナップショット（weekly_reflection_habit_summaries）との設計方針の統一】
#   既存の WeeklyReflectionHabitSummary と同じ「スナップショット」設計を採用する。
#   タスクが後から変更・削除されても、振り返り時点のデータが保持される。
#
# 【カラム設計の説明】
#   weekly_reflection_id : どの振り返りのスナップショットか（外部キー）
#   task_id              : 元のタスクへの参照（削除時は NULL になる・任意）
#   title                : タスク名のスナップショット（振り返り時点のコピー）
#   priority             : 優先度のスナップショット（0:must / 1:should / 2:could）
#   task_type            : 種別のスナップショット（0:通常 / 1:習慣関連 / 2:改善）
#   was_completed        : 振り返り時点での完了状態（true=完了 / false=未完了）
#   completed_at         : 完了日時のスナップショット（未完了の場合は NULL）
#   due_date             : 期限日のスナップショット（任意）
#
# 【インデックス設計】
#   INDEX(weekly_reflection_id)           : 振り返りに紐づくタスク一覧を高速取得
#   INDEX(task_id)                        : 元タスクからの逆引き検索用
#   UNIQUE(weekly_reflection_id, task_id) : 同じ振り返りに同じタスクが重複しないよう保証
#                                           ただし task_id が NULL の場合は除外（NULLS 非対象）
#
# 【外部キー制約】
#   weekly_reflection_id → weekly_reflections.id（CASCADE: 振り返り削除時にサマリーも削除）
#   task_id              → tasks.id（NULLIFY: タスク削除時は task_id を NULL にして記録を保持）
# ==============================================================================

class CreateWeeklyReflectionTaskSummaries < ActiveRecord::Migration[7.2]
  def change
    create_table :weekly_reflection_task_summaries do |t|
      # ── 外部キー ─────────────────────────────────────────────────────────────
      #
      # weekly_reflection_id: NOT NULL（必ずどこかの振り返りに属する）
      # null: false を指定することでDBレベルでも空を防ぐ
      t.references :weekly_reflection,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      #   on_delete: :cascade の意味:
      #   親の weekly_reflections レコードが削除されたとき、
      #   それに紐づくこのテーブルのレコードも自動で削除される。
      #   振り返りが消えたならスナップショットも不要なため CASCADE が適切。

      # task_id: NULL 許容（元のタスクが削除されると NULL になる）
      # null: true を明示しないが references のデフォルトは null: true
      t.references :task,
                   null: true,
                   foreign_key: { on_delete: :nullify }
      #   on_delete: :nullify の意味:
      #   元の tasks レコードが削除されたとき、task_id を NULL に更新する。
      #   こうすることでスナップショット自体は残り、タイトル等を引き続き表示できる。
      #   （CASCADE にするとタスク削除時にスナップショットも消えてしまう = NG）

      # ── スナップショットカラム ────────────────────────────────────────────────
      #
      # title: タスク名のコピー
      #   null: false → タスク名は必須（Task モデルでも presence バリデーションあり）
      t.string :title, null: false

      # priority: 優先度のコピー（0:must / 1:should / 2:could）
      #   null: false, default: 1 → Task モデルの default と合わせる
      t.integer :priority, null: false, default: 1

      # task_type: 種別のコピー（0:通常 / 1:習慣関連 / 2:改善）
      #   null: false, default: 0
      t.integer :task_type, null: false, default: 0

      # was_completed: 振り返り完了時点での「完了しているか」フラグ
      #   null: false, default: false → 未完了をデフォルトとする
      #   このフラグが「スナップショット」の核心。後からタスクの状態が変わっても
      #   振り返り時点の正確な状態がここに記録されている。
      t.boolean :was_completed, null: false, default: false

      # completed_at: タスクを完了した日時のコピー（未完了の場合は NULL）
      #   null: true（未完了タスクには completed_at がない）
      t.datetime :completed_at

      # due_date: 期限日のコピー（期限なしタスクは NULL）
      #   null: true（期限は任意項目）
      t.date :due_date

      # ── タイムスタンプ ────────────────────────────────────────────────────────
      # created_at, updated_at を自動生成する Rails の慣習カラム
      t.timestamps
    end

    # ── 追加インデックス ──────────────────────────────────────────────────────
    #
    # UNIQUE インデックス: (weekly_reflection_id, task_id)
    #   同じ振り返りに同じタスクのスナップショットが重複して作られないよう保証する。
    #
    #   WHERE task_id IS NOT NULL の理由:
    #     PostgreSQL では NULL 同士は「等しくない」と扱うため、
    #     UNIQUE 制約に NULL が含まれると重複チェックが効かない。
    #     task_id が NULL のレコードが複数できてしまう可能性を防ぐために
    #     「task_id が NULL でないレコードだけ」に UNIQUE を適用する部分インデックスにする。
    add_index :weekly_reflection_task_summaries,
              [:weekly_reflection_id, :task_id],
              unique: true,
              where: "task_id IS NOT NULL",
              name: "idx_wr_task_summaries_on_wr_id_and_task_id"
  end
end