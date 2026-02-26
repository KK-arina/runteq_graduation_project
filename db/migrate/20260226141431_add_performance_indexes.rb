# db/migrate/YYYYMMDDHHMMSS_add_performance_indexes.rb
#
# ============================================================
# Issue #29: パフォーマンス最適化 - インデックス追加（レビュー反映版）
# ============================================================
#
# 【レビュー指摘による変更内容】
#
#   変更前（初版）:
#     1. completed_at 単独インデックス
#     2. (user_id, completed_at) 複合インデックス
#
#   変更後（最終版）:
#     1. (user_id, week_start_date, completed_at) 3カラム複合インデックス1本のみ
#
# 【なぜ単独インデックスを削除するのか】
#   このアプリで completed_at を単独で検索するクエリは存在しない。
#   全てのクエリは「特定のユーザー」という条件（user_id）で始まるため、
#   completed_at 単独インデックスはDBに無駄なデータを持たせるだけになる。
#   インデックスは「読み取りを速くする代わりに書き込みを遅くする」トレードオフがある。
#   不要なインデックスは削除してトレードオフを最小化するのが正しい設計。
#
# 【なぜ3カラム複合インデックスにするのか】
#   アプリで発行される主要クエリを逆算すると以下の2パターンがある:
#
#   パターンA（locked? メソッド）:
#     WHERE user_id = ?
#     AND week_start_date = ?
#     AND completed_at IS NOT NULL
#
#   パターンB（index アクション）:
#     WHERE user_id = ?
#     AND completed_at IS NOT NULL
#     ORDER BY week_start_date DESC
#
#   (user_id, week_start_date, completed_at) の3カラム複合インデックスは
#   パターンAを完全にカバーし、パターンBも user_id で絞り込める。
#   インデックスの本数を増やさず1本で最大の効果を得る。
#
# 【複合インデックスの「左端の法則」】
#   複合インデックス (A, B, C) は以下の検索に使われる:
#     A のみの検索     → ✅ 使える（左端から順番に使う）
#     A + B の検索     → ✅ 使える
#     A + B + C の検索 → ✅ 使える（フル活用）
#     B のみの検索     → ❌ 使えない（左端のAをスキップできない）
#     C のみの検索     → ❌ 使えない
#   → user_id を必ず先頭に置くことで、全クエリパターンをカバーできる
#
# 【既存インデックスで対応済みのもの（このマイグレーションでは追加しない）】
#   - habit_records: (user_id, habit_id, record_date) UNIQUE ✅
#   - habit_records: user_id ✅
#   - habit_records: habit_id ✅
#   - habits: (user_id, deleted_at) ✅
#   - weekly_reflections: (user_id, week_start_date) UNIQUE ✅
#   - users: email UNIQUE ✅
#   - weekly_reflection_habit_summaries: weekly_reflection_id ✅

class AddPerformanceIndexes < ActiveRecord::Migration[7.2]
  # ============================================================
  # disable_ddl_transaction! とは？
  # ============================================================
  # PostgreSQL の algorithm: :concurrently（並行インデックス作成）は
  # トランザクション内では使用できない（PostgreSQL の仕様上の制約）。
  # disable_ddl_transaction! を宣言することで、このマイグレーション全体を
  # トランザクションなしで実行する。
  #
  # 【algorithm: :concurrently を使う理由】
  #   通常のインデックス作成はテーブル全体に「書き込みロック」をかける。
  #   本番環境でロックが発生すると、その間ユーザーが操作できなくなる（ダウンタイム）。
  #   :concurrently を指定すると、インデックス作成中も書き込みを受け付けるため
  #   ダウンタイムなしでインデックスを追加できる。
  #
  # 【注意点】
  #   トランザクションがないため、マイグレーション途中でエラーが起きた場合
  #   自動ロールバックされない。シンプルな内容に絞ることが推奨される。
  disable_ddl_transaction!

  def change
    # ──────────────────────────────────────────────────────────
    # インデックス: (user_id, week_start_date, completed_at) 3カラム複合インデックス
    # ──────────────────────────────────────────────────────────
    #
    # 【このインデックスがカバーするクエリ】
    #
    #   ① ApplicationController#locked?
    #     current_user.weekly_reflections
    #                 .for_week(last_week_start)   # WHERE week_start_date = ?
    #                 .completed                   # AND completed_at IS NOT NULL
    #                 .exists?
    #     → SQL: WHERE user_id=? AND week_start_date=? AND completed_at IS NOT NULL
    #     → 3カラム全部を使うため最も効率的に検索できる
    #
    #   ② WeeklyReflectionsController#index
    #     current_user.weekly_reflections
    #                 .completed                   # WHERE completed_at IS NOT NULL
    #                 .recent                      # ORDER BY week_start_date DESC
    #     → SQL: WHERE user_id=? AND completed_at IS NOT NULL ORDER BY week_start_date DESC
    #     → user_id（左端）で絞り込みができるため有効に使われる
    #
    # 【where: "completed_at IS NOT NULL" = 部分インデックス（Partial Index）】
    #   未完了（completed_at が NULL）のレコードはこのインデックスに含めない。
    #   振り返り未完了のレコードはロック判定などの「完了済み検索」に使われないため
    #   インデックスから除外することでファイルサイズを小さく保てる。
    #   → 書き込み時のインデックス更新コストが下がる
    #   → インデックスのメモリ使用量が減る
    add_index :weekly_reflections,
              [:user_id, :week_start_date, :completed_at],
              where: "completed_at IS NOT NULL",
              name: "idx_weekly_reflections_user_week_completed",
              algorithm: :concurrently
  end
end