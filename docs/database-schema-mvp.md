# HabitFlow データベース設計書（MVP範囲）

<br>

## テーブル一覧

<br>

| No | テーブル名 | 用途 |
|----|-----------|------|
| 1 | users | ユーザー情報 |
| 2 | habits | 習慣（チェック型のみ） |
| 3 | habit_records | 日次の習慣記録 |
| 4 | weekly_reflections | 週次振り返り |
| 5 | weekly_reflection_habit_summaries | 習慣サマリー（スナップショット） |

<br>

---

<br>

## 1. users（ユーザー）

<br>

**用途**: ユーザー情報の管理

<br>

| カラム名 | 型 | NULL | デフォルト | 説明 |
|---------|-----|------|-----------|------|
| id | bigint | NOT NULL | auto | 主キー |
| email | string(255) | NOT NULL | - | メールアドレス（ログインID） |
| encrypted_password | string(255) | NOT NULL | - | bcryptでハッシュ化されたパスワード |
| name | string(50) | NOT NULL | - | ユーザー名 |
| remember_created_at | datetime | NULL | - | 自動ログイン用タイムスタンプ |
| reset_password_token | string(255) | NULL | - | パスワードリセットトークン（MVP後に実装） |
| reset_password_sent_at | datetime | NULL | - | リセットメール送信日時（MVP後に実装） |
| created_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 作成日時 |
| updated_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 更新日時 |

<br>

**インデックス**:
```sql
PRIMARY KEY (id)
UNIQUE INDEX index_users_on_email (email)
INDEX index_users_on_reset_password_token (reset_password_token)
```

<br>

**バリデーション**:
- `email`: 必須、メール形式、一意性
- `name`: 必須、50文字以内
- `password`: 必須、8文字以上（登録時のみ）

<br>

**マイグレーションコマンド**:
```bash
rails g model User name:string email:string:uniq encrypted_password:string remember_created_at:datetime reset_password_token:string:uniq reset_password_sent_at:datetime
```

<br>

**注意事項**:
- reset_password_token / reset_password_sent_at はMVPでは未使用（Phase2以降で実装予定）

<br>

---

<br>

## 2. habits（習慣）

<br>

**用途**: ユーザーが管理する習慣の定義（MVP版：チェック型のみ）

<br>

| カラム名 | 型 | NULL | デフォルト | 説明 |
|---------|-----|------|-----------|------|
| id | bigint | NOT NULL | auto | 主キー |
| user_id | bigint | NOT NULL | - | ユーザーID（外部キー） |
| name | string(50) | NOT NULL | - | 習慣名 |
| weekly_target | integer | NOT NULL | - | 週次目標値（7日で何回実施するか） |
| deleted_at | datetime | NULL | NULL | 論理削除フラグ（NULLなら有効） |
| created_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 作成日時 |
| updated_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 更新日時 |

<br>

**インデックス**:
```sql
PRIMARY KEY (id)
INDEX index_habits_on_user_id (user_id)
INDEX index_habits_on_deleted_at (deleted_at)
```

<br>

**外部キー**:
```sql
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
```

<br>

**バリデーション**:
- `name`: 必須、50文字以内
- `weekly_target`: 必須、1以上7以下の整数

<br>

**スコープ**:
```ruby
scope :active, -> { where(deleted_at: nil) }
```

<br>

**マイグレーションコマンド**:
```bash
rails g model Habit user:references name:string weekly_target:integer deleted_at:datetime
```

<br>

**注意事項**:
- MVP版では「チェック型」のみ実装
- `measurement_type`, `unit` カラムはMVP後に追加
- 論理削除により過去の振り返りデータとの整合性を保持

<br>

---

<br>

## 3. habit_records（習慣記録）

<br>

**用途**: 日次の習慣実施記録

<br>

| カラム名 | 型 | NULL | デフォルト | 説明 |
|---------|-----|------|-----------|------|
| id | bigint | NOT NULL | auto | 主キー |
| user_id | bigint | NOT NULL | - | ユーザーID（外部キー） |
| habit_id | bigint | NOT NULL | - | 習慣ID（外部キー） |
| record_date | date | NOT NULL | - | 記録日（AM4:00基準） |
| completed | boolean | NOT NULL | false | 完了フラグ（チェック型） |
| created_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 作成日時 |
| updated_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 更新日時 |

<br>

**インデックス**:
```sql
PRIMARY KEY (id)
UNIQUE INDEX index_habit_records_unique (user_id, habit_id, record_date)
INDEX index_habit_records_on_user_id (user_id)
INDEX index_habit_records_on_habit_id (habit_id)
INDEX index_habit_records_on_record_date (record_date)
```

<br>

**外部キー**:
```sql
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
```

<br>

**バリデーション**:
- `record_date`: 必須
- `completed`: boolean型（デフォルト false）
- ユニーク制約: `user_id + habit_id + record_date`

<br>

**マイグレーションコマンド**:
```bash
rails g model HabitRecord user:references habit:references record_date:date completed:boolean
```

<br>

**マイグレーションファイルに追加**:
```ruby
add_index :habit_records, [:user_id, :habit_id, :record_date], unique: true, name: 'index_habit_records_unique'
```

<br>

**注意事項**:
- **AM4:00を日付の境界**とする（深夜活動を前日扱い）
- 実装例:
```ruby
  # record_date算出ロジック
  def self.current_record_date
    now = Time.current
    cutoff_time = now.beginning_of_day + 4.hours
    now < cutoff_time ? (now - 1.day).to_date : now.to_date
  end
```
- 1ユーザー・1習慣・1日付につき1レコードのみ（UNIQUE制約）
- MVP版では `value` カラムなし（数値型はMVP後）

<br>

**設計メモ**:
- habit_records.user_id は habits から導出可能だが、検索性能向上と将来の拡張性（習慣共有・コピー等）を考慮して保持する

<br>

---

<br>

## 4. weekly_reflections（週次振り返り）

<br>

**用途**: 週単位の振り返り記録（PDCA強制ロック機能の核心）

<br>

| カラム名 | 型 | NULL | デフォルト | 説明 |
|---------|-----|------|-----------|------|
| id | bigint | NOT NULL | auto | 主キー |
| user_id | bigint | NOT NULL | - | ユーザーID（外部キー） |
| week_start_date | date | NOT NULL | - | 対象週の開始日（月曜日） |
| week_end_date | date | NOT NULL | - | 対象週の終了日（日曜日） |
| reflection_comment | text | NULL | - | 振り返りコメント（1000文字以内） |
| is_locked | boolean | NOT NULL | false | ロック状態フラグ（PDCA強制ロック） |
| created_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 作成日時 |
| updated_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 更新日時 |

<br>

**インデックス**:
```sql
PRIMARY KEY (id)
UNIQUE INDEX index_weekly_reflections_unique (user_id, week_start_date)
INDEX index_weekly_reflections_on_user_id (user_id)
INDEX index_weekly_reflections_on_week_start_date (week_start_date)
```

<br>

**外部キー**:
```sql
FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
```

<br>

**バリデーション**:
- `reflection_comment`: 1000文字以内
- `week_start_date`: 必須、月曜日であること
- `week_end_date`: 必須、日曜日であること、week_start_dateの6日後
- ユニーク制約: `user_id + week_start_date`

<br>

**マイグレーションコマンド**:
```bash
rails g model WeeklyReflection user:references week_start_date:date week_end_date:date reflection_comment:text is_locked:boolean
```

<br>

**マイグレーションファイルに追加**:
```ruby
add_index :weekly_reflections, [:user_id, :week_start_date], unique: true, name: 'index_weekly_reflections_unique'
```

<br>

**注意事項**:
- `is_locked` は PDCA強制ロック機能で使用
- 週の範囲は**月曜日AM4:00〜日曜日AM3:59**
- ISO週（週の開始は月曜日）に準拠した運用
- MVP版では `direct_reason`, `background_situation` カラムなし（簡素化）
- week_end_date は week_start_date + 6日で常に導出可能
- MVPでは可読性を優先して保持しているが、将来的には計算属性として扱うことも可能

<br>

---

<br>

## 5. weekly_reflection_habit_summaries（習慣サマリー）

<br>

**用途**: 振り返り時点の習慣実績スナップショット（データの不変性保証）

<br>

| カラム名 | 型 | NULL | デフォルト | 説明 |
|---------|-----|------|-----------|------|
| id | bigint | NOT NULL | auto | 主キー |
| weekly_reflection_id | bigint | NOT NULL | - | 週次振り返りID（外部キー） |
| habit_id | bigint | NOT NULL | - | 習慣ID（外部キー） |
| habit_name | string(50) | NOT NULL | - | 習慣名（スナップショット） |
| weekly_target | integer | NOT NULL | - | 週次目標値（スナップショット） |
| actual_count | integer | NOT NULL | 0 | 実績回数 |
| achievement_rate | decimal(5,2) | NOT NULL | 0.00 | 達成率（％） |
| created_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 作成日時 |
| updated_at | datetime | NOT NULL | CURRENT_TIMESTAMP | 更新日時 |

<br>

**インデックス**:
```sql
PRIMARY KEY (id)
UNIQUE INDEX index_wrhs_unique (weekly_reflection_id, habit_id)
INDEX index_weekly_reflection_habit_summaries_on_habit (habit_id)
```

<br>

**外部キー**:
```sql
FOREIGN KEY (weekly_reflection_id) REFERENCES weekly_reflections(id) ON DELETE CASCADE
FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
```

<br>

**バリデーション**:
- `habit_name`: 必須
- `weekly_target`: 必須、1以上
- `actual_count`: 必須、0以上
- `achievement_rate`: 必須、0.00〜100.00

<br>

**マイグレーションコマンド**:
```bash
rails g model WeeklyReflectionHabitSummary weekly_reflection:references habit:references habit_name:string weekly_target:integer actual_count:integer achievement_rate:decimal
```

<br>

**マイグレーションファイルに追加**:
```ruby
change_column :weekly_reflection_habit_summaries, :achievement_rate, :decimal, precision: 5, scale: 2
```

<br>

**注意事項**:
- **スナップショット設計**: 習慣が後で編集・削除されても、振り返り時点の状態を保持
- `achievement_rate` の計算式: `(actual_count / weekly_target) * 100`
- MVP版では `measurement_type`, `unit`, `actual_value` カラムなし（チェック型のみ）

<br>

**設計メモ**:
- weekly_reflection_id × habit_id は業務上一意
- 重複防止のため UNIQUE INDEX を設定している
- achievement_rate は (actual_count / weekly_target) * 100 で算出される値
- MVPでは DB default を使用しているが、将来的にはアプリケーション側で必ず計算して代入する方針

<br>

---

<br>

## インデックス設計サマリー

<br>

### 主キー（全テーブル）
```sql
PRIMARY KEY (id)
```

<br>

### 一意性制約（UNIQUE INDEX）

<br>

| テーブル | カラム | 用途 |
|---------|--------|------|
| users | email | メールアドレスの一意性 |
| users | reset_password_token | トークンの一意性 |
| habit_records | (user_id, habit_id, record_date) | 重複記録防止 |
| weekly_reflections | (user_id, week_start_date) | 1週1振り返り保証 |

<br>

### 外部キー検索用（INDEX）

<br>

| テーブル | カラム | 用途 |
|---------|--------|------|
| habits | user_id | ユーザーの習慣一覧取得 |
| habit_records | user_id | ユーザーの記録一覧取得 |
| habit_records | habit_id | 習慣の記録一覧取得 |
| weekly_reflections | user_id | ユーザーの振り返り一覧取得 |
| weekly_reflection_habit_summaries | weekly_reflection_id | 振り返りの習慣サマリー取得 |
| weekly_reflection_habit_summaries | habit_id | 習慣の履歴取得 |

<br>

### 論理削除検索用（INDEX）

<br>

| テーブル | カラム | 用途 |
|---------|--------|------|
| habits | deleted_at | 有効な習慣のみ取得 |

<br>

### 日付検索用（INDEX）

<br>

| テーブル | カラム | 用途 |
|---------|--------|------|
| habit_records | record_date | 日付範囲での検索 |
| weekly_reflections | week_start_date | 週範囲での検索 |

<br>

---

<br>

## リレーションシップ図（テキスト形式）

<br>
```
users (1) ----< (N) habits
  ↓
  | (1) ----< (N) habit_records
  ↓                   ↑
  | (1) ----< (N)     | (N) >---- (1) habits
  ↓
  | (1) ----< (N) weekly_reflections
                ↓
                | (1) ----< (N) weekly_reflection_habit_summaries
                                        ↑
                                        | (N) >---- (1) habits
```

<br>

---

<br>

## マイグレーション実行順序

<br>
```bash
# 1. ユーザーテーブル
rails g model User name:string email:string:uniq encrypted_password:string remember_created_at:datetime reset_password_token:string:uniq reset_password_sent_at:datetime

# 2. 習慣テーブル
rails g model Habit user:references name:string weekly_target:integer deleted_at:datetime

# 3. 習慣記録テーブル
rails g model HabitRecord user:references habit:references record_date:date completed:boolean

# 4. 週次振り返りテーブル
rails g model WeeklyReflection user:references week_start_date:date week_end_date:date reflection_comment:text is_locked:boolean

# 5. 習慣サマリーテーブル
rails g model WeeklyReflectionHabitSummary weekly_reflection:references habit:references habit_name:string weekly_target:integer actual_count:integer achievement_rate:decimal

# マイグレーション実行
rails db:migrate
```

<br>

---

<br>

## 正規化レベル

<br>

本設計は**第3正規形**に準拠しています：

<br>

- ✅ **第1正規形**: すべての属性が原子値
- ✅ **第2正規形**: 部分関数従属を排除
- ✅ **第3正規形**: 推移的関数従属を排除

<br>

`weekly_reflection_habit_summaries` は意図的な非正規化（スナップショット）であり、データの不変性を担保するための設計です。

<br>

---

<br>

## MVP後の拡張予定

<br>

### テーブル追加

- `tasks` - タスク管理機能
- `habit_excluded_days` - 除外日設定
- `ai_analyses` - AI分析結果
- `password_reset_tokens` - パスワードリセット

<br>

### カラム追加

- `habits.measurement_type`, `habits.unit` - 数値型習慣
- `habit_records.value` - 数値型実績値
- `weekly_reflections.direct_reason`, `weekly_reflections.background_situation` - 詳細な振り返り

<br>