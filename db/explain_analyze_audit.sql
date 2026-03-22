-- ==============================================================================
-- Issue #A-6: DBインデックス監査用 EXPLAIN ANALYZE スクリプト
-- ==============================================================================
-- 【使い方】
-- docker compose exec web bin/rails db でPostgreSQLコンソールを開き、
-- 下記のSQLを1つずつ実行して「Seq Scan」が出ていないかを確認する。
--
-- 【読み方】
-- ・Index Scan / Index Only Scan → ✅ インデックスが使われている（良い）
-- ・Seq Scan（Sequential Scan）  → ❌ 全件スキャン（インデックス未使用）
--
-- 【注意】
-- EXPLAIN ANALYZE は実際にクエリを実行するため本番DBでの実行に注意。
-- EXPLAIN のみ（ANALYZEなし）なら実行せず計画だけ確認できる。
-- ==============================================================================


-- ==========================================================================
-- 1. habit_records: ダッシュボードの週次集計クエリ
-- ==========================================================================
-- 【想定インデックス】index_habit_records_on_user_id_and_record_date
-- 【期待結果】Index Scan または Index Only Scan
EXPLAIN ANALYZE
SELECT habit_id, COUNT(*)
FROM habit_records
WHERE user_id = 1
  AND record_date BETWEEN '2026-03-09' AND '2026-03-15'
  AND completed = true
GROUP BY habit_id;


-- ==========================================================================
-- 2. tasks: タスク一覧クエリ（複合部分インデックスの効果確認）
-- ==========================================================================
-- 【想定インデックス】idx_tasks_active_tasks（今回追加）
-- 【期待結果】Index Only Scan（インデックスだけで完結するため最速）
--
-- ★ レビュー指摘④：追加すべきクエリ
-- 一覧画面の基本クエリ。インデックスが効かないと全件スキャンになる。
EXPLAIN ANALYZE
SELECT *
FROM tasks
WHERE user_id = 1
  AND deleted_at IS NULL;


-- ==========================================================================
-- 3. tasks: ステータス・期限フィルタ付きクエリ
-- ==========================================================================
-- 【想定インデックス】idx_tasks_active_tasks（今回追加）
-- 【期待結果】Index Scan
EXPLAIN ANALYZE
SELECT *
FROM tasks
WHERE user_id = 1
  AND status = 0
  AND deleted_at IS NULL
ORDER BY due_date ASC;


-- ==========================================================================
-- 4. notification_logs: ユーザー別通知履歴クエリ
-- ==========================================================================
-- 【想定インデックス】index_notification_logs_on_user_id_and_created_at
-- 【期待結果】Index Scan
EXPLAIN ANALYZE
SELECT *
FROM notification_logs
WHERE user_id = 1
ORDER BY created_at DESC
LIMIT 20;


-- ==========================================================================
-- 5. notification_logs: deep_link_url 検索クエリ
-- ==========================================================================
-- 【想定インデックス】index_notification_logs_on_deep_link_url（今回追加）
-- 【期待結果】Index Scan
EXPLAIN ANALYZE
SELECT *
FROM notification_logs
WHERE deep_link_url = '/weekly_reflections/new';


-- ==========================================================================
-- 6. weekly_reflections: ロック判定クエリ（User#locked? で毎リクエスト実行）
-- ==========================================================================
-- 【想定インデックス】idx_weekly_reflections_user_week_completed（既存）
-- 【期待結果】Index Scan
EXPLAIN ANALYZE
SELECT *
FROM weekly_reflections
WHERE user_id = 1
  AND week_start_date = '2026-03-09'
  AND completed_at IS NOT NULL;


-- ==========================================================================
-- 7. weekly_reflections: UNIQUE制約確認
-- ==========================================================================
-- 【想定インデックス】index_weekly_reflections_on_user_id_and_week_start_date (UNIQUE)
-- 【期待結果】Index Scan
EXPLAIN ANALYZE
SELECT *
FROM weekly_reflections
WHERE user_id = 1
  AND week_start_date = '2026-03-09';