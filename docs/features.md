## 🚀 本リリース実装済み機能

<br>

### #A-1: 本リリース用 DB マイグレーション

<br>

**ブランチ:** `feature/A-1-db-migrations`<br>
**完了日:** 2026-03-20<br>
**対象:** MVP版スキーマからの全差分をマイグレーションファイルとして実装

<br>

#### 既存テーブルへのカラム追加

<br>

| テーブル | 追加カラム | 目的 |
|:---|:---|:---|
| `users` | `provider` / `uid` | OmniAuth（Google/LINE）ログイン対応 |
| `users` | `line_user_id` | LINE Messaging API 通知送信用 |
| `users` | `first_login_at` | オンボーディング完了判定（NULL=未完了） |
| `habits` | `measurement_type` | チェック型(0) / 数値型(1) の区別 |
| `habits` | `unit` | 数値型習慣の単位（分・冊・km など） |
| `habits` | `current_streak` / `longest_streak` | ストリーク（継続日数）管理 |
| `habits` | `allow_rest_mode` | お休みモード中のストリーク維持フラグ |
| `habits` | `archived_at` | 卒業習慣のアーカイブ（`deleted_at` とは別管理） |
| `habits` | `color` / `icon` / `position` | UI カスタマイズ・並び替え |
| `habit_records` | `numeric_value` | 数値型習慣の実績値（decimal型・精度保証） |
| `habit_records` | `memo` | 日次メモ（AI 分析精度向上に活用） |
| `habit_records` | `is_manual_input` | 自動記録 vs 手動修正の区別 |
| `habit_records` | `deleted_at` | 論理削除（統計整合性の保持） |
| `weekly_reflections` | `year` / `week_number` | ISO週番号による重複防止 |
| `weekly_reflections` | `mood` | 気分スコア（1〜5） |
| `weekly_reflections` | `direct_reason` / `background_situation` | 構造化された振り返り入力 |

<br>

#### 新規作成テーブル

<br>

| テーブル | 役割 | 主な設計ポイント |
|:---|:---|:---|
| `habit_excluded_days` | 習慣ごとの除外曜日 | UNIQUE制約(habit_id, day_of_week) |
| `tasks` | タスク管理（Must/Should/Could） | 4種インデックス・ai_generated フラグ |
| `ai_analyses` | AI分析結果の保存 | is_latest フラグ・input_snapshot(jsonb)・UNIQUE制約2種 |
| `user_settings` | ユーザー設定の一元管理 | 通知/お休みモード/AIコスト制御 |
| `user_purposes` | PMVV目標のバージョン管理 | is_active フラグ・analysis_state enum |
| `habit_templates` | オンボーディング用マスタ | カテゴリ別テンプレート |
| `notification_logs` | 通知送信履歴 | deep_link_url・ポリモーフィック関連 |
| `push_subscriptions` | Web Push購読情報（将来用） | 機能実装は後続リリース |
| `password_reset_tokens` | パスワードリセット | token_digest（ハッシュ化保存）・多重発行防止 |

<br>

### #A-2: 本番環境デプロイ（Render + Neon PostgreSQL）

<br>

**ブランチ:** `feature/A-2-production-deploy`<br>
**完了日:** 2026-03-20<br>
**本番URL:** https://habitflow-web.onrender.com

<br>

#### 採用構成

<br>

| 役割 | サービス | 理由 |
|:---|:---|:---|
| Web サービス | Render（無料プラン） | GitHub 連携で自動デプロイ・クレカ不要 |
| データベース | Neon Serverless PostgreSQL 16 | 永続無料・Render 内蔵 DB の90日削除問題を回避 |
| リージョン | Singapore（両サービス統一） | Web ↔ DB 間のレイテンシを最小化 |

<br>

#### 主な設定内容

<br>

| ファイル | 変更内容 |
|:---|:---|
| `render.yaml` | Neon 対応に全面書き換え・puma 直接起動・GoodJob Worker 準備（コメントアウト） |
| `config/puma.rb` | Worker 設定・`on_worker_boot`・`Integer()` 型安全変換を追加 |
| `bin/docker-entrypoint` | `db:prepare` → `db:migrate` に変更（Neon は CREATE DATABASE 権限なし） |

<br>

#### 環境変数設定（Render）

<br>

| Key | 管理方法 | 用途 |
|:---|:---|:---|
| `RAILS_ENV` | render.yaml に記載 | 本番環境モード指定 |
| `DATABASE_URL` | Render ダッシュボードで手動設定 | Neon 接続文字列 |
| `RAILS_MASTER_KEY` | Render ダッシュボードで手動設定 | credentials 復号キー |
| `RAILS_LOG_TO_STDOUT` | render.yaml に記載 | Render Logs タブへの出力 |
| `RAILS_SERVE_STATIC_FILES` | render.yaml に記載 | CSS/JS の直接配信 |
| `WEB_CONCURRENCY` | render.yaml に記載 | Puma Worker 数（2） |

<br>

### #A-3: GoodJob 導入・非同期処理基盤構築

<br>

**ブランチ:** `feature/A-3-good-job`<br>
**完了日:** 2026-03-20<br>
**概要:** Redis 不要の非同期ジョブ処理エンジン GoodJob を導入し、<br>
AI 分析・通知・ストリーク計算等のバックグラウンド処理基盤を構築。<br>

<br>

#### 技術選定の理由

<br>

| 技術 | 採用理由 |
|:---|:---|
| GoodJob | PostgreSQL のみで動作。Redis 不要のため Render 無料プランと相性が良い |
| Sidekiq (不採用) | 高性能だが Redis が必要。Render 無料プランではコスト増になる |

<br>

#### GoodJob の設定

<br>

| 設定項目 | 値 | 理由 |
|:---|:---|:---|
| `execution_mode` (development) | `:async` | Web プロセス内でスレッド実行。Docker 1台で完結 |
| `execution_mode` (production) | `:external` | Render の Worker サービスが別プロセスで実行 |
| `max_threads` | `3` | Web(6) + Worker(3) = 9 コネクション。Neon 無料プラン上限以内 |
| `poll_interval` | `30秒` | DB への SELECT 頻度と遅延のバランス点 |
| `cleanup_preserved_jobs_before_seconds_ago` | `86400秒（24時間）` | Neon 無料プランの容量制限に対応 |

<br>

#### cron ジョブ一覧（JST 基準）

<br>

| ジョブクラス | cron (UTC) | JST 実行時刻 | 役割 |
|:---|:---:|:---:|:---|
| `StreakCalculationJob` | `5 19 * * *` | 毎日 AM4:05 | ストリーク計算（#B-3 で本実装） |
| `DailyNotificationCountResetJob` | `5 15 * * *` | 毎日 00:05 | 通知カウントリセット |
| `MonthlyAiCountResetJob` | `0 15 * * *` | 毎日 00:00 | 月初のみ AI 使用回数リセット |
| `GoodJob::CleanupJobsJob` | `0 18 * * *` | 毎日 03:00 | 完了済みジョブ削除 |

<br>

月次リセットは cron 式を毎日実行にして、ジョブ内で `Time.current.day == 1` をチェックする方式を採用。<br>
UTC 変換による cron 式の複雑化を避けるための設計。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` | `gem "good_job"` 追加（4.x 系・バージョン固定なし） |
| `Gemfile` | `gem "minitest", "~> 5.1"` 追加（GoodJob が 6.x を引き込む問題を防止） |
| `config/application.rb` | `config.active_job.queue_adapter = :good_job` 追加 |
| `config/initializers/good_job.rb` | 新規作成（`Rails.application.configure` 形式・cron 4件） |
| `config/environments/development.rb` | `execution_mode = :async` 追加 |
| `config/environments/production.rb` | `execution_mode = :external` 追加 |
| `config/environments/test.rb` | `queue_adapter = :test` 追加 |
| `config/routes.rb` | GoodJob ダッシュボードを catch-all より前にマウント |
| `render.yaml` | Worker サービスは Render Free プランで利用不可のため未使用。GoodJob は `execution_mode: :async` で Web プロセス内で実行 |
| `app/jobs/application_job.rb` | `retry_on` / `discard_on` を追加 |
| `app/jobs/streak_calculation_job.rb` | 新規作成（#B-3 で本実装予定） |
| `app/jobs/daily_notification_count_reset_job.rb` | 新規作成 |
| `app/jobs/monthly_ai_count_reset_job.rb` | 新規作成 |
| `app/jobs/hello_good_job.rb` | 動作確認用（確認後削除可） |
| `db/migrate/YYYYMMDDHHMMSS_create_good_jobs.rb` | GoodJob 4.x 用テーブル5種を作成 |

<br>

#### 作成された DB テーブル

<br>

| テーブル名 | 役割 |
|:---|:---|
| `good_jobs` | ジョブキュー本体 |
| `good_job_batches` | バッチ処理管理 |
| `good_job_executions` | 実行履歴 |
| `good_job_processes` | Worker プロセス管理 |
| `good_job_settings` | GoodJob 内部設定 |

<br>

#### GoodJob ダッシュボード

<br>

| 環境 | URL | 認証 |
|:---|:---|:---|
| development | `http://localhost:3000/good_job` | なし |
| production | `https://habitflow-web.onrender.com/good_job` | Basic 認証（環境変数設定時のみ公開） |

<br>

本番環境での公開には Render ダッシュボードで以下の環境変数を設定する。<br>
```
GOOD_JOB_LOGIN=（任意のユーザー名）
GOOD_JOB_PASSWORD=（強力なパスワード）
```

<br>

#### Render Worker サービス設定

<br>

Render の Free プランは Background Worker が利用できないため（最低 $7/月）、Worker サービスは使用しない。<br>
GoodJob は `execution_mode: :async` を設定することで Web プロセス内でジョブを処理する。

<br>

将来有料プランに移行する場合は以下を `render.yaml` に追加する:<br>
```yaml
- type: worker
  name: habitflow-worker
  runtime: docker
  region: singapore
  plan: starter
  startCommand: bundle exec good_job start --max-threads=3
```
<br>

`--max-threads=3` を明示する理由:<br>
GoodJob のデフォルトスレッド数は 5。明示しないと Neon 無料プランの DB コネクション上限を超えるリスクがある。

<br>

### #A-4: Resend メール送信設定

<br>

**ブランチ:** `feature/A-4-resend-mailer`<br>
**完了日:** 2026-03-22<br>
**概要:** パスワードリセット・CSVエクスポート完了通知・週次レポートメールに使用する<br>
Resend をAction Mailerに接続。開発環境では letter_opener でブラウザプレビュー確認。

<br>

#### 技術選定の理由

<br>

| 技術 | 採用理由 |
|:---|:---|
| Resend | クレカ不要・月3,000通無料・Rails用gem公式提供。SendGrid（クレカ必要）・Mailgun（設定複雑）より優位 |
| letter_opener | 開発環境での無駄な送信を防止。ブラウザでメール内容をプレビュー確認できる |

<br>

#### Action Mailer 設定内容

<br>

| 環境 | delivery_method | 説明 |
|:---|:---|:---|
| development | `:letter_opener` | 実際には送信せず `tmp/letter_opener/` にHTMLとして保存 |
| production | `:resend` | Resend APIを経由して実際にメール送信 |

<br>

#### 本番環境の設定

<br>

| 設定項目 | 値 | 理由 |
|:---|:---|:---|
| `delivery_method` | `:resend` | Resend API経由でメール送信 |
| `raise_delivery_errors` | `true` | 送信失敗時に例外を発生させてエラーを検知 |
| `default_url_options` | `host: "habitflow-web.onrender.com"` | パスワードリセットメール内リンクのURLを正しく生成 |
| `asset_host` | `"https://habitflow-web.onrender.com"` | メール内画像・CSSの絶対URLを生成 |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` | `gem "resend"` / `gem "letter_opener"` 追加 |
| `config/initializers/resend.rb` | 新規作成（APIキーを環境変数から初期化） |
| `config/environments/production.rb` | Action Mailer本番設定追加（delivery_method・raise_delivery_errors・default_url_options・asset_host）<br>GoodJob execution_mode を `:external` → `:async` に変更（Render Worker非対応のため）<br>GoodJob max_threads を `2` に設定（Freeプランリソース制約対応） |
| `config/environments/development.rb` | letter_opener設定追加 |
| `app/mailers/application_mailer.rb` | fromアドレスを `HabitFlow <onboarding@resend.dev>` に設定 |
| `app/mailers/test_mailer.rb` | 新規作成（動作確認用・将来のMailer実装の参考） |
| `render.yaml` | `RESEND_API_KEY` 環境変数を追加（`sync: false`）<br>Workerセクションをコメントアウト（Render Freeプランは Worker 非対応） |

<br>

#### Render 環境変数設定

<br>

| Key | 管理方法 | 用途 |
|:---|:---|:---|
| `RESEND_API_KEY` | Render ダッシュボードで手動設定 | Resend API認証キー |

<br>

#### GoodJob execution_mode の変更理由

<br>

#A-3 では production の execution_mode を `:external`（別Workerプロセス）に設定していたが、<br>
Render の Background Worker は Free プランが存在しない（最低 $7/月 の Starter プラン）ため、<br>
`:async`（Webプロセス内でバックグラウンドスレッドを実行）に変更した。<br>

<br>

| モード | 動作 | 採用環境 |
|:---|:---|:---|
| `:async` | Webプロセス内のスレッドでジョブを実行 | 本番（Render Free）・開発 |
| `:external` | 別プロセス（Worker）でジョブを実行 | 有料プラン移行時 |

<br>

> ⚠️ `:async` モードはWebサーバーと同一プロセスのため、<br>
> 重い処理（CSV生成・AI分析）はWebレスポンスに影響する可能性があります。<br>
> 有料プランへの移行時は `:external` に戻し、render.yaml の Worker 設定を有効化してください。

<br>

### #A-5: habit_templates シードデータ・モデル作成

<br>

**ブランチ:** `feature/A-5-habit-templates-seed`<br>
**完了日:** 2026-03-22<br>
**概要:** オンボーディングで使用する習慣テンプレートのマスタデータを実装。<br>
カテゴリ別18件のプリセットデータを登録し、ユーザーがスムーズに習慣を選択できるようにする。

<br>

#### 登録テンプレート一覧（18件）

<br>

| カテゴリ | 件数 | 習慣名 |
|:---|:---|:---|
| 健康（health） | 5件 | 読書・瞑想・睡眠日記・水を飲む・早起き |
| フィットネス（fitness） | 5件 | 筋トレ・ジョギング・ストレッチ・ウォーキング・体重記録 |
| 学習（study） | 4件 | 英語学習・プログラミング学習・読書（学習）・オンライン講座 |
| マインド（mind） | 4件 | 日記・感謝リスト・呼吸法・デジタルデトックス |

<br>

#### 作成ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/habit_template.rb` | 新規作成（enum / バリデーション / スコープ） |
| `db/seeds.rb` | habit_templates シードデータを Step 8 として末尾に追記 |

<br>

#### HabitTemplate モデルの設計

<br>

| 設定 | 内容 |
|:---|:---|
| `measurement_type` enum | `check_type`(0) / `numeric_type`(1) |
| `category` enum | `health`(0) / `fitness`(1) / `study`(2) / `mind`(3) / `other`(4) |
| バリデーション | name（必須・100文字以内）/ default_weekly_target（1〜7の整数） |
| スコープ | `active` / `ordered` / `active_ordered` |

<br>

#### 設計上の判断

<br>

- `find_or_initialize_by` + `assign_attributes` + `save!` を採用<br>
  → 既存レコードも更新されるため、description や sort_order の修正が本番 DB に反映される<br>
  → `find_or_create_by!` のブロック方式では既存データが更新されないため不採用<br>
- slug カラムの追加は見送り<br>
  → schema.rb に定義がなく #A-1 のスコープ外。`name + category` の複合キーで一意性を保証できる<br>
- `enum _prefix: true` は見送り<br>
  → 使用箇所が生まれる #H-5（オンボーディング拡張）のタイミングで改めて検討する（YAGNI原則）

<br>

### #A-6: DBインデックス監査・最適化

<br>

**ブランチ:** `feature/A-6-db-index-audit`<br>
**完了日:** 2026-03-22<br>
**概要:** データ量が増加しやすいテーブルのインデックスを実測クエリで確認し、<br>
不足インデックスを追加。Bullet / rack-mini-profiler によるN+1監視基盤を構築。

<br>

#### スキーマ監査結果

<br>

| 対象 | 結果 | 内容 |
|:---|:---:|:---|
| `habit_records(user_id, record_date)` | ✅ 設定済み | ダッシュボード週次集計クエリに使用 |
| `habit_records(user_id, habit_id, record_date)` UNIQUE | ✅ 設定済み | 1日1件制約をDBレベルで保証 |
| `tasks(user_id, status, due_date)` | ✅ 設定済み | タスク一覧フィルタクエリに使用 |
| `notification_logs(user_id, created_at)` | ✅ 設定済み | 通知履歴・件数チェックに使用 |
| `weekly_reflections(user_id, week_start_date)` UNIQUE | ✅ 設定済み | 同一週の重複振り返りを防止 |
| `idx_weekly_reflections_user_week_completed` 部分INDEX | ✅ 設定済み | `User#locked?` の毎リクエスト実行クエリに使用 |
| `notification_logs.deep_link_url` | ❌ **未設定→追加** | #A-1設計済みだが未設定だった |
| `tasks` 複合部分インデックス | ❌ **未設定→追加** | `deleted_at IS NULL` フィルタ付き4条件クエリを最適化 |

<br>

#### 追加インデックス詳細

<br>

| インデックス名 | 対象 | 種別 | 理由 |
|:---|:---|:---|:---|
| `index_notification_logs_on_deep_link_url` | `notification_logs.deep_link_url` | 通常INDEX | 通知種別ごとの遷移先分析クエリを高速化 |
| `idx_tasks_active_tasks` | `tasks(user_id, status, deleted_at, due_date)` WHERE deleted_at IS NULL | 複合部分INDEX | `deleted_at IS NULL` を含む4条件クエリを Index Only Scan で完結させる |

<br>

#### なぜ `deleted_at` 単体ではなく複合部分インデックスなのか

<br>

実際のクエリパターン（TasksController#index）:<br>
```sql
WHERE user_id = ? AND status = 0 AND deleted_at IS NULL ORDER BY due_date ASC
```

<br>

`deleted_at` 単体インデックスでは `user_id` / `status` / `due_date` の条件を処理できず、<br>
結局テーブルを別途参照する「Heap Fetch」が大量発生する。<br>
`(user_id, status, deleted_at, due_date)` の複合インデックス + `WHERE deleted_at IS NULL` の部分インデックスにより<br>
インデックスだけで完結する「Index Only Scan」が可能になり最速になる。

<br>

#### マイグレーション設計のポイント

<br>

| 設計 | 内容 |
|:---|:---|
| `disable_ddl_transaction!` | 本番環境での書き込みロック回避（`algorithm: :concurrently` の使用に必須） |
| `up/down` 形式 | `change` 形式では rollback 時に concurrently での削除が保証されないため明示 |
| `if_not_exists: true` | 冪等性の確保（何度実行しても安全） |

<br>

#### 導入・設定ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` | `gem "rack-mini-profiler", require: false` 追加（development グループ） |
| `config/initializers/bullet.rb` | 新規作成（N+1検出設定・`unused_eager_loading_enable` 含む） |
| `config/initializers/rack_mini_profiler.rb` | 新規作成（Turbo Drive サポート・rescue LoadError 対応） |
| `db/migrate/YYYYMMDDHHMMSS_add_missing_indexes_for_performance.rb` | 新規作成（2インデックス追加） |
| `db/explain_analyze_audit.sql` | 新規作成（監査用 EXPLAIN ANALYZE スクリプト7件） |
| `test/db/index_audit_test.rb` | 新規作成（インデックス存在確認テスト・部分INDEX where条件まで検証） |

<br>

### #A-7: DBトランザクション設計・複数テーブル更新の整合性保証

<br>

**ブランチ:** `feature/A-7-transaction-design`<br>
**完了日:** 2026-03-22<br>
**概要:** 複数テーブルを横断する更新処理をトランザクションで保護し、<br>
部分的な失敗による中途半端なDB状態を防ぐ基盤を構築。<br>
ビジネスロジックをサービスクラスに集約し、コントローラーを軽量化した。

<br>

#### トランザクション保護対象フロー

<br>

| フロー | 保護対象テーブル | サービスクラス |
|:---|:---|:---|
| 振り返り完了 | `weekly_reflections` + `weekly_reflection_habit_summaries` | `WeeklyReflectionCompleteService` |
| 習慣記録保存 | `habit_records`（将来: + `habits.current_streak`） | `HabitRecordSaveService` |
| ユーザー退会 | `users` + `password_reset_tokens` + `user_settings` | `UserDestroyService` |
| AI提案確定（骨格） | `habits` + `tasks`（Issue #D-3〜#D-4 で本実装） | `AiProposalConfirmService` |

<br>

#### ApplicationRecord.with_transaction の設計

```ruby
# app/models/application_record.rb
def self.with_transaction(&block)
  # ブロック内で例外が発生すると Rails が自動ロールバックし例外を再 raise する
  # rescue はサービスクラス側で書く（with_transaction 内では rescue しない）
  ActiveRecord::Base.transaction(&block)
end
```

<br>

| 設計判断 | 理由 |
|:---|:---|
| `with_transaction` 内で `rescue` しない | transaction ブロックの内側で rescue すると例外がロールバック前にキャッチされ、DBが中途半端な状態でコミットされる危険がある |
| rescue はサービスクラス側に置く | transaction ブロックの外側で rescue することで「ロールバック完了 → エラー通知」の順序が保証される |
| ネスト禁止 | `with_transaction` の中で `with_transaction` を呼ぶと内側の失敗が外側に伝播しない。`create_all_for_reflection!` 内部の `transaction` は外側に合流するため問題ない |

<br>

#### WeeklyReflection モデルのバグ修正

<br>

`weekly_reflections` テーブルには `UNIQUE(user_id, year, week_number)` 制約があるが、<br>
`year` / `week_number` が `nil` のまま保存されていた本番バグを `before_validation` で修正。

```ruby
# app/models/weekly_reflection.rb
before_validation :set_year_and_week_number

def set_year_and_week_number
  return unless week_start_date.present?
  self.year        = week_start_date.cwyear  # ISO週番号ベースの年
  self.week_number = week_start_date.cweek   # ISO週番号（1〜53）
end
```

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/application_record.rb` | `with_transaction` クラスメソッドを追加 |
| `app/models/weekly_reflection.rb` | `before_validation :set_year_and_week_number` を追加（バグ修正） |
| `app/services/weekly_reflection_complete_service.rb` | 新規作成（振り返り完了フロー） |
| `app/services/habit_record_save_service.rb` | 新規作成（習慣記録フロー） |
| `app/services/user_destroy_service.rb` | 新規作成（退会処理フロー） |
| `app/services/ai_proposal_confirm_service.rb` | 新規作成（骨格のみ・Issue #D-3〜#D-4 で本実装） |
| `app/controllers/weekly_reflections_controller.rb` | `create` アクションをサービスクラスに委譲 |
| `app/controllers/habit_records_controller.rb` | `create` / `update` アクションをサービスクラスに委譲 |
| `test/test_helper.rb` | `require "minitest/mock"` を追加（stub 使用に必要） |
| `test/fixtures/weekly_reflections.yml` | 全 fixture に `year` / `week_number` を追加 |
| `test/services/application_record_with_transaction_test.rb` | 新規作成（5テスト） |
| `test/services/weekly_reflection_complete_service_test.rb` | 新規作成（6テスト） |
| `test/services/habit_record_save_service_test.rb` | 新規作成（3テスト） |

<br>

### #B-1: 数値型習慣の記録・達成率計算・リフレクション手法対応

<br>

**ブランチ:** `feature/B-1-numeric-habit`<br>
**完了日:** 2026-03-27<br>
**概要:** 習慣の記録タイプを「チェック型（やった/やらない）」と「数値型（分・冊・km等）」に拡張。<br>
振り返りフォームにリフレクション手法（なぜ？→どう？→からの？）のフィールドを追加し、<br>
全画面での単位表示の統一・数値型補正ロジックの実装・UIのハイライト修正を実施した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| DB | `next_action` カラムを `weekly_reflections` に追加（「からの？」フィールド対応） |
| Model | `Habit` に `measurement_type` enum・`weekly_target` バリデーション分岐を追加 |
| Model | `HabitRecord` に `numeric_value` バリデーション・`find_or_create_for` 数値型対応を追加 |
| Service | `HabitRecordSaveService` を数値型に対応・戻り値の `errors:[]` 配列形式に統一 |
| Service | `WeeklyReflectionCompleteService` に `corrections` 引数・差分補正ロジック・キー検証・`is_manual_input` 除外を追加 |
| Controller | `HabitRecordsController` に `Float()` 安全変換を追加 |
| Controller | `HabitRecordsController` の Strong Parameters に `:numeric_value` を追加 |
| Controller | `HabitsController` の Strong Parameters に `:unit` / `:measurement_type` を追加 |
| Controller | `DashboardsController` の `build_habit_stats` をチェック型/数値型の COUNT/SUM 分岐に更新 |
| Controller | `WeeklyReflectionsController` に `corrections` 受け渡し・Strong Parameters 追加・`build_habit_stats` 数値型対応 |
| View | `_habit_record.html.erb` にチェック型/数値型の UI 切り替え・`format("%g")` による数値表示統一 |
| View | `dashboards/index.html.erb` の単位表示をチェック型→「日」/数値型→ `habit.unit` に分岐 |
| View | `weekly_reflections/index.html.erb` の単位表示を同様に分岐 |
| View | `habits/new.html.erb` に `measurement_type` / `unit` フィールドを追加 |
| View | `weekly_reflections/new.html.erb` にリフレクション3項目フォーム・数値補正フィールドを追加 |
| View | `weekly_reflections/show.html.erb` にリフレクション3項目の表示を追加 |
| JS | `habit_form_controller.js` に `measurementLabel` ターゲット・`connect()` でのハイライト初期化を追加 |
| JS | `habit_record_controller.js` の `saveNumeric` を `event.target` 方式に変更（複数習慣対応） |

<br>

#### 振り返りフォームのリフレクション手法対応

<br>

| DBカラム | UIラベル | リフレクション項目の説明 |
|:---|:---|:---|
| `direct_reason` | なぜ？（直接の原因） | できなかった直接の理由を記述する |
| `background_situation` | どう？（改善策） | 次週どう改善するかを記述する |
| `next_action` | からの？（次への展開） | 具体的な次のアクションを記述する（#B-1 で新規追加） |
| `reflection_comment` | 自由コメント（任意） | 自由記述（最大1000文字） |

<br>

#### 数値補正ロジックの設計（差分補正方式）

<br>

振り返り画面でユーザーが週合計を手動補正できる機能を実装した。

<br>

```
例: 月曜20分・火曜30分・水曜25分 = 合計75分 → 補正後90分に設定したい
  差分 = 90 - 75 = +15分
  → 日曜日（week_end_date）のレコードに15分を追加保存
  → 月〜水の各日記録はそのまま保持される
```

<br>

| 設計ポイント | 内容 |
|:---|:---|
| 差分補正方式 | 各日の記録を壊さず週合計だけを調整する |
| `is_manual_input` フラグ | 補正レコードを日常記録と区別して再補正時の二重加算を防止 |
| `current_sum` から補正レコードを除外 | `.where(is_manual_input: [false, nil])` で再補正が安定する |
| キー形式のホワイトリスト検証 | `/\Ahabit_\d+\z/` でSQLインジェクションを防ぐ |
| 認可チェック | `@user.habits.find_by(id:)` 経由で他ユーザーの習慣を操作不可 |
| マイナス差分のクランプ | `new_value < 0` のとき `0.0` にクランプして負の記録を防ぐ |

<br>

#### 単位表示の統一ルール（全画面共通）

<br>

| 習慣タイプ | 表示例 | 使用する値 |
|:---|:---|:---|
| チェック型 | `3/7日（43%）` | `completed_count` と「日」固定 |
| 数値型 | `6/7冊（85%）` | `numeric_sum` と `habit.unit` |

<br>

数値の整形には全画面で `format("%g", value.to_f)` を統一使用。<br>
`format("%g", 6.0)` → `"6"`、`format("%g", 6.5)` → `"6.5"` と自動整形される。<br>
入力フィールドの `value` 属性・進捗表示・補正フィールドを含む全ての数値表示で統一する。

<br>

#### ラジオボタンのハイライトバグ修正

<br>

**問題：** 数値型カードをクリックしてもチェック型カードの青枠が残る。<br>
**原因：** `label` タグの青枠（`border-blue-500 bg-blue-50`）をサーバー側（ERB）のみで設定しており、<br>
ユーザーがクリックして切り替えたとき JavaScript 側でラベルのクラスを更新していなかった。<br>
**修正：** `habit_form_controller.js` に以下を追加した。

<br>

| 追加内容 | 目的 |
|:---|:---|
| `measurementLabel` ターゲットを `static targets` に追加 | JS から label タグを直接参照できるようにする |
| `connect()` メソッドを追加 | ページ読み込み時に `toggleUnit()` を自動実行し初期状態を同期する |
| `toggleUnit()` 内でラベルのクラスを付け替える処理を追加 | クリック時に青枠が正しく移動するようにする |
| ERB 側の条件分岐クラスを削除 | JS に管理を一本化し責務を分離する |

<br>

```
動作フロー:
  ページ読み込み → connect() → toggleUnit() → 現在の選択に合わせてラベルに青枠を付与
  カードをクリック → change イベント → toggleUnit() → クリックしたカードに青枠を移動
```

<br>

### #B-2: 習慣の除外日設定（habit_excluded_days）

<br>

**ブランチ:** `feature/B-2-habit-excluded-days`<br>
**完了日:** 2026-03-28<br>
**概要:** 習慣ごとに「実施しない曜日」を設定できる除外日機能を実装。<br>
除外日は達成率計算の分母から除外され、土日を除外した習慣は5日/5日=100%で達成となる。<br>
習慣の新規作成・編集フォームに曜日チェックボックスを追加し、一覧カードに除外曜日を表示する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `HabitExcludedDay` モデル作成（`belongs_to :habit` / `day_of_week: 0-6` バリデーション / `DAY_NAMES` 定数） |
| Model | `Habit` に `has_many :habit_excluded_days` 追加 |
| Model | `Habit` に `excluded_day_numbers` メソッド追加（除外日番号の配列を昇順で返す） |
| Model | `Habit` に `effective_weekly_target` メソッド追加（`min(weekly_target, 7-除外日数)` を返す） |
| Model | `Habit#weekly_progress_stats` をチェック型の分母を `effective_weekly_target` に変更 |
| Controller | `HabitsController` に `save_excluded_days!`（destroy_all→再登録方式）追加 |
| Controller | `HabitsController#create` をトランザクションで習慣保存と除外日保存を一体化 |
| Controller | `HabitsController` に `edit` / `update` アクション追加 |
| Controller | `HabitsController#index` / `DashboardsController#index` / `WeeklyReflectionsController` に `includes(:habit_excluded_days)` 追加（N+1防止） |
| Controller | 各コントローラーの `build_habit_stats` でチェック型の分母を `effective_weekly_target` に変更 |
| View | `habits/new.html.erb` に除外曜日チェックボックス追加（グリッドレイアウト・スマホ対応・バリデーションエラー後の状態復元） |
| View | `habits/edit.html.erb` を新規作成（既存除外日をチェック済み状態で表示・記録タイプ変更不可） |
| View | `habits/index.html.erb` に「除外: 土・日」表示・編集ボタン追加 |
| Route | `config/routes.rb` に `edit` / `update` を追加 |
| Test | `HabitExcludedDay` モデルテスト15件追加 |
| Fix | `test/fixtures/habit_excluded_days.yml` を削除（NOT NULL 制約違反の根本解決） |

<br>

#### effective_weekly_target の計算設計

```
実施予定日数 = min(weekly_target, 7 - 除外日数)

例1: 目標5日 / 除外: 土日(2日) → min(5, 5) = 5日 → 5/5日 = 100%
例2: 目標5日 / 除外なし      → min(5, 7) = 5日 → 従来通り
例3: 目標7日 / 除外: 5日     → min(7, 2) = 2日 → 物理的な実施可能日数が分母
```

<br>

チェック型のみ除外日が分母に影響する。数値型（分・冊・km）は絶対数値目標のため除外日に影響されない。

<br>

#### フォーム設計のポイント

<br>

| 設計 | 内容 |
|:---|:---|
| `check_box_tag "excluded_day_numbers[]"` | `habit` ネームスペース外で送信（habit テーブルのカラムではないため） |
| `destroy_all` → 再登録方式 | 更新時に「チェックを全て外す」操作も確実に DB に反映できる |
| `params.key?(:excluded_day_numbers)` | edit 画面でバリデーションエラー後の再表示時は params を優先し、通常表示は DB の値を使う |
| `focus-within:ring-2` | `sr-only` で非表示のチェックボックスへのキーボードフォーカスをラベルに可視化 |
| `has-[:checked]:border-blue-500` | JavaScript なしで選択状態を視覚的にハイライト |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/habit_excluded_day.rb` | 新規作成（バリデーション・DAY_NAMES/DAY_NAMES_FULL定数） |
| `app/models/habit.rb` | `has_many :habit_excluded_days` / `excluded_day_numbers` / `effective_weekly_target` / `weekly_progress_stats` 更新 |
| `app/controllers/habits_controller.rb` | `edit` / `update` / `save_excluded_days!` 追加・`includes` 追加・`build_habit_stats` 更新 |
| `app/controllers/dashboards_controller.rb` | `includes(:habit_excluded_days)` / `effective_weekly_target` 対応 |
| `app/controllers/weekly_reflections_controller.rb` | `includes(:habit_excluded_days)` / `effective_weekly_target` 対応 |
| `app/views/habits/new.html.erb` | 除外日チェックボックス追加・バリデーションエラー後の状態復元 |
| `app/views/habits/edit.html.erb` | 新規作成（既存除外日をチェック済みで表示・記録タイプ変更不可） |
| `app/views/habits/index.html.erb` | 「除外: 土・日」表示・編集ボタン追加・フォールバック値修正 |
| `config/routes.rb` | `edit` / `update` を追加 |
| `test/models/habit_excluded_day_test.rb` | 新規作成（15件） |
| `test/fixtures/habit_excluded_days.yml` | 削除（NOT NULL 違反の根本解決） |

<br>

#### テスト結果

<br>
```
B-2テスト: 15 runs, 33 assertions, 0 failures, 0 errors, 0 skips
全テスト:  291 runs, 792 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #B-3: ストリーク計算・表示（current_streak / longest_streak）

<br>

**ブランチ:** `feature/B-3-streak-calculation`<br>
**完了日:** 2026-03-29<br>
**概要:** 習慣の継続日数（ストリーク）を GoodJob で日次計算し、<br>
`habits.current_streak` / `longest_streak` に保存。<br>
ダッシュボード・習慣一覧に「🔥 N日」として表示する。<br>
AM4:00 基準・除外日考慮・お休みモード対応の完全実装。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `Habit#calculate_streak!` を追加（AM4:00基準・90日遡及・N+1防止の pluck+Hash化） |
| Model | `Habit#on_rest_mode?` を追加（現在のお休みモード状態を返す・UI表示用） |
| Model | `Habit#rest_mode_on_date?(date)` を追加（日付単位のお休みモード判定・ストリーク計算用） |
| Model | `HabitRecord#recorded?` を追加（チェック型: completed / 数値型: numeric_value > 0） |
| Model | `HabitRecord#first_recorded_today?` を追加（created_at が today_for_record と一致するか） |
| Model | `HabitRecord#updated_today?` を追加（updated_at が created_at より新しく今日の日付か） |
| Model | `User` に `has_one :user_setting` を追加（on_rest_mode? の参照に必要） |
| Job | `StreakCalculationJob` を本実装（毎日AM4:05・find_each・個別エラーはスキップ） |
| View | `_habit_record.html.erb` の状態バッジを5パターンに更新（未記録/今日記録済み/今日更新済み/記録済み） |
| View | `dashboards/index.html.erb` に🔥ストリークバッジ追加（7日以上→橙色/1〜6日→黄色） |
| View | `habits/index.html.erb` にストリークバッジ追加（継続日数・最高記録を表示） |
| Test | `test/models/habit_streak_test.rb` を新規作成（25件・33assertions） |

<br>

#### calculate_streak! のアルゴリズム

<br>
```
基準日（AM4:00境界の「今日」）から過去90日に向かって1日ずつ遡る
  ↓
その日が除外日（habit_excluded_days）なら → スキップ（ストリークを壊さず増やさない）
  ↓
達成済み（completed=true または numeric_value > 0）なら → streak + 1
  ↓
未達成 + rest_mode_on_date?(date) = true なら → スキップ（ストリーク維持）
  ↓
未達成 + お休みモードなし → break（ストリーク確定）
```

<br>

#### on_rest_mode? と rest_mode_on_date? の使い分け

<br>

| メソッド | 判定対象 | 用途 |
|:---|:---|:---|
| `on_rest_mode?` | 今この瞬間 | ビューでのUI表示判定 |
| `rest_mode_on_date?(date)` | 指定した過去の日付 | ストリーク計算（過去日付を遡るため必須） |

<br>

`on_rest_mode?` だけを使うと「昨日はお休みモード中だったが今日は終了している」ケースで<br>
昨日の未達成が誤って「通常未達成」と判定されストリークがリセットされるバグが発生する。<br>
`rest_mode_on_date?(date)` は `rest_mode_until.to_date >= date` で日付単位に判定するため正確。

<br>

#### 表示状態の5パターン

<br>

| `record_status` | 条件 | 表示 | 色 |
|:---|:---|:---|:---|
| `:not_recorded` | habit_record が nil | 未記録（非表示） | sr-only |
| `:updated_today` | updated_at > created_at かつ今日 | ↑ 今日更新済み | 青 |
| `:recorded_today` | created_at が今日 | ✓ 今日記録済み | 緑 |
| `:previously_recorded` | 昨日以前に作成・今日は未更新 | ✓ 記録済み | 緑 |

<br>

`updated_today?` を `first_recorded_today?` より先に判定する理由:<br>
今日初入力後にすぐ変更した場合、`first_recorded_today?` も `updated_today?` も true になるが<br>
ユーザーには「更新済み」として表示するのが正しいため `updated_today?` を優先する。

<br>

#### longest_streak の保護設計

```ruby
new_longest = [longest_streak, streak].max
update_columns(
  current_streak:            streak,
  longest_streak:            new_longest,  # 過去最高は絶対に下がらない
  last_streak_calculated_at: Time.current
)
```

<br>

`update_columns` を使う理由: バリデーションスキップ・`updated_at` 非更新・高速化。<br>
ストリーク計算はバッチ処理で頻繁に実行されるため `update!` のオーバーヘッドを避ける。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/habit.rb` | `calculate_streak!` / `on_rest_mode?` / `rest_mode_on_date?` を追加 |
| `app/models/habit_record.rb` | `recorded?` / `first_recorded_today?` / `updated_today?` を追加 |
| `app/models/user.rb` | `has_one :user_setting` を追加 |
| `app/jobs/streak_calculation_job.rb` | 本実装（includes N+1防止・個別エラースキップ） |
| `app/views/habit_records/_habit_record.html.erb` | 状態バッジを5パターンに更新 |
| `app/views/dashboards/index.html.erb` | 🔥ストリークバッジ追加 |
| `app/views/habits/index.html.erb` | ストリークバッジ・最高記録表示追加 |
| `test/models/habit_streak_test.rb` | 新規作成（25件） |
| `test/fixtures/habit_excluded_days.yml` | 削除（外部キー違反の根本解決） |

<br>

#### テスト結果

<br>
```
B-3テスト: 25 runs, 33 assertions, 0 failures, 0 errors, 0 skips
全テスト:  316 runs, 825 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #B-4: 習慣のアーカイブ機能（archived_at）

<br>

**ブランチ:** `feature/B-4-habit-archive`<br>
**完了日:** 2026-03-29<br>
**概要:** 習慣の「削除（deleted_at）」と「卒業アーカイブ（archived_at）」を明確に区別する機能を実装。<br>
達成して卒業した習慣をアーカイブとして残しつつ、アクティブ一覧から非表示にする。<br>
アーカイブ一覧ページ・復元機能・状態ガード付きのモデルメソッドを実装した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `scope :active` を修正（`archived_at: nil` の条件を追加） |
| Model | `scope :archived` を新規追加（`deleted_at: nil AND archived_at IS NOT NULL`） |
| Model | `archive!` メソッドを追加（状態ガード付き：二重実行・削除済みで RuntimeError） |
| Model | `unarchive!` メソッドを追加（状態ガード付き：未アーカイブで RuntimeError） |
| Model | `archived?` メソッドを追加（`archived_at.present?` を返す可読性向上ヘルパー） |
| Model | `active?` メソッドを修正（`deleted_at.nil? && archived_at.nil?` に変更） |
| Controller | `archive` アクション追加（POST /habits/:id/archive → habits#archive） |
| Controller | `unarchive` アクション追加（PATCH /habits/:id/unarchive → habits#unarchive） |
| Controller | `archived` アクション追加（GET /habits/archived → 8-2番画面） |
| Controller | `set_habit` を修正（`where(deleted_at: nil).find` に変更） |
| Controller | `before_action :require_unlocked` に `:archive` を追加 |
| Route | `collection do get :archived end` を追加（`archived_habits_path`） |
| Route | `member do post :archive / patch :unarchive end` を追加 |
| View | `habits/index.html.erb` にヘッダーの「📦 アーカイブ済みを見る」リンクを追加 |
| View | `habits/index.html.erb` の各習慣カードに `button_to` で「📦 卒業」ボタンを追加 |
| View | `habits/archived.html.erb` を新規作成（8-2番画面・スマホ・デスクトップ両対応） |
| Test | `test/models/habit_archive_test.rb` を新規作成（22件） |
| Test | `test/controllers/habits_archive_controller_test.rb` を新規作成（6件） |

<br>

#### 習慣の状態管理設計

<br>

| 状態 | 条件 | 操作可否 |
|:---|:---|:---|
| アクティブ | `deleted_at: nil AND archived_at: nil` | 全操作可能 |
| アーカイブ済み | `deleted_at: nil AND archived_at: 設定済み` | 復元のみ可能 |
| 削除済み | `deleted_at: 設定済み` | 操作不可 |

<br>

#### archive! の状態ガード設計

```ruby
def archive!
  raise RuntimeError, "すでにアーカイブ済みです" if archived?
  raise RuntimeError, "削除済みのため操作できません" if deleted?
  update!(archived_at: Time.current)
end

def unarchive!
  raise RuntimeError, "アーカイブされていません" unless archived?
  update!(archived_at: nil)
end
```

<br>

状態ガードをモデルに集約することで、コントローラーが薄くなり（単一責任の原則）、<br>
不正な状態遷移（二重アーカイブ・削除済み習慣のアーカイブ）をデータ層で防いでいる。

<br>

#### set_habit の変更履歴と設計意図

<br>

| バージョン | 実装 | 問題 |
|:---|:---|:---|
| MVP版 | `current_user.habits.active.find` | アーカイブ済み習慣が `unarchive` で取得不可 |
| B-4初版 | `current_user.habits.find` | 論理削除済み習慣も取得できてしまい既存テスト失敗 |
| B-4最終版 | `current_user.habits.where(deleted_at: nil).find` | 削除済みを除外・アーカイブ済みは操作可能 |

<br>

`where(deleted_at: nil)` を使うことで「削除済みだけ排除」し、<br>
アクティブ（`archived_at: nil`）とアーカイブ済み（`archived_at: 設定済み`）の両方を操作対象にできる。<br>
`current_user.habits.` で絞り込むため他ユーザーの習慣は RecordNotFound になりセキュリティも維持される。

<br>

#### button_to 採用の理由

<br>

アーカイブボタンは `link_to + data-turbo-method: :post` から `button_to` に変更した。

<br>

| 方式 | POST の仕組み | リスク |
|:---|:---|:---|
| `link_to + turbo_method` | Turbo が JS で POST に変換（疑似POST） | JS無効・Turbo読み込み失敗時に GET になる |
| `button_to` | `<form method="post">` として展開（本物のPOST） | JS なしでも確実に POST が送られる |

<br>

`form: { style: "display:inline" }` を指定することで他のボタンと横並びのレイアウトを維持している。

<br>

#### アーカイブ一覧ページ（8-2番画面）の設計

<br>

| 設計 | 内容 |
|:---|:---|
| グレートーン配色 | アクティブ習慣（白背景）と視覚的に区別（`bg-gray-50 / text-gray-600`） |
| レスポンシブ | `grid-cols-1 md:grid-cols-2 lg:grid-cols-3`（スマホ1列・タブレット2列・PC3列） |
| Empty State | 0件時に「卒業ボタンでアーカイブできます」の案内とボタンを表示 |
| アーカイブ日表示 | `habit.archived_at.strftime("%Y年%m月%d日")` で卒業日を表示 |
| 最高ストリーク表示 | `longest_streak > 0` のときに「🔥 N日」を表示して達成を称える |
| パンくず代わり | 「← 習慣一覧に戻る」リンクでユーザーが迷子にならないよう設置 |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/habit.rb` | `scope :active` 修正・`scope :archived` 追加・`archive!` / `unarchive!` / `archived?` / `active?` 追加 |
| `app/controllers/habits_controller.rb` | `archive` / `unarchive` / `archived` アクション追加・`set_habit` 修正・`before_action` 更新 |
| `config/routes.rb` | `collection :archived` / `member :archive` / `member :unarchive` を追加 |
| `app/views/habits/index.html.erb` | 「📦 アーカイブ済みを見る」リンク追加・`button_to` でアーカイブボタン追加 |
| `app/views/habits/archived.html.erb` | 新規作成（8-2番画面・グレートーン・Empty State・復元ボタン） |
| `test/models/habit_archive_test.rb` | 新規作成（22件：scope・archive!/unarchive!・状態ガード異常系） |
| `test/controllers/habits_archive_controller_test.rb` | 新規作成（6件：archived一覧・archive・unarchive・他ユーザー防止） |

<br>

#### テスト結果

<br>
```
B-4テスト: 22 runs, 33 assertions, 0 failures, 0 errors, 0 skips
全テスト:  344 runs, 867 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #B-5: 習慣削除確認モーダル（M-1）

<br>

**ブランチ:** `feature/B-5-habit-menu-modal`<br>
**完了日:** 2026-03-30<br>
**概要:** 習慣削除時の誤操作防止モーダルを実装。<br>
「アーカイブ」「完全に削除」の2択を提示し、スマホはボトムシート形式で表示する。<br>
PDCAロック中は「⋯」メニュー自体を非表示にし、サーバー側と合わせた二重防御を実現する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| JS | `habit_menu_controller.js` を新規作成（Stimulusコントローラー） |
| JS | デスクトップ（768px以上）: 画面中央オーバーレイモーダルを表示 |
| JS | スマホ（768px未満）: 画面下部からスライドインするボトムシートを表示 |
| JS | `window.innerWidth >= 768` でデスクトップ/スマホを判定して切り替え |
| JS | Escapeキー・オーバーレイクリック・キャンセルボタンでモーダルを閉じる |
| JS | `document.body.style.overflow = "hidden"` でモーダル表示中は背景スクロールを禁止 |
| View | `_habit_card_actions.html.erb` パーシャルを新規作成（⋯ボタン + モーダルUI） |
| View | `content_for :modals` でモーダルHTMLを `</body>` 直前に出力（CSSバグ回避） |
| View | `habits/index.html.erb` のカード右上ボタン群を「⋯」メニューに置き換え |
| Layout | `application.html.erb` に `<%= yield :modals %>` を `</body>` 直前に追加 |
| Test | `habits_menu_controller_test.rb` を新規作成（14件） |
| Fix | `habit_excluded_day_test.rb` / `habits_controller_test.rb` に `travel_to` を追加（曜日依存バグ修正） |

<br>

#### モーダルUIの構成

<br>

| UI要素 | 内容 |
|:---|:---|
| 「⋯」ボタン | 習慣カード右上に表示。ロック中は `unless locked` で出力しない |
| デスクトップモーダル | `fixed inset-0 bg-black/50` のオーバーレイ + 中央白パネル |
| スマホボトムシート | `fixed inset-0` + `items-end` + `translate-y` アニメーションでスライドイン |
| アーカイブボタン | `button_to archive_habit_path` で POST /habits/:id/archive |
| 削除ボタン | `button_to habit_path` で DELETE /habits/:id |
| キャンセルボタン | `closeMenu()` でモーダルを閉じる |

<br>

#### 技術的な課題と解決策

<br>

**① `fixed inset-0` が効かない問題（CSSスタッキングコンテキスト）**

<br>

習慣カードの `div` に `transition-shadow` クラスがあり、<br>
CSS の仕様で `transition` プロパティを持つ祖先要素の子孫 `fixed` 要素は<br>
「ビューポート全体」ではなく「その祖先要素」を基準に配置されてしまう。<br>
`content_for :modals` でモーダルHTMLを `</body>` 直前に「逃がす」ことで解消した。

<br>

**② Tailwind `hidden`（`display: none !important`）との競合**

<br>

`classList.remove("hidden")` 後に `style.display = "flex"` で上書きしようとしても<br>
`!important` により `flex` が適用されない問題が発生した。<br>
初期状態を `style="display: none"` に変更し、JS で `style.display` を直接制御することで解消した。

<br>

**③ Stimulusスコープ外のDOM操作**

<br>

`button_to` が生成する `<form>` タグとイベントの干渉を避けるため、<br>
モーダルを `data-controller` の外側に配置した。<br>
`getElementById()` + `addEventListener` でスコープ外のモーダルを制御する設計にした。

<br>

**④ `content_for` のタイミング問題**

<br>

`connect()` でイベントリスナーを設定しようとしても、<br>
`content_for :modals` がページ末尾に出力されるため<br>
`connect()` 時点ではモーダルのDOMが存在しない場合があった。<br>
リスナーの設定を `openMenu()` 内（初回のみ）に移動し、`_listenersAttached` フラグで二重登録を防いだ。

<br>

**⑤ 既存テストの曜日依存バグ修正**

<br>

`current_week_range` は `week_start..today_for_record` の範囲で集計するため、<br>
今日が月曜の場合「週の範囲が1日分」になり複数日の記録がカウントされないバグがあった。<br>
`travel_to` で金曜・水曜に固定することで曜日に依存しないテストにした。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/javascript/controllers/habit_menu_controller.js` | 新規作成（Stimulusコントローラー） |
| `app/views/habits/_habit_card_actions.html.erb` | 新規作成（⋯ボタン + モーダルUIパーシャル） |
| `app/views/habits/index.html.erb` | カード右上ボタン群を⋯メニューに置き換え |
| `app/views/layouts/application.html.erb` | `<%= yield :modals %>` を `</body>` 直前に追加 |
| `test/controllers/habits_menu_controller_test.rb` | 新規作成（14件） |
| `test/models/habit_excluded_day_test.rb` | `travel_to` 追加（金曜固定・曜日依存バグ修正） |
| `test/controllers/habits_controller_test.rb` | `travel_to` 追加（水曜固定・曜日依存バグ修正） |

<br>

#### テスト結果

<br>
```
B-5テスト: 14 runs, 38 assertions, 0 failures, 0 errors, 0 skips
全テスト:  358 runs, 905 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #B-6: 習慣のカラー・アイコン・Drag&Drop 並び替え

<br>

**ブランチ:** `feature/B-6-habit-color-icon-sort`<br>
**完了日:** 2026-04-05<br>
**概要:** 習慣にカラーコードとアイコン（絵文字）を設定可能にし、ダッシュボード・習慣一覧の視認性を向上。<br>
`acts_as_list` gem でユーザーごとの並び順を DB 管理し、SortableJS + Stimulus で<br>
Drag & Drop 並び替え（即時保存）を実装。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Gem | `acts_as_list` を追加（`position` カラムで並び順管理・`scope: :user_id` でユーザー別管理） |
| Model | `Habit` に `acts_as_list column: :position, scope: :user_id, add_new_at: :bottom` を追加 |
| Model | `scope :active` の order を `position ASC NULLS LAST, created_at ASC` に変更（並び替え順を反映） |
| Model | `color` バリデーション追加（`#rrggbb` 形式・`allow_blank: true`） |
| Model | `icon` バリデーション追加（最大2文字・`allow_blank: true`） |
| Controller | `sort` アクション追加（`PATCH /habits/sort`・`insert_at` で position 更新） |
| Controller | `require_unlocked` に `:sort` を追加（PDCAロック中は並び替え不可） |
| Controller | `habit_params` に `:color` / `:icon` を追加（Strong Parameters） |
| Route | `collection do patch :sort end` を追加（`sort_habits_path`） |
| Importmap | `Sortable` を jsdelivr CDN からピン留め（ESM 形式・CDN は `cdnjs` では 404 のため `jsdelivr` を採用） |
| JS | `habit_sort_controller.js` を新規作成（SortableJS + fetch で PATCH 送信） |
| JS | `forceFallback: true` を設定（`display: grid` コンテナでの動作を保証） |
| JS | `habit_form_controller.js` に `selectColor()` / `selectIcon()` / `syncInitialState()` を追加 |
| JS | `syncInitialState()` で hidden input の値から初期選択状態を JS 側で一元管理（ERB 依存を排除） |
| View | `new.html.erb` / `edit.html.erb` にカラーピッカー（8色スウォッチ）・アイコン選択（16絵文字）UI を追加 |
| View | カラー・アイコンは hidden input + Stimulus で管理（スウォッチは `<button>` のためそのままでは送信されない） |
| View | `habits/index.html.erb` のグリッドコンテナに `data-controller="habit-sort"` / `data-habit-sort-sort-url-value` / `data-habit-sort-locked-value` を追加 |
| View | 各カードに `data-habit-id` / ドラッグハンドルボタン（`data-sort-handle`）を追加 |
| View | カード左ボーダーにインラインスタイルで `habit.color` を反映（Tailwind 動的クラスはビルド対象外のためインラインスタイル採用） |
| View | カード習慣名の前にアイコン（`habit.icon`）を表示 |
| View | `dashboards/index.html.erb` にアイコン表示・カラープログレスバーを追加 |
| View | `habit_records/_habit_record.html.erb` のチェック型・数値型ラベルにアイコン表示を追加（対応漏れ修正） |
| Test | `test/models/habit_sort_test.rb` を新規作成（8件） |
| Test | `test/controllers/habits_sort_controller_test.rb` を新規作成（3件） |

<br>

#### カラー・アイコンの UI 設計

<br>

| 設計 | 内容 |
|:---|:---|
| hidden input 方式 | カラースウォッチ・アイコンボタンは `<button>` 要素のためフォーム送信されない。Stimulus が hidden input の value を更新することで Rails に届ける |
| ERB での初期選択 | `selected_color == color_item[:value]` で初期選択クラスを付与（ERB + JS の二重管理で確実に表示） |
| syncInitialState() | `connect()` 時に hidden input の値を読んでスウォッチ・アイコンの選択状態を JS で同期（バリデーションエラー後の再表示も正確） |
| hover クラスは HTML に記述 | Tailwind の `hover:scale-110` を JS（classList）で動的追加するとビルド対象外になるリスクがあるため HTML に常時記述する |
| インラインスタイルでカラー適用 | `style="border-left: 4px solid <%= habit.color %>"` → Tailwind は動的カラーコードを静的解析できないためインラインスタイルを採用 |

<br>

#### Drag & Drop 実装の設計

<br>

| 設計 | 内容 |
|:---|:---|
| SortableJS + Stimulus | importmap（CDN）経由で SortableJS を読み込み、Stimulus コントローラー内で初期化 |
| handle 指定 | `handle: "[data-sort-handle]"` でハンドルアイコン以外からのドラッグを防止（チェックボックスや数値入力との誤操作防止） |
| forceFallback: true | `display: grid` のコンテナで SortableJS のネイティブ DnD が正常に動作しないため CSS フォールバック実装を強制 |
| 即時保存 | `onEnd` コールバックで DOM 順から habitIds 配列を取得し `PATCH /habits/sort` に fetch 送信 |
| ロック中は無効化 | ERB 側でハンドル非表示 + JS 側で `if (this.lockedValue) return`（Stimulus の `locked: Boolean` Value）+ サーバー側 `require_unlocked` の三重防御 |
| 二重防御設計 | サーバー側の `sort` アクションは `require_unlocked` で保護されているため、JS を無効化しても操作不可 |
| position NULL 対応 | scope :active の ORDER に `NULLS LAST` を指定（既存レコードの position が NULL でも末尾に表示） |

<br>

#### CDN 選定の経緯

<br>

| CDN | URL | 結果 |
|:---|:---|:---:|
| cdnjs.cloudflare.com | `.../Sortable/1.15.2/Sortable.esm.js` | ❌ 404（ESM 版が存在しない） |
| cdn.jsdelivr.net | `.../sortablejs@1.15.0/modular/sortable.esm.js` | ✅ 200 OK |

<br>

importmap は ECMAScript Module（ESM）形式のみ対応。<br>
`cdnjs` の `1.15.2` には ESM 版が存在しないため `jsdelivr` の `1.15.0` を採用した。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` | `gem "acts_as_list"` 追加 |
| `app/models/habit.rb` | `acts_as_list` 設定・`scope :active` order 変更・`color` / `icon` バリデーション追加 |
| `app/controllers/habits_controller.rb` | `sort` アクション追加・`require_unlocked` に `:sort` 追加・`habit_params` に `:color` / `:icon` 追加 |
| `config/routes.rb` | `collection do patch :sort end` を追加 |
| `config/importmap.rb` | `pin "Sortable"` を jsdelivr CDN で追加 |
| `app/javascript/controllers/habit_sort_controller.js` | 新規作成（SortableJS + fetch・`forceFallback: true`） |
| `app/javascript/controllers/habit_form_controller.js` | `selectColor()` / `selectIcon()` / `syncInitialState()` 追加・`colorInput` / `colorSwatch` / `iconInput` / `iconButton` ターゲット追加 |
| `app/views/habits/new.html.erb` | カラーピッカー・アイコン選択 UI 追加 |
| `app/views/habits/edit.html.erb` | カラーピッカー・アイコン選択 UI 追加 |
| `app/views/habits/index.html.erb` | Drag & Drop コンテナ設定・カラー左ボーダー・アイコン・ドラッグハンドル追加 |
| `app/views/dashboards/index.html.erb` | アイコン表示・カラープログレスバー追加 |
| `app/views/habit_records/_habit_record.html.erb` | チェック型・数値型ラベルにアイコン（`habit.icon`）表示を追加（対応漏れ修正） |
| `test/models/habit_sort_test.rb` | 新規作成（8件：カラー・アイコンバリデーション・acts_as_list 動作確認） |
| `test/controllers/habits_sort_controller_test.rb` | 新規作成（3件：並び替え保存・未ログイン・不正ID混入） |

<br>

#### テスト結果

<br>
```
B-6テスト: 11 runs, 0 failures, 0 errors, 0 skips
全テスト:  369 runs, 929 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #B-7: habit_records.memo（日次メモ）機能

<br>

**ブランチ:** `feature/B-7-habit-record-memo`<br>
**完了日:** 2026-04-06<br>
**概要:** 各習慣の日次記録に定性メモを記録できる機能を追加。<br>
AI分析の `root_cause` 精度向上に活用する。200文字以内・音声入力対応。<br>
`NOT_PROVIDED` センチネル値による部分更新設計で、チェック/数値操作時にメモが消えない設計を実現。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `HabitRecord` に `memo` バリデーション追加（最大200文字・任意・`allow_blank: true`） |
| Model | `HabitRecord#has_memo?` インスタンスメソッドを追加（`memo.present?` を返す） |
| Service | `HabitRecordSaveService` に `NOT_PROVIDED` センチネル値による部分更新設計を導入 |
| Service | `initialize` の引数デフォルトを `NOT_PROVIDED` に変更し「送られなかった項目は更新しない」設計に |
| Controller | `parse_service_params` を `params.key?` による送信有無判定に変更 |
| Controller | `create` / `update` アクションに `memo: service_params[:memo]` を追加 |
| View | `_habit_record.html.erb` に💬トグルボタン・テキストエリア・文字数カウンター・保存/キャンセルボタンを追加 |
| View | `data-controller="habit-record"` を最外側 div に移動（Stimulus スコープ修正） |
| View | `show_memo_area` 変数で Turbo Stream 差し替え後の展開状態をERB側で制御 |
| JS | `habit_record_controller.js` にメモ関連メソッドを追加（`toggleMemo` / `saveMemo` / `cancelMemo` / `updateMemoCount`） |
| JS | `toggle()` / `saveNumeric()` から `memo` の送信を削除（各操作が自分の項目だけを更新する設計） |
| JS | `voice_input_controller.js` を新規作成（Web Speech API・graceful degradation対応） |
| JS | `index.js` に `voice-input` コントローラーを登録 |
| CSP | `content_security_policy.rb` の `nonce_directives` を `[]` に変更（Turbo Stream との競合を解消） |
| Test | モデルテスト 8件・統合テスト 6件を追加（383 runs, 953 assertions） |

<br>

#### 設計上の判断

<br>

**① `NOT_PROVIDED` センチネル値による部分更新設計**

<br>

`memo: nil` が「メモを空にする操作」なのか「`memo` パラメータが送られなかった」なのかを<br>
デフォルト値を `nil` にすると区別できない。<br>
`:not_provided` シンボルをデフォルトにすることで<br>
「送られなかった項目は DB を変更しない」という部分更新を実現した。<br>
```ruby
NOT_PROVIDED = :not_provided

def initialize(user:, habit:, completed: NOT_PROVIDED, numeric_value: NOT_PROVIDED, memo: NOT_PROVIDED)
  ...
end

update_params = {}
update_params[:completed]     = @completed     unless @completed     == NOT_PROVIDED
update_params[:numeric_value] = @numeric_value unless @numeric_value == NOT_PROVIDED
update_params[:memo]          = @memo.presence unless @memo          == NOT_PROVIDED
habit_record.update!(update_params)
```

<br>

**② 各操作が「自分の項目だけ」送る設計**

<br>

`toggle()` → `completed` のみ送信<br>
`saveNumeric()` → `numeric_value` のみ送信<br>
`saveMemo()` → `memo` のみ送信<br>
<br>
操作ごとに担当項目を分離することで「チェックしたらメモが消えた」などの<br>
サイレントデータ消失を防いでいる。

<br>

**③ Stimulus スコープ修正（`data-controller` の移動）**

<br>

`memoArea` ターゲットが `data-controller="habit-record"` のスコープ外にあったため<br>
`Missing target element "memoArea"` エラーが発生していた。<br>
`data-controller` を最外側の wrapper div（`id="habit_record_row_xxx"`）に移動し、<br>
チェック行・メモ行の両方がスコープ内に入るよう修正した。

<br>

**④ Turbo Stream 差し替え後の表示制御はERB側で行う**

<br>

`saveMemo()` 実行後に Turbo Stream がパーシャル全体を差し替えるため、<br>
JS側で `_updateMemoToggleStyle()` を呼んでも差し替え後は古い要素への参照が無効になる。<br>
💬の青色化・メモエリアの展開状態は `show_memo_area = current_memo.present?` として<br>
ERB側で制御することで、Turbo Stream 差し替え後も正しい状態で表示される。

<br>

**⑤ CSP の `nonce_directives` を `[]` に変更**

<br>

`nonce_directives = ["script-src"]` の設定では Turbo Drive のページ遷移時に<br>
新しい body の `<script>` タグに古いページの nonce が引き継がれず<br>
Turbo Stream の DOM 差し替えがブロックされていた。<br>
`nonce_directives = []` に変更することで Turbo との競合を解消した。<br>
`script_src :self, :https, :unsafe_inline` で外部スクリプトの制御は維持される。

<br>

**⑥ 音声入力の graceful degradation**

<br>

`SpeechRecognition` が存在しない場合（Firefox など）は<br>
`connect()` 内で 🎤 ボタンを `display: none` にする。<br>
「タップしても何も起きない」という混乱を防ぐ設計。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/habit_record.rb` | `memo` バリデーション追加・`has_memo?` メソッド追加 |
| `app/services/habit_record_save_service.rb` | `NOT_PROVIDED` センチネル値導入・部分更新設計に変更 |
| `app/controllers/habit_records_controller.rb` | `parse_service_params` を `params.key?` 判定に変更・`memo:` を追加 |
| `app/views/habit_records/_habit_record.html.erb` | メモUI追加・`data-controller` を最外側divに移動・`show_memo_area` 変数追加 |
| `app/javascript/controllers/habit_record_controller.js` | メモ関連メソッド追加・`toggle`/`saveNumeric` から `memo` 送信を削除 |
| `app/javascript/controllers/voice_input_controller.js` | 新規作成（Web Speech API） |
| `app/javascript/controllers/index.js` | `voice-input` コントローラーを登録 |
| `config/initializers/content_security_policy.rb` | `nonce_directives = []` に変更・`script_src` に `:unsafe_inline` 追加 |
| `test/models/habit_record_memo_test.rb` | 新規作成（8件：バリデーション・`has_memo?`） |
| `test/integration/memo_flow_test.rb` | 新規作成（6件：保存・部分更新・バリデーションエラー） |

<br>

#### テスト結果

<br>
```
B-7テスト: 14件（モデル8件・統合6件）
全テスト:  383 runs, 953 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #C-1: Task モデル・基本 CRUD

<br>

**ブランチ:** `feature/C-1-task-model-crud`<br>
**完了日:** 2026-04-07<br>
**概要:** tasks テーブルを使ったタスクの基本CRUD実装。<br>
Must/Should/Could の優先度と todo/doing/done/archived の状態管理。<br>
タスク一覧ページ（優先度別フィルタタブ）・新規作成ページ・ダッシュボード統合を実装。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `Task` モデル作成（enum: priority/task_type/status・バリデーション・スコープ・インスタンスメソッド） |
| Model | `User` に `has_many :tasks, dependent: :destroy` を追加 |
| Model | `before_validation :set_default_task_type` を追加（NOT NULL 制約対応） |
| Controller | `TasksController` 作成（index / new / create・Strong Parameters・ロックチェック） |
| Controller | `DashboardsController` に `@today_tasks` を追加（今日が期限のタスク最大5件） |
| Controller | `priority_counts` に `unscope(:order)` を追加（PG::GroupingError 修正） |
| Route | `resources :tasks, only: [:index, :new, :create]` を追加 |
| View | 9番: タスク一覧ページ（フィルタタブ5種・優先度別カラー・件数バッジ・Empty State） |
| View | 10番: タスク新規作成ページ（優先度カード選択UI・バリデーション表示） |
| View | ダッシュボードに「今日のタスク」セクションを追加 |
| View | ヘッダーに「タスク管理」ナビリンクを追加（PC・モバイル両対応） |
| JS | `priority_card_controller.js` を新規作成（Stimulus でカード選択状態を管理） |
| i18n | `ja.yml` に Task モデルの属性名・エラーメッセージを追加 |
| Test | Task モデルテスト17件・コントローラーテスト14件を追加 |

<br>

#### enum 設計

<br>

| enum | 値 | 設計意図 |
|:---|:---|:---|
| `priority` | `must:0 / should:1 / could:2` | ORDER BY priority ASC で重要度順に自動ソートできる |
| `status` | `todo:0 / doing:1 / done:2 / archived:3` | done と archived を分離し「完了済み履歴」を保持 |
| `task_type` | `normal:0 / habit:1 / improve:2` | AI 提案タスクと手動タスクを区別する |

<br>

#### scope 設計

<br>

| scope | 条件 | 用途 |
|:---|:---|:---|
| `active` | `deleted_at IS NULL ORDER BY priority ASC, due_date ASC NULLS LAST` | 通常の一覧表示（論理削除除外） |
| `not_archived` | `status != archived` | アクティブタスクの表示（完了済みタブと分離） |
| `today` | `due_date = HabitRecord.today_for_record` | ダッシュボードの「今日のタスク」 |
| `overdue` | `due_date < 今日 AND status not in (done, archived)` | 期限切れタスクの強調表示 |
| `must / should / could` | `priority = 対応値` | フィルタタブでの絞り込み |

<br>

#### 技術的なポイント

<br>

**① `unscope(:order)` による PG::GroupingError の解消**

<br>

`scope :active` に `ORDER BY due_date` が含まれているため、<br>
`GROUP BY priority` と組み合わせると PostgreSQL が GroupingError を発生させる。<br>
`priority_counts = base_tasks.not_archived.unscope(:order).group(:priority).count` とすることで<br>
ORDER BY を除去してから GROUP BY を実行し、件数集計クエリを安定させた。

<br>

**② `NOT_PROVIDED` を使わずにデフォルト値を設定する方針**

<br>

`task_type` は NOT NULL 制約があるが、フォームの `include_blank` で空文字が送信される場合がある。<br>
`before_validation :set_default_task_type` で空文字・nil を `"normal"` に変換することで<br>
`PG::NotNullViolation` を防ぎ、フォームの利便性（任意選択）も保持した。

<br>

**③ Stimulus による優先度カード排他選択の実装**

<br>

Tailwind の `peer-checked` は「ラジオボタンが外れた状態」のスタイルを自動リセットしない。<br>
3つのカードのうち1つを選択しても、他の2つのアクティブスタイルが残ってしまう問題があった。<br>
`priority_card_controller.js` を作成し、全カードをリセットしてから選択カードだけをアクティブにする設計で解決した。<br>
バリデーションエラー後のフォーム再表示時も `connect()` で選択状態を復元できる。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/task.rb` | 新規作成（enum・バリデーション・スコープ・インスタンスメソッド・before_validation） |
| `app/models/user.rb` | `has_many :tasks, dependent: :destroy` を追加 |
| `app/controllers/tasks_controller.rb` | 新規作成（index / new / create・Strong Parameters・ロックチェック） |
| `app/controllers/dashboards_controller.rb` | `@today_tasks` を追加 |
| `config/routes.rb` | `resources :tasks, only: [:index, :new, :create]` を追加 |
| `app/views/tasks/index.html.erb` | 新規作成（9番: タスク一覧ページ） |
| `app/views/tasks/new.html.erb` | 新規作成（10番: タスク新規作成ページ） |
| `app/views/dashboards/index.html.erb` | 「今日のタスク」セクションを追加 |
| `app/views/shared/_header.html.erb` | 「タスク管理」ナビリンクを追加（PC・モバイル両対応） |
| `app/javascript/controllers/priority_card_controller.js` | 新規作成（Stimulus: 優先度カード選択状態管理） |
| `app/javascript/controllers/index.js` | `priority-card` コントローラーを登録 |
| `config/locales/ja.yml` | Task モデルの属性名・エラーメッセージを追加 |
| `test/models/task_test.rb` | 新規作成（17件: バリデーション・enum・スコープ・インスタンスメソッド） |
| `test/controllers/tasks_controller_test.rb` | 新規作成（14件: index・new・create・ロックチェック・Strong Parameters） |

<br>

#### テスト結果

<br>
```
C-1テスト: 31件（モデル17件・コントローラー14件）
全テスト:  414 runs, 1042 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #C-2: タスクの完了チェック・ステータス管理

<br>

**ブランチ:** `feature/C-2-task-toggle-status`<br>
**完了日:** 2026-04-07<br>
**概要:** チェックボックスで即時完了（status=done）。Turbo Stream + Stimulus でページリロードなしに<br>
完了タブへの移動・アーカイブボタン・「すべてアーカイブ」機能を実装。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `Task#toggle_complete!` を追加（done↔todo切り替え・completed_at同時更新・archived?ガード） |
| Model | `Task#archive!` を追加（done?ガード・二重アーカイブ防止・completed_at保持） |
| Controller | `toggle_complete` アクション追加（PATCH /tasks/:id/toggle_complete・Turbo Stream・ロック中でも操作可） |
| Controller | `archive` アクション追加（PATCH /tasks/:id/archive・Turbo Stream） |
| Controller | `archive_all_done` アクション追加（PATCH /tasks/archive_all_done・update_allでN+1回避） |
| Controller | `include ActionView::RecordIdentifier` / `include ActionView::Helpers::TagHelper` を追加（dom_id/content_tag解決） |
| Controller | `recalculate_counts` private メソッドを追加（タブ件数の再集計） |
| Route | `member: toggle_complete/archive`・`collection: archive_all_done` を追加 |
| View | `index.html.erb` をパーシャル化・リストIDを `active-tasks-list-{tab}` / `done-tasks-list` に統一 |
| View | `_task_row.html.erb` を新規作成（未完了タスク行・Stimulus task-toggle接続） |
| View | `_done_task_row.html.erb` を新規作成（完了タスク行・アーカイブボタン・disabled切り替え） |
| View | `_tab_counts.html.erb` を新規作成（タブ件数バッジ・Turbo Streamで差し替え対象） |
| View | `task-count-display` IDを追加（「○件のタスク」のTurbo Stream更新対象） |
| JS | `task_toggle_controller.js` を新規作成（fetch + Turbo.renderStreamMessage・tab パラメータ送信・エラーロールバック） |
| JS | `index.js` に `task-toggle` コントローラーを登録 |
| Test | モデルテスト7件・コントローラーテスト13件を追加（420 runs, 1049 assertions） |

<br>

#### Turbo Stream の動作設計

<br>

| 操作 | Turbo Stream の動作 |
|:---|:---|
| 未完了→完了（done タブ以外） | `replace(dom_id(@task))` で行をその場で完了行に変更 |
| 完了→未完了（done タブ） | `remove(dom_id(@task))` で done リストから削除 |
| 個別アーカイブ | `remove(dom_id(@task))` で行を削除 |
| 一括アーカイブ | `replace("done-tasks-list")` で空状態のHTMLに置き換え |
| 件数バッジ更新 | `replace("task-tab-counts")` でタブ全体を差し替え |
| 件数テキスト更新 | `replace("task-count-display")` で「○件のタスク」を更新 |

<br>

#### 設計上の判断

<br>

**① ロック中でもチェック操作は可能な設計**

<br>

`toggle_complete` アクションには `require_unlocked` を適用しない。<br>
ロックは「新規追加・削除・編集」を制限するものであり、<br>
既存タスクの完了チェックはロック中でも継続できる設計にする（習慣の日次記録と同じ方針）。

<br>

**② タブに応じた Turbo Stream の動作分岐**

<br>

チェックボックス操作時、現在見ているタブによって Turbo Stream の動作を変える。<br>
「全て」「Must」「Should」「Could」タブでは `replace` でその場で見た目を変える（消えないようにする）。<br>
「完了済み」タブでは `remove` で行を消す（別タブに遷移すると復元が確認できる）。<br>
Stimulus の fetch 時に `?tab=` パラメータを URL SearchParams で取得してサーバーに送ることで<br>
コントローラー側で現在のタブを把握できる設計にした。

<br>

**③ archived は done タブに表示しない（パターンA採用）**

<br>

done タブのクエリを `where(status: :done)` のみに限定し、`archived` は除外する。<br>
アーカイブ = 「完了タブからも非表示にする整理操作」と定義し、<br>
データはDBに保持するが UI からは見えなくする（習慣のアーカイブと同じ設計思想）。

<br>

#### テスト結果

<br>
```
C-2テスト: 20件（モデル7件・コントローラー13件）
全テスト:  420 runs, 1049 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #C-3: タスク削除確認モーダル（M-2）・手動タスク削除

<br>

**ブランチ:** `feature/C-3-task-delete-modal`<br>
**完了日:** 2026-04-08<br>
**概要:** ai_generated=false の手動作成タスクのみ削除可能にする機能を実装。<br>
削除実行前に確認用モーダル（PC: 中央モーダル / スマホ: ボトムシート）を表示する。<br>
削除後は Turbo Stream でリアルタイム更新・トースト通知を表示する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Controller | `TasksController#destroy` を追加（ai_generated=true は 403・ロック中は302・論理削除） |
| Controller | `before_action :require_unlocked` を `:destroy` から外し、destroyアクション内で明示的に順序制御（ai_generated チェック→ロックチェック） |
| Controller | Turbo Stream: remove(タスク行) + replace(タブ件数) + replace(件数表示) + prepend(フラッシュ通知) |
| Route | `resources :tasks` の `only:` に `:destroy` を追加（DELETE /tasks/:id） |
| JS | `task_menu_controller.js` を新規作成（Stimulusコントローラー） |
| JS | `window.innerWidth >= 768` でデスクトップ（中央モーダル）/スマホ（ボトムシート）を切り替え |
| JS | `turbo:submit-end` イベントで削除後にモーダルを自動クローズ・`overflow: hidden` を解除 |
| JS | `_injectTabToForms()` で削除フォームに現在のタブを hidden input として動的追加（タブ維持） |
| JS | `disconnect()` でイベントリスナーを削除（メモリリーク修正） |
| View | `_task_row.html.erb` に「⋯」メニューボタンを追加（手動タスクかつロック解除中のみ表示） |
| View | `content_for :modals` でモーダルHTMLを `</body>` 直前に出力（CSSスタッキングコンテキスト対応） |
| View | `button_to` に `turbo_submits_with: "削除中..."` を追加（二重送信防止） |
| View | `_tab_counts.html.erb` の複数行文字列内 `#{}` を文字列結合 `+` に修正（Turbo Stream再描画時の未評価バグ修正） |
| View | `shared/_flash_message.html.erb` を新規作成（Turbo Stream用トースト通知パーシャル） |
| Layout | `application.html.erb` に `<div id="flash-area"></div>` を追加（Turbo Stream prependの挿入先） |
| Test | モデルテスト4件・コントローラーテスト5件を追加（429 runs, 1073 assertions） |

<br>

#### 設計上の判断

<br>

**① before_action :require_unlocked を destroy から外した理由**

<br>

`before_action` は登録順に実行されるため、`require_unlocked` が `ai_generated` チェックより先に動いてしまう。<br>
ロック中かつ AI 生成タスクを削除しようとしたとき、「AI生成タスクは削除できません（403）」ではなく<br>
「ロック中です（302）」が返るという優先順位の逆転が発生していた。<br>
`destroy` アクション内で「① ai_generated チェック → ② ロックチェック → ③ 論理削除」の順を明示的に制御することで解決した。<br>
```ruby
def destroy
  # ① 最優先: AI生成タスクは 403
  if @task.ai_generated?
    render ..., status: :forbidden
    return
  end

  # ② 次: ロック中は 302
  return if require_unlocked

  # ③ 論理削除を実行
  @task.soft_delete
end
```

<br>

**② Turbo Stream 再描画時の `_tab_counts.html.erb` の `#{}` 未評価バグ**

<br>

`link_to` の `class:` オプションが複数行にまたがる文字列の中で `#{}` を使うと、<br>
通常のページ表示では正しく評価されるが、Turbo Stream による `replace` 再描画時に<br>
`#{ current_tab == 'must' ? 'bg-red-500' : 'bg-white' }` が文字列としてそのまま出力されるバグがあった。<br>
文字列結合（`"共通クラス " + (条件式)`）に変更することで Turbo Stream 再描画時も正しく評価されるようになった。

<br>

**③ travel_to ブロック内のセッション喪失問題**

<br>

`ActionDispatch::IntegrationTest` では `travel_to` ブロック内でセッションが引き継がれない仕様がある。<br>
setup で行った `post login_path` が無効になり未ログイン扱いになるため、<br>
AI生成タスク削除テストなど travel_to を使わなくてよいテストは setup の時刻をそのまま使う設計にした。<br>
ロック中テスト（月曜への時刻移動が必要）だけは travel_to ブロック内で再ログインを行う。

<br>

#### テスト結果

<br>
```
C-3テスト: 9件（モデル4件・コントローラー5件）
全テスト:  429 runs, 1073 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #C-4: 週次振り返りのタスクスナップショット保存

<br>

**ブランチ:** `feature/C-4-weekly-reflection-task-summary`<br>
**完了日:** 2026-04-08<br>
**概要:** 振り返り完了時に当週のタスク実績を `weekly_reflection_task_summaries` にスナップショット保存。<br>
後からタスクを削除しても振り返り詳細ページにタスク実績が正確に表示される。<br>
合わせて toggle_complete 後にモーダルが開かなくなる既存バグを修正した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Migration | `weekly_reflection_task_summaries` テーブルを新規作成（task_id: on_delete: :nullify / weekly_reflection_id: on_delete: :cascade / title / priority / task_type / was_completed / completed_at / due_date） |
| Migration | UNIQUE 部分インデックス `idx_wr_task_summaries_on_wr_id_and_task_id`（WHERE task_id IS NOT NULL）を追加 |
| Model | `WeeklyReflectionTaskSummary` モデルを新規作成（enum: priority/task_type・バリデーション・スコープ・`create_all_for_reflection!`・`build_from_task`・`priority_label`・`priority_color_class`） |
| Model | `WeeklyReflection` に `has_many :task_summaries, class_name: "WeeklyReflectionTaskSummary", dependent: :destroy` を追加 |
| Service | `WeeklyReflectionCompleteService#call` のトランザクション内に `WeeklyReflectionTaskSummary.create_all_for_reflection!(@reflection)` を追加 |
| Controller | `WeeklyReflectionsController#show` に `@task_summaries = @weekly_reflection.task_summaries.by_priority.to_a` を追加 |
| View | `weekly_reflections/show.html.erb` のセクション②とセクション③の間にタスク実績セクションを追加（優先度別プログレスバー・was_completedフラグによる✅/⬜表示・打ち消し線・完了件数メッセージ） |
| View | `_task_modal.html.erb` を新規作成（モーダルHTMLをパーシャルに切り出し） |
| View | `_task_row.html.erb` の `content_for :modals` を `render "tasks/task_modal"` に変更（toggle後モーダル消失バグ修正） |
| Controller | `TasksController#toggle_complete` の Turbo Stream レスポンスにモーダル再注入（`turbo_stream.replace("task-modal-#{@task.id}", ...)`）を追加（バグ修正） |
| Layout | `application.html.erb` の重複 `id="flash-area"` を削除（`<main>` 外の1箇所を削除し `<main>` 内の1箇所に統一） |
| Test | `WeeklyReflectionTaskSummary` モデルテストを新規作成（21件） |

<br>

#### スナップショット設計の核心

<br>

| 設計 | 内容 |
|:---|:---|
| `task_id` の `on_delete: :nullify` | タスクが削除されると `task_id` が NULL になるが、`title` 等のスナップショットは保持される |
| `was_completed` フラグ | `task.done? \|\| task.archived?` を振り返り時点での完了状態として記録。後からタスクの状態が変わっても振り返り時点の事実が保たれる |
| UNIQUE 部分インデックス | `WHERE task_id IS NOT NULL` とすることで PostgreSQL の「NULL 同士は等しくない」仕様に対応 |
| プレースホルダー形式の OR クエリ | Arel を廃止し named bind variables（`:start / :end / :start_dt / :end_dt`）による SQL プレースホルダー形式を採用（可読性・SQLインジェクション対策） |
| `find_each` によるメモリ最適化 | `tasks.each` から `tasks.find_each` に変更。1000件ずつバッチ処理してメモリ効率を向上 |

<br>

#### toggle 後にモーダルが開かないバグの修正

<br>

**問題の原因:**<br>
`content_for :modals` はサーバーサイドのフルレンダリング時にのみ動作する。<br>
`toggle_complete` の Turbo Stream で `_task_row` を `replace` すると、<br>
パーシャル内の `content_for :modals` が `yield :modals` に反映されずモーダル HTML が DOM から消える。<br>
結果として `document.getElementById("task-modal-${id}")` が `null` を返し、<br>
`openMenu()` が何もできなくなっていた。

<br>

**修正内容:**

<br>

| 修正 | 内容 |
|:---|:---|
| `_task_modal.html.erb` を新規作成 | `_task_row.html.erb` のモーダルHTMLを独立したパーシャルに切り出す |
| `_task_row.html.erb` を修正 | `content_for :modals do...end` を `render "tasks/task_modal", task: task` に変更。フルレンダリング時はインラインで直接DOMに出力される |
| `toggle_complete` アクションを修正 | 未完了に戻す `else` ブロックに `turbo_stream.replace("task-modal-#{@task.id}", partial: "tasks/task_modal", ...)` を追加。DOM に再注入することで `openMenu()` が正常に動作する |
| `application.html.erb` を修正 | `<main>` 外の重複 `id="flash-area"` を削除。同一 ID が2つあると Turbo のDOM整合性が崩れる |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `db/migrate/YYYYMMDDHHMMSS_create_weekly_reflection_task_summaries.rb` | 新規作成 |
| `app/models/weekly_reflection_task_summary.rb` | 新規作成 |
| `app/models/weekly_reflection.rb` | `has_many :task_summaries` を追加 |
| `app/services/weekly_reflection_complete_service.rb` | トランザクション内に `WeeklyReflectionTaskSummary.create_all_for_reflection!` を追加 |
| `app/controllers/weekly_reflections_controller.rb` | `show` アクションに `@task_summaries` を追加 |
| `app/views/weekly_reflections/show.html.erb` | タスク実績セクションを追加 |
| `app/views/tasks/_task_modal.html.erb` | 新規作成（モーダルHTMLパーシャル分離） |
| `app/views/tasks/_task_row.html.erb` | `content_for :modals` → `render "tasks/task_modal"` に変更 |
| `app/views/tasks/index.html.erb` | `task-modals-container` コンテナを追加 |
| `app/controllers/tasks_controller.rb` | `toggle_complete` にモーダル再注入を追加 |
| `app/views/layouts/application.html.erb` | `<main>` 外の重複 `id="flash-area"` を削除 |
| `test/fixtures/weekly_reflection_task_summaries.yml` | 新規作成 |
| `test/models/weekly_reflection_task_summary_test.rb` | 新規作成（21件） |

<br>

#### テスト結果

<br>

```
C-4テスト: 21 runs, 46 assertions, 0 failures, 0 errors, 0 skips
全テスト:  450 runs, 1119 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #C-5: タスクのアラーム通知（GoodJob + メール）

<br>

**ブランチ:** `feature/C-5-task-alarm-job`<br>
**完了日:** 2026-04-12<br>
**概要:** `scheduled_at` と `alarm_enabled=true` のタスクに対して、`alarm_minutes_before` 分前に<br>
GoodJob でジョブをスケジュールし、LINE またはメールで通知を送信する機能を実装。<br>
通知履歴を `notification_logs` に記録し、日次通知上限チェックを実装。<br>
タスク作成・更新フォームにアラーム設定 UI（実施予定日時・アラーム ON/OFF・分数入力）を追加。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `NotificationLog` モデルを新規作成（enum: notification_type/channel/status・record_success/record_failure/record_skip クラスメソッド） |
| Mailer | `TaskMailer#alarm_notification` を新規作成（HTML + テキスト両形式・ユーザーのタイムゾーンで時刻表示） |
| Job | `TaskAlarmJob` を新規作成（スキップ条件5種・メール送信・ログ記録・daily_notification_count のatomic更新） |
| Controller | `TasksController#create` にアラームジョブエンキュー処理（`enqueue_alarm_job_if_needed`）を追加 |
| Controller | `TasksController#update` を新規追加（古いジョブを JSONB `@>` 演算子で安全削除・再スケジュール） |
| Controller | `TasksController#edit` を新規追加・`routes.rb` に `:edit` / `:update` を追加 |
| View | `tasks/new.html.erb` に実施予定日時（datetime-local）・アラーム設定 UI を追加 |
| View | `tasks/edit.html.erb` を新規作成（scheduled_at を JST で表示・アラーム設定 UI） |
| View | `tasks/_task_modal.html.erb` に「✏️ 編集する」リンクを追加（デスクトップ・スマホ両対応） |
| JS | `alarm_toggle_controller.js` を新規作成（アラームOFF時に分数入力欄を disabled にする） |
| JS | `index.js` に `alarm-toggle` コントローラーを登録 |
| i18n | `config/locales/ja.yml` に `date.formats.long` / `time.formats.long` を追加 |
| Test | `TaskAlarmJobTest`（8ケース）・`TaskMailerTest` を追加 |
| Fix | `test/fixtures/notification_logs.yml` を削除（NOT NULL 違反の根本解決） |
| Fix | `HabitRecordSaveServiceTest` の日付を未来日付に変更（フィクスチャとの衝突解消） |

<br>

#### スキップ条件（TaskAlarmJob）

<br>

| 条件 | 処理 |
|:---|:---|
| `alarm_enabled = false` | return（ログなし） |
| `scheduled_at = nil` | return（ログなし） |
| `status = done / archived` | return（ログなし） |
| `notification_enabled = false` | return（ログなし） |
| `daily_notification_count >= daily_notification_limit` | `NotificationLog.record_skip` して return |

<br>

#### 通知チャネルの優先順位

<br>

| 優先順位 | チャネル | 条件 |
|:---|:---|:---|
| 1位 | LINE | `line_notification_enabled = true` かつ `line_user_id` が存在する |
| 2位 | メール | `email_notification_enabled = true`（LINE 未設定時のフォールバック） |

<br>

LINE 通知は G-1（LINE Messaging API 通知基盤）実装後に有効化予定。<br>
現在は LINE が設定されていても自動的にメール通知にフォールバックする。

<br>

#### cancel_existing_alarm_jobs の設計

<br>

update 時の古いジョブ削除に PostgreSQL の JSONB `@>`（containment）演算子を使用。

<br>

```ruby
GoodJob::Job
  .where(job_class: "TaskAlarmJob")
  .where(finished_at: nil)
  .where("serialized_params @> ?", { arguments: [task.id] }.to_json)
  .delete_all
```

<br>

| 方式 | 問題点 |
|:---|:---|
| `LIKE "%#{task.id}%"` | task.id=1 が id=10, 100 にもマッチする誤削除リスク |
| JSONB `@>` 演算子 | arguments 配列の値を正確に一致させるため誤削除なし・インデックスも有効 |

<br>

#### daily_notification_count の atomic 更新

<br>

```ruby
# ❌ Ruby 側で計算 → 同時実行でカウントがズレる
user_setting.update_columns(daily_notification_count: user_setting.daily_notification_count + 1)

# ✅ DB 側で計算 → 原子的操作で競合しない
UserSetting.where(id: user_setting.id)
           .update_all("daily_notification_count = daily_notification_count + 1")
```

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/notification_log.rb` | 新規作成（enum定義・record_success/failure/skip） |
| `app/mailers/task_mailer.rb` | 新規作成（alarm_notification） |
| `app/views/task_mailer/alarm_notification.html.erb` | 新規作成（HTMLメール本文） |
| `app/views/task_mailer/alarm_notification.text.erb` | 新規作成（テキストメール本文） |
| `app/jobs/task_alarm_job.rb` | 新規作成（GoodJobジョブ本体） |
| `app/controllers/tasks_controller.rb` | create/update にエンキュー処理・edit/update アクション追加 |
| `app/views/tasks/new.html.erb` | scheduled_at・アラーム設定 UI 追加 |
| `app/views/tasks/edit.html.erb` | 新規作成 |
| `app/views/tasks/_task_modal.html.erb` | 「✏️ 編集する」リンクを追加 |
| `app/javascript/controllers/alarm_toggle_controller.js` | 新規作成 |
| `app/javascript/controllers/index.js` | alarm-toggle コントローラーを登録 |
| `config/locales/ja.yml` | date/time の :long フォーマットを追加 |
| `config/routes.rb` | :edit / :update を追加 |
| `test/jobs/task_alarm_job_test.rb` | 新規作成（8ケース） |
| `test/mailers/task_mailer_test.rb` | 自動生成から修正（引数なし呼び出しを修正） |
| `test/fixtures/notification_logs.yml` | 削除（NOT NULL 違反の根本解決） |
| `test/services/habit_record_save_service_test.rb` | 日付を未来日付（2030-01-01〜03）に変更（フィクスチャ衝突解消） |

<br>

#### テスト結果

<br>

```
C-5テスト: 9件（JobTest 8件・MailerTest 1件）
全テスト:  459 runs, 1150 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #C-6: ダッシュボードの Must/Should/Could 別タスク達成率表示

<br>

**ブランチ:** `feature/C-6-dashboard-task-priority-stats`<br>
**完了日:** 2026-04-18<br>
**概要:** ダッシュボードに今週のタスク優先度（Must/Should/Could）別の週次達成率プログレスバーを追加。<br>
あわせて全画面の達成率表記・カラーを統一し、習慣フォームのチェック型週次目標値を非表示化した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Controller | `DashboardsController` に `build_task_priority_stats` メソッドを追加（Must/Should/Could 別の集計） |
| Controller | `group(:priority).count` で2クエリのみ（N+1なし）。Rails enum の `group()` はキーが文字列で返るため `priority_map` 変換不要 |
| Controller | `in_time_zone.beginning_of_day` で Date 型と datetime 型の BETWEEN 比較のタイムゾーンズレを修正 |
| Controller | archived タスクも done としてカウント（「完了後に整理したもの」として達成実績に含める） |
| View | ダッシュボードに「今週のタスク達成率」セクションを追加（Must=赤/Should=青/Could=緑） |
| View | `data-testid` を各要素に付与してテストから正確に参照できるように |
| View | total が 0 の優先度は行ごと非表示。全優先度が 0 件の場合はカード全体を非表示 |
| Helper | `ApplicationHelper` に `rate_hex_color` / `habit_progress_text` を追加 |
| Helper | Tailwind 動的クラス（`bg-<%= rate_color %>-500`）はビルド時検出されないため `rate_hex_color` によるインラインスタイルに統一 |
| Helper | `habit_progress_text` でダッシュボード・週次振り返り・習慣管理の達成率表記を統一 |
| View | チェック型の分母を `weekly_target` → `effective_weekly_target`（除外日考慮後）に変更 |
| View | 週次振り返り一覧の色分けを4段階（黄色あり）から3段階（緑/青/赤）に統一 |
| View | 習慣管理のチェック型週次目標の単位を「回」→「日」に変更 |
| JS | `habit_form_controller.js` に `weeklyTargetField` / `weeklyTargetHiddenWrapper` ターゲットを追加 |
| JS | `toggleUnit()` でチェック型選択時に週次目標値フィールドを非表示に切り替え |
| View | `habits/new.html.erb` / `habits/edit.html.erb` でチェック型の週次目標値を非表示（hidden で 7 を送信） |
| Test | `data-testid` ベースの `assert_select` でテストの誤検知を防止（8件追加） |
| Test | setup に fixtures タスクの論理削除・ログイン成功保証を追加 |

<br>

#### N+1 を起こさない設計（2クエリのみ）

<br>

```ruby
# 今週タスクの優先度別総件数（1クエリ）
total_counts = base_scope.unscope(:order).group(:priority).count

# 完了（done + archived）件数（1クエリ）
done_counts = base_scope.unscope(:order)
                        .where(status: [Task.statuses[:done], Task.statuses[:archived]])
                        .group(:priority).count
```

<br>

ループ内でDBを叩かないため、タスクが何件あっても常に2クエリで済む。

<br>

#### タイムゾーン修正のポイント

<br>

`HabitRecord.today_for_record` は `Date` 型を返す。<br>
`created_at`（datetime 型）との BETWEEN 比較では<br>
`week_start.in_time_zone.beginning_of_day` / `today.in_time_zone.end_of_day` を使う。<br>
`Date#beginning_of_day` のままだと UTC 変換がズレてテスト環境でタスクが集計されないバグが発生する。

<br>

#### Rails enum の group() のキー型に注意

<br>

```ruby
# group(:priority).count の返り値
{ "must" => 3, "should" => 5, "could" => 2 }  # キーは整数ではなく文字列
```

<br>

Rails の enum カラムを `group().count` すると、キーは整数（0/1/2）ではなく<br>
enum 名の文字列（`"must"/"should"/"could"`）で返る。<br>
`priority_map` による整数→文字列変換は不要で `total_counts["must"]` で直接アクセスできる。

<br>

#### Tailwind 動的クラスの問題と解決

<br>

| 問題 | 解決 |
|:---|:---|
| `bg-<%= rate_color %>-500` はビルド時に検出されず CSS が生成されない | `rate_hex_color` によるインラインスタイル（`background-color: #22c55e`）に変更 |
| `text-<%= rate_color %>-600` も同様 | `style="color: <%= rate_hex_color(rate) %>"` に変更 |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/controllers/dashboards_controller.rb` | `build_task_priority_stats` メソッドを追加（タイムゾーン修正・2クエリ設計） |
| `app/helpers/application_helper.rb` | `rate_hex_color` / `habit_progress_text` を追加 |
| `app/views/dashboards/index.html.erb` | 今週のタスク達成率セクション追加・習慣達成率カラーをインラインスタイルに変更・表記統一 |
| `app/views/weekly_reflections/index.html.erb` | プログレスバー色を4段階→3段階に統一・`habit_progress_text` で表記統一 |
| `app/views/weekly_reflections/new.html.erb` | プログレスバー色・表記を統一・`effective_weekly_target` に変更 |
| `app/views/habits/index.html.erb` | チェック型週次目標の単位を「回」→「日」に変更 |
| `app/views/habits/new.html.erb` | チェック型の週次目標値フィールドを非表示・hidden input（value=7）を追加 |
| `app/views/habits/edit.html.erb` | チェック型は `hidden_field :weekly_target, value: 7` のみに変更 |
| `app/javascript/controllers/habit_form_controller.js` | `weeklyTargetField` / `weeklyTargetHiddenWrapper` ターゲット追加・`toggleUnit()` に表示切替ロジック追加 |
| `test/controllers/dashboards_controller_test.rb` | 8件追加（`data-testid` ベース・fixtures干渉対策・ログイン成功保証） |
| `test/integration/dashboard_test.rb` | h2テキスト正規表現を更新（`今週の習慣達成率` に変更） |

<br>

#### テスト結果

<br>

```
C-6テスト: 8 runs, 38 assertions, 0 failures, 0 errors, 0 skips
全テスト:  464 runs, 1180 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #C-7: タスクのAI編集ページ（11番・AI提案モーダル経由）

<br>

**ブランチ:** `feature/C-7-task-ai-edit`<br>
**完了日:** 2026-04-19<br>
**概要:** AI提案プレビューモーダルからのみアクセス可能なタスク編集ページを実装。<br>
通常の `TasksController#edit` とは別ルートとして `ai_edit` / `ai_update` を追加。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Route | `get :ai_edit` / `patch :ai_update` を member ブロックに追加 |
| Controller | `ai_edit` アクション: session に `ai_context_task_id` フラグを設定 |
| Controller | `ai_update` アクション: フラグ検証 → 限定 params で保存 → アラーム再スケジュール |
| Controller | `set_ai_context` / `verify_ai_context` / `clear_ai_context` を private に追加 |
| Controller | `ai_update_params`: title・due_date・estimated_hours のみ許可（priority 除外） |
| View | `app/views/tasks/ai_edit.html.erb` 新規作成（AI経由限定バナー付き） |
| View | `form_with model: @task, data: { turbo: false }` で Turbo を無効化し通常フォーム送信 |
| Test | `test/controllers/tasks_ai_edit_controller_test.rb` 新規作成（9件） |<br><br>

<br>

#### アクセス制御の設計

<br>

ai_edit（GET）
↓ session[:ai_context_task_id] = @task.id を設定
ai_edit.html.erb を表示（AI経由限定バナー・優先度は読み取り専用）
ai_update（PATCH）
↓ session[:ai_context_task_id] == @task.id か検証
一致しない → tasks_path へリダイレクト（「AI提案モーダル経由でのみ実行できます」）
一致する   → ai_update_params で保存 → session クリア → tasks_path へ

<br>

#### 優先度を変更不可にする二重防御

<br>

| 防御層 | 実装 |
|:---|:---|
| UI 層 | `ai_edit.html.erb` で priority フィールドを静的テキスト表示のみにする |
| サーバー層 | `ai_update_params` に `:priority` を含めない |<br><br>

<br>

#### テスト結果

<br>

```
C-7テスト:  9 runs, 37 assertions, 0 failures, 0 errors, 0 skips
全テスト:  473 runs, 1217 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-1: UserPurpose モデル・PMVV入力ページ

<br>

**ブランチ:** `feature/D-1-user-purpose-model`<br>
**完了日:** 2026-04-19<br>
**概要:** PMVV（Purpose/Mission/Vision/Value/Current）を入力・バージョン管理する<br>
UserPurpose モデルと入力ページを実装。<br>
保存時に AI 分析ジョブをエンキューし、バックグラウンドで分析を開始する設計。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `UserPurpose` モデル作成（`belongs_to :user` / `enum :analysis_state` / バリデーション / スコープ） |
| Model | `before_validation :set_version` で新規作成時にバージョン番号を自動採番 |
| Model | `before_save :deactivate_previous_versions` で保存前に旧バージョンを `is_active=false` に一括更新 |
| Model | `UserPurpose.current_for(user)` クラスメソッドで現在有効な PMVV を1件取得 |
| Model | `validate :at_least_one_field_present` で5フィールドのうち1つ以上の入力を必須化 |
| Model | `User` に `has_many :user_purposes, dependent: :destroy` を追加 |
| Controller | `UserPurposesController` 作成（show / new / create / edit / update） |
| Controller | `before_action :require_login` で全アクションに認証を要求 |
| Controller | `update` アクションは既存レコードの変更ではなく新規レコード作成（バージョン管理のため） |
| Job | `PurposeAnalysisJob` スタブ作成（D-2で AI API 呼び出しを本実装予定） |
| Route | `resource :user_purpose`（単数形）を追加（ID なし URL: `/user_purpose` / `/user_purpose/new` 等） |
| View | 16番: PMVV目標管理ページ（`analysis_state` 4状態バナー切替・バージョン履歴表示・Empty State） |
| View | 17番: PMVV入力ページ（5フィールド・voice-input Stimulus コントローラー連携🎤ボタン） |
| View | `_voice_field.html.erb` パーシャルで5フィールドを DRY に実装 |
| View | `form_with` の `url:` と `method:` を明示（単数形リソースは自動ルーティング解決不可のため） |
| Header | PC用・モバイル用ヘッダーに「目標管理」ナビリンクを追加 |
| i18n | `ja.yml` に `user_purpose` の属性名・エラーメッセージを追加 |

<br>

#### バージョン管理の設計

<br>

| 設計 | 内容 |
|:---|:---|
| 新規作成方式 | 更新のたびに新しいレコードを作成し、古いレコードを `is_active=false` に変更する |
| `before_validation :set_version` | 同一ユーザーの最大バージョン + 1 を自動採番（`maximum(:version).to_i + 1`） |
| `before_save :deactivate_previous_versions` | `update_all` で1クエリ一括更新（N+1防止） |
| `is_active` フラグ | 常に1件のみ `true` の状態を保証する |
| 過去バージョン | `is_active=false` のレコードを履歴として全件保持する |

<br>

#### analysis_state の遷移

<br>
pending(0) → analyzing(1) → completed(2)
↘ failed(3)

<br>

| 状態 | 意味 |
|:---|:---|
| `pending` | 保存直後。GoodJob キューに追加済み |
| `analyzing` | D-1 スタブではここで止まる（D-2 で AI 呼び出し後に遷移予定） |
| `completed` | AI 分析が正常完了（D-2 以降で実装） |
| `failed` | AI 分析が失敗（D-2 以降で実装） |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/user_purpose.rb` | 新規作成（enum / バリデーション / スコープ / before_validation / before_save / current_for） |
| `app/models/user.rb` | `has_many :user_purposes, dependent: :destroy` を追加 |
| `app/controllers/user_purposes_controller.rb` | 新規作成（show / new / create / edit / update） |
| `app/jobs/purpose_analysis_job.rb` | 新規作成（D-2 連携用スタブ・analysis_state を analyzing に変更するのみ） |
| `app/views/user_purposes/show.html.erb` | 新規作成（16番: PMVV目標管理ページ） |
| `app/views/user_purposes/new.html.erb` | 新規作成（17番: PMVV入力ページ・新規） |
| `app/views/user_purposes/edit.html.erb` | 新規作成（17番: PMVV入力ページ・編集） |
| `app/views/user_purposes/_voice_field.html.erb` | 新規作成（音声入力付きテキストエリアパーシャル） |
| `app/views/shared/_header.html.erb` | 「目標管理」ナビリンクを追加（PC・モバイル両対応） |
| `config/routes.rb` | `resource :user_purpose, only: [:show, :new, :create, :edit, :update]` を追加 |
| `config/locales/ja.yml` | `user_purpose` の属性名・エラーメッセージを追加 |

<br>

#### テスト結果

<br>

```
全テスト:  473 runs, 1217 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-2: PMVV AI分析ジョブ（GoodJob + Gemini API）

<br>

**ブランチ:** `feature/D-2-purpose-analysis-job`<br>
**完了日:** 2026-04-25<br>
**概要:** UserPurpose 保存後に GoodJob で非同期実行される AI 分析ジョブを実装。<br>
Gemini REST API（gemini-2.5-flash）をデフォルトとし、Groq API（openai/gpt-oss-120b）へのフォールバックを備える。<br>
analysis_state を pending → analyzing → completed/failed に遷移させ、<br>
Turbo Stream で 16番ページをリアルタイム更新する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Service | `AiClient` 抽象化クラスを新規作成（`app/services/ai_client.rb`）<br>Gemini REST API / Groq API を faraday で直接呼び出す<br>Gemini → Groq のフォールバック・429 レート制限時の指数バックオフ・ブロックキャッシュを実装 |
| Model | `AiAnalysis` モデルを新規作成（`app/models/ai_analysis.rb`）<br>`is_latest` フラグ管理・`before_create :deactivate_previous_analyses` コールバック<br>`at_least_one_parent_present` バリデーション |
| Job | `PurposeAnalysisJob` を D-1 スタブから完全実装（`app/jobs/purpose_analysis_job.rb`）<br>Chain-of-Thought 3ステップ プロンプト・JSON パース強化・Turbo Stream 通知 |
| DB | `ai_analyses.model_name` → `ai_model_name` にカラムをリネーム<br>（`model_name` は ActiveRecord 予約語のため） |
| Controller | `retry_analysis` アクションを追加（POST で分析ジョブを再実行） |
| View | `_analysis_status_banner.html.erb` パーシャルを新規作成（Turbo Stream target）<br>`show.html.erb` に `turbo_stream_from` を追加 |
| Route | `post :retry_analysis, on: :member` を追加 |
| Test | `AiAnalysis` モデルテスト（5件）・`PurposeAnalysisJob` テスト（6件）を追加<br>`Minitest::Mock` による `AiClient` スタブ方式を採用 |

<br>

#### AI API の構成

<br>

| プロバイダ | モデル | 役割 | 取得先 |
|:---|:---|:---|:---|
| Google Gemini | `gemini-2.5-flash` | デフォルト | https://aistudio.google.com/ |
| Groq | `openai/gpt-oss-120b` | フォールバック | https://console.groq.com/ |

<br>

#### フォールバック設計

<br>
AiClient#analyze
↓ Gemini が利用可能か確認（Rails.cache ブロックフラグ）
↓ Gemini REST API 呼び出し
↓ 429 レート制限 → 指数バックオフ（1秒→2秒）でリトライ（最大2回）
↓ 失敗 → Gemini を5分間ブロック（Rails.cache に記録）
↓ Groq API にフォールバック
↓ 全プロバイダ失敗 → nil を返す

<br>

#### Chain-of-Thought プロンプト設計

<br>

| ステップ | 内容 |
|:---|:---|
| ステップ1（分析） | PMVV の整合性確認・現状と Vision のギャップ特定・Why×3 で根本原因を深掘り |
| ステップ2（コーチング） | 強みと改善点の特定・Value を守りながら Vision に近づく方法・励ましと行動指針 |
| ステップ3（提案） | 具体的な習慣3つ・タスク3つを提案（各提案に有効な理由を添付） |

<br>

#### ai_analyses に保存されるデータ

<br>

| カラム | 内容 |
|:---|:---|
| `analysis_comment` | PMVV の総合分析コメント（200〜400文字） |
| `root_cause` | 現状と Vision のギャップの根本原因（Why×3・150〜300文字） |
| `coaching_message` | 励ましと具体的なアドバイス（150〜300文字） |
| `improvement_suggestions` | 改善のための全体的な提案（100〜200文字） |
| `actions_json` | 推奨アクション（習慣3件・タスク3件）の配列（JSONB） |
| `input_snapshot` | 分析実行時の PMVV データのスナップショット（JSONB） |
| `ai_model_name` | 実際に使用した AI モデル名（正確に記録） |
| `prompt_version` | プロンプトのバージョン（`v1.1`）|
| `crisis_detected` | 危機ワード検出フラグ |

<br>

#### analysis_state の遷移

<br>
pending(0) → analyzing(1) → completed(2)
↘ failed(3)

<br>

| 状態 | タイミング | UI 表示 |
|:---|:---|:---|
| `pending` | UserPurpose 保存直後 | ⏳ AI分析待機中... |
| `analyzing` | ジョブ実行開始時 | 🤖 AIが分析しています（スピナー） |
| `completed` | 分析完了時 | ✅ AI分析が完了しました |
| `failed` | 分析失敗時 | ⚠️ 分析に失敗しました（再試行ボタン付き） |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/services/ai_client.rb` | 新規作成（Gemini REST API / Groq API クライアント・フォールバック設計） |
| `app/models/ai_analysis.rb` | 新規作成（is_latest 管理・before_create コールバック・バリデーション） |
| `app/jobs/purpose_analysis_job.rb` | D-1 スタブから完全実装（Chain-of-Thought・JSON パース・Turbo Stream）|
| `app/views/user_purposes/_analysis_status_banner.html.erb` | 新規作成（Turbo Stream target・4状態バナー） |
| `app/views/user_purposes/show.html.erb` | `turbo_stream_from` 追加・パーシャル化 |
| `app/controllers/user_purposes_controller.rb` | `retry_analysis` アクション追加 |
| `config/routes.rb` | `post :retry_analysis, on: :member` 追加 |
| `config/locales/ja.yml` | AI 分析関連日本語メッセージ追加 |
| `Gemfile` | `gem "faraday"` 追加（Gemini REST API / Groq API の HTTP 通信） |
| `db/migrate/YYYYMMDDHHMMSS_rename_model_name_in_ai_analyses.rb` | `model_name` → `ai_model_name` にリネーム |
| `test/models/ai_analysis_test.rb` | 新規作成（5件：バリデーション・is_latest・scope） |
| `test/jobs/purpose_analysis_job_test.rb` | 新規作成（6件：正常系・異常系・前後文章パース） |

<br>

#### テスト結果

<br>

```
D-2テスト: 11件（モデル5件・ジョブ6件）
全テスト:  484 runs, 1242 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-3: PMVV目標管理ページ（16番）・AI分析結果ページ（18番）

<br>

**ブランチ:** `feature/D-3-pmvv-show-and-ai-result`<br>
**完了日:** 2026-04-26<br>
**概要:** AI分析が完了した PMVV の詳細結果ページと、<br>
目標管理ページの4状態バナー自動切替（Turbo Stream）を実装。<br>
チェックした提案を習慣・タスクとしてダッシュボードに一括登録できる。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Route | `get :ai_result` / `post :apply_proposals` を `resource :user_purpose` の member に追加 |
| Controller | `ai_result` アクション新規追加（input_snapshot から PMVV 5要素を @snapshot_* に展開・actions_json を @habit_proposals / @task_proposals に分離） |
| Controller | `apply_proposals` アクション新規追加（インデックス番号でセキュリティ設計・トランザクション内で習慣・タスクを一括 create!） |
| Controller | `show` アクションに `@ai_analysis` 取得処理を追加（completed バナーの「結果を見る →」用） |
| View | `_analysis_status_banner.html.erb` の completed ブランチに `link_to "結果を見る →", ai_result_user_purpose_path` を実装 |
| View | `ai_result.html.erb` を新規作成（18番・PMVV 5要素・AI分析コメント・真の原因・コーチングメッセージ・推奨アクション） |
| View | `shared/_ai_disclaimer.html.erb` を新規作成（AI免責バナーパーシャル・全 AI 出力ページ共通） |
| View | `show.html.erb` のバナーパーシャル呼び出しに `ai_analysis: @ai_analysis` を追加 |
| Job | `purpose_analysis_job.rb` の `broadcast_state_update` に `ai_analysis` を渡すよう修正（Turbo Stream 更新失敗バグを解消） |
| i18n | `config/locales/ja.yml` の `activerecord:` 重複定義を1か所に統合 |
| Fix | `ja.yml` の `task.title.blank` メッセージをモデルの定義と統一（テスト失敗を修正） |
| Infra | `config/cable.yml` の development adapter を `async` → `solid_cable` に変更（Turbo Stream 有効化） |
| Infra | `config/database.yml` に `cable:` 接続を各環境に追加（solid_cable 用） |
| Infra | `solid_cable:install` を実行・`solid_cable_messages` テーブルを作成 |
| Migration | `db/migrate/YYYYMMDDHHMMSS_add_channel_hash_to_solid_cable_messages.rb` を追加（solid_cable 3.0.12 が要求する `channel_hash` カラムを追加） |

<br>

#### 推奨アクション登録の設計

<br>

| 設計 | 内容 |
|:---|:---|
| インデックス番号で送信 | 提案のタイトルをパラメータとして送ると攻撃者が任意のタイトルを送信できるリスクがある。チェックボックスの value にインデックス番号を使い、サーバー側で AI 分析結果から提案を特定する設計 |
| トランザクション内で一括作成 | `ActiveRecord::Base.transaction` で習慣・タスクを一括 create!。途中で失敗した場合は全てロールバックされる |
| 習慣のデフォルト設定 | `measurement_type: :check_type, weekly_target: 5`（まず無理なく続けられる頻度をデフォルトにする） |
| タスクの分類 | `task_type: :improve, ai_generated: true`（C-3 実装の「手動タスクのみ削除可能」と連動） |

<br>

#### input_snapshot から PMVV を表示する理由

<br>

AI 分析後にユーザーが PMVV を更新した場合でも、<br>
「この分析はこの内容で行われた」という記録を正確に表示するために<br>
最新の `@current_purpose` ではなく `input_snapshot`（JSONB）から5要素を取り出す。<br>
`with_indifferent_access` でシンボル・文字列どちらのキーでもアクセス可能にしている。

<br>

#### Turbo Stream 自動更新の仕組み

<br>

```
ユーザーが PMVV を保存
  ↓ PurposeAnalysisJob がエンキューされる
  ↓ GoodJob が分析を実行する
  ↓ 分析状態が変わるたびに broadcast_state_update を呼ぶ
  ↓ solid_cable が solid_cable_messages テーブルに書き込む
  ↓ ブラウザの Action Cable が 100ms ポーリングで検知する
  ↓ Turbo Stream が _analysis_status_banner.html.erb を自動で差し替える
```

<br>

#### solid_cable 導入の経緯

<br>

| アダプター | 問題 | 結果 |
|:---|:---|:---:|
| `async`（元の設定） | 同一プロセスのメモリ内でのみ通信。GoodJob のバックグラウンドスレッドからブロードキャストしてもブラウザへの通知が届かない | ❌ |
| `solid_cable` | PostgreSQL の DB をブローカーとして使う。プロセスをまたいでも通知が届く。Redis 不要 | ✅ |

<br>

`solid_cable 3.0.12` は `channel_hash` カラムを要求するが、<br>
`solid_cable:install` で生成されるマイグレーションには含まれていないため<br>
別途マイグレーションを追加して `channel_hash bigint` カラムを追加した。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `config/routes.rb` | `get :ai_result` / `post :apply_proposals` を member ブロックに追加 |
| `app/controllers/user_purposes_controller.rb` | `ai_result` / `apply_proposals` アクションを追加・`show` に `@ai_analysis` 取得を追加 |
| `app/views/user_purposes/show.html.erb` | バナーパーシャルに `ai_analysis: @ai_analysis` を追加 |
| `app/views/user_purposes/_analysis_status_banner.html.erb` | completed 状態の「結果を見る →」リンクを実装 |
| `app/views/user_purposes/ai_result.html.erb` | 新規作成（18番 AI分析結果ページ） |
| `app/views/shared/_ai_disclaimer.html.erb` | 新規作成（AI免責バナーパーシャル） |
| `app/jobs/purpose_analysis_job.rb` | `broadcast_state_update` に `ai_analysis` を渡すよう修正 |
| `config/cable.yml` | `development: adapter: solid_cable` に変更 |
| `config/database.yml` | 各環境に `cable:` 接続を追加 |
| `db/cable_migrate/20260426000001_create_solid_cable_messages.rb` | solid_cable テーブル作成 |
| `db/migrate/YYYYMMDDHHMMSS_add_channel_hash_to_solid_cable_messages.rb` | `channel_hash bigint` カラムを追加 |
| `config/locales/ja.yml` | `activerecord:` の重複定義を統合・`task.title.blank` を修正 |

<br>

#### テスト結果

<br>

```
全テスト: 484 runs, 1242 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-4: 週次振り返り AI分析ジョブ（GoodJob）

<br>

**ブランチ:** `feature/D-4-weekly-reflection-analysis-job`<br>
**完了日:** 2026-04-26<br>
**概要:** 振り返り完了後に GoodJob で非同期実行される AI 分析ジョブを実装。<br>
Gemini REST API（gemini-2.5-flash）をデフォルトとし、Groq API（openai/gpt-oss-120b）へのフォールバックを備える（#D-2 の AiClient を共通利用）。<br>
振り返りデータと、PMVV が設定されている場合はその整合性分析も含む Chain-of-Thought プロンプトを設計。<br>
分析結果を `ai_analyses` テーブルに保存し、`ai_analysis_count` を原子的にインクリメントする。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Job | `WeeklyReflectionAnalysisJob` を新規作成（`app/jobs/weekly_reflection_analysis_job.rb`）<br>Chain-of-Thought 3ステップ プロンプト・PMVV 有無による動的プロンプト分岐・JSON パース強化 |
| Service | `WeeklyReflectionCompleteService` にジョブエンキュー処理を追加<br>トランザクション外での `perform_later`（A-7 設計原則に従う）・月次上限の事前チェック |
| Model | `User` に `after_create :create_user_setting` コールバックを追加<br>ユーザー登録時に `UserSetting` を自動作成（欠落によるジョブスキップを防ぐ） |
| i18n | `config/locales/ja.yml` に `UserSetting` のバリデーションエラーメッセージを追加 |
| Test | `WeeklyReflectionAnalysisJob` テスト 8件・`WeeklyReflectionCompleteService` テスト 2件追加<br>`include ActiveJob::TestHelper` で `assert_enqueued_with` / `assert_no_enqueued_jobs` を使用 |

<br>

#### プロンプト設計

<br>

| ステップ | 内容 |
|:---|:---|
| ステップ1（分析） | 振り返りデータから「できなかった本質的な原因」を Why×3 で深掘り・PMVV がある場合は Vision/Value とのギャップを特定 |
| ステップ2（コーチング） | 強みの特定・PMVV に沿った改善策・励ましと行動指針 |
| ステップ3（提案） | 習慣3件・タスク3件（各提案に有効な根拠を添付） |

<br>

#### ai_analyses に保存されるデータ

<br>

| カラム | 内容 |
|:---|:---|
| `analysis_type` | `:weekly_reflection`（enum 値 0） |
| `analysis_comment` | 今週の振り返りの総合分析コメント（200〜400文字） |
| `root_cause` | できなかった本質的な原因（Why×3・150〜300文字） |
| `coaching_message` | 励ましと来週に向けた具体的なアドバイス（150〜300文字） |
| `improvement_suggestions` | 全体的な改善提案のサマリー（100〜200文字） |
| `actions_json` | 習慣3件・タスク3件の提案配列（JSONB）<br>`ai_proposed_habit` / `ai_proposed_task` モデルは存在しないため全てここに格納 |
| `input_snapshot` | 分析実行時の振り返りデータ + PMVV のスナップショット（JSONB） |
| `ai_model_name` | 実際に使用した AI モデル名（`gemini-2.5-flash` または `openai/gpt-oss-120b`） |
| `prompt_version` | プロンプトのバージョン（`v1.0`） |
| `crisis_detected` | 危機ワード検出フラグ |

<br>

#### ai_analysis_count のインクリメント設計

<br>

```ruby
# ❌ Ruby 側で計算 → 同時実行で競合が発生する
user_setting.increment!(:ai_analysis_count)

# ✅ DB 側で計算 → 原子的操作で競合しない
UserSetting.where(id: user_setting.id)
           .update_all("ai_analysis_count = ai_analysis_count + 1")
```

<br>

#### 月次上限チェックの二重防御

<br>

| チェック箇所 | タイミング | 効果 |
|:---|:---|:---|
| `WeeklyReflectionCompleteService#enqueue_analysis_job_if_eligible` | エンキュー前 | 不要なジョブを DB に積まない最適化 |
| `WeeklyReflectionAnalysisJob#perform` | ジョブ実行時 | タイムラグや二重エンキューによる超過を防ぐ |

<br>

#### トランザクション外でエンキューする理由

<br>

A-7 の設計原則「トランザクション内は DB アクセスのみ。外部 API・GoodJob エンキューは外に出す」に従う。<br>
トランザクション内でエンキューすると、ジョブが実行されたときに DB のコミットが完了していない可能性がある。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/jobs/weekly_reflection_analysis_job.rb` | 新規作成（Chain-of-Thought・PMVV 有無による動的プロンプト・JSON パース強化・月次上限チェック） |
| `app/services/weekly_reflection_complete_service.rb` | `enqueue_analysis_job_if_eligible` メソッドを追加（トランザクション外でエンキュー） |
| `app/models/user.rb` | `after_create :create_user_setting` を追加・`create_user_setting` private メソッドを追加 |
| `config/locales/ja.yml` | `user_setting.ai_analysis_monthly_limit.greater_than_or_equal_to` を追加 |
| `test/jobs/weekly_reflection_analysis_job_test.rb` | 新規作成（8件：正常系・nil返却・PMVV有無・上限チェック・discard_on） |
| `test/services/weekly_reflection_complete_service_test.rb` | エンキュー確認テスト 2件追加（`include ActiveJob::TestHelper` 追加） |
| `test/jobs/task_alarm_job_test.rb` | setup の `UserSetting.create!` を `user.user_setting.update!` に変更（after_create 対応） |
| `test/mailers/task_mailer_test.rb` | setup の `UserSetting.create!` を削除（after_create で自動作成済み） |

<br>

#### テスト結果

<br>

```
D-4テスト: 10件（ジョブ8件・サービス2件）
全テスト: 494 runs, 1272 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-5: 危機介入機能（Railsキーワード検出 + プロンプトルール）

<br>

**ブランチ:** `feature/D-5-crisis-intervention`<br>
**完了日:** 2026-05-03<br>
**概要:** 振り返り入力・PMVV入力で危機ワード（「死にたい」「消えたい」等）を検出した場合、<br>
AI分析をスキップして危機介入モーダルを表示。`crisis_detected=true` を `ai_analyses` テーブルに記録する。<br>
⚠️ 法規・安全対応として最優先で実装した機能。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Module | `CrisisDetector` モジュールを新規作成（`app/models/concerns/`）<br>`CRISIS_KEYWORDS` 定数（30件のバリエーション）・`CRISIS_PATTERN` 正規表現・`before_validation :check_crisis_keywords`・`crisis_word_detected?` 述語メソッド |
| Model | `WeeklyReflection` に `CrisisDetector` をインクルード。`crisis_text_fields` で全4フィールドを対象に指定 |
| Model | `UserPurpose` に `CrisisDetector` をインクルード。`crisis_text_fields` で全5フィールドを対象に指定 |
| Service | `WeeklyReflectionCompleteService` を更新<br>crisis 検出時は `WeeklyReflectionAnalysisJob` をスキップ<br>`crisis_detected=true` の `AiAnalysis` を記録<br>戻り値に `crisis_detected: Boolean` キーを追加 |
| Controller | `WeeklyReflectionsController#create` を更新<br>crisis 検出時に `flash[:crisis] = true` をセット<br>`weekly_reflections_path`（一覧）または `dashboard_path`（ロック解除時）にリダイレクト |
| Controller | `UserPurposesController#create` / `#update` を更新<br>crisis 検出時に `PurposeAnalysisJob` をスキップ<br>`analysis_state` を `failed` に更新（「AI分析待機中...」バナーが永久に残るのを防ぐ）<br>`flash[:crisis] = true` をセットして `user_purpose_path` にリダイレクト |
| JS | `crisis_intervention_controller.js` を新規作成（Stimulusコントローラー）<br>デスクトップ（768px以上）: 画面中央オーバーレイモーダル<br>スマホ（768px未満）: ボトムシート（`translateY` アニメーション）<br>「入力を続ける」ボタンのみで閉じる設計（Escape・オーバーレイクリックでは閉じない） |
| View | `shared/_crisis_intervention_modal.html.erb` を新規作成（Stimulusコントローラーのルート要素）<br>`data-crisis-intervention-show-value` で `flash[:crisis]` を受け取り自動表示を制御 |
| View | `shared/_crisis_modal_content.html.erb` を新規作成（デスクトップ・スマホ共通コンテンツ）<br>🌸アイコン・よりそいホットライン（0120-279-338・24時間）・いのちの電話（0120-783-556）を表示<br>`clamp()` でレスポンシブなフォントサイズ自動調整を実装 |
| View | `weekly_reflections/index.html.erb` にモーダルを追加（振り返り一覧・crisis のリダイレクト先） |
| View | `weekly_reflections/new.html.erb` にモーダルを追加（13-M） |
| View | `user_purposes/new.html.erb` / `edit.html.erb` / `show.html.erb` にモーダルを追加（17-M） |
| View | `dashboards/index.html.erb` にモーダルを追加（ロック解除 + crisis 時のリダイレクト先） |
| Layout | `application.html.erb` の `flash.each` に `next if message_type.to_s == "crisis"` を追加<br>`flash[:crisis]` の `true` が「true」としてトースト表示されるバグを修正 |
| Prompt | `WeeklyReflectionAnalysisJob` / `PurposeAnalysisJob` の `build_prompt` に危機検出ルールを明記<br>通常の落ち込み表現（「つらい」「疲れた」等）と危機ワードの区別基準をAIに指示 |
| Test | `test/models/concerns/crisis_detector_test.rb` を新規作成（11件）<br>`test/services/weekly_reflection_complete_service_crisis_test.rb` を新規作成（5件）<br>`test/models/habit_record_memo_test.rb` の `record_date` 日付衝突バグを修正（2026-05 → 2025-01） |

<br>

#### 相談窓口情報（モーダル表示内容）

<br>

| 窓口 | 電話番号 | 対応時間 | 費用 |
|:---|:---|:---|:---|
| よりそいホットライン | 0120-279-338 | 24時間・365日 | 無料 |
| いのちの電話 | 0120-783-556 | 毎日16〜21時（毎月10日24時間） | 無料 |

<br>

出典: [よりそいホットライン](https://www.yorisoi-hotline.jp/) / [いのちの電話](https://www.inochi.or.jp/)

<br>

#### crisis 検出フローの設計

<br>

```
ユーザーが振り返り/PMVV を送信
  ↓
WeeklyReflection / UserPurpose の before_validation が実行
  ↓
CrisisDetector#check_crisis_keywords が全フィールドを CRISIS_PATTERN でスキャン
  ↓
        危機ワードあり？
        ↙             ↘
      Yes               No
       ↓                 ↓
crisis_word_detected    通常処理
= true                  AI ジョブをエンキュー
       ↓
AI ジョブをスキップ
crisis_detected=true の
AiAnalysis を記録
       ↓
flash[:crisis] = true
適切なページにリダイレクト
       ↓
Stimulus connect() が
show-value="true" を検出
       ↓
🌸 危機介入モーダルを表示
       ↓
「入力を続ける」でモーダルを閉じる
```

<br>

#### 設計上の重要判断

<br>

| 判断 | 理由 |
|:---|:---|
| 振り返り・PMVV の保存自体は続行する | ユーザーを詰まらせない。「記録はされた」という安心感を提供する |
| ロック解除も通常通り実行する | crisis 検出は保存の「失敗」ではなく「特別な状態」のため |
| AI 分析ジョブのみスキップする | AI が危機的な感情を「改善ポイント」として分析することへの配慮 |
| `crisis_detected=true` を DB に記録する | 運営者がサポートが必要なユーザーを把握できる設計。将来のフォローアップ通知にも活用可能 |
| オーバーレイクリック・Escape では閉じない | ユーザーに必ず一度情報を目にしてもらうための設計 |
| `analysis_state` を `failed` に更新する | pending のままだと「AI分析待機中...」バナーが永久に表示され続けるため |

<br>

#### テスト結果

<br>

```
D-5テスト: 16件（CrisisDetectorテスト11件・WeeklyReflectionCompleteService危機介入テスト5件）
全テスト:  510 runs, 1294 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-6: AIコスト上限管理（ai_analysis_monthly_limit）

<br>

**ブランチ:** `feature/D-6-ai-cost-limit`<br>
**完了日:** 2026-05-03<br>
**概要:** `user_settings.ai_analysis_count` が `ai_analysis_monthly_limit`（デフォルト: 10回）に達したとき、<br>
AI分析をスキップして14-B（AIコスト上限エラーモーダル）を表示。<br>
「AIなしで振り返りを完了する」でロック解除のみ実行できる。<br>
毎月1日に `MonthlyAiCountResetJob` が使用回数をリセットする（GoodJob cron は #A-3 で実装済み）。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Controller | `ApplicationController` に `ai_limit_exceeded?` を追加（`helper_method` 登録でビューでも使用可） |
| Controller | `WeeklyReflectionsController#create` に上限チェックを追加<br>超過時は `flash.now[:ai_limit] = true` + `render :new` で**入力内容を保持したまま**モーダルを表示 |
| Controller | `WeeklyReflectionsController#complete_without_ai` を新規追加<br>`POST /weekly_reflections/complete_without_ai` で振り返り保存・ロック解除・AI分析スキップを実行 |
| Controller | `complete_without_ai_params` を追加<br>モーダル専用フォームのフラットなパラメータ形式と通常の `weekly_reflection[]` 形式の両方に対応 |
| Controller | `setup_new_form_variables` を抽出（`create` / `complete_without_ai` 両方で使う DRY 化） |
| Route | `resources :weekly_reflections` に `collection do post :complete_without_ai end` を追加 |
| JS | `ai_limit_modal_controller.js` を新規作成（Stimulus コントローラー）<br>デスクトップ（768px以上）: 画面中央オーバーレイモーダル<br>スマホ（768px未満）: 画面下部ボトムシート<br>`submitWithoutAi()` でメインフォームの入力値を専用フォームの hidden フィールドにコピーして送信 |
| View | `_ai_limit_modal.html.erb` を新規作成（14-B モーダルラッパー）<br>`data-ai-limit-modal-show-value` で `flash.now[:ai_limit]` を受け取り自動表示 |
| View | `_ai_limit_modal_content.html.erb` を新規作成（デスクトップ・スマホ共通コンテンツ）<br>使用状況カード（N/10回 + 赤プログレスバー）・「AIなしで完了」専用フォーム・「入力を続ける」ボタン |
| View | `new.html.erb` / `index.html.erb` / `dashboards/index.html.erb` にモーダルパーシャルを追加 |
| i18n | `config/locales/ja.yml` に D-6 関連メッセージを追加 |
| Test | `test/controllers/weekly_reflections_ai_limit_test.rb` を新規作成（9テスト） |

<br>

#### 設計上の最重要ポイント: `render :new` vs `redirect_to`

<br>

| 方式 | 動作 | 採用理由 |
|:---|:---|:---:|
| `redirect_to new_weekly_reflection_path` | ユーザーが入力した「なぜ？」「どう？」等のテキストが全て消える | ❌ 不採用 |
| `render :new, status: :unprocessable_entity` | `@weekly_reflection` のインスタンス変数が保持されてフォームの入力内容が残る | ✅ 採用 |

<br>

`render :new` + `flash.now[:ai_limit] = true` の組み合わせにより、<br>
「入力内容はそのまま残った状態でモーダルだけが浮かび上がる」UXを実現した。

<br>

#### モーダルの「AIなしで完了」送信方式

<br>

`render :new` で再描画されたフォームは action 属性がページの URL（相対パス）になるため、<br>
JavaScript でフォームの action を書き換える方式は不安定になることが判明した。<br>
モーダル内に `complete_without_ai` 専用の独立したフォームを配置し、<br>
Stimulus の `submitWithoutAi()` でメインフォームの入力値を hidden フィールドにコピーして送信する設計を採用した。

<br>

ユーザーが振り返りを入力して「振り返りを完了する」を押す
↓
create アクションで ai_limit_exceeded? が true
↓
assign_attributes は実行済みのため入力値が @weekly_reflection に保持されている
↓
flash.now[:ai_limit] = true + render :new（フォームの入力内容が残る）
↓
Stimulus connect() が show-value="true" を検出 → 14-B モーダルを自動表示
↓
「AIなしで振り返りを完了する」を押す
↓
submitWithoutAi() がメインフォームの各フィールドの値を専用フォームの hidden フィールドにコピー
↓
POST /weekly_reflections/complete_without_ai に送信
↓
complete_without_ai アクション: 振り返り保存 + ロック解除 + AI分析スキップ

<br>

#### complete_without_ai_params の設計

<br>

| 状況 | パラメータ形式 | 対応 |
|:---|:---|:---|
| 通常フォームから送信（将来拡張用） | `weekly_reflection[field]` 形式 | `weekly_reflection_params` を使用 |
| モーダルの hidden フォームから送信 | フラット形式（`field` のみ） | `params.permit(:reflection_comment, ...)` を使用 |

<br>

#### テスト設計の知見

<br>

`travel_to` は `ActionDispatch::IntegrationTest` のHTTPリクエスト内スレッドに引き継がれないため、<br>
`locked?` の時刻依存テストはリクエスト結果（リダイレクト先）ではなく<br>
DB状態（振り返りの保存確認・flash の有無）で検証する設計に変更した。

<br>

#### テスト結果

<br>

```
D-6テスト: 9 runs, 32 assertions, 0 failures, 0 errors, 0 skips
全テスト:  519 runs, 1326 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-7: オンボーディング 5/5 PMVV入力ステップ

<br>

**ブランチ:** `feature/D-7-onboarding-pmvv-step`<br>
**完了日:** 2026-05-04<br>
**概要:** 初回ログインユーザーのオンボーディング最終ステップ（5/5）として PMVV 入力画面を追加。<br>
スキップ可能。完了後に AI 分析ジョブを非同期投入し、ダッシュボードで Turbo Stream により分析完了をリアルタイム通知する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Controller | `OnboardingsController` を新規作成（step5 / complete / skip アクション） |
| Controller | `ApplicationController#require_login` に `redirect_to_onboarding_if_needed` を追加（初回ユーザーを自動誘導） |
| Controller | `DashboardsController` に `@current_purpose` / `@ai_analysis` を追加 |
| Route | `scope "/onboarding"` に `step5`（GET）/ `complete`（POST）/ `skip`（POST）を追加 |
| View | `app/views/onboardings/step5.html.erb` を新規作成（ステップインジケーター・PMVVフォーム・スキップボタン） |
| View | `app/views/dashboards/index.html.erb` に `turbo_stream_from` とバナーを追加 |
| i18n | `config/locales/ja.yml` にオンボーディング関連メッセージを追加 |
| Test | `test/controllers/onboardings_controller_test.rb` を新規作成（7件） |

<br>

#### 設計上の重要ポイント

<br>

**① スキップボタンをフォームの外に配置する理由**

<br>

`button_to` は独自の `<form method="post">` を生成する。<br>
HTML の仕様では `<form>` の中に `<form>` を入れることができない。<br>
メインフォーム（PMVV 入力）の内側に `button_to` を置くと、スキップ時にメインフォームの<br>
バリデーション（`at_least_one_field_present`）が発火し「少なくとも1つ入力してください」エラーが表示された。<br>
`button_to` を `<% end %>` の後（フォームの外）に配置することで完全に独立した POST になり正常動作する。

<br>

**② Turbo Stream チャンネル名は `user_purpose.id` を使う**

<br>

`PurposeAnalysisJob` の `broadcast_replace_to` は `"user_purpose_#{user_purpose.id}"` チャンネルに送信する。<br>
ビュー側も `turbo_stream_from "user_purpose_#{@current_purpose.id}"` と合わせることで<br>
分析完了がブラウザにリアルタイム通知される。<br>
`current_user.id`（ユーザーの ID）と `user_purpose.id`（PMVV レコードの ID）は異なるため注意。

<br>

**③ `redirect_to_onboarding_if_needed` の無限ループ防止**

<br>

```ruby
# onboardings / sessions / users / errors / pages コントローラーでは実行しない
return if controller_name.in?(%w[onboardings sessions users errors pages])
return unless current_user&.first_login_at.nil?
redirect_to onboarding_step5_path, notice: t("onboarding.welcome")
```

<br>

#### テスト結果

<br>

```
D-7テスト: 7 runs, 0 failures, 0 errors, 0 skips
全テスト:  528 runs, 1353 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-8: AI提案の習慣編集ページ（8番・AI経由限定）

<br>

**ブランチ:** `feature/D-8-habit-ai-edit`<br>
**完了日:** 2026-05-04<br>
**概要:** AI提案プレビューモーダル（#14番）からのみアクセス可能な習慣専用編集ページを実装。<br>
C-7（tasks#ai_edit）と同じ session フラグ方式を採用しコードパターンを統一。<br>
measurement_type（記録タイプ）はUI・サーバーの両層で変更不可にして過去データの整合性を保護する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Route | `get :ai_edit` / `patch :ai_update` を `resources :habits` の member ブロックに追加 |
| Controller | `ai_edit` アクション: session に `ai_context_habit_id` フラグを設定 |
| Controller | `ai_update` アクション: フラグ検証 → A-7原則に従いトランザクション内で update! + save_excluded_days! → session クリア → habits_path へリダイレクト |
| Controller | `require_unlocked` に `:ai_update` を追加（PDCAロック中は更新不可・ai_edit の表示は可） |
| Controller | `set_ai_context` / `verify_ai_context` / `clear_ai_context` を private に追加 |
| Controller | `ai_update_params`: name・weekly_target のみ許可（measurement_type・color・icon を除外） |
| View | `app/views/habits/ai_edit.html.erb` 新規作成（AI経由限定バナー・記録タイプ読み取り専用・除外日のバリデーションエラー後保持） |
| View | `form_with data: { turbo: false }` で Turbo を無効化し通常フォーム送信 |
| i18n | `config/locales/ja.yml` に `habits.ai_edit.unauthorized` / `habits.ai_update.success` を追加 |
| Test | `test/controllers/habits_ai_edit_controller_test.rb` 新規作成（10件） |

<br>

#### アクセス制御の設計

<br>

```
ai_edit（GET）
  ↓ session[:ai_context_habit_id] = @habit.id を設定
  ↓ ai_edit.html.erb を表示（AI経由限定バナー・記録タイプは読み取り専用）
ai_update（PATCH）
  ↓ session[:ai_context_habit_id] == @habit.id か検証
  一致しない → habits_path へリダイレクト（「AI提案モーダル経由でのみ実行できます」）
  一致する   → ai_update_params で保存 → session クリア → habits_path へ
```

<br>

#### measurement_type を変更不可にする二重防御

<br>

| 防御層 | 実装 |
|:---|:---|
| UI 層 | `ai_edit.html.erb` で measurement_type フィールドをテキスト表示のみにする（ラジオボタンなし） |
| サーバー層 | `ai_update_params` に `:measurement_type` を含めない |

<br>

#### なぜ measurement_type を変更不可にするのか

<br>

チェック型(0) ⇄ 数値型(1) を変更すると `habit_records.completed` と<br>
`habit_records.numeric_value` の過去データが無意味になり、<br>
ストリーク計算・達成率計算が壊れる。<br>
AI提案でも過去データの整合性を壊す変更は許可しない。

<br>

#### C-7（tasks#ai_edit）との対称性

<br>

| 項目 | tasks | habits |
|:---|:---|:---|
| session キー | `ai_context_task_id` | `ai_context_habit_id` |
| 変更不可フィールド | `priority` | `measurement_type` |
| 保存メソッド | `update(ai_update_params)` | `update!(ai_update_params)` + `save_excluded_days!` |
| トランザクション | なし（アラームジョブ再スケジュールあり） | あり（A-7原則に従う） |

<br>

セッションキーを `ai_context_habit_id` / `ai_context_task_id` と別名にすることで<br>
両方の ai_edit が同時に開かれた場合でも互いに干渉しない設計になっている。

<br>

#### テスト設計のポイント

<br>

他ユーザーの習慣へのアクセス確認では `assert_response :not_found` ではなく<br>
`assert_redirected_to habits_path` が正しい期待値になる。<br>
`set_habit` が `RecordNotFound` を rescue して `redirect_to habits_path` を返す設計のため、<br>
`rescue_from` による404ではなく302リダイレクトが実際の動作になる。

<br>

#### テスト結果

<br>

```
D-8テスト: 10 runs, 38 assertions, 0 failures, 0 errors, 0 skips
全テスト:  538 runs, 1391 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-9: AiAnalysis input_snapshot JSONBスキーマバリデーション

<br>

**ブランチ:** `feature/D-9-ai-analysis-input-snapshot-validation`<br>
**完了日:** 2026-05-05<br>
**概要:** `ai_analyses.input_snapshot`（jsonb）は自由形式のため、5つの必須キーが欠落すると<br>
18番画面（PMVV詳細）のUIが崩壊する。DB保存前にスキーマを強制バリデーションする。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `AiAnalysis` に `validate :input_snapshot_schema_valid` を追加 |
| Model | `input_snapshot_schema_valid` プライベートメソッドを追加<br>- `purpose_breakdown` 分析のみ対象（`weekly_reflection` はスキップ）<br>- 必須5キー: `purpose` / `mission` / `vision` / `value` / `current_situation`<br>- キーの存在のみチェック（値の nil は許容 / `allow_blank: true` 設計に準拠）<br>- `with_indifferent_access` でシンボルキー・文字列キー両方に対応<br>- `input_snapshot` が nil の場合はスキップ（ジョブ側の事前チェックで保護） |
| Job | `PurposeAnalysisJob` の Step 4（JSON パース後）に `input_snapshot` 事前バリデーションを追加<br>- `AiAnalysis.new` で仮インスタンスを作成し `valid?` でバリデーション実行<br>- 失敗時は `handle_failure` を呼び `failed` 状態に遷移・エラー詳細を DB に記録 |
| i18n | `config/locales/ja.yml` に `input_snapshot` フィールドの日本語名（`"PMVV分析データ"`）を追加 |
| Test | モデルテストに D-9 関連テスト 11 ケースを追加（正常系 5・異常系 7）<br>- `weekly_reflection` は `create!` で作成（フィクスチャ依存を排除）<br>- `private` ヘルパーをファイル末尾に配置（`test` ブロックの非公開化を防止）<br>- nil 値はキーが存在すれば通過するテストに変更（`allow_blank` 設計に準拠） |

<br>

#### バリデーション設計の詳細

<br>

| 設計判断 | 理由 |
|:---|:---|
| `json-schema` gem（外部ライブラリ）を使わない | Gemfile 変更不要・Docker 再ビルド不要・今回の要件（5キーの存在チェック）には十分な堅牢性 |
| キーの「存在」のみチェック、値の nil は許容 | `UserPurpose` の各フィールドは `allow_blank: true` のため未入力時に nil が保存される。18番画面は `.presence \|\| "未入力"` で nil を安全に処理できる |
| `with_indifferent_access` を使う | `build_input_snapshot` はシンボルキー（`:purpose` 等）で Hash を作るが、DB 読み出し時は文字列キー（`"purpose"`）になる。両形式に対応することで型の違いを吸収する |
| `input_snapshot` が nil のときはスキップ | 実運用では `build_input_snapshot` が必ず Hash を返すため nil にならない。テストの利便性（`input_snapshot` を省略したモデルテストが書きやすい）のためスキップ設計にし、ジョブ側の事前チェックで保護する |
| ジョブ側に事前バリデーションを追加する理由 | `create!` 時にバリデーションエラーが発生すると `ActiveRecord::RecordInvalid` が `raise` され、`rescue => e` でキャッチしてジョブ全体を `raise` し直すと `user_purpose` の状態が `analyzing` のまま stuck するリスクがある。事前チェックで確実に `handle_failure` を呼び画面を正しく「失敗」状態に遷移させる |

<br>

#### テスト結果

<br>

```
D-9テスト: 16 runs, 45 assertions, 0 failures, 0 errors, 0 skips
全テスト:  549 runs, 1423 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #D-10: AI API レート制限（連打防止）

<br>

**ブランチ:** `feature/d-10-ai-rate-limit`<br>
**完了日:** 2026-05-05<br>
**概要:** 振り返り完了ボタンや「再試行する」を連打された場合に、同一ユーザーから短時間に<br>
複数のAI分析ジョブが投入されるのを防ぐ。月次上限管理（#D-6）とは別の「同一分内の重複リクエスト」防止。<br>
あわせて `render_error_page` の `format.any` 対応で `favicon.ico` の `UnknownFormat` エラーを解消。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Migration | `user_settings` に `last_ai_requested_at datetime` カラムを追加<br>null: true（初回リクエストなしを許容）・インデックス不要（user_id 経由で取得するため） |
| Model | `UserSetting` に `ai_recently_requested?` を追加（1分以内かどうかを判定）<br>`UserSetting` に `touch_ai_requested_at!` を追加（`update_columns` で単一カラムのみ更新） |
| Controller | `ApplicationController` に `throttle_ai_request` before_action を追加<br>判定①: `last_ai_requested_at` が1分以内 → `flash[:notice]` + `redirect_back`<br>判定②: `analysis_state: [:pending, :analyzing]` のジョブが存在する → `flash[:notice]` + `redirect_back`<br>全通過時: `touch_ai_requested_at!` で現在時刻を記録 |
| Controller | `WeeklyReflectionsController` に `before_action :throttle_ai_request, only: [:create]` を追加<br>（`complete_without_ai` は AI を使わないため除外） |
| Controller | `UserPurposesController` に `before_action :throttle_ai_request, only: [:create, :update, :retry_analysis]` を追加 |
| Controller | `ApplicationController#render_error_page` に `format.any { head status }` を追加<br>（`favicon.ico` など未知フォーマットへのリクエストで `ActionController::UnknownFormat` が発生していた問題を解消） |
| JS | `ai_throttle_controller.js` を新規作成（Stimulusコントローラー）<br>ボタン押下後 1 分間 `disabled` にして「受け付けました...」と表示<br>`connect()` でタイマーID を初期化・`disconnect()` でタイマーをクリア（メモリリーク防止） |
| JS | `index.js` に `ai-throttle` コントローラーを登録 |
| View | `weekly_reflections/new.html.erb` のフォームに `ai-throttle` コントローラーを追加<br>`data-controller: "form-submit ai-throttle"` / `action` に両コントローラーの submit イベントを並列登録<br>送信ボタンに `data-ai-throttle-target="button"` を追加 |
| View | `user_purposes/_analysis_status_banner.html.erb` の「再試行する」ボタンに<br>`form: { data: { controller: "ai-throttle", action: "submit->ai-throttle#throttle" } }` を追加 |
| i18n | `config/locales/ja.yml` に `ai_throttle.too_soon` / `ai_throttle.already_processing` を追加 |
| Test | `test/controllers/weekly_reflections_controller_test.rb` のテスト5に<br>`user.user_setting.update_columns(last_ai_requested_at: 2.minutes.ago)` を追加（throttle バイパス対応） |

<br>

#### 2段階の重複判定設計

<br>

| 判定 | チェック内容 | 実装 |
|:---|:---|:---|
| 判定① | 1分以内のリクエスト | `user_setting.last_ai_requested_at > Time.current - 1.minute` |
| 判定② | pending/analyzing ジョブの存在 | `user_purposes.where(analysis_state: [:pending, :analyzing]).exists?` |

<br>

#### サーバーサイドとフロントエンドの二重防御

<br>

| 防御層 | 実装 | 効果 |
|:---|:---|:---|
| サーバー層 | `ApplicationController#throttle_ai_request`（DB 管理・Redis 不使用） | HTTP 直接送信でも制限される |
| フロント層 | `AiThrottleController`（Stimulus）でボタンを 1 分間 disabled | ユーザーの連打を物理的に防ぐ |

<br>

#### format.any 追加による favicon.ico エラー解消

<br>

`catch-all` ルートが `favicon.ico`（`ico` フォーマット）のリクエストを受けると<br>
`respond_to` ブロックに `ico` の処理がないため `ActionController::UnknownFormat` が発生していた。<br>
`format.any { head status }` を追加することで `html` / `json` / `turbo_stream` 以外の<br>
全フォーマット（`ico` / `xml` / `png` 等）に対してボディなしのステータスコードのみを返すようになった。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `db/migrate/YYYYMMDDHHMMSS_add_last_ai_requested_at_to_user_settings.rb` | 新規作成 |
| `app/models/user_setting.rb` | `ai_recently_requested?` / `touch_ai_requested_at!` を追加 |
| `app/controllers/application_controller.rb` | `throttle_ai_request` を追加・`render_error_page` に `format.any` を追加 |
| `app/controllers/weekly_reflections_controller.rb` | `before_action :throttle_ai_request, only: [:create]` を追加 |
| `app/controllers/user_purposes_controller.rb` | `before_action :throttle_ai_request, only: [:create, :update, :retry_analysis]` を追加 |
| `app/javascript/controllers/ai_throttle_controller.js` | 新規作成 |
| `app/javascript/controllers/index.js` | `ai-throttle` コントローラーを登録 |
| `app/views/weekly_reflections/new.html.erb` | フォームと送信ボタンに `ai-throttle` を適用 |
| `app/views/user_purposes/_analysis_status_banner.html.erb` | 「再試行する」ボタンに `ai-throttle` を適用 |
| `config/locales/ja.yml` | `ai_throttle` 関連メッセージを追加 |
| `test/controllers/weekly_reflections_controller_test.rb` | テスト5に throttle バイパス処理を追加 |

<br>

#### テスト結果

<br>

```
D-10テスト: 既存 549 runs すべてパス（0 failures, 0 errors, 0 skips）
```

<br>

### #D-11: AI APIエラーハンドリングUX改善（タイムアウト・失敗時）

<br>

**ブランチ:** `feature/d-11-ai-error-handling-ux`<br>
**完了日:** 2026-05-06<br>
**概要:** Gemini APIのタイムアウト・無料枠超過（429）など、AI機能を「失敗前提」で設計。<br>
①事前フォールバック判定・②429指数バックオフリトライ・③Groqへの自動切替という<br>
「落ちない設計」を完成させ、失敗時のUXを大幅に改善する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Service | `AiClient` にカスタムエラークラス `AuthError` / `RateLimitError` を追加 |
| Service | `handle_http_error` メソッドで Gemini / Groq 共通の HTTP エラー処理を共通化（DRY化） |
| Service | タイムアウト（`Faraday::TimeoutError` / `Timeout::Error`）を明示的に rescue して Sentry に Capture |
| Service | 401エラー（`AuthError`）を即座に rescue して Sentry に fatal 通知 |
| Service | 全プロバイダ失敗（Gemini・Groq 両方失敗）を最終 rescue で Sentry に error 通知（#I-4 追加・モデル廃止404等の早期検知） |
| Service | `notify_sentry` ヘルパーで Sentry gem がない環境でもログのみ出力（I-5導入後に自動有効化） |
| Service | `analyze` メソッドは「常に nil か Hash を返す」設計を維持（Job側との契約） |
| Job | `PurposeAnalysisJob`: 全プロバイダ失敗時に `wait: 60.seconds` で最大3回再エンキュー |
| Job | `PurposeAnalysisJob`: 再エンキュー中は `pending` 状態に戻して「自動再試行中」を表示 |
| Job | `PurposeAnalysisJob`: 最大再試行回数（`MAX_REENQUEUE_COUNT = 3`）超過後に `failed` 確定 |
| Job | `PurposeAnalysisJob`: JSONパース失敗時に `raw_response` を `metadata(jsonb)` に保存 |
| Job | `PurposeAnalysisJob`: `discard_on AiClient::AuthError` で認証エラー時に即座に破棄 |
| Job | `WeeklyReflectionAnalysisJob`: 同様の再エンキュー・`metadata` 保存を実装 |
| View | 16番ページ failed バナー: `last_error_message` をエラー種別ごとに日本語変換して表示 |
| View | 16番ページ failed バナー: タイムアウト時に「➡️ AIなしで続行する」ボタンを表示（`show_without_ai` フラグで制御） |
| View | 16番ページ failed バナー: 「💡 AI分析がなくても習慣・タスクの記録は通常通りご利用いただけます。」を常時表示 |
| i18n | `config/locales/ja.yml` に `ai_error` 名前空間のメッセージを追加 |
| Test | `PurposeAnalysisJobTest` に D-11 関連テスト4件を追加（再エンキュー・最大回数超過・metadata保存・AuthError）|

<br>

#### AiClient のエラー設計

<br>

| エラー種別 | HTTPステータス | 対応 | Sentry通知 |
|:---|:---:|:---|:---:|
| `AuthError`（認証エラー） | 401 | 即座に failed 確定・Job破棄（`discard_on`） | ✅ level: fatal |
| `RateLimitError`（レート制限） | 429 | 指数バックオフリトライ（1秒→2秒・最大2回）→ Groq へ切替 | なし |
| `Faraday::TimeoutError`（タイムアウト） | — | nil を返す → Job が再エンキュー | ✅ level: warning |
| その他のエラー | 500系 | Groq へフォールバック | なし |

<br>

#### 全プロバイダ失敗時の再エンキュー設計

<br>

1回目失敗 → pending に戻す → 60秒後に再エンキュー（reenqueue_count: 1）
2回目失敗 → pending に戻す → 60秒後に再エンキュー（reenqueue_count: 2）
3回目失敗 → pending に戻す → 60秒後に再エンキュー（reenqueue_count: 3）
4回目失敗（reenqueue_count >= MAX_REENQUEUE_COUNT）→ failed 確定

<br>

GoodJob の `retry_on` では固定秒数の `wait` が指定できないため、<br>
`perform_later(wait: 60.seconds)` を明示的に呼ぶ設計を採用。

<br>

#### failed 状態UIのエラー種別判定

<br>

| 判定条件（`last_error_message` に含まれる文字列） | アイコン | タイトル | AIなしで続行ボタン |
|:---|:---:|:---|:---:|
| `"タイムアウト"` / `"timeout"` | ⏱️ | 分析がタイムアウトしました | ✅ 表示 |
| `"429"` / `"レート制限"` / `"上限"` | 🚦 | AIの利用制限に達しました | なし |
| `"401"` / `"認証"` / `"接続できません"` | 🔑 | AIサービスに接続できません | なし |
| `"解析"` / `"パース"` / `"JSON"` | 📄 | AI応答の解析に失敗しました | なし |
| `"再試行"` / `"自動的に"` | 🔄 | 一時的なエラーが発生しました | なし |
| その他 | ⚠️ | 分析に失敗しました | なし |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/services/ai_client.rb` | `AuthError` / `RateLimitError` 追加・`handle_http_error` 共通化・`notify_sentry` 追加 |
| `app/jobs/purpose_analysis_job.rb` | 再エンキューロジック・`metadata` 保存・`discard_on AiClient::AuthError` 追加 |
| `app/jobs/weekly_reflection_analysis_job.rb` | 再エンキューロジック・`metadata` 保存・`discard_on AiClient::AuthError` 追加 |
| `app/views/user_purposes/_analysis_status_banner.html.erb` | failed バナー大幅改善（エラー種別判定・AIなしで続行ボタン・補足テキスト） |
| `config/locales/ja.yml` | `ai_error` 名前空間（timeout/auth/all_providers_failed/parse_failed/retrying）を追加 |
| `test/jobs/purpose_analysis_job_test.rb` | D-11 関連テスト4件追加（552 runs, 0 failures に更新） |

<br>

#### テスト結果

<br>

```
D-11テスト: 4件（再エンキュー・最大回数超過・metadata保存・AuthError）追加
全テスト:  552 runs, 1433 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #E-1: 振り返りポイント必須化・PMVV必須化・気分スコア・音声入力拡張

<br>

**ブランチ:** `feature/e-1-weekly-reflection-mood-enhancements`<br>
**完了日:** 2026-05-11<br>
**概要:** 週次振り返りのリフレクション3フィールドを必須化し、気分スコア（★1〜5）入力UIを追加。<br>
PMVV目標管理の5フィールドも必須化し、入力フォームに必須バッジ・インラインエラー表示を追加した。<br>
音声入力（🎤ボタン）を振り返り・PMVV双方の全フィールドに対応させた。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Model | `WeeklyReflection`: `direct_reason` / `background_situation` / `next_action` を presence: true（必須化）<br>`reflection_comment`（自由コメント）は任意に変更 |
| Model | `WeeklyReflection`: `mood` カラムに numericality バリデーション（1〜5の整数・任意）を追加 |
| Model | `UserPurpose`: `purpose` / `mission` / `vision` / `value` / `current_situation` を presence: true（必須化） |
| Model | `UserPurpose`: `include CrisisDetector` を維持（`crisis_word_detected?` は OnboardingsController で使用） |
| View | `weekly_reflections/new.html.erb`: 気分スコアUI（★選択・ラベル表示）を追加<br>3フィールドに「必須」バッジ（赤）・インラインエラー表示を追加<br>自由コメントを「任意」バッジ（グレー）に変更 |
| View | `weekly_reflections/show.html.erb`: 気分スコアを★表示で追加 |
| View | `user_purposes/_voice_field.html.erb`: 全フィールドに「必須」バッジ・エラー時赤枠・インラインエラー表示を追加<br>`new.html.erb` / `edit.html.erb` / `step5.html.erb` の3ページに自動反映 |
| View | `onboardings/step5.html.erb`: 情報バナーの「すべて任意入力です」を削除（スキップ案内のみに変更） |
| JS | `mood_rating_controller.js` を新規作成（★クリックで色変更・ラベル更新・Stimulusコントローラー） |
| JS | `index.js` に `mood-rating` コントローラーを登録 |
| Controller | `weekly_reflections_controller.rb`: Strong Parameters に `mood` / `direct_reason` / `background_situation` / `next_action` を追加 |
| Test | 全14ファイルの `WeeklyReflection.create!` / フォーム送信パラメータに3フィールドを追加<br>`UserPurpose.create!` に5フィールド（`mission` / `value` / `current_situation`）を追加<br>`travel_to { assert }` ブロック内アサーションを `travel_to / travel_back` 展開形式に修正 |

<br>

#### 気分スコアUIの設計

<br>

| 設計 | 内容 |
|:---|:---|
| Stimulusコントローラー | `mood_rating_controller.js` で ★クリックをハンドリング。ラジオボタンを hidden input として送信 |
| ラベル定義 | `{ 1 => "😞 とても悪い", 2 => "😟 悪い", 3 => "😐 普通", 4 => "😊 良い", 5 => "😄 とても良い" }` |
| 任意設計 | mood は `allow_nil: true`（未選択でも振り返り完了可） |
| 詳細ページ | `show.html.erb` で `"★" * mood` 形式で表示 |

<br>

#### バリデーション設計のポイント

<br>

| 設計 | 内容 |
|:---|:---|
| `numericality: { in: 1..5 }` は使用不可 | Rails 7 で `in:` が `ArgumentError` になるため `greater_than_or_equal_to: 1, less_than_or_equal_to: 5` を使用 |
| `include CrisisDetector` の維持 | `crisis_word_detected?` メソッドが `OnboardingsController#complete` と `CrisisDetectorTest` で使われるため削除禁止 |
| `ja.yml` の `activerecord:` は1箇所のみ | 2箇所あると後が前を上書きして全エラーメッセージが消えるバグになる |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/weekly_reflection.rb` | `direct_reason` / `background_situation` / `next_action` を必須化・`reflection_comment` を任意化・mood バリデーション追加 |
| `app/models/user_purpose.rb` | 5フィールドを必須化・`include CrisisDetector` を維持・`crisis_text_fields` プライベートメソッド追加 |
| `app/controllers/weekly_reflections_controller.rb` | Strong Parameters に4フィールドを追加 |
| `app/views/weekly_reflections/new.html.erb` | 気分スコアUI追加・3フィールドに必須バッジ・インラインエラー追加・自由コメントを任意バッジに変更 |
| `app/views/weekly_reflections/show.html.erb` | 気分スコアを★表示で追加 |
| `app/views/user_purposes/_voice_field.html.erb` | 必須バッジ・エラー時赤枠・インラインエラー追加（3ページに自動反映） |
| `app/views/onboardings/step5.html.erb` | バナー文言修正（任意→スキップ案内のみ） |
| `app/javascript/controllers/mood_rating_controller.js` | 新規作成（★選択UI・ラベル更新） |
| `app/javascript/controllers/index.js` | `mood-rating` コントローラーを登録 |
| `test/fixtures/weekly_reflections.yml` | 全フィクスチャに3フィールドを追加（`complete!` 対応） |
| `test/models/weekly_reflection_test.rb` | `travel_to / travel_back` 展開形式に修正・3フィールドのテスト追加 |
| `test/controllers/onboardings_controller_test.rb` | `valid_purpose_params` ヘルパー追加・5フィールド必須化対応 |
| （他11ファイル） | `WeeklyReflection.create!` / `UserPurpose.create!` / フォーム送信パラメータに必須フィールドを追加 |

<br>

#### テスト結果

<br>

```
全テスト: 571 runs, 1456 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #E-2: 振り返りの習慣スナップショット更新（数値型・単位対応）

<br>

**ブランチ:** `feature/e-2-habit-snapshot-numeric`<br>
**完了日:** 2026-05-13<br>
**概要:** `weekly_reflection_habit_summaries` に数値型習慣の実績値（`actual_value`）と<br>
単位（`unit`）カラムを追加し、スナップショット保存ロジックをチェック型・数値型の両対応に更新。<br>
振り返り詳細ページで数値型の実績を「N 分（XX%）」形式で正しく表示できるようにした。

<br>

#### 追加カラム

<br>

| テーブル | 追加カラム | 型 | 目的 |
|:---|:---|:---|:---|
| `weekly_reflection_habit_summaries` | `actual_value` | decimal(10,2) | 数値型習慣の週次実績値合計（SUM）。チェック型は NULL |
| `weekly_reflection_habit_summaries` | `unit` | string | 数値型習慣の単位スナップショット（例: 分, 冊）。チェック型は NULL |

<br>

#### スナップショット保存ロジックの変更

<br>

| 習慣タイプ | 集計方式 | 保存先 | 表示例 |
|:---|:---|:---|:---|
| チェック型 | `completed: true` の COUNT | `actual_count` | 「5 / 7 日（71%）」 |
| 数値型 | `numeric_value` の SUM | `actual_value` + `unit` | 「90 / 120 分（75%）」 |

<br>

#### 技術的な設計ポイント

<br>

**① `to_d`（BigDecimal）でSUMを集計する理由**

<br>

Rails の `decimal` カラムは `BigDecimal` で管理されている。<br>
`.to_f`（Float）に変換すると浮動小数点の誤差（例: `0.1 + 0.2 ≠ 0.3`）が発生する可能性がある。<br>
`.to_d`（BigDecimal変換）を使うことで精度を保護した。

<br>

**② `unit` をスナップショットとして保存する理由**

<br>

後から習慣の単位（例: 「分」→「時間」）を変更しても、<br>
過去の振り返り詳細ページは振り返り時点の単位で正しく表示される。<br>
習慣名・目標値と同じスナップショット設計を踏襲している。

<br>

**③ `deleted_at: nil` 条件をチェック型にも追加（レビュー反映）**

<br>

変更前はチェック型の `COUNT` クエリに `deleted_at: nil` 条件がなかった。<br>
数値型（`SUM`）側には設定済みだったため、論理削除除外の条件を両型で統一した。

<br>

**④ `numeric?` メソッドで型判定をスナップショットデータから行う**

<br>

`habit_id` が `on_delete: :nullify` で NULL になっている可能性があるため、<br>
`habit.numeric_type?` ではなく `actual_value.present?` で判定する設計を採用。<br>
スナップショットデータ（`actual_value`）を信頼することで、習慣が削除された後も正しく表示できる。

<br>

#### 追加メソッド

<br>

| メソッド | 種別 | 内容 |
|:---|:---|:---|
| `numeric?` | インスタンス | `actual_value.present?` で数値型かどうかを判定 |
| `summary_text` | インスタンス | チェック型:「5 / 7 日（71%）」/ 数値型:「90 / 120 分（75%）」形式で返す |

<br>

**`format("%g")` を使う理由:**<br>
`%g` は末尾のゼロを除去する書式指定子。<br>
`90.0 → "90"`、`6.5 → "6.5"` と自動整形されるため「90.0 分」のような冗長な表示を防げる。

<br>

#### あわせて実施した修正

<br>

| 修正内容 | 対象 |
|:---|:---|
| プログレスバーの色閾値を3段階（80/50）→4段階（100/70/40）に変更 | `rate_hex_color` / `rate_color` ヘルパー |
| 全画面のプログレスバーを `rate_hex_color` インラインスタイルに統一 | ダッシュボード / 習慣管理 / 振り返り一覧 / 振り返り詳細 |
| 習慣管理の進捗数値色を `rate_hex_color` に統一 | `habits/index.html.erb` |
| 習慣作成フォームの週次目標値送信バグを修正 | `habit_form_controller.js`（hidden input 廃止・number_field 1つで管理） |
| favicon.ico を追加（404エラー解消） | `public/favicon.ico` |
| stylesheet の preload 警告を抑制 | `application.html.erb`（`preload: false`） |
| `achievement_rate_text` メソッドを使い達成率表示を小数点2桁に統一 | `show.html.erb` |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `db/migrate/20260512120319_add_actual_value_and_unit_to_weekly_reflection_habit_summaries.rb` | 新規作成（actual_value / unit カラム追加） |
| `app/models/weekly_reflection_habit_summary.rb` | `build_from_habit` を数値型対応・`numeric?` / `summary_text` メソッド追加・バリデーション追加 |
| `app/views/weekly_reflections/show.html.erb` | 習慣別実績を `summary_text` に統一・`rate_hex_color` に統一・`achievement_rate_text` 使用 |
| `app/helpers/application_helper.rb` | `rate_hex_color` / `rate_color` を3段階→4段階に変更 |
| `app/views/habits/index.html.erb` | プログレスバー・進捗数値色を `rate_hex_color` に統一 |
| `app/views/weekly_reflections/index.html.erb` | プログレスバーを `rate_hex_color` に統一 |
| `app/javascript/controllers/habit_form_controller.js` | `querySelector` ベースに変更（週次目標値の送信バグ修正） |
| `app/views/habits/new.html.erb` | hidden input 廃止・number_field 1つで週次目標値を管理 |
| `app/views/layouts/application.html.erb` | `preload: false` 追加（preload 警告抑制） |
| `public/favicon.ico` | 新規作成（404エラー解消） |
| `test/models/weekly_reflection_habit_summary_test.rb` | 数値型テストケース追加・`numeric?` / `summary_text` テスト追加 |
| `test/fixtures/weekly_reflection_habit_summaries.yml` | `actual_value` / `unit` カラム対応・数値型フィクスチャ追加 |
| `test/fixtures/habits.yml` | `habit_numeric` フィクスチャ追加 |
| `test/fixtures/users.yml` | `fixture_only_user` 追加（既存テストの件数アサーション保護） |
| `test/integration/habit_full_flow_test.rb` | `HabitRecord` 取得をユーザー・習慣で絞り込みに変更 |

<br>

#### テスト結果

<br>

```
全テスト: 586 runs, 1481 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #E-3: AI提案プレビューモーダル・プログレスバーリアルタイム更新・AI分析完了通知

<br>

**ブランチ:** `feature/e3-ai-proposal-modal`<br>
**完了日:** 2026-05-16<br>
**概要:** 週次振り返りのAI分析結果をプレビューモーダル（14-A）で確認・確定できる機能を実装。<br>
あわせて /habits・/dashboard のプログレスバーリアルタイム更新と、<br>
AI分析完了時の Turbo Stream 自動バナー切替を実装した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| View | `weekly_reflections/_ai_proposal_modal.html.erb` を新規作成（デスクトップ中央モーダル＋スマホボトムシート） |
| View | `weekly_reflections/_ai_proposal_modal_content.html.erb` を新規作成（AI提案内容・PMVVとの整合性・変更サマリー） |
| View | `weekly_reflections/_ai_proposal_banner.html.erb` を新規作成（Turbo Stream target・分析中/完了バナー切替） |
| View | `habits/_habit_card.html.erb` を新規作成（習慣カード全体パーシャル・プログレスバー含む） |
| View | `dashboards/_habit_stat_row.html.erb` を新規作成（ダッシュボード習慣達成率バーパーシャル） |
| View | `habits/index.html.erb` のカードループを `_habit_card` パーシャルに移行 |
| View | `dashboards/index.html.erb` の習慣バーを `_habit_stat_row` パーシャルに移行（id付与） |
| View | `weekly_reflections/index.html.erb` に `turbo_stream_from` を追加・バナー部分をパーシャルに置き換え |
| JS | `ai_proposal_modal_controller.js` を新規作成（モーダル開閉・除外ボタン・ESCキー対応） |
| JS | `index.js` に `ai-proposal-modal` コントローラーを登録 |
| Controller | `confirm_proposals` アクションを新規追加（二重送信防止・is_locked解除・ai_generated:true設定） |
| Controller | `habit_records_controller.rb` に `build_turbo_stream_response` / `build_habit_stats` を追加（リクエスト元ページ判定） |
| Controller | `weekly_reflections_controller.rb` の `index` アクションに `@latest_reflection` / `@latest_ai_analysis` / `@current_purpose` を追加 |
| Controller | `user_purposes_controller.rb` の `apply_proposals` に冪等性チェック追加・`parse_frequency_to_weekly_target` でデフォルト7に統一 |
| Job | `weekly_reflection_analysis_job.rb` に `broadcast_completion` private メソッドを追加（AI分析完了時に Turbo Stream 通知） |
| Route | `config/routes.rb` に `post :confirm_proposals` を追加 |

<br>

#### AI提案プレビューモーダル（14-A）の設計

<br>

| 機能 | 内容 |
|:---|:---|
| AI免責バナー | 毎回表示。「AI提案は参考情報です」を明示する |
| PMVVとの整合性 | `user_purpose` が存在する場合、提案がPMVVに沿っているか表示 |
| 変更サマリー | 追加・変更・除外の差分一覧を視覚的に表示 |
| タスク除外ボタン | 「除外」ボタンでカードを DOM から削除（`data-task-card` 属性で特定） |
| 確定ボタン | 「来週の計画を確定」→ `confirm_proposals` POST → `is_locked: false` 解除・`ai_generated: true` 設定 |
| 二重送信防止 | `ai_analysis.created_at` 以降に `ai_generated: true` タスクが存在すれば冪等処理 |
| ESCキー対応 | `disconnect()` でイベントリスナーを確実に解放（Turbo Back対策） |

<br>

#### プログレスバーリアルタイム更新の設計

<br>

| ページ | 更新対象 | 仕組み |
|:---|:---|:---|
| `/habits` | id=`habit_record_#{habit.id}` のカード全体 | `turbo_stream.replace` で `_habit_card` パーシャルを置き換え（プログレスバー含む） |
| `/dashboard` | id=`habit_record_row_#{habit.id}` + id=`dashboard_habit_stat_#{habit.id}` | チェックボックス部分と達成率バーの2件を同時 `turbo_stream.replace` |

<br>

`request.referer` でリクエスト元ページを判定し、`/habits` か否かで Turbo Stream の対象を切り替える設計を採用。<br>
既存の JavaScript（`habit_record_controller.js`）を変更せずに済む方式。

<br>

#### AI分析完了通知（Turbo Stream）の設計

<br>

```
振り返り完了 → WeeklyReflectionAnalysisJob 実行
  ↓ AI分析完了
  ↓ broadcast_completion が solid_cable に broadcast
  ↓ weekly_reflections/index が "weekly_reflection_#{reflection.id}" チャンネルを購読
  ↓ id="weekly_reflection_ai_banner" が自動更新
  ↓ 「AI分析中...」→「AI提案を確認する →」に切り替わる（リロードなし）
```

<br>

#### 数値型習慣のデフォルト値統一

<br>

| 修正箇所 | 変更内容 |
|:---|:---|
| `habit_form_controller.js` | 数値型切替時のデフォルト 5 → 7 に変更 |
| `weekly_reflections_controller.rb` の `parse_frequency_to_weekly_target` | デフォルト 5 → 7 |
| `user_purposes_controller.rb` の `parse_frequency_to_weekly_target` | デフォルト 7（統一） |

<br>

#### テスト結果

<br>

```
全テスト: 586 runs, 1481 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #E-4: 通知ディープリンク実装（redirect_to パラメータ）

<br>

**ブランチ:** `feature/e4-deep-link`<br>
**完了日:** 2026-05-16<br>
**概要:** LINE通知のURLをタップした未ログインユーザーを `/login?redirect_to={path}` へ誘導し、<br>
ログイン後に元のページへ自動遷移する機能を実装。<br>
オープンリダイレクト攻撃（外部URLへの不正誘導）を防ぐセキュリティチェックも実装した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Controller | `ApplicationController#require_login` に `redirect_to` パラメータ対応を追加<br>未ログイン時は `login_path(redirect_to: request.fullpath)` へリダイレクト |
| Controller | `ApplicationController#safe_redirect_path?` を新規追加（オープンリダイレクト防止）<br>外部URL・ダブルスラッシュ（`//evil.com`）・`javascript:` スキームを拒否 |
| Controller | `SessionsController#create` にログイン後のディープリンク遷移を追加<br>`determine_redirect_path` で優先順位（onboarding優先 → redirect_to → dashboard）を明確化 |
| View | `sessions/new.html.erb` に `hidden_field_tag :redirect_to` を追加<br>ログイン失敗後に再表示されても `redirect_to` パラメータが POST body に維持される |
| Service | `app/services/notification_service.rb` を新規作成<br>LINE/メール通知メッセージに `deep_link_url` を埋め込む処理を集約（G-1実装後に拡張予定） |
| Job | `TaskAlarmJob` を `NotificationService` に委譲するよう更新<br>`increment_notification_count!` をプレースホルダー方式（`["...", Time.current]`）に修正 |
| i18n | `config/locales/ja.yml` に `deep_link.invalid_redirect` メッセージを追加 |
| Test | `test/controllers/sessions_controller_test.rb` を新規作成（10ケース）<br>正常系・外部URL・ダブルスラッシュ・`javascript:` の全パターンを網羅 |
| Test | 既存22テストの `assert_redirected_to login_path` を `assert_redirected_to %r{/login}` に修正<br>（E-4 でクエリパラメータが付くようになったため正規表現に変更） |

<br>

#### safe_redirect_path? の検証ロジック

<br>

| 入力値 | 結果 | 理由 |
|:---|:---|:---:|
| `/weekly_reflections/new` | ✅ 安全 | 相対パス・スラッシュ始まり |
| `/tasks?tab=must` | ✅ 安全 | クエリ文字列付き相対パス |
| `http://evil.com` | ❌ 危険 | ホスト名あり |
| `//evil.com` | ❌ 危険 | ダブルスラッシュ（外部ホスト指定として悪用可能） |
| `javascript:alert(1)` | ❌ 危険 | 不正URI（`URI::InvalidURIError`） |
| `nil` / `""` | ❌ 危険 | `blank?` チェックで弾く |

<br>

#### ログイン後の遷移優先順位

<br>

| 優先度 | 条件 | 遷移先 | 理由 |
|:---:|:---|:---|:---|
| 1位 | `first_login_at` が nil（初回ログイン） | `onboarding_step5_path` | PMVV 未設定のユーザーを他ページに飛ばすと機能しない |
| 2位 | `redirect_to` が安全なパスを指す | その `redirect_to` のパス | LINE通知経由のディープリンクは元ページに戻すべき |
| 3位 | その他（パラメータなし・外部URL） | `dashboard_path` | 従来通りの動作を維持 |

<br>

#### NotificationService の設計

<br>

| メソッド | 用途 | deep_link_url |
|:---|:---|:---|
| `send_alarm(task:)` | タスクアラーム通知 | `/tasks/#{task.id}` |
| `send_weekly_report(weekly_reflection:)` | 週次レポート通知（G-2予定） | `/weekly_reflections/new` |
| `send_ai_result(user_purpose:)` | AI分析完了通知（将来実装予定） | `/user_purposes/#{user_purpose.id}` |

<br>

LINE通知は G-1（LINE Messaging API 通知基盤）実装後に有効化予定。<br>
現時点では LINE 設定済みでもメール通知にフォールバックし、ログに `original_channel=line actual_channel=email` を記録する。

<br>

### #E-5: 振り返り詳細ページ（15番）の強化

<br>

**ブランチ:** `feature/e-5-reflection-show-enhancement`<br>
**完了日:** 2026-05-17<br>
**概要:** 振り返り詳細ページ（15番）に AI分析コメント・分析待機中ポーリング・AI免責バナーを追加。<br>
気分スコア・習慣スナップショット・タスクスナップショット（#E-1〜#E-4で実装済み）と統合し、<br>
振り返り詳細画面を完全な形に仕上げた。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Controller | `WeeklyReflectionsController#show` に `@ai_analysis` アサインを追加<br>`.latest + .order(created_at: :desc)` で最新保証<br>`analysis_comment: nil` のレコードもビュー側で判定できるよう除外しない設計に変更 |
| View | `show.html.erb` にセクション⑤（AI分析コメント）を追加<br>分析完了時: 💬総合コメント / 🔍根本原因 / 💡改善提案 / 🎯コーチングメッセージ を条件付きで表示<br>分析待機中: スピナーUI + Stimulus ポーリングコントローラー接続<br>`@ai_analysis` が nil の場合はセクション全体を非表示 |
| View | AI分析表示時のみ `shared/_ai_disclaimer` を描画（AI免責バナー） |
| JS | `ai_analysis_polling_controller.js` を新規作成<br>10秒間隔で fetch → AI分析セクションを部分更新（outerHTML差し替えでスクロール位置維持）<br>完了検知後に `clearInterval` でポーリング自動停止<br>分析完了 = 待機UIが DOM から消えたことを検知する設計 |
| Config | `config/environments/development.rb` に `config.action_view.preload_links_header = false` を追加<br>Rails 7.2 + Turbo 環境の CSS preload 警告を開発環境限定で抑制<br>`respond_to?(:preload_links_header=)` で将来の Rails アップデートにも対応 |

<br>

#### AI分析表示の設計

<br>

| 状態 | 条件 | 表示 |
|:---|:---|:---|
| レコードなし | `@ai_analysis.nil?` | セクション⑤・免責バナーともに非表示 |
| 分析完了 | `analysis_comment.present?` | 4つのカード（💬🔍💡🎯）を表示 |
| 分析待機中 | `analysis_comment.nil?` | スピナー + 「自動で切り替わります」を表示してポーリング開始 |

<br>

#### ポーリングの設計

<br>
振り返り詳細ページを開く（分析待機中）
↓ ai_analysis_polling_controller が connect()
↓ 10秒ごとに fetch → 同ページの HTML を取得
↓ id="ai-analysis-section" の内容を比較
↓ 待機UIが消えていれば → outerHTML を差し替え → ポーリング停止
→ 画面が「AI分析中...」→「完了カード」に切り替わる（リロード不要）

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/controllers/weekly_reflections_controller.rb` | `show` アクションに `@ai_analysis` アサインを追加（`.latest.order(created_at: :desc).first`） |
| `app/views/weekly_reflections/show.html.erb` | セクション⑤（AI分析 + 免責バナー）を追加・待機UIに Stimulus 接続 |
| `app/javascript/controllers/ai_analysis_polling_controller.js` | 新規作成（fetch ポーリング・outerHTML差し替え・完了検知・clearInterval） |
| `config/environments/development.rb` | `config.action_view.preload_links_header = false` を追加（CSS preload 警告抑制） |

<br>

#### テスト結果

<br>

```
全テスト: 596 runs, 1473 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #F-1: OmniAuth Google ログイン

<br>

**ブランチ:** `feature/f-1-omniauth-google`<br>
**完了日:** 2026-05-18<br>
**概要:** Google アカウントでのログイン・新規登録を実装。<br>
`users.provider='google_oauth2'` / `users.uid=Google sub` で管理。<br>
既存メールアカウントと同じメールの Google アカウントでログインした場合は<br>
既存アカウントに Google 情報をマージする（重複作成しない）設計。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Gem | `omniauth-google-oauth2 ~> 1.2` / `omniauth-rails_csrf_protection` を追加 |
| Initializer | `config/initializers/omniauth.rb` を新規作成（Google OAuth2 設定・on_failure ハンドリング） |
| Model | `User.from_omniauth` クラスメソッドを追加（3段階: provider+uid検索 → メールマージ → 新規作成） |
| Model | `has_secure_password validations: false` に変更（Google ユーザーはパスワード不要） |
| Model | `password` バリデーションに `if: :email_provider?` 条件を追加 |
| Migration | `password_digest` カラムの NOT NULL 制約を解除 |
| Controller | `OmniauthCallbacksController` を新規作成（google アクション・failure アクション） |
| Controller | 初回ログイン判定（`first_login_at IS NULL` → オンボーディングへ遷移） |
| Route | `/auth/google_oauth2/callback` / `/auth/failure` を追加 |
| View | `shared/_google_auth_button.html.erb` を新規作成（共通部分テンプレート） |
| View | `sessions/new.html.erb` に「Google アカウントでログイン」ボタンを追加 |
| View | `users/new.html.erb` に「Google アカウントで登録」ボタンを追加 |
| CSP | `content_security_policy.rb` に `form_action` へ Google ドメインを追加 |
| i18n | `ja.yml` に `omniauth.google.*` メッセージを追加 |

<br>

#### 認証フロー

<br>

```
ユーザーが「Googleでログイン」ボタンをクリック
  ↓ POST /auth/google_oauth2（button_to + data-turbo="false"）
  ↓ OmniAuth ミドルウェアが Google 認証ページへリダイレクト
  ↓ ユーザーが Google でログインを許可
  ↓ GET /auth/google_oauth2/callback
  ↓ User.from_omniauth が ① provider+uid 検索 → ② メールマージ → ③ 新規作成
  ↓ reset_session でセッション固定攻撃を防止
  ↓ first_login_at が nil → オンボーディングへ / それ以外 → ダッシュボードへ
```

<br>

#### 既存メールアカウントとのマージ設計

<br>

| ケース | 動作 |
|:---|:---|
| 初回 Google ログイン（未登録） | 新規ユーザーを作成。`first_login_at: nil` のためオンボーディングへ |
| 2回目以降 Google ログイン | `provider + uid` で検索して既存ユーザーを返す |
| 同じメールでメール登録済み | `update_columns(provider:, uid:)` で既存アカウントにマージ（重複作成しない） |

<br>

#### 技術的な設計ポイント

<br>

**① `button_to` + `form_tag` の使い分け**

<br>

`button_to` に `do...end` ブロックを渡すと無限レンダリングループが発生する既知のバグがある。<br>
`form_tag + <button>` の組み合わせで POST ボタンを安全に実装した。<br>
`data-turbo="false"` を文字列で指定することで `data-turbo="false"` が確実に出力される。

<br>

**② `update_columns` でマージする理由**

<br>

`update!` を使うと `email` の uniqueness バリデーションが実行され、<br>
自分自身のメールと衝突してバリデーションエラーになるリスクがある。<br>
`provider` と `uid` のみを更新するだけなので `update_columns` が安全で適切。

<br>

**③ `password_digest` の NOT NULL 制約解除**

<br>

Google ユーザーはパスワードを持たないため `password_digest` が NULL になる。<br>
既存スキーマには NOT NULL 制約があったため、マイグレーションで制約を解除した。<br>
セキュリティ上の懸念はなく、`has_secure_password` の `authenticate` は<br>
`password_digest: nil` のユーザーに対して必ず `false` を返す。

<br>

**④ `skip_before_action :verify_authenticity_token` が必要な理由**

<br>

`omniauth-rails_csrf_protection` は認証開始リクエスト（POST /auth/google_oauth2）を保護する。<br>
コールバック（GET /auth/google_oauth2/callback）は Google からのリダイレクトのため<br>
Rails の authenticity_token が含まれず、CSRF 検証をスキップする必要がある。<br>
OAuth2 の state パラメータで CSRF は別途保護されているため安全。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` | `omniauth-google-oauth2 ~> 1.2` / `omniauth-rails_csrf_protection` を追加 |
| `config/initializers/omniauth.rb` | 新規作成（Google OAuth2 設定・on_failure・prompt: "select_account"） |
| `config/initializers/content_security_policy.rb` | `policy.form_action :self, "https://accounts.google.com"` を追加 |
| `config/routes.rb` | `/auth/google_oauth2/callback` / `/auth/failure` を追加 |
| `app/models/user.rb` | `from_omniauth` クラスメソッド追加・`has_secure_password validations: false`・`email_provider?` メソッド追加 |
| `app/controllers/omniauth_callbacks_controller.rb` | 新規作成（google / failure アクション） |
| `app/views/shared/_google_auth_button.html.erb` | 新規作成（`form_tag + button` 方式・無限ループ対策済み） |
| `app/views/sessions/new.html.erb` | Google ログインボタン追加 |
| `app/views/users/new.html.erb` | Google 登録ボタン追加 |
| `config/locales/ja.yml` | `omniauth.google.success/failure/login_error` を追加 |
| `db/migrate/20260518131434_allow_null_password_digest_for_oauth_users.rb` | `password_digest` の NOT NULL 制約を解除 |

#### テスト結果

<br>

```
全テスト: 596 runs, 1473 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #F-2: OmniAuth LINE ログイン

<br>

**ブランチ:** `feature/f-2-omniauth-line`<br>
**完了日:** 2026-05-21<br>
**概要:** LINE アカウントでのログイン・新規登録を実装。<br>
`users.provider='line_v2_1'` / `users.uid=LINE sub` で管理。<br>
LINE Messaging API の `line_user_id`（通知用）とは別カラムで管理する設計。<br>
`omniauth-line-v2_1` gem（OmniAuth 2.x 対応の最新安定版・2025年11月リリース）を採用。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Gem | `omniauth-line-v2_1 ~> 1.2` を追加（OmniAuth 2.x / Rails 7.x 対応・cadenza-tech製） |
| Initializer | `config/initializers/omniauth.rb` に `:line_v2_1` プロバイダを追加（`scope: "profile openid"`） |
| Model | `User.from_omniauth` を LINE（メールなし）に対応するよう拡張<br>LINE は email を返さないため `find_by(email: nil)` による誤マージを防ぐ条件分岐を追加<br>`fallback_name_for` クラスメソッドで `"LINE User"` を返す |
| Migration | `users.email` カラムの NOT NULL 制約を解除<br>（LINE ユーザーはメールアドレスなしで登録されるため必須） |
| Controller | `OmniauthCallbacksController` に `line` アクションを追加<br>`skip_before_action` に `:line` を追加（OAuthコールバックのCSRF除外） |
| Route | `/auth/line_v2_1/callback` ルートを追加 |
| View | `shared/_line_auth_button.html.erb` を新規作成（`form_tag + button` 方式・無限ループ対策済み）<br>LINE ブランドカラー `#06C755`（緑）・公式SVGアイコン |
| View | `sessions/new.html.erb` に「LINEでログイン」ボタンを追加 |
| View | `users/new.html.erb` に「LINEで登録」ボタンを追加 |
| Controller | `sessions_controller.rb` の `new` アクションにログイン済みチェックを追加<br>（ブラウザの「戻る」ボタン対策・ログイン済みならダッシュボードへリダイレクト） |
| CSP | `content_security_policy.rb` の `form_action` に `"https://access.line.me"` を追加 |
| ENV | `docker-compose.yml` に `LINE_CHANNEL_ID` / `LINE_CHANNEL_SECRET` 環境変数を追加 |
| i18n | `ja.yml` に `omniauth.line.*` メッセージを追加 |
| Test | `test/models/user_test.rb` に LINE 用テスト4件を追加 |

<br>

#### 認証フロー

<br>
ユーザーが「LINEでログイン」ボタンをクリック
↓ POST /auth/line_v2_1（form_tag + data-turbo="false"）
↓ OmniAuth ミドルウェアが LINE の認証ページへリダイレクト
↓ ユーザーが LINE でログインを許可
↓ GET /auth/line_v2_1/callback
↓ User.from_omniauth が ① provider+uid 検索 → ② 新規作成（LINEはメールマージなし）
↓ reset_session でセッション固定攻撃を防止
↓ first_login_at が nil → オンボーディングへ / それ以外 → ダッシュボードへ

<br>

#### uid と line_user_id の分離設計

<br>

| カラム | 用途 | 値の例 |
|:---|:---|:---|
| `users.uid` | LINE Login の sub（OmniAuth ログイン識別子） | `Ufb48e50c42efe835c44194c829167ab3` |
| `users.line_user_id` | LINE Messaging API 通知用 userId（G-1 で実装予定） | NULL（未設定） |
| `users.provider` | 認証プロバイダ識別子 | `"line_v2_1"` |

<br>

LINE Login の sub（`uid`）と Messaging API の userId（`line_user_id`）は別物。<br>
混同すると将来の通知実装（#G-1）で事故が発生するため明確に分離して管理する。

<br>

#### 技術的な設計ポイント

<br>

**① gem 名とストラテジー名が異なる**

<br>

| 種類 | 値 |
|:---|:---|
| gem 名（Gemfile） | `omniauth-line-v2_1` |
| ストラテジーファイル | `omniauth/strategies/line_v2_1.rb` |
| provider シンボル | `:line_v2_1`（`LineV21` の snake_case 変換） |
| コールバック URL | `/auth/line_v2_1/callback` |
| `users.provider` に保存される値 | `"line_v2_1"` |

<br>

`:line` を指定すると `OmniAuth::Strategies::Line` を探してしまい<br>
`uninitialized constant OmniAuth::Strategies::Line` エラーになる。<br>
`:line_v21`（アンダースコアが1つ）も `LineV21` に対応するが、<br>
実際のストラテジーファイル名が `line_v2_1` のため `:line_v2_1` が正しい。

<br>

**② LINE はメールアドレスを返さない**

<br>

LINE の email スコープは別途申請が必要な特権スコープのため、<br>
通常の `profile openid` スコープでは `auth["info"]["email"]` が存在しない。<br>
`email.present?` の条件分岐でマージ処理をスキップし、<br>
`users.email` は NULL のまま保存する（`allow_nil: true` 対応済み）。

<br>

**③ `users.email` の NOT NULL 制約解除が必要**

<br>

Rails モデルの `allow_nil: true` はRailsレベルのバリデーションのみ。<br>
PostgreSQL の NOT NULL 制約はDB レベルで `INSERT` 時に NULL を拒否するため、<br>
LINE ユーザーの登録時に `PG::NotNullViolation` が発生する。<br>
`change_column_null :users, :email, true` のマイグレーションで解除が必要。

<br>

**④ LINE Developers Console の設定**

<br>

| 設定項目 | 値 |
|:---|:---|
| チャネルの種類 | LINE Login |
| アプリタイプ | ✅ ウェブアプリ |
| コールバック URL（開発） | `http://localhost:3000/auth/line_v2_1/callback` |
| コールバック URL（本番） | `https://your-app.onrender.com/auth/line_v2_1/callback` |
| 開発中チャネルのテスト | 権限設定 → メールで招待 → Role: Tester で自アカウントを追加 |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` | `omniauth-line-v2_1 ~> 1.2` を追加 |
| `config/initializers/omniauth.rb` | `:line_v2_1` プロバイダを追加（`scope: "profile openid"`） |
| `config/initializers/content_security_policy.rb` | `policy.form_action` に `"https://access.line.me"` を追加 |
| `config/routes.rb` | `/auth/line_v2_1/callback` を追加 |
| `app/models/user.rb` | `from_omniauth` を LINE 対応に拡張・`fallback_name_for` クラスメソッド追加 |
| `app/controllers/omniauth_callbacks_controller.rb` | `line` アクション追加・`skip_before_action` に `:line` 追加 |
| `app/controllers/sessions_controller.rb` | `new` アクションにログイン済みチェック追加 |
| `app/views/shared/_line_auth_button.html.erb` | 新規作成（`form_tag + button` 方式・`#06C755` 緑・公式SVGアイコン） |
| `app/views/sessions/new.html.erb` | LINE ログインボタン追加・区切り線条件分岐修正 |
| `app/views/users/new.html.erb` | LINE 登録ボタン追加・区切り線条件分岐修正 |
| `config/locales/ja.yml` | `omniauth.line.success/failure/login_error` を追加・`omniauth.error.login_error` を追加 |
| `docker-compose.yml` | `LINE_CHANNEL_ID` / `LINE_CHANNEL_SECRET` 環境変数を追加 |
| `db/migrate/YYYYMMDDHHMMSS_remove_not_null_from_users_email.rb` | `users.email` の NOT NULL 制約を解除 |
| `test/models/user_test.rb` | LINE 用テスト4件追加（新規作成・重複なし・フォールバック名・パスワード不要） |

<br>

#### テスト結果

<br>

```
全テスト: 600 runs, 1487 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #F-3: 利用規約・プライバシーポリシー同意（登録時必須）

<br>

**ブランチ:** `feature/f3-terms-agreement`<br>
**完了日:** 2026-05-23<br>
**概要:** ユーザー登録時に利用規約・プライバシーポリシーへの同意を必須化する機能を実装。<br>
OAuth（Google/LINE）初回ログイン時も同意ページを表示し、同意日時を DB に記録する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Migration | `users` テーブルに `terms_agreed_at datetime` カラムを追加（NULL許容・同意済みのみ部分インデックス） |
| Model | `User` に `attr_accessor :terms_agreed` 仮想属性を追加 |
| Model | `validates :terms_agreed, acceptance: true, if: :email_provider?` バリデーションを追加 |
| Model | `before_validation :set_terms_agreed_at, if: :email_provider?` で同意時に日時を自動記録 |
| Model | `terms_agreed?` を public メソッドとして定義（ApplicationController から呼ぶため） |
| Controller | `ApplicationController` に `redirect_to_terms_agreement_if_needed` を追加（全画面ガード） |
| Controller | `redirect_to_onboarding_if_needed` の除外リストに `terms_agreement` を追加 |
| Controller | `OmniauthCallbacksController` の遷移優先度1を `terms_agreed?` チェックに変更 |
| Controller | `TermsAgreementController` を新規作成（show / agree アクション） |
| Controller | `PagesController` に `terms` / `privacy` アクションを追加 |
| View | `users/new.html.erb` に同意チェックボックスを追加（未チェック時ボタン非活性） |
| View | `terms_agreement/show.html.erb` を新規作成（OAuth初回ログイン用同意ページ） |
| View | `pages/terms.html.erb` / `pages/privacy.html.erb` を新規作成（未ログイン閲覧可） |
| View | `shared/_footer.html.erb` を新規作成（利用規約・プライバシーポリシーリンク） |
| JS | `terms_agreement_controller.js` を新規作成（チェックボックスOFF時ボタン非活性） |
| JS | `index.js` に `TermsAgreementController` を手動登録 |
| Route | `/terms` / `/privacy` / `/terms_agreement`（GET/POST）を追加 |
| i18n | `ja.yml` に `terms_agreement.*` メッセージを追加 |
| i18n | `attributes: > user: > terms_agreed: "利用規約への同意"` を追加 |
| Test | `test/fixtures/users.yml` 全ユーザーに `terms_agreed_at` を追加（既存テスト保護） |
| Test | `test_helper.rb` の `log_in_as` に `terms_agreed_at` 自動設定を追加 |
| Test | `test/controllers/terms_agreement_controller_test.rb` を新規作成（6件） |

<br>

#### 設計上の重要ポイント

<br>

**① `terms_agreed?` は public に置く**

<br>

`ApplicationController` の `redirect_to_terms_agreement_if_needed` から<br>
`user.terms_agreed?` を呼ぶため、`private` に置くと `NoMethodError` が発生する。<br>
`def terms_agreed?` は public ブロックに定義し、`set_terms_agreed_at` のみ private にする。

<br>

**② `attr_accessor :terms_agreed` は必須**

<br>

`validates :terms_agreed, acceptance: true` だけでは仮想属性が自動生成されない。<br>
フォームから `terms_agreed: "1"` を受け取るために `attr_accessor` が必要。

<br>

**③ バリデーションは `if: :email_provider?` で条件付き**

<br>

Google/LINE ユーザーは登録フォームを経由しないため、<br>
`allow_nil: true` より `if: :email_provider?` の方が安全。<br>
OAuthユーザーのプロフィール更新時にバリデーションが誤って発火しない設計になる。

<br>

**④ `before_validation` で `set_terms_agreed_at` を実行**

<br>

`before_save` だと全保存で毎回走ってしまう。<br>
`before_validation` + `if: :email_provider?` で「メールユーザーの登録時のみ」に限定する。

<br>

**⑤ fixture全ユーザーに `terms_agreed_at` 追加が必須**

<br>

`terms_agreed_at` が nil のユーザーでテストがログインすると<br>
全画面ガードで `/terms_agreement` にリダイレクトされ、既存テストが全て失敗する。<br>
`test/fixtures/users.yml` 全ユーザーに `terms_agreed_at: "2026-01-01 00:00:00"` を追加することで<br>
既存テストへの影響をゼロにできる。

<br>

**⑥ `log_in_as` に自動設定を追加してテスト修正を最小化**

<br>

`test_helper.rb` の `log_in_as` で `terms_agreed_at` が nil のユーザーに<br>
自動的に `update_column` で日時をセットすることで、<br>
未同意テスト以外の全テストが修正なしで動作する。<br>
未同意状態が必要なテストだけ `log_in_as` の後に `user.update_column(:terms_agreed_at, nil)` で戻す。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `db/migrate/YYYYMMDDHHMMSS_add_terms_agreed_at_to_users.rb` | 新規作成（datetime・NULL許容・部分インデックス） |
| `app/models/user.rb` | `attr_accessor :terms_agreed`・`validates :terms_agreed`・`before_validation :set_terms_agreed_at`・`terms_agreed?`（public）・`set_terms_agreed_at`（private）を追加 |
| `app/controllers/application_controller.rb` | `redirect_to_terms_agreement_if_needed` 追加・`redirect_to_onboarding_if_needed` の除外リスト更新 |
| `app/controllers/users_controller.rb` | `user_params` に `:terms_agreed` を追加 |
| `app/controllers/omniauth_callbacks_controller.rb` | `determine_redirect_path_for_omniauth` に優先度1として `terms_agreed?` チェックを追加 |
| `app/controllers/terms_agreement_controller.rb` | 新規作成（show / agree アクション・`require_login`・`ensure_needs_agreement`） |
| `app/controllers/pages_controller.rb` | `terms` / `privacy` アクション追加 |
| `config/routes.rb` | `/terms` / `/privacy` / `/terms_agreement`（GET/POST）を追加 |
| `app/views/users/new.html.erb` | 同意チェックボックス追加（data-controller="terms-agreement form-submit"） |
| `app/views/terms_agreement/show.html.erb` | 新規作成 |
| `app/views/pages/terms.html.erb` | 新規作成 |
| `app/views/pages/privacy.html.erb` | 新規作成 |
| `app/views/shared/_footer.html.erb` | 新規作成（利用規約・プライバシーポリシーリンク） |
| `app/javascript/controllers/terms_agreement_controller.js` | 新規作成（checkbox / button ターゲット・connect / toggle メソッド） |
| `app/javascript/controllers/index.js` | `TermsAgreementController` を手動登録追加 |
| `config/locales/ja.yml` | `terms_agreement.*` メッセージ・`user.terms_agreed` 属性名を追加 |
| `test/fixtures/users.yml` | 全ユーザーに `terms_agreed_at: "2026-01-01 00:00:00"` を追加 |
| `test/test_helper.rb` | `log_in_as` に `terms_agreed_at` 自動設定を追加 |
| `test/controllers/terms_agreement_controller_test.rb` | 新規作成（6件：未同意表示・未ログインリダイレクト・同意済みリダイレクト・同意でダッシュボード遷移・初回ログインでオンボーディング遷移・チェックなし422） |

<br>

#### テスト結果

<br>

```
全テスト: 607 runs, 1501 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #F-4: パスワードリセット機能（Resend メール送信）

<br>

**ブランチ:** `feature/f4-password-reset`<br>
**完了日:** 2026-05-23<br>
**概要:** メールアドレスを入力するとパスワードリセットURLをResend経由で送信する機能を実装。<br>
BCryptハッシュ化済みトークンのDB保存・24時間有効期限・使用済み無効化・メール列挙攻撃防止に対応。

<br>

#### 実装画面

<br>

| 画面番号 | URL | 内容 |
|:---|:---|:---|
| 23番 | `/password_resets/new` | メールアドレス入力フォーム |
| 26番 | `/password_resets/:token/edit` | 新パスワード入力フォーム |
| 27番 | ログインページ（リダイレクト先） | パスワード変更成功後 |
| 29番 | エラーページ（HTTP 404） | トークン無効・期限切れ・使用済み |

<br>

#### セキュリティ設計

<br>

| 設計ポイント | 内容 |
|:---|:---|
| BCryptハッシュ化保存 | 平文トークンはDB非保存。DB漏洩時にリセットURLを復元不可（Devise同様の設計） |
| UNIQUE制約（user_id） | 1ユーザーにつきトークン1件のみ存在。多重発行を防止 |
| 24時間有効期限 | `expires_at` が現在時刻より過去のトークンは無効 |
| 使用済み無効化 | パスワード変更完了後に `is_used=true` を設定。トランザクション内で変更と無効化を一体化 |
| メール列挙攻撃防止 | 存在しないメールアドレスでも同一フラッシュメッセージを返す |
| セッション固定攻撃防止 | パスワード変更後に `reset_session` を実行 |
| OAuthユーザー除外 | Google/LINEユーザーはパスワードリセット非対象（メール非送信・フラッシュのみ表示） |

<br>

#### N+1対応

<br>

`find_by_raw_token` に `includes(:user)` を追加し、<br>
コントローラーで `@token_record.user` を参照する際の追加クエリを防止している。

<br>

#### letter_opener_web 導入（F-4修正）

<br>

Docker環境ではブラウザが自動起動しないため `letter_opener` から `letter_opener_web` に変更。<br>
`http://localhost:3000/letter_opener` でメール一覧をブラウザ確認できる。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/models/password_reset_token.rb` | 新規作成（generate_token_for / find_by_raw_token / valid_token? / expire!） |
| `app/mailers/password_mailer.rb` | 新規作成（reset_password・deliver_later） |
| `app/views/password_mailer/reset_password.html.erb` | 新規作成（HTMLメールテンプレート・インラインCSS） |
| `app/views/password_mailer/reset_password.text.erb` | 新規作成（テキストメールテンプレート） |
| `app/controllers/password_resets_controller.rb` | 新規作成（new / create / edit / update） |
| `app/views/password_resets/new.html.erb` | 新規作成（23番画面） |
| `app/views/password_resets/edit.html.erb` | 新規作成（26番画面） |
| `app/views/errors/token_invalid.html.erb` | 新規作成（29番画面・HTTP 404） |
| `app/views/sessions/new.html.erb` | 「パスワードをお忘れの方」リンクを追加 |
| `app/controllers/application_controller.rb` | `redirect_to_onboarding_if_needed` の除外リストに `password_resets` を追加 |
| `config/routes.rb` | `resources :password_resets` 追加・`mount LetterOpenerWeb::Engine` を1つの `if Rails.env.development?` ブロックに統合 |
| `config/locales/ja.yml` | `password_reset:` セクション・`helpers.submit.password_reset` を追加 |
| `Gemfile` | `letter_opener` → `letter_opener_web` に変更 |
| `config/environments/development.rb` | `delivery_method: :letter_opener_web` に変更・コメント整理 |
| `test/models/password_reset_token_test.rb` | 新規作成（15 runs） |
| `test/controllers/password_resets_controller_test.rb` | 新規作成（18 runs） |

<br>

#### テスト結果

<br>

```
F-4追加分: +33 runs, +55 assertions
全テスト:  640 runs, 1556 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #F-5: rack-attack によるブルートフォース対策

<br>

**ブランチ:** `feature/F-5-rack-attack`<br>
**完了日:** 2026-05-23<br>
**概要:** rack-attack gem でログイン試行回数制限・API全体レート制限を設定。<br>
テスト環境では `Rack::Attack.enabled = false` で無効化し、専用テストファイル内で明示的に有効化する設計を採用。<br>
Docker環境（ブリッジIPアドレス `172.18.0.1` 含む）を safelist に登録済み。

<br>

#### throttle ルール一覧

<br>

| ルール名 | 制限 | 対象 |
|:---|:---|:---|
| `login/ip` | 5分間に10回 | ログインIP別試行回数 |
| `login/email` | 20分間に10回 | ログインEmail別試行回数 |
| `api/ip` | 1分間に100リクエスト | API全体（IP別） |
| `password_reset/ip` | 15分間に5回 | パスワードリセットIP別試行回数 |

<br>

#### 設計上の重要判断

<br>

**① `unless Rails.env.test?` で全体を囲む**

<br>

`rack_attack.rb` 全体を `unless Rails.env.test?` で囲むことで、<br>
テスト環境では全throttleルールが登録されない設計にした。<br>
`class Rack::Attack do ... return ... end` 形式だと `return` が `SyntaxError` になるため、<br>
`unless Rails.env.test?` によるブロックが唯一の安全な回避策。

<br>

**② throttleルールをテストファイル内で直接登録**

<br>

initializer でテスト環境の登録をスキップするため、<br>
`rack_attack_test.rb` の setup 内でテスト用のthrottleルールを明示的に登録する設計を採用。<br>
teardown で `Rack::Attack.throttles.clear` して他テストに影響しないよう後始末する。

<br>

**③ Fail2Ban は不採用**

<br>

Rack/Rails 境界での `env` 伝達が Render 環境で保証されないため不採用。<br>
代わりに throttle（試行回数制限）のみで対策する設計にした。

<br>

**④ Docker ブリッジIP を safelist に追加**

<br>

Docker 環境では Web コンテナから DB コンテナへのアクセスが `172.18.0.1`（ブリッジIP）経由になる。<br>
safelist に `172.18.0.1` を含めないとローカル開発中もブロックされる問題が発生する。<br>
safelist 適用は `development?` 環境限定としてセキュリティを維持。

<br>

#### キャッシュ設定

<br>

| 環境 | キャッシュストア | 理由 |
|:---|:---|:---|
| development | `Rack::Attack::Cache::MemoryStore.new` | Redis 不要・ローカル開発で完結 |
| production | `Rails.cache`（Solid Cache / DB） | Render 無料プランで Redis 不要 |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` | `gem "rack-attack", "~> 6.8"` を追加 |
| `config/initializers/rack_attack.rb` | 新規作成（throttle 4種・safelist・429レスポンス設定・`unless Rails.env.test?` で全体を囲む） |
| `app/views/errors/too_many_requests.html.erb` | 新規作成（429カスタムエラーページ） |
| `app/controllers/application_controller.rb` | `render_429` メソッドを追加（rack-attack の throttled_responder から呼び出す） |
| `test/integration/rack_attack_test.rb` | 新規作成（setup/teardown でルール登録・`Rack::Attack.enabled = true` で有効化） |

<br>

#### テスト設計のポイント

<br>

`Rack::Attack.enabled` を setup で `true`・teardown で `false` に切り替え、<br>
`Rack::Attack.cache.store` に `ActiveSupport::Cache::MemoryStore.new` をセットすることで<br>
テスト間の状態が完全に分離される。<br>
throttleルールも setup 内で `Rack::Attack.throttle(...)` として直接登録するため、<br>
initializer のルール定義に依存しない独立したテスト設計になっている。

<br>

#### テスト結果

<br>

```
全テスト:  644 runs, 1574 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #F-6: ユーザーデータ削除ポリシー（退会時の論理削除 / カスケード設計）

<br>

**ブランチ:** `feature/f-6-user-destroy-policy`<br>
**完了日:** 2026-05-24<br>
**概要:** 退会時にユーザーデータをどう扱うかを明確にした。論理削除（`users.deleted_at`）と匿名化の方針を定め、<br>
「個人識別情報は即時削除・活動データは匿名化して統計用に保持」という B案（統計保持設計）を実装。

<br>

#### 削除ポリシー（確定版）

<br>

| データ種別 | 処理方針 | 理由 |
|:---|:---|:---|
| ユーザー名・メールアドレス・LINE ID | 即時匿名化（上書き） | 個人特定を不可能にする |
| パスワード情報 | BCryptランダムハッシュに置換 | 退会後のログインを完全無効化 |
| パスワードリセットトークン | 物理削除 | 退会後の悪用リスクを排除 |
| プッシュ通知の宛先情報 | 物理削除 | 退会後の通知送信を防止 |
| 習慣・タスク・振り返り・AI分析 | 匿名化して保持 | 将来の習慣継続率分析・AI精度向上に活用 |

<br>

#### 技術的な実装ポイント

<br>

**① `deleted_at` + 部分インデックスによる再登録対応**

<br>

`users.email` の unique 制約を全行対象から `WHERE deleted_at IS NULL` の部分インデックスに変更。<br>
退会済みユーザーのメールアドレスが解放されるため、同じアドレスでの再登録が可能になる。<br>
Rails バリデーション側も `conditions: -> { where(deleted_at: nil) }` で DB と完全一致させた。

<br>

**② BCrypt ランダムパスワードによるログイン無効化**

<br>

`password_digest: nil` は `null: false` 制約で落ちる。`""` は `has_secure_password` と相性が悪い。<br>
`BCrypt::Password.create(SecureRandom.hex(32))` で256bitランダムハッシュを生成することで<br>
ログイン不能・null制約クリア・has_secure_password対応の三点を同時に満たす。

<br>

**③ `before_destroy` ガードによる物理削除禁止**

<br>

`has_many` から `dependent: :destroy` を外したため、`User.destroy` を呼ぶと<br>
`PG::ForeignKeyViolation` が発生する危険がある。<br>
`before_destroy :prevent_physical_destroy` で本番・開発環境での物理削除を完全に禁止し、<br>
退会処理は必ず `UserDestroyService` 経由であることを強制する設計にした。

<br>

#### 主な作成・変更ファイル

<br>

| ファイル | 変更内容 |
|:---|:---|
| `db/migrate/YYYYMMDDHHMMSS_add_deleted_at_to_users.rb` | `deleted_at` カラム追加・部分インデックス設計（up/down 分離） |
| `app/services/user_destroy_service.rb` | 個人情報匿名化・セキュリティトークン削除・トランザクション管理 |
| `app/controllers/settings_controller.rb` | 設定ページ・退会処理アクション（新規） |
| `app/views/settings/show.html.erb` | M-4 退会確認モーダル（削除/保持データを明示） |
| `app/models/user.rb` | `scope :active`・`before_destroy` ガード・`email uniqueness conditions` 修正 |
| `config/routes.rb` | `resource :settings` 追加（`settings_path` 利用可能に） |
| `test/services/user_destroy_service_test.rb` | 完了条件3項目・統計保持確認・セキュリティトークン削除確認（新規） |

<br>

#### テスト結果

<br>

```
全テスト:  652 runs, 1593 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #G-1: LINE Messaging API 通知基盤

<br>

**ブランチ:** `feature/g-1-line-notification`<br>
**完了日:** 2026-05-31<br>
**概要:** LINE Messaging API を使ったプッシュ通知基盤を実装。<br>
タスクアラーム通知を LINE に送信し、失敗時はメールにフォールバックする設計。<br>
通知履歴を `notification_logs` に記録し、日次通知上限チェックを実装。

<br>

#### 技術構成

<br>

| 項目 | 内容 |
|:---|:---|
| 通知方式 | LINE Messaging API Push Message（Net::HTTP で直接呼び出し） |
| チャネルアクセストークン | 長期トークン（`LINE_CHANNEL_ACCESS_TOKEN` 環境変数） |
| フォールバック | LINE 送信失敗時はメール通知に自動切替 |
| 通知ログ | `notification_logs` に `channel: "line"`, `status: "success/failed/skipped"` を記録 |
| 日次上限 | `user_settings.daily_notification_limit` でユーザーごとに上限管理 |

<br>

#### LINE Console 設定

<br>

| 設定 | 内容 |
|:---|:---|
| プロバイダー | HabitFlow-Prod（新規作成・既存プロバイダーは権限問題のため別途作成） |
| LINE Login チャネル | OmniAuth LINE ログイン用（F-2 実装済み） |
| Messaging API チャネル | プッシュ通知用（同一プロバイダー下に配置することで uid == userId が保証される） |
| 料金プラン | コミュニケーションプラン（月0円・月200通・自動課金なし） |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/services/line_notification_service.rb` | 新規作成（Net::HTTP で LINE Push Message API を呼び出し） |
| `app/services/notification_service.rb` | LINE 実装を有効化・フォールバック設計を実装 |
| `app/controllers/omniauth_callbacks_controller.rb` | `save_line_user_id` メソッドを追加（LINE ログイン時に `line_user_id` を保存） |
| `app/models/notification_log.rb` | `record_success` / `record_failure` に `retry_count` 引数を追加 |
| `render.yaml` | `LINE_CHANNEL_ACCESS_TOKEN` 環境変数を追加 |
| `docker-compose.yml` | `LINE_CHANNEL_ACCESS_TOKEN` 環境変数を追加 |
| `config/locales/ja.yml` | LINE 通知関連メッセージを追加 |
| `test/services/line_notification_service_test.rb` | 新規作成（5 runs, 17 assertions） |
| `test/services/notification_service_test.rb` | 新規作成（3 runs, 13 assertions） |

<br>

#### 動作確認済み項目

<br>

| 項目 | 確認内容 |
|:---|:---|
| LINE ログイン | `users.line_user_id` に LINE userId が保存される |
| Push 通知送信 | LINE アプリにメッセージが届く |
| 通知ログ記録 | `notification_logs` に `channel: "line"`, `status: "success"` が記録される |
| 日次上限スキップ | 上限到達時に `status: "skipped"` が記録される |
| メールフォールバック | LINE 送信失敗時に `channel: "email"` で通知ログが記録される |

<br>

#### 設計上の重要判断

<br>

LINE Login チャネルと Messaging API チャネルを**同一プロバイダー**に作成することで<br>
OmniAuth で取得した `uid` と Messaging API の `userId` が一致することが保証される。<br>
別プロバイダーに作成すると両者が異なる値になり通知が届かない。

<br>

Render Free プランの Worker は利用不可のため、`habitflow-worker` サービスは使用しない。<br>
GoodJob は `execution_mode: :async` で Web プロセス内で実行される（#A-4 で設計済み）。

<br>

#### テスト結果

<br>

```
G-1テスト: 8 runs, 30 assertions, 0 failures, 0 errors, 0 skips
全テスト:  660 runs, 1623 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #G-2: 週次レポートメール（毎週月曜日 GoodJob cron）

<br>

**ブランチ:** `feature/g2-weekly-report-mail`<br>
**完了日:** 2026-05-31<br>
**概要:** 毎週月曜日 AM9:00（JST）に先週の振り返りサマリーをメールで送信する機能を実装。<br>
`user_settings.weekly_report_enabled = true` のユーザーのみが対象。<br>
HTML/テキスト multipart 形式・deep_link_url による振り返り入力ページへの直接遷移に対応。

<br>

#### 技術構成

<br>

| 項目 | 内容 |
|:---|:---|
| 送信方式 | Resend（ActionMailer 経由・`deliver_now`） |
| 実行トリガー | GoodJob cron（毎週月曜日 UTC 00:00 = JST 09:00） |
| 対象ユーザー | `user_settings.weekly_report_enabled: true` かつ `email` が存在するアクティブユーザー |
| フォールバック | 退会済み・email なし（LINE のみユーザー）は自動除外 |
| メール形式 | HTML + テキスト multipart/alternative |
| deep_link_url | `/weekly_reflections/new`（振り返り入力ページへ直接遷移） |

<br>

#### メール内容

<br>

| セクション | 内容 |
|:---|:---|
| 先週の振り返り | `direct_reason` / `background_situation` / `next_action` / `reflection_comment` / `mood`（気分スコア） |
| 習慣達成状況 | チェック型習慣の達成率（完了数 / 目標日数・達成率%・3色カラー表示） |
| CTA ボタン | 「今週の振り返りを記録する」→ `/weekly_reflections/new` へ遷移 |
| 未提出の場合 | 振り返り未完了のメッセージを表示 |
| 習慣なしの場合 | 習慣未登録のメッセージを表示 |

<br>

#### 習慣達成率カラー（`achievement_color`）

<br>

| 達成率 | 色 | 意味 |
|:---:|:---|:---|
| 80%以上 | 🟢 緑 | 達成 |
| 50%以上 | 🔵 青 | まずまず |
| 50%未満 | 🔴 赤 | 要改善 |

<br>

#### GoodJob cron 設定

<br>

| 項目 | 内容 |
|:---|:---|
| cron 式 | `"0 0 * * 1"`（UTC 00:00 毎週月曜 = JST 09:00） |
| cron キー名 | `weekly_report_mail`（重複実行防止のため一意の名前を使用） |
| Job クラス | `WeeklyReportJob` |

<br>

#### 設計上の重要判断

<br>

**① `deliver_now` を使う理由**<br>
`WeeklyReportJob` 自体がすでに GoodJob の非同期ジョブとして実行されているため、<br>
内部で `deliver_later` を使うと「ジョブの中でジョブを登録する」二重構造になってしまう。<br>
`deliver_now` で同期送信することでシンプルな処理フローを維持する。

<br>

**② ループ内 `begin ~ rescue` で1ユーザーの失敗を他に影響させない**<br>
1人のユーザーへのメール送信が失敗しても残りのユーザーへの送信を継続できるよう、<br>
`rescue` をループ「内側」に配置する。ループの外側に置くと1人失敗で全員に届かなくなる。

<br>

**③ チェック型習慣のみを対象にする理由**<br>
数値型習慣の達成率計算は `weekly_target` との数値比較が必要で複雑になる。<br>
週次レポートメールは簡潔さを優先し、チェック型（`measurement_type: :check_type`）のみを対象にする。

<br>

**④ `measurement_type: :check_type` を使う理由**<br>
`docker compose exec web bin/rails runner "puts Habit.defined_enums.inspect"` で確認した結果、<br>
カラム名は `habit_type` ではなく `measurement_type` が正しい。<br>
enum 値は `check_type: 0` / `numeric_type: 1` で定義されている。

<br>

#### 堅牢性テスト（stub を使った1ユーザー失敗テスト）

<br>

`WeeklyReportMailer.stub` で特定ユーザーのメール生成時に強制例外を発生させ、<br>
他ユーザーへの送信が継続されることを確認するテストを実装した。<br>
Minitest の `stub` はブロックを抜けると自動で元のメソッドに戻るため、他テストへの影響がない。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/jobs/weekly_report_job.rb` | 新規作成（GoodJob cron 実行・ユーザー絞り込み・達成率計算・エラー分離） |
| `app/mailers/weekly_report_mailer.rb` | 新規作成（`helper :application` 明示・`new_weekly_reflection_url` で deep_link_url 生成） |
| `app/views/weekly_report_mailer/report.html.erb` | 新規作成（インラインスタイル・3色カラー・CTA ボタン） |
| `app/views/weekly_report_mailer/report.text.erb` | 新規作成（HTML 非対応クライアント向けプレーンテキスト版） |
| `app/helpers/application_helper.rb` | `achievement_color` メソッドを追加（メール用3段階カラー判定） |
| `config/initializers/good_job.rb` | `weekly_report_mail` cron エントリを追加（`cleanup_finished_jobs` 末尾にカンマを追加） |
| `test/mailers/weekly_report_mailer_test.rb` | 新規作成（3件：振り返りあり・なし・習慣なし） |
| `test/jobs/weekly_report_job_test.rb` | 新規作成（4件：送信確認・無効ユーザー除外・退会ユーザー除外・堅牢性） |
| `test/mailers/previews/weekly_report_mailer_preview.rb` | 新規作成（3色カラー確認用ダミーデータ付きプレビュー） |

<br>

#### テスト結果

<br>

```
G-2テスト: Mailer 3件・Job 4件（合計7件）
全テスト:  667 runs, 1654 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### 動作確認済み項目

<br>

| 項目 | 確認内容 |
|:---|:---|
| letter_opener | `WeeklyReportMailer.report(user, reflection, habit_stats).deliver_now` でメール受信を確認 |
| HTML 版 | グラデーションヘッダー・振り返り内容・習慣達成率（緑・青・赤）・CTAボタンが正しく表示 |
| テキスト版 | `View as plain-text email` で全項目が正しく出力されることを確認 |
| deep_link_url | ボタンの href が `https://localhost:3000/weekly_reflections/new` であることを確認 |
| ジョブ実行 | `WeeklyReportJob.new.perform` で2ユーザーに送信成功（`成功=2, 失敗=0`） |
| 振り返り未提出 | 「先週の振り返りはまだ提出されていません」が正しく表示 |
| 習慣未登録 | 「習慣がまだ登録されていません」が正しく表示 |

### #G-3: 通知設定ページ（21番）

<br>

**ブランチ:** `feature/g3-notification-settings`<br>
**完了日:** 2026-06-02<br>
**概要:** `user_settings` テーブルを使った通知設定ページを実装。<br>
LINE通知・メール通知・週次レポートの ON/OFF トグルスイッチ（4種）と<br>
1日の最大通知数スライダー（Stimulusリアルタイム更新）を提供する。<br>
LINE未連携時は連携案内バナーとボタンを表示する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Route | `resource :settings` に `member do get :notification_settings / patch :update_notification_settings end` を追加<br>`path: "notification_settings"` 指定で GET・PATCH を同一 URL に統一 |
| Controller | `UserSettingsController` を新規作成（`notification_settings` / `update_notification_settings`）<br>`before_action :require_login` で全アクション認証必須<br>保存後 `status: :see_other` で 303 リダイレクト（Turboフラッシュ表示対応） |
| View | `notification_settings.html.erb` を新規作成（21番画面）<br>セクション1: 通知全体マスタスイッチ<br>セクション2: LINE通知・メール通知・週次レポートのチャンネル設定<br>セクション3: 1日の最大通知数スライダー（`notification-limit` Stimulusコントローラー接続） |
| View | `settings/show.html.erb` に通知設定リンクカードを追加（LINE連携状況バッジ付き） |
| JS | `notification_limit_controller.js` を新規作成（スライダーのリアルタイム値表示） |
| i18n | `ja.yml` に `user_settings.notification_settings.update_success` メッセージを追加 |
| Test | `test/controllers/user_settings_controller_test.rb` を新規作成（8 runs, 24 assertions） |

<br>

#### 解決した主要な技術的問題

<br>

**① PATCH ルートの URL 統一（`path:` 指定）**

<br>

`patch :update_notification_settings` だけだと URL が `/settings/update_notification_settings` になる。<br>
`path: "notification_settings"` を追加することで GET と同一の `/settings/notification_settings` に統一できる。<br>

```ruby
resource :settings, only: %i[show destroy] do
  member do
    get   :notification_settings,
          to: "user_settings#notification_settings"
    patch :update_notification_settings,
          to:   "user_settings#update_notification_settings",
          path: "notification_settings"  # ← これがないと URL が別になる
  end
end
```

<br>

**② Tailwind v4 の `peer-checked:` は `span` には効かない**

<br>

Tailwind v4 では `peer-checked:` は `.peer` クラスの直接隣接する兄弟要素（`~*` CSS セレクター）にのみ適用される。<br>
`span` の中に `peer-checked:translate-x-5` を書いても、`span` は `peer` の直接兄弟ではないため効かない。<br>
解決策: `span` を `label` に統合し、`label` に直接 `peer-checked:bg-blue-600` 等のクラスを付与する。<br>

```html


    
  





```

<br>

**③ Turbo フォーム送信後のフラッシュ表示問題**

<br>

Turbo が有効なフォームで `redirect_to` すると、フラッシュメッセージが次のリクエストで表示されない問題がある。<br>
`data: { turbo: false }` でフォームを通常の HTML フォーム送信に変更し、<br>
`status: :see_other`（303）を明示することで Turbo との競合を解消した。

<br>

**④ LINE 連携ボタンのフォームネスト問題**

<br>

`button_to` は `<form>` を生成するため、メインフォームの内側にネストできない（HTML 仕様違反）。<br>
`<button form="line-connect-form">` でフォームの外側の別フォームと紐付け、<br>
ページ末尾に `id="line-connect-form"` の hidden フォームを配置することで解決した。

<br>

**⑤ Turbo キャッシュ問題の解消**

<br>

`data-turbo="false"` のフォームを含むページでは、Turbo のキャッシュにより<br>
「戻る」操作後にフォームの状態が正しく復元されない問題が発生する。<br>
`content_for :head` で `<meta name="turbo-cache-control" content="no-cache">` を出力し、<br>
`application.html.erb` の `<title>` 直後に `<%= yield :head %>` を追加することで解消した。

<br>

#### 生成ルート

<br>

| パスヘルパー | HTTP | URL |
|:---|:---|:---|
| `notification_settings_settings_path` | GET | `/settings/notification_settings` |
| `update_notification_settings_settings_path` | PATCH | `/settings/notification_settings` |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `config/routes.rb` | `notification_settings` / `update_notification_settings` を member ブロックに追加（`path:` 指定で URL 統一） |
| `app/controllers/user_settings_controller.rb` | 新規作成（`notification_settings` / `update_notification_settings` アクション・`notification_settings_params`） |
| `app/views/user_settings/notification_settings.html.erb` | 新規作成（21番画面・Tailwind v4 対応トグル4種・スライダー・LINE連携ボタン） |
| `app/views/settings/show.html.erb` | 通知設定リンクカードを追加（LINE連携状況バッジ付き） |
| `app/views/layouts/application.html.erb` | `<title>` 直後に `<%= yield :head %>` を追加 |
| `app/javascript/controllers/notification_limit_controller.js` | 新規作成（スライダーリアルタイム値表示） |
| `app/javascript/controllers/index.js` | `stimulus:manifest:update` で `NotificationLimitController` を自動登録 |
| `config/locales/ja.yml` | `user_settings.notification_settings.update_success` / `update_failure` を追加 |
| `test/controllers/user_settings_controller_test.rb` | 新規作成（8 runs, 24 assertions） |

<br>

#### テスト結果

<br>

```
G-3テスト: 8 runs, 24 assertions, 0 failures, 0 errors, 0 skips
全テスト:  675 runs, 1678 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### 動作確認済み項目

<br>

| 項目 | 確認内容 |
|:---|:---|
| トグルスイッチ4種 | クリックで ON/OFF が切り替わる |
| スライダー | ドラッグ中にリアルタイムで「N件」が更新される |
| 保存 | トースト「通知設定を保存しました ✅」が表示される |
| リロード後 | 設定が保持されている |
| 未ログイン | ログインページへリダイレクトされる |
| LINE 未連携 | 連携案内バナーと「LINE でログイン・連携する」ボタンが表示される |

<br>

### #G-4: お休みモード設定ページ（22番）・ストリーク維持

<br>

**ブランチ:** `feature/g4-rest-mode`<br>
**完了日:** 2026-06-06<br>
**概要:** 旅行・病気・繁忙期などでお休みを設定すると、`allow_rest_mode=true` の習慣のストリークが維持される機能を実装。<br>
設定ページ（22番）・M-3 確認モーダル（デスクトップ中央モーダル/スマホボトムシート）・<br>
`RestModeExpiryJob`（毎日 JST AM4:10 自動解除）・ダッシュボードへのバナー表示を実装。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Route | `resource :settings` の `member` ブロックに `rest_mode`（GET）/ `start_rest_mode`（POST）/ `stop_rest_mode`（DELETE）を追加 |
| Controller | `UserSettingsController` に `rest_mode` / `start_rest_mode` / `stop_rest_mode` アクションを追加<br>`rest_mode_until` のバリデーション（空・過去日付は 422）・303 See Other リダイレクト |
| Model | `UserSetting` の `rest_mode_until` / `rest_mode_reason` カラムを利用（#A-1 で追加済み）<br>`rest_mode_active?` メソッドで現在のお休みモード状態を判定 |
| Job | `RestModeExpiryJob` を新規作成（毎日 JST AM4:10・期限切れを `update_all` で一括解除） |
| GoodJob cron | `good_job.rb` に `rest_mode_expiry` cron エントリを追加（UTC `"10 19 * * *"` = JST AM4:10） |
| View | `app/views/user_settings/rest_mode.html.erb` を新規作成（22番画面）<br>フォーム・🎤音声入力ボタン・習慣一覧（allow_rest_mode 状態バッジ付き） |
| View | M-3 確認モーダル: デスクトップ（中央オーバーレイ）/ スマホ（ボトムシート）<br>入力日付・理由をモーダル内の確認欄にリアルタイム反映 |
| View | `dashboards/index.html.erb` にお休みモードバナー（`data-testid="rest-mode-dashboard-banner"`）と<br>習慣行に「😴 休息中」バッジ（`data-testid="rest-mode-habit-badge-#{habit.id}"`）を追加 |
| View | `settings/show.html.erb` にお休みモード設定へのナビゲーションカードを追加 |
| JS | `rest_mode_modal_controller.js` を新規作成（Stimulus コントローラー）<br>content_for :modals でスコープ外に出るボタンを `_setupModalListeners()` + `addEventListener` で制御<br>`_listenersAttached` フラグで二重登録を防止 |
| i18n | `ja.yml` に `user_settings.rest_mode.*` メッセージを追加（started/stopped/invalid_date/stop_button/stop_confirm） |
| Test | `test/controllers/user_settings_rest_mode_test.rb` を新規作成（13 runs, 30 assertions）<br>`test/jobs/rest_mode_expiry_job_test.rb` を新規作成（Job テストを分離） |

<br>

#### 技術的なポイント

<br>

**① `form_with url:` + `scope: :user_setting` でパラメータ名を統一する**

<br>

`form_with url: start_rest_mode_settings_path` に `scope: :user_setting` を追加しないと<br>
`f.date_field :rest_mode_until` が `rest_mode_until=...` として送信され、<br>
コントローラーの `params[:user_setting][:rest_mode_until]` が nil になりバリデーションエラーになる。<br>
`scope: :user_setting` を指定することで `user_setting[rest_mode_until]=...` として送信される。

<br>

**② content_for :modals のスコープ外ボタンは addEventListener で制御する**

<br>

モーダル内のボタン（「開始する」「キャンセル」「×」）は `content_for :modals` で<br>
`</body>` 直前に出力されるため、`data-controller="rest-mode-modal"` のスコープ外に出る。<br>
`data-action="click->rest-mode-modal#submitForm"` は Stimulus から見えないため無効。<br>
`openModal()` の初回呼び出し時に `_setupModalListeners()` で `addEventListener` を直接登録する<br>（B-5/C-3 と同じ設計パターン）。<br>
各ボタンに `id="rest-mode-submit-btn"` 等を付与し `document.getElementById()` で取得する。

<br>

**③ オーバーレイクリックはバブリングを考慮して `event.target` を照合する**

<br>

`#rest-mode-modal` はモーダル全体を囲む外枠のため、<br>
パネル内クリックもバブリングで外枠まで伝播してくる。<br>
`closeFromOverlay(event)` 内で `event.target === overlay` の場合のみ閉じる設計にし、<br>
パネル内クリックで誤ってモーダルが閉じないようにする。

<br>

**④ ストリーク計算との連携（#B-3 実装済み）**

<br>

`Habit#rest_mode_on_date?(date)` が `rest_mode_until.to_date >= date` で日付単位に判定し、<br>
`Habit#calculate_streak!` がその日の未達成を「お休みモード中」としてスキップする。<br>
`allow_rest_mode=true` の習慣のみが対象（`allow_rest_mode=false` はストリーク保護対象外）。

<br>

#### 生成ルート

<br>

| パスヘルパー | HTTP | URL |
|:---|:---|:---|
| `rest_mode_settings_path` | GET | `/settings/rest_mode` |
| `start_rest_mode_settings_path` | POST | `/settings/rest_mode` |
| `stop_rest_mode_settings_path` | DELETE | `/settings/rest_mode` |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `config/routes.rb` | `rest_mode` / `start_rest_mode` / `stop_rest_mode` を member ブロックに追加 |
| `app/controllers/user_settings_controller.rb` | `rest_mode` / `start_rest_mode` / `stop_rest_mode` アクションを追加 |
| `app/jobs/rest_mode_expiry_job.rb` | 新規作成（毎日 AM4:10 自動解除・`update_all` で一括処理） |
| `config/initializers/good_job.rb` | `rest_mode_expiry` cron エントリを追加 |
| `app/views/user_settings/rest_mode.html.erb` | 新規作成（22番画面・フォーム・習慣一覧・M-3 モーダル） |
| `app/views/dashboards/index.html.erb` | お休みモードバナーと「😴 休息中」バッジを追加 |
| `app/views/settings/show.html.erb` | お休みモード設定へのナビゲーションカードを追加 |
| `app/javascript/controllers/rest_mode_modal_controller.js` | 新規作成（`_setupModalListeners` + `addEventListener` 方式） |
| `app/javascript/controllers/index.js` | `RestModeModalController` を手動登録 |
| `config/locales/ja.yml` | `user_settings.rest_mode.*` メッセージを追加 |
| `app/controllers/dashboards_controller.rb` | `@user_setting = current_user.user_setting` を追加（N+1防止） |
| `app/controllers/settings_controller.rb` | `@user_setting = current_user.user_setting` を追加 |
| `test/controllers/user_settings_rest_mode_test.rb` | 新規作成（13 runs, 30 assertions） |
| `test/jobs/rest_mode_expiry_job_test.rb` | 新規作成（Job テスト分離） |

<br>

#### テスト結果

<br>

```
G-4テスト: 13 runs, 30 assertions, 0 failures, 0 errors, 0 skips
全テスト:  691 runs, 1714 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### 動作確認済み項目

<br>

| 項目 | 確認内容 |
|:---|:---|
| お休みモード設定ページ | `/settings` → お休みモードセクションが通知設定の下に表示される |
| フォーム表示 | `/settings/rest_mode` → フォーム・🎤ボタン・習慣一覧が表示される |
| モーダル | 終了日選択 → モーダルが開き日付が確認欄に反映される |
| 開始 | 「開始する」→ POST 303 → フラッシュメッセージ「お休みモードを開始しました（〜YYYY年M月D日）😴」 |
| ダッシュボード | お休みモードバナーと「😴 休息中」バッジが表示される |
| 終了 | 「お休みモードを終了する」→ 確認ダイアログ → 解除 → バナー消去 |

<br>

### #G-5: CSVエクスポート機能

<br>

**ブランチ:** `feature/G-5-csv-export`<br>
**完了日:** 2026-06-07<br>
**概要:** 設定ページから習慣記録・タスク・週次振り返りのデータをCSV形式でダウンロードできる機能を実装。<br>
1,000件以下は即時ダウンロード、1,000件超はGoodJobでバックグラウンド生成しメールで通知する。<br>
Excelで文字化けなく開けるUTF-8 BOM付きCSVとして出力する。

<br>

#### 技術構成

<br>

| 項目 | 内容 |
|:---|:---|
| 即時ダウンロード | 1,000件以下は `send_data` で直接CSVをダウンロード |
| バックグラウンド処理 | 1,000件超はGoodJobで非同期生成 → Resendでメール通知 |
| ダウンロードURL | `MessageVerifier` による署名付きトークン（即時5分/非同期24時間） |
| 文字コード | UTF-8 BOM付き（Excelでの文字化け防止） |
| 改行コード | CRLF（`\r\n`）形式でExcel互換 |

<br>

#### エクスポート対象

<br>

| 種別 | ファイル名例 | 主なカラム |
|:---|:---|:---|
| 習慣記録 | `habitflow_habit_records_20260607_120000.csv` | 記録日・習慣名・記録タイプ・完了・数値・単位・メモ |
| タスク | `habitflow_tasks_20260607_120000.csv` | タスク名・優先度・種別・ステータス・期限日・完了日時 |
| 週次振り返り | `habitflow_weekly_reflections_20260607_120000.csv` | 振り返り週・気分スコア・なぜ？・どう？・からの？ |

<br>

#### Turbo + send_data の競合解決

<br>

Turbo が有効な状態で `send_data` を返すとTurboがバイナリをインターセプトしファイルが届かない問題が発生する。<br>
解決策として **View側で件数を判定し、1,000件以下のボタンに `data-turbo="false"` を付与**する設計を採用。<br>
`data-turbo="false"` ボタンはTurboを経由しない通常HTMLリクエストになるため、<br>
コントローラーの303リダイレクト → `download` アクションの `send_data` がブラウザに正しく届く。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/services/csv_export_service.rb` | 新規作成（CSV生成・件数取得・ファイル名生成） |
| `app/services/csv_download_token_service.rb` | 新規作成（署名付きトークン生成・検証） |
| `app/jobs/csv_export_job.rb` | 新規作成（非同期CSV生成・メール通知） |
| `app/mailers/csv_export_mailer.rb` | 新規作成（CSV生成完了メール） |
| `app/views/csv_export_mailer/ready.html.erb` | 新規作成（HTMLメール本文） |
| `app/views/csv_export_mailer/ready.text.erb` | 新規作成（テキストメール本文） |
| `app/controllers/csv_exports_controller.rb` | 新規作成（エクスポート・ダウンロードアクション） |
| `app/helpers/settings_helper.rb` | 追記（`export_path_for` ヘルパー） |
| `app/views/settings/_csv_export_button.html.erb` | 新規作成（件数判定・data-turbo切替ボタン） |
| `app/views/settings/show.html.erb` | 追記（CSVエクスポートセクション） |
| `app/controllers/settings_controller.rb` | 追記（CSV件数取得・重複定義を整理） |
| `config/routes.rb` | 追記（CSVエクスポート3ルート・ダウンロードルート） |
| `config/locales/ja.yml` | 追記（`csv_exports` 関連メッセージ） |
| `test/services/csv_export_service_test.rb` | 新規作成（16件） |
| `test/services/csv_download_token_service_test.rb` | 新規作成 |
| `test/controllers/csv_exports_controller_test.rb` | 新規作成（10件） |

<br>

#### テスト結果

<br>

```
G-5テスト: 10 runs, 39 assertions, 0 failures, 0 errors, 0 skips
全テスト:  717 runs, 1785 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### 動作確認済み項目

<br>

| 項目 | 確認内容 |
|:---|:---|
| 習慣記録CSV | ダウンロード成功・Excelで文字化けなし |
| タスクCSV | ダウンロード成功・優先度・ステータスが日本語で出力 |
| 週次振り返りCSV | ダウンロード成功・気分スコア・全振り返り項目が出力 |
| バックグラウンド処理 | 「⏳ 生成中...」ボタン表示・letter_openerでメール確認 |
| メール内リンク | 24時間有効トークン・クリックでCSVダウンロード成功 |

<br>

### #G-6: 設定ページ拡張 + #G-3通知設定修正

<br>

**ブランチ:** `feature/g6-settings-page-expansion`<br>
**完了日:** 2026-06-10<br>
**概要:** 設定ページ（23番）にインラインプロフィール編集・ソーシャルアカウント連携管理・タイムゾーン設定・AI使用状況表示を追加。<br>
あわせてG-3で発見された通知設定の不具合（マスタースイッチ連動・独立制御・フォールバック廃止・週次レポート制御）を修正した。

<br>

#### G-6: 設定ページ拡張

<br>

| カテゴリ | 内容 |
|:---|:---|
| Route | `update_profile`（PATCH path: "profile"）/ `update_timezone`（PATCH path: "timezone"）/ `disconnect_line`（DELETE path: "line"）を member に追加 |
| Controller | `SettingsController#show`: `@line_connected` / `@current_timezone` / `@ai_analysis_count` / `@ai_analysis_monthly_limit` / `@ai_usage_rate` をアサイン |
| Controller | `update_profile`: `params.require(:user).permit(:name)` で名前を保存・失敗時は alert + redirect |
| Controller | `update_timezone`: `ActiveSupport::TimeZone[]` ホワイトリストチェック |
| Controller | `disconnect_line`: `provider == "line_v2_1"` ガード・`line_user_id` を nil に更新 |
| Model | `User#line_connected?`: `provider == "line_v2_1" \|\| line_user_id.present?` |
| Model | `validates :password` に `on: :create` を追加（更新時のバリデーション誤発動防止） |
| JS | `settings_profile_controller.js` 新規作成（インライン編集のopen/close・他セクションのopacity制御・voice input連携） |
| View | `settings/show.html.erb` をプロフィール編集・LINE連携・タイムゾーン・AI使用状況・CSVエクスポート・退会セクションで再構成 |
| View | LINEセクション: ログイン連携専用（Googleセクションは削除・Google通知APIは技術的に不可のため） |
| View | LINE/Google連携ボタンを `link_to(GET)` → `button_to(POST)` + `form: { class: "inline" }` に変更（OmniAuth 2.x GET拒否対応） |
| Test | `test/controllers/settings_controller_g6_test.rb` 新規作成（update_profile・update_timezone・disconnect_line 各正常/異常系） |

<br>

#### G-3 修正（G-6テスト中に発見した通知設定の不具合）

<br>

| カテゴリ | 内容 |
|:---|:---|
| JS | `notification_master_controller.js` 新規作成（マスタースイッチOFF時に通知チャネルをグレーアウト・`pointer-events-none`・`disabled` 非使用でフォーム値を保持） |
| JS | `index.js` に `notification-master` コントローラーを登録 |
| View | `notification_settings.html.erb` にマスタースイッチ連動の `data` 属性を追加（`notification-master-target="master/channel"`・`change->notification-master#toggle`） |
| Service | `NotificationService#use_line?` / `use_email?` に `notification_enabled?` チェックを追加（防御的実装） |
| Service | `NotificationService` を独立制御に変更（`if-elsif` → `if-if`）<br>LINE通知とメール通知が独立したON/OFFスイッチのため両方ONなら両方送信 |
| Service | LINE送信失敗時のメールフォールバックを廃止<br>LINE失敗はLINE失敗として記録・メールはメール設定に従って独立判断 |
| Job | `WeeklyReportJob` の対象ユーザー絞り込みに `notification_enabled: true` を追加（マスタースイッチOFF時は週次レポートも送信しない） |
| View | `notification_settings.html.erb` に LINE通知連携解除ボタンを追加<br>LINE連携済み時は解除ボタン・未連携時は連携ボタンを表示 |
| View | `line-disconnect-form` 隠しフォームを追加（メインフォームのフォームネスト回避） |
| Test | `test/services/notification_service_test.rb` を独立制御設計に合わせて更新（LINE失敗→メールフォールバックしないことを確認） |

<br>

#### 動作確認済み項目

<br>

| 項目 | 確認内容 |
|:---|:---|
| プロフィール編集 | インライン編集で名前を変更・保存・他セクションがグレーアウト |
| LINE連携管理 | ログイン連携状況の表示・disconnect_line で line_user_id をクリア |
| タイムゾーン設定 | セレクトボックスで変更・保存後に反映 |
| AI使用状況 | 今月の使用回数・上限・プログレスバーを表示 |
| 通知全般マスタースイッチ | OFFで通知チャネルがグレーアウト・操作不可（値は保持） |
| アラーム通知 6パターン | 通知全般OFF・LINE通知ON/OFF・LINE連携有無・メール通知ON/OFF の全組み合わせ |
| 週次レポート 3パターン | 通知全般ON/OFF × weekly_report_enabled ON/OFF |
| 通知制限 3パターン | 上限未達→送信・上限到達→スキップ・上限1件→1件後スキップ |
| LINE通知連携解除 | 通知設定ページからLINE通知連携を解除できる |

<br>

### #G-7: AI分析完了時のダッシュボードリアルタイム通知バナー

<br>

**ブランチ:** `feature/g7-dashboard-completion-banner`<br>
**完了日:** 2026-06-13<br>
**概要:** PMVV目標分析・振り返りAI分析の完了時に、ダッシュボードを開いているユーザーへ<br>
Turbo Stream でリアルタイム通知バナーを表示する機能を実装。<br>
GoodJobのバックグラウンドジョブから `broadcast_replace_to` で配信し、<br>
`dismissible_controller.js` による × 閉じ機能を提供する。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Job | `PurposeAnalysisJob` に `broadcast_dashboard_completion` メソッドを追加<br>completed 時のみ `dashboard_notifications_#{user_id}` ストリームにブロードキャスト |
| Job | `WeeklyReflectionAnalysisJob` に `broadcast_dashboard_completion` を追加<br>ターゲット `dashboard_reflection_completion_banner` へ配信 |
| View | `dashboards/_pmvv_completion_banner.html.erb` を新規作成（緑系・✨・`ai_result_user_purpose_path` リンク） |
| View | `dashboards/_reflection_completion_banner.html.erb` を新規作成（青系・🔄・`weekly_reflection_path` リンク） |
| View | `dashboards/index.html.erb` を修正<br>- `turbo_stream_from` を `@current_purpose` の if ブロック外に移動<br>- 空の `dashboard_pmvv_completion_banner` / `dashboard_reflection_completion_banner` div を追加<br>- completed 時は `analysis_status_banner` の中身を非表示（バナー重複解消） |
| JS | `dismissible_controller.js` を新規作成（× ボタンでバナーを閉じる・`connect()` で hidden リセット対応） |
| JS | `index.js` に `dismissible` コントローラーを手動登録 |
| Test | `purpose_analysis_job_test.rb` に G-7 テスト3件を追加 |
| Test | `weekly_reflection_analysis_job_test.rb` に G-7 テスト2件を追加 |

<br>

#### バナー仕様

<br>

| バナー | ターゲット ID | 色 | アイコン | 遷移先 |
|:---|:---|:---|:---|:---|
| PMVV目標分析完了 | `dashboard_pmvv_completion_banner` | 緑系 | ✨ | `ai_result_user_purpose_path` |
| 振り返りAI分析完了 | `dashboard_reflection_completion_banner` | 青系 | 🔄 | `weekly_reflection_path(reflection)` |

<br>

#### 設計上の重要ポイント

<br>

**① `turbo_stream_from` は `@current_purpose` の if ブロック外に置く**

<br>

`@current_purpose` が nil（未入力ユーザー）の場合でも振り返りAI分析バナーを受信するため、<br>
`turbo_stream_from "dashboard_notifications_#{current_user.id}"` を<br>
`@current_purpose` の if ブロック外に配置する。<br>
ブロック内に置くと PMVV 未設定ユーザーはチャンネルを購読できずバナーが届かない。

<br>

**② completed 時の analysis_status_banner は中身を非表示にする**

<br>

`analysis_status_banner`（PMVV完了バナー）と `dashboard_pmvv_completion_banner` が<br>
同時に表示されるバナー重複を防ぐため、completed 状態では<br>
`analysis_status_banner` の中身を ERB の条件分岐で非表示にする。

<br>

**③ パーシャルの最外殻 div には id を付けない**

<br>

`broadcast_replace_to` のターゲット id（`dashboard_pmvv_completion_banner`）は<br>
ダッシュボードの空 div が持つ。パーシャルの最外殻 div に同名 id を付けると<br>
Turbo Stream 差し替え後に id が二重になりバグの原因になる。

<br>

**④ dismissible_controller.js の connect() で hidden をリセット**

<br>

Turbo によってパーシャルが差し替えられた際、コントローラーの `connect()` が再度呼ばれる。<br>
`connect()` で `element.removeAttribute("hidden")` を実行することで<br>
以前 × で閉じていたバナーでも再配信時に正しく表示される。

<br>

### #G-8: AI分析カウント月次リセットバッチ（テスト追加）

<br>

**ブランチ:** `feature/G-8-monthly-ai-count-reset-test`<br>
**完了日:** 2026-06-13<br>
**概要:** 毎月1日 JST 00:00 に全ユーザーの `user_settings.ai_analysis_count` を 0 にリセットする<br>
`MonthlyAiCountResetJob` のテストファイルを新規作成。<br>
ジョブ本体・GoodJob cron 登録は #A-3 で実装済みのため、テストのみを追加。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Test | `test/jobs/monthly_ai_count_reset_job_test.rb` を新規作成（7テスト・15アサーション） |
| Test | `travel_to` で月初/月初以外/月末の境界値を検証 |
| Test | `to_s` でcronキーをSymbol/String両対応にして安全に比較 |
| Test | `UserSetting.where(id: @test_user_setting_ids).maximum(:ai_analysis_count)` で全件SQL確認 |
| Test | 14-Bモーダルの表示条件解消を間接確認 |

<br>

#### テスト設計のポイント

<br>

| 設計 | 理由 |
|:---|:---|
| `teardown` で `destroy` しない | `use_transactional_tests` で自動ロールバックされるため不要 |
| `cron_config.keys.map(&:to_s)` で比較 | GoodJobの設定キーはSymbol/Stringどちらの場合もあるため文字列に統一して比較 |
| `@test_user_setting_ids` で絞り込み | `fixtures(:all)` の他ユーザーのai_analysis_countと干渉しないよう対象を限定 |
| `update_all` 後に `.reload` | `update_all` はSQL直接発行のためRubyオブジェクトのキャッシュを更新しない |
| コンソールでの月初シミュレートは `update_all` で代替 | `travel_to` はコンソールで使用不可のため、ジョブの核心処理を直接実行して確認 |

<br>

#### cron 設定（#A-3 で実装済み）

<br>

| 設定 | 内容 |
|:---|:---|
| cron キー | `monthly_ai_count_reset` |
| cron 式 | `"0 15 * * *"`（毎日 UTC 15:00 = JST 00:00） |
| ジョブクラス | `MonthlyAiCountResetJob` |
| 月初判定 | ジョブ内で `Time.current.day == 1` をチェック（毎日起動・月初のみリセット） |

<br>

#### 動作確認済み項目

<br>

| 項目 | 確認内容 |
|:---|:---|
| GoodJob管理画面 | `/good_job` → `monthly_ai_count_reset` が `MonthlyAiCountResetJob / 0 15 * * *` で Active 表示 |
| 設定ページ | `/settings` → AI使用状況「0 / 10 回」が正しく表示 |
| 月初以外スキップ | `MonthlyAiCountResetJob.perform_now` → 「今日は月初ではないためスキップ（YYYY-MM-DD）」ログ出力 |
| リセット処理 | `UserSetting.update_all(ai_analysis_count: 0)` → リセット件数: N件・全件0確認 |

<br>

### #G-9: 週次振り返りAI提案拡張（habit_modify / habit_delete / task_modify / goal_review）

<br>

**ブランチ:** `feature/g-9-weekly-reflection-ai-proposal-extension`<br>
**完了日:** 2026-06-14<br>
**概要:** 週次振り返りAI分析ジョブのプロンプトを v2.0 に拡張し、4種のアクションタイプ（habit_modify / habit_delete / task_modify / goal_review）によるAI提案を実装。<br>
振り返り詳細ページにAI提案確認ボタンを追加し、モーダルから習慣・タスクの修正を確定できるようにした。<br>
あわせてダッシュボード・PMVVページのTurbo Streamバナー二重表示バグを修正した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Job | `WeeklyReflectionAnalysisJob`: `PROMPT_VERSION` を `"v2.0"` に更新・`VALID_ACTION_TYPES` 定数をクラスレベルに追加（メソッド内定数はSyntaxError）・`maxOutputTokens: 8192`（4096→拡張でレスポンス途中切れ対応）・`goal_review` のJSON スキーマを固定キー形式（`purpose_suggestion` 等5項目）に変更 |
| Service | `AiClient`: `maxOutputTokens: 8192`（Gemini 207行目）・`max_tokens: 8192`（Groq 254行目）に更新 |
| Controller | `WeeklyReflectionsController#confirm_proposals`: `habit_modify_indices` / `habit_delete_indices` / `task_modify_indices` / `goal_review_requested` を処理・habit_modify は `weekly_target` を `clamp(1,7)` でホワイトリスト更新・habit_delete は `soft_delete`・task_modify は `priority` のみ更新・goal_review は DB変更なし `user_purpose_path` へリダイレクト |
| Controller | `WeeklyReflectionsController#show`: `@current_purpose = UserPurpose.current_for(current_user)` を追加（goal_review セクション表示用） |
| View | `_ai_proposal_modal_content.html.erb`: habit_modify / habit_delete / task_modify / goal_review の4セクションを追加・`whitespace-pre-wrap` + 同一行記述で段落ずれ修正・goal_review チェックボックスを `each_with_index` ブロック内に移動（構文エラー修正）・固定キー形式の5項目改善案表示 |
| View | `weekly_reflections/show.html.erb`: AI免責バナー直後に「✨ 来週のAI提案を確認する →」ボタンを追加・`_ai_proposal_modal` パーシャルを render・`window.dispatchEvent(new CustomEvent('open-ai-proposal-modal'))` でモーダル直接起動 |
| View | `user_purposes/ai_result.html.erb`: `whitespace-pre-wrap` + 同一行記述で段落ずれ修正 |
| View | `dashboards/index.html.erb`: `turbo_stream_from` を `@current_purpose` の if ブロック外に移動・completed 時の `analysis_status_banner` 中身を非表示（バナー重複解消）・振り返り分析中バナー3状態分岐を追加 |
| View | `dashboards/_pmvv_completion_banner.html.erb`: 完了時刻表示を追加（`l completed_at, format: :long`） |
| Fix | ダッシュボードとPMVVページのTurbo Streamストリームを分離（`dashboard_user_purpose_#{id}` に変更） |
| Fix | `purpose_analysis_job.rb` の `broadcast_state_update` 重複定義（533行目付近）を削除し1つに統合 |
| Fix | `dashboards_controller.rb`: 振り返りAI分析中バナー用の変数追加（`@latest_completed_reflection` / `@reflection_ai_analysis` / `@reflection_analysis_pending`） |
| Test | `weekly_reflection_analysis_job_test.rb` に G-9 テスト5件追加（PROMPT_VERSION / build_prompt習慣・タスク一覧 / 空配列 / build_input_snapshot） |
| Test | `weekly_reflections_controller_test.rb` に G-9 テスト3件追加（task_modify優先度更新 / 存在しないタスクスキップ / goal_review→user_purpose_pathリダイレクト） |

<br>

#### バグ修正一覧

<br>

| バグ | 原因 | 修正 |
|:---|:---|:---|
| `VALID_ACTION_TYPES` SyntaxError | メソッド内定数定義 | クラスレベルに移動 |
| AIレスポンス途中切れ（318文字） | maxOutputTokens:4096 不足 | 8192 に増加 |
| 段落ずれ | whitespace-pre-wrap + ERBインデント | タグと内容を同一行に記述 |
| goal_review 構文エラー | each ブロック外で `idx` を参照 | ブロック内にチェックボックス移動 |
| ダッシュボードバナー二重表示 | 同一Turbo Streamストリーム | `dashboard_user_purpose_#{id}` に分離 |
| 「AIが分析しています」が消えない | `broadcast_state_update` 重複定義（旧実装が有効） | 旧実装（533行目）を削除 |
| 分析中バナーが消えない | `exists?` 条件が厳しすぎ | `1.week.ago` 条件に変更 |
| goal_review 5項目表示されない | suggestions配列→固定キー形式 | `purpose_suggestion` 等のキーに統一 |
| PMVVページ「結果を見る」消失 | completed?ブロックを空にした副作用 | ブロック復元+ストリーム分離で解決 |

<br>

#### Turbo Stream ストリーム分離の設計

<br>

| ストリーム名 | 配信先 | 内容 |
|:---|:---|:---|
| `user_purpose_#{id}` | PMVVページ（16番） | 全状態の `analysis_status_banner` パーシャル |
| `dashboard_user_purpose_#{id}` | ダッシュボード | completed 時は空HTML・それ以外はパーシャル |
| `dashboard_notifications_#{user_id}` | ダッシュボード | PMVV完了・振り返りAI完了の通知バナー |

<br>

ダッシュボードとPMVVページが同じストリームを購読していたことで、PMVVページ向けの `completed?` バナー（「AI分析が完了しました」）がダッシュボードにも届き二重表示になっていた。ストリームを完全分離することで解消した。

<br>

#### テスト結果

<br>

```
743 runs, 1861 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #H-1: スマホ Bottom Navigation 実装

<br>

**ブランチ:** `feature/h1-bottom-navigation`<br>
**完了日:** 2026-06-14<br>
**概要:** モバイル（768px未満）でサイドバーを非表示にし、画面下部に5タブの Bottom Navigation を表示。<br>
バッジ表示・iOS SafeArea対応・ja.yml 連携・`bn_ai_analysis_count` による未確認AI分析件数カウントを実装。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| View | `app/views/shared/_bottom_navigation.html.erb` を新規作成（5タブ: ホーム・習慣・タスク・グラフ・設定） |
| View | `fixed bottom-0 md:hidden` でモバイル専用表示・`hidden md:flex` でサイドバーをPC専用に切替 |
| View | `controller_name` でアクティブタブハイライト（設定タブは `settings` / `user_settings` 両対応） |
| View | バッジ: PDCAロック中→ホームに赤「!」点滅 / Must未完了→タスクに赤数字 / AI分析完了（未確認）→グラフに青数字 |
| View | iOS SafeArea対応（`env(safe-area-inset-bottom)`）・`aria-label` / `aria-current` アクセシビリティ対応 |
| View | `app/views/layouts/application.html.erb` の `<main>` に `pb-16 md:pb-0` 追加（BNに隠れない対応） |
| View | `render 'shared/bottom_navigation'` を `yield :modals` 直前に追加 |
| Controller | `application_controller.rb` に `bn_must_incomplete_count` helper_method 追加（Must未完了数・`||=`でメモ化） |
| Controller | `application_controller.rb` に `bn_ai_analysis_count` helper_method 追加（Integer返却・`0` がtruthyのため `?` なし） |
| Model | `user_settings` に `last_analytics_viewed_at datetime` カラムを追加（マイグレーション） |
| Model | `user_setting.rb` に `touch_analytics_viewed_at!` メソッドを追加 |
| Controller | `user_purposes_controller.rb` の `show` でバッジリセット処理を追加（H-4実装後に `AnalyticsController#index` へ移動予定） |
| i18n | `config/locales/ja.yml` に `shared.bottom_navigation` の日本語定義を追加 |

<br>

#### bn_ai_analysis_count の設計

<br>

| カウント対象 | 条件 |
|:---|:---|
| PMVV分析（purpose_breakdown） | `UserPurpose.current_for(user)` が completed かつ `last_analytics_viewed_at` より後に更新 |
| 振り返りAI分析（weekly_reflection） | `last_analytics_viewed_at` より後に作成された `actions_json` が存在する分析 |
| `last_analytics_viewed_at` が nil の場合 | 7日前を基準にする（初回ユーザーの全件表示防止） |

<br>

#### H-4実装時の差し替え箇所

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/views/shared/_bottom_navigation.html.erb` | `user_purpose_path`（暫定）→ `analytics_path` に変更 |
| `app/controllers/user_purposes_controller.rb` の `show` | `touch_analytics_viewed_at!` 呼び出しを削除 |
| `app/controllers/analytics_controller.rb`（新規） | `index` アクションに `touch_analytics_viewed_at!` を追加 |

<br>

#### 動作確認結果

<br>

| 項目 | 結果 |
|:---|:---:|
| 768px未満でBN表示・デスクトップで非表示 | ✅ |
| 5タブ均等配置・高さ64px | ✅ |
| アクティブタブハイライト（controller_name判定） | ✅ |
| コンテンツがBNに隠れない（pb-16 md:pb-0） | ✅ |
| Must未完了タスク赤バッジ | ✅ |
| AI分析完了青バッジ（PMVV+振り返りAI合計件数） | ✅ |
| グラフタブを開いたときバッジリセット | ✅ |
| PDCAロックバッジ（月曜AM4:00以降・仕様通り） | ✅ |
| 日本語表示（ja.yml連携） | ✅ |
| 743 runs, 0 failures, 0 errors | ✅ |

<br>

### #H-2: M-4退会確認モーダルのスマホボトムシート対応

<br>

**ブランチ:** `feature/H-2-bottom-sheet-modal`<br>
**完了日:** 2026-06-14<br>
**概要:** 設定ページの退会確認モーダル（M-4）をスマホ対応のボトムシート形式に変更。<br>
全モーダルの z-index を Bottom Navigation（z-50）より前面に修正し、<br>
フッターがBNに隠れないよう下部余白を追加した。

<br>

#### 修正内容一覧

<br>

| 対象 | 修正内容 |
|:---|:---|
| `deactivate_modal_controller.js` | スマホボトムシート対応（touchstart/touchmove/touchend・120pxスワイプで閉じる）・open()冒頭で_closeTimerキャンセル・style.cssText=""によるインラインスタイル完全クリア・requestAnimationFrame二重呼び出しで確実なアニメーション初期化 |
| `settings/show.html.erb` | `<div hidden>` → `class="hidden"` に統一・overlay z-[60]・mobileSheet z-[60] pointer-events-none・sheetPanel pointer-events-auto・ボトムシートHTML追加 |
| `shared/_footer.html.erb` | `py-6` → `py-6 pb-20 md:pb-6`（Bottom Navigation に隠れない対応） |
| `shared/_crisis_intervention_modal.html.erb` | z-index:50 → z-index:60 |
| `weekly_reflections/_ai_limit_modal.html.erb` | z-50 → z-[60]（2箇所） |
| `weekly_reflections/_ai_proposal_modal.html.erb` | z-[50]→z-[60]、z-[60]→z-[70]、z-[70]→z-[80] |

<br>

#### 長期バグ（2回目open時に初期位置に戻らない）の根本原因と解決

<br>

| 調査ステップ | 発見内容 |
|:---|:---|
| console.logで呼び出し順序確認 | close()とopen()の競合ではないことを確認 |
| getComputedStyle確認 | 2回目open時に `transition: none` が残っていることを発見 |
| 原因特定 | close()のsetTimeout(300ms)が_openMobile()の実行後に発火し `transition="none"` を上書き |
| 最終解決 | open()冒頭で_closeTimerをclearTimeout・style.cssText=""でインラインスタイル完全クリア・requestAnimationFrameを二重呼び出し |

<br>

#### 動作確認済み項目

<br>

| 項目 | 結果 |
|:---|:---:|
| 退会するタップ → ボトムシートスライドイン | ✅ |
| キャンセル/×/暗幕タップ/Escapeで閉じる | ✅ |
| 2回目open時に初期位置からスライドイン | ✅ |
| スワイプダウン120px以上で閉じる | ✅ |
| 120px未満で離すと元の位置に戻る | ✅ |
| フッターがBNに隠れず表示 | ✅ |
| 他モーダル（13-M・14-A・14-B）がBN前面に表示 | ✅ |
| 743 runs, 0 failures, 0 errors | ✅ |

<br>

### #H-3: 音声入力機能（voice_input_controller.js）

<br>

**ブランチ:** `feature/H-3-voice-input`<br>
**完了日:** 2026-06-21<br>
**概要:** Web Speech API（SpeechRecognition / webkitSpeechRecognition）を使った音声入力 Stimulus コントローラーを実装。<br>
振り返り入力・PMVV入力・習慣作成の全テキストフィールドに🎤アイコンを接続し、話している最中からリアルタイムにテキストが反映される設計を実現。<br>
動作確認中に偶発的に発見した D-5（危機介入機能）× G-9（ダッシュボード表示）の不整合バグは H-10 として別途切り出した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| JS | `voice_input_controller.js` を新規作成（SpeechRecognition / webkitSpeechRecognition の両対応） |
| JS | `recognition.lang = "ja-JP"` で日本語認識を設定 |
| JS | `interimResults = true` と `handleResult` での `interimTranscript` 反映により、話している最中からリアルタイムにテキストが表示される |
| JS | `startValue` を録音開始時点で保持し、毎イベントで「startValue + 確定テキスト + 暫定テキスト」を組み立て直すことで重複・消失バグを防止 |
| JS | `recognition.start()` を try/catch で保護し、`DOMException`（recognition has already started）によるクラッシュを防止 |
| JS | `window.activeVoiceController` で複数フィールド間の同時録音を防止（新しいフィールドの録音開始時に前のフィールドを自動停止） |
| JS | `isProcessing` フラグで `start()` 呼び出し中の連打をロックし、`onstart` イベントで解除 |
| JS | `showToast()` をインライン表示方式に変更（🎤ボタン直上に絶対配置で表示） |
| JS | 未対応ブラウザ（Firefox等）では `connect()` で `style.display = "none"` により🎤ボタンを非表示 |
| JS | `disconnect()` で `recognition.abort()` を実行し、Turbo遷移後のマイク解放を保証 |
| View | `weekly_reflections/new.html.erb`（4箇所）・`user_purposes/_voice_field.html.erb`・`habits/new.html.erb` に音声入力フィールドを追加 |
| View | 上記ビューの `data-controller="voice-input"` を持つ親divに `class="relative"` を追加（インライントーストの絶対配置の基準位置として必要） |
| Doc | `privacy.html.erb` に音声入力機能の説明を追加（4-2節：音声データはブラウザ内処理のみ、外部APIへの送信なし） |

<br>

#### リアルタイム追記の実装設計

<br>

ISSUE要件「認識テキストをリアルタイムでテキストエリア・入力フィールドに追記」を満たすため、<br>
`interimResults: true` を活用して「話している途中の暫定テキスト」も `onresult` イベントで取得する設計にした。<br>
`handleResult` 内で `event.results` を全件ループし、`isFinal: true`（確定結果）と<br>
`isFinal: false`（暫定結果）をそれぞれ別の変数に集計したうえで、<br>
最終的に `startValue + separator + finalTranscript + interimTranscript` をフィールドに書き込む。

<br>

```javascript
// 話している最中からリアルタイムに反映する（interimTranscriptを含める）
this.fieldTarget.value =
  this.startValue + separator + finalTranscript + interimTranscript
```

<br>

`interimTranscript` は次のイベントが来るたびに新しい内容で上書きされるため、<br>
確定した瞬間に二重に残ることはない。

<br>

#### インライントーストへの設計変更

<br>

当初は既存の `#flash-area`（ページ最下部）を使ったトースト表示を実装していたが、<br>
動作確認で2つの問題が発覚した。

<br>

| 問題 | 原因 |
|:---|:---|
| 2回目以降トーストが表示されない | `flash_controller.js` の `dismiss()` は要素を `hidden` クラスで隠すだけで DOM から削除しないため、`querySelector` が古い非表示要素を誤って再利用していた |
| トーストの位置が分かりにくい | `#flash-area` はページ最下部固定のため、複数フィールドが縦に並ぶフォームでは操作した🎤ボタンから離れた位置に表示される |

<br>

解決策として、`#flash-area` を使わず🎤ボタンの直後に絶対配置でインラインメッセージを挿入する方式に変更した。<br>
`bottom-full`（ボタンの直上に配置）を採用し、縦に並ぶ次のフィールドと重ならないよう調整した。<br>
`position: relative` はJS側で強制せず、HTML側の `class="relative"` で明示する設計とすることで<br>
レイアウトの責務をHTML/CSS側に集約した（JSはロジックのみを担当）。

<br>

#### 連打防止の二段階設計

<br>

| 防御 | 実装 | 防ぐ問題 |
|:---|:---|:---|
| `isProcessing` フラグ | `start()` 呼び出し直後にロックし `onstart` イベントで解除 | マイク起動前の連打による `DOMException` |
| トーストの再利用 | `data-voice-inline-toast` 属性で既存ボックスを検出し再利用 | 同一メッセージの大量表示 |
| `onclick` への代入 | `addEventListener` ではなく `onclick =` を使用 | 閉じるボタンのイベントリスナー多重登録 |

<br>

`closeButton.onclick = () => { toastBox.remove() }` のように `onclick` への代入方式を採用することで、<br>
トーストボックスを再利用するたびにクリックハンドラーが積み重なる事故を防いでいる。

<br>

#### テスト結果

<br>

```
743 runs, 1861 assertions, 0 failures, 0 errors, 0 skips
```

<br>

> 📌 音声入力機能はブラウザのWeb Speech APIを直接操作するJavaScript機能のため、<br>
> Rails の自動テスト（Minitest）の対象外。Chrome（リアルタイム追記・マイク拒否時の挙動・複数フィールド制御）・<br>
> Firefox（🎤ボタン非表示）でのブラウザ動作確認を実施し、すべての完了条件を満たすことを確認した。

<br>

### #H-4: グラフ・進捗分析ページ（19番）

<br>

**ブランチ:** `feature/H-4-analytics-page`<br>
**完了日:** 2026-06-22<br>
**概要:** 習慣別達成率推移・気分スコア推移・ストリーク記録・月次サマリーをChart.jsで可視化するグラフページを実装。<br>
期間フィルター（4週/12週/全期間）・Empty State・Bottom Navigationバッジリセット機構・デスクトップ用ヘッダーリンクを含む。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| DB | `user_settings.last_analytics_viewed_at` カラム追加（グラフページの最終閲覧日時を記録） |
| Model | `UserSetting#touch_analytics_viewed_at!` 追加（`update_columns` で軽量更新） |
| Controller | `AnalyticsController#index` 新規実装（期間フィルター・折れ線/棒グラフ用データ・月次サマリー・N+1対策済み集計） |
| Controller | `ApplicationController#bn_ai_analysis_count` を `last_analytics_viewed_at` 基準に変更（H-1時点の固定7日窓から訪問ベースのリセット方式に変更） |
| Route | `get "analytics", to: "analytics#index", as: :analytics` 追加 |
| JS | `analytics_chart_controller.js` 新規作成（Chart.js v4 UMDビルド・折れ線グラフ＋棒グラフ・`disconnect()` で `destroy()`） |
| View | `analytics/index.html.erb` 新規作成（Empty State・月次サマリーカード・2種のグラフ・ストリークテーブル） |
| View | `shared/_bottom_navigation.html.erb` のグラフタブを `user_purpose_path`（暫定）→ `analytics_path`（正式）に差し替え |
| View | `shared/_header.html.erb` のPC用・モバイル用ナビゲーションに「グラフ」リンクを追加（デスクトップ幅でもアクセス可能に） |

<br>

#### N+1対策の設計（最重要ポイント）

<br>

習慣数 × 週数の組み合わせでグラフを描画する画面は典型的なN+1の温床になりやすいため、以下を徹底した。

<br>

| 対策 | 内容 |
|:---|:---|
| 一括取得 | `habit_records` を期間全体ぶん `pluck` で1回だけ取得し、Rubyのハッシュで `[habit_id, 週開始日]` ごとにグルーピング |
| `effective_weekly_target` のループ外計算 | 値は週によって変わらないため、習慣ごとに1回だけ計算してから週ループに渡す |
| `.pluck` ではなく `.map` を使用 | `habit_excluded_days.pluck(:day_of_week)` は preload 済みでも必ずDBに問い合わせる仕様があるため、preload済み配列を直接 `.map(&:day_of_week)` する設計に変更 |
| 月次サマリーとの統合クエリ | チャート期間と当月のうち早い方を起点に1回だけ `habit_records` を取得し、月次サマリーもメモリ内で算出 |

<br>

#### Bottom Navigationバッジリセットの仕組み

<br>

ユーザーがグラフタブを開く

↓

AnalyticsController#index の先頭で touch_analytics_viewed_at! を実行

↓ user_settings.last_analytics_viewed_at = 現在時刻

同一リクエスト内でレイアウトが Bottom Navigation をレンダリング

↓ bn_ai_analysis_count が current_user.user_setting（has_one キャッシュ）を参照

↓ 更新済みの last_analytics_viewed_at がそのまま基準時刻になる

青バッジの判定（基準時刻以降に完了した分析のみカウント）→ 0件 → バッジが消える

<br>

`last_analytics_viewed_at` が `nil`（未訪問ユーザー）の場合は H-1時点の設計を踏襲し `7.days.ago` にフォールバックする。

<br>

#### Chart.js 導入時のトラブルシューティング記録

<br>

Chart.js を importmap 経由で導入する際、ESM版の配布形式に起因する複数の障害が発生し、<br>
最終的に UMD版 + グローバル変数方式で解決した。詳細は本READMEの「開発を通じて得た主要な教訓」を参照。

<br>

#### テスト結果

<br>

```
全テスト:  756 runs, 1885 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #H-5: オンボーディング step2 習慣テンプレート選択

<br>

**ブランチ:** `feature/H-5-onboarding-template-selection`<br>
**完了日:** 2026-06-26<br>
**概要:** オンボーディングのステップ構成を再設計し、step2（内部ファイル名）に習慣テンプレート選択画面（UI表示: 1/2）を実装。<br>
step5（内部ファイル名・UI表示: 2/2）は既存のPMVV入力ステップ。<br>
`habit_templates`（#A-5で登録済みのマスタデータ18件）をカテゴリ別に表示し、<br>
選択した習慣をオンボーディング完了時に一括登録する。<br>
PDCAロックをスキップする `require_unlocked_unless_onboarding` を実装し、<br>
初回ユーザーがオンボーディング経由で習慣を作成できる設計を実現した。

<br>

#### 実装内容

<br>

| カテゴリ | 内容 |
|:---|:---|
| Controller | `OnboardingsController#step2` を新規追加（GETで習慣テンプレート一覧を表示） |
| Controller | `OnboardingsController#complete` を修正（`selected_template_ids` パラメータを受け取り、選択テンプレートから習慣を一括作成） |
| Controller | `ApplicationController` に `require_unlocked_unless_onboarding` メソッドを追加 |
| Controller | `HabitsController#create` に `before_action :require_unlocked_unless_onboarding` を追加（PDCAロック中でも初回ログイン時はスキップ） |
| Model | `HabitTemplate` モデルを参照（#A-5実装済み）・`category` スコープでカテゴリ別取得 |
| Route | `get "onboarding/step2", to: "onboardings#step2", as: :onboarding_step2` を追加 |
| View | `app/views/onboardings/step2.html.erb` を新規作成（カテゴリ別テンプレートカード・チェックボックス選択UI） |
| Seeds | `seeds.rb` の `User.destroy_all` を `User.unscoped.delete_all` に変更（`prevent_physical_destroy` コールバック回避） |
| Seeds | `find_or_initialize_by + assign_attributes + save!` パターンを維持（冪等性確保） |

<br>

#### require_unlocked_unless_onboarding の設計

<br>

| 条件 | 動作 |
|:---|:---|
| `params[:from_onboarding] == "true"` かつ `current_user.first_login_at.nil?` | PDCAロックチェックをスキップ |
| 上記以外 | 通常の `require_unlocked` と同じ動作 |

<br>

オンボーディング経由（`from_onboarding=true`）かつ初回ユーザー（`first_login_at.nil?`）の場合のみ<br>
ロックをスキップする二重条件チェックにより、通常フォームからの不正スキップを防ぐ設計になっている。

<br>

#### seeds.rb の User.unscoped.delete_all 変更

<br>

| 方式 | 動作 | 採用 |
|:---|:---|:---:|
| `User.destroy_all` | `before_destroy :prevent_physical_destroy` コールバックが発火し `RuntimeError` | ❌ |
| `User.unscoped.delete_all` | コールバックを発火させずSQLで直接削除 | ✅ |

<br>

`prevent_physical_destroy` は本番・開発環境での物理削除を禁止するガード（#F-6で実装）。<br>
seeds.rb でユーザーをリセットする際はコールバックを経由しない `delete_all` が唯一の安全な方法になる。<br>
`User.delete_all` ではなく `User.unscoped.delete_all` を使う理由は、<br>
`scope :active`（`deleted_at IS NULL`）が適用されてしまい退会済みユーザーが残る問題を防ぐため。

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/controllers/application_controller.rb` | `require_unlocked_unless_onboarding` メソッドを追加 |
| `app/controllers/habits_controller.rb` | `before_action :require_unlocked_unless_onboarding, only: [:create]` を追加 |
| `app/controllers/onboardings_controller.rb` | `step2` アクションを追加・`complete` を修正（テンプレート選択→習慣一括作成） |
| `app/javascript/controllers/onboarding_template_controller.js` | 新規作成（テンプレートカード選択UI・チェックボックス連動） |
| `app/javascript/controllers/index.js` | `onboarding-template` コントローラーを登録 |
| `app/views/onboardings/step2.html.erb` | 新規作成（カテゴリ別テンプレートカード・ステップインジケーター） |
| `config/locales/ja.yml` | オンボーディングstep2関連メッセージを追加 |
| `config/routes.rb` | `get "onboarding/step2"` を追加 |
| `db/migrate/20260320001125_create_habit_templates.rb` | コメントの category enum 順を修正（コードレビュー対応） |
| `db/seeds.rb` | `User.destroy_all` → `User.unscoped.delete_all` に変更・コメント追加 |
| `test/controllers/onboardings_controller_test.rb` | step2表示・テンプレート選択→習慣作成・require_unlocked_unless_onboarding動作確認テストを追加 |

<br>

#### テスト結果

<br>

```
760 runs, 1891 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### #H-6: スマホ対応レスポンシブ調整（全画面）

<br>

**ブランチ:** `feature/h-6-responsive-adjustment`<br>
**完了日:** 2026-06-27<br>
**対象:** 全認証済み画面（14ファイル）のスマホ表示品質を統一

<br>

#### 対応内容

<br>

| カテゴリ | 内容 | 対象ファイル |
|:---|:---|:---|
| iOS 自動ズーム防止 | input / textarea / select の font-size を `text-base`（16px）に統一 | sessions/new, users/new, password_resets/new・edit, habits/new・edit, tasks/new, weekly_reflections/new, user_purposes/_voice_field, onboardings/step2, user_settings/rest_mode・notification_settings |
| タップ領域 44px 確保（WCAG 2.1） | 送信ボタン・キャンセルボタンを `py-2`・`py-2.5` → `py-3` に統一 | sessions/new, users/new, password_resets/new・edit, tasks/new |
| 横スクロール対応 | テーブルに `overflow-x-auto` ラッパーを追加 | weekly_reflections/show（タスク実績セクション）|
| 優先度カード高さ統一 | CSS Grid 内の3カードが `h-full` + `flex flex-col` で常に同一高さに揃う | tasks/new |

<br>

#### ブラウザ確認結果

<br>

Chrome DevTools で 375px（iPhone SE）に設定して全画面確認済み。

<br>

| 確認項目 | 結果 |
|:---|:---:|
| input タップ時に iOS でページがズームしない | ✅ |
| 優先度カード（Must/Should/Could）の枠サイズが揃っている | ✅ |
| ボタンが 44px 以上のタップ領域 | ✅ |
| タスク実績リストが横スクロール可能 | ✅ |
| ストリーク記録テーブルが 375px 内に収まる | ✅ |
| 通知設定のスライダー「10件」が崩れない | ✅ |
| お休みモード設定の入力がズームしない | ✅ |
| オンボーディング step2 テンプレートが2列 | ✅ |

<br>

### #H-7: Empty State UI 実装（全画面）

<br>

**ブランチ:** `feature/h-7-empty-state-ui`<br>
**完了日:** 2026-06-28<br>
**概要:** データが0件のとき表示する案内UI（Empty State）を共通パーシャル化し、<br>
ダッシュボード・習慣一覧・タスク一覧・グラフ・PMVV・振り返りの全6画面に統一実装。<br>
外部レビューの指摘（py-10・font-semibold・max-w-md・inline-flex・render partial: locals: 形式）を全て反映した。

<br>

#### 共通パーシャルの設計

<br>

| パラメータ | 型 | デフォルト | 説明 |
|:---|:---|:---|:---|
| `icon` | 文字列 | `"📋"` | 絵文字アイコン（`aria-hidden="true"` でアクセシビリティ対応） |
| `title` | 文字列 | `"データがありません"` | メインメッセージ |
| `description` | 文字列 | nil | 補足説明文（省略可、省略時は非表示） |
| `cta_label` | 文字列 | nil | CTAボタンラベル（`cta_path` とセットで指定） |
| `cta_path` | パス | nil | CTAボタンの遷移先（`cta_label` とセットで指定） |
| `cta_class` | 文字列 | nil | CTAボタンの追加クラス（省略時はデフォルトの青いボタン） |
| `testid` | 文字列 | `"empty-state"` | `data-testid` 属性値（テストコードから識別） |

<br>

#### 画面別の実装詳細

<br>

| 画面 | icon | CTA | ロック中のガード | 特記事項 |
|:---|:---|:---|:---:|:---|
| ダッシュボード | 📊 | ✅ 「最初の習慣を追加する」 | ✅ | `testid: "dashboard-habits-empty-state"` |
| 習慣一覧 | 📋 | ✅ 「習慣を追加する」 | ✅ | `testid: "habits-empty-state"` |
| タスク一覧（all） | ✅ | ✅ 「タスクを追加する」 | ✅ | タブ別分岐（all/done/must等） |
| タスク一覧（done） | ✅ | なし | — | 完了タスクがないだけのためCTA不要 |
| グラフ分析 | 📊 | ✅ 「ダッシュボードへ →」 | — | `text-xs` の小さめボタンを`cta_class`で指定・`testid: "analytics-empty-state"` |
| PMVV目標 | 🎯 | ✅ 「目標を入力する →」 | — | バイオレット色・`rounded-xl` を `cta_class` で指定 |
| 振り返り一覧 | 📖 | なし | — | 時間帯依存のためCTA非表示・案内テキストのみ |

<br>

#### `local_assigns.fetch` を使う理由

<br>

Railsパーシャルでデフォルト値を安全に設定するには `local_assigns.fetch(:key, default)` が最適。<br>
`defined?(変数名)` はスコープ問題で誤作動する可能性があり、<br>
`||=` は意図的に `false` を渡したいケースで誤作動する可能性がある。

<br>

#### `render partial: locals: ` 形式を採用した理由

<br>

省略記法 `render "shared/empty_state"` でも動作するが、<br>
`render partial: "shared/empty_state", locals: { ... }` の明示的な形式にすることで<br>
「パーシャルにローカル変数を渡している」という意図がコードを読む人に伝わりやすくなる。<br>
将来名前空間が増えたときのテンプレート解決失敗リスクも防げる。

<br>

#### テスト結果

<br>

```
766 runs, 1908 assertions, 0 failures, 0 errors, 0 skips
dashboards: 10 runs, 46 assertions, 0 failures
analytics:  12 runs, 24 assertions, 0 failures
tasks:      21 runs, 49 assertions, 0 failures
```

<br>

#### 追加・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/views/shared/_empty_state.html.erb` | **新規作成**: 共通Empty Stateパーシャル |
| `app/views/dashboards/index.html.erb` | 習慣0件時にCTA付きEmpty Stateを追加 |
| `app/views/habits/index.html.erb` | 既存の独自Empty StateをパーシャルのCTAに統一 |
| `app/views/tasks/index.html.erb` | タブ別分岐でパーシャルに統一 |
| `app/views/analytics/index.html.erb` | `data-testid="analytics-empty-state"` を維持したままパーシャル化 |
| `app/views/user_purposes/show.html.erb` | バイオレット色ボタンをcta_classで指定してパーシャル化 |
| `app/views/weekly_reflections/index.html.erb` | CTAなしの案内テキストのみをパーシャルに統一 |
| `test/controllers/dashboards_controller_test.rb` | ダッシュボードEmpty StateのCTA表示テストを2件追加 |
| `test/controllers/analytics_controller_test.rb` | パーシャル移行後も`analytics-empty-state` testidが正しく出力されることを確認するテストを追加 |
| `test/controllers/tasks_controller_test.rb` | タスクEmpty State（all/done）の表示テストを3件追加 |

<br>

### #H-8: パーソナライズAIコンテキスト生成（UserContextBuilderService）

<br>

**ブランチ:** `feature/h-8-personalize-ai-context`<br>
**完了日:** 2026-06-29<br>
**概要:** 過去8週間の習慣達成パターン・振り返りトレンド・AI提案採用状況を分析し、<br>
AIプロンプトに注入するパーソナライズコンテキスト（context_summary）を生成する機能を実装。<br>
インコンテキスト学習により、ファインチューニング不要でユーザー個別の傾向を反映した提案を実現する。

<br>

#### 追加テーブル

<br>

| テーブル | 役割 | 主な設計ポイント |
|:---|:---|:---|
| `ai_user_profiles` | ユーザー別AIプロファイルの保存（1ユーザー1レコード） | user_id UNIQUE制約・jsonb default: {}・analyzed_at インデックス |

<br>

#### 主要コンポーネント

<br>

| コンポーネント | 種別 | 役割 |
|:---|:---|:---|
| `AiUserProfile` | Model | stale?メソッド（7日以上古いか判定） |
| `UserContextBuilderService` | Service | 分析実行・context_summary生成・DBへのUpsert |
| `UpdateAiProfileJob` | Job | 単一ユーザー更新 / 全ユーザー週次一括更新の2パターン |

<br>

#### UserContextBuilderService の分析内容

<br>

| メソッド | 分析内容 |
|:---|:---|
| `analyze_habit_patterns` | 過去8週間の習慣別達成率（HIGH=70%以上・LOW=40%未満で分類） |
| `analyze_reflection_trends` | 振り返り完了率・平均気分スコア・ネガティブ/ポジティブキーワード抽出 |
| `analyze_proposal_adoption` | AI提案タスク（ai_generated: true）の実行率算出 |
| `generate_context_summary` | 上記を日本語テキストに変換（最大3000文字） |
| `context_text_for` | プロファイルなし・user nil 時は空文字を返す（フォールバック） |

<br>

#### 更新タイミング

<br>

| タイミング | 実装 | 詳細 |
|:---|:---|:---|
| 振り返り完了後 | `WeeklyReflectionCompleteService` から `UpdateAiProfileJob.perform_later` | AI分析上限に関わらず常に実行（DB集計のみでAPI不使用） |
| 毎週月曜 JST AM4:15 | GoodJob cron `"15 19 * * 1"` | 全アクティブユーザーを `find_each` で順次更新 |

<br>

#### 外部レビュー対応（全項目反映済み）

<br>

| 指摘 | 対応内容 |
|:---|:---|
| t.references の重複インデックス | `index: false` を明示し `add_index` の UNIQUE のみ残す |
| jsonb カラムに default: {} なし | `default: {}, null: false` を全 jsonb カラムに付与 |
| stale? の定数二重管理 | `AiUserProfile#stale?` から `UserContextBuilderService::STALE_DAYS` を参照 |
| context_text_for に user nil ガードなし | `return "" if user.nil?` を先頭に追加 |
| call の戻り値に profile を含める必要なし | `{ success: true/false }` に簡素化 |
| rescue の分類が粗い | `RecordInvalid` / `StatementInvalid` / `StandardError` に分類 |
| context_summary の最大長未設定 | `MAX_SUMMARY_LENGTH = 3000` で truncate |
| N+1 の TODO コメント不足 | `analyze_habit_patterns` 内に `# TODO(H-9)` を追加 |

<br>

#### テスト結果

<br>

```
H-8テスト:  14 runs, 22 assertions, 0 failures, 0 errors, 0 skips
全テスト:  780 runs, 1930 assertions, 0 failures, 0 errors, 0 skips
```

<br>

---

<br>

### #H-9: N+1クエリ検知・includes最適化（全一覧ページ）+ 完了バナー永続化

<br>

**ブランチ:** `feature/H-9-n-plus-one-optimization`<br>
**完了日:** 2026-07-09<br>
**概要:** 一覧系ページのN+1を bullet で検査し、実際に残っていた唯一のN+1（`Habit#excluded_day_numbers` の `.pluck`）を解消。<br>
あわせてグラフタブ青バッジの重複カウント（`bn_ai_analysis_count` の `is_latest` 未絞り込み）と `aria-current` の表記不統一を修正。<br>
実装確認中に発見したPMVV・振り返り完了バナーの「リロードで消える／✖で消しても復活する」不具合も本ISSUE内で修正した。

<br>

#### N+1・パフォーマンス対応

<br>

| 対象 | 実態 | H-9での対応 |
|:---|:---|:---|
| `Habit#excluded_day_numbers` | `.pluck` が preload を無視して毎回SELECT発行（習慣一覧でN+1＋Unused Eager Loading警告） | `.map(&:day_of_week)` に変更し preload済み配列を使用 |
| ダッシュボード / 習慣一覧 | `@today_records_hash`＋`group(:habit_id)`集計で既にN+1フリー | `includes(:habit_records)` は逆効果のため追加せず |
| タスク一覧 | 優先度別カウントは既に `group(:priority).count` | 追加変更なし |
| 週次振り返り一覧 | 既に `includes(:habit_summaries)` 済み | 追加変更なし |
| AI提案モーダル | 提案は `actions_json`（JSONB）から描画・`ai_proposed_*` 未参照 | `includes` は no-op のため追加せず |

<br>

#### バグ修正・整合性対応

<br>

| 項目 | 内容 |
|:---|:---|
| グラフタブ青バッジの重複カウント | `bn_ai_analysis_count` に `.where(ai_analyses: { is_latest: true })` を追加。再分析で `is_latest: false` になった古い分析を除外（`index_ai_analyses_latest_weekly_reflection_unique` によりDB側でも1振り返り＝最新1件を保証） |
| aria-current の表記統一 | `analytics/index.html.erb` の期間フィルターを `? "page" : false`（`_header.html.erb` と同じWAI-ARIAトークン）に統一。非選択時は属性自体を出力しない |

<br>

#### 完了バナーの永続表示（PMVV・振り返り／✖まで残す）

<br>

| 項目 | 内容 |
|:---|:---|
| 追加カラム | `user_settings.pmvv_banner_dismissed_at` / `reflection_banner_dismissed_at`（✖で閉じた日時） |
| 表示判定 | `dashboards_controller` で「最新分析の `created_at` が閉じた日時より新しければ表示」。リロード後も✖まで残り、再分析で再表示される |
| dismiss経路 | `PATCH /user_purpose/dismiss_completion_banner`・`PATCH /weekly_reflections/dismiss_completion_banner` を追加。`dismissible_controller.js` を汎用化し、✖押下時に fetch で閉じ状態を保存（204応答） |
| ライブ配信との共存 | 既存の `broadcast_dashboard_completion`（Turbo Stream）はそのまま維持 |

<br>

#### Issue記載より「実コード」を優先した判断

<br>

| Issueチェックリスト | 判断 |
|:---|:---|
| `includes(:habit_records)` 追加 | 追加せず（既存の集計クエリ方式が最適・eager loadは逆効果） |
| `includes(:ai_proposed_habits, :ai_proposed_tasks)` 追加 | 追加せず（モーダルは `actions_json` 描画で no-op） |
| bullet を test グループに追加し `raise` | 見送り（無関係な既存テストを巻き込むため）。`/habits` のクエリ数を数える決定論的な回帰テストで代替（CI全体での bullet 強制は Week I で別途検討） |

<br>

#### テスト結果

<br>

```
H-9追加分:  dashboards 18 runs（バナー永続化8本）/ analytics（重複カウント2本）/ habits（N+1クエリ数1本）
全テスト:  791 runs, 1974 assertions, 0 failures, 0 errors, 0 skips
動作確認:  http://localhost:3000 で両バナーの「表示→F5で残る→✖→F5で復活しない」・PATCH 204 を確認
Bullet:    docker compose logs web | grep -iE "eager loading|N+1 Query" → 警告なし（合格）
```

<br>

> 💡 **N+1は「preload しても `.pluck`／`.where`／`.count` を使うと再クエリが飛ぶ」**<br>
> `includes` を付けても、モデルメソッド内で `.pluck` を使うと preload が無視され N+1 になる。<br>
> bullet の「Unused Eager Loading」警告はこのパターンを検知するシグナルになる。

<br>

### #H-10: 危機介入レコードによるダッシュボード「分析中」誤表示の修正

<br>

**ブランチ:** `feature/h-10-crisis-skipped-banner`<br>
**完了日:** 2026-07-12<br>
**概要:** 危機介入（#D-5）でAI分析がスキップされたレコード（`crisis_detected: true` / `actions_json: nil`）を、<br>
G-9のダッシュボード判定が「分析未完了」と誤認し「振り返りAI分析中...」バナーが永続表示される不具合を修正。<br>
D-5・G-9はそれぞれ単体では正常で、2機能の組み合わせ（分析スキップ後の後続表示）に考慮漏れがあった。

<br>

#### 不具合の原因

<br>

| 項目 | 内容 |
|:---|:---|
| 発見経緯 | #H-3（音声入力）の動作確認中に偶発的に発見 |
| 直接原因 | `@reflection_ai_analysis` を `.latest.where.not(actions_json: nil).first` で取得していた |
| 誤判定の流れ | 危機スキップ（`actions_json: nil`）が最新だと除外され `nil` になり、`@reflection_analysis_pending` が永久に `true` のままになる |

<br>

#### 修正内容（変更対象は G-9 のダッシュボード表示ロジックのみ）

<br>

| ファイル | 変更内容 |
|:---|:---|
| `app/controllers/dashboards_controller.rb` | `.where.not(actions_json: nil)` 除外を廃止。最新分析（`is_latest: true`・1件）を取得し `crisis_detected` で分岐。`@reflection_crisis_skipped` を追加し pending 条件に `!@reflection_crisis_skipped` を追加。判定を private `reflection_analysis_pending?` に切り出し |
| `app/views/dashboards/index.html.erb` | `elsif @reflection_crisis_skipped` ブランチを追加し 💛 の「見送り」専用バナーを表示。各バナーに `data-testid` を付与 |
| `config/locales/ja.yml` | バナー文言を `dashboards.index.*` に i18n 集約 |
| `test/controllers/dashboards_controller_test.rb` | 回帰テスト4件追加 |

<br>

#### 設計上のポイント

<br>

| ポイント | 内容 |
|:---|:---|
| なぜ絞り込みを外すか | `is_latest` は部分ユニークインデックス（`weekly_reflection_id かつ is_latest = true`）で「1振り返り＝最新1件」を保証。最新1件を取得し `crisis_detected` で分岐するのが正しい |
| マイグレーション | **不要**（`crisis_detected` は `boolean / null: false / default: false` で既存） |
| gem 追加・再ビルド | 不要 |
| D-5 への影響 | なし（危機介入側のロジック・データ構造は変更しない） |
| テスト戦略 | 文言依存を避け `data-testid` で構造検証。i18n キーの存在チェックも追加 |

<br>

#### 検証結果

<br>

| 項目 | 結果 |
|:---|:---|
| 全テスト | 795 runs / 0 failures / 0 errors |
| 実機（複数危機レコード） | `is_latest: true` は常に1件で表示崩れなし |
| 実機（通常 → 危機 → 通常） | 「分析中」→ 完了バナーへ正しく遷移 |
| 実機（Turbo 戻る/進む） | バナー表示が崩れない |

<br>

### #I-1: 統合テスト・モデルテスト（本リリース分）

<br>

**ブランチ:** `feature/i-1-integration-model-tests`<br>
**完了日:** 2026-07-14<br>
**対象:** 本リリースで追加した全機能の統合テスト・モデルテストを網羅追加。あわせて `db:migrate:status` の `NO FILE` 表示を棚卸し。

<br>

#### 追加・拡張したテスト

<br>

| ファイル | 種別 | 内容 |
|:---|:---|:---|
| `test/models/task_test.rb` | 追記 | `task_type` enum・`set_default_task_type` コールバック・`priority` 必須・`habit` optional・`overdue` スコープ・`active` スコープの並び順 |
| `test/models/user_purpose_test.rb` | 新規 | `analysis_state` enum・`version` バリデーション（必須/整数/1以上）・5フィールド必須・500文字境界・`active_for`/`current_for`（有効な最新版の取得） |
| `test/models/numeric_habit_achievement_test.rb` | 新規 | 数値型習慣の達成率境界値。計算経路が2つ（`Habit#weekly_progress_stats`＝`floor`／`WeeklyReflectionHabitSummary.build_from_habit`＝`round(2)`）あるため両方を検証 |
| `test/models/concerns/crisis_detector_test.rb` | 追記 | 全 `CRISIS_KEYWORDS` の網羅検出（退行防止）＋ 誤検出ガード（「必死」「終わらせたい」等の一般語を検出しない） |
| `test/services/weekly_reflection_complete_service_crisis_test.rb` | 追記 | 危機検出時に `UpdateAiProfileJob` も抑制されること・危機 `AiAnalysis` の `is_latest`/`analysis_type`/`prompt_version=crisis_skip` 検証 |
| `test/integration/omniauth_login_flow_test.rb` | 新規 | Google/LINE コールバック→セッション確立→遷移先。新規/既存/フォールバック名/認証失敗 |
| `test/integration/pmvv_analysis_flow_test.rb` | 新規 | PMVV `create`（pending・旧版無効化・`PurposeAnalysisJob` 投入）/ 危機 `create`（ジョブ抑制・`failed`・危機記録・`flash[:crisis]`）/ `update`（バージョン管理）/ `apply_proposals`（提案→習慣・タスク作成） |
| `test/controllers/tasks_controller_test.rb` | 追記 | 作成→完了→アーカイブの一連フロー（エンドツーエンド） |
| `test/jobs/csv_export_job_test.rb` | 新規 | 非同期CSVのジョブ実行→ダウンロードURL入りメール送信・`email` 未設定ユーザーはスキップ |

<br>

#### 副産物①：危機監査レコードの保存バグを修正（統合テストが検出）

<br>

`UserPurposesController#record_crisis_analysis_for_purpose` が `analysis_type: :purpose_breakdown` の `AiAnalysis` を作る際、<br>
`input_snapshot` に PMVV の5キー（`purpose`/`mission`/`vision`/`value`/`current_situation`）を含めていなかった。<br>
そのため #D-9 の `input_snapshot_schema_valid` バリデーションで弾かれ、`AiAnalysis.create`（非bang）が保存に失敗し、<br>
**危機検出の監査レコードが本番で黙って残らない**状態だった。`input_snapshot` に5キーを追加して修正（`app/controllers/user_purposes_controller.rb`）。<br>
※週次振り返りの危機記録は `analysis_type: :weekly_reflection` で同検証をスキップするため影響なし。

<br>

#### 副産物②：`db:migrate:status` の `NO FILE` 表示の棚卸し

<br>

**結論：バグではなく、複数データベース構成による正常表示。**<br>
`config/database.yml` が `primary`（`migrations_paths=db/migrate`）と `cable`（`db/cable_migrate`・Solid Cable用）の2接続を<br>
同一DB（`habitflow_development`）に定義しているため、`db:migrate:status` は接続ごとに1ブロックずつ出力する。<br>
`primary` ブロックでは Solid Cable の1件だけ `NO FILE`、`cable` ブロックでは他44件が `NO FILE` になる。<br>
「連続実行で `NO FILE` 多発」に見えたのは、同一実行内の primary/cable 2ブロックの読み違いだった。<br>
実ファイル 44（`db/migrate`）＋ 1（`db/cable_migrate`）＝ 45 ＝ `schema_migrations` 45件で完全一致・**孤立ゼロ**を検証コマンドで確認済み。実害なし・修正不要。

<br>

#### 検証結果

<br>

| 項目 | 結果 |
|:---|:---|
| 全テスト | 841 runs / 2223 assertions / 0 failures / 0 errors / 0 skips |
| `schema_migrations` ↔ 実ファイル | 45件すべて一致（孤立なし） |
| 危機監査レコード | 修正後、PMVV危機検出時も `AiAnalysis` が正しく保存される |

<br>

### #I-6: キャッシュ戦略設計（Solid Cache / fragment cache）

<br>

**ブランチ:** `feature/i-6-solid-cache`<br>
**完了日:** 2026-07-18<br>
**対象:** ダッシュボード・グラフ・AI分析結果ページに Redis 不要のキャッシュを導入し、Render 無料構成での UX とコストを最適化

<br>

#### 採用技術と構成方針

<br>

| 項目 | 内容 |
|:---|:---|
| キャッシュストア | Solid Cache 1.0.10（Rails 8 標準バックエンド・MIT・完全無料） |
| 保存先 | 既存の Neon PostgreSQL 内の `solid_cache_entries` テーブル（Redis 不使用） |
| DB構成 | **単一DB構成**（`config/cache.yml` で `database:` を指定せず `ActiveRecord::Base` のコネクションプールを共有） |
| 上限管理 | `max_age: 7日` ＋ `max_entries: 10,000`（`max_size` の容量サンプリングを避けクエリコストを削減） |
| テーブル作成 | `db/migrate` の通常マイグレーション（`render.yaml` の `startCommand` の `db:migrate` で本番に自動適用） |

<br>

#### キャッシュ対象と無効化設計

<br>

| 対象 | キャッシュするもの | キー | 有効期限 | 無効化トリガー |
|:---|:---|:---|:---:|:---|
| ダッシュボード | 習慣記録の生集計（`check_counts`/`numeric_sums`） | `dashboard_habit_stats:{user_id}:{週開始日}` | 1時間 | `HabitRecord`/`Habit` の `after_commit` |
| グラフ（19番） | 完成した集計データ3種（習慣/月次サマリー/気分） | `analytics:{user_id}:{period}:{today}` | 6時間 | `HabitRecord`/`Habit`/`WeeklyReflection` の `after_commit` |
| AI分析結果（18番） | ビューのHTML断片（読み取り専用部のみ） | `ai_analyses/{id}-{updated_at}`（自動） | 永続（max_age） | 再分析で新レコード＝新IDになり自動失効 |

<br>

#### 設計上の重要な判断

<br>

**① ダッシュボードは「集計値だけ」をキャッシュし、達成率の割り算は毎回実行する**

<br>

達成率の分母 `effective_weekly_target`（目標回数 ÷ 除外日考慮）は、preload 済みの `habit_excluded_days` から追加クエリ0件で求まる。<br>
そのため達成率まで丸ごとキャッシュせず「習慣記録の生集計」だけをキャッシュすることで、**目標値・除外日の変更が即座に画面へ反映**される（1時間待たされない）設計にした。

<br>

**② キャッシュキーは `Date.today.cweek` ではなく `HabitRecord.today_for_record` を使う**

<br>

ISSUE原文は `Date.today.cweek` だったが、これは本アプリの2つの規約に違反する。<br>
・`Date.today` はサーバーのタイムゾーン（本番はUTC）を見るため、`config.time_zone = "Tokyo"` を無視して日付が1日ズレる。<br>
・本アプリの日付境界は **AM4:00** のため、`cweek` だと深夜0:00〜3:59 だけキーが翌週にジャンプする。<br>
`HabitRecord.today_for_record` 由来の週開始日（`beginning_of_week(:monday)`）を使い、全画面と同じ日付判定に揃えた。

<br>

**③ Solid Cache は `delete_matched` 非対応 → 再構築可能な「決定的キー」で無効化する**

<br>

`SolidCache::Store` はワイルドカード削除（`delete_matched("dashboard:*")`）を実装していない（呼ぶと `NotImplementedError`）。<br>
そのため無効化は「DBを引かずに完全に組み立て直せるキー」を `Rails.cache.delete` する方式に統一。<br>
キー生成・削除ロジックはすべて `ApplicationRecord`（`cache_key_for` / `expire_*`）に集約し、作る側と消す側でキーが食い違う事故を防いだ。

<br>

**④ AI分析結果ページはフォームをキャッシュ範囲外にする（CSRFトークン焼き付き防止）**

<br>

18番のフォーム（`form_with`）は `authenticity_token`（CSRFトークン）をHTMLに埋め込む。<br>
これをフラグメントキャッシュに含めると、同一ユーザーが再ログインした後に **422 InvalidAuthenticityToken** が発生する。<br>
`cache @ai_analysis do` で包むのは読み取り専用の①分析対象PMVV〜④コーチングメッセージのみとし、⑤推奨アクションのフォームは意図的に範囲外に置いた。

<br>

**⑤ `touch: true` は追加しない（Neon への無駄な書き込みを避ける）**

<br>

18番の `cache @ai_analysis` は `ai_analyses/{id}-{updated_at}` を自動でキーにする。<br>
再分析は既存レコードの更新ではなく **`AiAnalysis.create!` で新レコード（新ID）** を作る（`before_create :deactivate_previous_analyses` が古い方を `is_latest: false` にする）ため、IDが変わるだけでキーが変わり、`touch: true` は不要。<br>
追加すると AI分析のたびに `user_purposes` へ無意味な `UPDATE` が1回増えるだけなので、あえて追加しないことを「適切な設定」と判断した。

<br>

#### 効果（実測値）

<br>

| 画面 | 効果 |
|:---|:---|
| AI分析結果（18番） | 初回 Write 込み **21.5ms** → 2回目以降 Read のみ **2〜4ms**（約10倍高速化） |
| グラフ（19番） | 2回目以降は重い `pluck` ＋ Ruby ループを丸ごとスキップし `SolidCache::Entry Load` 1回のみ・描画0.5ms |
| 本番のキャッシュ基盤 | `file_store`（Renderの毎デプロイ消滅）/ `memory_store`（Puma 2 Worker間の不整合）の潜在バグを解消 |

<br>

#### テスト

<br>

| 項目 | 結果 |
|:---|:---|
| 全テスト | 855 runs / 2282 assertions / 0 failures / 0 errors / 0 skips |
| 追加テスト | 疎通5件（`solid_cache_store_test`）＋ 動作・無効化・セキュリティ・AM4:00境界9件（`i6_cache_behavior_test`） |
| 既存テスト保護 | `test` 環境は `null_store` を維持し、既存841テストに影響なし（キャッシュ検証は専用テスト内で一時差し替え） |

<br>

#### 作成・変更ファイル一覧

<br>

| ファイル | 変更内容 |
|:---|:---|
| `Gemfile` / `Gemfile.lock` | `solid_cache "~> 1.0"` を追加 |
| `config/cache.yml` | 新規作成（`max_age` / `max_entries` / `namespace`・`database:` は指定しない） |
| `db/migrate/*_create_solid_cache_entries.rb` | 新規作成（`solid_cache_entries` テーブル・インデックス3種） |
| `config/environments/production.rb` | `cache_store = :solid_cache_store` / `perform_caching = true` を明示 |
| `config/environments/development.rb` | キャッシュON時のストアを `memory_store` → `solid_cache_store` に統一 |
| `config/environments/test.rb` | `null_store` 維持を明示（既存テスト保護のコメント追記） |
| `app/models/application_record.rb` | キャッシュキー生成・無効化メソッドを集約（`ANALYTICS_PERIOD_KEYS` 含む） |
| `app/models/habit.rb` / `habit_record.rb` / `weekly_reflection.rb` | `after_commit` でキャッシュを無効化 |
| `app/controllers/dashboards_controller.rb` | 集計とキャッシュを分離（`fetch_weekly_record_counts` / `build_stats_from_counts`） |
| `app/controllers/analytics_controller.rb` | 集計を `build_chart_payload` に集約しキャッシュ・`PERIOD_KEYS` を `ApplicationRecord` 参照に |
| `app/views/user_purposes/ai_result.html.erb` | 読み取り専用部を `cache @ai_analysis` で包む（フォームは範囲外） |
| `test/integration/solid_cache_store_test.rb` | 新規作成（疎通テスト5件） |
| `test/integration/i6_cache_behavior_test.rb` | 新規作成（動作・無効化テスト9件） |

<br>

#### 既知の制限（トレードオフ）

<br>

- `Habit#calculate_streak!` は `update_columns` を使うため `after_commit` が発火せず、グラフの「最長ストリーク」が最大6時間古い可能性がある。<br>
- `acts_as_list` の並び替えは `update_all` を使うため、グラフの凡例の順番・配色が最大6時間古い可能性がある。<br>
- どちらも ISSUE が「リアルタイム性が不要」と定義したグラフページ内の**表示上の話**であり、データ自体が誤ることはなく、`expires_in`（6時間）で必ず解消する。

<br>

### #I-5: エラー監視・本番ログ基盤構築（Sentry）

<br>

**ブランチ:** `feature/i-5-sentry`<br>
**完了日:** 2026-07-21<br>
**対象:** 本番で発生する Rails 例外・AI API エラー・GoodJob 失敗・フロントエンド JS エラー・LINE 通知の予期しない失敗を、Sentry でリアルタイムに検知・通知する監視基盤

<br>

#### 監視対象と捕捉方式

<br>

| 監視対象 | 捕捉方式 |
|:---|:---|
| Rails 例外（本番） | `ApplicationController#render_500` から明示 `Sentry.capture_exception`（`rescue_from` で握られ自動ミドルウェアに届かないため） |
| AI API エラー | `AiClient` がタイムアウト（warning）・認証失敗401（fatal）を明示通知 |
| GoodJob ジョブ失敗 | sentry-rails の ActiveJob 連携が自動捕捉 |
| GoodJob スレッド基盤エラー | `config.good_job.on_thread_error` で通知 |
| フロントエンド JS エラー | Sentry Browser SDK（self-host）を `<head>` で読み込み未捕捉エラーを通知 |
| 週次AIプロファイル生成の失敗 | `UserContextBuilderService` の予期しない例外を通知 |
| LINE 通知の予期しない障害 | `LineNotificationService` のネットワーク/SSL/タイムアウト等を通知 |

<br>

#### 設計上の要点

<br>

- **本番のみ有効**: `SENTRY_DSN` が設定された本番環境でのみ初期化。開発・テストでは無効（無料枠を本番専用に温存）。<br>
- **ノイズ除外**: 404系（`RecordNotFound` / `RoutingError`）は送信せず、LINE の想定内失敗（Bot未友達追加400・レート上限429）も除外。<br>
- **PII 保護**: `send_default_pii = false`。ユーザー識別は `user.id` のみで、メールアドレス等は送らない。<br>
- **Performance Monitoring**: `traces_sample_rate 0.1`（本番の10%）。<br>
- **Release Tracking**: Render が自動提供する `RENDER_GIT_COMMIT` をリリースに紐付け、不具合とデプロイの相関を追跡。

<br>

### #I-2: セキュリティ最終確認（Brakeman / 手動監査）

<br>

**ブランチ:** `feature/i-2-security-final-check`<br>
**完了日:** 2026-07-26<br>
**対象:** 本リリース全機能に対する脆弱性スキャンと手動セキュリティ監査（認可・Strong Parameters・CSRF・トークン設計）を実施し、リリース可能なセキュリティ水準を機械的・網羅的に確認

<br>

#### 手動チェック6項目の結果

<br>

| チェック項目 | 結果 | 根拠 |
|:---|:---|:---|
| Brakeman 警告 0 件 | ✅ | `brakeman -A`（追加チェック込み）でコード脆弱性 0 件。`CheckUnscopedFind` も 0 |
| Strong Parameters 全確認 | ✅ | 全 20 コントローラが `require().permit()` のホワイトリスト。`permit!` は皆無 |
| 認可（他ユーザーアクセス防止） | ✅ | 全 DB アクセスが `current_user` スコープ経由。未スコープ `find` はゼロ（IDOR 無し） |
| OmniAuth CSRF 対策 | ✅ | `omniauth-rails_csrf_protection` 導入＋認証ボタンは `form_tag` の POST |
| AI提案モーダルの ai_context 検証 | ✅ | `session[:ai_context_*]`（暗号化 Cookie）に対象 ID を保存し `verify_ai_context` で一致検証 |
| CSV エクスポートの署名・期限・認可 | ✅ | `MessageVerifier` 署名＋`expires_at`（即時5分/非同期24時間）＋`user_id` 照合の三重防御 |

<br>

#### 設計上の要点

<br>

- **Brakeman を CI ゲート化**: `brakeman -w2 -z` を採用し、警告があれば終了コード 1 で検知できる運用に統一。<br>
- **EOLRails 警告の扱い**: 唯一検出された `EOLRails`（Rails 7.2 のサポート期限告知）はコードの脆弱性ではなく依存の寿命告知のため、`config/brakeman.yml` の `skip_checks` に理由コメント付きで登録（その後の Rails 8.1 化により除外を解除）。<br>
- **認可は「grep + Brakeman + テスト」の三重で証明**: `find` 全数検索・`CheckUnscopedFind` 0 件・全自動テスト緑（861件）で他ユーザーデータへのアクセス不可を裏付け。

<br>

### フレームワーク・依存関係の最新化（Rails 8.1 / Ruby 3.4.10 / Dependabot）

<br>

**ブランチ:** `feature/i-2-security-final-check`（#I-2 と同ブランチ）<br>
**完了日:** 2026-07-26<br>
**対象:** セキュリティ・保守性の観点から、フレームワークと依存ライブラリを安全な範囲で最新化し、以後の更新を自動化する体制を構築

<br>

#### 実施内容

<br>

| 対象 | 変更 | 要点 |
|:---|:---|:---|
| Ruby on Rails | 7.2.3 → **8.1.3** | サポート期限（2027-10まで）と Ruby 3.4 親和性。`load_defaults` は段階移行 |
| Ruby | 3.4.7 → **3.4.10** | 3.4 系最新パッチ（zlib CVE 等のセキュリティ修正） |
| 依存 gem（第1波） | 基盤・セキュリティ系を最新化 | `nokogiri` / `rack` / `bcrypt` / `pg` / `faraday` / `turbo-rails` / `importmap-rails` / `tailwindcss-rails` 等 |
| 依存 gem（第2波） | 影響の大きい2件を単独更新 | `good_job` / `resend`（AI分析・メール送信を個別に動作確認） |
| Brakeman | 7.1.1 → **8.0.5** | 静的解析ツールを最新化（新チェック込みで警告 0 件を再確認） |

<br>

#### 継続的な更新体制（Dependabot）

<br>

- **GitHub Dependabot** を導入（`.github/dependabot.yml`）。gem・Docker ベースイメージを毎週監視し、更新を **Pull Request** として自動作成。<br>
- **安定重視の設定**: パッチ／マイナー更新は 1 つの PR に集約し、メジャー更新は gem ごとの個別 PR として切り出し（CI を確認しながら 1 件ずつ検証可能）。<br>
- **保留したメジャー**（`puma` 8 / `solid_cable` 4 / `minitest` 6）は Web サーバー・リアルタイム基盤・テスト基盤に関わるため、安定性を優先して本リリース後に個別対応する方針とし、Dependabot の `ignore` で不要な PR を抑制。<br>
- **脆弱性対応**: `Dependabot alerts` / `security updates`（無料）を有効化し、CVE を検知・修正 PR ベースで適用。

<br>

### #I-3: 本番動作確認（Render 本番の最終スモーク）

<br>

**ブランチ:** `feature/i-3-production-check`<br>
**完了日:** 2026-08-30<br>
**対象:** 実コードに基づく本番チェックリストの実行と、本番のみで表面化する設定/ENV ギャップの監査・修正。全テスト **867 runs / 0 failures / 0 errors** 緑、`bundle audit` **脆弱性 0 件**を達成。

<br>

#### 1. 本番設定・ENV 監査

<br>

| 対象 | 修正内容 | 目的 |
|:---|:---|:---|
| `production.rb` | `action_mailer` / `asset_host` を `ENV.fetch("APP_HOST", …)` 化 | メール内リンクのドメインを本番ホストに統一 |
| `production.rb` | `public_file_server.headers` に 1 年 `immutable` の `Cache-Control` を追加 | 静的アセットの長期キャッシュ（Lighthouse「キャッシュ TTL: None」対策） |
| `database.yml` / `docker-compose.yml` | test/development の DB を分離（`DATABASE_URL` の継承を停止） | `db:test:prepare` が開発 DB を初期化する事故を防止 |
| `db/seeds.rb` ＋ `db/seeds/` | 司令塔＋テンプレート＋デモの 3 分割。破壊的シードは `development` 限定＋二重ガード | 本番 DB の誤消去を構造的に不可能化（`SEED_IN_PRODUCTION=true` を恒久安全化） |

<br>

#### 2. Sentry が検出した本番エラーの修正

<br>

| エラー | 原因 | 修正 |
|:---|:---|:---|
| `Couldn't determine a delay based on :exponentially_longer` | Rails 7.2 で `:exponentially_longer` が削除 | `application_job.rb` の `retry_on` を **`:polynomially_longer`** に変更 |
| `PG::UniqueViolation`（AiAnalysis 二重作成） | `is_latest` 部分ユニークへの並行重複 | AI 分析ジョブに `rescue ActiveRecord::RecordNotUnique` を追加（静かに破棄し完了扱い） |

<br>

#### 3. ストリークの cron 非依存化（recalc-on-save）

<br>

Render 無料プランは 15 分アクセスがないとスリープするため、深夜 4:05 の `StreakCalculationJob`（cron）が発火せず、記録してもストリークが 0 のままになる問題を発見。<br>
`HabitRecordSaveService` に「保存コミット後（トランザクション外）にその習慣の `calculate_streak!` を実行」する処理を追加し、cron に依存せず記録時にリアルタイム反映するように変更。<br>
再計算の失敗が記録保存を巻き添えにしないよう `rescue StandardError` で分離し、失敗は `Sentry.capture_exception` で可視化。日次 cron はバックアップとして残置。

<br>

#### 4. CSP（Content Security Policy）の本番対応

<br>

**① `script-src` に `:blob` を追加**<br>
importmap の polyfill（es_module_shims）が生成する `blob:` スクリプトのブロックを解消。

<br>

**② `form-action` を LINE 全ドメインに対応**<br>
Chrome / Safari は「フォーム送信後のリダイレクト先」まで `form-action` で検査するため、LINE Login の認可フロー（複数サブドメインを経由）がブロックされていた。<br>
`:https`（過度に広い）ではなく `"https://*.line.me"` / `"https://line.me"` を許可し、必要範囲だけを通す設計にした。

<br>

#### 5. Render ヘルスチェック `/up` の 404 修正

<br>

ルートに `/up`（Rails 標準ヘルスチェック）が未定義で、末尾の catch-all（`match "*path" → errors#not_found`）に飲み込まれ 404 を返していた。<br>
`get "up" => "rails/health#show"` を **catch-all より前（ルート先頭）** に追加し、200 を返すよう修正。

<br>

#### 6. Lighthouse 対応（本番計測）

<br>

| 項目 | 対応 |
|:---|:---|
| SEO | `<head>` に `content_for(:description)` で上書き可能な `<meta name="description">` を追加 |
| Accessibility | 本文の薄字 `text-gray-400 → text-gray-500`、緑文字 `text-green-600 → text-green-700`、達成率カラー三項を 700 系に統一（進捗バーの鮮やかな色・`aria-hidden` のブランドマークは意図的に保持） |
| Performance | 静的アセットの `Cache-Control` を設定。Performance スコア自体は Render 無料枠の **TTFB（サーバー応答）** が支配的で、コード側は最適化済み（FCP/LCP/CLS/TBT 良好） |

<br>

**本番 Lighthouse スコア:** Performance 81 / **Accessibility 96（コントラスト対応で更に改善）** / **Best Practices 100** / SEO 91（meta 追加で更に改善）

<br>

#### 7. gem 脆弱性の一括更新（`bundle audit`）

<br>

`bundler-audit` を導入し、既知脆弱性を検出・修正。**結果は `No vulnerabilities found`**。

<br>

| gem | 更新 | 深刻度 |
|:---|:---|:---|
| `rails`（activestorage） | 8.1.3 → **8.1.3.1** | 任意ファイル読み取り / RCE |
| `oauth2` | 2.0.19 → **2.0.25** | High（bearer トークン漏洩・OmniAuth 関連） |
| `puma` | 7.1.0 → **7.2.1** | High（PROXY プロトコル） |
| `net-imap` | 0.5.12 → **0.6.6** | High 他複数（コマンドインジェクション等） |
| `addressable` | 2.8.8 → **2.9.0** | High（ReDoS） |
| `websocket-driver` | 0.8.0 → **0.8.2** | メモリ枯渇 |
| `json` / `mail` | 2.21.2 / 2.9.1 | 各種 |

<br>

#### 8. テスト

<br>

- `HabitRecordSaveService` に recalc-on-save の検証を **9 テスト**追加（チェック型：記録→ストリーク 1／3 連続→3／解除→0、数値型：>0→達成・=0→未達成、メモのみ更新で `completed` 維持）。<br>
- 本番確認中に発見した `tasks/ai_edit.html.erb` の**ファイル取り違え**（habits 用の `@habit` 版が誤配置されていた）を修正。<br>
- 最終テスト：**867 runs / 2303 assertions / 0 failures / 0 errors**。

<br>

### 🛠️ 本番運用での不具合対応（#I-4 期間中）

<br>

本リリース後の本番運用中に発見・修正した不具合を記録します。<br>
「本番で起きた問題を、ログから原因を特定して解決する」実運用の経験です。

<br>

#### Groq フォールバックモデルの廃止対応

<br>

**症状:**<br>
週次振り返り・PMVV の AI 分析が「分析中…」のまま完了しない。<br>
数日前には「再試行が何度も」表示される現象も発生していた。

<br>

**原因（Render のログから特定）:**<br>
① メインの Gemini API が一時的に高負荷（HTTP 503）になった際、設計通り Groq へフォールバック。<br>
② しかし Groq 側のモデル `llama-3.3-70b-versatile` が **2026年8月16日に廃止**（HTTP 404 model_not_found）されていた。<br>
③ 両プロバイダ失敗となり、`#D-11` の設計に従って最大3回まで再エンキュー（＝「再試行が何度も」の正体）。<br>
　Gemini が正常な日は成功し、Gemini が混んでフォールバックした瞬間だけ露呈する間欠的な不具合だった。

<br>

**修正:**<br>
`app/services/ai_client.rb` の Groq モデル名を、公式推奨の後継 `openai/gpt-oss-120b` に更新。<br>
あわせて `ENV.fetch("GROQ_MODEL", "openai/gpt-oss-120b")` として環境変数で上書き可能にし、<br>
将来モデルが再び廃止されても環境変数の変更だけで対応できる（コード修正・再デプロイ不要）設計にした。

<br>

**得られた学び:**<br>
外部 AI API のモデルは廃止・入れ替えが起こる前提で、モデル名は環境変数に外出しすべき。<br>
フォールバック機構は「フォールバック先も失敗する」ケースまで想定して監視する必要がある。

<br>

**再発防止（#I-4 で実装）:**<br>
上記の学びを受けて、AI 分析の最終 rescue（Gemini・Groq が両方失敗する経路）に Sentry 通知を追加した。<br>
これまで 401（認証）やタイムアウトは Sentry 通知されていたが、「全プロバイダ失敗」だけは<br>
ログ出力のみで通知が無く、今回のモデル廃止（404）を開発者が即座に検知できなかった。<br>
最終 rescue に `notify_sentry(e, level: :error, extra: { phase: "all_providers_failed", groq_model: GROQ_MODEL })`<br>
を追加し、次に同種の障害（モデル廃止・API 仕様変更）が起きたときは開発者へ即通知されるようにした。<br>
Sentry に送るのは診断に必要なメタ情報（例外クラス・使用モデル名）のみで、ユーザーが入力した<br>
プロンプト本文は送らない（個人情報をエラー監視サービスに複製しない配慮）。<br>
この安全網が将来のリファクタで消えないよう、`test/services/ai_client_test.rb` に回帰テストを追加した。