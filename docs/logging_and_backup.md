# HabitFlow - ログ確認・バックアップ手順書

**対象環境**: 本番環境（Render.com）<br>
**最終更新**: 2026年3月<br>
**関連 Issue**: #35

---

## 目次

1. [ログ設定の概要](#1-ログ設定の概要)
2. [Render でのログ確認方法](#2-render-でのログ確認方法)
3. [ログの読み方](#3-ログの読み方)
4. [エラー発生時の調査手順](#4-エラー発生時の調査手順)
5. [データベースバックアップの確認](#5-データベースバックアップの確認)
6. [よくあるエラーと対処法](#6-よくあるエラーと対処法)

---

## 1. ログ設定の概要

HabitFlow の本番環境では以下のログ設定を採用しています。<br>

### 設定ファイルの場所

| ファイル | 役割 |
|---|---|
| `config/environments/production.rb` | ログレベル・出力先・タグの設定 |
| `config/initializers/filter_parameters.rb` | 機密情報のフィルタリング設定 |
| `render.yaml` | `RAILS_LOG_TO_STDOUT=true` の環境変数設定 |

### 設定内容のまとめ
```ruby
# config/environments/production.rb

# ログレベル: :info（アクセスログ＋エラーを記録）
config.log_level = :info

# 出力先: STDOUT（Render のダッシュボードで確認可能）
# ENV["RAILS_LOG_TO_STDOUT"] が true のときのみ有効化
if ENV["RAILS_LOG_TO_STDOUT"].present?
  logger           = ActiveSupport::Logger.new(STDOUT)
  logger.formatter = config.log_formatter
  config.logger    = ActiveSupport::TaggedLogging.new(logger)
end

# タグ: リクエスト ID を各ログ行の先頭に付与
config.log_tags = [ :request_id ]
```

### 機密情報のフィルタリング

以下の情報はログに **[FILTERED]** と表示され、実際の値は記録されません。<br>
```ruby
# config/initializers/filter_parameters.rb
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn
]
```

ユーザーのパスワードやメールアドレスがログに残ることはありません。<br>

---

## 2. Render でのログ確認方法

### 確認手順

**① Render ダッシュボードにアクセス**<br>
[https://dashboard.render.com](https://dashboard.render.com) にログインする。<br>

**② サービスを選択**<br>
左メニューから `habitflow-web` をクリックする。<br>

**③ Logs タブを開く**<br>
上部タブの `Logs` をクリックする。<br>
```
[サービスページのタブ]
Overview | Logs | Metrics | Events | Environment | Settings
                ↑ここをクリック
```

**④ ログが表示される**<br>
リアルタイムでログが流れてくる。以下のように表示される。<br>
```
[abc123ef] Started GET "/dashboard" for 1.2.3.4 at 2026-03-01 10:00:00 +0000
[abc123ef] Processing by DashboardsController#index as HTML
[abc123ef] Completed 200 OK in 45ms (Views: 32.1ms | ActiveRecord: 8.4ms)

[def456gh] Started POST "/habits" for 1.2.3.4 at 2026-03-01 10:01:00 +0000
[def456gh] Processing by HabitsController#create as HTML
[def456gh] Completed 302 Found in 12ms
```

### ログの絞り込み（検索）

Render の Logs ページ上部の検索ボックスでキーワード絞り込みができます。<br>

| 検索キーワード | 目的 |
|---|---|
| `ERROR` | エラーログのみ表示 |
| `500` | 500エラーのみ表示 |
| `DashboardsController` | 特定のコントローラーのログのみ表示 |
| `[abc123ef]` | 特定のリクエスト ID に関するログのみ表示 |

---

## 3. ログの読み方

### 正常なリクエストのログ
```
[abc123ef] Started GET "/dashboard" for 1.2.3.4 at 2026-03-01 10:00:00 +0000
[abc123ef] Processing by DashboardsController#index as HTML
[abc123ef] Completed 200 OK in 45ms (Views: 32.1ms | ActiveRecord: 8.4ms)
```

| 部分 | 意味 |
|---|---|
| `[abc123ef]` | リクエスト ID（同一リクエストのログを追跡するため） |
| `Started GET "/dashboard"` | GET メソッドで /dashboard にアクセス |
| `for 1.2.3.4` | アクセス元の IP アドレス |
| `Completed 200 OK` | HTTP ステータス 200（正常） |
| `in 45ms` | レスポンスにかかった時間 |
| `Views: 32.1ms` | ビューの描画時間 |
| `ActiveRecord: 8.4ms` | DB クエリの合計時間（ここが長い場合は改善が必要） |

### エラーのログ
```
[xyz789ab] Started GET "/habits/999" for 1.2.3.4 at 2026-03-01 10:05:00 +0000
[xyz789ab] Processing by HabitsController#show as HTML
[xyz789ab] Parameters: {"id"=>"999"}
[xyz789ab] Completed 404 Not Found in 8ms
```

| HTTP ステータス | 意味 | よくある原因 |
|---|---|---|
| `200 OK` | 正常 | - |
| `302 Found` | リダイレクト | ログイン後の遷移など |
| `404 Not Found` | ページが見つからない | 無効な ID へのアクセス |
| `422 Unprocessable Entity` | バリデーションエラー | フォームの入力ミス |
| `500 Internal Server Error` | サーバーエラー | コードのバグ |

### 機密情報がフィルタリングされたログ
```
[abc123ef] Parameters: {"user"=>{"email"=>"[FILTERED]", "password"=>"[FILTERED]"}}
```

メールアドレスとパスワードは `[FILTERED]` と表示され、実際の値はログに残りません。<br>

---

## 4. エラー発生時の調査手順

### STEP 1: エラーのリクエスト ID を特定する

Render のログで `ERROR` または `500` を検索し、<br>
リクエスト ID（例: `[abc123ef]`）を確認する。<br>

### STEP 2: 同じリクエスト ID のログを追跡する

リクエスト ID でログを絞り込み、エラーが起きた流れを確認する。<br>
```
[abc123ef] Started POST "/weekly_reflections" for 1.2.3.4
[abc123ef] Processing by WeeklyReflectionsController#create as HTML
[abc123ef] Parameters: {"weekly_reflection"=>{"direct_reason"=>"..."}}
[abc123ef] ERROR -- : ActiveRecord::RecordInvalid: ...
[abc123ef] Completed 422 Unprocessable Entity in 15ms
```

### STEP 3: スタックトレースを読む

`ERROR` の下に続くスタックトレースで、エラーが発生したファイルと行番号を確認する。<br>
```
app/controllers/weekly_reflections_controller.rb:25:in `create'
app/controllers/application_controller.rb:10:in `require_login'
```

→ `weekly_reflections_controller.rb` の 25 行目が原因<br>

### STEP 4: ローカルで再現させて修正する

ローカル環境（開発環境）でエラーを再現させ、修正してから本番にデプロイする。<br>
```bash
# テストを実行してエラーが再現するか確認
docker compose exec web bin/rails test
```

---

## 5. データベースバックアップの確認

### Render の自動バックアップ仕様

Render の PostgreSQL データベース（無料プラン）のバックアップは以下の通りです。<br>

| 項目 | 内容 |
|---|---|
| バックアップ有無 | **無料プランはバックアップなし** |
| データ保持期間 | インスタンス存続中 |
| ストレージ容量 | 1GB まで（無料プラン） |
| 有効期限 | 作成から **90日** で自動削除 |

> ⚠️ **重要（必ず読んでください）**<br>
> Render の無料プランの PostgreSQL は **90日で自動削除** されます。<br>
> また、**自動バックアップ機能は提供されていません。**<br>
> データ消失のリスクがあるため、**本番運用・ユーザーデータを扱う場合は**<br>
> **必ず有料プランへ移行してください。**<br>
> 無料プランは学習・検証目的のみに留めることを強く推奨します。<br>

### 手動バックアップの方法

本番データを手動でバックアップする場合は以下の手順を使います。<br>

**① Render ダッシュボードで接続情報を確認**<br>
`habitflow-db` → `Info` タブ → `External Database URL` をコピーする。<br>

**② ローカルでバックアップを実行**<br>
```bash
# pg_dump でバックアップファイルを作成
pg_dump "postgresql://ユーザー名:パスワード@ホスト名/DB名" > backup_$(date +%Y%m%d).sql

# 例（External Database URL をそのまま使う場合）
pg_dump "postgres://xxxx:yyyy@oregon-postgres.render.com/habitflow_db_xxxx" > backup_20260301.sql
```

**③ バックアップファイルを安全な場所に保存**<br>
```bash
# バックアップファイルの確認
ls -la backup_*.sql
```

### バックアップから復元する方法
```bash
# バックアップファイルから復元
psql "postgresql://ユーザー名:パスワード@ホスト名/DB名" < backup_20260301.sql
```

### 現在のデータ量の確認方法
```bash
docker compose exec web bin/rails runner "
  puts '=== データ件数確認 ==='
  puts \"ユーザー数: #{User.count}\"
  puts \"習慣数: #{Habit.count}\"
  puts \"記録数: #{HabitRecord.count}\"
  puts \"振り返り数: #{WeeklyReflection.count}\"
"
```

---

## 6. よくあるエラーと対処法

### エラー①: `ActiveRecord::RecordNotFound`
```
ActiveRecord::RecordNotFound: Couldn't find Habit with 'id'=999
```

**原因**: 存在しないレコードへのアクセス<br>
**対処**: `find` → `find_by` に変更するか、`rescue` で 404 ページを表示する<br>

### エラー②: `ActionController::InvalidAuthenticityToken`
```
ActionController::InvalidAuthenticityToken
```

**原因**: CSRF トークンの不一致（フォームの二重送信、セッション切れなど）<br>
**対処**: ユーザーにページを再読み込みしてから再試行してもらう<br>

### エラー③: `PG::ConnectionBad`
```
PG::ConnectionBad: could not connect to server
```

**原因**: データベースへの接続失敗<br>
**対処**: Render ダッシュボードで `habitflow-db` のステータスを確認する<br>

### エラー④: `Errno::ENOSPC` / ストレージ不足
```
Errno::ENOSPC: No space left on device
```

**原因**: Render のストレージ（1GB）が満杯<br>
**対処**: 不要なファイルを削除するか、有料プランにアップグレードする<br>

---

*このドキュメントは Issue #35 で整備されました。*