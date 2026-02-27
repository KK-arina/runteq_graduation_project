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
- ✅ 習慣新規作成機能実装完了
- ✅ 習慣削除機能実装完了（論理削除対応）
- ✅ HabitRecordモデル作成完了（AM4:00基準、UNIQUE制約、CASCADE）
- ✅ 習慣の日次記録機能実装完了（Turbo Streams即時保存、楽観的UI）
- ✅ 習慣の週次進捗統計自動計算実装完了（N+1問題対策済み）
- ✅ 習慣管理機能のテスト実装完了（119 runs, 322 assertions, 0 failures）
- ✅ ダッシュボード機能実装完了（今週の達成率・今日の習慣チェックリスト）
- ✅ WeeklyReflectionHabitSummaryモデル作成完了（スナップショット設計・冪等性対応）
- ✅ 週次振り返り一覧ページ実装完了（日曜AM4:00判定・N+1対策・travel_to日付非依存テスト）
- ✅ 週次振り返り入力ページ実装完了（form_with model設計・トランザクション保証・スナップショット自動作成）
- ✅ 週次振り返り詳細ページ実装完了（コードレビュー対応・フィクスチャ設計・ルーティング整備）
- ✅ PDCA強制ロック機能実装完了（月曜AM4:00判定・新規作成/削除ブロック・ダッシュボード警告バナー）
- ✅ 振り返り完了時のPDCAロック自動解除機能実装完了（completed_at記録・前週pending_reflection自動完了・ロック解除バナー表示）
- ✅ レスポンシブデザイン実装完了（全ページスマホ対応・ハンバーガーメニュー）
- ✅ エラーハンドリング実装完了（カスタム404/422/500ページ・バリデーションエラー共通化・トースト通知）
- ✅ セキュリティ対策実装完了（CSRF対策・SQLインジェクション対策・XSS対策・Strong Parameters・CSP設定・セッション管理強化）
- ✅ パフォーマンス最適化実装完了（Bullet gem導入・N+1問題解消・DBインデックス追加）
- ✅ 統合テスト（主要フロー）実装完了（202 runs, 602 assertions, 0 failures）

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

### 完了したマイルストーン（Week 1）

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
| #12 | 習慣新規作成機能 | ✅ 完了 | 2/15 | 3 |
| #13 | 習慣削除機能 | ✅ 完了 | 2/15 | 2 |
| #14 | HabitRecordモデルの作成 | ✅ 完了 | 2/16 | 2 |
| #15 | 習慣の日次記録機能（即時保存） | ✅ 完了 | 2/19 | 5 |
| #16 | 進捗率の自動計算ロジック | ✅ 完了 | 2/19 | 2 |
| #17 | 習慣管理機能のテスト | ✅ 完了 | 2/20 | 2 |

<br>

**Week 2 進捗**: 20SP / 20SP（100%） 🎉

<br>

**Week 2 目標**: 20SP

<br>

### 完了したマイルストーン（Week 2）

<br>

#### ✅ Issue #10: Habitモデルの作成
- Habitモデル実装（習慣管理の基盤）
- バリデーション実装（name: 最大50文字、weekly_target: 1-7）
- 論理削除機能実装（activeスコープ、deletedスコープ、soft_deleteメソッド）
- アソシエーション設定（belongs_to :user、has_many :habits）
- モデルテスト作成（20テストケース）
- 全テスト成功: 40 runs, 112 assertions, 0 failures
- インデックス最適化（user_id, deleted_at, 複合インデックス）

<br>

#### ✅ Issue #11: 習慣一覧ページの作成
- HabitsController実装（indexアクション）
- 習慣一覧ビュー作成（カード形式レイアウト）
- レスポンシブデザイン対応（モバイル: 1列、タブレット: 2列、PC: 3列）
- 進捗率の表示（仮データ: 50%固定）
- Empty State実装（習慣0件時の表示）
- seeds.rbにサンプルデータ追加（2ユーザー、各5件の習慣）
- 論理削除された習慣の除外（activeスコープ使用）

<br>

#### ✅ Issue #12: 習慣新規作成機能
- HabitsController に new, create アクション実装
- 習慣新規作成フォーム作成
- バリデーションエラー表示機能
- Strong Parameters によるセキュリティ対策（`:name`, `:weekly_target`のみ許可）
- フラッシュメッセージ表示（成功: 緑、エラー: 赤）
- レイアウト改善（共通ヘッダー・フッターを全ページに適用）
- 統合テスト作成（7テストケース）
- テスト結果: 49 runs, 140 assertions, 0 failures

<br>

#### ✅ Issue #13: 習慣削除機能
- HabitsController に destroy アクション実装
- 削除確認ダイアログ（Turbo Confirm）
- 論理削除処理（deleted_atの更新）
- セキュリティ対策（他のユーザーの習慣削除を防止）
- 統合テスト作成（4テストケース）
- テスト結果: 4 runs, 27 assertions, 0 failures
- 全テスト成功: 53 runs, 167 assertions, 0 failures

<br>

#### ✅ Issue #14: HabitRecordモデルの作成
- HabitRecordモデル実装（日次記録の基盤、チェック型のみ）
- マイグレーション作成（user_id, habit_id, record_date, completed）
- UNIQUE制約（user_id, habit_id, record_date）で重複記録を防止
- CASCADE設定（ユーザー・習慣削除時に記録も自動削除、DB + アプリ二重保証）
- AM4:00基準の日付計算ロジック（today_for_record メソッド）
- スコープ追加（for_date, for_user）
- インスタンスメソッド（toggle_completed!）
- アソシエーション設定（belongs_to :user, :habit、has_many :habit_records）
- モデルテスト作成（18テストケース、42 assertions）
- 全テスト成功: 18 runs, 42 assertions, 0 failures
- 世界一エンジニアレビュー対応（外部キーCASCADE、Date.current統一、インデックス最適化）

<br>

#### ✅ Issue #15: 習慣の日次記録機能（即時保存）
- HabitRecordsController 作成（create / update アクション、ネストされたルーティング）
- Stimulus コントローラー実装（`app/javascript/controllers/habit_record_controller.js`）
  - チェックボックス変更を検知して即時 HTTP リクエスト
  - 保存中のローディングアイコン表示（楽観的UI）
  - タイムアウト処理（10秒）
  - エラー時の自動ロールバック
- Turbo Streams でページリロードなしに即時反映
  - `turbo_stream.replace("habit_record_#{@habit.id}", ...)` で該当カードのみ差し替え
- モデルメソッドに責務を集約（疎結合設計）
  - `HabitRecord.find_or_create_for(user, habit)`: 今日のレコードを取得または作成
  - `HabitRecord#update_completed!(value)`: 完了状態の更新ロジックをモデルに隠蔽
- セキュリティ対策
  - `current_user.habits.active.find` で他ユーザーの習慣へのアクセスを遮断
  - `current_user.habit_records.find` で他ユーザーのレコード操作を遮断
- N+1問題の解消（`today_records_hash` で今日分を一括取得）
- テスト追加（計 88 runs, 262 assertions, 0 failures, 0 errors）
  - 同日に2回 POST しても HabitRecord が1件だけ作成されること
  - 他ユーザーのレコード操作が不可であること
  - AM 4:00 境界値（3:59 / 4:00 / 4:01）の動作確認（`travel_to` 使用）

<br>

#### ✅ Issue #16: 進捗率の自動計算ロジック
- `Habit#weekly_progress_stats(user)` メソッドを追加（進捗率・完了日数を1回のDBアクセスで返す）
- `HabitsController#index` に `@habit_stats` ハッシュを追加（N+1問題を完全解消）
- `views/habits/index.html.erb` を更新（50%固定 → 動的表示、N+1問題対策、レイアウト崩れ修正）
- `habit_records/_habit_record.html.erb` を更新（習慣名の重複表示を削除、チェックボックス＋完了バッジのみに整理）
- テスト追加（モデル9件 + コントローラー4件）
- 全テスト成功: 89 runs, 236 assertions, 0 failures, 0 errors

<br>

#### ✅ Issue #17: 習慣管理機能のテスト
- 統合テスト追加（習慣作成・削除・日次記録・AM4:00境界値）
- 進捗率計算モデルテスト追加（0件・未完了除外・他ユーザー除外・100%上限・先週除外）
- fixturesキー名を `one/two` → `habit_one/habit_two` に統一（可読性向上）
- 既存テスト4ファイルのfixtures参照を一括修正
- 全テスト成功: 119 runs, 322 assertions, 0 failures, 0 errors, 0 skips

<br>

### Week 3（2/21〜）: ダッシュボード・週次振り返り

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|-------|---------|-----------|--------|-----|
| #18 | ダッシュボードの作成 | ✅ 完了 | 2/21 | 4 |
| #19 | WeeklyReflectionモデルの作成 | ✅ 完了 | 2/21 | 2 |
| #20 | WeeklyReflectionHabitSummaryモデルの作成 | ✅ 完了 | 2/21 | 2 |
| #21 | 週次振り返り一覧ページ | ✅ 完了 | 2/21 | 2 |
| #22 | 週次振り返り入力ページ | ✅ 完了 | 2/21 | 4 |
| #23 | 週次振り返り詳細ページ | ✅ 完了 | 2/21 | 2 |
| #24 | PDCA強制ロック機能 | ✅ 完了 | 2/21 | 4 |

<br>

**Week 3 進捗**: 20SP / 20SP（100%） 🎉

<br>

**Week 3 目標**: 20SP

<br>

#### ✅ Issue #18: ダッシュボードの作成
- `DashboardsController` の作成（今週の達成率・今日の習慣チェックリスト）
- AM4:00基準での「今日」の判定（`HabitRecord.today_for_record` を流用）
- N+1問題対策（`today_records_hash` + `habit_stats` ハッシュで一括取得）
- ログイン・登録後のリダイレクト先を `dashboard_path` に統一（直接遷移でUX向上）
- `log_in_as` ヘルパーを `test_helper.rb` に追加（ログイン処理の共通化）
- 既存テスト4ファイルをリダイレクト先変更に追従修正
- 全テスト成功: 121 runs, 324 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #19: WeeklyReflectionモデルの作成
- `WeeklyReflection` モデル作成（user_id, week_start_date, week_end_date, reflection_comment, is_locked）
- UNIQUE制約（user_id + week_start_date）をDBレベル + Railsバリデーションで二重ガード
- AM4:00基準の週計算（`HabitRecord.today_for_record` を流用した `current_week_start_date`）
- `find_or_build_for_current_week` でコントローラー肥大化を防ぐ設計
- カスタムバリデーション（`week_end_date` は `week_start_date + 6日` を強制）
- スコープ追加（`completed`, `pending`, `recent`, `for_week`）
- `Userモデル` に `has_many :weekly_reflections, dependent: :destroy` を追加
- モデルテスト22件追加（AM4:00境界値・UNIQUE制約・CASCADE・週範囲整合性を網羅）
- 全テスト成功: 143 runs, 362 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #20: WeeklyReflectionHabitSummaryモデルの作成

<br>

- スナップショット設計によるデータ不変性の実現（振り返り時点の習慣名・目標値をコピー保存）
- `build_from_habit` クラスメソッド（単体スナップショット構築）
- `create_all_for_reflection!` クラスメソッド（全習慣一括作成・トランザクション保証・冪等性対応）
- 達成率の自動計算（`actual_count / weekly_target × 100`、0〜100にclamp、小数点2桁）
- UNIQUE制約（weekly_reflection_id + habit_id）をDBレベル + Railsバリデーションで二重ガード
- `habit_id` を `null: true` に設定（`on_delete: :nullify` との整合性・スナップショット保護）
- `WeeklyReflection` に `has_many :habit_summaries` を追加
- `Habit` に `has_many :weekly_reflection_habit_summaries` を追加
- 全テスト成功: 172 runs, 409 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #21: 週次振り返り一覧ページ

<br>

- `WeeklyReflectionsController` の作成と `index` アクションの実装
- 日曜 AM4:00 以降かつ未完了の場合のみ「今週を振り返る」ボタンを表示する判定ロジックを実装（`Time.current` による時刻判定で境界値を厳密化）
- 今週の習慣達成率サマリーをプログレスバーで視覚化（N+1問題対策済み）
- 過去の完了済み振り返りのリスト表示（`includes(:habit_summaries)` で N+1 を事前対策）
- データ未存在時の Empty State 実装
- ヘッダーナビに「振り返り」リンクを追加
- `travel_to + current_week_start_date` による日付非依存なテスト設計（固定日付ハードコードを廃止）
- 全テスト成功: 187 runs, 435 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #22: 週次振り返り入力ページ
- `WeeklyReflectionsController` に `new` / `create` アクションを追加
- `form_with model: @weekly_reflection` による Rails らしい RESTful フォーム設計（`url:` / `method:` 不要）
- トランザクション内で振り返り本体（WeeklyReflection）とスナップショット（WeeklyReflectionHabitSummary）を一括保存
- `find_or_build_for_current_week` による冪等性保証（同じ週に2回送信しても1件のみ作成）
- 今週すでに完了済みの場合は詳細ページへリダイレクト（二重送信防止）
- `rescue RecordInvalid` / `rescue RecordNotUnique` による二重防衛エラーハンドリング
- 振り返りフォームに今週の習慣達成率（達成済み・未達成の分類）を表示し、記入内容のヒントを提供
- `validates :reflection_comment, length: { maximum: 1000 }` をモデルに追加
- fixtures の週重複・外部キー違反・ラベル不整合を全て解消し全テストグリーンを達成
- 全テスト成功: 188 runs, 443 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #23: 週次振り返り詳細ページ
- `WeeklyReflectionsController` に `show` アクションを追加（`set_weekly_reflection` で認可チェック）
- `app/views/weekly_reflections/show.html.erb` 作成（総合達成率・習慣別サマリー・振り返りコメント表示）
- `calculate_overall_achievement_rate` を private メソッドに分離（責務分離・`.size` でSQL節約）
- `.order(achievement_rate: :desc)` をハッシュ形式に統一（SQLインジェクション対策）
- `includes(:habit)` を追加（将来の N+1 問題を予防）
- コードレビュー対応 5 項目（order形式・includes・partition削除・メソッド分離・テスト強化）
- フィクスチャ設計：`for_summary_test` / `one_habit_one` / `two_habit_one` の衝突回避設計
- `routes.rb` 整備：`login_path` / `logout_path` エイリアス・`POST /login`・ネストルート追加
- `root "pages#index"` 修正（`pages#top` → `pages#index` でルート404を解消）
- 全テスト成功: 189 runs, 443 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #24: PDCA強制ロック機能
- `ApplicationController` に `locked?` メソッドを追加（月曜AM4:00以降かつ前週振り返り未完了でロック発動）
- `ApplicationController` に `require_unlocked` メソッドを追加（ロック中の操作をサーバー側でブロック）
- `HabitsController` の `create` / `destroy` に `before_action :require_unlocked` を追加（URL直打ち対策）
- ダッシュボード・習慣一覧ページに警告バナーを追加（振り返りページへの導線付き）
- ロック中は新規作成・削除ボタンを非活性化（🔒アイコン表示・cursor-not-allowed）
- 即時保存（チェックボックス）はロック中でも動作維持
- `travel_to` による月曜AM4:00境界値テストを追加（AM3:59はロックしない・AM4:00以降はロック）
- 全テスト成功: 198 runs, 474 assertions, 0 failures, 0 errors, 0 skips

<br>

### Week 4（3/9〜3/15）: ロック解除・UI改善

<br>

 Issue | タイトル | ステータス | 完了日 | SP |
|-------|---------|-----------|--------|-----|
| #25 | 振り返り完了時のPDCAロック自動解除 | ✅ 完了 | 2/22 | 2 |
| #26 | レスポンシブデザインの調整 | ✅ 完了 | 2/23 | 4 |
| #27 | エラーハンドリングの改善 | ✅ 完了 | 2/25 | 3 |
| #28 | セキュリティ対策 | ✅ 完了 | 2/26 | 3 |
| #29 | パフォーマンス最適化 | ✅ 完了 | 2/26 | 2 |
| #30 | 統合テスト（主要フロー） | ✅ 完了 | 2/27 | 6 |

<br>

**Week 4 進捗**: 20SP / 20SP（100%） 🎉

<br>

**Week 4 目標**: 20SP

<br>

#### ✅ Issue #25: 振り返り完了時のPDCAロック自動解除

<br>

- `WeeklyReflection#complete!` を拡張し `completed_at`（日時）と `is_locked: true` を同時更新（整合性保証）
- `completed?` / `pending?` / `week_label` メソッドを `WeeklyReflection` モデルに追加
- ロック中ユーザーが振り返りを投稿すると、今週分の complete! に加えて前週の `pending_reflection` も complete! してロックを解除
- `was_locked` を保存前に記録する設計（`complete!` 後は `locked?` が必ず false になるため）
- ロック解除時は `flash[:unlock]` で緑バナー + `dashboard_path` へリダイレクト
- 通常ユーザーは `weekly_reflections_path` へリダイレクト（元の動作を維持）
- `pdca_lock_test.rb` の `create_last_week_reflection` 引数を `is_locked:` → `completed:` に変更（`completed_at` ベースの判定に統一）
- 全テスト成功: 182 runs, 467 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #26: レスポンシブデザインの調整
- PC版のデザインを完全に維持しつつ、全ページのスマホ対応を実装
- `_header.html.erb` にハンバーガーメニューを追加（PC用ナビは `hidden md:flex` でモバイル時のみ非表示）
- `mobile_menu_controller.js`（Stimulus）を新規作成（外側クリック・ESCキー・メモリリーク対策・ARIA属性完全対応）
- TOPページ `h1` フォントサイズをモバイル対応（`text-4xl sm:text-5xl`）
- 利用フロー矢印を CSS 疑似要素（`::before`）で実装（モバイル: ↓ / PC: →）
- モバイルメニューのボタンを同幅・同高さに統一（`w-full py-4 text-base`）・`focus-visible` でキーボードアクセシビリティ対応
- 全ページ（ダッシュボード・習慣一覧・振り返りページ）のレスポンシブ対応を確認・完了

<br>

#### ✅ Issue #27: エラーハンドリングの改善
- カスタムエラーページ作成（404 / 422 / 500）
- `ErrorsController` を新規作成し、catch-all ルートで未定義URLを404ページへ安全に誘導
- `shared/_form_errors.html.erb` パーシャルを作成し、バリデーションエラー表示を全フォームで共通化
- フラッシュメッセージにアイコン追加・フェードアウトアニメーション付きトースト通知を実装
- `rescue_from` による例外ハンドリング（`StandardError` は本番環境のみ）
- `render file:` → `render template:` 修正（ERBが正しく処理されない問題を解消）
- `_form_errors.html.erb` 内の自己参照 `render` を除去（`SystemStackError` 無限ループを修正）
- `habit_record_row_` にTurboターゲットIDを変更（習慣カードのID重複によるDOM置換崩れを修正）

<br>

#### ✅ Issue #28: セキュリティ対策
- `config/application.rb` にセッションCookie設定を明示化（`secure`・`httponly`・`same_site: :lax`・`expire_after: 14.days`）
- `config/environments/production.rb` にセキュリティヘッダーを `.merge!` で追加（既存Railsデフォルトヘッダーを保持）
- `config/initializers/content_security_policy.rb` を新規作成（CSP設定・nonceによるImportmapインラインスクリプト許可）
- `style_src :unsafe_inline` でプログレスバーのインラインスタイルを許可
- `application_controller.rb` にCSRF/SQLi/XSS/Strong Parameters/セッション管理の実装状況コメントを補強
- CSPブロックによるチェックボックス動作不全・プログレスバー表示崩れを修正

#### ✅ Issue #29: パフォーマンス最適化

<br>

- Bullet gem 導入（development環境でのN+1問題自動検出・ログ出力・フッター表示）
- `build_habit_stats` メソッドを `WeeklyReflectionsController` に実装（`.group(:habit_id).count` によるDB集計でActiveRecordオブジェクト生成をゼロに）
- `ApplicationController#locked?` を `find_by` → `exists?` に変更（SELECT 1 ... LIMIT 1 でメモリロードなし）
- 初週ユーザーの誤ロックを修正（前週レコード存在確認を追加）
- `render_error_page` に turbo_stream 対応を追加（`head status` でMissingTemplateエラーを解消）
- `weekly_reflections` フィクスチャの `completed_at` を全件明示設定（`pending_reflection` は `locked_user` 専用に分離）
- `weekly_reflections (user_id, week_start_date, completed_at)` 3カラム複合インデックス追加（部分インデックス・CONCURRENTLY）
- 全テスト成功: 182 runs, 467 assertions, 0 failures, 0 errors, 0 skips

<br>

#### ✅ Issue #30: 統合テスト（主要フロー）

<br>

- エンドツーエンドの主要フロー統合テスト5ファイル（20テストケース）を新規作成
- 既存11ファイルは個別機能テスト担当・今回は「一連の流れ」のみをカバーする棲み分け設計
- `travel_to` による完全固定日付（2026-03-09/16等）でどの環境・時間帯でも再現性保証
- `log_in_as` ヘルパーを統合テストでも共通利用（test_helper.rb の設計方針を統一維持）
- fixtures 日付との重複回避設計（week_start_date が既存fixtures と衝突しない日付を選定）
- `HabitRecord.where(user: @user).delete_all` でテスト間のデータ干渉を排除（pdca_lock_flow_test）
- Sprockets キャッシュの権限エラー（`Permission denied @ apply2files`）を `sudo rm -rf tmp/cache/assets` で解消
- 全テスト成功: 202 runs, 602 assertions, 0 failures, 0 errors, 0 skips

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
│   ├── assets/
│   │   └── stylesheets/
│   │       └── application.css              # カスタムCSS（.arrow-divider 疑似要素：モバイル↓/PC→の矢印切り替え）
│   ├── controllers/
│   │   ├── application_controller.rb    # ヘルパーメソッド（current_user, logged_in?, require_login, locked?, require_unlocked, render_error_page）※turbo_stream対応済み
│   │   ├── dashboards_controller.rb     # ダッシュボード（index）今週の達成率・今日のチェックリスト
│   │   ├── weekly_reflections_controller.rb # 週次振り返り（index, new, create, show）complete!によるロック解除・was_locked保存前記録・build_habit_statsによるDB集計
│   │   ├── habit_records_controller.rb  # 習慣記録（create, update）ネストされたルーティング
│   │   ├── habits_controller.rb         # 習慣管理（index, new, create, destroy）
│   │   ├── errors_controller.rb         # カスタムエラーページ（not_found / unprocessable / internal_server_error）catch-all対応
│   │   ├── pages_controller.rb          # ランディングページ（ログイン済みはdashboardへリダイレクト）
│   │   ├── sessions_controller.rb       # ログイン・ログアウト（new, create, destroy）
│   │   └── users_controller.rb          # ユーザー登録（new, create）
│   ├── javascript/
│   │   └── controllers/
│   │       ├── habit_record_controller.js   # Stimulusコントローラー（即時保存・楽観的UI）
│   │       └── mobile_menu_controller.js    # Stimulusコントローラー（ハンバーガーメニュー開閉・外側クリック・ESCキー・メモリリーク対策・ARIA対応）
│   ├── models/
│   │   ├── user.rb                       # Userモデル（認証機能、has_many :habits, :habit_records, :weekly_reflections）
│   │   ├── habit.rb                      # Habitモデル（習慣管理、論理削除機能、has_many :habit_records）
│   │   ├── habit_record.rb               # HabitRecordモデル（日次記録、AM4:00基準、UNIQUE制約）
│   │   ├── weekly_reflection.rb              # WeeklyReflectionモデル（UNIQUE制約・AM4:00基準週計算・complete!/completed?/pending?/week_label）
│   │   └── weekly_reflection_habit_summary.rb # スナップショット設計・達成率計算・冪等性対応
│   └── views/
│       ├── habit_records/
│       │   ├── _habit_record.html.erb        # チェックボックス付き習慣記録カード（Turbo Streamターゲット）
│       │   └── _habit_record_error.html.erb  # エラー時の差し替えパーシャル
│       ├── layouts/
│       │   └── application.html.erb      # 全ページ共通レイアウト（ヘッダー・フッター・フラッシュ）
│       ├── shared/
│       │   ├── _header.html.erb          # 共通ヘッダー（ログイン状態で表示切替・Issue #26でハンバーガーメニュー追加）
│       │   ├── _footer.html.erb          # 共通フッター（全ページ）
│       │   └── _form_errors.html.erb     # バリデーションエラー共通パーシャル（全フォームで使用）
│       ├── habits/
│       │   ├── index.html.erb            # 習慣一覧ページ（カード形式、レスポンシブ対応）
│       │   └── new.html.erb              # 習慣新規作成フォーム
│       ├── dashboards/
│       │   └── index.html.erb            # ダッシュボード（今週の達成率・今日のチェックリスト）
│       ├── weekly_reflections/
│       │   ├── index.html.erb                # 週次振り返り一覧（振り返りボタン・達成率サマリー・履歴リスト）
│       │   ├── new.html.erb                  # 週次振り返り入力フォーム（今週の習慣達成実績・コメント入力）
│       │   └── show.html.erb                 # 週次振り返り詳細（総合達成率・習慣別サマリー・コメント表示）
│       ├── errors/
│       │   ├── not_found.html.erb              # 404エラーページ
│       │   ├── unprocessable_entity.html.erb   # 422エラーページ
│       │   └── internal_server_error.html.erb  # 500エラーページ
│       ├── pages/
│       │   └── index.html.erb            # TOPページ（シンプル化済み）
│       ├── sessions/
│       │   └── new.html.erb              # ログインフォーム
│       └── users/
│           └── new.html.erb              # 新規登録フォーム
├── db/
│   ├── migrate/
│   │   ├── YYYYMMDDHHMMSS_create_users.rb         # Usersテーブル作成
│   │   ├── YYYYMMDDHHMMSS_create_habits.rb        # Habitsテーブル作成
│   │   ├── YYYYMMDDHHMMSS_create_habit_records.rb # HabitRecordsテーブル作成（AM4:00基準、UNIQUE制約）
│   │   ├── YYYYMMDDHHMMSS_create_weekly_reflections.rb # WeeklyReflectionsテーブル作成
│   │   ├── YYYYMMDDHHMMSS_create_weekly_reflection_habit_summaries.rb # WeeklyReflectionHabitSummariesテーブル作成
│   │   ├── YYYYMMDDHHMMSS_add_completed_at_to_weekly_reflections.rb # completed_atカラム追加（振り返り完了日時の記録）
│   │   └── YYYYMMDDHHMMSS_add_performance_indexes.rb # パフォーマンス最適化インデックス（weekly_reflections 3カラム複合インデックス・CONCURRENTLY）
│   ├── schema.rb                              # データベーススキーマ
│   └── seeds.rb                               # サンプルデータ（2ユーザー、計10件の習慣）
├── docs/
│   ├── er-diagram-mvp.md                 # ER図（Mermaid形式）
│   ├── database-schema-mvp.md            # テーブル定義書
│   └── production-check-issue-7.md       # Issue #7 本番環境確認レポート
├── test/
│   ├── models/
│   │   ├── user_test.rb                  # Userモデルテスト（13テストケース）
│   │   ├── habit_test.rb                 # Habitモデルテスト（20テストケース）
│   │   ├── habit_record_test.rb          # HabitRecordモデルテスト（18テストケース、42 assertions）
│   │   ├── habit_progress_test.rb        # 進捗率計算モデルテスト（6テストケース）Issue #17
│   │   ├── weekly_reflection_test.rb          # WeeklyReflectionモデルテスト（22テストケース）Issue #19
│   │   └── weekly_reflection_habit_summary_test.rb # WeeklyReflectionHabitSummaryモデルテスト Issue #20
│   ├── integration/
│   │   ├── user_registration_test.rb     # ユーザー登録統合テスト（2テストケース）
│   │   ├── user_login_test.rb            # ログイン・ログアウト統合テスト（4テストケース）
│   │   ├── habit_creation_test.rb        # 習慣新規作成統合テスト（7テストケース）
│   │   ├── habit_deletion_test.rb        # 習慣削除統合テスト（4テストケース）
│   │   ├── habit_record_instant_save_test.rb  # 習慣記録即時保存統合テスト（5テストケース）
│   │   ├── habit_management_test.rb           # 習慣管理統合テスト（11テストケース）Issue #17
│   │   ├── dashboard_test.rb                  # ダッシュボード統合テスト（3テストケース）Issue #18
│   │   ├── weekly_reflection_index_test.rb    # 週次振り返り一覧統合テスト Issue #21
│   │   ├── habit_daily_record_test.rb         # 日次記録・AM4:00境界値テスト（6テストケース）Issue #17
│   │   ├── weekly_reflection_index_test.rb    # 週次振り返り一覧統合テスト Issue #21
│   │   ├── weekly_reflection_create_test.rb   # 週次振り返り作成統合テスト（E2Eフロー・1000文字バリデーション）Issue #22
│   │   ├── pdca_lock_test.rb                  # PDCAロック統合テスト（月曜AM4:00判定・ロック中の作成/削除ブロック・即時保存維持・completed_atベース判定）Issue #24/#25
│   │   ├── user_auth_flow_test.rb             # ユーザー認証E2Eフロー統合テスト（登録→ダッシュボード→ログアウト→再ログイン・未ログイン時アクセス制限）Issue #30
│   │   ├── habit_full_flow_test.rb            # 習慣E2Eフロー統合テスト（作成→日次記録→進捗確認・Turbo Stream検証・Empty State）Issue #30
│   │   ├── weekly_reflection_flow_test.rb     # 週次振り返りE2Eフロー統合テスト（一覧→新規作成→保存→詳細確認・スナップショット作成確認）Issue #30
│   │   ├── pdca_lock_flow_test.rb             # PDCAロックE2Eフロー統合テスト（ロック発動→解除→習慣作成・初週ユーザー確認・travel_to完全固定日付）Issue #30
│   │   └── error_cases_test.rb               # エラーケース統合テスト（404・認可・バリデーション422・他ユーザーデータアクセス防止）Issue #30
│   ├── controllers/
│   │   ├── dashboards_controller_test.rb      # DashboardsControllerテスト（3テストケース）Issue #18
│   │   ├── weekly_reflections_controller_test.rb # WeeklyReflectionsControllerテスト（show/index/new/create・認可・境界値・ロック解除）Issue #21/#22/#23/#25
│   │   ├── habits_controller_test.rb     # HabitsControllerテスト（2テストケース）
│   │   └── habit_records_controller_test.rb  # HabitRecordsControllerテスト（AM4:00境界値・セキュリティ）
│   └── fixtures/
│       ├── users.yml                     # テスト用ユーザーデータ
│       ├── habits.yml                    # テスト用習慣データ（habit_one/habit_two/habit_deleted）
│       ├── habit_records.yml             # テスト用習慣記録データ（AM4:00基準、UNIQUE制約テスト）
│       ├── weekly_reflections.yml        # テスト用週次振り返りデータ（for_summary_test含む・travel_to週と非衝突設計）
│       └── weekly_reflection_habit_summaries.yml  # テスト用習慣サマリーデータ（スコープテスト用達成率設計）
├── bin/
│   └── docker-entrypoint                     # コンテナ起動時の初期化スクリプト
├── config/
│   ├── database.yml                      # DB接続設定
│   ├── initializers/
│   │   └── content_security_policy.rb   # CSP設定（nonce方式・script_src/style_src/img_src等）
│   ├── environments/
│   │   └── production.rb                # 本番用セキュリティヘッダー（X-Frame-Options・Referrer-Policy等を .merge! で追加）
│   └── routes.rb                         # ルーティング設定（習慣管理追加）
├── Dockerfile                            # 本番環境用Dockerfile
├── Dockerfile.dev                        # 開発環境用Dockerfile
├── docker-compose.yml                    # Docker Compose設定
├── render.yaml                           # Renderデプロイ設定
└── Gemfile                               # Gem依存関係
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
```erb
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
```

<br>

**共通フッター（app/views/shared/_footer.html.erb）**:
```erb
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
```

<br>

**レイアウトファイル（app/views/layouts/application.html.erb）**:
```erb
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
```

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

#### 習慣一覧ページ（Issue #11）

<br>

**実装日**: 2026年2月15日

<br>

**実装機能**:

<br>

**HabitsController（app/controllers/habits_controller.rb）**:
```ruby
class HabitsController < ApplicationController
  # ログインしていないユーザーはアクセスできないようにする
  before_action :require_login

  # GET /habits
  def index
    # 現在ログインしているユーザーの習慣を取得
    # activeスコープで論理削除されていない習慣のみを取得
    # created_at: :descで新しい順に並び替え
    @habits = current_user.habits.active.order(created_at: :desc)
  end
end
```

<br>

### ルーティング

<br>

**config/routes.rb**:
```ruby
Rails.application.routes.draw do
  root "pages#index"
  
  resources :users, only: [:new, :create]
  
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
  
  # 習慣管理（index のみ）
  resources :habits, only: [:index]
end
```

<br>

**ルーティング一覧**:
```
      Prefix Verb   URI Pattern              Controller#Action
        root GET    /                        pages#index
       users POST   /users(.:format)         users#create
    new_user GET    /users/new(.:format)     users#new
       login GET    /login(.:format)         sessions#new
             POST   /login(.:format)         sessions#create
      logout DELETE /logout(.:format)        sessions#destroy
      habits GET    /habits(.:format)        habits#index
```

<br>

**習慣一覧ビュー（app/views/habits/index.html.erb）**:

<br>

**レイアウト構造**:
- コンテナ: max-w-7xl mx-auto（最大幅制限、中央揃え）
- パディング: px-4 sm:px-6 lg:px-8（レスポンシブな左右パディング）
- グリッド: grid-cols-1 md:grid-cols-2 lg:grid-cols-3（レスポンシブなカラム数）
- ギャップ: gap-6（カード間の隙間 = 1.5rem = 24px）

<br>

**カードデザイン**:
- 角丸: rounded-xl（12px）
- 影: shadow-sm（軽い影）
- ホバー時: hover:shadow-md（影を濃くする）
- トランジション: transition（0.2秒でスムーズにアニメーション）
- ボーダー: border border-gray-200

<br>

**進捗率表示（仮データ）**:
- プログレスバー外側: bg-gray-200 h-2 rounded-full
- プログレスバー内側: bg-blue-500 h-2 rounded-full（width: 50%固定）
- パーセンテージ: text-sm font-bold text-blue-600（50%固定）
- 実績表示: text-xs text-gray-400（3/X日固定）

<br>

**Empty State（習慣0件時）**:
- 破線ボーダー: border-2 border-dashed border-gray-300
- 円形アイコン: w-16 h-16 rounded-full bg-blue-100（青色の円形背景）
- メッセージ: 「まだ習慣が登録されていません」
- CTAボタン: 「習慣を登録する」（青色、px-6 py-3）

<br>

**共通ヘッダーへの追加**:
```erb
<% if logged_in? %>
  <%= link_to "習慣一覧", habits_path, 
      class: "text-gray-600 hover:text-gray-900 px-3 py-2 text-sm font-medium transition-colors" %>
  
    <%= current_user.name %> さん
  
  ...
<% end %>
```

<br>

**seeds.rb（サンプルデータ）**:
```ruby
# ユーザー1: test@example.com
user1 = User.create!(
  name: "山田太郎",
  email: "test@example.com",
  password: "password123",
  password_confirmation: "password123"
)

# 5件の習慣を作成
user1.habits.create!(name: "読書（15分以上）", weekly_target: 7)
user1.habits.create!(name: "筋トレ", weekly_target: 5)
user1.habits.create!(name: "瞑想（10分）", weekly_target: 7)
user1.habits.create!(name: "英語学習", weekly_target: 5)
user1.habits.create!(name: "ジョギング", weekly_target: 3)

# 論理削除された習慣（テスト用）
deleted_habit = user1.habits.create!(
  name: "削除された習慣（表示されないはず）",
  weekly_target: 7
)
deleted_habit.soft_delete
```

<br>

**UI/UX設計のポイント**:

<br>

**1. レスポンシブデザイン**:
- モバイル（〜767px）: 1列表示
- タブレット（768px〜1023px）: 2列表示
- PC（1024px〜）: 3列表示

<br>

**2. カードの視覚階層**:
- 上部エリア（flex-1）: 習慣名、詳細情報
- 下部エリア（固定）: 進捗率、プログレスバー
- 縦方向のフレックスボックス（flex flex-col）で進捗エリアを下部に固定

<br>

**3. アイコンの色分け**:
- チェック型: text-blue-500（青色）
- 週次目標: text-green-500（緑色）
- 視覚的に情報を区別しやすくする

<br>

**4. アニメーション効果**:
- ホバー時に影が濃くなる（hover:shadow-md）
- トランジション効果（transition）で滑らかに変化
- ユーザーの操作に対する視覚的フィードバック

<br>

**技術的な工夫**:

<br>

**1. link_to ヘルパーメソッド使用**:
```erb
<%= link_to "#", class: "..." do %>
  新しい習慣を追加
<% end %>
```
- `<a href="#">` よりも推奨される書き方
- 将来的にパスが変更されても自動的に追従
- Railsのルーティングと連携

<br>

**2. Tailwind CSSのユーティリティクラス**:
- カスタムCSS不要
- コンパイル不要（tailwindcss-railsのコアクラスのみ使用）
- メンテナンス性が高い

<br>

**3. コメントの充実**:
```erb
<%# tracking-tight: 文字間隔を詰めて読みやすくする %>
習慣管理
```
- 各Tailwindクラスの意味を説明
- 初心者でも理解しやすい
- 将来のメンテナンスが容易

<br>

**セキュリティ対策**:
- `before_action :require_login` でログイン必須
- `current_user.habits` でログインユーザーの習慣のみ取得
- 他のユーザーの習慣にはアクセス不可

<br>

**論理削除の動作確認**:
```ruby
# Railsコンソールでの確認
user = User.find_by(email: "test@example.com")

# 有効な習慣のみ取得
user.habits.active.count  # => 5

# 論理削除を実行
habit = user.habits.first
habit.soft_delete

# 削除後の確認
user.habits.active.count   # => 4
user.habits.deleted.count  # => 1

# 復元
habit.update(deleted_at: nil)
user.habits.active.count   # => 5
```

<br>

## 習慣新規作成機能（Issue #12）

<br>

### コントローラー実装

<br>

**HabitsController**:
```ruby
# app/controllers/habits_controller.rb

class HabitsController < ApplicationController
  before_action :require_login

  # GET /habits - 習慣一覧ページ
  def index
    @habits = current_user.habits.active.order(created_at: :desc)
  end

  # GET /habits/new - 新規作成フォーム
  def new
    @habit = current_user.habits.build
  end

  # POST /habits - 習慣の作成処理
  def create
    @habit = current_user.habits.build(habit_params)
    
    if @habit.save
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の登録に失敗しました"
      render :new, status: :unprocessable_entity
    end
  end

  private

  def habit_params
    params.require(:habit).permit(:name, :weekly_target)
  end
end
```

<br>

**実装の特徴**:
- `current_user.habits.build`: user_id を自動設定（セキュリティ対策）
- Strong Parameters: `:name`, `:weekly_target` のみ許可
- 保存成功時: `redirect_to habits_path` で一覧ページへリダイレクト
- 保存失敗時: `render :new, status: :unprocessable_entity` で422エラーを返す（Turbo対応）

<br>

### フォーム実装

<br>

**習慣新規作成フォーム（app/views/habits/new.html.erb）**:
```erb
  新しい習慣を追加

  <%= form_with model: @habit, local: true do |f| %>
    <% if @habit.errors.any? %>
      <%= @habit.errors.count %> 件のエラーがあります

      <% @habit.errors.full_messages.each do |message| %>
        <%= message %>
      <% end %>

    <% end %>
    
    <%= f.label :name, "習慣名", class: "block text-sm font-medium text-gray-700 mb-2" %>
    <%= f.text_field :name,
        placeholder: "例: 読書、筋トレ、英語学習",
        class: "w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500" %>
      
      習慣名は50文字以内で入力してください
      
    

    
    
    <%= f.label :weekly_target, "週次目標値", class: "block text-sm font-medium text-gray-700 mb-2" %>
    <%= f.number_field :weekly_target,
        min: 1,
        max: 7,
        value: f.object.weekly_target || 7,
        placeholder: "例: 7（週7回実施）",
        class: "w-full px-4 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500" %>
      
      週あたりの実施回数を設定します（1〜7回）
      
    

    
    
    <%= link_to "キャンセル", habits_path,
        class: "flex-1 px-4 py-2 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 transition text-center" %>
    <%= f.submit "登録する",
        class: "flex-1 px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition" %>
    
  <% end %>

```

<br>

**フォーム設計のポイント**:
- `form_with model: @habit`: RESTfulなフォーム生成
- `value: f.object.weekly_target || 7`: デフォルト値7、エラー後も入力値を保持
- `local: true`: Turboの非同期送信を無効化（通常のHTMLフォーム送信）
- レスポンシブデザイン: `max-w-2xl`（672px）でフォームに適した幅

<br>

### バリデーションエラー表示

<br>

**エラーボックスの実装**:
```erb
<% if @habit.errors.any? %>
  
  <%= @habit.errors.count %> 件のエラーがあります
    
  <% @habit.errors.full_messages.each do |message| %>
    <%= message %>
  <% end %>
  
<% end %>
```

<br>

**エラー表示の特徴**:
- `@habit.errors.any?`: バリデーションエラーの有無を判定
- `@habit.errors.count`: エラー件数を表示
- `@habit.errors.full_messages`: すべてのエラーメッセージを配列で取得
- 赤色のエラーボックス（`bg-red-50`, `border-l-4`, `border-red-500`）
- 日本語対応（`pluralize` は使用しない）

<br>

### レイアウト改善

<br>

**共通レイアウト（app/views/layouts/application.html.erb）**:
```erb
  HabitFlow
    
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>

  <% flash.each do |message_type, message| %>
    <%= message %>
  <% end %>

  <%= render 'shared/header' %>
    <%= yield %>
  <%= render 'shared/footer' %>
```

<br>

**レイアウトの特徴**:
- `min-h-screen flex flex-col`: フッターを最下部に固定
- `flex-1`: メインコンテンツが残りスペースを全て使う
- フラッシュメッセージの条件分岐表示（成功: 緑、エラー: 赤）

<br>

**共通ヘッダー（app/views/shared/_header.html.erb）**:
```erb
  <%= link_to "HabitFlow", root_path, class: "hover:text-blue-700 transition-colors" %>

  <% if logged_in? %>

    <%= link_to "習慣一覧", habits_path, class: "text-gray-600 hover:text-gray-900 px-3 py-2 text-sm font-medium transition-colors" %>
      <%= current_user.name %> さん
    <%= button_to "ログアウト", logout_path,
      method: :delete,
      class: "px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 transition-colors",
      data: { turbo_confirm: "ログアウトしますか？" } %>

  <% else %>

    <%= link_to "ログイン", login_path, class: "text-gray-600 hover:text-gray-900 px-3 py-2 text-sm font-medium transition-colors" %>
    <%= link_to "新規登録", new_user_path, class: "px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 transition-colors" %>

  <% end %>
```

<br>

**ヘッダーの特徴**:
- ログイン状態に応じて自動的に表示を切り替え
- ログイン済み: 習慣一覧リンク + ユーザー名 + ログアウトボタン
- 未ログイン: ログイン + 新規登録リンク

<br>

### レスポンシブデザイン

<br>

**ページごとの最大幅設定**:
- 習慣一覧ページ: `max-w-7xl`（1280px）- 広いコンテンツ
- 習慣新規作成ページ: `max-w-2xl`（672px）- フォームに適した幅
- ログイン・ユーザー登録ページ: `max-w-md`（448px）- 狭いフォーム

<br>

**左右パディング（レスポンシブ対応）**:
```erb
class="px-4 sm:px-6 lg:px-8"
```
- モバイル（デフォルト）: 16px（`px-4`）
- タブレット（640px以上）: 24px（`sm:px-6`）
- PC（1024px以上）: 32px（`lg:px-8`）

<br>

**間隔の統一**:
- ヘッダーとカードの間隔: 24px（`mb-6`）
- カード間の間隔: 24px（`gap-6`）
- デザインのリズムを統一することで見やすさ向上

<br>

### セキュリティ対策

<br>

**Strong Parameters**:
```ruby
def habit_params
  params.require(:habit).permit(:name, :weekly_target)
end
```
- `:name`, `:weekly_target` のみ許可
- `:user_id` は permit に含めない（自動設定）
- 不正なパラメータを無視

<br>

**user_id の自動設定**:
```ruby
@habit = current_user.habits.build(habit_params)
```
- `current_user.habits.build` で user_id を自動設定
- ユーザーが他人の習慣を作成できないようにする

<br>

**セキュリティテスト**:
```ruby
test "他ユーザーのuser_idを指定しても無視されること（セキュリティテスト）" do
  post habits_path, params: {
    habit: {
      name: "ハッキング試み",
      weekly_target: 7,
      user_id: @other_user.id  # 不正なuser_id
    }
  }
  
  assert_equal @user.id, Habit.last.user_id  # 現在のユーザーIDで作成される
  assert_not_equal @other_user.id, Habit.last.user_id  # 他ユーザーIDは無視される
end
```

<br>

### 統合テスト

<br>

**テストファイル（test/integration/habit_creation_test.rb）**:
```ruby
require "test_helper"

class HabitCreationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:two)
  end

  test "ログイン後に習慣を作成できること" do
    # ログイン
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password"
      }
    }
    
    # 新規作成フォームにアクセス
    get new_habit_path
    assert_response :success
    
    # 習慣を作成
    assert_difference("Habit.count", 1) do
      post habits_path, params: {
        habit: {
          name: "朝のランニング",
          weekly_target: 7
        }
      }
    end
    
    # 一覧ページにリダイレクト
    assert_redirected_to habits_path
    follow_redirect!
    
    # フラッシュメッセージ確認
    assert_select "div", text: /習慣を登録しました/
    
    # user_id が正しく設定されているか確認
    assert_equal @user.id, Habit.last.user_id
  end

  test "習慣名が空欄の場合はエラーメッセージが表示されること" do
    post login_path, params: { session: { email: @user.email, password: "password" } }
    
    # 習慣作成（習慣名が空欄）
    assert_no_difference("Habit.count") do
      post habits_path, params: {
        habit: {
          name: "",
          weekly_target: 7
        }
      }
    end
    
    # 422エラー
    assert_response :unprocessable_entity
    
    # エラーメッセージ表示
    assert_select "div.bg-red-50"
    assert_select "li", text: /Name can't be blank/
  end

  test "他ユーザーのuser_idを指定しても無視されること（セキュリティテスト）" do
    post login_path, params: { session: { email: @user.email, password: "password" } }
    
    post habits_path, params: {
      habit: {
        name: "ハッキング試み",
        weekly_target: 7,
        user_id: @other_user.id  # 不正なuser_id
      }
    }
    
    # 現在のユーザーIDで作成される
    assert_equal @user.id, Habit.last.user_id
    # 他ユーザーIDは無視される
    assert_not_equal @other_user.id, Habit.last.user_id
  end
end
```

<br>

**テストカバレッジ**:
- 正常系テスト: 習慣作成成功、一覧ページへリダイレクト
- 異常系テスト: 習慣名空欄、週次目標値0、週次目標値8
- セキュリティテスト: 不正なuser_id送信を無視
- 未ログインテスト: フォームアクセス拒否、習慣作成拒否

<br>

**テスト結果**:
```
49 runs, 140 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### fixtures 修正

<br>

**ユーザーfixtures（test/fixtures/users.yml）**:
```yaml
one:
  name: Test User
  email: fixture_one@example.com
  password_digest: <%= BCrypt::Password.create("password") %>

two:
  name: Other User
  email: fixture_two@example.com
  password_digest: <%= BCrypt::Password.create("password") %>
```

<br>

**習慣fixtures（test/fixtures/habits.yml）**:
```yaml
one:
  user: one
  name: 読書
  weekly_target: 7
  deleted_at: null

two:
  user: two
  name: 筋トレ
  weekly_target: 5
  deleted_at: null

deleted_one:
  user: one
  name: 削除済み習慣
  weekly_target: 3
  deleted_at: <%= 1.day.ago %>
```

<br>

**fixtures 修正の理由**:
- メールアドレスの衝突回避
  - fixtures: `fixture_one@example.com`, `fixture_two@example.com`
  - テストコード: `user_#{SecureRandom.hex(4)}@example.com`
- 習慣件数の制限
  - `users(:one)` に紐づく習慣を制限（削除テストの正確性向上）

<br>

### モデル修正

<br>

**User モデル（app/models/user.rb）**:
```ruby
class User < ApplicationRecord
  has_many :habits, dependent: :destroy
  
  before_save { self.email = email.downcase }
  
  validates :name, presence: true, length: { maximum: 50 }
  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i }
  
  has_secure_password
  
  # 🔴 追加: password の最低文字数バリデーション
  # has_secure_password だけでは最低文字数をチェックしないため
  validates :password, length: { minimum: 8 }, allow_nil: true
end
```

<br>

**モデル修正の理由**:
- `has_secure_password` は最低文字数をチェックしない
- 明示的に `validates :password, length: { minimum: 8 }` を追加

<br>

### ルーティング

<br>

**config/routes.rb**:
```ruby
Rails.application.routes.draw do
  root "pages#index"
  
  resources :users, only: [:new, :create]
  
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
  
  # 習慣管理（index, new, create）
  resources :habits, only: [:index, :new, :create]
end
```

<br>

**ルーティング一覧**:
```
      Prefix Verb   URI Pattern              Controller#Action
        root GET    /                        pages#index
       users POST   /users(.:format)         users#create
    new_user GET    /users/new(.:format)     users#new
       login GET    /login(.:format)         sessions#new
             POST   /login(.:format)         sessions#create
      logout DELETE /logout(.:format)        sessions#destroy
      habits GET    /habits(.:format)        habits#index
             POST   /habits(.:format)        habits#create
   new_habit GET    /habits/new(.:format)    habits#new
```

<br>

### 技術的な学び

<br>

**1. fixtures と create! は併用しない**:
- fixtures 使用時: `users(:one)` を使う
- create! 使用時: `SecureRandom.hex` でユニーク化

<br>

**2. IntegrationTest では session に直接アクセス不可**:
- `logged_in?` メソッドは使えない
- 挙動ベースでテスト（`get new_habit_path` → `assert_redirected_to login_path`）

<br>

**3. エラーメッセージはバリデーションルールと一致させる**:
- `greater_than_or_equal_to: 1` → `"must be greater than or equal to 1"`

<br>

**4. すべてのテストに assert を書く**:
- `missing assertions` 警告を防ぐ

<br>

**5. テストが正しい前提で考えない**:
- テスト自体が間違っていることもある

<br>

## 習慣削除機能（Issue #13）

<br>

### コントローラー実装

<br>

**HabitsController（destroy アクション）**:
```ruby
# app/controllers/habits_controller.rb

class HabitsController < ApplicationController
  # ログインしていないユーザーはアクセスできないようにする
  before_action :require_login
  
  # destroy アクション実行前に @habit を取得
  # set_habit メソッドで current_user の習慣のみを取得するため、
  # 他のユーザーの習慣を削除しようとしても NotFound エラーになる
  before_action :set_habit, only: [:destroy]

  # GET /habits
  def index
    @habits = current_user.habits.active.order(created_at: :desc)
  end

  # GET /habits/new
  def new
    @habit = current_user.habits.build
  end

  # POST /habits
  def create
    @habit = current_user.habits.build(habit_params)
    
    if @habit.save
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の登録に失敗しました"
      render :new, status: :unprocessable_entity
    end
  end
  
  # DELETE /habits/:id
  def destroy
    # @habit は before_action :set_habit で取得済み
    
    # 論理削除を実行（deleted_at に現在時刻を設定）
    # soft_delete メソッドは Habit モデルで定義済み
    if @habit.soft_delete
      # 削除成功時: 成功メッセージを設定して一覧ページへリダイレクト
      flash[:notice] = "習慣を削除しました"
      redirect_to habits_path, status: :see_other
    else
      # 削除失敗時: エラーメッセージを設定して一覧ページへリダイレクト
      # 通常、soft_delete は失敗しないが、万が一のためのエラーハンドリング
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  private

  def habit_params
    params.require(:habit).permit(:name, :weekly_target)
  end
  
  # @habit を取得するメソッド
  # current_user.habits.active で現在のユーザーの有効な習慣のみを検索
  # find(params[:id]) で指定された id の習慣を取得
  # 他のユーザーの習慣や論理削除済みの習慣は取得できない
  def set_habit
    @habit = current_user.habits.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # 習慣が見つからない場合（他のユーザーの習慣 or 削除済み）
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end
end
```

<br>

**実装の特徴**:
- `before_action :set_habit`: destroy アクション実行前に @habit を取得
- `@habit.soft_delete`: Habit モデルで定義済みの論理削除メソッド
- `status: :see_other`: Rails 7 / Turbo 対応のリダイレクト（HTTP 303）
- `rescue ActiveRecord::RecordNotFound`: 習慣が見つからない場合のエラーハンドリング

<br>

### 削除ボタンの実装

<br>

**習慣一覧ページ（app/views/habits/index.html.erb）**:
```erb
  <%= habit.name %>
  <!-- method: :delete で DELETE /habits/:id にリクエスト -->

  <%= button_to habit_path(habit), 
      method: :delete,
      data: { turbo_confirm: "本当に削除しますか？\n「#{habit.name}」を削除すると、過去の記録も表示されなくなります。" },
      class: "px-3 py-1 text-sm bg-red-600 text-white rounded-md hover:bg-red-700 transition-colors" do %>
    削除
  <% end %>
```

<br>

**実装の特徴**:
- `button_to` を使用（DELETEリクエストはフォーム送信が必要）
- `method: :delete`: DELETE リクエストを送信
- `data: { turbo_confirm: "..." }`: Turbo Confirm で削除前に確認ダイアログを表示
- `\n` で改行して、削除される習慣名を表示
- 赤色のボタン（`bg-red-600`）で視覚的に警告

<br>

### 論理削除の実装

<br>

**Habitモデル（app/models/habit.rb）**:
```ruby
# 論理削除を実行するメソッド
# deleted_at カラムに現在時刻を設定することで「削除済み」とマークする
# 物理削除（destroy）ではなく論理削除を使う理由:
#   - 過去の振り返りデータとの整合性を保つため
#   - weekly_reflection_habit_summaries でスナップショットとして参照されるため
def soft_delete
  # touch: 指定したカラムに現在時刻を設定するメソッド
  # touch(:deleted_at) => deleted_at = Time.current
  # updated_at も自動的に更新される
  touch(:deleted_at)
end
```

<br>

**論理削除の設計思想**:
- `deleted_at` に現在時刻を設定することで「削除済み」とマークする
- データベースから物理的に削除しない
- 過去の振り返りデータ（weekly_reflection_habit_summaries）との整合性を保つ
- スナップショット設計との連携

<br>

### セキュリティ対策

<br>

**1. before_action :set_habit**:
```ruby
before_action :set_habit, only: [:destroy]

def set_habit
  @habit = current_user.habits.active.find(params[:id])
rescue ActiveRecord::RecordNotFound
  flash[:alert] = "習慣が見つかりませんでした"
  redirect_to habits_path
end
```

<br>

**特徴**:
- `current_user.habits.active`: 現在のユーザーの有効な習慣のみを検索
- 他のユーザーの習慣は取得できない
- 論理削除済みの習慣は取得できない（`active` スコープで除外）
- `rescue ActiveRecord::RecordNotFound`: 習慣が見つからない場合のエラーハンドリング

<br>

**2. status: :see_other**:
```ruby
redirect_to habits_path, status: :see_other
```

<br>

**特徴**:
- Rails 7 / Turbo 対応のリダイレクト
- HTTP 303 ステータスコードを返す
- ブラウザの「戻る」ボタンを押しても、削除リクエストが再送信されない

<br>

### 統合テスト

<br>

**テストファイル（test/integration/habit_deletion_test.rb）**:
```ruby
require "test_helper"

class HabitDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:two)
    @habit = habits(:one)
    @other_habit = habits(:two)
    
    # test ユーザーでログイン
    post login_path, params: {
      session: {
        email: @user.email,
        password: "password"
      }
    }
  end
  
  test "ログイン後に習慣を論理削除できること" do
    # 削除前の習慣数を確認（有効な習慣のみ）
    assert_equal 1, @user.habits.active.count
    
    # 削除リクエストを送信
    assert_difference("Habit.active.count", -1) do
      delete habit_path(@habit)
    end
    
    # 削除後の習慣数を確認（有効な習慣のみ）
    assert_equal 0, @user.habits.active.count
    
    # 論理削除されていることを確認（deleted_at が設定されている）
    @habit.reload
    assert_not_nil @habit.deleted_at
    
    # 物理削除されていないことを確認
    assert Habit.exists?(@habit.id)
    
    # リダイレクト先の確認
    assert_redirected_to habits_path
    follow_redirect!
    
    # 成功メッセージが表示されることを確認
    assert_select "div", text: /習慣を削除しました/
  end
  
  test "他のユーザーの習慣は削除できないこと（セキュリティテスト）" do
    # 削除前の習慣数を確認
    assert_equal 1, @other_user.habits.active.count
    
    # 他のユーザーの習慣を削除しようとする
    assert_no_difference("Habit.active.count") do
      delete habit_path(@other_habit)
    end
    
    # 他のユーザーの習慣数は変わらないことを確認
    assert_equal 1, @other_user.habits.active.count
    
    # 習慣一覧ページにリダイレクトされることを確認
    assert_redirected_to habits_path
    follow_redirect!
    
    # エラーメッセージが表示されることを確認
    assert_select "div", text: /習慣が見つかりませんでした/
  end
  
  test "論理削除済みの習慣は再度削除できないこと" do
    # 習慣を論理削除
    @habit.soft_delete
    
    # 削除前の習慣数を確認（有効な習慣のみ）
    assert_equal 0, @user.habits.active.count
    
    # 論理削除済みの習慣を削除しようとする
    assert_no_difference("Habit.count") do
      delete habit_path(@habit)
    end
    
    # 習慣一覧ページにリダイレクトされることを確認
    assert_redirected_to habits_path
    follow_redirect!
    
    # エラーメッセージが表示されることを確認
    assert_select "div", text: /習慣が見つかりませんでした/
  end
  
  test "未ログイン時は習慣を削除できないこと" do
    # ログアウト
    delete logout_path
    
    # 削除前の習慣数を確認
    assert_equal 1, @user.habits.active.count
    
    # 習慣を削除しようとする
    assert_no_difference("Habit.active.count") do
      delete habit_path(@habit)
    end
    
    # ログインページにリダイレクトされることを確認
    assert_redirected_to login_path
  end
end
```

<br>

**テストカバレッジ**:
- 正常系テスト: ログイン後に習慣を論理削除できること
- セキュリティテスト: 他のユーザーの習慣は削除できないこと
- 異常系テスト: 論理削除済みの習慣は再度削除できないこと
- 認証テスト: 未ログイン時は習慣を削除できないこと

<br>

**テスト結果**:
```
4 runs, 27 assertions, 0 failures, 0 errors, 0 skips
```

<br>

### ルーティング

<br>

**config/routes.rb**:
```ruby
Rails.application.routes.draw do
  root "pages#index"
  
  resources :users, only: [:new, :create]
  
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
  
  # 習慣管理（index, new, create, destroy）
  resources :habits, only: [:index, :new, :create, :destroy]
end
```

<br>

**ルーティング一覧**:
```
      Prefix Verb   URI Pattern              Controller#Action
        root GET    /                        pages#index
       users POST   /users(.:format)         users#create
    new_user GET    /users/new(.:format)     users#new
       login GET    /login(.:format)         sessions#new
             POST   /login(.:format)         sessions#create
      logout DELETE /logout(.:format)        sessions#destroy
      habits GET    /habits(.:format)        habits#index
             POST   /habits(.:format)        habits#create
   new_habit GET    /habits/new(.:format)    habits#new
       habit DELETE /habits/:id(.:format)    habits#destroy
```

<br>

### 動作確認（Railsコンソール）
```ruby
# ユーザーと習慣を取得
user = User.first
habit = user.habits.active.first

# 論理削除前の状態確認
habit.active?     # => true
habit.deleted?    # => false
habit.deleted_at  # => nil

# 論理削除を実行
habit.soft_delete

# 論理削除後の状態確認
habit.reload
habit.active?     # => false
habit.deleted?    # => true
habit.deleted_at  # => Sun, 15 Feb 2026 10:16:57.790426000 UTC +00:00

# データベースにレコードが残っていることを確認（物理削除されていない）
Habit.exists?(habit.id)  # => true

# active スコープで取得できないことを確認
user.habits.active.count   # => 削除された分、カウントが減る

# deleted スコープで取得できることを確認
user.habits.deleted.count  # => 削除された分、カウントが増える

# 実際の削除確認例
user = User.first
habit = user.habits.create(name: "テスト習慣", weekly_target: 7)

# 削除前
user.habits.active.count  # => 2

# 論理削除
habit.soft_delete

# 削除後
user.habits.active.count   # => 1（一覧に表示されない）
user.habits.count          # => 2（データベースには残っている）
user.habits.deleted.count  # => 1（削除済みスコープでは取得できる）
```

<br>

### UI/UX設計のポイント

<br>

**1. 削除ボタンの配置**:
- 習慣カードのヘッダー右上に配置
- 習慣名と削除ボタンを `flex justify-between` で左右に配置
- 削除ボタンは固定幅、習慣名は可変幅（`flex-1`）

<br>

**2. 視覚的な警告**:
- 赤色のボタン（`bg-red-600`）で「削除」という危険な操作を強調
- ホバー時に濃くなる（`hover:bg-red-700`）
- 小さめのボタン（`px-3 py-1 text-sm`）で誤クリックを防ぐ

<br>

**3. 削除確認ダイアログ**:
- Turbo Confirm で削除前に確認を求める
- 習慣名を表示して、削除対象を明確にする
- 「過去の記録も表示されなくなります」と警告
- `\n` で改行して、読みやすくする

<br>

**4. フラッシュメッセージ**:
- 削除成功時: 緑色のメッセージ（`flash[:notice]`）
- 削除失敗時: 赤色のメッセージ（`flash[:alert]`）
- 習慣が見つからない場合: 赤色のメッセージ

<br>

### 技術的な学び

<br>

**1. button_to の使用理由**:
- `link_to` ではなく `button_to` を使用
- DELETEリクエストはフォーム送信で行う必要がある
- セキュリティ上、リンク（GET）で削除操作を行うべきではない

<br>

**2. Turbo Confirm の活用**:
- `data: { turbo_confirm: "..." }` で確認ダイアログを表示
- JavaScriptを書かずに実装できる
- Turbo（Hotwire）の標準機能

<br>

**3. 論理削除 vs 物理削除**:
- 論理削除: `deleted_at` に日時を設定、データは残る
- 物理削除: レコード自体を削除、データは失われる
- 論理削除を採用した理由:
  - 過去の振り返りデータとの整合性を保つ
  - weekly_reflection_habit_summaries でスナップショットとして参照
  - データの復元が可能（将来的に実装予定）

<br>

**4. セキュリティ対策の徹底**:
- `current_user.habits.active` で現在のユーザーの有効な習慣のみを検索
- 他のユーザーの習慣は取得できない
- 論理削除済みの習慣は取得できない
- `rescue ActiveRecord::RecordNotFound` でエラーハンドリング

<br>

**5. Rails 7 / Turbo 対応**:
- `status: :see_other` で HTTP 303 リダイレクト
- ブラウザの「戻る」ボタン対策
- Turbo の非同期通信との互換性

<br>

#### HabitRecordモデル（Issue #14）

<br>

**実装日**: 2026年2月16日

<br>

**モデル設計**:
- 日次の習慣記録を管理する基盤モデル
- AM 4:00 を1日の境界とする特殊な日付計算ロジック
- チェック型習慣のみ対応（MVP範囲）
- DB + アプリの二重データ整合性保証（CASCADE）

<br>

**テーブル定義**:
```sql
CREATE TABLE habit_records (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id BIGINT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  record_date DATE NOT NULL,
  completed BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE INDEX index_habit_records_on_habit_id ON habit_records(habit_id);
CREATE UNIQUE INDEX index_habit_records_on_user_habit_date 
  ON habit_records(user_id, habit_id, record_date);
```

<br>

**バリデーション**:
- record_date: 必須
- record_date: ユニーク制約（scope: [:user_id, :habit_id]）
- completed: true/false のみ許可（nilは不可）

<br>

**外部キー制約（CASCADE）**:
```ruby
# マイグレーション
t.references :user, null: false, foreign_key: { on_delete: :cascade }
t.references :habit, null: false, foreign_key: { on_delete: :cascade }
```
- ユーザー削除時: 習慣記録も自動削除（DBレベル + アプリレベル）
- 習慣削除時: 習慣記録も自動削除（DBレベル + アプリレベル）
- データ整合性を二重保証

<br>

**UNIQUE制約**:
```ruby
add_index :habit_records, 
          [:user_id, :habit_id, :record_date], 
          unique: true, 
          name: 'index_habit_records_on_user_habit_date'
```
- 同じユーザーが同じ習慣を同じ日に複数回記録できないようにする
- DBレベル + アプリレベルの二重制約

<br>

**クラスメソッド**:
```ruby
# AM 4:00 基準の「今日」を取得
def self.today_for_record
  now = Time.current
  boundary = now.change(hour: 4, min: 0, sec: 0)
  now < boundary ? now.to_date - 1.day : now.to_date
end

# 記録の検索または作成
def self.find_or_create_for(user, habit, date = today_for_record)
  find_or_create_by!(user: user, habit: habit, record_date: date)
end
```

<br>

**インスタンスメソッド**:
```ruby
# 完了状態を切り替え（Rails標準の toggle! を使用）
def toggle_completed!
  toggle!(:completed)
end
```

<br>

**スコープ**:
```ruby
scope :for_date, ->(date) { where(record_date: date) }
scope :for_user, ->(user) { where(user: user) }
```

<br>

**アソシエーション**:
```ruby
# HabitRecordモデル
belongs_to :user
belongs_to :habit

# Userモデル
has_many :habit_records, dependent: :destroy

# Habitモデル
has_many :habit_records, dependent: :destroy
```

<br>

**AM 4:00 基準の設計思想**:
- 深夜の活動を前日の記録として扱う
- 例: 2024/1/1 AM 3:59 → 2023/12/31 として記録
- 例: 2024/1/1 AM 4:00 → 2024/1/1 として記録
- 習慣アプリの特性を考慮した設計

<br>

**データ整合性の設計**:
- UNIQUE制約（user_id, habit_id, record_date）
  - 同じユーザーが同じ習慣を同じ日に複数回記録できない
  - DBレベル（マイグレーション）+ アプリレベル（バリデーション）の二重制約
- 外部キー制約（CASCADE）
  - ユーザー削除時: 習慣記録も自動削除
  - 習慣削除時: 習慣記録も自動削除
  - DBレベル（on_delete: :cascade）+ アプリレベル（dependent: :destroy）の二重保証

<br>

**テスト戦略**:
- バリデーションテスト（3テストケース）
  - record_date の存在チェック
  - record_date のユニーク制約
  - completed の包含チェック
- アソシエーションテスト（4テストケース）
  - User との関連付け
  - Habit との関連付け
  - ユーザー削除時の CASCADE 動作
  - 習慣削除時の CASCADE 動作
- UNIQUE制約テスト（2テストケース）
  - 同じユーザー・習慣・日付の記録は重複不可
  - 異なる日付なら同じユーザー・習慣でも作成可能
- AM 4:00 基準の日付計算テスト（3テストケース）
  - AM 4:00 より前は前日として扱われる
  - AM 4:00 以降は当日として扱われる
  - PM 11:59 は当日として扱われる
- スコープテスト（2テストケース）
  - for_date スコープ
  - for_user スコープ
- メソッドテスト（4テストケース）
  - find_or_create_for メソッド（新規作成・既存取得）
  - toggle_completed! メソッド（false→true、true→false）

<br>

**テスト結果**:
```
18 runs, 42 assertions, 0 failures, 0 errors, 0 skips
```

<br>

**世界一エンジニアレビュー対応**:

<br>

**必須修正（実装済み）**:
- ✅ 外部キー削除挙動を `on_delete: :cascade` に明確化（DBレベルのデータ整合性保証）
- ✅ インデックスの冗長性を解消（user_id 単体インデックスを削除）
- ✅ `Date.today` → `Date.current` に統一（タイムゾーン対応）
- ✅ `test_helper.rb` に `TimeHelpers` を追加（travel_to 使用のため）

<br>

**推奨改善（実装済み）**:
- ✅ `today_for_record` ロジックを `change(hour: 4)` で改善（柔軟性向上）
- ✅ スコープを追加（`for_date`, `for_user`）
- ✅ `toggle_completed!` を Rails標準の `toggle!` に簡潔化

<br>

**動作確認（Railsコンソール）**:
```ruby
# ユーザーと習慣を取得
user = User.first
habit = user.habits.first

# AM 4:00 基準の「今日」を確認
HabitRecord.today_for_record
# => 2024-01-01 AM 3:59 に実行 → Date.new(2023, 12, 31)
# => 2024-01-01 AM 4:00 に実行 → Date.new(2024, 1, 1)

# 習慣記録を作成
record = HabitRecord.find_or_create_for(user, habit)
record.persisted?  # => true

# スコープの動作確認
HabitRecord.for_date(Date.current)  # => 今日の記録を全て取得
HabitRecord.for_user(user)          # => 特定ユーザーの記録を全て取得

# 完了状態を切り替え（Rails標準の toggle! を使用）
record.toggle_completed!
record.completed  # => true

# もう一度切り替え
record.toggle_completed!
record.completed  # => false

# 重複レコードを作成しようとする（エラーになることを確認）
duplicate = HabitRecord.create(
  user: user, 
  habit: habit, 
  record_date: HabitRecord.today_for_record, 
  completed: true
)
duplicate.errors.full_messages
# => ["Record date has already been taken"]

# CASCADE の動作確認
user.destroy
# => user に紐づく habit_records も自動削除される（DBレベル + アプリレベル）
```

<br>

**セキュリティ対策**:
- 外部キー制約（user_id, habit_id）でデータ整合性を保証
- UNIQUE制約で重複レコードを防止
- CASCADE により親レコード削除時に孤立レコードが残らないことを保証

<br>

**MVP後の拡張予定**:
- 数値型習慣への対応（value カラム追加）
- completed を「value が目標値を超えたかどうか」のキャッシュとして機能させる
- または completed を廃止して value.present? で判定する形に変更

<br>

#### 習慣の日次記録機能（Issue #15）

<br>

**実装日**: 2026年2月19日

<br>

**実装機能**:

<br>

**ルーティング（ネスト構造）**:
```ruby
# config/routes.rb
resources :habits, only: [:index, :new, :create, :destroy] do
resources :habit_records, only: [:create, :update]
end
```

<br>

**生成されるルーティング**:
```
habit_habit_records POST  /habits/:habit_id/habit_records(.:format)      habit_records#create
habit_habit_record PATCH /habits/:habit_id/habit_records/:id(.:format)  habit_records#update
```

<br>

**HabitRecordsController**:
```ruby
# app/controllers/habit_records_controller.rb

class HabitRecordsController < ApplicationController
  before_action :require_login
  before_action :set_habit

  # POST /habits/:habit_id/habit_records
  def create
    @habit_record = HabitRecord.find_or_create_for(current_user, @habit)
    @habit_record.update_completed!(params[:completed] == "1")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end
      format.html { redirect_to habits_path, notice: "記録を保存しました" }
    end
  end

  # PATCH /habits/:habit_id/habit_records/:id
  def update
    @habit_record = current_user.habit_records.find(params[:id])
    @habit_record.update_completed!(params[:completed] == "1")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "habit_record_#{@habit.id}",
          partial: "habit_records/habit_record",
          locals:  { habit: @habit, habit_record: @habit_record }
        )
      end
      format.html { redirect_to habits_path, notice: "記録を更新しました" }
    end
  end

  private

  def set_habit
    @habit = current_user.habits.active.find(params[:habit_id])
  rescue ActiveRecord::RecordNotFound
    head :not_found and return
  end
end
```

<br>

**実装の特徴**:
- `HabitRecord.find_or_create_for`: 今日のレコードを取得または新規作成（モデルに責務を集約）
- `@habit_record.update_completed!`: 完了状態の更新ロジックをモデルに隠蔽（疎結合設計）
- `current_user.habit_records.find`: セキュリティ対策（他ユーザーのレコード操作を遮断）
- `set_habit` で `head :not_found and return`: 外部パーシャルに依存しないシンプルな404応答

<br>

**HabitRecordモデルへの追加メソッド**:
```ruby
# app/models/habit_record.rb

# 完了状態を更新するメソッド
# Controller が completed カラムを直接知らなくて済む設計（疎結合）
def update_completed!(value)
  update!(completed: value)
end

# 今日のレコードを取得または作成するクラスメソッド
# Controller が record_date や user_id の設定方法を知らなくて済む設計
def self.find_or_create_for(user, habit, date = today_for_record)
  find_or_create_by!(user: user, habit: habit, record_date: date)
end
```

<br>

**Stimulus コントローラー（habit_record_controller.js）**:
```javascript
// app/javascript/controllers/habit_record_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "loading"]
  static values  = { createUrl: String, updateUrl: String, recordId: Number }

  async toggle() {
    const checkbox  = this.checkboxTarget
    const completed = checkbox.checked

    this._setLoadingState(true)

    try {
      const url    = this.recordIdValue === 0 ? this.createUrlValue : this.updateUrlValue
      const method = this.recordIdValue === 0 ? "POST" : "PATCH"

      const response = await Promise.race([
        fetch(url, {
          method,
          headers: {
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
            "Accept":       "text/vnd.turbo-stream.html",
            "Content-Type": "application/x-www-form-urlencoded"
          },
          body: `completed=${completed ? "1" : "0"}`
        }),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("timeout")), 10000)
        )
      ])

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const responseText = await response.text()
      window.Turbo.renderStreamMessage(responseText)
    } catch (error) {
      // エラー時はチェックボックスを元の状態に戻す（楽観的UIのロールバック）
      checkbox.checked = !completed
      console.error("保存エラー:", error)
    } finally {
      this._setLoadingState(false)
    }
  }

  _setLoadingState(isLoading) {
    this.checkboxTarget.disabled = isLoading
    if (isLoading) {
      this.loadingTarget.removeAttribute("hidden")
    } else {
      this.loadingTarget.setAttribute("hidden", "")
    }
  }
}
```

<br>

**パーシャル（_habit_record.html.erb）**:
```erb
<%# app/views/habit_records/_habit_record.html.erb %>
<%# Turbo Stream の置換ターゲット: id="habit_record_" %>

<%
  record     = habit_record || HabitRecord.new(completed: false)
  create_url = habit_habit_records_path(habit)
  update_url = record.persisted? ? habit_habit_record_path(habit, record) : ""
  record_id  = record.persisted? ? record.id : 0
%>

  <%# チェックボックス + ローディングアイコン + 習慣名 + 完了バッジ %>
```

<br>

**N+1問題の解消（習慣一覧ページ）**:
```ruby
# app/controllers/habits_controller.rb（indexアクション）

def index
  @habits = current_user.habits.active.order(created_at: :desc)

  # today_records_hash: 今日分の HabitRecord を1回のクエリで一括取得
  # { habit_id => habit_record } のハッシュ形式で返す
  today = HabitRecord.today_for_record
  @today_records_hash = HabitRecord
    .where(user: current_user, habit: @habits, record_date: today)
    .index_by(&:habit_id)
end
```

```erb
<%# app/views/habits/index.html.erb %>
<%# N+1を防ぐために @today_records_hash からO(1)で取得 %>
<%= render "habit_records/habit_record",
    habit:        habit,
    habit_record: @today_records_hash[habit.id] %>
```

<br>

**セキュリティ設計**:
- `set_habit`: `current_user.habits.active.find` で他ユーザーの習慣へのアクセスを遮断
- `update` アクション: `current_user.habit_records.find` で他ユーザーのレコード操作を遮断
- いずれも `RecordNotFound` で 404 を返し、存在の有無を漏洩しない

<br>

**テスト**:
- HabitRecordsControllerTest（AM 4:00 境界値テスト・セキュリティテスト含む）
- HabitRecordInstantSaveTest（Turbo Stream レスポンス・他ユーザー遮断テスト）
- 全テスト結果: 88 runs, 262 assertions, 0 failures, 0 errors, 0 skips

<br>

#### 習慣の週次進捗統計自動計算（Issue #16）

<br>

**実装日**: 2026年2月19日

<br>

**設計方針**:
- 進捗率（%）と完了日数の両方をビューで使用するため、1回のDBアクセスで両方返す `weekly_progress_stats` メソッドを設計
- 計算ロジックはモデルに集約（Fat Model）し、コントローラー・ビューから切り離す
- コントローラーで全習慣分を事前計算してハッシュ化することでN+1問題を完全解消

<br>

**Habitモデルへの追加メソッド**:
```ruby
# app/models/habit.rb

# 今週の進捗率と完了日数を1回のDBアクセスで返す
# 戻り値: { rate: Integer(0〜100), completed_count: Integer }
def weekly_progress_stats(user)
  range = current_week_range  # AM4:00基準の今週月曜〜今日

  completed_count = habit_records
                      .where(user: user)
                      .where(record_date: range)
                      .where(completed: true)
                      .count

  return { rate: 0, completed_count: completed_count } if weekly_target.zero?

  rate = ((completed_count.to_f / weekly_target) * 100).clamp(0, 100).floor
  { rate: rate, completed_count: completed_count }
end

private

# AM4:00基準で「今週の月曜日〜今日」の Date の Range を返す
def current_week_range
  today = HabitRecord.today_for_record
  today.beginning_of_week(:monday)..today
end
```

<br>

**コントローラーでの一括計算（N+1問題対策）**:
```ruby
# app/controllers/habits_controller.rb（indexアクション）

# ビューのループ内でDBクエリが発生するN+1問題を防ぐため
# 全習慣分の進捗統計をコントローラーで事前計算してハッシュに格納する
# 格納形式: { habit_id => { rate: 14, completed_count: 1 } }
@habit_stats = @habits.each_with_object({}) do |habit, hash|
  hash[habit.id] = habit.weekly_progress_stats(current_user)
end
```

<br>

**ビューでの参照（DBアクセスなし）**:
```erb
<%# @habit_stats から O(1) で取得（DBアクセスなし） %>
<% stats = @habit_stats[habit.id] || { rate: 0, completed_count: 0 } %>
<% progress = stats[:rate] %>
<% completed_count = stats[:completed_count] %>
<%# プログレスバー（進捗率に応じて色が変化） %>
<%= completed_count %> / <%= habit.weekly_target %> 日達成

```

<br>

**削除ボタンのレイアウト崩れ修正**:
- `button_to`（`<form>` タグを生成 → block要素によるflex崩れ）から `link_to + data-turbo-method: :delete` に変更
```erb
<%# 修正後: タグが生成されないため flexレイアウトを崩さない %>
<%= link_to "削除",
    habit_path(habit),
    data: { turbo_method: :delete, turbo_confirm: "「#{habit.name}」を削除しますか？" },
    class: "px-2 py-1 text-xs bg-red-100 text-red-600 rounded hover:bg-red-200 transition flex-shrink-0" %>
```

<br>

**テスト戦略**:
- 記録0件のとき `rate: 0, completed_count: 0` であること
- 未完了の記録（`completed: false`）は集計に含まれないこと
- 他ユーザーの記録は集計に含まれないこと
- AM4:00境界値（3:59 → 前日、4:00 → 当日）の動作確認

<br>

**テスト結果**:
```
89 runs, 236 assertions, 0 failures, 0 errors, 0 skips
```

<br>

**動作確認（Railsコンソール）**:
```ruby
user = User.find_by(email: "yamada@example.com")
habit = user.habits.active.first
habit.weekly_progress_stats(user)
# => { rate: 14, completed_count: 1 }
```

<br>

#### 習慣管理機能のテスト（Issue #17）

<br>

**実装日**: 2026年2月20日

<br>

**テストカバレッジ（新規追加分）**:
- 習慣作成テスト（正常系・バリデーション異常系・セキュリティ・未ログイン）
- 習慣削除テスト（正常系・セキュリティ・論理削除済み・未ログイン）
- 日次記録テスト（作成・重複防止・セキュリティ・AM4:00境界値）
- 進捗率計算テスト（0件・未完了除外・他ユーザー除外・100%上限・先週除外）

<br>

**fixturesキー名の統一**:
- `habits(:one)` / `habits(:two)` → `habits(:habit_one)` / `habits(:habit_two)` / `habits(:habit_deleted)` に変更
- キー名に種別を含めることで、テストコードを読んだときに「何のデータか」が一目でわかる
- 既存テスト4ファイルの参照箇所を `sed` コマンドで一括置換

<br>

**技術的なポイント**:
- `setup` ブロックで `@habit.habit_records.destroy_all` を実行し、フィクスチャデータとテストデータの干渉を防止
- `travel_to` でシステム時刻を固定し、AM4:00境界値（3:59 → 前日、4:00 → 当日）を正確に検証

<br>

**テスト結果**:
```
119 runs, 322 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### ダッシュボード機能（Issue #18）

<br>

**実装日**: 2026年2月21日

<br>

**コントローラー設計**:
```ruby
# app/controllers/dashboards_controller.rb

class DashboardsController < ApplicationController
  before_action :require_login

  def index
    @today      = HabitRecord.today_for_record          # AM4:00基準の「今日」
    @week_start = @today.beginning_of_week(:monday)     # 今週月曜日

    @habits = current_user.habits.active.order(created_at: :desc)

    # N+1対策①: 今日の記録を1クエリで一括取得 → { habit_id => HabitRecord }
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: @today)
      .index_by(&:habit_id)

    # N+1対策②: 全習慣の週次統計を事前計算 → { habit_id => { rate:, completed_count: } }
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    # 全体達成率（全習慣の平均）
    @overall_rate = @habits.empty? ? 0 :
      (@habit_stats.values.map { |s| s[:rate] }.sum.to_f / @habit_stats.size).round
  end
end
```

<br>

**リダイレクト設計の変更**:

<br>

| コントローラー | 変更前 | 変更後 | 理由 |
|--------------|--------|--------|------|
| `SessionsController#create` | `root_path` | `dashboard_path` | リダイレクト1回に削減、UX向上 |
| `UsersController#create` | `root_path` | `dashboard_path` | 同上 |
| `PagesController#index` | なし | `logged_in?` → `dashboard_path` | 直接アクセス時の振り分け |

<br>

**テストの共通化**:
```ruby
# test/test_helper.rb に追加

module TestLoginHelper
  # ログイン処理を1箇所に集約
  # 将来ログイン実装が変わっても、ここだけ修正すれば全テストに反映される
  def log_in_as(user)
    post login_path, params: {
      session: { email: user.email, password: "password" }
    }
  end
end

class ActionDispatch::IntegrationTest
  include TestLoginHelper
end
```

<br>

**今回の修正で直った既存テストの失敗原因**:

<br>

| 失敗していたテスト | 原因 | 修正内容 |
|-----------------|------|---------|
| `user_registration_test.rb` | `div.ユーザー登録が完了しました` がダッシュボードにない | `assert_select "h1", text: /ダッシュボード/` に変更 |
| `user_login_test.rb` | `assert_redirected_to root_path` だが実際は `dashboard_path` | `assert_redirected_to dashboard_path` に変更 |
| `habit_record_instant_save_test.rb` | `assert_response :success` だが `head :not_found` で404を返していた | `assert_response :not_found` に変更 |
| `habit_creation_test.rb` | `assert_redirected_to root_path` だが実際は `dashboard_path` | `assert_redirected_to dashboard_path` に変更 |

<br>

**テスト結果**:
```
121 runs, 324 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### WeeklyReflectionモデル（Issue #19）

<br>

**実装日**: 2026年2月21日

<br>

**モデル設計**:
- 週次振り返りデータを管理する基盤モデル
- 1ユーザーにつき1週間あたり1レコードのみ作成可能
- AM4:00基準でHabitRecordと一貫した週の判定ロジック
- 振り返り完了フラグ（`is_locked`）によるPDCA強制ロック機能の基盤

<br>

**テーブル定義**:
```sql
CREATE TABLE weekly_reflections (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start_date DATE NOT NULL,
  week_end_date DATE NOT NULL,
  reflection_comment TEXT,
  is_locked BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX index_weekly_reflections_on_user_id_and_week_start_date
  ON weekly_reflections(user_id, week_start_date);
```

<br>

**バリデーション**:
- week_start_date: 必須
- week_end_date: 必須、`week_start_date + 6日` であること（カスタムバリデーション）
- reflection_comment: 1000文字以内（任意入力）
- is_locked: true/false のみ許可（`inclusion` で検証）
- week_start_date: ユニーク制約（scope: :user_id）

<br>

**カスタムバリデーション（週範囲の整合性）**:
```ruby
validate :week_range_must_be_one_week

private

def week_range_must_be_one_week
  return if week_start_date.blank? || week_end_date.blank?
  unless week_end_date == week_start_date + 6.days
    errors.add(:week_end_date, 'は開始日の6日後でなければなりません')
  end
end
```

<br>

**クラスメソッド**:
```ruby
# AM4:00基準で「今週の月曜日」を取得
def self.current_week_start_date
  today = HabitRecord.today_for_record
  today.beginning_of_week(:monday)
end

# 今週分を取得、なければ新規インスタンスを返す（未保存）
def self.find_or_build_for_current_week(user)
  start_date = current_week_start_date
  user.weekly_reflections.find_or_initialize_by(week_start_date: start_date) do |r|
    r.week_end_date = start_date + 6.days
  end
end
```

<br>

**インスタンスメソッド**:
```ruby
def complete!     = update!(is_locked: true)   # 振り返りを完了状態にする
def completed?    = is_locked                  # 完了済みかどうか
def pending?      = !is_locked                 # 未完了かどうか
def week_label    # 表示用ラベル例: "2026/02/16 - 02/22"
  "#{week_start_date.strftime('%Y/%m/%d')} - #{week_end_date.strftime('%m/%d')}"
end
```

<br>

**スコープ**:
```ruby
scope :completed, -> { where(is_locked: true) }
scope :pending,   -> { where(is_locked: false) }
scope :recent,    -> { order(week_start_date: :desc) }
scope :for_week,  ->(start_date) { where(week_start_date: start_date) }
```

<br>

**テスト戦略**:
- バリデーション正常系・異常系（1000文字制限・nil・週範囲不正）
- UNIQUE制約（同一ユーザー同一週の重複作成を拒否、別ユーザーは許可）
- アソシエーション（CASCADE: ユーザー削除時に振り返りも自動削除）
- AM4:00境界値（`travel_to` で月曜AM3:59 → 先週、AM4:00 → 今週を検証）
- `find_or_build_for_current_week`（既存レコード取得・新規インスタンス生成）
- インスタンスメソッド（`complete!`, `completed?`, `week_label`）

<br>

**テスト結果**:
```
22 runs, 38 assertions, 0 failures, 0 errors, 0 skips
（全体: 143 runs, 362 assertions, 0 failures, 0 errors, 0 skips）
```

<br>

#### WeeklyReflectionHabitSummaryモデル（Issue #20）

<br>

**実装日**: 2026年2月21日

<br>

**設計思想（スナップショット）**:

<br>

このテーブルは「履歴」ではなく「スナップショット」です。

<br>

習慣（habits）テーブルのデータはユーザーによって後から変更・削除される可能性があります。<br>
しかし週次振り返りは「振り返りを行った時点の状態」を永続保存する必要があります。<br>

<br>

例：<br>
1週目：習慣名「読書」目標7回 → サマリーに「読書, 7回」をコピー保存<br>
2週目：習慣名を「英語学習」に変更<br>
→ 1週目の振り返りを見ても「読書」のまま表示される（正しい記録を守れる）<br>

<br>

**テーブル定義**:
```sql
CREATE TABLE weekly_reflection_habit_summaries (
  id BIGSERIAL PRIMARY KEY,
  weekly_reflection_id BIGINT NOT NULL REFERENCES weekly_reflections(id) ON DELETE CASCADE,
  habit_id BIGINT REFERENCES habits(id) ON DELETE SET NULL,
  habit_name VARCHAR NOT NULL,
  weekly_target INTEGER NOT NULL,
  actual_count INTEGER NOT NULL DEFAULT 0,
  achievement_rate DECIMAL(5,2) NOT NULL DEFAULT 0.0,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX idx_wr_habit_summaries_on_wr_id_and_habit_id
  ON weekly_reflection_habit_summaries(weekly_reflection_id, habit_id);
```

<br>

**外部キー制約の設計**:

<br>

| カラム | NULL | on_delete | 理由 |
|--------|------|-----------|------|
| weekly_reflection_id | NOT NULL | CASCADE | 振り返り本体が消えたらサマリーも不要 |
| habit_id | NULL許容 | NULLIFY | 習慣が削除されてもスナップショットデータは残す |

<br>

`habit_id` を `null: true` にする理由：<br>
`on_delete: :nullify` により habit 削除時に DB が habit_id を NULL に書き換えようとする。<br>
`null: false`（NOT NULL制約）のままだと `PG::NotNullViolation` エラーになるため、NULL を許容する設計が正しい。<br>

<br>

**バリデーション**:
- habit_name: 必須・50文字以内（スナップショット）
- weekly_target: 必須・1以上の整数（達成率計算の分母になるため0禁止）
- actual_count: 必須・0以上の整数
- achievement_rate: 必須・0〜100の範囲
- habit_id: ユニーク制約（scope: :weekly_reflection_id）、NULL許容

<br>

**クラスメソッド**:
```ruby
# 単体スナップショット構築（DBには保存しない）
def self.build_from_habit(weekly_reflection, habit)
  week_range = weekly_reflection.week_start_date..weekly_reflection.week_end_date
  actual_count = habit.habit_records
                      .where(user: weekly_reflection.user,
                             record_date: week_range,
                             completed: true)
                      .count
  rate = calculate_rate(actual_count, habit.weekly_target)
  weekly_reflection.habit_summaries.build(
    habit:            habit,
    habit_name:       habit.name,           # スナップショット
    weekly_target:    habit.weekly_target,  # スナップショット
    actual_count:     actual_count,
    achievement_rate: rate
  )
end

# 全習慣のサマリーを一括作成（トランザクション保証・冪等性対応）
def self.create_all_for_reflection!(weekly_reflection)
  transaction do
    weekly_reflection.user.habits.active.each do |habit|
      next if weekly_reflection.habit_summaries.exists?(habit: habit) # 冪等性
      build_from_habit(weekly_reflection, habit).save!
    end
  end
end
```

<br>

**達成率の計算ロジック**:
```ruby
# actual / target * 100、0〜100にclamp、小数点2桁で丸め
((actual.to_f / target) * 100).clamp(0, 100).round(2)
```

<br>

**冪等性（idempotent）の保証**:

<br>

`create_all_for_reflection!` は同じ振り返りに対して何度呼んでもデータが重複しない設計です。<br>
`next if exists?(habit: habit)` により既存サマリーをスキップするため、<br>
ページリロードや二重送信が発生しても安全に動作します。<br>

<br>

**アソシエーション**:
```ruby
# WeeklyReflectionHabitSummary
belongs_to :weekly_reflection
belongs_to :habit, optional: true  # habit_id が NULL になっても許容

# WeeklyReflection
has_many :habit_summaries,
         class_name: 'WeeklyReflectionHabitSummary',
         dependent: :destroy

# Habit
has_many :weekly_reflection_habit_summaries, dependent: :nullify
```

<br>

**テスト戦略**:
- バリデーションテスト（正常系・異常系・境界値）
- UNIQUE制約テスト（同一振り返り×習慣の重複禁止、異なる組み合わせは許可）
- スナップショットテスト（`build_from_habit` で habit_name・weekly_target が正しくコピーされること）
- 実績集計テスト（未完了記録・他ユーザー記録が含まれないこと）
- 冪等性テスト（`create_all_for_reflection!` を2回呼んでも件数が増えないこと）
- CASCADEテスト（WeeklyReflection削除時にサマリーも削除されること）

<br>

**テスト結果**:
```
172 runs, 409 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### 週次振り返り一覧ページ（Issue #21）

<br>

**実装日**: 2026年2月21日

<br>

**ルーティング**:
```ruby
# config/routes.rb
resources :weekly_reflections, only: [:index, :new, :create, :show]
```

<br>

**WeeklyReflectionsController（index アクション）**:
```ruby
# app/controllers/weekly_reflections_controller.rb

class WeeklyReflectionsController < ApplicationController
  before_action :require_login

  def index
    # 今週の振り返りを取得（なければ未保存インスタンスを返す）
    @current_week_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)

    # 振り返り作成ボタンの表示可否を判定
    @can_create_reflection = can_create_reflection?

    # 過去の完了済み振り返りを取得（habit_summariesのN+1を事前対策）
    @past_reflections = current_user.weekly_reflections
                                    .completed
                                    .recent
                                    .includes(:habit_summaries)

    # 今週の習慣達成率を一括計算（N+1問題対策）
    @habits = current_user.habits.active.order(created_at: :desc)
    @habit_stats = @habits.each_with_object({}) do |habit, hash|
      hash[habit.id] = habit.weekly_progress_stats(current_user)
    end

    rates = @habit_stats.values.map { |s| s[:rate] }
    @overall_rate = rates.any? ? (rates.sum.to_f / rates.size).round : 0
  end

  private

  def can_create_reflection?
    now = Time.current
    is_sunday       = now.wday == 0
    is_after_4am    = now >= now.beginning_of_day + 4.hours
    is_not_completed = @current_week_reflection.new_record? ||
                       @current_week_reflection.pending?
    is_sunday && is_after_4am && is_not_completed
  end
end
```

<br>

**振り返り作成ボタンの表示ロジック**:

<br>

| 状態 | 表示内容 |
|------|---------|
| 日曜 AM4:00 以降 かつ 未完了 | 「今週を振り返る」ボタン（青色） |
| 今週の振り返りが完了済み | 完了メッセージ + 詳細リンク |
| 平日・土曜、または日曜 AM4:00 未満 | 次回振り返り日を案内 |

<br>

**設計上のポイント**:

<br>

`can_create_reflection?` を `private` メソッドに切り出した理由:<br>
判定ロジック（日曜かつ4時以降かつ未完了）をビューに直接書くと変更に弱くなるためです。<br>
コントローラーの1箇所に集約することで、仕様変更時の修正コストを最小化します。<br>

<br>

`Time.current` を使う理由:<br>
`Time.now` はサーバーのローカル時刻を返しますが、`Time.current` は Rails の `config.time_zone` に従ったタイムゾーン補正済みの時刻を返します。<br>
本番環境でサーバーのタイムゾーンがズレていても正確に動作させるためです。<br>

<br>

**テスト設計（固定日付を使わない理由）**:

<br>

テスト内でデータを作成する際、`Date.new(2025, 12, 1)` のような固定日付は:<br>
- fixtures のデータと衝突する可能性がある<br>
- 将来 fixtures が増えたとき再び壊れる<br>
- なぜその日付なのかコードを読んでも分からない<br>

<br>

そのため `travel_to + WeeklyReflection.current_week_start_date` を使い、<br>
アプリのロジックそのものに追従する日付非依存なテスト設計を採用しています。<br>

```ruby
# テスト例
travel_to Time.zone.local(2025, 12, 3, 10, 0, 0) do
  week_start = WeeklyReflection.current_week_start_date  # 2025/12/01（月曜）
  WeeklyReflection.create!(
    user: @user,
    week_start_date: week_start,
    week_end_date:   week_start + 6.days,
    reflection_comment: "テスト振り返りコメント",
    is_locked: true
  )
  get weekly_reflections_path
  assert_select "body", text: /テスト振り返りコメント/
end
```

<br>

**テスト結果**:
```
187 runs, 435 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### 週次振り返り入力ページ（Issue #22）

<br>

**実装日**: 2026年2月21日

<br>

**コントローラー設計**:

<br>

`new` アクション：`find_or_build_for_current_week` で今週分のインスタンスを取得し、完了済みなら詳細ページへ早期リダイレクト。`prepare_habit_stats` を private メソッドに切り出して `new` と `create` 失敗時で再利用（DRY原則）。

<br>

`create` アクション：`find_or_build_for_current_week` による冪等性保証、トランザクション内で振り返り本体と習慣スナップショットを一括保存。

```ruby
# app/controllers/weekly_reflections_controller.rb（createアクション抜粋）

def create
  @weekly_reflection = WeeklyReflection.find_or_build_for_current_week(current_user)
  @weekly_reflection.assign_attributes(weekly_reflection_params)

  ActiveRecord::Base.transaction do
    @weekly_reflection.is_locked = true
    @weekly_reflection.save!
    WeeklyReflectionHabitSummary.create_all_for_reflection!(@weekly_reflection)
  end

  redirect_to weekly_reflections_path, notice: "今週の振り返りを完了しました！"

rescue ActiveRecord::RecordInvalid => e
  flash.now[:alert] = "保存に失敗しました: #{e.record.errors.full_messages.join(', ')}"
  prepare_habit_stats
  render :new, status: :unprocessable_entity

rescue ActiveRecord::RecordNotUnique
  flash.now[:alert] = "今週の振り返りはすでに存在します"
  prepare_habit_stats
  render :new, status: :unprocessable_entity
end
```

<br>

**フォーム設計（form_with）**:

<br>

`url:` と `method:` を省略し `model: @weekly_reflection` のみ指定。Rails が `new_record?` / `persisted?` を自動判定し、新規なら `POST /weekly_reflections`、既存なら `PATCH /weekly_reflections/:id` を自動設定するため、Rails らしいシンプルなコードになる。

<br>

**バリデーション追加**:
```ruby
# app/models/weekly_reflection.rb
validates :reflection_comment, length: { maximum: 1000 }, allow_blank: true
```

<br>

**エラーハンドリング設計（二重防衛）**:

<br>

| rescue 対象 | 想定シナリオ | 対応 |
|------------|------------|------|
| `RecordInvalid` | バリデーション失敗（1000文字超過等） | エラーメッセージを表示してフォーム再レンダリング |
| `RecordNotUnique` | DB の UNIQUE 制約違反（並列リクエスト等の極まれなケース） | 安全にフォーム再レンダリング |

<br>

`rescue StandardError` は使わない。想定外のエラー（DB接続エラー等）は Rails のデフォルトエラーハンドラーに委ねることで、開発中は即座に問題に気づける。

<br>

**fixtures 設計の教訓**:

<br>

今回のテスト修正で得られた重要な知見：

<br>

- Rails の fixtures は `before_validation` 等のモデルコールバックをバイパスして DB に直接 INSERT する。`week_end_date` のような NOT NULL カラムは fixtures に明示的に書く必要がある
- `uniqueness` バリデーションは DB を参照するため、fixtures に存在する組み合わせは `valid?` が `false` になる。`setup` で使う reflection は fixtures にサマリーが紐づいていない専用レコード（`for_summary_test`）を用意する
- fixtures のラベル名を変更したときは、外部キーで参照している全 fixtures ファイルを必ず確認する

<br>

**テスト結果**:
```
188 runs, 443 assertions, 0 failures, 0 errors, 0 skips
```

<br>

#### 週次振り返り詳細ページ（Issue #23）

<br>

**実装日**: 2026年2月21日

<br>

**コントローラー設計**:

<br>

`show` アクション：`set_weekly_reflection` を `before_action` に切り出し、`current_user.weekly_reflections.find` で他ユーザーの振り返りへのアクセスを遮断。`calculate_overall_achievement_rate` を private メソッドに分離して責務を明確化。

```ruby
# app/controllers/weekly_reflections_controller.rb（showアクション抜粋）

before_action :set_weekly_reflection, only: [:show]

def show
  @habit_summaries = @weekly_reflection.habit_summaries
                                       .includes(:habit)
                                       .order(achievement_rate: :desc)
  @overall_achievement_rate = calculate_overall_achievement_rate
end

private

def set_weekly_reflection
  @weekly_reflection = current_user.weekly_reflections.find(params[:id])
rescue ActiveRecord::RecordNotFound
  redirect_to weekly_reflections_path, alert: "振り返りが見つかりませんでした。"
end

def calculate_overall_achievement_rate
  return 0 if @habit_summaries.empty?
  (@habit_summaries.map(&:achievement_rate).sum / @habit_summaries.size.to_f).round(1)
end
```

<br>

**コードレビュー対応（5項目）**:

<br>

| 指摘 | 修正内容 | 理由 |
|------|---------|------|
| `.order` 文字列形式 | `order(achievement_rate: :desc)` に変更 | SQLインジェクション対策・Rails標準スタイル |
| N+1 予防 | `includes(:habit)` を追加 | 将来の `summary.habit.name` アクセスに備えた事前対策 |
| 不要な `partition` | ビューで使われていた `@achieved_summaries` を削除 | 未使用変数の除去 |
| メソッド分離 | `calculate_overall_achievement_rate` を private に | show アクションの責務を「変数準備のみ」に絞る |
| テスト強化 | `assert_select "h2"` で見出し3件を追加検証 | UI崩壊・見出し削除を検知できるよう強化 |

<br>

**フィクスチャ設計の教訓（UNIQUE制約回避）**:

<br>

モデルテストの `setup` が `for_summary_test × habit_one` を `.new` で使うため、<br>
フィクスチャ側は `for_summary_test × habit_two`（`one_habit_one` キー）を定義して衝突を回避。<br>
スコープテスト用の `two_habit_one` は `completed_one` に紐づけることで `for_summary_test` との競合を防ぐ設計。

<br>

**ルーティング整備**:

<br>

routes.rb の置き換えにより消えていたエイリアスと、テストが参照するネストルートを復元：
```ruby
# login_path / logout_path エイリアス（application_controller.rb・_header.html.erb・test_helper.rb が使用）
get    "/login",  to: "sessions#new",     as: :login
post   "/login",  to: "sessions#create"   # test_helper.rb の post login_path 用
delete "/logout", to: "sessions#destroy", as: :logout

# habit_habit_records_path を生成するネストルート
resources :habits, only: [:index, :new, :create, :destroy] do
  resources :habit_records, only: [:create, :update]
end
```

<br>

**テスト結果**:
```
189 runs, 443 assertions, 0 failures, 0 errors, 0 skips
```

<br>

## PDCA強制ロック機能（Issue #24）

<br>

### 機能概要

<br>

月曜日のAM4:00時点で前週の週次振り返りが未完了の場合、以下の操作をブロックします。

<br>

- **習慣の新規作成をブロック** — 振り返りを優先させるため
- **習慣の削除をブロック** — 逃げの削除を防止し、PDCAを回すため
- **ダッシュボード・習慣一覧に警告バナーを表示** — 振り返りページへの導線を提供

<br>

即時保存（チェックボックスによる日次記録）はロック中でも動作します。

<br>

### ロック判定ロジック（locked?）
```ruby
# app/controllers/application_controller.rb

def locked?
  return false unless logged_in?

  # 今週月曜日のAM4:00を計算
  # Date.current.beginning_of_week(:monday) でDateを基準にすることで
  # タイムゾーン混在を防ぎます
  this_monday_4am = Date.current
                        .beginning_of_week(:monday)
                        .in_time_zone
                        .change(hour: 4, min: 0, sec: 0)

  # AM4:00未満（日曜深夜〜月曜3:59）はロックしない
  return false if Time.current < this_monday_4am

  # 前週の振り返りが存在しかつ未完了（pending?）ならロック
  last_week_start = HabitRecord.today_for_record
                               .beginning_of_week(:monday) - 1.week
  last_week_reflection = current_user.weekly_reflections
                                     .find_by(week_start_date: last_week_start)
  return false if last_week_reflection.nil?
  last_week_reflection.pending?
end
```
<br>

### ロック時のサーバー側ブロック（require_unlocked）
```ruby
# app/controllers/application_controller.rb

# ロック中は create / destroy を実行させない「門番」メソッド
# before_action として HabitsController に設定します
def require_unlocked
  return unless locked?

  respond_to do |format|
    format.html do
      flash[:alert] = "先週の振り返りが未完了のため、この操作はできません。先に振り返りを完了してください。"
      redirect_back fallback_location: habits_path
    end
    format.turbo_stream { head :locked }  # HTTP 423 Locked
    format.json { render json: { error: "locked" }, status: :locked }
  end
end
```

<br>

### HabitsController への適用
```ruby
# app/controllers/habits_controller.rb

# create と destroy の実行前にロックチェックを走らせます
# index（一覧表示）や new（フォーム表示）はロック中でも閲覧可能にするため除外しています
before_action :require_unlocked, only: [:create, :destroy]
```

<br>

### ビューでのUI制御
```erb
<%# ロック中は非活性ボタン（クリックしても何も起きない）を表示 %>
<% if @locked %>
  
    🔒 + 新しい習慣を追加
  
<% else %>
  <%= link_to new_habit_path, class: "..." do %>
    + 新しい習慣を追加
  <% end %>
<% end %>
```

<br>

### 設計上のポイント

<br>

**月曜AM4:00という時間条件を厳密に実装している理由：**<br>
仕様は「月曜AM4:00を過ぎた時点でロック発動」です。<br>
この条件がない場合、月曜になった瞬間ではなく前週中からずっとロックされてしまいます。<br>
`Date.current.beginning_of_week(:monday).in_time_zone.change(hour: 4)` で<br>
タイムゾーンを考慮した正確な時刻計算をしています。<br>

<br>

**サーバー側でもブロックする理由：**<br>
ビュー側でボタンを非活性にするだけでは、URLを直接叩けばリクエストが通ってしまいます。<br>
`before_action :require_unlocked` をコントローラーに設定することで、<br>
どんな方法でリクエストを送っても必ずサーバー側でブロックされます。<br>

<br>

### テスト戦略
```ruby
# test/integration/pdca_lock_test.rb

# travel_to で月曜AM4:01に固定することで
# テストを実行する曜日・時間に関わらず同じ結果になる（テストの再現性を保証）
setup do
  travel_to next_monday.in_time_zone.change(hour: 4, min: 1) + 1.week
end

# AM4:00前はロックしないことの境界値テスト
test "月曜AM3:59は前週未完了でもロックされない" do
  travel_to this_monday.in_time_zone.change(hour: 3, min: 59)
  get dashboard_path
  assert_select "p", text: /先週の振り返りが未完了/, count: 0
end
```

<br>

**テスト結果**:
```
198 runs, 474 assertions, 0 failures, 0 errors, 0 skips
```

<br>

## 振り返り完了時のPDCAロック自動解除（Issue #25）

<br>

### 機能概要

<br>

振り返りを投稿して完了した瞬間に、PDCAロックを自動解除する機能です。

<br>

Issue #24 でロック発動の仕組みを作りましたが、解除する手段がありませんでした。<br>
Issue #25 でそのループを「振り返りを書いたら解除される」という形で閉じています。

<br>

### 設計の核心：「今週を保存」と「前週のロック解除」は別の操作

<br>

ロック判定は `locked? → 前週の pending? を確認` という連鎖で行われます。<br>
つまり **ロック解除 = 前週の振り返りを complete! すること** です。

<br>

今週の振り返りを保存するだけでは前週の `pending_reflection` は変わりません。<br>
そのため create アクション内で「前週も complete! する」処理が必要です。
```ruby
# app/controllers/weekly_reflections_controller.rb（createアクション抜粋）

# ロック状態を「保存前に」記録する
# complete! を呼んだ後は locked? が false になるため、保存前に変数へ入れておく
was_locked = current_user.locked?

ActiveRecord::Base.transaction do
  @weekly_reflection.save!
  WeeklyReflectionHabitSummary.create_all_for_reflection!(@weekly_reflection)

  # 今週の振り返りを完了にする（is_locked: true + completed_at を記録）
  @weekly_reflection.complete!

  # ロック中だった場合は「前週の振り返り」も complete! してロックを解除する
  if was_locked
    last_week_start = WeeklyReflection.current_week_start_date - 7.days
    last_week = current_user.weekly_reflections
                            .find_by(week_start_date: last_week_start)
    last_week&.complete!
  end
end

current_user.reload  # complete! 後のキャッシュをリセット

# ロック解除時は緑バナー + ダッシュボードへ、通常時は一覧ページへ
if was_locked
  redirect_to dashboard_path,
              flash: { unlock: "🔓 振り返りが完了しました！PDCAロックが解除されました。今週も頑張りましょう！" }
else
  redirect_to weekly_reflections_path,
              notice: "今週の振り返りを保存しました！お疲れ様でした🎉"
end
```

<br>

### complete! メソッドの設計（is_locked と completed_at の二重更新）
```ruby
# app/models/weekly_reflection.rb

def complete!
  return if completed?
  # is_locked: true → 既存コードの completed スコープ・二重送信防止チェックと整合
  # completed_at    → pending?/completed? の判定・locked? の連鎖と整合
  update!(completed_at: Time.current, is_locked: true)
end
```

<br>

`is_locked` と `completed_at` を両方更新する理由：<br>
- `is_locked` : 既存コード（`new`/`create` の二重送信防止・`.completed` スコープ）が依存
- `completed_at` : `pending?` → `locked?` の判定チェーンが依存<br>
両方を `complete!` の1か所で同時に更新することで整合性を保ちます。

<br>

### テスト結果

<br>
```
182 runs, 467 assertions, 0 failures, 0 errors, 0 skips
```

<br>

## レスポンシブデザインの調整（Issue #26）

<br>

### 対応方針

<br>

**PC版のデザインを1ミリも変えず、モバイルにだけ機能を追加するアプローチを採用。**<br>
Issue #24 時点の PC 版デザインをベースに、Tailwind CSS のモバイルファースト設計（`md:` プレフィックス）で安全に対応しました。

<br>

### ハンバーガーメニュー（ナビゲーションのモバイル対応）

<br>

**PC 用ナビゲーションの変更点（最小限）**：
```erb
<%# 変更前 %>


<%# 変更後（hidden を追加しただけ） %>

```

<br>

`hidden` : モバイルでは非表示（`display: none`）<br>
`md:flex` : 768px 以上で横並びフレックスに切り替わる<br>

<br>

**追加した要素（モバイルのみ）**：
- ハンバーガーボタン（`md:hidden` で PC では非表示）
- モバイル用ドロップダウンメニュー（初期状態 `hidden`・Stimulus で制御）
- ARIA 属性（`aria-expanded`・`aria-controls`・`aria-label`）によるアクセシビリティ対応

<br>

### Stimulus コントローラー（mobile_menu_controller.js）
```javascript
// app/javascript/controllers/mobile_menu_controller.js
static targets = ["menu", "button", "openIcon", "closeIcon"]

connect()    // isOpen フラグ初期化・ESCキーリスナー登録
disconnect() // メモリリーク防止（リスナー全解除・overflow-hidden 残留防止）
toggle()     // ボタンクリック時に開閉状態を反転
closeOnOutsideClick() // ヘッダー外クリックで閉じる
closeOnEscape()       // ESCキーで閉じる
_openMenu()  // hidden 削除・アイコン切替・aria-expanded="true"・スクロールロック
_closeMenu() // hidden 追加・アイコン切替・aria-expanded="false"・スクロールロック解除
```

<br>

`bind(this)` を使う理由：イベントリスナーに渡した関数の `this` がコントローラーインスタンスに固定されるため。<br>
`disconnect()` で必ず解除する理由：Turbo でページ遷移を繰り返すとメモリリークが累積するため。

<br>

### 利用フロー矢印の CSS 実装

<br>

Tailwind CSS では疑似要素（`::before`）の `content` プロパティを直接制御できないため、<br>
`application.css` に `@media` クエリで実装しました。
```css
/* モバイル: 縦並びなので下向き矢印 */
.arrow-divider::before {
  content: "↓";
  color: #9ca3af;
  font-size: 1.5rem;
  font-weight: bold;
}

/* PC（768px 以上）: 右向き矢印に切り替え */
@media (min-width: 768px) {
  .arrow-divider::before {
    content: "→";
  }
}
```

<br>

### モバイルボタンの UX 改善

<br>

| 項目 | 変更前 | 変更後 | 理由 |
|------|--------|--------|------|
| 高さ | `py-3` | `py-4` | Apple 推奨タップ領域 44px 以上を確保 |
| フォント | `text-sm` | `text-base` | モバイルでの視認性向上 |
| フォーカス | なし | `focus-visible:outline` | キーボード操作のアクセシビリティ対応 |
| ボタン幅 | 不均一 | `w-full` + 同一スタイル | ログイン・新規登録のバランスを統一 |

<br>

## エラーハンドリングの改善（Issue #27）

<br>

### 実装概要

<br>

- カスタムエラーページ（404 / 422 / 500）の作成
- バリデーションエラー表示の共通パーシャル化
- フラッシュメッセージのトースト通知化
- 未定義URLのcatch-all対応
- Turbo Streamターゲット ID の重複修正

<br>

### カスタムエラーページ

<br>

`config/application.rb` に `config.exceptions_app = routes` を設定し、Railsのエラーハンドリングをルーティング経由に切り替えます。

<br>

`ErrorsController` を新規作成し、各エラーアクションを定義：
```ruby
# app/controllers/errors_controller.rb

class ErrorsController < ApplicationController
  def not_found
    render_404
  end

  def unprocessable
    render status: :unprocessable_entity
  end

  def internal_server_error
    render status: :internal_server_error
  end
end
```

<br>

`config/routes.rb` にエラー用ルートとcatch-allルートを追加：
```ruby
# エラーページ
get "/404", to: "errors#not_found"
get "/422", to: "errors#unprocessable"
get "/500", to: "errors#internal_server_error"

# catch-allルート（必ず最後に記述）
match "*path", to: "errors#not_found", via: :all
```

<br>

### render file: → render template: の修正

<br>

`pages_controller.rb` で `render file:` を使うとERBが評価されず、HTMLソースがそのまま表示される問題が発生しました。
```ruby
# 修正前（NG）
render file: Rails.root.join("app/views/errors/internal_server_error.html.erb"), ...

# 修正後（OK）
render template: "errors/internal_server_error", layout: "application", status: :internal_server_error
```

<br>

`render template:` はRailsのビュー解決機構を使うためERBが正しく処理されます。

<br>

### バリデーションエラー共通パーシャル（_form_errors.html.erb）

<br>

各フォームで重複していたエラー表示ブロックを1つのパーシャルに集約しました。
```erb
<%# app/views/shared/_form_errors.html.erb %>
<% if model.errors.any? %>
      
        <%= model.errors.count %> 件の入力エラーがあります
    
      <% model.errors.full_messages.each do |message| %>
        <%= message %>
      <% end %>
  
<% end %>
```

<br>

**重要な設計上の注意点**：このパーシャル内に `render` を書いてはいけません。<br>
自分自身を `render` すると `SystemStackError (stack level too deep)` の無限ループが発生します。<br>
ERBコメント（`<%# %>`）内に `<%= render ... %>` を書いても、環境によっては評価されるため同様に危険です。

<br>

呼び出し側では以下のように使います：
```erb
<%= render "shared/form_errors", model: @user %>
<%= render "shared/form_errors", model: @habit %>
<%= render "shared/form_errors", model: @weekly_reflection %>
```

<br>

### Turbo StreamターゲットID重複の修正

<br>

`_habit_record.html.erb` の外側divと `habits/index.html.erb` の習慣カードdivが同じID `habit_record_XX` を使っていたため、チェックボックスON/OFF後にTurboがカード全体をパーシャルの中身だけで置換してしまう問題がありました。

<br>

| 変更前 | 変更後 |
|--------|--------|
| `id="habit_record_<%= habit.id %>"` | `id="habit_record_row_<%= habit.id %>"` |
| コントローラー: `"habit_record_#{@habit.id}"` | `"habit_record_row_#{@habit.id}"` |

<br>

パーシャルのIDとコントローラーの `turbo_stream.replace` のターゲットIDを一致させることで、チェックボックス操作後もカードのデザインが正しく保たれます。

<br>

## セキュリティ対策（Issue #28）

<br>

### 実装概要

<br>

- セッションCookieの明示的な設定強化
- 本番環境へのセキュリティレスポンスヘッダー追加
- Content Security Policy（CSP）初期化ファイルの新規作成
- ApplicationController へのセキュリティ実装状況コメント補強
- CSP起因のフロントエンドバグ（チェックボックス・プログレスバー）の修正

<br>

### セッションCookie設定（config/application.rb）
```ruby
# config/application.rb

config.session_store :cookie_store,
  key:          "_habitflow_session",
  secure:       Rails.env.production?,
  httponly:     true,
  same_site:    :lax,
  expire_after: 14.days
```

<br>

| 設定項目 | 値 | 理由 |
|---------|-----|------|
| `key` | `_habitflow_session` | アプリ固有名でCookieを識別 |
| `secure` | 本番のみ true | HTTPS通信時のみCookieを送信（本番限定） |
| `httponly` | true | JavaScriptからのCookieアクセスを遮断（XSS対策） |
| `same_site` | :lax | 外部サイトからのリクエストでCookieを送らない（CSRF追加対策） |
| `expire_after` | 14.days | 端末紛失・公共PC利用リスクを考慮したバランス値 |

<br>

### セキュリティレスポンスヘッダー（config/environments/production.rb）
```ruby
# config/environments/production.rb

config.action_dispatch.default_headers.merge!(
  "X-Frame-Options"                  => "SAMEORIGIN",
  "X-XSS-Protection"                 => "0",
  "X-Content-Type-Options"           => "nosniff",
  "X-Download-Options"               => "noopen",
  "X-Permitted-Cross-Domain-Policies"=> "none",
  "Referrer-Policy"                  => "strict-origin-when-cross-origin"
)
```

<br>

**`.merge!` を使う理由：**<br>
`=` で代入すると Railsのデフォルトセキュリティヘッダー（CSP・Permissions-Policy等）が全消去されてしまいます。<br>
`.merge!` で既存ヘッダーを保持しながら追加設定を上書きします。

<br>

### Content Security Policy（config/initializers/content_security_policy.rb）
```ruby
# config/initializers/content_security_policy.rb

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none
  policy.script_src  :self, :https        # nonce で Importmap のインラインスクリプトを許可
  policy.style_src   :self, :https, :unsafe_inline  # プログレスバーのインラインスタイル対応
end

# 毎リクエストごとにランダムな nonce を生成し script タグに自動付与
Rails.application.config.content_security_policy_nonce_generator =
  ->(_request) { SecureRandom.base64(16) }

Rails.application.config.content_security_policy_nonce_directives = ["script-src"]
```

<br>

**nonce 方式を採用した理由：**<br>
Rails 7 の Importmap は `<script type="importmap">` というインラインスクリプトを HTML に直接埋め込みます。<br>
`script-src :self` だけではこれがブロックされ、Turbo が初期化されずチェックボックスが動作しません。<br>
`:unsafe_inline` は全インラインスクリプトを許可してしまうため、nonce（ワンタイムトークン）方式を採用しています。<br>
nonce を持つスクリプトのみ実行が許可されるため、攻撃者が注入したスクリプトはブロックされます。

<br>

**`style_src :unsafe_inline` が必要な理由：**<br>
プログレスバーは `style="width: <%= stats[:rate] %>%"` というインライン style 属性を使用しています。<br>
nonce は script 専用のため style 属性には使えません。<br>
CSS インジェクションは JS インジェクションより危険度が低く、script_src は保護済みのため許容範囲と判断しています。

<br>

### CSPバグ修正（チェックボックス・プログレスバー）

<br>

Issue #27 完了後、CSP設定を有効化した際に2つのフロントエンドバグが発覚しました。

<br>

| バグ | 原因 | 修正 |
|------|------|------|
| チェックボックスが動作しない（「✓ 完了」・取り消し線が出ない） | `script-src :self` が Importmap のインラインスクリプトをブロック → Turbo が初期化されず `renderStreamMessage` が無効 | nonce 設定を追加して Importmap を許可 |
| プログレスバーが常に全幅表示 | `style-src` が `style="width: XX%"` をブロック → ブラウザのデフォルト幅（100%）が適用 | `style_src :unsafe_inline` を追加 |

<br>

### 既存のセキュリティ実装（確認済み）

<br>

| 対策 | 実装箇所 | 実装内容 |
|------|---------|---------|
| CSRF対策 | ApplicationController（Rails標準） | `csrf_meta_tags` + `reset_session`（ログイン・ログアウト時） |
| SQLインジェクション対策 | 全コントローラー | Active Record プレースホルダー使用・生SQL未使用 |
| XSS対策 | 全ビュー | ERB `<%= %>` による自動エスケープ・`raw`/`html_safe` 未使用 |
| Strong Parameters | 各コントローラー | `permit` で許可カラムを明示 |
| 認可制御 | ApplicationController / 各コントローラー | `require_login` / `current_user.habits.find` で他ユーザーデータへのアクセスを遮断 |

<br>

## パフォーマンス最適化（Issue #29）

<br>

### Bullet gem 導入

<br>

development環境に Bullet gem を追加し、N+1問題を自動検出できる環境を整備しました。
```ruby
# config/environments/development.rb

config.after_initialize do
  Bullet.enable       = true
  Bullet.alert        = true
  Bullet.rails_logger = true
  Bullet.add_footer   = true
end
```

<br>

### N+1問題の解消：build_habit_stats

<br>

**変更前の問題**：<br>
`WeeklyReflectionsController` の `index` / `new` / `create` で `habit.weekly_progress_stats(current_user)` をループ内で呼んでいたため、習慣がN件あるとSQLがN回発行されていました。

<br>

**変更後**：<br>
`.group(:habit_id).count` によりDB側でCOUNT/GROUP BYを実行し、ActiveRecordオブジェクトを一切生成しない設計に変更しました。
```ruby
# app/controllers/weekly_reflections_controller.rb

def build_habit_stats(habits, user)
  today      = HabitRecord.today_for_record
  week_start = today.beginning_of_week(:monday)
  week_range = week_start..today

  # 変更前: .group_by(&:habit_id) → 全レコードをメモリにロード
  # 変更後: .group(:habit_id).count → DBがCOUNT/GROUP BYで集計
  records_count_by_habit = HabitRecord
    .where(user: user, habit: habits, record_date: week_range, completed: true)
    .group(:habit_id)
    .count

  habits.each_with_object({}) do |habit, hash|
    completed_count = records_count_by_habit[habit.id] || 0
    rate = habit.weekly_target.zero? ? 0 :
      ((completed_count.to_f / habit.weekly_target) * 100).clamp(0, 100).floor
    hash[habit.id] = { rate: rate, completed_count: completed_count }
  end
end
```

<br>

**効果**：SQL発行回数 N+1回 → 2回（habits取得 + records一括集計）

<br>

### ApplicationController#locked? の最適化

<br>

`find_by` でレコード全体をメモリにロードしていた箇所を `exists?` に変更しました。

<br>

| 変更点 | 変更前 | 変更後 |
|--------|--------|--------|
| SQL | `SELECT * FROM ...` | `SELECT 1 FROM ... LIMIT 1` |
| メモリ | ActiveRecordオブジェクト生成あり | オブジェクト生成なし |
| 初週ユーザー | 前週レコードなし → `!false` → 誤ってロック | 前週レコード存在確認を追加 → 正しくスルー |

<br>

### インデックス追加

<br>

`locked?` と振り返り一覧の両クエリパターンをカバーする3カラム複合インデックスを1本追加しました。
```ruby
# db/migrate/YYYYMMDDHHMMSS_add_performance_indexes.rb

add_index :weekly_reflections,
          [:user_id, :week_start_date, :completed_at],
          where: "completed_at IS NOT NULL",
          name: "idx_weekly_reflections_user_week_completed",
          algorithm: :concurrently
```

<br>

- 部分インデックス（`WHERE completed_at IS NOT NULL`）でインデックスサイズを削減
- `CONCURRENTLY` で既存データへのロックなしにインデックスを作成
- 複合インデックスの左端の法則により `locked?` と `index` 両クエリをカバー

<br>

### フィクスチャ設計の改善

<br>

`pending_reflection`（`completed_at: ~`）が `users(:one)` に干渉して Habit 系テストが全滅する問題を修正しました。

<br>

**基本方針**：フィクスチャは「完了済み（`completed_at` あり）」を基本とし、未完了データが必要なテストはテストコード内で動的に作成します。<br>
`pending_reflection` は `locked_user`（`users(:one)` とは別ユーザー）専用に分離し、干渉を完全に排除しています。

<br>

## 統合テスト（Issue #30）

<br>

### テスト設計方針

<br>

既存11ファイルが「個別機能の正常系・異常系」を担当しているのに対し、<br>
Issue #30 では「複数機能が連携して動く一連のフロー（エンドツーエンド）」のみをカバーします。<br>
責務を明確に分離することで、テスト同士の重複をなくしメンテナンスコストを最小化しています。

<br>

### 作成した統合テストファイル（5ファイル・20テストケース）

<br>

| ファイル | テスト数 | カバー範囲 |
|---------|---------|-----------|
| `user_auth_flow_test.rb` | 3 | 登録→ダッシュボード→ログアウト→再ログインの完全フロー |
| `habit_full_flow_test.rb` | 3 | 習慣作成→日次記録（Turbo Stream）→ダッシュボード進捗確認 |
| `weekly_reflection_flow_test.rb` | 3 | 振り返り一覧→新規作成→保存→詳細確認・スナップショット検証 |
| `pdca_lock_flow_test.rb` | 2 | ロック発動→振り返り完了→ロック解除→習慣作成の完全フロー |
| `error_cases_test.rb` | 9 | 404・認可エラー・バリデーション422・他ユーザーデータアクセス防止 |

<br>

### 主要な実装ポイント

<br>

**travel_to による完全固定日付（再現性保証）**

<br>

PDCAロックや週次振り返りは「今週」「前週」という時間依存の概念を持つため、<br>
テストを実行する曜日・時間帯によって結果が変わるリスクがあります。
```ruby
# travel_to の外で Date.current を計算すると travel_to の効果が当たらない（NG）
next_monday = Date.current.beginning_of_week(:monday) + 1.week
travel_to next_monday.in_time_zone.change(hour: 4, min: 1) do ...

# 完全固定の日付を使うことで「どこで実行しても同じ結果」になる（OK）
travel_to Time.zone.local(2026, 3, 9, 4, 1, 0) do ...
```

<br>

**Turbo Stream レスポンスの検証**
```ruby
# Accept ヘッダーを明示することで Turbo Stream フォーマットでレスポンスが返ることを確認
post habit_habit_records_path(habit),
     params:  { completed: "1" },
     headers: { "Accept" => "text/vnd.turbo-stream.html" }

assert_response :success
assert_equal "text/vnd.turbo-stream.html", response.media_type
```

<br>

**422 テストのビュー確認（レビュー反映）**

<br>

HTTPステータスが 422 でも、ビューが壊れてエラーが表示されていない場合はテストをパスしてしまいます。<br>
`assert_select "form"` を追加することでフォームの再レンダリングまで検証しています。
```ruby
assert_response :unprocessable_entity
assert_select "form"  # フォームが再表示されていること（ビュー崩壊を検知）
```

<br>

**fixtures との日付重複回避設計**

<br>

`travel_to` で固定する日付は既存 fixtures の `week_start_date` と重複しない週を選定しています。

<br>

| テストファイル | 固定日付 | 対応する前週 |
|-------------|---------|------------|
| `weekly_reflection_flow_test.rb` | 2026-03-01 / 03-08 / 03-15 | fixtures と非重複 |
| `pdca_lock_flow_test.rb（テスト1）` | 2026-03-09（月）AM4:01 | 前週: 03-02〜03-08 |
| `pdca_lock_flow_test.rb（テスト2）` | 2026-03-16（月）AM4:01 | テスト1と異なる週で干渉防止 |

<br>

**テスト実行コマンド**
```bash
# 統合テスト5ファイルのみ実行
bundle exec rails test \
  test/integration/user_auth_flow_test.rb \
  test/integration/habit_full_flow_test.rb \
  test/integration/weekly_reflection_flow_test.rb \
  test/integration/pdca_lock_flow_test.rb \
  test/integration/error_cases_test.rb

# 全テスト実行（202件）
bundle exec rails test
```

<br>

**テスト結果**:
```
202 runs, 602 assertions, 0 failures, 0 errors, 0 skips
```

<br>
```