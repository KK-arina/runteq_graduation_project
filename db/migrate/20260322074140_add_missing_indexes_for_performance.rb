# db/migrate/YYYYMMDDHHMMSS_add_missing_indexes_for_performance.rb
#
# ==============================================================================
# 【Issue #A-6: DBインデックス監査・最適化】
#
# 【スキーマ監査結果サマリー】
#
# ■ 追加が必要と判明したインデックス（このマイグレーションで対応）
#   ① notification_logs.deep_link_url
#      理由: ISSUEリスト #A-1 で設計済みだが CreateNotificationLogs に含まれず未設定。
#
#   ② tasks(user_id, status, deleted_at, due_date) 複合部分インデックス
#      理由: 「tasks.deleted_at 単体」は実クエリ
#            WHERE user_id=? AND status=0 AND deleted_at IS NULL ORDER BY due_date
#            に対して弱い（4条件クエリをカバーできない）。
#            複合インデックス + 部分インデックス（WHERE deleted_at IS NULL）が最適。
#
# ■ 追加不要と確認したインデックス（コメントのみ記載）
#   ③ weekly_reflections(user_id, week_start_date, completed_at) 部分インデックス
#      理由: idx_weekly_reflections_user_week_completed として schema.rb に既に存在する。
#            追加不要。
#
# 【なぜ change ではなく up/down を使うのか】
# disable_ddl_transaction! と algorithm: :concurrently を組み合わせる場合、
# change メソッドは rollback（db:rollback）時の逆操作を自動生成しようとするが、
# concurrently で作ったインデックスの削除も concurrently で行う必要があり、
# Rails の自動逆操作では対応できないケースがある。
# up/down を明示することで rollback 時の挙動を完全にコントロールでき、
# 本番環境での事故を防げる。
#
# 【disable_ddl_transaction! とは】
# Rails はデフォルトでマイグレーション全体をトランザクション内で実行する。
# これにより「途中でエラーが出ても中途半端な変更が残らない」安全性がある。
# しかし algorithm: :concurrently はトランザクション内で使用できない PostgreSQL の制約がある。
# disable_ddl_transaction! でこのマイグレーション全体のトランザクションを無効にする。
#
# 【algorithm: :concurrently とは】
# 通常の add_index は実行中にテーブル全体へ書き込みロックをかける。
# 本番稼働中に実行するとそのテーブルへの書き込みが全部止まってしまう。
# algorithm: :concurrently を使うと PostgreSQL が
# 「他の操作をブロックせずにインデックスを並行作成」してくれる。
# ==============================================================================
class AddMissingIndexesForPerformance < ActiveRecord::Migration[7.2]
  # algorithm: :concurrently を使うために必須の宣言
  # これがないと「PG::ActiveSqlTransaction: CREATE INDEX CONCURRENTLY
  # cannot run inside a transaction block」エラーが発生する
  disable_ddl_transaction!

  # ===========================================================================
  # up: マイグレーション適用時に実行される処理
  # ===========================================================================
  def up
    # =========================================================================
    # ① notification_logs.deep_link_url へのインデックス
    # =========================================================================
    #
    # 【このインデックスが必要な理由】
    # ISSUEリスト #A-1 で「INDEX: (deep_link_url) — 通知種別ごとの遷移先分析クエリ用」
    # として追加が要件に明記されていたが、CreateNotificationLogs マイグレーションに
    # 含まれておらず未設定のままだった。
    #
    # 【想定クエリ】
    #   WHERE deep_link_url = '/weekly_reflections/new'
    #   → 通知種別ごとの遷移先分析・デバッグ時に使用
    #
    # 【deep_link_url の prefix index は検討不要な理由】
    # HabitFlow の deep_link_url は '/weekly_reflections/new' のような
    # 短いパスのみ格納する設計であり、URLが長くなるケースがない。
    # prefix index（先頭N文字のみインデックス化）は不要と判断した。
    #
    # 【if_not_exists: true の理由】
    # 冪等性（何度実行しても同じ結果になる性質）を保証するため。
    # 既にインデックスが存在する場合でもエラーにならずスキップする。
    add_index :notification_logs,
              :deep_link_url,
              name: "index_notification_logs_on_deep_link_url",
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # ② tasks: 複合部分インデックス（アクティブタスク高速化）
    # =========================================================================
    #
    # 【なぜ deleted_at 単体インデックスではなく複合部分インデックスなのか】
    #
    # ▼ 実際のクエリパターン（TasksController#index）
    #   WHERE user_id = ?
    #     AND status = 0
    #     AND deleted_at IS NULL
    #   ORDER BY due_date ASC
    #
    # ▼ deleted_at 単体インデックスの問題点
    #   PostgreSQL はインデックスを使う際に「どの条件で絞り込むか」を考える。
    #   deleted_at IS NULL という条件だけインデックスに入れても、
    #   user_id・status・due_date の条件を処理できず
    #   結局テーブルを別途参照する「Heap Fetch」が大量発生する。
    #
    # ▼ 複合インデックス (user_id, status, deleted_at, due_date) の利点
    #   WHERE user_id = ? AND status = ? の絞り込みからORDER BY due_date まで
    #   インデックスだけで完結する（「Index Only Scan」が可能になる）。
    #
    # ▼ 部分インデックス（WHERE deleted_at IS NULL）の利点
    #   論理削除済みレコード（deleted_at IS NOT NULL）をインデックスから除外できる。
    #   通常、アクティブなタスクの方が圧倒的に多いため
    #   インデックスサイズが小さくなり読み取り速度が上がる。
    #
    # 【インデックス名について】
    # idx_tasks_active_tasks という名前で、
    # 「アクティブなタスクの検索に使うインデックス」であることを示している。
    add_index :tasks,
              [:user_id, :status, :deleted_at, :due_date],
              name: "idx_tasks_active_tasks",
              where: "deleted_at IS NULL",
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # ③ weekly_reflections: 追加不要（確認済み）
    # =========================================================================
    #
    # 【確認結果】
    # schema.rb に以下が既に存在することを確認済み:
    #   t.index ["user_id", "week_start_date", "completed_at"],
    #           name: "idx_weekly_reflections_user_week_completed",
    #           where: "(completed_at IS NOT NULL)"
    #
    # WeeklyReflectionsController の completed スコープと
    # User#locked? メソッドが使うクエリはこのインデックスでカバーされている。
    # if_not_exists: true で安全ではあるが、「確認した上で追加しない」方が
    # マイグレーション履歴として綺麗なため、コードは記述しない。
  end

  # ===========================================================================
  # down: db:rollback 時に実行される処理（up の逆操作）
  # ===========================================================================
  #
  # 【なぜ down を明示するのか】
  # change メソッドを使うと Rails が自動で逆操作を生成しようとするが、
  # concurrently で作ったインデックスの削除も concurrently で行う必要がある。
  # Rails の自動逆操作は concurrently を考慮しないため、
  # 本番環境での rollback 時に問題が起きるリスクがある。
  # down を明示することで rollback の挙動を完全にコントロールできる。
  def down
    # ① notification_logs.deep_link_url インデックスを削除
    # if_exists: true → インデックスが存在しない場合もエラーにならない（冪等性）
    remove_index :notification_logs,
                 name: "index_notification_logs_on_deep_link_url",
                 if_exists: true

    # ② tasks 複合部分インデックスを削除
    remove_index :tasks,
                 name: "idx_tasks_active_tasks",
                 if_exists: true
  end
end