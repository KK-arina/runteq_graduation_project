# HabitFlow ドキュメント一覧

> このディレクトリは **MVPレビューおよび開発ドキュメント** をまとめた場所です。<br>
> レビュアーや開発者が、サービスの仕様・デモ方法・設計を素早く理解できるよう整理しています。

<br>

---

<br>

## 📚 ドキュメント一覧

<br>

| ファイル | 内容 |
|:---------|:-----|
| [`demo_scenario.md`](demo_scenario.md) | MVPレビュー用のデモ操作手順（所要時間 5〜10 分） |
| [`known_issues.md`](known_issues.md) | MVP 時点の既知の問題点 & 本リリース以降の改善予定リスト |
| [`mvp_review_issue.md`](mvp_review_issue.md) | GitHub Issue 提出用の MVPレビュー依頼原稿（コピペ用） |
| [`er-diagram-mvp.md`](er-diagram-mvp.md) | ER 図（Mermaid 形式） |
| [`database-schema-mvp.md`](database-schema-mvp.md) | テーブル定義書 |
| [`user_guide.md`](user_guide.md) | 初めて使う方向けの操作手順ガイド |
| [`architecture.md`](architecture.md) | 設計・技術実装ノート（技術選定の理由・実装詳細） |
| [`development.md`](development.md) | 開発進捗ログ（Week 別 SP 管理・Issue 完了記録・教訓） |
| [`operations.md`](operations.md) | 運用・デプロイ記録（本番環境設定・チェックリスト） |
| [`logging_and_backup.md`](logging_and_backup.md) | 本番ログ確認・バックアップ手順 |
| [`features.md`](features.md) | 本リリース実装済み機能の詳細（ISSUE 別） |
| [`technical-notes.md`](technical-notes.md) | 技術的な工夫の詳細 |
| [`lessons-learned.md`](lessons-learned.md) | 開発を通じて得た教訓 |
| [`archive/mvp-verification.md`](archive/mvp-verification.md) | MVP 期の検証記録アーカイブ（旧 Issue #7/#9/#37/#39 を統合） |

<br>

---

<br>

## 🎯 MVPレビュー時に参照する順序

<br>

**レビュアーの方はこの順番でご確認ください。**

<br>

**1️⃣ デモ操作手順**<br>
→ [`demo_scenario.md`](demo_scenario.md)<br>
　サービス URL とデモアカウント情報、推奨操作フローをまとめています。

<br>

**2️⃣ 既知の制限事項**<br>
→ [`known_issues.md`](known_issues.md)<br>
　MVP 時点で未実装の機能と、その理由・今後の対応予定を記載しています。

<br>

**3️⃣ レビュー依頼 Issue 本文**<br>
→ [`mvp_review_issue.md`](mvp_review_issue.md)<br>
　GitHub Issue に提出した原稿の保存版です。

<br>

---

<br>

## 🗂️ スクリーンショット

<br>

実際の画面イメージは [`screenshots/`](screenshots/) フォルダに格納されています。

<br>

| ファイル | 説明 |
|:---------|:-----|
| `screenshots/dashboard_1〜2.png` | ダッシュボード画面（上部・下部） |
| `screenshots/weekly_reflection_1〜3.png` | 週次振り返り画面 |
| `screenshots/habits_index_1.png` | 習慣一覧画面 |
| `screenshots/tasks_1.png` | タスク管理画面 |
| `screenshots/analytics_1〜2.png` | グラフ・進捗分析画面 |
| `screenshots/pmvv_1〜3.png` | PMVV 目標管理・AI 分析画面 |
| `screenshots/mobile_1.png` | スマホ版（Bottom Navigation） |

<br>

---

<br>

## 📅 更新履歴

<br>

| 日付 | 内容 |
|:-----|:-----|
| 2026-03-10 | Issue #40 対応として MVPレビュー用ドキュメントを追加・初版作成 |
| 2026-09-23 | #I-4: README を3ファイルに分割・スクショ更新・MVP検証レポートを archive に統合 |
