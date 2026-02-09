# HabitFlow（ハビットフロー）

<br>

## サービス概要

習慣管理・タスク管理・PDCAサイクルを統合し、AI分析によって「なぜ習慣が続かないのか」の真の原因を究明する自己成長サポートアプリです。

運動・読書・勉強などの様々な習慣を記録し、週次でPDCAサイクルを回すことで継続的な改善を実現します。

「できなかった言い訳」を可視化し、AIによる厳しい分析で自分に甘えを許さない仕組みを提供します。

<br>

---

<br>

## このサービスへの思い・作りたい理由

<br>

### 課題点

私は習慣を継続したいと思っていますが、「仕事が忙しい」「疲れていた」という表面的な言い訳で習慣が途切れ、同じパターンを繰り返してしまいます。週末に振り返っても「まあ仕方ない」で済ませてしまい、根本的な改善ができていません。

**この「甘え」は明文化・可視化されていないから許されてしまいます。** 記録も残らず、振り返りもしないから、同じ失敗を繰り返します。

既存の習慣管理アプリは記録するだけで「なぜできなかったのか」の分析がなく、ToDoアプリとも別々で管理が面倒です。

<br>

### 解決するメイン機能

**本アプリの最優先課題は「甘え」を可視化し、根本的な改善サイクルを回すことです。**

<br>

そのための3つのメイン機能：

1. **週次振り返り機能** - できなかった理由を明文化して記録
2. **AI分析連携機能** - 外部AIに現状を共有し、「なぜ？」を3回繰り返して真の原因を究明
3. **改善計画の自動反映機能** - AI提案を貼り付けるだけで、改善タスクが自動追加される

<br>

習慣管理やタスク管理は、この改善サイクルを支えるための補助機能です。

**優しく励ますアプリではなく、厳しく現実を突きつけるアプリを作りたい。**

<br>

---

<br>

## ユーザー層について

<br>

### 主要ターゲット：自分自身

<br>

**選んだ理由：**
- 実際に困っている課題を解決するため、必要な機能が明確
- 自分がヘビーユーザーとして使い込み、継続的に改善できる
- 平日夜にPCで確認する使い方に最適化

<br>

**将来的な展開（MVP後）：**

習慣を継続したい社会人、自己成長に取り組む学生、フリーランスなどに展開可能ですが、MVP段階では自分が満足して使えることを最優先とします。

<br>

---

<br>

## サービスの利用イメージ

<br>

### 【平日夜】5〜15分：習慣チェック

1. 今日の習慣をチェック（例：運動、読書、勉強など）
2. タスクを完了チェック
3. 進捗率が自動更新される

<br>

### 【日曜夜】30分〜1時間：週次振り返り

1. 今週の結果を確認（各習慣の達成率）
2. 振り返り入力（うまくいかなかったこと、表面的な理由、背景）
3. 「AIに共有」ボタンで現状サマリーをコピー
4. 外部のAIサービス（ChatGPT/Claude/Gemini等）に貼り付けて分析依頼
5. AIの回答（真の原因、改善タスク）をコピー
6. アプリに貼り付けて「一括反映」→ 自動的にタスク追加・目標更新

<br>

### 得られる価値

- 習慣の継続率向上（進捗可視化とPDCAサイクル）
- 真の原因発見（AIが「なぜ？」を3回繰り返して根本原因を究明）
- 具体的な改善（「もっと頑張ろう」ではなく、実行可能なタスクに変換）

<br>

---

<br>

## ユーザーの獲得について

<br>

**MVP段階：**

自分自身がヘビーユーザーとして3〜6ヶ月使い込み、習慣の継続率は上がるか、AI分析は役立つか、毎日続けられるかを検証します。

<br>

**MVP後：**

技術ブログ（Qiita/Zenn）での記事化、GitHub公開、SNSでの情報発信、友人への紹介を検討しますが、ユーザー獲得は二の次。まずは自分が満足できるものを作ることに集中します。

<br>

---

<br>

## サービスの差別化ポイント・推しポイント

<br>

### 既存サービスとの比較

| 機能 | Habitica | Todoist | Notion | HabitFlow |
|:---:|:---:|:---:|:---:|:---:|
| 習慣トラッキング | ◯ | △ | ◯ | ◯ |
| タスク管理 | ◯ | ◯ | ◯ | ◯ |
| 進捗率自動計算 | ◯ | △ | 手動 | ◯ |
| PDCA振り返り | ✗ | ✗ | ◯※ | ◯ |
| AI原因分析 | ✗ | ✗ | ✗ | ◯ |
| 改善計画自動生成 | ✗ | ✗ | ✗ | ◯ |

> ※Notionは振り返り用テンプレートを自分で作成・カスタマイズする必要あり

<br>

**比較対象の選定理由：**
- **Habitica：** 習慣トラッキングで有名。習慣・日課・To-Doを管理可能だが、PDCA振り返りや分析機能はない
- **Todoist：** タスク管理の定番。繰り返しタスクで習慣も管理できるが専用機能ではない
- **Notion：** 万能ツール。習慣トラッキングも可能だが、PDCA構造は自分で作る必要があり初期設定に手間がかかる

<br>

### 明確な差別化ポイント

<br>

#### 1. 習慣×タスク×PDCAの統合

- **既存：** 習慣管理とタスク管理が別々、PDCAは手動で構築が必要
- **HabitFlow：** 最初から統合され、設定不要ですぐ使える

<br>

#### 2. AI活用による真の原因究明

- **既存：** 「疲れていた」で終わり
- **HabitFlow：** AIが「なぜ？」を3回繰り返し、根本原因を究明

<br>

#### 3. 改善計画の自動生成・反映

- **既存：** 改善策を考えても実行計画を立てる手間で結局やらない
- **HabitFlow：** AI提案を貼り付けるだけで、タスク追加・進捗再計算が自動実行

<br>

#### 4. 柔軟な進捗管理

- **既存：** 日数ベースの管理のみ
- **HabitFlow：** 習慣ごとに測定タイプを選択（毎日実施・冊数・時間）

<br>

---

<br>

## 機能候補

<br>

### MVPリリース時に作りたい機能

1. **ユーザー認証機能** - ユーザー登録・ログイン・ログアウト、パスワード暗号化（bcrypt）
2. **習慣管理機能** - 習慣のCRUD、測定タイプ（毎日実施/冊数/時間）、日次記録、進捗率の自動計算
3. **月次目標設定機能** - 月初に目標を設定、できない日の事前登録、達成状況の表示
4. **タスク管理機能** - タスクのCRUD、優先度（Must/Should/Could）、タイプ（習慣関連/通常/改善タスク）
5. **ダッシュボード** - 今月の進捗サマリー、今日の習慣チェックリスト、今日のタスク一覧
6. **週次振り返り機能** - 今週の結果表示、振り返り入力フォーム、保存機能
7. **AI分析用プロンプト生成機能** - 「AIに共有」ボタンで最適化されたプロンプトをクリップボードにコピー
8. **AI提案の自動反映機能** - AIの回答を貼り付けるテキストエリア、「一括反映」ボタン、パース処理

<br>

**MVPとして成立する理由：**

習慣の記録、進捗率の自動計算、タスクの一元管理、週次振り返り、AI分析で真の原因究明、改善計画の自動反映 → 「習慣×タスク×PDCA」の本質的な価値を提供できる

<br>

**実装がシンプルな理由：**
- 使用技術：Rails 7.2のみ（新しいフレームワーク不要）
- 実装内容：基本的なCRUD操作が中心
- 複雑な処理：文字列パース（Ruby標準ライブラリ）、日付計算のみ
- 外部API連携：なし（AIはコピペ方式）

<br>

### 開発期間：12週間（約3ヶ月）

<br>

**前提条件：**

- Rails初心者（Runteqカリキュラム学習中）
- 週15〜20時間の開発時間確保
- 2026年3月までに完成
- **Docker環境での開発**（ローカル環境の差異を排除）

<br>

#### Phase 1（2週間）：基礎学習と環境構築、認証機能

- **Week 1：** 
  - **Docker環境構築**（1-2日）
    - Dockerfile, docker-compose.yml作成
    - Rails + PostgreSQL + Tailwind CSS環境の立ち上げ
    - `docker compose up`でアプリ起動確認
  - **Rails基礎の復習**（1日）
  - **Hotwire/Stimulus学習**（2〜3日で基礎と動作確認）
    - Turbo Framesの基本
    - Turbo Streamsの基本
    - Stimulusコントローラーの基本
- **Week 2：** ユーザー認証実装（bcrypt使用）

<br>

#### Phase 2（4週間）：コア機能の実装

- **Week 3：** 習慣管理機能
- **Week 4：** 日次記録機能
- **Week 5：** タスク管理機能
- **Week 6：** ダッシュボード

<br>

#### Phase 3（4週間）：PDCA機能の実装

- **Week 7：** 月次目標設定
- **Week 8：** 進捗率の自動計算
- **Week 9：** 週次振り返り機能
- **Week 10：** AI連携機能（プロンプト生成、パース処理）

<br>

#### Phase 4（2週間）：仕上げとデプロイ

- **Week 11：** UI改善とバグ修正
- **Week 12：** 最終調整、Renderへのデプロイ、動作確認

<br>

**技術検証について：**
- Week 1でHotwire/Stimulusの基礎学習と動作確認を実施
- 使用技術はRails標準機能のみ（CRUD操作、日付計算、文字列パース）
- 外部API連携なし（AIはコピペ方式）
- OpenAI Whisper、ffmpeg等は使用しません

<br>

**つまずきやすいポイントと対策：**
- **データベース設計** → ER図を事前に作成、講師レビュー
- **進捗率の計算ロジック** → 小さく分けて実装、ログで確認
- **JSON型の扱い** → PostgreSQLのJSON型について学習、簡単な例から試す
- **文字列パース処理** → AI出力フォーマットを厳密に定義、テストデータで確認
- **Hotwire/Stimulus** → Week 1で基礎学習と動作確認（2〜3日）

<br>

### 本リリースまでに作りたい機能

MVPを3〜6ヶ月使い込んだ後、実際に困った課題に基づいて以下を検討：
- グラフ・チャート（習慣の推移可視化）
- 月次振り返り機能
- ダークモード
- スマホ対応（レスポンシブ、PWA化）

<br>

---

<br>

## 使用技術スタック

<br>

### 開発環境
- **Docker**: 24.0以上
- **Docker Compose**: 2.20以上

<br>

### バックエンド

#### Ruby 3.4.x
- 本プロジェクトで使用
- Dockerイメージでバージョン固定

#### Rails 7.2.x
- 安定版として採用
- Rails 7系の推奨構成（Hotwire / Importmap + tailwindcss-rails）

<br>

**選定理由：**
- 2026年3月までの開発期間を完全にカバー
- Runteqカリキュラムとの互換性が高い
- トラブルシューティングが容易

<br>

### フロントエンド
- **Hotwire（Turbo + Stimulus）** - Railsネイティブ、SPAのような操作感
- **Tailwind CSS（tailwindcss-rails）** 
- **Node.js** - 不要（tailwindcss-rails を使用）

> **注意：** HotwireとTailwind CSSはRunteqカリキュラムで明示的に扱われているか確認できていませんが、Rails 7にデフォルトで含まれており、学習コストが低い（2〜3日）ため採用。Week 1で学習期間を確保。

<br>

### データベース

#### PostgreSQL 16.x
- Docker公式イメージを使用
- JSON型や集計機能を活用予定

<br>

**選定理由：**
- PostgreSQL 16系は2023年9月リリースで2年以上の実績
- 17系より安定性が高い

<br>

### 認証

- **bcrypt** - Railsの標準的な認証方法（スクラッチ実装）

<br>

### デプロイ・インフラ

#### 開発環境：Docker + Docker Compose
- ローカル開発環境の統一
- チーム開発時の環境差異を解消
- 完全無料

<br>

#### 本番環境：Render（無料プラン）
- **Webサービス：** 無料
- **PostgreSQL：** 無料データベース
- **制限事項：**
  - 無料データベースには利用期限や制限がある場合あり
  - MVP動作確認用途として使用予定
  - Webサービスは15分間アクティビティがないとスリープ
- **MVPリリースレビュー時にデプロイして動作確認**

<br>

#### Git / GitHub
- バージョン管理
- 完全無料

<br>

> **注意：** Phase 4（Week 12）でRenderへのデプロイ作業を実施し、MVPリリースレビュー前に動作確認を行います。

<br>

---

<br>

## 開発環境セットアップ

<br>

### 前提条件
- Docker Desktop（24.0以上）がインストールされていること
- Docker Composeがインストールされていること（Docker Desktopに含まれる）
- Gitがインストールされていること

<br>

### セットアップ手順

<br>

1. **リポジトリのクローン**
```bash
git clone https://github.com/yourusername/HabitFlow.git
cd HabitFlow
```

<br>

2. **環境変数ファイルの作成**
```bash
cp .env.development.sample .env.development
```

<br>

3. **Dockerコンテナの起動**
```bash
docker compose up
```

<br>

初回起動時は以下の処理が自動で実行されます：
- Rubyイメージのダウンロード
- PostgreSQLイメージのダウンロード
- Gemのインストール
- データベースの作成
- Tailwind CSS のビルド

<br>

4. **動作確認**

ブラウザで http://localhost:3000 にアクセス

Railsのウェルカムページが表示されればOK

<br>

5. **コンテナの停止**
```bash
# Ctrl+C で停止（フォアグラウンド実行の場合）
# または
docker compose down
```

<br>

### トラブルシューティング

<br>

#### ポート3000が既に使用されている
```bash
# 使用中のプロセスを確認
lsof -i :3000
# プロセスを終了させるか、docker-compose.ymlでポートを変更
```

<br>

#### データベース接続エラー
```bash
# コンテナを完全に削除して再起動
docker compose down -v
docker compose up
```

<br>

#### Tailwind CSSが反映されない
```bash
# コンテナ内でTailwindを再ビルド
docker compose exec web bin/rails tailwindcss:build
```

<br>

#### 権限エラー（Permission denied）
```bash
# entrypoint.shに実行権限を付与
chmod +x entrypoint.sh
```

<br>

---

<br>

## 開発コマンド

<br>

### Railsコンソール
```bash
docker compose exec web bin/rails console
```

<br>

### データベースマイグレーション
```bash
docker compose exec web bin/rails db:migrate
```

<br>

### テスト実行
```bash
docker compose exec web bin/rails test
```

<br>

### ログ確認
```bash
docker compose logs -f web
```

<br>

---

<br>

## 実装予定の機能と技術

<br>

### 1. AI分析のパース処理

**使用技術：** Ruby標準ライブラリ（`String#split`、正規表現）

```ruby
# AIに統一フォーマットで出力させ、パイプ区切りをパース
priority, title, due_date, time = line.split("|")
current_user.tasks.create!(
  title: title,
  priority: priority.downcase,
  due_date: Date.parse(due_date),
  estimated_time: time.to_i,
  task_type: 'improvement'
)
```

<br>

### 2. 進捗率の自動計算

**使用技術：** Railsモデルメソッド、PostgreSQL集計関数、日付計算

```ruby
class Goal < ApplicationRecord
  def calculate_progress_rate
    case habit.measurement_type
    when 'daily_check'
      # 毎日実施型
      total_days = days_in_month - excluded_dates.count
      completed_days = daily_records.where(completed: true).count
      (completed_days.to_f / total_days * 100).round(1)
    when 'count'
      # 冊数型
      completed = daily_records.sum(:value)
      (completed.to_f / target_value * 100).round(1)
    when 'duration'
      # 時間型
      total = daily_records.sum(:value)
      (total.to_f / target_value * 100).round(1)
    end
  end
end
```

<br>

### 3. 自動更新

**使用技術：** after_saveコールバック

```ruby
class DailyRecord < ApplicationRecord
  after_save :update_goal_progress
  
  private
  
  def update_goal_progress
    goal = habit.goals.current_month.first
    goal.update(progress_rate: goal.calculate_progress_rate)
  end
end
```

<br>

### 4. JSON型の活用

**使用技術：** PostgreSQLのJSON型で柔軟なデータ保存

```ruby
# goals テーブル - できない日のリスト
{ excluded_dates: ["2025-01-15", "2025-01-16"] }

# reviews テーブル - AI提案タスク
{ improvement_tasks: [{ priority: "must", title: "23:00アラーム設定" }] }
```

<br>

## 画面遷移図

<br>

https://www.figma.com/design/ayV08jHHGE18BHlp7CEEvc/Habitflow--%E6%8F%90%E5%87%BA%E7%94%A8-?node-id=0-1&p=f&t=K8IAsjx90tS8AeDN-0

<br>

## ER図

<br>

https://i.gyazo.com/bd25eec5ecc56490a272f788b2fd2fbd.png

<br>

## issue

<br>

https://github.com/users/KK-arina/projects/1/views/1

<br>
```