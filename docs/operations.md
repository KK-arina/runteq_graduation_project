# Operations（運用・デプロイ記録）

> このファイルは HabitFlow の**デプロイ設定・本番確認チェックリスト・インフラ構成**をまとめたドキュメントです。

<br>

---

<br>

## 目次

<br>

1. [インフラ構成](#1-インフラ構成)
2. [Render 設定（render.yaml）](#2-render-設定renderyaml)
3. [環境変数一覧](#3-環境変数一覧)
4. [デプロイ手順](#4-デプロイ手順)
5. [本番確認チェックリスト](#5-本番確認チェックリスト)
6. [スリープ対策（Google Apps Script）](#6-スリープ対策google-apps-script)
7. [既知のインフラ制限](#7-既知のインフラ制限)
8. [トラブルシューティング](#8-トラブルシューティング)

<br>

---

<br>

## 1. インフラ構成

<br>

| 項目 | 内容 |
|:---|:---|
| 本番 URL | https://habitflow-web.onrender.com |
| ホスティング | Render（無料プラン） |
| DB | PostgreSQL 16（Render 無料 DB） |
| デプロイ方式 | GitHub `main` ブランチへの Push で自動デプロイ |
| CI | なし（手動テスト確認後に main へマージ） |
| コンテナ | Docker（マルチステージビルド） |
| タイムゾーン | Asia/Tokyo（JST） |

<br>

---

<br>

## 2. Render 設定（render.yaml）

<br>

```yaml
services:
  - type: web
    name: habitflow-web
    runtime: docker
    dockerfilePath: ./Dockerfile
    startCommand: bin/rails db:migrate && exec bin/rails server -b 0.0.0.0
    envVars:
      - key: RAILS_ENV
        value: production
      - key: RAILS_MASTER_KEY
        sync: false          # Render の Environment Variables で手動設定
      - key: DATABASE_URL
        fromDatabase:
          name: habitflow-db
          property: connectionString
      - key: RAILS_SERVE_STATIC_FILES
        value: true
      - key: WEB_CONCURRENCY
        value: 2

databases:
  - name: habitflow-db
    databaseName: habitflow_production
    user: habitflow
    plan: free
```

<br>

### `startCommand` の設計意図

<br>

| コマンド | 理由 |
|:---|:---|
| `bin/rails db:migrate` | デプロイのたびに未適用マイグレーションを自動実行。`migrate` は冪等なので毎回実行しても安全 |
| `exec bin/rails server` | `exec` を付けることで Rails が PID 1 になり Graceful Shutdown（SIGTERM 受信→正常終了）が機能する |
| `-b 0.0.0.0` | コンテナ外からのアクセスを受け付けるためにバインドアドレスを指定 |

<br>

---

<br>

## 3. 環境変数一覧

<br>

| 変数名 | 設定場所 | 内容 |
|:---|:---|:---|
| `RAILS_ENV` | render.yaml | `production` 固定 |
| `RAILS_MASTER_KEY` | Render Dashboard > Environment | `config/master.key` の内容をコピー（`.gitignore` 対象のため手動設定必須） |
| `DATABASE_URL` | render.yaml（fromDatabase） | Render が自動生成する PostgreSQL 接続文字列 |
| `RAILS_SERVE_STATIC_FILES` | render.yaml | `true` に設定しないと CSS / JS が配信されない |
| `WEB_CONCURRENCY` | render.yaml | Puma のワーカー数（無料プランは `2` が推奨） |
| `SEED_IN_PRODUCTION` | 手動（seeds 実行時のみ） | `true` に設定しないと seeds.rb が本番で実行されない（安全フラグ） |

<br>

---

<br>

## 4. デプロイ手順

<br>

### 通常デプロイ（自動）

<br>

```bash
# 1. main ブランチに push するだけで自動デプロイされる
git push origin main

# 2. Render の Dashboard でデプロイログを確認する
#    → https://dashboard.render.com/
#    → habitflow-web > Deploys タブ
```

<br>

### 手動デプロイ（強制再デプロイ）

<br>

Render Dashboard > habitflow-web > **Manual Deploy** > "Deploy latest commit"

<br>

### デプロイ確認手順

<br>

```bash
# デプロイ完了後、Render のログで以下を確認する
# 1. マイグレーション完了メッセージ
#    "== 20260301000001 AddUniqueIndexToWeeklyReflections: migrated"
# 2. Puma 起動メッセージ
#    "Listening on http://0.0.0.0:10000"
```

<br>

---

<br>

## 5. 本番確認チェックリスト

<br>

> Issue #37 にて実施した本番最終動作確認の記録です。<br>
> 再確認時はこのリストをもとに手動で検証してください。

<br>

### ① アクセス・認証

<br>

| # | 確認項目 | 期待動作 | ステータス |
|:---:|:---|:---|:---:|
| 1 | ランディングページ表示 | キャッチコピーとログイン/登録ボタンが表示される | ✅ |
| 2 | ユーザー新規登録 | フォーム送信後ダッシュボードにリダイレクト | ✅ |
| 3 | ログイン（正常） | `test@example.com` / `password` でログイン成功 | ✅ |
| 4 | ログイン（エラー） | 誤パスワードでエラーメッセージ表示 | ✅ |
| 5 | ログアウト | ランディングページにリダイレクト | ✅ |
| 6 | 未ログインアクセス | `/dashboard` へのアクセスがログインページにリダイレクト | ✅ |

<br>

### ② 習慣管理

<br>

| # | 確認項目 | 期待動作 | ステータス |
|:---:|:---|:---:|:---:|
| 7 | 習慣の新規作成 | フォーム送信後に習慣一覧に表示される | ✅ |
| 8 | 習慣の削除 | 論理削除され一覧から消える（DBには残る） | ✅ |
| 9 | 日次記録チェック | チェックボックスをクリックで即時保存（リロードなし） | ✅ |
| 10 | 週次進捗統計 | チェック数に応じて達成率が更新される | ✅ |
| 11 | ダッシュボード表示 | 今週の達成率・今日の習慣リストが表示される | ✅ |

<br>

### ③ 週次振り返り

<br>

| # | 確認項目 | 期待動作 | ステータス |
|:---:|:---|:---:|:---:|
| 12 | 振り返り一覧表示 | 完了済みの振り返りが新しい順に表示される | ✅ |
| 13 | 振り返り入力フォーム | 習慣ごとの達成率とコメント入力欄が表示される | ✅ |
| 14 | 振り返り保存 | 送信後、詳細ページにリダイレクトされる | ✅ |
| 15 | スナップショット確認 | 詳細ページで習慣名・目標値・達成率が正しく表示される | ✅ |

<br>

### ④ PDCA ロック

<br>

| # | 確認項目 | 期待動作 | ステータス |
|:---:|:---|:---:|:---:|
| 16 | ロック状態の確認 | 月曜 AM4:00 以降に前週振り返り未完了でロックバナーが表示される | ✅ |
| 17 | ロック中の制限 | ロック中に習慣を追加しようとするとエラーになる | ✅ |
| 18 | ロック解除 | 振り返りを完了すると緑のバナーが表示されロックが解除される | ✅ |
| 19 | 解除後の習慣追加 | 解除後は習慣の追加・削除が正常に動作する | ✅ |

<br>

### ⑤ タイムゾーン（JST）確認

<br>

| # | 確認項目 | 期待動作 | ステータス |
|:---:|:---|:---:|:---:|
| 20 | 日次記録の日付 | JST の AM4:00 基準で今日の記録が正しく表示される | ✅ |
| 21 | ロック発動時刻 | 月曜 JST AM4:00 でロックが発動する（UTC 22:00 ≠ JST AM7:00） | ✅（Issue #37 修正済み） |

<br>

### ⑥ UI / アクセシビリティ

<br>

| # | 確認項目 | 期待動作 | ステータス |
|:---:|:---|:---:|:---:|
| 22 | レスポンシブ確認 | スマホ表示でハンバーガーメニューが正常に動作する | ✅ |
| 23 | カスタムエラーページ | 存在しない URL へのアクセスで 404 ページが表示される | ✅ |

<br>

---

<br>

## 6. スリープ対策（Google Apps Script）

<br>

Render 無料プランは15分間アクセスがないとスリープします。<br>
以下の Google Apps Script を設定し、10分おきに ping を送信しています。

<br>

```javascript
function pingHabitFlow() {
  try {
    UrlFetchApp.fetch("https://habitflow-web.onrender.com/up");
    Logger.log("Ping success: " + new Date());
  } catch (e) {
    Logger.log("Ping failed: " + e.message);
  }
}
```

<br>

**設定方法:**

1. [Google Apps Script](https://script.google.com/) にアクセス
2. 上記コードをペースト
3. トリガー（⏰）→「トリガーを追加」→ 時間ベース → 10分ごと

<br>

> ⚠️ `/up` は Rails のヘルスチェックエンドポイントです（`GET /up` → 200 OK）。

<br>

---

<br>

## 7. 既知のインフラ制限

<br>

| 制限 | 内容 | 対策 |
|:---|:---|:---|
| Render 無料プランのスリープ | 15分間アクセスがないと起動に30〜60秒かかる | GAS で10分おきに ping を送信（⑥参照） |
| Render 無料 DB の有効期限 | PostgreSQL インスタンスが作成から **90日で自動削除** される | レビュー期間内に確認を完了する |
| 自動バックアップなし | Render 無料プランには DB 自動バックアップがない | 本番移行時は有料プランへ移行する |
| メール送信機能なし | パスワードリセットには Action Mailer の設定が必要 | MVP 後に実装予定 |
| ビルド時間 | コールドデプロイ時に3〜5分かかる場合がある | マージ前にテストを確認してから push する |

<br>

---

<br>

## 8. トラブルシューティング

<br>

### `Missing secret_key_base`

<br>

```
原因: RAILS_MASTER_KEY が Render の Environment Variables に設定されていない
対処: Render Dashboard > habitflow-web > Environment
     RAILS_MASTER_KEY に config/master.key の内容を設定する
```

<br>

### `PG::ConnectionBad`

<br>

```
原因: DATABASE_URL が正しく設定されていない
対処: render.yaml の fromDatabase 設定を確認する
     databases セクションの name が services の fromDatabase.name と一致しているか確認
```

<br>

### CSS / JS が全く適用されない

<br>

```
原因: RAILS_SERVE_STATIC_FILES が未設定
対処: Render の Environment Variables に
     RAILS_SERVE_STATIC_FILES=true を追加する
```

<br>

### デプロイ後にマイグレーションが適用されていない

<br>

```
原因: startCommand に db:migrate が含まれていない
対処: render.yaml の startCommand が以下になっているか確認する
     bin/rails db:migrate && exec bin/rails server -b 0.0.0.0
```

<br>

### 本番で seeds を実行したい場合

<br>

```bash
# ⚠️ 通常は実行禁止。必要な場合のみ以下の手順で実行する

# 1. Render Dashboard > habitflow-web > Environment
#    SEED_IN_PRODUCTION=true を一時的に追加する

# 2. Render の Shell から実行する
bin/rails db:seed

# 3. 実行後、SEED_IN_PRODUCTION を必ず削除する（誤実行防止）
```

<br>

---

<br>

*最終更新: 2026年3月（Issue #37 本番確認済み）*
