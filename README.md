# HabitFlow（ハビットフロー）

<br>

## 🌐 本番環境

<br>

**URL**: https://habitflow-web.onrender.com

<br>

**デプロイ環境**:
- **ホスティング**: Render（無料プラン）
- **データベース**: PostgreSQL 16
- **アプリケーション**: Docker化されたRails 7.2

<br>

**デプロイ状況**:
- ✅ TOPページ（ランディングページ）公開中
- ✅ Tailwind CSS適用済み
- ✅ 共通ヘッダー・フッター実装済み（全ページ統一）
- ✅ ユーザー登録機能実装済み
- ✅ ログイン・ログアウト機能実装済み
- ✅ 本番環境での認証機能動作確認完了
- ✅ Habitモデル作成完了
- ✅ 習慣一覧ページ実装完了
- 🚧 習慣新規作成機能（開発中）

<br>

---

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

## 📊 開発進捗状況

<br>

**開発期間**: 2026年2月10日〜3月31日（7週間）

<br>

### Week 1（2/10〜2/16）: 基盤構築

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|-------|---------|-----------|--------|-----|
| #1 | Docker + Rails 環境構築 + Tailwind CSS | ✅ 完了 | 2/10 | 2 |
| #2 | データベース設計（MVP範囲のみ） | ✅ 完了 | 2/10 | 2 |
| #3 | TOPページ（ランディングページ）作成 | ✅ 完了 | 2/11 | 2 |
| #4 | Renderへの初回デプロイ | ✅ 完了 | 2/11 | 3 |
| #5 | Userモデルの作成 | ✅ 完了 | 2/11 | 2 |
| #6 | ユーザー登録機能 | ✅ 完了 | 2/12 | 3 |
| #7 | ログイン・ログアウト機能 | ✅ 完了 | 2/13 | 3 |
| #8 | 認証機能の本番確認 | ✅ 完了 | 2/14 | 1 |
| #9 | 認証機能テスト + 共通レイアウト実装 | ✅ 完了 | 2/14 | 2 |

<br>

**Week 1 進捗**: 20SP / 20SP（100%） 🎉

<br>

### 完了したマイルストーン

<br>

#### ✅ Issue #1: Docker環境構築
- Docker + Rails 7.2.3 + PostgreSQL 16.11環境構築
- Tailwind CSS 4.1導入
- `docker compose up` でワンコマンド起動
- 開発環境の完全統一化

<br>

#### ✅ Issue #2: データベース設計
- MVP範囲のER図作成（5テーブル）
- テーブル定義書作成
- ユニーク制約・インデックス設計
- ドキュメント整備（`docs/er-diagram-mvp.md`, `docs/database-schema-mvp.md`）

<br>

#### ✅ Issue #3: TOPページ作成
- ランディングページ実装（Tailwind CSS使用）
- レスポンシブデザイン対応
- ヒーローセクション・価値説明・利用フロー実装

<br>

#### ✅ Issue #4: Renderへの初回デプロイ
- Render環境構築（Web + PostgreSQL）
- `render.yaml` によるインフラコード化
- 本番用Dockerfile作成（マルチステージビルド）
- 環境変数設定（`RAILS_MASTER_KEY`, `DATABASE_URL`）
- **本番URL**: https://habitflow-web.onrender.com
- デプロイ自動化（GitHubプッシュ時に自動デプロイ）

<br>

#### ✅ Issue #5: Userモデル作成
- bcrypt gem導入
- Userモデル実装（`password_digest`使用、Rails標準準拠）
- `has_secure_password` による認証機能
- バリデーション実装
  - name: presence, length(max: 50)
  - email: presence, uniqueness(case_insensitive), format(URI::MailTo::EMAIL_REGEXP)
  - password: allow_nil, length(min: 8)
- before_save callback（email小文字変換）

<br>

#### ✅ Issue #6: ユーザー登録機能
- UsersController作成（new, create）
- 新規登録フォーム作成（Tailwind CSSデザイン）
- バリデーションエラー表示機能
  - エラー件数表示
  - エラーメッセージ一覧表示（赤色のエラーボックス）
- 登録成功時の自動ログイン（session管理）
- フラッシュメッセージ表示
  - 成功メッセージ（緑色、notice）
  - エラーメッセージ（赤色、alert）
- ApplicationControllerにヘルパーメソッド追加
  - current_user（現在ログインしているユーザーを取得）
  - logged_in?（ログイン状態をチェック）
- 統合テスト作成（正常系・異常系）
- TOPページに登録リンク追加（「今すぐ始める」→ `/users/new`）

<br>

#### ✅ Issue #7: ログイン・ログアウト機能
- SessionsController作成（new, create, destroy）
- ログインフォーム作成（Tailwind CSSデザイン）
- ログイン処理実装
  - メールアドレス＋パスワード認証
  - `reset_session` によるセッション固定攻撃対策
  - ログイン成功時にセッション保存
  - ログイン失敗時にエラーメッセージ表示
- ログアウト処理実装
  - `reset_session` でセッション破棄
  - `status: :see_other` でリダイレクト（Rails 7 / Turbo対応）
- ヘッダーにログイン状態表示
  - ログイン中: 「◯◯ さん」「ログアウト」ボタン
  - 未ログイン時: 「ログイン」「新規登録」リンク
- ApplicationControllerに認証チェック追加
  - `require_login`（ログイン必須チェック）
- TOPページレイアウト修正
  - ログイン状態によるボタン切り替え
- 統合テスト作成（正常系・異常系、ログアウト）
- 全テスト成功確認（19 runs, 57 assertions）

<br>

#### ✅ Issue #8: 認証機能の本番確認
- 本番環境（Render）での動作確認実施
- 本番環境URL: https://habitflow-web.onrender.com
- 確認項目:
  - ユーザー登録機能: 正常動作
  - ログイン機能: 正常動作（正常系・異常系）
  - ログアウト機能: 正常動作
  - フラッシュメッセージ表示: 正常動作
  - ヘッダーログイン状態表示: 正常動作
- 確認結果レポート作成: `docs/production-check-issue-7.md`
- 全機能が本番環境で正常に動作することを確認
- 備考:
  - Renderの無料プランのため、初回アクセス時に約30秒の起動時間が必要
  - それ以降は正常に動作

<br>

#### ✅ Issue #9: 認証機能テスト + 共通レイアウト実装
- 共通ヘッダー実装（shared/_header.html.erb）
- 共通フッター実装（shared/_footer.html.erb）
- application.html.erb に組み込み
- フラッシュメッセージ一元管理
- レスポンシブ対応確認
- 全テスト実行確認
- テスト結果: 20 runs, 59 assertions, 0 failures, 0 errors, 0 skips
- テストカバレッジ:
  - Userモデルテスト（13テストケース）
  - ユーザー登録統合テスト（2テストケース）
  - ログイン・ログアウト統合テスト（4テストケース）
- テストファイル:
  - `test/models/user_test.rb`
  - `test/integration/user_registration_test.rb`
  - `test/integration/user_login_test.rb`
- Week 1の全Issue完了

<br>

### Week 2（2/16〜2/22）: 習慣管理基盤

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|-------|---------|-----------|--------|-----|
| #10 | Habitモデルの作成 | ✅ 完了 | 2/15 | 2 |
| #11 | 習慣一覧ページの作成 | ✅ 完了 | 2/15 | 2 |
| #12 | 習慣新規作成機能 | 🔜 予定 | - | 3 |
| #13 | 習慣削除機能 | 🔜 予定 | - | 2 |
| #14 | HabitRecordモデルの作成 | 🔜 予定 | - | 2 |
| #15 | 習慣の日次記録機能（即時保存） | 🔜 予定 | - | 5 |
| #16 | 進捗率の自動計算ロジック | 🔜 予定 | - | 2 |
| #17 | 習慣管理機能のテスト | 🔜 予定 | - | 2 |

<br>

**Week 2 進捗**: 4SP / 20SP（20%）

<br>

**Week 2 目標**: 20SP

<br>

### 完了したマイルストーン（Week 2）

<br>

#### ✅ Issue #10: Habitモデルの作成

- Habitモデルの実装（習慣管理の基盤）
- マイグレーション作成（name, weekly_target, deleted_at）
- バリデーション実装
  - name: presence, length(max: 50)
  - weekly_target: presence, numericality(only_integer, 1-7)
- 論理削除機能実装
  - activeスコープ（deleted_at IS NULL）
  - deletedスコープ（deleted_at IS NOT NULL）
  - soft_deleteメソッド（touch(:deleted_at)使用）
  - active?メソッド、deleted?メソッド
- アソシエーション設定
  - belongs_to :user（Habitモデル）
  - has_many :habits, dependent: :destroy（Userモデル）
- モデルテスト作成（20テストケース）
  - バリデーションテスト（正常系・異常系）
  - アソシエーションテスト（dependent: :destroy確認）
  - スコープテスト（active, deleted）
  - インスタンスメソッドテスト（soft_delete, active?, deleted?）
  - 論理削除の統合テスト
- 全テスト成功確認
  - Habitモデルテスト: 20 runs, 53 assertions, 0 failures
  - 全体テスト: 40 runs, 112 assertions, 0 failures
- Railsコンソールでの動作確認完了

<br>

**技術的特徴**:
- 論理削除設計（deleted_atカラム使用）
  - 過去の振り返りデータとの整合性を保つため
  - スナップショット設計との連携を考慮
- touchメソッド使用（より明確で推奨される実装）
- インデックス最適化
  - user_id（t.referencesで自動作成）
  - deleted_at（論理削除フィルタリング用）
  - 複合インデックス（user_id, deleted_at）
- テストカバレッジ
  - 境界値テスト（0, 1, 7, 8, -1）
  - 文字数制限テスト（50文字、51文字）
  - 論理削除の動作確認（スコープ、メソッド）

<br>

**データベース設計**:
```sql
CREATE TABLE habits (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(50) NOT NULL,
  weekly_target INTEGER NOT NULL DEFAULT 7,
  deleted_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX index_habits_on_deleted_at ON habits(deleted_at);
CREATE INDEX index_habits_on_user_id_and_deleted_at ON habits(user_id, deleted_at);
```

<br>

#### ✅ Issue #11: 習慣一覧ページの作成

- HabitsController実装（indexアクション）
- 習慣一覧ビュー作成（カード形式レイアウト）
- レスポンシブデザイン対応
  - モバイル: 1列表示
  - タブレット: 2列表示
  - PC: 3列表示
- 進捗率の表示（仮データ: 50%固定）
- 論理削除された習慣の除外（activeスコープ使用）
- 「新しい習慣を追加」ボタン実装（リンク先はダミー）
- Empty State実装（習慣0件時の表示）
- seeds.rbにサンプルデータ追加
  - 2ユーザー作成（test@example.com、yamada@example.com）
  - 各ユーザーに5件の習慣を作成
  - 各ユーザーに1件の論理削除済み習慣を作成
- 共通ヘッダーに「習慣一覧」リンク追加

<br>

**実装内容**:

<br>

**HabitsController**:
```ruby
class HabitsController < ApplicationController
  before_action :require_login

  def index
    @habits = current_user.habits.active.order(created_at: :desc)
  end
end
```

<br>

**習慣一覧ビュー（app/views/habits/index.html.erb）**:
- カード形式のグリッドレイアウト
- 習慣名、週次目標値、測定タイプ（チェック型固定）を表示
- プログレスバーで進捗率を視覚化（仮データ: 50%）
- 実績表示（仮データ: 3/X日）
- Tailwind CSSによる洗練されたデザイン
- ホバーエフェクト（shadow-md）
- トランジション効果

<br>

**Empty State**:
- 習慣が0件の場合の専用UI
- 円形アイコン + 魅力的なメッセージ
- 「習慣を登録する」ボタン
- 破線ボーダー（border-dashed）

<br>

**ルーティング**:
```ruby
# config/routes.rb

resources :habits, only: [:index]
```

<br>

**seeds.rb**:
- test@example.com ユーザー作成
  - 5件の習慣（読書、筋トレ、瞑想、英語学習、ジョギング）
  - 1件の論理削除済み習慣
- yamada@example.com ユーザー作成（将来のため）
  - 5件の習慣（朝のランニング、読書、ストレッチ、水分摂取、日記）
  - 1件の論理削除済み習慣
- HabitRecord.destroy_all はコメントアウト（モデル未作成のため）

<br>

**UI/UX設計**:
- レスポンシブグリッド（grid-cols-1 md:grid-cols-2 lg:grid-cols-3）
- カードデザイン（rounded-xl、shadow-sm）
- アイコンの色分け
  - チェック型: 青色（text-blue-500）
  - 週次目標: 緑色（text-green-500）
- プログレスバー
  - 外側: グレー（bg-gray-200）
  - 内側: 青色（bg-blue-500）
  - 高さ: h-2（8px）

<br>

**動作確認**:
- Railsコンソールでの論理削除テスト実施
- 論理削除された習慣が一覧に表示されないことを確認
- activeスコープの動作確認
- deletedスコープの動作確認
- レスポンシブデザインの動作確認（モバイル/タブレット/PC）

<br>

**テスト**:
- 全テスト実行: 40 runs, 112 assertions, 0 failures
- 既存のテストに影響なし

<br>

**今後の実装予定**:
- Issue #12: 「新しい習慣を追加」ボタンの動作実装
- Issue #15: 日次記録機能（チェックボックス）
- Issue #16: 進捗率の動的計算（現在は50%固定）

<br>

**技術的特徴**:
- link_to ヘルパーメソッド使用（将来のパス変更に強い）
- Tailwind CSSのユーティリティクラスのみ使用（コンパイル不要）
- Hotwire対応の準備（turbo_frameタグは将来実装）
- コメント充実（各Tailwindクラスの意味を説明）

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

2. **環境変数ファイルの作成（必要な場合のみ）**
```bash
cp .env.development.sample .env.development
```

<br>

> **注意：** .env.development.sample は将来的に環境変数を追加した場合のサンプル用です。現状のMVP段階では未使用のため、存在しなくても問題ありません。

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

**初回起動時の追加手順**:
```bash
# データベース作成（初回のみ）
docker compose exec web bin/rails db:create

# マイグレーション実行（初回のみ）
docker compose exec web bin/rails db:migrate
```

<br>

> **注意：** `docker-entrypoint` スクリプトで自動実行される設定もありますが、手動実行を推奨します。

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

#### Rails未作成時の初回セットアップ（初回のみ）
```bash
docker compose down
docker compose run --rm web rails new . \
  --force \
  --database=postgresql \
  --css=tailwind
docker compose build
docker compose up
```

<br>

> **注意：** 通常の開発では不要です。

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
Tailwind CSS は以下の構成で読み込まれています。
- build成果物：app/assets/builds/tailwind.css
- 読み込み指定：<%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
- マニフェスト：app/assets/config/manifest.js (//= link tailwind.css)

<br>

以下を確認してください。
```bash
# build成果物が存在するか
docker compose exec web ls app/assets/builds/

# Tailwindを再ビルド
docker compose exec web bin/rails tailwindcss:build
```

<br>

> **注意：** application.tailwind.css は使用していません。

<br>

#### 権限エラー（Permission denied）
```bash
# entrypoint.shに実行権限を付与
chmod +x entrypoint.sh
```

<br>

#### テスト実行時のエラー
```bash
# テスト環境のデータベースを初期化
docker compose exec web bin/rails db:environment:set RAILS_ENV=test
docker compose exec web bin/rails db:test:prepare
```

<br>

#### Renderデプロイ時のエラー

**エラー: `PG::ConnectionBad: database does not exist`**
- Render Dashboardで環境変数 `DATABASE_URL` が正しく設定されているか確認
- `RAILS_MASTER_KEY` が設定されているか確認（`cat config/master.key` の内容）

<br>

**エラー: `psych gem` ビルド失敗**
- Dockerfileに `libyaml-dev`（ビルドステージ）と `libyaml-0-2`（本番ステージ）が含まれているか確認

<br>

---

<br>

## 開発時の基本ルール（重要）

<br>

### コンテナの起動・停止
```bash
# 起動
docker compose up

# 停止
docker compose down
```

<br>

### Railsコマンドの実行方法
```bash
# 推奨：起動中コンテナで実行
docker compose exec web bin/rails xxx

# 非推奨：一時コンテナが作られる
docker compose run web bin/rails xxx
```

<br>

> **注意：** docker compose run は一時コンテナを作成するため、assets や build 結果が意図せず失われる場合があります。 通常の開発では exec を使用してください。

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

### Tailwind CSSのビルド
```bash
# 手動ビルド
docker compose exec web bin/rails tailwindcss:build

# 自動監視モード（開発時）
docker compose exec web bin/rails tailwindcss:watch
```

<br>

### データベースリセット
```bash
# データベースを削除して再作成
docker compose exec web bin/rails db:reset

# テスト環境のデータベース準備
docker compose exec web bin/rails db:test:prepare
```

<br>

---

<br>

## 📁 プロジェクト構成

<br>

### 主要ディレクトリ
```
habitflow/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb    # ヘルパーメソッド（current_user, logged_in?, require_login）
│   │   ├── habits_controller.rb         # 習慣管理（index）
│   │   ├── pages_controller.rb          # ランディングページ
│   │   ├── sessions_controller.rb       # ログイン・ログアウト（new, create, destroy）
│   │   └── users_controller.rb          # ユーザー登録（new, create）
│   ├── models/
│   │   ├── user.rb                       # Userモデル（認証機能、has_many :habits）
│   │   └── habit.rb                      # Habitモデル（習慣管理、論理削除機能）
│   └── views/
│       ├── layouts/
│       │   └── application.html.erb      # 全ページ共通レイアウト（ヘッダー・フッター・フラッシュ）
│       ├── shared/
│       │   ├── _header.html.erb          # 共通ヘッダー（全ページ、習慣一覧リンク追加）
│       │   └── _footer.html.erb          # 共通フッター（全ページ）
│       ├── habits/
│       │   └── index.html.erb            # 習慣一覧ページ（カード形式、レスポンシブ対応）
│       ├── pages/
│       │   └── index.html.erb            # TOPページ（シンプル化済み）
│       ├── sessions/
│       │   └── new.html.erb              # ログインフォーム
│       └── users/
│           └── new.html.erb              # 新規登録フォーム
├── db/
│   ├── migrate/
│   │   ├── YYYYMMDDHHMMSS_create_users.rb    # Usersテーブル作成
│   │   └── YYYYMMDDHHMMSS_create_habits.rb   # Habitsテーブル作成
│   └── schema.rb                         # データベーススキーマ
├── docs/
│   ├── er-diagram-mvp.md                 # ER図（Mermaid形式）
│   ├── database-schema-mvp.md            # テーブル定義書
│   └── production-check-issue-7.md       # Issue #7 本番環境確認レポート
├── test/
│   ├── models/
│   │   ├── user_test.rb                  # Userモデルテスト（13テストケース）
│   │   └── habit_test.rb                 # Habitモデルテスト（20テストケース）
│   ├── integration/
│   │   ├── user_registration_test.rb     # ユーザー登録統合テスト（2テストケース）
│   │   └── user_login_test.rb            # ログイン・ログアウト統合テスト（4テストケース）
│   └── fixtures/
│       ├── users.yml                     # テスト用ユーザーデータ
│       └── habits.yml                    # テスト用習慣データ
├── config/
│   ├── database.yml                      # DB接続設定
│   └── routes.rb                         # ルーティング設定（習慣管理追加）
├── Dockerfile                            # 本番環境用Dockerfile
├── Dockerfile.dev                        # 開発環境用Dockerfile
├── docker-compose.yml                    # Docker Compose設定
├── render.yaml                           # Renderデプロイ設定
└── Gemfile                               # Gem依存関係
```
<br>

### 重要ファイルの説明

<br>

| ファイル | 説明 |
|---------|------|
| `render.yaml` | Renderのインフラ設定（IaC） |
| `Dockerfile` | 本番環境用（マルチステージビルド） |
| `Dockerfile.dev` | 開発環境用（ホットリロード対応） |
| `bin/docker-entrypoint` | コンテナ起動時の初期化スクリプト |
| `docs/er-diagram-mvp.md` | ER図（Mermaid）とMVP範囲説明 |
| `docs/database-schema-mvp.md` | 全テーブル詳細定義 |
| `docs/production-check-issue-7.md` | Issue #7 本番環境確認レポート |
| `test/integration/user_login_test.rb` | ログイン・ログアウト統合テスト |
| `test/models/habit_test.rb` | Habitモデルテスト（20テストケース） |
| `app/models/habit.rb` | Habitモデル（論理削除機能実装） |
| `app/controllers/habits_controller.rb` | 習慣管理コントローラー（index実装） |
| `app/views/habits/index.html.erb` | 習慣一覧ビュー（カード形式、レスポンシブ対応） |
| `db/seeds.rb` | サンプルデータ（2ユーザー、計10件の習慣） |

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

---

<br>

## 📚 技術ドキュメント

<br>

### データベース設計

<br>

- **ER図（MVP範囲）**: [docs/er-diagram-mvp.md](docs/er-diagram-mvp.md)
- **テーブル定義書（MVP範囲）**: [docs/database-schema-mvp.md](docs/database-schema-mvp.md)

<br>

### MVP範囲のテーブル（5テーブル）

<br>

1. **users** - ユーザー情報（認証機能）
2. **habits** - 習慣（チェック型のみ、MVP範囲）
3. **habit_records** - 日次記録（AM4:00基準）
4. **weekly_reflections** - 週次振り返り（PDCA機能）
5. **weekly_reflection_habit_summaries** - スナップショット（データ不変性）

<br>

### 実装済み機能の技術詳細

<br>

## Docker環境構築（Issue #1）

<br>

### 開発環境

- Docker 24.0以上  
- Docker Compose 2.20以上  
- Ruby 3.4.7  
- Rails 7.2.3  
- PostgreSQL 16.11  
- Tailwind CSS 4.1.18  

<br>

### Dockerfile.dev（開発環境用）

```dockerfile
FROM ruby:3.4.7

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install -y build-essential libpq-dev nodejs yarn

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["bin/dev"]
```

<br>

### docker-compose.yml

```yaml
version: '3.8'

services:
  db:
    image: postgres:16.11
    environment:
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  web:
    build:
      context: .
      dockerfile: Dockerfile.dev
    command: bin/dev
    volumes:
      - .:/rails
      - bundle:/usr/local/bundle
    ports:
      - "3000:3000"
    depends_on:
      - db
    environment:
      DATABASE_URL: postgres://postgres:password@db:5432
      RAILS_ENV: development

volumes:
  postgres_data:
  bundle:
```

<br>

### Tailwind CSS導入

- `tailwindcss-rails` gem 使用
- `bin/dev` で Rails サーバーと Tailwind の監視を同時起動
- `app/assets/builds/tailwind.css` に自動ビルド

<br>

### 設計意図

- Dockerによりローカルと本番の環境差異を排除
- PostgreSQLをコンテナ化し環境構築を簡略化
- フロントエンドビルドをRailsと統合管理

---

## データベース設計（Issue #2）

<br>

### MVP範囲のER設計

- 5テーブル構成
  - users
  - habits
  - habit_records
  - weekly_reflections
  - weekly_reflection_habit_summaries

- Mermaid形式でER図作成  
  → `docs/er-diagram-mvp.md`

- リレーションの明確化（1:N、依存関係整理）

<br>

### テーブル定義書

- 全カラムの詳細定義  
  → `docs/database-schema-mvp.md`

- データ型、NULL制約、デフォルト値を明記
- インデックス設計（検索性能最適化）
- ユニーク制約によるデータ整合性担保

<br>

### 設計の特徴

- PostgreSQLのJSON型活用
  - `goals.excluded_dates`：実行不可日の配列
  - `weekly_reflections.improvement_tasks`：AI提案タスク

- 日付基準をAM4:00で設計（習慣アプリ特性を考慮）
- `weekly_reflection_habit_summaries` により週次データを不変保存

<br>

### 設計思想

- 将来的なAI分析拡張を前提
- 変更可能データと履歴データを明確分離
- MVPながらスケールを想定した構造

---

## TOPページ作成（Issue #3）

<br>

### ランディングページ構成

```erb
<!-- ヘッダー -->
<header class="bg-white shadow-sm">
  <!-- ロゴ、ナビゲーション -->
</header>

<!-- ヒーローセクション -->
<main class="bg-gradient-to-b from-blue-50 to-white">
  <h1>甘えを可視化する</h1>
  <p>習慣 × PDCA で目標達成を加速</p>
  <%= link_to "今すぐ始める", new_user_path %>
</main>

<!-- 価値説明 -->
<section class="bg-white py-16">
</section>

<!-- 利用フロー -->
<section class="bg-gray-50 py-16">
</section>

<!-- フッター -->
<footer class="bg-gray-900 text-white py-8">
</footer>
```

<br>

### UI設計（Tailwind CSS）

- グラデーション背景（`bg-gradient-to-b`）
- レスポンシブ設計（`md:grid-cols-3`）
- ホバーエフェクト（`hover:bg-blue-700`）
- トランジション（`transition duration-200`）

<br>

### ルーティング

```ruby
# config/routes.rb

Rails.application.routes.draw do
  root "pages#index"
end
```

<br>

### 設計意図

- 未ログインユーザー向け導線最適化
- 「習慣 × PDCA × AI」という価値を明確化
- コンバージョン（新規登録）への導線設計

---

## Renderへの初回デプロイ（Issue #4）

<br>

### 本番環境構成

- Render Web Service（無料プラン）
- Render PostgreSQL（無料プラン）
- GitHub連携による自動デプロイ

<br>

### render.yaml（Infrastructure as Code）

```yaml
services:
  - type: web
    name: habitflow-web
    runtime: docker
    plan: free
    dockerfilePath: ./Dockerfile
    envVars:
      - key: DATABASE_URL
        fromDatabase:
          name: habitflow-db
          property: connectionString
      - key: RAILS_MASTER_KEY
        sync: false

databases:
  - name: habitflow-db
    databaseName: habitflow
    plan: free
```

<br>

### Dockerfile（本番用・マルチステージビルド）

```dockerfile
# ビルドステージ
FROM ruby:3.4.7 AS build
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install -y build-essential libpq-dev nodejs yarn
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
RUN bin/rails assets:precompile

# 本番ステージ
FROM ruby:3.4.7
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install -y libpq-dev
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
```

<br>

### 環境変数

- `RAILS_MASTER_KEY`：暗号化キー（credentials用）
- `DATABASE_URL`：PostgreSQL接続文字列（Render自動設定）

<br>

### デプロイフロー

1. GitHubへプッシュ  
2. Renderが自動検知  
3. Dockerイメージビルド  
4. データベースマイグレーション  
5. アプリケーション起動  

<br>

### 本番URL

https://habitflow-web.onrender.com

<br>

#### Userモデル（Issue #5）

<br>

**認証方式**: bcrypt + has_secure_password（Rails標準）

<br>

**パスワード暗号化**:
```ruby
# password_digest カラムに自動的にハッシュ化して保存
user = User.new(
  name: "山田太郎",
  email: "yamada@example.com",
  password: "password123",
  password_confirmation: "password123"
)
user.save
# => password_digest: "$2a$12$cAYRw9BXKiBuA..."
```

<br>

**パスワード認証**:
```ruby
user.authenticate("password123")  # => # （成功）
user.authenticate("wrongpassword") # => false （失敗）
```

<br>

**バリデーション**:
- name: 必須、最大50文字
- email: 必須、一意（大文字小文字無視）、メール形式（URI::MailTo::EMAIL_REGEXP）
- password: 更新時は任意（allow_nil）、最小8文字

<br>

**セキュリティ対策**:
- before_save callback で email を小文字に統一
- ログに機密情報を出力しない（filter_parameter_logging）
- uniqueness検証で `LOWER(email)` による重複チェック

<br>

#### ユーザー登録機能（Issue #6）

<br>

**実装機能**:

<br>

**UsersController**:
```ruby
# app/controllers/users_controller.rb

class UsersController < ApplicationController
  # GET /users/new - 新規登録フォーム表示
  def new
    @user = User.new
  end

  # POST /users - ユーザー作成処理
  def create
    @user = User.new(user_params)
    if @user.save
      session[:user_id] = @user.id  # 自動ログイン
      flash[:notice] = "ユーザー登録が完了しました"
      redirect_to root_path
    else
      flash.now[:alert] = "ユーザー登録に失敗しました"
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
```

<br>

**ApplicationController（ヘルパーメソッド）**:
```ruby
# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  helper_method :current_user, :logged_in?

  private

  # 現在ログインしているユーザーを取得
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # ログイン状態をチェック
  def logged_in?
    current_user.present?
  end
end
```

<br>

**フラッシュメッセージ**:
- 成功時: 緑色のメッセージ（`flash[:notice]`）
- エラー時: 赤色のメッセージ（`flash.now[:alert]`）
- 画面右上に固定表示
- アイコン付き（SVG）

<br>

**バリデーションエラー表示**:
- エラー件数表示（`@user.errors.count`）
- エラーメッセージ一覧表示（`@user.errors.full_messages`）
- 赤色のエラーボックス（Tailwind CSS）

<br>

**セキュリティ対策**:
- Strong Parameters（`user_params`）
- CSRF対策（Rails標準）
- パスワード暗号化（bcrypt）
- セッション管理（暗号化されたCookie）

<br>

**テスト**:
- 正常系テスト: ユーザー登録成功、自動ログイン確認
- 異常系テスト: バリデーションエラー、エラーメッセージ表示確認

<br>

#### ログイン・ログアウト機能（Issue #7）

<br>

**実装機能**:

<br>

**SessionsController**:
```ruby
# app/controllers/sessions_controller.rb

class SessionsController < ApplicationController
  # GET /login - ログインフォーム表示
  def new
  end

  # POST /login - ログイン処理
  def create
    user = User.find_by(email: params[:session][:email].downcase)
    if user && user.authenticate(params[:session][:password])
      reset_session  # セッション固定攻撃対策
      session[:user_id] = user.id
      flash[:notice] = "ログインしました"
      redirect_to root_path
    else
      flash.now[:alert] = "メールアドレスまたはパスワードが正しくありません"
      render :new, status: :unprocessable_entity
    end
  end

  # DELETE /logout - ログアウト処理
  def destroy
    reset_session  # セッション全体をリセット
    @current_user = nil
    flash[:notice] = "ログアウトしました"
    redirect_to root_path, status: :see_other  # Rails 7推奨
  end
end
```

<br>

**ApplicationController（認証チェック）**:
```ruby
# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  
  helper_method :current_user, :logged_in?
  
  private
  
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
  
  def logged_in?
    current_user.present?
  end
  
  # ログイン必須チェック
  def require_login
    unless logged_in?
      flash[:alert] = "ログインしてください"
      redirect_to login_path
    end
  end
end
```

<br>

**ルーティング**:
```ruby
# config/routes.rb

Rails.application.routes.draw do
  root "pages#index"
  
  # ユーザー登録
  resources :users, only: [:new, :create]
  
  # ログイン・ログアウト
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
end
```

<br>

**セキュリティ対策**:
- `reset_session`: セッション固定攻撃対策（ログイン・ログアウト時）
- `status: :see_other`: ブラウザの戻るボタン対策（Rails 7 / Turbo）
- Strong Parameters: 許可されたパラメータのみ受け取る
- CSRF対策: Rails標準機能

<br>

**ログイン状態表示**:
- ヘッダーに「◯◯ さん」と表示
- ログアウトボタン（確認ダイアログ付き）
- 未ログイン時は「ログイン」「新規登録」リンク表示

<br>

**テスト**:
- 正常系テスト: ログイン成功、セッション保存確認
- 異常系テスト: 無効なメール・パスワードでログイン失敗
- ログアウトテスト: セッション破棄確認
- 全テスト成功: 19 runs, 57 assertions, 0 failures

<br>

#### 認証機能の本番環境確認（Issue #8）

<br>

**確認環境**:
- 本番URL: https://habitflow-web.onrender.com
- ホスティング: Render（無料プラン）
- データベース: PostgreSQL 16

<br>

**確認項目**:

<br>

**1. TOPページ表示**
- ✅ ページが正しく表示される
- ✅ Tailwind CSSが適用されている
- ✅ ヘッダーに「ログイン」「新規登録」リンクがある

<br>

**2. ユーザー登録機能**
- ✅ 新規登録フォームが表示される
- ✅ 登録が成功する
- ✅ 成功メッセージが表示される
- ✅ ログイン状態になる
- ✅ ヘッダーにユーザー名が表示される

<br>

**3. ログアウト機能**
- ✅ ログアウトボタンが表示される
- ✅ 確認ダイアログが表示される
- ✅ ログアウトが成功する
- ✅ 成功メッセージが表示される
- ✅ 未ログイン状態になる

<br>

**4. ログイン機能（正常系）**
- ✅ ログインフォームが表示される
- ✅ ログインが成功する
- ✅ 成功メッセージが表示される
- ✅ ログイン状態になる

<br>

**5. ログイン機能（異常系）**
- ✅ エラーメッセージが表示される
- ✅ ログインフォームが再表示される
- ✅ 未ログイン状態のまま

<br>

**確認結果**:

<br>

全機能が本番環境で正常に動作することを確認。<br>
詳細は `docs/production-check-issue-7.md` を参照。

<br>

**注意事項**:
- Renderの無料プランのため、初回アクセス時に約30秒の起動時間が必要
- スリープ対策は Issue #10 以降で実装予定

<br>

#### 認証機能のテスト（Issue #9）

<br>

**テスト実施日**: 2024年2月14日

<br>

**テスト結果**:
```
20 runs, 59 assertions, 0 failures, 0 errors, 0 skips
```

<br>

**テストカバレッジ**:

<br>

**1. Userモデルテスト（13テストケース）**
- バリデーション（name, email, password）
- パスワード暗号化
- email小文字変換
- 重複チェック

<br>

**2. ユーザー登録統合テスト（2テストケース）**
- 正常系: ユーザー登録成功、自動ログイン
- 異常系: バリデーションエラー表示

<br>

**3. ログイン・ログアウト統合テスト（4テストケース）**
- 正常系: ログイン成功、セッション保存
- 異常系: 無効なメールアドレス、無効なパスワード
- ログアウト: セッション破棄確認

<br>

**テストファイル**:
- `test/models/user_test.rb`
- `test/integration/user_registration_test.rb`
- `test/integration/user_login_test.rb`

<br>

**テスト戦略**:
- 正常系・異常系の両方をテスト
- セッション管理の検証
- HTTPステータスコードの確認（200, 303, 422）
- フラッシュメッセージの検証

<br>

#### 共通ヘッダー・フッター実装（Issue #9に追加）

<br>

**実装目的**:
- 全23画面で共通レイアウトを統一
- DRY原則に基づくパーシャル化
- 認証状態に応じたナビゲーション制御

<br>

**実装機能**:

<br>

**共通ヘッダー（app/views/shared/_header.html.erb）**:
erb
<header class="bg-gray-50 border-b border-gray-200">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
    <div class="flex justify-between items-center">
      <!-- ロゴエリア -->
      <div class="text-2xl font-bold text-blue-600">
        <%= link_to "HabitFlow", root_path %>
      </div>

      <!-- ナビゲーションエリア -->
      <div class="flex items-center space-x-4">
        <% if logged_in? %>
          <span><%= current_user.name %> さん</span>
          <%= button_to "ログアウト", logout_path, method: :delete %>
        <% else %>
          <%= link_to "ログイン", login_path %>
          <%= link_to "新規登録", new_user_path %>
        <% end %>
      </div>
    </div>
  </div>
</header>

<br>

**共通フッター（app/views/shared/_footer.html.erb）**:
erb
<footer class="bg-gray-900 text-white py-8 mt-auto">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
    <div class="text-center text-sm">
      <p>© 2024 HabitFlow. All rights reserved.</p>
      <div class="mt-2 space-x-4 text-gray-400">
        <span>利用規約</span>
        <span>プライバシーポリシー</span>
      </div>
    </div>
  </div>
</footer>

<br>

**レイアウトファイル（app/views/layouts/application.html.erb）**:
erb
<body class="min-h-screen flex flex-col bg-white text-gray-900">
  <%= render "shared/header" %>

  <main class="flex-1">
    <!-- フラッシュメッセージ表示 -->
    <% flash.each do |message_type, message| %>
      <div class="<%= message_type == 'notice' ? 'bg-green-100 border-green-400 text-green-700' : 'bg-red-100 border-red-400 text-red-700' %> px-4 py-3 rounded border">
        <%= message %>
      </div>
    <% end %>

    <%= yield %>
  </main>

  <%= render "shared/footer" %>
</body>

<br>

**TOPページ構成**:
- ヒーローセクション: キャッチコピー「甘えを可視化する」、CTAボタン
- 価値説明セクション: 3つの特徴（3列グリッド、レスポンシブ対応）
- 利用フローセクション: 4ステップ（横並び、レスポンシブ対応）

<br>

**UI設計（Tailwind CSS）**:
- レスポンシブデザイン（md:grid-cols-3, md:flex-row）
- フレックスボックスレイアウト（flex, justify-between）
- グリッドレイアウト（grid, grid-cols-1）
- フッターを最下部に固定（min-h-screen, flex-col, flex-1, mt-auto）

<br>

**パーシャル（Partial）の活用**:
- ヘッダー・フッターを app/views/shared/ に配置
- <%= render "shared/header" %> で読み込み
- DRY原則（Don't Repeat Yourself）に従う
- コードの重複を避ける

<br>

**画面遷移図との整合性**:
- 完全に一致するレイアウト
- シンプルで落ち着いたデザイン
- 全23画面に共通のヘッダー・フッター表示

<br>

**テスト**:
- 全テスト実行: 20 runs, 59 assertions, 0 failures
- 既存のテストに影響なし
- ビューの変更がテストに影響しないことを確認

<br>

#### Habitモデル（Issue #10）

<br>

**モデル設計**:
- 習慣管理の基盤モデル（MVP範囲：チェック型のみ）
- 論理削除設計（deleted_atカラム使用）
- user_idへの外部キー制約（dependent: :destroy）

<br>

**テーブル定義**:
```sql
CREATE TABLE habits (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(50) NOT NULL,
  weekly_target INTEGER NOT NULL DEFAULT 7,
  deleted_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX index_habits_on_user_id ON habits(user_id);
CREATE INDEX index_habits_on_deleted_at ON habits(deleted_at);
CREATE INDEX index_habits_on_user_id_and_deleted_at ON habits(user_id, deleted_at);
```

<br>

**バリデーション**:
- name: 必須、最大50文字
- weekly_target: 必須、整数のみ、1〜7の範囲

<br>

**スコープ**:
```ruby
scope :active, -> { where(deleted_at: nil) }
scope :deleted, -> { where.not(deleted_at: nil) }
```

<br>

**インスタンスメソッド**:
```ruby
# 論理削除を実行
def soft_delete
  touch(:deleted_at)
end

# 有効な習慣かどうかを判定
def active?
  deleted_at.nil?
end

# 削除済みかどうかを判定
def deleted?
  !active?
end
```

<br>

**アソシエーション**:
```ruby
# Habitモデル
belongs_to :user

# Userモデル
has_many :habits, dependent: :destroy
```

<br>

**論理削除の設計思想**:
- 過去の振り返りデータとの整合性を保つため物理削除は行わない
- weekly_reflection_habit_summaries テーブルにスナップショットとして保存
- 論理削除された習慣でも過去の振り返りで参照可能

<br>

**インデックス設計**:
- user_id: ユーザーごとの習慣一覧取得を高速化
- deleted_at: 論理削除フィルタリングを高速化
- (user_id, deleted_at): 「特定ユーザーの有効な習慣のみ取得」という最頻出クエリを最適化

<br>

**テスト戦略**:
- バリデーションテスト（正常系・異常系）
  - name: 空文字、nil、51文字、50文字
  - weekly_target: nil、0、負の数、8、小数、1、7
- アソシエーションテスト
  - ユーザーとの関連付け確認
  - dependent: :destroy の動作確認
- スコープテスト
  - activeスコープの動作確認
  - deletedスコープの動作確認
- インスタンスメソッドテスト
  - soft_deleteメソッドの動作確認
  - active?メソッドの動作確認
  - deleted?メソッドの動作確認
- 論理削除の統合テスト
  - soft_delete後にactiveスコープから除外されることを確認
  - soft_delete後にdeletedスコープに含まれることを確認

<br>

**テスト結果**:
- Habitモデルテスト: 20 runs, 53 assertions, 0 failures
- 全体テスト: 40 runs, 112 assertions, 0 failures

<br>

**動作確認（Railsコンソール）**:
```ruby
# ユーザー取得
user = User.first

# 習慣作成
habit = user.habits.create(name: "朝のランニング", weekly_target: 7)
habit.persisted?  # => true
habit.active?     # => true

# 論理削除
habit.soft_delete
habit.deleted?    # => true
habit.deleted_at  # => Sun, 15 Feb 2026 00:40:49 UTC

# スコープ確認
Habit.active.include?(habit)   # => false
Habit.deleted.include?(habit)  # => true
```

<br>

**セキュリティ対策**:
- Strong Parameters（習慣作成・更新時）
- 外部キー制約（user_id）
- dependent: :destroy（ユーザー削除時に習慣も削除）

<br>

**MVP後の拡張予定**:
- measurement_typeカラム追加（daily_check, count, duration）
- unitカラム追加（冊、時間）
- 数値型習慣への対応
- 除外日設定（曜日指定）

<br>
```