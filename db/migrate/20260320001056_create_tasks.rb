# db/migrate/YYYYMMDDHHMMSS_create_tasks.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# tasks テーブルを新規作成する。
#
# 【このテーブルの役割】
# ユーザーが管理するタスクを保存する。
# AI が提案したタスクと、ユーザーが手動で作成したタスクを一緒に管理する。
#
# 【priority（優先度）の値】
#   0: Must   → 絶対にやる（最重要）
#   1: Should → できればやる（重要）
#   2: Could  → 余裕があればやる（任意）
#
# 【task_type（タイプ）の値】
#   0: 通常タスク   → 手動で作成した一般的なタスク
#   1: 習慣関連     → 特定の習慣と紐づいたタスク
#   2: 改善タスク   → AI の提案に基づく改善アクション
#
# 【status（状態）の値】
#   0: todo     → 未着手
#   1: doing    → 進行中
#   2: done     → 完了
#   3: archived → アーカイブ（完了後に整理した状態）
# ==============================================================================

class CreateTasks < ActiveRecord::Migration[7.2]
  def change
    create_table :tasks do |t|

      # ─────────────────────────────────────────────────────────────────────
      # user_id: このタスクを所有するユーザー（外部キー）
      # ─────────────────────────────────────────────────────────────────────
      # null: false → タスクは必ずユーザーに紐づく（孤立したタスクは作れない）
      # on_delete: :cascade → ユーザー削除時にタスクも一緒に削除される
      t.references :user,
                   null: false,
                   foreign_key: { on_delete: :cascade }

      # ─────────────────────────────────────────────────────────────────────
      # habit_id: 関連する習慣（オプション・外部キー）
      # ─────────────────────────────────────────────────────────────────────
      # task_type = 1（習慣関連タスク）のときに使用する
      # null: true → 通常タスクや改善タスクは習慣と紐づかなくてよいため NULL 許可
      # on_delete: :nullify → 習慣が削除されても、タスクは残す（habit_id が NULL になる）
      # index: false → 後で個別にインデックスを追加するため自動生成を抑制
      t.references :habit,
                   null: true,
                   foreign_key: { on_delete: :nullify },
                   index: false

      # ─────────────────────────────────────────────────────────────────────
      # title: タスク名
      # ─────────────────────────────────────────────────────────────────────
      # string 型: タスクのタイトル（最大100文字をモデル側でバリデーション）
      # null: false → タイトルなしのタスクは作れない
      t.string :title, null: false

      # ─────────────────────────────────────────────────────────────────────
      # priority: 優先度（0: Must / 1: Should / 2: Could）
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: Rails の enum で管理する
      # default: 1 → デフォルトは Should（中程度の優先度）
      # null: false → 必須項目
      t.integer :priority, null: false, default: 1

      # ─────────────────────────────────────────────────────────────────────
      # task_type: タスクの種類（0: 通常 / 1: 習慣関連 / 2: 改善）
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: Rails の enum で管理する
      # default: 0 → デフォルトは通常タスク
      # null: false → 必須項目
      t.integer :task_type, null: false, default: 0

      # ─────────────────────────────────────────────────────────────────────
      # status: タスクの状態（0: todo / 1: doing / 2: done / 3: archived）
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: Rails の enum で管理する
      # default: 0 → 新規作成時は「未着手（todo）」
      # null: false → 必須項目
      t.integer :status, null: false, default: 0

      # ─────────────────────────────────────────────────────────────────────
      # due_date: 期限日
      # ─────────────────────────────────────────────────────────────────────
      # date 型: 年月日のみを保存（時刻は不要）
      # NULL 許可: 期限なしのタスクも許可する
      t.date :due_date

      # ─────────────────────────────────────────────────────────────────────
      # estimated_hours: 見積もり作業時間
      # ─────────────────────────────────────────────────────────────────────
      # decimal 型: 小数点を含む時間数を正確に保存する
      # precision: 5 → 最大5桁（例: 999.99時間まで保存可能）
      # scale: 1     → 小数点以下1桁（0.5時間単位で入力できる）
      # NULL 許可: 任意入力
      t.decimal :estimated_hours, precision: 5, scale: 1

      # ─────────────────────────────────────────────────────────────────────
      # scheduled_at: 実施予定日時
      # ─────────────────────────────────────────────────────────────────────
      # datetime 型: アラーム通知に使用する日時
      # NULL 許可: 予定時刻なしのタスクも許可
      t.datetime :scheduled_at

      # ─────────────────────────────────────────────────────────────────────
      # alarm_enabled: アラーム通知のON/OFF
      # ─────────────────────────────────────────────────────────────────────
      # boolean 型: true = アラームあり / false = アラームなし
      # default: false → デフォルトはアラームなし
      # null: false → NULL は不可
      t.boolean :alarm_enabled, null: false, default: false

      # ─────────────────────────────────────────────────────────────────────
      # alarm_minutes_before: 何分前に通知するか
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: 0, 5, 10, 30, 60 などの分数を保存
      # NULL 許可: alarm_enabled = false のときは NULL でよい
      t.integer :alarm_minutes_before

      # ─────────────────────────────────────────────────────────────────────
      # completed_at: タスク完了日時
      # ─────────────────────────────────────────────────────────────────────
      # datetime 型: タスクを完了した日時を記録する
      # NULL     = 未完了
      # 日時あり = 完了済み
      t.datetime :completed_at

      # ─────────────────────────────────────────────────────────────────────
      # ai_generated: AI が自動生成したタスクか
      # ─────────────────────────────────────────────────────────────────────
      # boolean 型:
      #   true  → AI の提案から作られたタスク（削除には AI 提案モーダルが必要）
      #   false → ユーザーが手動で作成したタスク（削除確認モーダルから削除可能）
      # default: false → 通常はユーザー作成
      # null: false → NULL は不可
      t.boolean :ai_generated, null: false, default: false

      # ─────────────────────────────────────────────────────────────────────
      # deleted_at: 論理削除用タイムスタンプ
      # ─────────────────────────────────────────────────────────────────────
      # NULL     = 有効なタスク
      # 日時あり = 論理削除済み（一覧から非表示）
      t.datetime :deleted_at

      # created_at・updated_at を自動で追加する
      t.timestamps
    end

    # ─────────────────────────────────────────────────────────────────────────
    # INDEX の追加（4種類）
    # ─────────────────────────────────────────────────────────────────────────

    # INDEX 1: (alarm_enabled, scheduled_at)
    # GoodJob が「アラームが有効で、特定時刻に通知すべきタスク」を検索するためのインデックス
    # WHERE alarm_enabled = true AND scheduled_at <= ? のクエリに使用
    add_index :tasks,
              [:alarm_enabled, :scheduled_at],
              name: 'index_tasks_on_alarm_enabled_and_scheduled_at'

    # INDEX 2: (user_id, alarm_enabled)
    # 「このユーザーのアラーム設定済みタスク一覧」を取得するためのインデックス
    # WHERE user_id = ? AND alarm_enabled = true のクエリに使用
    add_index :tasks,
              [:user_id, :alarm_enabled],
              name: 'index_tasks_on_user_id_and_alarm_enabled'

    # INDEX 3: (user_id, status, due_date)
    # タスク一覧画面で「このユーザーの未完了タスクを期限順で表示」するためのインデックス
    # WHERE user_id = ? AND status = 0 ORDER BY due_date ASC のクエリに使用
    add_index :tasks,
              [:user_id, :status, :due_date],
              name: 'index_tasks_on_user_id_and_status_and_due_date'

    # INDEX 4: (user_id, scheduled_at)
    # 「このユーザーの今週の予定タスク一覧」を取得するためのインデックス
    # WHERE user_id = ? AND scheduled_at BETWEEN ? AND ? のクエリに使用
    add_index :tasks,
              [:user_id, :scheduled_at],
              name: 'index_tasks_on_user_id_and_scheduled_at'
  end
end