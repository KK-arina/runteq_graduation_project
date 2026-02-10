<br>
````

# HabitFlow ER図（MVP範囲のみ）

<br>

## MVP範囲のテーブル構成

<br>

以下の5テーブルのみを実装します：

<br>

1. **users** - ユーザー情報
2. **habits** - 習慣（チェック型のみ）
3. **habit_records** - 習慣記録
4. **weekly_reflections** - 週次振り返り
5. **weekly_reflection_habit_summaries** - 習慣サマリー（スナップショット）

<br>
```
```mermaid
erDiagram
    users ||--o{ habits : "has many"
    users ||--o{ habit_records : "has many"
    users ||--o{ weekly_reflections : "has many"
    habits ||--o{ habit_records : "has many"
    habits ||--o{ weekly_reflection_habit_summaries : "has many"
    weekly_reflections ||--o{ weekly_reflection_habit_summaries : "has many"

    users {
        bigint id PK
        string email UK "NOT NULL, ログインID"
        string encrypted_password "NOT NULL, bcrypt"
        string name "NOT NULL, max 50 chars"
        datetime remember_created_at "自動ログイン用"
        string reset_password_token UK "NULL許可"
        datetime reset_password_sent_at "NULL許可"
        datetime created_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    habits {
        bigint id PK
        bigint user_id FK "NOT NULL"
        string name "NOT NULL, max 50 chars"
        integer weekly_target "NOT NULL, >= 1, 週7回実施目標"
        datetime deleted_at "論理削除, NULL=有効"
        datetime created_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    habit_records {
        bigint id PK
        bigint user_id FK "NOT NULL"
        bigint habit_id FK "NOT NULL"
        date record_date "NOT NULL, AM4:00基準"
        boolean completed "default: false, チェック型"
        datetime created_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    weekly_reflections {
        bigint id PK
        bigint user_id FK "NOT NULL"
        date week_start_date "NOT NULL, 月曜日"
        date week_end_date "NOT NULL, 日曜日"
        text reflection_comment "max 1000 chars"
        boolean is_locked "default: false, PDCA強制ロック"
        datetime created_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    weekly_reflection_habit_summaries {
        bigint id PK
        bigint weekly_reflection_id FK "NOT NULL"
        bigint habit_id FK "NOT NULL"
        string habit_name "NOT NULL, スナップショット"
        integer weekly_target "NOT NULL, スナップショット"
        integer actual_count "NOT NULL, 実績回数"
        decimal achievement_rate "NOT NULL, 5,2, 達成率%"
        datetime created_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

<br>

---

<br>

## MVP範囲外（MVP後に実装）

<br>

以下のテーブル・カラムは**MVP後**に実装します：

<br>

### テーブル

- ❌ `tasks` - タスク管理機能
- ❌ `habit_excluded_days` - 除外日設定
- ❌ `weekly_reflection_task_summaries` - タスクサマリー
- ❌ `ai_analyses` - AI分析結果
- ❌ `ai_proposed_*` - AI提案テーブル群
- ❌ `password_reset_tokens` - パスワードリセット

<br>

### カラム

- ❌ `habits.measurement_type` - 数値型習慣
- ❌ `habits.unit` - 単位
- ❌ `habit_records.value` - 数値型実績値
- ❌ `weekly_reflections.direct_reason` - 表面的理由
- ❌ `weekly_reflections.background_situation` - 背景・状況
- ❌ `weekly_reflection_habit_summaries.measurement_type` - 測定タイプ
- ❌ `weekly_reflection_habit_summaries.unit` - 単位
- ❌ `weekly_reflection_habit_summaries.actual_value` - 数値型実績値

<br>

---

<br>

## MVP実装の注意点

<br>

### 1. チェック型のみ

- MVP版では習慣は「やった/やらない」のチェック型のみ
- 数値型（回数・時間）はMVP後に実装

<br>

### 2. 論理削除

- `habits.deleted_at` で論理削除を実装
- 過去の振り返りデータとの整合性を保持

<br>

### 3. AM4:00基準

- `habit_records.record_date` は深夜活動を前日扱い
- 例: 2026/2/11 AM3:59 → 2026/2/10として記録

<br>

### 4. PDCA強制ロック

- `weekly_reflections.is_locked` で実装
- 月曜AM4:00時点で未完了ならロック発動

<br>

### 5. スナップショット

- `weekly_reflection_habit_summaries` で振り返り時点の状態を保存
- 後で習慣を変更・削除しても過去データは不変

<br>