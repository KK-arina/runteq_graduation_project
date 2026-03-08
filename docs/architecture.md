# Architecture（設計・技術実装ノート）

> HabitFlow の**サービス設計・技術選定の理由・実装詳細**をまとめた開発者向けドキュメントです。<br>
> 「なぜそう設計・実装したか」の判断根拠を記録しています。

<br>

---

<br>

## 目次

<br>

**設計編**
1. [サービス概要・作った理由](#1-サービス概要作った理由)
2. [ユーザー層・利用イメージ](#2-ユーザー層利用イメージ)
3. [既存サービスとの差別化](#3-既存サービスとの差別化)
4. [画面遷移図](#4-画面遷移図)
5. [ER図・データベース設計](#5-er図データベース設計)
6. [機能候補（MVP / 本リリース）](#6-機能候補mvp--本リリース)

**技術実装編**
7. [技術スタック・アーキテクチャ概要](#7-技術スタックアーキテクチャ概要)
8. [認証機能（Issue #5〜#9）](#8-認証機能-issue-59)
9. [習慣管理 / 日次記録（Issue #10〜#17）](#9-習慣管理--日次記録-issue-1017)
10. [ダッシュボード（Issue #18）](#10-ダッシュボード-issue-18)
11. [週次振り返り（Issue #19〜#23）](#11-週次振り返り-issue-1923)
12. [PDCA 強制ロック（Issue #24〜#25）](#12-pdca-強制ロック-issue-2425)
13. [セキュリティ対策（Issue #28）](#13-セキュリティ対策-issue-28)
14. [パフォーマンス最適化（Issue #29）](#14-パフォーマンス最適化-issue-29)
15. [アクセシビリティ対応（Issue #33）](#15-アクセシビリティ対応-issue-33)
16. [本番デプロイ設定（Issue #36）](#16-本番デプロイ設定-issue-36)
17. [タイムゾーン重大バグ修正（Issue #37）](#17-タイムゾーン重大バグ修正-issue-37)

<br>

---

<br>

## 1. サービス概要・作った理由

<br>

習慣管理・タスク管理・PDCAサイクルを統合し、AI分析によって「なぜ習慣が続かないのか」の真の原因を究明する自己成長サポートアプリです。

<br>

### 課題

<br>

私は習慣を継続したいと思っていますが、「仕事が忙しい」「疲れていた」という表面的な言い訳で習慣が途切れ、同じパターンを繰り返してしまいます。

<br>

**この「甘え」は明文化・可視化されていないから許されてしまいます。**

<br>

既存の習慣管理アプリは記録するだけで「なぜできなかったのか」の分析がなく、ToDoアプリとも別々で管理が面倒です。

<br>

### 解決アプローチ（3つのメイン機能）

<br>

| # | 機能 | 役割 |
|:---:|:---|:---|
| 1 | **週次振り返り** | できなかった理由を明文化して記録する |
| 2 | **PDCA強制ロック** | 振り返りを完了しないと新しい習慣を追加できない強制力 |
| 3 | **AI分析連携（拡張）** | 外部AIに現状を共有し「なぜ？」を3回繰り返して真の原因を究明 |

<br>

習慣管理やタスク管理は、この改善サイクルを支えるための補助機能です。

<br>

---

<br>

## 2. ユーザー層・利用イメージ

<br>

### 主要ターゲット：自分自身

<br>

- 実際に困っている課題を解決するため、必要な機能が明確
- 自分がヘビーユーザーとして使い込み、継続的に改善できる
- 平日夜にPCで確認する使い方に最適化

<br>

### 利用イメージ

<br>

**【平日夜】5〜15分：習慣チェック**

```
ダッシュボードを開く → 今日の習慣にチェックを入れる（自動保存）→ 進捗率が自動更新
```

<br>

**【日曜夜】30分〜1時間：週次振り返り**

```
週次振り返りページを開く
  → 今週の達成結果を確認
  → 振り返りコメントを入力して完了
  → PDCAロックが解除される → 来週の習慣管理が再開できる
```

<br>

---

<br>

## 3. 既存サービスとの差別化

<br>

| 機能 | Habitica | Todoist | Notion | HabitFlow |
|:---:|:---:|:---:|:---:|:---:|
| 習慣トラッキング | ◯ | △ | ◯ | ◯ |
| タスク管理 | ◯ | ◯ | ◯ | ◯（MVP後） |
| 進捗率自動計算 | ◯ | △ | 手動 | ◯ |
| PDCA振り返り | ✗ | ✗ | ◯※ | ◯ |
| AI原因分析 | ✗ | ✗ | ✗ | ◯（MVP後） |
| 改善計画自動生成 | ✗ | ✗ | ✗ | ◯（MVP後） |

<br>

> ※ Notion は振り返り用テンプレートを自分で作成・カスタマイズする必要あり

<br>

最大の差別化は **「PDCA強制ロック」** です。  
既存サービスは振り返りをしなくても何も起きませんが、HabitFlow は振り返りを完了しないと習慣の追加・削除ができません。「やらざるを得ない仕組み」を組み込んでいます。

<br>

---

<br>

## 4. 画面遷移図

<br>

**Figma（設計書）：**
https://www.figma.com/design/ayV08jHHGE18BHlp7CEEvc/Habitflow--%E6%8F%90%E5%87%BA%E7%94%A8-?node-id=0-1&p=f&t=K8IAsjx90tS8AeDN-0

<br>

### 画面一覧（全23画面）

<br>

| 画面番号 | 画面名 | URL | 備考 |
|:---:|:---|:---|:---|
| 1 | ランディングページ | `/` | — |
| 2 | ログイン | `/login` | — |
| 3 | 新規登録 | `/users/new` | — |
| 4-1〜4-4 | 初回オンボーディング | — | MVP後実装 |
| 5-1 | ダッシュボード（通常） | `/dashboard` | — |
| 5-2 | ダッシュボード（ロック中） | `/dashboard` | 警告バナー表示 |
| 6 | 習慣一覧 | `/habits` | — |
| 7 | 習慣新規作成 | `/habits/new` | — |
| 12 | 週次振り返り一覧 | `/weekly_reflections` | — |
| 13 | 週次振り返り入力 | `/weekly_reflections/new` | — |
| 15 | 週次振り返り詳細 | `/weekly_reflections/:id` | — |
| 17〜23 | 認証・エラー関連 | — | カスタムエラーページ実装済み |

<br>

### 画面遷移の重要ルール

<br>

| ルール | 詳細 |
|:---|:---|
| 日付切り替え基準 | AM4:00（深夜活動を前日として扱う） |
| PDCAロック発動 | 月曜AM4:00、前週振り返り未完了時 |
| ロック解除 | 振り返りフォームを完了して送信 |

<br>

---

<br>

## 5. ER図・データベース設計

<br>

**ER図（Gyazo）：** https://i.gyazo.com/bd25eec5ecc56490a272f788b2fd2fbd.png

**Mermaid形式の詳細：** [`docs/er-diagram-mvp.md`](er-diagram-mvp.md)

**テーブル定義書：** [`docs/database-schema-mvp.md`](database-schema-mvp.md)

<br>

### MVPテーブル構成（5テーブル）

<br>

| テーブル | 説明 | 設計上のポイント |
|:---|:---|:---|
| `users` | ユーザー情報・bcrypt認証 | `email` に UNIQUE 制約 |
| `habits` | 習慣 | 論理削除（`deleted_at`）で過去データを保持 |
| `habit_records` | 日次記録 | AM4:00基準・`(habit_id, user_id, recorded_on)` に UNIQUE 制約 |
| `weekly_reflections` | 週次振り返り | `(user_id, week_start_date)` に UNIQUE 制約 |
| `weekly_reflection_habit_summaries` | 振り返り時点のスナップショット | 習慣名・目標値を保存時点で固定し、後から変更しても過去データが正確に表示される |

<br>

### スナップショット設計の理由

<br>

振り返り保存後に習慣の名前・目標値が変更された場合でも、過去の振り返り詳細ページで正確な情報を表示できるよう `weekly_reflection_habit_summaries` に保存時点のデータを記録しています。外部キーのみを持つ設計では履歴が壊れるため採用しませんでした。

<br>

---

<br>

## 6. 機能候補（MVP / 本リリース）

<br>

### MVP で実装した機能

<br>

| # | 機能 | 状態 |
|:---:|:---|:---:|
| 1 | ユーザー認証（登録・ログイン・ログアウト、bcrypt） | ✅ |
| 2 | 習慣管理（CRUD・日次記録・進捗率自動計算） | ✅ |
| 3 | ダッシュボード（今週の進捗サマリー・今日の習慣チェックリスト） | ✅ |
| 4 | 週次振り返り（結果表示・振り返り入力・スナップショット保存） | ✅ |
| 5 | PDCAロック（月曜AM4:00発動・振り返り完了で解除） | ✅ |

<br>

### 本リリースで追加予定の機能

<br>

| # | 機能 | 優先度 |
|:---:|:---|:---:|
| 1 | タスク管理（CRUD・優先度 Must/Should/Could） | 高 |
| 2 | AI分析用プロンプト生成（「AIに共有」ボタン） | 高 |
| 3 | AI提案の自動反映（貼り付け → 一括反映） | 高 |
| 4 | パスワードリセット | 中 |
| 5 | 初回オンボーディング（4ステップガイド） | 中 |
| 6 | グラフ・チャート（習慣の推移可視化） | 低 |

<br>

---

<br>

## 7. 技術スタック・アーキテクチャ概要

<br>

### 技術スタック

<br>

| 分類 | 技術 |
|:---|:---|
| Backend | Ruby 3.4.7 / Rails 7.2.3 |
| Database | PostgreSQL 16 |
| Frontend | Hotwire（Turbo / Stimulus） |
| CSS | Tailwind CSS |
| Auth | `has_secure_password`（bcrypt） |
| Infra | Docker / Render |
| Test | Rails Minitest（221 runs, 0 failures） |

<br>

### アーキテクチャ概要

<br>

HabitFlow はモノリシックな Rails アプリケーションとして構成されています。

<br>

```
Browser
  ↓ HTML / Turbo Stream
Controller（認証・認可・ロック判定を共通処理）
  ↓
Model（ビジネスロジック・AM4:00基準の日付計算・進捗集計）
  ↓
PostgreSQL（UNIQUE制約・複合インデックス）
```

<br>

フロントエンドは **Hotwire（Turbo + Stimulus）** を利用しており、チェックボックスの即時保存など SPA に近い操作感を Rails の標準機能だけで実現しています。Node.js・React は使用せず、Importmap で JavaScript を管理しています。

<br>

### 技術選定の理由

<br>

| 技術 | 採用理由 |
|:---|:---|
| `has_secure_password`（Devise不使用） | 認証の仕組みをコードレベルで理解するため。MVP規模ではDeviseの機能（メール確認等）の大半が不要 |
| Hotwire（React不使用） | Rails標準で完結させることで複雑性を下げる。チェックボックスの即時保存程度であればTurbo Streamsで十分 |
| 論理削除（`deleted_at`） | 過去の `habit_records` や振り返りスナップショットへの参照整合性を保つため |
| スナップショット設計 | 振り返り時点の習慣名・目標値を固定し、後から習慣を変更しても過去記録が正確に表示されるようにするため |

<br>

---

<br>

## 8. 認証機能（Issue #5〜#9）

<br>

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password

  before_save :downcase_email

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }

  private

  def downcase_email
    # nil 安全化: email が nil でもエラーにならないよう to_s を挟む（Issue #37 修正）
    self.email = email.to_s.downcase
  end
end
```

<br>

```ruby
# app/controllers/application_controller.rb
def current_user
  # N+1 を防ぐため、1リクエスト内では DB アクセスを1回に限定する
  @current_user ||= User.find_by(id: session[:user_id])
end
```

<br>

```ruby
# app/controllers/sessions_controller.rb
def create
  user = User.find_by(email: params[:email].to_s.downcase)
  if user&.authenticate(params[:password])
    # セッション固定攻撃対策: ログイン前後でセッション ID を再生成する
    reset_session
    session[:user_id] = user.id
    redirect_to dashboard_path
  else
    flash.now[:alert] = "メールアドレスまたはパスワードが正しくありません"
    render :new, status: :unprocessable_entity
  end
end
```

<br>

---

<br>

## 9. 習慣管理 / 日次記録（Issue #10〜#17）

<br>

### AM4:00 基準の日付計算

<br>

深夜活動（AM3:59まで）を前日として扱うため、専用メソッドで「今日」を計算します。

<br>

```ruby
# app/models/habit_record.rb
def self.today_date
  current_time = Time.current
  if current_time.hour < 4
    current_time.to_date - 1.day
  else
    current_time.to_date
  end
end

# ユニーク制約: 同じ習慣を同じ日に2回記録できない
# モデルバリデーションだけでは競合状態で抜けがあるため DB レベルでも制約を設ける
validates :recorded_on, uniqueness: { scope: [:habit_id, :user_id] }
```

<br>

```ruby
# db/migrate/xxxx_add_unique_index_to_habit_records.rb
class AddUniqueIndexToHabitRecords < ActiveRecord::Migration[7.2]
  def change
    add_index :habit_records,
              [:habit_id, :user_id, :recorded_on],
              unique: true,
              name: "index_habit_records_on_habit_user_recorded",
              if_not_exists: true
  end
end
```

<br>

### Turbo Streams による即時保存（楽観的 UI）

<br>

チェックボックスをクリックした瞬間に UI を更新し、バックグラウンドでサーバーに保存します。失敗時はチェックを元に戻します。

<br>

```javascript
// app/javascript/controllers/habit_record_controller.js
toggle(event) {
  const checkbox = event.target
  const isChecked = checkbox.checked

  // 楽観的 UI: サーバーレスポンスを待たずに即座に見た目を更新
  this.updateProgressBar(checkbox.dataset.habitId, isChecked)

  fetch(`/habit_records`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
    },
    body: JSON.stringify({ habit_id: checkbox.dataset.habitId, checked: isChecked })
  }).then(response => {
    if (!response.ok) {
      // 失敗時: チェックと進捗バーを元に戻す
      checkbox.checked = !isChecked
      this.updateProgressBar(checkbox.dataset.habitId, !isChecked)
    }
  })
}
```

<br>

### 週次進捗統計の N+1 対策

<br>

```ruby
# app/models/habit.rb
def weekly_progress_stats(week_start: Date.current.beginning_of_week(:monday))
  # 今週の記録を1クエリで取得（N+1 防止）
  records_count = habit_records
    .where(recorded_on: week_start..(week_start + 6.days))
    .count

  {
    achieved: records_count,
    target:   frequency_per_week,
    rate:     frequency_per_week > 0 ? (records_count.to_f / frequency_per_week * 100).round : 0
  }
end
```

<br>

---

<br>

## 10. ダッシュボード（Issue #18）

<br>

ダッシュボードは複数の習慣・記録を表示するため N+1 が発生しやすいです。コントローラーで一括集計してハッシュで View に渡す設計にしました。

<br>

```ruby
# app/controllers/dashboards_controller.rb
def show
  @habits = current_user.habits.active.order(:created_at)
  today   = HabitRecord.today_date
  week_start = today.beginning_of_week(:monday)

  # 今日の記録を habit_id をキーにしたハッシュで取得（1クエリ）
  @today_records_hash = current_user.habit_records
    .where(recorded_on: today)
    .index_by(&:habit_id)

  # 今週の記録数を habit_id をキーにしたハッシュで取得（1クエリ）
  @weekly_counts_hash = current_user.habit_records
    .where(recorded_on: week_start..(week_start + 6.days))
    .group(:habit_id)
    .count

  @is_locked = current_user.pdca_locked?
end
```

<br>

---

<br>

## 11. 週次振り返り（Issue #19〜#23）

<br>

### スナップショット保存

<br>

```ruby
# app/models/weekly_reflection.rb
def complete!(habit_summaries_data)
  transaction do
    habit_summaries_data.each do |data|
      # 冪等設計: 既存のものは更新、なければ作成
      weekly_reflection_habit_summaries.find_or_initialize_by(habit_id: data[:habit_id]).tap do |s|
        s.assign_attributes(
          habit_name:       data[:habit_name],    # 保存時点の習慣名を記録
          target_count:     data[:target_count],  # 保存時点の目標値を記録
          achieved_count:   data[:achieved_count],
          achievement_rate: data[:achievement_rate]
        )
        s.save!
      end
    end

    was_locked = user.pdca_locked?
    update!(completed_at: Time.current, is_locked: false)
    was_locked  # ロック解除通知の表示判定に使用
  end
end
```

<br>

### `form_with` の POST 強制設定

<br>

週次振り返りは「更新」ではなく「完了処理」として設計しているため、`update` アクションを使わず `complete` というカスタム POST アクションで送信します。`form_with model:` に `persisted?=true` のレコードを渡すと自動で PATCH になるため、`url:` と `method:` を明示しています（Issue #37 修正）。

<br>

```erb
<%= form_with url: complete_weekly_reflection_path(@weekly_reflection),
              method: :post do |f| %>
```

<br>

---

<br>

## 12. PDCA 強制ロック（Issue #24〜#25）

<br>

```ruby
# app/models/user.rb
def pdca_locked?
  now = Time.current
  monday_4am = now.beginning_of_week(:monday).change(hour: 4)
  return false if now < monday_4am  # 月曜 AM4:00 前は常にアンロック

  last_week_start = monday_4am.to_date - 7.days
  reflection = weekly_reflections.find_by(week_start_date: last_week_start)
  reflection.nil? || reflection.completed_at.nil?
end
```

<br>

UI だけでブロックすると API ツール等で突破されるため、コントローラーでもサーバー側でブロックしています。

<br>

```ruby
# app/controllers/habits_controller.rb
before_action :require_unlocked, only: [:create, :destroy]

def require_unlocked
  if current_user.pdca_locked?
    redirect_to habits_path, alert: "振り返りを完了するまで習慣を追加・削除できません"
  end
end
```

<br>

---

<br>

## 13. セキュリティ対策（Issue #28）

<br>

| 対策 | 実装内容 |
|:---|:---|
| CSRF | Rails 標準の `authenticity_token` + ログイン時 `reset_session` |
| XSS | ERB の自動 HTML エスケープ・CSP（nonce 方式） |
| SQL インジェクション | Active Record のプレースホルダー使用（生 SQL なし） |
| 認可制御 | `current_user.habits.find` で他ユーザーのデータへのアクセスを遮断 |
| セッション | `httponly: true` / `secure: true`（本番）/ `same_site: :lax` |

<br>

```ruby
# config/initializers/content_security_policy.rb
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self, :https
  policy.script_src  :self, :https, :nonce  # nonce 方式: unsafe-inline より安全
  policy.style_src   :self, :https, :nonce
  policy.object_src  :none
end

Rails.application.config.content_security_policy_nonce_generator =
  ->(_request) { SecureRandom.base64(16) }
```

<br>

---

<br>

## 14. パフォーマンス最適化（Issue #29）

<br>

| 最適化 | 内容 |
|:---|:---|
| Bullet gem | development 環境で N+1 を自動検出 |
| `index_by` による一括取得 | 習慣ごとの今日の記録を1クエリで取得しハッシュ化 |
| `group(:habit_id).count` | 週次記録数を GROUP BY の1クエリで集計 |
| `exists?` への置き換え | 存在確認だけなら `SELECT 1 LIMIT 1` で十分 |
| 複合インデックス追加 | `habit_records(user_id, recorded_on, habit_id)` の3カラム複合インデックス |

<br>

---

<br>

## 15. アクセシビリティ対応（Issue #33）

<br>

WCAG 2.1 AA 基準に準拠しています。

<br>

| 対応 | 実装 |
|:---|:---|
| スキップリンク | `<a href="#main-content" class="sr-only focus:not-sr-only">` をヘッダー直後に配置 |
| ARIA ランドマーク | `<main role="main">` / `<nav role="navigation">` |
| `aria-live` | トースト通知をスクリーンリーダーに読み上げさせる |
| `aria-current` | ナビゲーションの現在ページを明示 |
| フォーカスリング | `focus:ring-2 focus:ring-blue-500` を全インタラクティブ要素に適用 |

<br>

---

<br>

## 16. 本番デプロイ設定（Issue #36）

<br>

```yaml
# render.yaml（抜粋）
startCommand: bin/rails db:migrate && exec bin/rails server -b 0.0.0.0
```

<br>

| コマンド | 理由 |
|:---|:---|
| `bin/rails db:migrate` | デプロイのたびに未適用マイグレーションを自動実行（冪等なので毎回実行して安全） |
| `exec bin/rails server` | Rails が PID 1 になり Graceful Shutdown（SIGTERM 受信→正常終了）が機能する |
| `-b 0.0.0.0` | コンテナ外からのアクセスを受け付けるためにバインドアドレスを指定 |

<br>

---

<br>

## 17. タイムゾーン重大バグ修正（Issue #37）

<br>

### 発覚した問題

<br>

本番環境で PDCA ロックが JST ではなく UTC（9時間ズレ）で発動していました。

<br>

**原因**: `config/application.rb` に `config.time_zone = "Tokyo"` が設定されていなかった。

<br>

### 修正内容

<br>

```ruby
# config/application.rb に追加
config.time_zone = "Tokyo"
config.active_record.default_timezone = :local  # DB に JST で保存する
```

<br>

### 教訓

<br>

| 教訓 | 詳細 |
|:---|:---|
| `config.time_zone` は最初に設定する | 未設定で Rails が UTC で動作し、本番でロック時刻が9時間ズレる |
| `Time.current` / `Date.current` を使う | `Time.now` はタイムゾーン設定が無視される |
| `form_with` の HTTP メソッド自動判定に注意 | `persisted?=true` のレコードを渡すと自動で PATCH になる。routes に `update` がない設計では `url:` と `method:` を明示する |
| テストでは値でレコードを特定する | `order(created_at: :desc).first` は fixtures の順序が不安定。`find_by(name:)` で直接特定する |

<br>

---

<br>

*最終更新: 2026年3月（Issue #37 修正内容を反映）*
