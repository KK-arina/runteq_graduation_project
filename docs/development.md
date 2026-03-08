# Development Log（開発進捗ログ）

> このファイルは HabitFlow の**週次開発進捗・ストーリーポイント管理・Issue完了記録**をまとめたドキュメントです。<br>
> Issue管理ボード: https://github.com/users/KK-arina/projects/1/views/1

<br>

---

<br>

## 目次

<br>

1. [全体サマリー](#1-全体サマリー)
2. [Week 1（2/10〜2/16）: 基盤構築](#2-week-1210216-基盤構築)
3. [Week 2（2/16〜2/22）: 習慣管理基盤](#3-week-2216222-習慣管理基盤)
4. [Week 3（2/21〜）: ダッシュボード・週次振り返り](#4-week-3221-ダッシュボード週次振り返り)
5. [Week 4: ロック解除・UI改善](#5-week-4-ロック解除ui改善)
6. [Week 5: バグ修正・最終調整](#6-week-5-バグ修正最終調整)
7. [Week 6（3/1〜3/31）: 本番確認・ドキュメント整備](#7-week-631331-本番確認ドキュメント整備)
8. [テスト件数の推移](#8-テスト件数の推移)

<br>

---

<br>

## 1. 全体サマリー

<br>

| 項目 | 内容 |
|:---|:---|
| 開発期間 | 2026年2月10日〜3月31日（約7週間） |
| 総Issue数 | #1〜#42 |
| 完了Issue数 | #1〜#37（Week 6対応中） |
| 最終テスト結果 | 221 runs, 648 assertions, 0 failures, 0 errors, 0 skips |
| 本番URL | https://habitflow-web.onrender.com |

<br>

---

<br>

## 2. Week 1（2/10〜2/16）: 基盤構築

<br>

**進捗: 20SP / 20SP（100%）🎉**

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|:---:|:---|:---:|:---:|:---:|
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

### Week 1 達成内容

<br>

- Docker + Rails 7.2.3 + PostgreSQL 16 + Tailwind CSS 環境構築完了
- bcrypt + has_secure_password によるスクラッチ認証実装
- Render（無料プラン）への初回デプロイ成功・自動デプロイ設定完了
- 共通ヘッダー・フッター実装（全ページ統一）
- テスト結果: **20 runs, 59 assertions, 0 failures**

<br>

---

<br>

## 3. Week 2（2/16〜2/22）: 習慣管理基盤

<br>

**進捗: 20SP / 20SP（100%）🎉**

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|:---:|:---|:---:|:---:|:---:|
| #10 | Habitモデルの作成 | ✅ 完了 | 2/15 | 2 |
| #11 | 習慣一覧ページの作成 | ✅ 完了 | 2/15 | 2 |
| #12 | 習慣新規作成機能 | ✅ 完了 | 2/15 | 3 |
| #13 | 習慣削除機能 | ✅ 完了 | 2/15 | 2 |
| #14 | HabitRecordモデルの作成 | ✅ 完了 | 2/16 | 2 |
| #15 | 習慣の日次記録機能（即時保存） | ✅ 完了 | 2/19 | 5 |
| #16 | 進捗率の自動計算ロジック | ✅ 完了 | 2/19 | 2 |
| #17 | 習慣管理機能のテスト | ✅ 完了 | 2/20 | 2 |

<br>

### Week 2 達成内容

<br>

- Habitモデル（論理削除: `deleted_at`・activeスコープ）実装
- HabitRecordモデル（AM4:00基準日付・UNIQUE制約・CASCADE）実装
- Turbo Streams即時保存・楽観的UI・Stimulusコントローラー実装
- 週次進捗統計（`weekly_progress_stats`・N+1対策済み）実装
- テスト結果: **119 runs, 322 assertions, 0 failures**

<br>

---

<br>

## 4. Week 3（2/21〜）: ダッシュボード・週次振り返り

<br>

**進捗: 20SP / 20SP（100%）🎉**

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|:---:|:---|:---:|:---:|:---:|
| #18 | ダッシュボードの作成 | ✅ 完了 | 2/21 | 4 |
| #19 | WeeklyReflectionモデルの作成 | ✅ 完了 | 2/21 | 2 |
| #20 | WeeklyReflectionHabitSummaryモデルの作成 | ✅ 完了 | 2/21 | 2 |
| #21 | 週次振り返り一覧ページ | ✅ 完了 | 2/21 | 2 |
| #22 | 週次振り返り入力ページ | ✅ 完了 | 2/21 | 4 |
| #23 | 週次振り返り詳細ページ | ✅ 完了 | 2/21 | 2 |
| #24 | PDCA強制ロック機能 | ✅ 完了 | 2/21 | 4 |

<br>

### Week 3 達成内容

<br>

- ダッシュボード実装（N+1対策・`today_records_hash` + `habit_stats`）
- WeeklyReflectionモデル（UNIQUE制約・AM4:00基準週計算）実装
- WeeklyReflectionHabitSummaryモデル（スナップショット設計・冪等性対応）実装
- PDCA強制ロック（月曜AM4:00判定・新規作成/削除ブロック・警告バナー）実装
- テスト結果: **198 runs, 474 assertions, 0 failures**

<br>

---

<br>

## 5. Week 4: ロック解除・UI改善

<br>

**進捗: 20SP / 20SP（100%）🎉**

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|:---:|:---|:---:|:---:|:---:|
| #25 | 振り返り完了時のPDCAロック自動解除 | ✅ 完了 | 2/22 | 2 |
| #26 | レスポンシブデザインの調整 | ✅ 完了 | 2/23 | 4 |
| #27 | エラーハンドリングの改善 | ✅ 完了 | 2/25 | 3 |
| #28 | セキュリティ対策 | ✅ 完了 | 2/26 | 3 |
| #29 | パフォーマンス最適化 | ✅ 完了 | 2/26 | 2 |
| #30 | 統合テスト（主要フロー） | ✅ 完了 | 2/27 | 6 |

<br>

### Week 4 達成内容

<br>

- `complete!` メソッド拡張（`completed_at` + `is_locked` 同時更新）
- `was_locked` を保存前に記録する設計でロック解除フロー実装
- ハンバーガーメニュー実装（`mobile_menu_controller.js`・ARIA対応）
- カスタムエラーページ（404/422/500）・バリデーション共通パーシャル実装
- CSP設定（nonce方式）・セッションCookie設定強化
- Bullet gem導入・N+1解消・3カラム複合インデックス追加
- E2Eフロー統合テスト5ファイル・20ケース追加
- テスト結果: **202 runs, 602 assertions, 0 failures**

<br>

---

<br>

## 6. Week 5: バグ修正・最終調整

<br>

**進捗: 20SP / 20SP（100%）🎉**

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|:---:|:---|:---:|:---:|:---:|
| #31 | バグ修正週 | ✅ 完了 | 2/28 | 8 |
| #32 | UI/UX最終調整 | ✅ 完了 | 2/28 | 4 |
| #33 | アクセシビリティ対応 | ✅ 完了 | 3/1 | 2 |
| #34 | seeds.rb の充実 | ✅ 完了 | 3/1 | 2 |
| #35 | ログ設定 | ✅ 完了 | 3/1 | 2 |
| #36 | 最終デプロイ・本番確認 | ✅ 完了 | 3/1 | 2 |

<br>

### Week 5 達成内容

<br>

- `order(created_at: :desc).first` → `find_by(name:)` 修正（fixtures依存バグ解消）
- `form_submit_controller.js`（ローディング・二重送信防止・バックボタン復帰対応）実装
- WCAG 2.1 AA基準対応（スキップリンク・aria-live・aria-current・focus:ring）
- ERBコメント構文バグ（`%>`誤認識）を全ファイルで修正
- seeds.rb 本番誤実行防止ガード（`SEED_IN_PRODUCTION` フラグ方式）
- `render.yaml` に `startCommand` 追加（`db:migrate` 自動実行・`exec` Graceful Shutdown）
- テスト結果: **202 runs, 604 assertions, 0 failures**

<br>

---

<br>

## 7. Week 6（3/1〜3/31）: 本番確認・ドキュメント整備

<br>

**進捗: 4SP / 20SP（目標: 3/31 レビュー依頼提出）**

<br>

| Issue | タイトル | ステータス | 完了日 | SP |
|:---:|:---|:---:|:---:|:---:|
| #37 | 本番環境最終動作確認 | ✅ 完了 | 3/8 | 4 |
| #38 | READMEとドキュメント整備 | 🔄 対応中 | — | 3 |
| #39 | 最終動作確認チェックリスト | 🔲 未着手 | — | 3 |
| #40 | MVPレビュー準備 | 🔲 未着手 | — | 2 |
| #41 | 最終バグ修正バッファ | 🔲 未着手 | — | 6 |
| #42 | 最終調整とレビュー依頼提出準備 | 🔲 未着手 | — | 2 |

<br>

### Issue #37 達成内容（重大バグ修正含む）

<br>

- **タイムゾーン重大バグ修正**: `config.time_zone = "Tokyo"` / `config.active_record.default_timezone = :local` 追加（未設定で本番ロック時刻が9時間ズレていた）
- **先週未完了振り返り優先表示**: `find_pending_last_week_reflection` 追加
- **フォームPATCH→POSTバグ修正**: `form_with` に `url:` と `method: :post` を明示
- **DBユニーク制約追加**: `weekly_reflections` に `user_id + week_start_date` の unique index（`if_not_exists: true`）
- **downcase_email nil安全化**: `email.to_s.downcase`
- 本番環境最終動作確認テスト19ケース追加
- テスト結果: **221 runs, 648 assertions, 0 failures**

<br>

---

<br>

## 8. テスト件数の推移

<br>

| 時点 | runs | assertions | failures | errors |
|:---:|:---:|:---:|:---:|:---:|
| Week 1完了（#9） | 20 | 59 | 0 | 0 |
| Week 2完了（#17） | 119 | 322 | 0 | 0 |
| Week 3 #24完了 | 198 | 474 | 0 | 0 |
| Week 4完了（#30） | 202 | 602 | 0 | 0 |
| Week 5完了（#36） | 202 | 604 | 0 | 0 |
| **Week 6 #37完了** | **221** | **648** | **0** | **0** |

<br>

---

<br>

## 主要な教訓（Issue #1〜#37）

<br>

### タイムゾーン・時間依存ロジック

<br>

| 教訓 | 詳細 |
|:---|:---|
| `config.time_zone` は最初に設定する | 未設定でRailsがUTCで動作し本番で9時間ズレる（Issue #37） |
| `Time.current` / `Date.current` を使う | `Time.now` はタイムゾーン非対応（Issue #14） |
| `travel_to` のスコープに注意 | `travel_to` 外で `Date.current` を計算すると効果が当たらない（Issue #30） |
| `form_with` のHTTPメソッド自動判定 | `persisted?=true` のレコードを渡すと自動でPATCHになる。routesにupdateがない場合は `url:` と `method:` を明示（Issue #37） |

<br>

### テスト設計

<br>

| 教訓 | 詳細 |
|:---|:---|
| `order(created_at: :desc).first` は使わない | fixturesの `created_at` は順序が不安定。`find_by` で値を直接特定する（Issue #31, #33） |
| `assert_not_nil` をセットで付ける | レコード取得失敗時に原因を早期検出できるようにする |
| fixtures と動的データの干渉を防ぐ | `setup` でデータリセット。未完了データが必要なテストはテスト内で動的作成する |

<br>

### ERBコメント構文バグ

<br>

| 教訓 | 詳細 |
|:---|:---|
| コメントブロック内に `%>` を含む文字列を書かない | `%>` がコメント閉じタグと誤認識されテキストがHTMLとして出力される（Issue #32, #33） |
| コメントブロックの `%>` 閉じ忘れに注意 | `ActionView::SyntaxErrorInTemplate` が発生する |

<br>

### N+1問題対策

<br>

| 教訓 | 詳細 |
|:---|:---|
| ループ内でDBアクセスするメソッドを呼ばない | コントローラーで `.group(:habit_id).count` による一括集計を行いハッシュで渡す（Issue #16, #29） |
| `find_by` → `exists?` で最適化 | 存在確認だけなら `SELECT 1 LIMIT 1` で十分（Issue #29） |

<br>

### 本番デプロイ設計

<br>

| 教訓 | 詳細 |
|:---|:---|
| `exec` を必ず付ける | `exec bin/rails server` でRailsがPID 1になりGraceful Shutdownが機能する（Issue #36） |
| `db:migrate` を `startCommand` に含める | デプロイと同時に自動適用。`migrate` は冪等なので毎回実行しても安全（Issue #36） |
| seeds.rb には環境変数フラグ方式の本番ガードを入れる | `SEED_IN_PRODUCTION` フラグで二重ロック（Issue #34, #36） |
| マイグレーションに `if_not_exists: true` を付ける | 冪等性を保証（Issue #37） |

<br>

---

<br>

*最終更新: 2026年3月*
