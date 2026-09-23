## 🔧 技術的な工夫

<br>

### 1. AM4:00 基準の日付管理

<br>

深夜に習慣を行うユーザーを考慮し、1日の境界を **AM4:00** に設定しています。<br>
`Time.now` ではなく `Time.current` を使用し、タイムゾーン（JST）を確実に適用しています。<br>
```ruby
def self.today_date
  now = Time.current
  now.hour < 4 ? now.to_date - 1.day : now.to_date
end
```

<br>

### 2. N+1 問題の解消

<br>

ダッシュボードでは複数の習慣と記録を同時に表示するため、`index_by` と `group(:habit_id).count` を使い、**それぞれ1クエリで**一括取得しています。ループ内での DB アクセスを完全に排除し、習慣が増えてもクエリ数が変わらない設計にしています。<br>
```ruby
# 今日の記録を O(1) で参照できるハッシュに変換（1クエリ）
@today_records_hash = current_user.habit_records
  .where(recorded_on: today).index_by(&:habit_id)

# 今週の集計も1クエリで完結
@weekly_counts_hash = current_user.habit_records
  .where(recorded_on: week_start..(week_start + 6.days))
  .group(:habit_id).count
```

<br>

### 3. PDCA 強制ロックの設計

<br>

「振り返りをしたくなる仕組み」ではなく「**振り返りをしないと前に進めない仕組み**」を採用しました。  
行動心理学の「実行意図（Implementation Intention）」に基づき、振り返りを完了しないと習慣の追加・削除を物理的にブロックします。UI だけでなくサーバー側でも必ずチェックし、API ツールからの直接リクエストも防いでいます。

<br>

### 4. スナップショット設計による履歴の正確性

<br>

振り返り保存時点の習慣名・目標値を `weekly_reflection_habit_summaries` に記録しています。  
後から習慣を変更・削除しても**過去の振り返り詳細ページは常に正確な値を表示**できます。

<br>

### 5. 本リリース DB 設計の主要ポイント

<br>

**① `deleted_at` と `archived_at` の分離設計**

<br>

habits テーブルで削除（`deleted_at`）と卒業アーカイブ（`archived_at`）を別カラムで管理。<br>
「もう使わない習慣」と「達成して卒業した習慣」を区別し、アーカイブは復元可能にしている。

<br>

**② `ai_analyses` の再実行対応設計（`is_latest` フラグ）**

<br>

当初は `UNIQUE(weekly_reflection_id)` のみの制約だったが、AI の再実行・精度改善時に詰まる問題を発見。<br>
`is_latest` フラグを追加し、`UNIQUE(weekly_reflection_id) WHERE is_latest = true` という部分インデックスに変更。<br>
過去の分析履歴（`input_snapshot` / `prompt_version` / `model_name`）を削除せず保持できる設計になっている。

<br>

**③ `password_reset_tokens` のセキュリティ設計**

<br>

平文トークンを DB に保存する設計から `token_digest`（ハッシュ化済み）保存に変更。<br>
DB 漏洩時に攻撃者がリセット URL を再現できない構造にしている（Devise と同じアプローチ）。<br>
また `user_id` に UNIQUE 制約を追加し、1ユーザーにつきトークンが1件のみ存在する設計で多重発行を防止。

<br>

**④ `notification_logs.deep_link_url` によるディープリンク設計**

<br>

LINE 通知をタップした際にアプリ内の特定画面へ直接遷移できるよう、遷移先パスを通知ログに保存。<br>
未ログイン時は `/login?redirect_to={deep_link_url}` を経由してログイン後に自動遷移する。

<br>

**⑤ `disable_ddl_transaction!` による本番ダウンタイムゼロのインデックス追加**

<br>

`notification_logs` への追加インデックスは `algorithm: :concurrently` を使用。<br>
通常のインデックス作成はテーブル全体に書き込みロックをかけるが、<br>
`concurrently` を指定することで本番環境でもユーザーへの影響なくインデックスを追加できる。

<br>

### 5-2. グラフページのN+1ゼロ設計（H-4）

<br>

「習慣 × 週」の組み合わせでグラフを描画する画面は、素朴に実装すると<br>
習慣数×週数だけクエリが発行される典型的なN+1の温床になる。<br>
`habit_records` を期間全体ぶん `pluck` で1回だけ取得し、Rubyのハッシュで<br>
`[habit_id, 週開始日]` ごとにグルーピングすることで、習慣数・週数に関わらず<br>
クエリを常に1回に抑える設計にした。

<br>

**Active Recordの隠れた仕様への対応**<br>
`habit_excluded_days.pluck(:day_of_week)` は `includes` で preload 済みであっても<br>
必ずDBに再問い合わせしてしまう仕様があるため、preload済み配列を直接<br>
`.map(&:day_of_week)` する設計に変更し、N+1を確実に回避した。

<br>

### 5-3. Bottom Navigationバッジの「訪問ベース」リセット設計（H-4）

<br>

H-1時点では「直近7日以内に完了した分析」を機械的にバッジ表示していたが、<br>
グラフページを確認した後も7日間バッジが消えない問題があった。<br>
`user_settings.last_analytics_viewed_at`（最後にグラフページを開いた日時）を<br>
基準時刻にし、ページを開いた瞬間に `touch_analytics_viewed_at!` で<br>
基準時刻を更新することで、「確認したら即座にバッジが消える」体験を実現した。

<br>

Railsの `has_one` アソシエーションキャッシュが同一リクエスト内で機能することを利用し、<br>
更新直後のレイアウトレンダリング時に最新の `last_analytics_viewed_at` が<br>
そのままバッジ判定に使われる設計にしている（追加クエリなし）。

<br>

### 5-4. Chart.js のCDN配布形式問題と UMDビルドによる解決（H-4）

<br>

Chart.js の ESM版（`dist/chart.js`）は内部コードが複数の兄弟ファイル<br>
（`dist/chunks/helpers.dataset.js` 等）に分割された構造になっており、<br>
importmap-rails の `pin` コマンドでメイン部分のみを取得しても、<br>
ブラウザが解決できない相対パスへのリクエストで404/422が発生する問題があった。<br>
全コードを1ファイルに完全インライン化した UMDビルド（`dist/chart.umd.js`）を採用し、<br>
`window.Chart` 経由でグローバル変数としてアクセスする方式に変更することで解決した。

<br>

UMDビルドは Chart.js コンポーネントが読み込み時点で自動登録されているため、<br>
`Chart.registerables` が `undefined` になる。`Array.isArray()` で存在確認してから<br>
`Chart.register()` を呼ぶ防御的な実装にすることで、登録方式が異なる<br>
将来のビルド変更にも安全に対応できるようにしている。

<br>

### 5-5. Empty State の共通パーシャル設計（H-7）

<br>

`app/views/shared/_empty_state.html.erb` を共通パーシャルとして新規作成し、<br>
6画面のEmpty State表示を1ファイルに集約（DRY原則）した。<br>

<br>

**`local_assigns.fetch` によるデフォルト値設定**<br>
Railsパーシャルでデフォルト値を安全に設定する方法として `local_assigns.fetch(:key, default)` を採用。<br>
`defined?(変数名)` のスコープ問題や `||=` の false誤作動リスクを回避できる。

<br>

**ロック状態とCTAの出し分け設計**<br>
`cta_label` / `cta_path` が両方 `nil` のときボタンが非表示になる設計により、<br>
ロック中は「cta_label / cta_pathを渡さない」だけでボタンが消える。<br>
呼び出し元のロジックがシンプルになり、パーシャル側のロジックも最小限に保てる。

<br>

**`data-testid` によるテスト識別**<br>
各画面のEmpty Stateに固有の `testid:` を渡すことで、<br>
`assert_select "[data-testid='dashboard-habits-empty-state']"` のように<br>
テストコードから特定のEmpty Stateを識別できる設計にした。<br>
analytics の `testid: "analytics-empty-state"` は既存テストが参照しているため維持した。

<br>

### 6. `db:prepare` ではなく `db:migrate` を使う理由

<br>

Neon などのマネージド PostgreSQL では「DB 作成権限（`CREATE DATABASE`）」がユーザーに付与されていない。<br>
`db:prepare` は「DB が存在しなければ作成 → マイグレーション実行」という処理のため、<br>
CREATE DATABASE ステップで権限エラーが発生し `exit 1` → デプロイ失敗ループになる。<br>
`db:migrate` は既存 DB に対してマイグレーションのみ実行するため、マネージド DB で正しく動作する。<br>
何度実行しても適用済みはスキップされるため安全（冪等性あり）。<br>
```ruby
# ❌ Neon ではエラーになる（CREATE DATABASE 権限なし）
DISABLE_DATABASE_ENVIRONMENT_CHECK=1 ./bin/rails db:prepare

# ✅ Neon で正しく動作する（既存 DB へのマイグレーションのみ）
./bin/rails db:migrate
```

<br>

### 7. `exec` による Graceful Shutdown の実現

<br>

`startCommand` や `docker-entrypoint` の最後で `exec` を使って Puma を起動している。<br>
`exec` を使わない場合、シェル（PID 1）→ Puma（PID 2）という親子関係になり、<br>
Render の停止シグナル（SIGTERM）がシェルに届いても Puma に転送されず強制終了（SIGKILL）される。<br>
`exec` を使うと Puma が PID 1 になり SIGTERM を直接受け取れるため、<br>
処理中のリクエストを完了してから終了する Graceful Shutdown が機能する。<br>
```bash
# ❌ exec なし：シェルが PID 1 のまま → SIGTERM が Puma に届かない
bundle exec puma -C config/puma.rb

# ✅ exec あり：Puma が PID 1 になる → Graceful Shutdown が機能する
exec bundle exec puma -C config/puma.rb
```

<br>

### 8. GoodJob のバージョン問題と解決アプローチ（#A-3）

<br>

**① バージョン体系の罠**

<br>

GoodJob はバージョンによって設定 API と DB スキーマが大きく変わる。<br>

| バージョン | 状態 |
|:---|:---|
| 3.3.x | Rails 7.2 の新 API（`enqueue_after_transaction_commit?`）に未対応 |
| 3.30.1 | 3.x 系の最終安定版 |
| 3.99.x | 4.x への移行版。DB スキーマが変わる |
| 4.x | Rails 7.2 / 8.x 正式対応。最新設計 ← 採用 |

<br>

最終的に GoodJob 4.x（最新版・バージョン固定なし）を採用。<br>
`good_job:install` で 4.x 用の完全なスキーマを新規生成することで解決。

<br>

**② 設定 API の変遷**

<br>

GoodJob 4.x では `GoodJob.configure { |c| ... }` ブロックが廃止されている。<br>
`Rails.application.configure do ... end` ブロック内に `config.good_job.*` 形式で設定する。<br>
これが 4.x で動作する公式推奨の書き方。

<br>

**③ catch-all ルートと GoodJob ダッシュボードの順序問題**

<br>

Rails のルーティングは上から順に評価される。<br>
`match "*path", to: "errors#not_found", via: :all`（catch-all）が先にあると<br>
`/good_job` も 404 になってしまう。<br>
GoodJob のマウントを catch-all より前に記述することで解決。

<br>

**④ `docker compose restart` vs `docker compose up --build` の違い**

<br>

| コマンド | 挙動 |
|:---|:---|
| `docker compose restart` | コンテナ再起動のみ。コードの変更は反映されない |
| `docker compose up --build` | Docker イメージを再ビルド。`bundle install` が再実行される |

<br>

`execution_mode` 等の設定変更は `--build` なしでは反映されない。<br>
gem の追加・変更・設定ファイルの変更後は必ず `docker compose up --build` を実行すること。

<br>

### 9. 非同期処理（GoodJob）の構成について（#A-4 で変更）

<br>

本アプリでは GoodJob を使用して非同期処理を実装しています。<br>
本来は Background Worker（別プロセス）を使用する構成が推奨されますが、<br>
Render の Free プランでは Worker が利用できないため、以下の構成を採用しています。

<br>

| 項目 | 内容 |
|:---|:---|
| `execution_mode` | `:async`（Webプロセス内でバックグラウンド処理を実行） |
| `max_threads` | `2`（Freeプランのリソース制約に合わせて制限） |
| ジョブの永続化 | PostgreSQL（Neon）に保存されるため再起動後も消えない |

<br>

#### 制約事項

<br>

- Webサーバーとジョブ処理が同一プロセスのため、重い処理（CSV生成・AI分析）は<br>
  Webのレスポンス速度に影響する可能性があります<br>
- 本番用途では Worker 分離構成を推奨します

<br>

#### 将来的な拡張

<br>

有料プラン（Starter: $7/月）移行時に以下の変更で Worker を分離できます。<br>
```ruby
# config/environments/production.rb
config.good_job.execution_mode = :external  # :async から変更
```

<br>

render.yaml に以下の Worker 設定を追加することで<br>
自動的に habitflow-worker が作成されます。

<br>

### 10. 開発環境でのメール確認（letter_opener_web）

<br>

開発中に実際のメール送信を行うと以下の問題が発生する。<br>
- Resend の無料枠（月3,000通）を無駄に消費する<br>
- 実在するアドレスに誤ってメールが届く危険がある

<br>

**なぜ letter_opener ではなく letter_opener_web を使うのか:**<br>
`letter_opener` は送信のたびにブラウザを自動起動しようとするが、<br>
Dockerコンテナ内にはブラウザが存在しないため開かれない。<br>
`letter_opener_web` は `/letter_opener` にアクセスするだけで<br>
送信済みメールの一覧を確認できる Web UI を提供するため Docker 環境に最適。

<br>

http://localhost:3000/letter_opener

<br>

パスワードリセットを申請してメールが一覧に表示されることで送信基盤の動作を確認できる。

<br>

### 11. seeds.rb の冪等性設計（find_or_initialize_by パターン）

<br>

`find_or_create_by!` のブロック方式は「新規作成時のみ」属性をセットするため、<br>
既存レコードが永遠に更新されないという問題がある。<br>
例えば description を後から修正しても、本番 DB には反映されない。<br>

<br>

`find_or_initialize_by` + `assign_attributes` + `save!` を組み合わせることで<br>
新規作成・既存更新の両方を1つのパターンで安全に処理できる。<br>
```ruby
# ❌ find_or_create_by! ブロック方式：既存データが更新されない
HabitTemplate.find_or_create_by!(name: data[:name], category: data[:category]) do |t|
  t.description = data[:description]  # 既存レコードがあればここは実行されない
end

# ✅ find_or_initialize_by + assign_attributes：新規・既存どちらも正しく処理される
template = HabitTemplate.find_or_initialize_by(name: data[:name], category: data[:category])
is_new = template.new_record?  # assign_attributes の前に確認（重要）
template.assign_attributes(description: data[:description], ...)
template.save!
```

<br>

`new_record?` は `assign_attributes` の**前**に確認すること。<br>
`assign_attributes` 後はインスタンスの状態が変化するため、正確な新規/既存判定ができなくなる場合がある。

<br>

### 12. インデックス設計と本番ダウンタイムゼロの実現（#A-6）

<br>

**① インデックス監査の観点**

<br>

単体インデックスと複合インデックスでは、同じクエリに対するパフォーマンスが大きく異なる。<br>
```sql
-- このクエリに対して...
WHERE user_id = ? AND status = 0 AND deleted_at IS NULL ORDER BY due_date ASC

-- ❌ deleted_at 単体インデックス → Heap Fetch が大量発生
-- ✅ (user_id, status, deleted_at, due_date) 複合部分インデックス → Index Only Scan で完結
```

<br>

**② `algorithm: :concurrently` の使い方**

<br>

通常の `add_index` はテーブル全体に書き込みロックをかけるため、<br>
本番稼働中に実行するとその間ユーザーが操作できなくなる。<br>
`disable_ddl_transaction!` + `algorithm: :concurrently` を組み合わせることで<br>
他の操作をブロックせずにインデックスを追加できる。

<br>

**③ `change` ではなく `up/down` を使う理由**

<br>

`change` メソッドでは Rails が自動で逆操作（rollback 時の処理）を生成しようとするが、<br>
`concurrently` で作ったインデックスの削除も `concurrently` で行う必要があり<br>
自動生成では対応できない。`up/down` を明示することで rollback の挙動を完全にコントロールできる。

<br>

### 13. サービスクラスによるトランザクション境界の集約（#A-7）

<br>

**① rescue の位置がトランザクションの正確さを決める**

<br>

`ActiveRecord::Base.transaction do ... end` のブロック「内側」に `rescue` を書くと、<br>
例外がロールバックをトリガーする前にキャッチされ、DBが中途半端な状態でコミットされる。<br>
```ruby
# ❌ transaction の内側で rescue → ロールバックが発生しない
ActiveRecord::Base.transaction do
  save!
rescue => e
  { success: false }  # ← ここでキャッチするとロールバックされずコミットされる
end

# ✅ transaction の外側で rescue → ロールバック完了後にキャッチ
ActiveRecord::Base.transaction do
  save!              # ← ここで例外発生 → Rails が自動ロールバック
end
rescue => e          # ← ロールバック完了後にここに来る
{ success: false }
```

<br>

**② テストでのクラス汚染防止: `stub` の活用**

<br>

テスト内でクラスメソッドやインスタンスメソッドを `define_method` で直接書き換えると、<br>
`ensure` での復元が不完全な場合に他テストに影響するフレーキーテストが発生する。<br>
`minitest/mock` の `stub` はブロックを抜けると自動で元に戻るため安全。<br>
```ruby
# ❌ define_method + remove_method → 元のメソッドも消えてしまう
WeeklyReflection.define_method(:complete!) { raise ... }
ensure
  WeeklyReflection.remove_method(:complete!)  # 元の実装も削除される

# ✅ stub → ブロックを抜けると自動で元に戻る
error_lambda = -> { raise ActiveRecord::RecordInvalid, invalid_record }
reflection.stub(:complete!, error_lambda) do
  # このブロック内だけ complete! が差し替えられる
end
```

<br>

### 14. ストリーク計算の N+1 防止設計（#B-3）

<br>

ストリーク計算は全ユーザー × 全習慣をバッチ処理するため、N+1 が発生すると処理時間が指数的に増大する。<br>
以下の設計で全ての N+1 を排除している。

<br>

**① 90日分の記録を1クエリで一括取得・Hash化**

```ruby
# ❌ ループ内でクエリ → 90日 × 習慣数 のクエリが発生
(0..90).each do |i|
  HabitRecord.find_by(record_date: date - i, ...)  # N+1
end

# ✅ 90日分を1クエリで取得して Hash に変換 → ループ内はメモリ参照のみ
records_map = habit_records
  .where(record_date: start_date..reference_date)
  .pluck(:record_date, :completed, :numeric_value)
  .each_with_object({}) { |(date, comp, num), hash| hash[date] = ... }
```

<br>

**② Job 側で includes を使って関連データを一括取得**

```ruby
Habit.active
  .includes(:habit_excluded_days)   # excluded_day_numbers の N+1 防止
  .includes(user: :user_setting)    # on_rest_mode? の N+1 防止
  .find_each { |habit| habit.calculate_streak!(reference_date) }
```

<br>

`find_each` を使う理由: 大量レコードを1000件ずつバッチ処理してメモリ効率を高めるため。<br>
`each` は全レコードを一括ロードするが `find_each` は分割して処理するためユーザー数が増えても安全。

<br>

### 15. on_rest_mode? と rest_mode_on_date? の分離設計（#B-3）

<br>

お休みモードの判定を「現在」と「過去の日付」で分離している。<br>

<br>

**なぜ分離が必要か:**<br>
ストリーク計算では基準日から過去に向かって1日ずつ遡るため、<br>
各日が「その日にお休みモード中だったか」を正確に判定する必要がある。<br>
`on_rest_mode?`（現在時刻での判定）を使うと、<br>
「昨日はお休みモード中だったが今日（計算時点）は終了している」ケースで<br>
昨日の未達成が誤って「通常未達成」と判定されストリークがリセットされるバグになる。<br>
```ruby
# on_rest_mode? → 今この瞬間のお休みモード状態（UI表示用）
def on_rest_mode?
  user.user_setting&.rest_mode_active?
end

# rest_mode_on_date?(date) → 指定した日付のお休みモード状態（ストリーク計算用）
def rest_mode_on_date?(date)
  return false unless allow_rest_mode
  setting = user.user_setting
  return false unless setting&.rest_mode_until.present?
  setting.rest_mode_until.to_date >= date  # その日はまだお休み期間内か
end
```

<br>

### 16. travel_to のネスト禁止と代替手法（#B-3）

<br>

Rails 7.x 以降は `travel_to` ブロックの入れ子を `RuntimeError` として禁止している。<br>
「昨日作成されたレコード」を再現したい場合に `travel_to` を2重にネストするパターンは使えない。<br>
```ruby
# ❌ travel_to のネスト → RuntimeError
travel_to Time.zone.local(2026, 4, 12) do
  record = HabitRecord.create!(...)
  travel_to Time.zone.local(2026, 4, 13) do  # RuntimeError: Calling travel_to with a block...
    assert_not record.first_recorded_today?
  end
end

# ✅ update_columns で created_at を直接書き換えて「昨日作成」を再現する
travel_to Time.zone.local(2026, 4, 13, 10, 0, 0) do
  record = HabitRecord.create!(record_date: Date.new(2026, 4, 12), ...)
  # created_at を昨日に強制変更（update_columns はバリデーション・タイムスタンプ更新をスキップ）
  record.update_columns(created_at: Time.zone.local(2026, 4, 12, 10, 0, 0))
  assert_not record.first_recorded_today?
end
```

<br>

**③ `before_validation` で UNIQUE 制約の前提データを自動セット**

<br>

`before_save` はバリデーション「後」に実行されるため、UNIQUE 制約のバリデーションに間に合わない。<br>
`year` / `week_number` のような「保存前に必ず値が必要なカラム」は `before_validation` でセットする。<br>
これにより fixtures を経由した場合でも `year` / `week_number` が正しくセットされる。

<br>

### 17. GROUP BY と ORDER BY の競合と `unscope(:order)` による解消（#C-1）

<br>

`scope :active` に `ORDER BY due_date ASC NULLS LAST` を含めると、<br>
`GROUP BY priority` と組み合わせたとき PostgreSQL が以下のエラーを発生させる。<br>
```
PG::GroupingError: column "tasks.due_date" must appear in the GROUP BY clause
```

<br>

Rails の scope はチェーンすると ORDER BY が引き継がれるため、<br>
`base_tasks.not_archived.group(:priority).count` は内部で<br>
`GROUP BY priority ORDER BY priority, due_date` という不正な SQL になる。<br>
`unscope(:order)` で ORDER BY 句だけを除去してから GROUP BY を実行することで解消できる。<br>
WHERE 句（`deleted_at IS NULL` など）は `unscope(:order)` の影響を受けないため安全。<br>
```ruby
# ❌ scope :active の ORDER BY が引き継がれて GroupingError
priority_counts = base_tasks.not_archived.group(:priority).count

# ✅ unscope(:order) で ORDER BY を除去してから GROUP BY
priority_counts = base_tasks.not_archived.unscope(:order).group(:priority).count
```

<br>

### 18. Tailwind の peer-checked だけでは「外れた状態」をリセットできない（#C-1）

<br>

Tailwind の `peer-checked` は「ラジオボタンが checked 状態のとき」スタイルを適用するが、<br>
「他のラジオボタンが選択されて checked が外れたとき」スタイルを自動的に元に戻さない。<br>
3つのカード（Must/Should/Could）で1つを選ぶと他の2つの青枠が残ってしまうバグになる。<br>
Stimulus コントローラーで全カードをリセット（非アクティブクラスを追加・アクティブクラスを削除）してから<br>
選択カードだけをアクティブにすることで排他選択を確実に実現できる。<br>
```javascript
updateCards() {
  this.labelTargets.forEach(label => {
    const radio = label.querySelector("input[type='radio']")
    const card  = label.querySelector("[data-priority-card-target='card']")
    const activeClasses   = (card.dataset.activeClass   || "").split(" ").filter(Boolean)
    const inactiveClasses = (card.dataset.inactiveClass || "").split(" ").filter(Boolean)

    if (radio.checked) {
      card.classList.add(...activeClasses)
      card.classList.remove(...inactiveClasses)
    } else {
      card.classList.remove(...activeClasses)  // ← これが重要。外れた状態をリセット
      card.classList.add(...inactiveClasses)
    }
  })
}
```

<br>

### 19. Turbo Stream でビューヘルパーをコントローラーから使うには include が必要（#C-2）

<br>

`dom_id` / `content_tag` はビューヘルパーメソッドであり、<br>
コントローラーからそのまま呼ぶと `NoMethodError: undefined method 'dom_id'` になる。<br>
```ruby
# ❌ include なし → NoMethodError
class TasksController < ApplicationController
  def toggle_complete
    turbo_stream.replace(dom_id(@task), ...)  # NoMethodError
  end
end

# ✅ 必要なヘルパーモジュールを include する
class TasksController < ApplicationController
  include ActionView::RecordIdentifier    # dom_id / dom_class を提供
  include ActionView::Helpers::TagHelper  # content_tag を提供
end
```

<br>

`ActionView::RecordIdentifier`: `dom_id(@task)` → `"task_1"` を生成する。<br>
Turbo Stream の `replace` / `remove` のターゲット ID として使用する。<br>
`ActionView::Helpers::TagHelper`: `content_tag(:p, "テキスト", class: "...")` を提供する。<br>
`archive_all_done` の空状態HTMLをコントローラー内で生成するために必要。

<br>

### 20. チェックボックスの即時更新は Stimulus fetch + Turbo.renderStreamMessage が最適（#C-2）

<br>

`form_with` + `data: { turbo: true }` でも Turbo Stream リクエストを送れるが、<br>
チェックボックスの `change` イベントに直接バインドする場合は Stimulus fetch の方が制御しやすい。<br>
fetch に `Accept: text/vnd.turbo-stream.html` を付けることでコントローラーの `format.turbo_stream` が発動し、<br>
返ってきた Turbo Stream HTML を `Turbo.renderStreamMessage(html)` で処理することで<br>
ページリロードなしに DOM を差し替えられる。<br>
fetch が失敗した場合は `checkbox.checked = !checkbox.checked` でロールバックして<br>
「操作が失敗した」ことをユーザーに視覚的に伝える設計にする。<br>
```javascript
// ✅ Stimulus fetch + Turbo.renderStreamMessage の組み合わせ
async toggle(event) {
  const checkbox = event.target
  const currentTab = new URLSearchParams(window.location.search).get("tab") || "all"
  try {
    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept":       "text/vnd.turbo-stream.html",
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body: `tab=${encodeURIComponent(currentTab)}`
    })
    if (response.ok) {
      Turbo.renderStreamMessage(await response.text())
    } else {
      checkbox.checked = !checkbox.checked  // ロールバック
    }
  } catch (error) {
    checkbox.checked = !checkbox.checked    // ロールバック
  }
}
```

<br>

### 21. Turbo Stream でタブをまたいだ「移動」を replace ではなく remove + prepend で実現する（#C-2）

<br>

`turbo_stream.replace(dom_id(@task), ...)` はその場でHTMLを差し替えるため「移動」にはならない。<br>
「done タブの行を消して active リストの先頭に追加する」には `remove` + `prepend` を組み合わせる。<br>
ただし移動先リストが現在表示されていない場合（別タブを見ているとき）は `prepend` 先が存在しないため<br>
Turbo がスキップする動作になる。これは意図した挙動として許容し、<br>
「タブを切り替えると復元されている」UX で対応する設計にした。<br>
```ruby
# done タブで完了を外すとき: done リストから消す
streams << turbo_stream.remove(dom_id(@task))
# → done タブから行が消える
# → 「全て」タブに切り替えると未完了タスクとして表示されている
```

<br>

### 22. update_all でN+1なしに一括更新する（#C-2）

<br>

`current_user.tasks.each { |t| t.archive! }` は件数分の UPDATE SQL を発行する（N+1更新）。<br>
`update_all` を使うと1回の SQL で全件更新でき、件数が増えてもパフォーマンスが劣化しない。<br>
注意点: `update_all` はコールバック・バリデーションをスキップする。<br>
今回は `status` カラムの変更のみのため問題ないが、コールバックに依存する処理がある場合は使えない。<br>
```ruby
# ❌ N+1更新: 件数分のUPDATE SQL が発行される
current_user.tasks.where(status: :done).each { |t| t.archive! }

# ✅ 1回のUPDATEで全件更新（N+1なし）
count = current_user.tasks
                    .active
                    .where(status: Task.statuses[:done])
                    .update_all(status: Task.statuses[:archived])
```

<br>

### 23. before_action の実行順序と明示的な優先制御（#C-3）

<br>

`before_action` は定義順に実行されるため、実行順序の制御が必要な場合は before_action を使わず<br>
アクション内で明示的に呼ぶ方が安全な場合がある。<br>
C-3 では `require_unlocked` を before_action に登録すると `ai_generated` チェックより先に実行されてしまい、<br>
「ロック中 + AI生成タスク削除」のとき期待する 403 ではなく 302 が返るバグになった。<br>
`destroy` アクション内で「①ai_generated チェック → ②ロックチェック → ③論理削除」の順を<br>
明示的に書くことで実行順序を保証できる。<br>
```ruby
# ❌ before_action の登録順では ai_generated チェックより先に require_unlocked が動く
before_action :set_task,         only: [:destroy]
before_action :require_unlocked, only: [:destroy]  # ← ai_generated チェックより先に実行

# ✅ destroy 内で明示的な順序制御
def destroy
  if @task.ai_generated?   # ① 最優先
    head :forbidden and return
  end
  return if require_unlocked  # ② 次
  @task.soft_delete            # ③ 実行
end
```

<br>

### 24. Turbo Stream 再描画と ERB の `#{}` の評価タイミング（#C-3）

<br>

Rails の ERB テンプレートは `<%= %>` でしか Ruby コードを評価しない。<br>
ただし `link_to` などの **Ruby メソッドの引数文字列内** では `#{}` が Ruby の文字列補間として機能する。<br>
問題は `class:` オプションの文字列が **複数行にまたがる** 場合に発生する。<br>
```ruby
# 通常ページ表示: 正常に評価される（ように見える）
class: "flex-shrink-0 ...
        #{ current_tab == 'all' ? 'bg-blue-600' : 'bg-white' }"
```
Turbo Stream による `replace` 再描画時は Rails がパーシャルを再レンダリングするが、<br>
複数行文字列内の `#{}` がそのまま HTML に出力されるバグが発生した。<br>
文字列結合（`"共通クラス " + (条件式)`）に変更することで確実に評価される。<br>
```ruby
# ✅ 文字列結合で確実に評価される
class: "flex-shrink-0 ... " + (current_tab == "all" ? "bg-blue-600 text-white" : "bg-white text-gray-600 ..."),
```

<br>

### 25. turbo:submit-end イベントでモーダルのクリーンアップをする設計（#C-3）

<br>

`button_to` で Turbo Stream フォームを送信すると、タスク行は削除されるがモーダル自体は<br>
`content_for :modals` で `</body>` 直前に配置されているため残り続ける。<br>
`document.body.style.overflow = "hidden"` も解除されずページ全体がスクロール不能になる問題があった。<br>
Turbo が提供する `turbo:submit-end` イベント（フォーム送信完了時に document に発火）を監視し、<br>
フォームの ID が一致した場合のみ `closeMenu()` を呼んでモーダルを閉じる設計にした。<br>
```javascript
// connect() でリスナーを登録する
this._boundSubmitEnd = this._handleSubmitEnd.bind(this)
document.addEventListener("turbo:submit-end", this._boundSubmitEnd)

// フォームID が自分のタスクのものなら閉じる
_handleSubmitEnd(event) {
  const form = event.detail?.formSubmission?.formElement
  if (!form) return
  if (form.id === `task-delete-form-${this.taskIdValue}` ||
      form.id === `task-delete-sheet-form-${this.taskIdValue}`) {
    this.closeMenu()
  }
}

// disconnect() で必ず削除する（メモリリーク防止）
document.removeEventListener("turbo:submit-end", this._boundSubmitEnd)
```

<br>

### 26. 削除フォームへの tab パラメータ動的注入（#C-3）

<br>

`_task_row.html.erb` はパーシャルのためレンダリング時点で現在のタブ（`?tab=must` 等）を持っていない。<br>
ERB 側でフォームに静的に `tab` を埋め込めないため、モーダルを開くとき（`openMenu()`）に<br>
URL の `URLSearchParams` から `tab` を取得して hidden input を動的に追加する方式を採用した。<br>
これにより `destroy` アクションで `params[:tab]` を正しく受け取れ、削除後もタブが維持される。<br>
```javascript
_injectTabToForms() {
  const tab = new URLSearchParams(window.location.search).get("tab")
  if (!tab) return

  [`task-delete-form-${this.taskIdValue}`, `task-delete-sheet-form-${this.taskIdValue}`]
    .forEach(formId => {
      const form = document.getElementById(formId)
      if (!form) return
      let input = form.querySelector("input[name='tab']")
      if (!input) {
        input = document.createElement("input")
        input.type = "hidden"
        input.name = "tab"
        form.appendChild(input)
      }
      input.value = tab
    })
}
```

<br>

### 27. redirect_to での 403 返却は status: オプションで明示する（#C-3）

<br>

`redirect_to` はデフォルトで HTTP 302 を返す。<br>
AI 生成タスクの削除を拒否する際に 403 を返したい場合は `status: :forbidden` を明示する必要がある。<br>
```ruby
# ❌ status 未指定 → 302 が返る（テストが expect: 403, actual: 302 で失敗する）
redirect_to tasks_path, alert: "AI生成タスクはこの方法では削除できません"

# ✅ status: :forbidden を明示 → 403 が返る
redirect_to tasks_path,
            alert:  "AI生成タスクはこの方法では削除できません",
            status: :forbidden
```

<br>

### 28. travel_to ブロック内のセッション喪失は再ログインで解決する（#C-3）

<br>

`ActionDispatch::IntegrationTest` では `travel_to` ブロック内でセッションクッキーが引き継がれない仕様がある。<br>
`setup` で行った `post login_path` が無効になり未ログイン扱いになるため<br>
`require_login` が先に動いて302が返り、期待するステータスが確認できない問題が発生する。<br>
```ruby
# ❌ travel_to ブロック内はセッションが切れる → require_login → 302 になる
test "AI生成タスクは削除できない（403）" do
  travel_to Time.zone.local(2026, 4, 9) do
    delete task_path(ai_task)
    assert_response :forbidden  # 実際は302が返るため失敗
  end
end

# ✅ travel_to ブロックを使わない（setup の時刻をそのまま使う）
test "AI生成タスクは削除できない（403）" do
  # setup で travel_to Time.zone.local(2026, 4, 8) 済みなので追加不要
  delete task_path(ai_task)
  assert_response :forbidden  # 正常に403が返る
end

# ✅ 月曜への時刻移動が必要なテストだけブロック内で再ログインする
test "ロック中は削除できない" do
  travel_to Time.zone.local(2026, 4, 13, 10, 0, 0) do
    # ブロック内で再ログインが必要
    post login_path, params: { session: { email: @user.email, password: "password" } }
    delete task_path(task)
    assert_response :redirect
  end
end
```

<br>

### 29. content_for は Turbo Stream の replace では yield に反映されない（#C-4）

<br>

`content_for :modals do...end` はサーバーサイドのフルレンダリング時にのみ動作する。<br>
Turbo Stream の `replace` でパーシャルを差し替えると、<br>
パーシャル内の `content_for :modals` は `yield :modals`（`</body>` 直前）に反映されず<br>
モーダル HTML が DOM から消えてしまう。<br>
これによって `document.getElementById("task-modal-${id}")` が `null` を返し、<br>
「⋯」ボタンを押してもモーダルが開かなくなる。<br>

<br>

**解決策:**<br>
モーダル HTML を独立したパーシャル（`_task_modal.html.erb`）に切り出し、<br>
`_task_row.html.erb` からインラインで `render` する設計に変更する。<br>
加えて `toggle_complete` の Turbo Stream レスポンスに<br>
`turbo_stream.replace("task-modal-#{@task.id}", partial: "tasks/task_modal", ...)` を追加することで<br>
タスク行の差し替え後もモーダル HTML が DOM に存在し続ける。<br>

<br>

```ruby
# ❌ content_for :modals → Turbo Stream replace 後に yield :modals から消える
<% content_for :modals do %>
  ...
<% end %>

# ✅ パーシャルとしてインライン出力 → DOM に直接残り続ける
<%= render "tasks/task_modal", task: task %>

# コントローラーで toggle 後にモーダルを再注入する
streams << turbo_stream.replace(
  "task-modal-#{@task.id}",
  partial: "tasks/task_modal",
  locals:  { task: @task }
)
```

<br>

### 30. 同一 id が2箇所存在すると Turbo の DOM 整合性が崩れる（#C-4）

<br>

HTML の仕様では同一ページに同じ `id` を持つ要素は1つだけでなければならない。<br>
重複した `id` が存在すると `document.getElementById()` が最初に見つかった要素だけを返し、<br>
Turbo Stream の `prepend("flash-area", ...)` が意図しない要素を操作する場合がある。<br>
`application.html.erb` に `id="flash-area"` が `<main>` の外と中に2箇所あった場合、<br>
Turbo のイベント処理で DOM の整合性が崩れ、モーダルの表示等に影響する。<br>
`id` は必ずページ全体で一意にすること。重複を発見したら一方を削除するか別の `id` を付ける。<br>

<br>

```html

    の外 -->

  <%= yield %>
     の中 -->




  <%= yield %>
  

```

<br>

### 31. タスクスナップショットは `on_delete: :nullify` で「参照」と「記録」を分離する（#C-4）

<br>

習慣スナップショット（`WeeklyReflectionHabitSummary`）と同じ「スナップショット設計」を採用する。<br>
`task_id` は `on_delete: :nullify`（タスク削除時に NULL になる）とし、<br>
`title` / `priority` / `was_completed` 等のスナップショットカラムは保持する。<br>
これによりタスクを削除しても振り返り詳細ページが正確に表示され続ける。<br>

<br>

| 外部キー設計 | 動作 | 採用理由 |
|:---|:---|:---|
| `on_delete: :cascade` | タスク削除時にスナップショットも削除 | ❌ 振り返り詳細が壊れる |
| `on_delete: :nullify` | タスク削除時は task_id を NULL に更新 | ✅ スナップショット（title等）は残り続ける |

<br>

`was_completed` フラグが「スナップショット設計の核心」であり、<br>
`task.done? || task.archived?` を振り返り完了時点での完了状態として記録する。<br>
後からタスクの状態が変わっても振り返り時点の事実が保たれる。

<br>

### 32. GoodJob の wait_until でアラームを指定時刻にスケジュールする（#C-5）

<br>

`TaskAlarmJob.set(wait_until: notify_at).perform_later(task.id)` と書くことで、<br>
`notify_at`（= `scheduled_at - alarm_minutes_before 分`）になったときにジョブが自動実行される。<br>
GoodJob は `good_jobs` テーブルの `scheduled_at` カラムを参照し、<br>
ポーリング（30秒ごと）または PostgreSQL の LISTEN/NOTIFY でその時刻を検知して実行する。<br>

<br>

```ruby
# スケジュール計算（UTC で統一）
minutes_before = task.alarm_minutes_before.to_i
notify_at      = task.scheduled_at - minutes_before.minutes

# 未来の日時のみスケジュール（過去日時は GoodJob が即時実行してしまうため除外）
return unless notify_at > Time.current

TaskAlarmJob.set(wait_until: notify_at).perform_later(task.id)
```

<br>

### 33. update 時のジョブ再スケジュールは JSONB @> 演算子で安全に削除する（#C-5）

<br>

タスクの `scheduled_at` を変更した場合、古いジョブをそのまま残すと<br>
「変更前の時刻に通知が届く」「二重通知になる」事故が起きる。<br>
update 時に既存ジョブを削除してから新しいジョブを登録することで解消する。<br>

<br>

**なぜ LIKE 検索（`LIKE "%#{task.id}%"`）を使わないのか:**

<br>

| 方式 | 問題点 |
|:---|:---|
| `LIKE "%1%"` | task.id=1 が id=10, 100, 1000 にもマッチして別タスクのジョブを誤削除 |
| JSONB `@>` 演算子 | `{"arguments":[1]}` を厳密に一致させるため誤削除ゼロ・インデックスも有効 |

<br>

```ruby
GoodJob::Job
  .where(job_class: "TaskAlarmJob")
  .where(finished_at: nil)
  .where("serialized_params @> ?", { arguments: [task.id] }.to_json)
  .delete_all
```

<br>

### 34. deliver_now vs deliver_later の使い分け（#C-5）

<br>

`TaskAlarmJob` はすでに GoodJob のバックグラウンドジョブとして実行されているため、<br>
その中でメールを `deliver_later` すると「ジョブの中でさらにジョブを積む」二重非同期になる。<br>
ジョブ内ではメールを同期送信（`deliver_now`）するのが正しい設計。<br>

<br>

| 呼び出し場所 | 使うメソッド | 理由 |
|:---|:---|:---|
| コントローラー・モデル | `deliver_later` | バックグラウンドで非同期送信（リクエストを止めない） |
| GoodJob ジョブ内 | `deliver_now` | すでにバックグラウンド実行中のため二重非同期は不要 |

<br>

### 35. フィクスチャの自動生成は NOT NULL 違反の温床（#C-5）

<br>

`bin/rails generate model NotificationLog --skip-migration` を実行すると<br>
`--skip-migration` を指定していても `test/fixtures/notification_logs.yml` が自動生成される。<br>
`one: {}` は全カラムが nil のレコードを意味するため、<br>
`user_id` の NOT NULL 制約に違反してテスト全体がクラッシュする。<br>
setup で動的にデータを作成する方式のテストではフィクスチャファイル自体が不要なため、<br>
モデル生成後は必ずフィクスチャファイルの内容を確認して不要なら削除すること。<br>

<br>

```bash
# 確認
docker compose exec web cat test/fixtures/notification_logs.yml

# 不要なら削除
rm test/fixtures/notification_logs.yml
docker compose exec web bin/rails db:test:prepare
```

<br>

### 36. session によるアクセス制御と URL パラメータ改ざん対策（#C-7）

<br>

「AI提案モーダルを経由したかどうか」をサーバー側で証明する手段が必要だった。<br>
URL パラメータ（`?from=ai_modal` 等）はユーザーが直接書き換えられるため不適切。<br>
Rails の session は暗号化された Cookie として保存されるため改ざんできない。<br>
`ai_edit`（GET）で `session[:ai_context_task_id] = @task.id` を設定し、<br>
`ai_update`（PATCH）で `session[:ai_context_task_id] == @task.id` を照合する設計にした。<br>
task_id まで照合する理由: 「タスクAの ai_edit → タスクBの ai_update」という<br>
不正なクロスアクセスも確実に弾くため。

<br>

### 37. form_with の Turbo 干渉は data: { turbo: false } で解消する（#C-7）

<br>

Rails 7 の `form_with` はデフォルトで Turbo Drive が処理する。<br>
`ai_update` アクションが通常の HTML リダイレクト（302）を返しても<br>
Turbo が `TURBO_STREAM` 形式でリクエストを送るため、<br>
コントローラーが `ActionController::ParameterMissing` を発生させてフォームが動かなかった。<br>
`data: { turbo: false }` を指定することで Turbo を無効にし、<br>
従来の HTML フォーム送信（`<form method="post">`）として動作させることで解決した。<br>
また `form_with` に `model: @task` を渡すことで `f.text_field :title` が<br>
`name="task[title]"` を自動生成し、`params[:task][:title]` としてサーバーで受け取れる。

<br>

### 38. 単数形リソース（resource）では form_with の url: と method: を明示する（#D-1）

<br>

`resources :user_purposes`（複数形）の場合、`form_with model: @user_purpose`（新規）は<br>
Rails が自動で `user_purposes_path`（POST）を解決できる。<br>
しかし `resource :user_purpose`（単数形）の場合、Rails は `user_purposes_path` を探しに行くが<br>
単数形リソースでは `user_purposes_path` が存在しないため `NoMethodError` が発生する。<br>
単数形リソースでは `url:` と `method:` を必ず明示することで正しいルートに送信できる。<br>
```ruby
# ❌ 単数形リソースでは user_purposes_path が存在しないため NoMethodError
<%= form_with model: @user_purpose, local: true do |f| %>

# ✅ url: と method: を明示する
<%= form_with model: @user_purpose,
              url: user_purpose_path,
              method: :post,
              local: true do |f| %>
```
レビューコメントで「`url:` を削除すべき」という指摘があっても、<br>
単数形リソースには適用できない。`url:` 省略が有効なのは複数形リソースのみ。

<br>

### 39. before_save の update_all で旧バージョンを一括無効化する（#D-1）

<br>

PMVV のバージョン管理では「常に is_active=true が1件のみ存在する」ことを保証する必要がある。<br>
`before_save` で `user.user_purposes.where(is_active: true).update_all(is_active: false)` を実行することで<br>
新しいレコードを保存する直前に全旧バージョンを一括で無効化できる。<br>
`update_all` を使う理由: 1回の SQL UPDATE で全件を処理するため N+1 を防止できる。<br>
`each { |r| r.update! }` だと旧バージョンの件数分の UPDATE が発生する。<br>
```ruby
def deactivate_previous_versions
  scope = user.user_purposes.where(is_active: true)
  scope = scope.where.not(id: id) if persisted?  # 更新時は自分自身を除外
  scope.update_all(is_active: false)
end
```
`persisted?` で新規作成（id が nil）か更新かを区別する。<br>
新規作成時は自身の id がまだないため除外不要。更新時は自分を除外しないと自分も無効化される。

<br>

### 40. before_validation on: :create でバージョン番号を自動採番する（#D-1）

<br>

`validates :version, presence: true` があるため、`before_save` では遅すぎる。<br>
`before_validation` で事前に version をセットしないとバリデーションエラーになる。<br>
`maximum(:version).to_i` は「最大バージョンが存在しない場合（初回）」に `nil` を返すため、<br>
`.to_i` を付けることで `nil.to_i = 0` → `0 + 1 = 1` という安全な初期値設定ができる。<br>
```ruby
before_validation :set_version, on: :create  # 新規作成時のみ実行

def set_version
  max_version = user.user_purposes.maximum(:version).to_i  # nil → 0
  self.version = max_version + 1  # 初回は 1、2回目は 2...
end
```

<br>

### 41. update アクションで「新規作成」することで履歴を保持するバージョン管理（#D-1）

<br>

通常の CRUD では `update` アクションで既存レコードを変更するが、<br>
PMVV のバージョン管理では `update` でも `current_user.user_purposes.build(...)` で<br>
新しいレコードを作成する設計にする。<br>
これにより古いバージョンの PMVV は `is_active=false` として履歴に残り続け、<br>
「このバージョンで AI 分析した」という記録が正確に保たれる。<br>
`before_save` コールバックが新規レコード保存前に旧バージョンを自動的に無効化するため、<br>
コントローラー側では `build` して `save` するだけでよい。<br>
```ruby
# update アクションでも build（= 新規作成）する
def update
  @user_purpose = current_user.user_purposes.build(user_purpose_params)
  @user_purpose.analysis_state = :pending
  if @user_purpose.save
    # before_save :deactivate_previous_versions が旧バージョンを自動無効化する
    PurposeAnalysisJob.perform_later(@user_purpose.id)
    redirect_to user_purpose_path, notice: "目標を更新しました。AIによる再分析を開始しています..."
  else
    render :edit, status: :unprocessable_entity
  end
end
```

<br>

### 42. _voice_field.html.erb パーシャルで5フィールドの DRY 化（#D-1）

<br>

PMVV の5フィールド（Purpose/Mission/Vision/Value/Current）はいずれも<br>
「ラベル + 音声入力ボタン + テキストエリア」という同じ構造を持つ。<br>
これを5回コピペすると変更時に5箇所を同時に修正する必要があり、<br>
レビューコメントで指摘されたように DRY 原則に反する。<br>
`_voice_field.html.erb` パーシャルを作成し、`locals:` で差異部分を受け取ることで<br>
ビューのコード量を大幅に削減できる。<br>
```erb
<%# 呼び出し側（new.html.erb / edit.html.erb） %>
<%= render "user_purposes/voice_field",
      f: f,
      field: :purpose,
      label_text: "Purpose",
      hint_text: "人生で一番大切にしていることは？",
      placeholder: "...",
      example: "例: ...",
      rows: 3,
      maxlength: 1000 %>
```
`rows ||= 3` / `maxlength ||= 1000` でデフォルト値を設定することで<br>
value フィールドの `rows: 2` / `maxlength: 500` のような例外にも対応できる。

<br>

### 43. Google 公式 Ruby SDK が存在しない場合は REST API を faraday で直接呼ぶ（#D-2）

<br>

2026年4月時点で Google の Gemini API に対応した公式 Ruby SDK は存在しない。<br>
サードパーティ gem（`google-generative-ai` 等）は RubyGems に存在せずビルドが失敗する。<br>
faraday で Gemini の REST API エンドポイントを直接呼ぶ方式が最も安定している。

<br>

```
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}
```

<br>

認証は Authorization ヘッダーではなくクエリパラメータ `?key=` で行う点が OpenAI と異なる。<br>
レスポンス構造: `candidates[0].content.parts[0].text` を `dig` で安全に取得する。

<br>

### 44. Gemini の `limit: 0` エラーはモデル変更で解消する（#D-2）

<br>

2025年12月の Google のクォータ変更以降、`gemini-2.0-flash` の無料枠が一部プロジェクトで `limit: 0` になる。<br>
Google AI Studio の「お支払い情報を設定」リンクが表示されている場合、<br>
そのプロジェクトの無料枠設定が正常に機能していないことを示す。<br>
新しいプロジェクトを作成し直しても解消しない場合は、モデルを `gemini-2.5-flash` に変更することで解消できる。<br>
2026年4月時点の無料枠対象モデルは Gemini 2.5 系（Flash・Flash-Lite・Pro）が中心。

<br>

### 45. ActiveRecord の予約語はカラム名に使ってはいけない（#D-2）

<br>

`model_name` は ActiveRecord が内部で使用している予約済みメソッド名。<br>
テーブルに `model_name` カラムがあると `ActiveRecord::DangerousAttributeError` が発生し、<br>
モデルが全く使えなくなる。<br>
AI モデル名を保存するカラムは `ai_model_name` のように文脈を含む名前にすることで回避できる。<br>
他の主な予約語: `type`（STI用）/ `hash`（Rubyメソッド）/ `class`（Rubyキーワード）/ `id`（主キー）

<br>

### 46. AiClient の戻り値は Hash 形式にして使用モデルを正確に記録する（#D-2）

<br>

AI クライアントが文字列のみを返す設計だと「実際にどのモデルで生成したか」を<br>
呼び出し元（Job）が知る方法がなく、Rails.cache のフラグで推測するしかなくなる。<br>
`{ text: "レスポンステキスト", model: "gemini-2.5-flash" }` の Hash 形式で返すことで<br>
Gemini が使われたのか Groq フォールバックが使われたのかを正確に `ai_model_name` に記録できる。

<br>

```ruby
# ❌ String のみ → どのモデルを使ったか Job 側で知る方法がない
return response_text

# ✅ Hash 形式 → 使用モデルを正確に伝達できる
{ text: response_text, model: GEMINI_MODEL }
```

<br>

### 47. JSON パースは必ず正規表現で `{ }` の範囲を抽出してから行う（#D-2）

<br>

AI は高確率で JSON の前後に文章を付けて返す。<br>
「はい、分析結果です：\n{...}\n\n以上です。」のようなパターンが頻繁に発生する。<br>
コードブロック除去（`gsub(/```json\n?/`）だけでは不十分で、<br>
正規表現 `/\{.*\}/m`（`m` フラグで改行をまたぐ）で `{ }` の範囲を抽出することで<br>
前後の文章があっても JSON 部分だけを確実に取り出せる。

<br>

```ruby
# ① コードブロック除去
text = raw_response.gsub(/```json\n?/, "").gsub(/```\n?/, "")

# ② { } 範囲の抽出（前後の文章を切り捨てる）
json_str = text[/\{.*\}/m]
return nil if json_str.blank?

# ③ パース
parsed = JSON.parse(json_str, symbolize_names: true)
```

<br>

### 48. Minitest::Mock で「呼ばれたか」まで検証する（#D-2）

<br>

`Object.new` に `define_singleton_method` で戻り値を返すだけのスタブは<br>
「メソッドが実際に呼ばれたか」を検証しない。ジョブが途中でリターンしても気づかないテストになる。<br>
`Minitest::Mock` の `expect` + `verify` を使うことで<br>
「指定した引数でメソッドが呼ばれた」ことまで検証できる。

<br>

```ruby
# ✅ Minitest::Mock で「呼ばれたか・引数は正しいか」まで検証する
def stub_ai_client(return_value)
  mock = Minitest::Mock.new
  mock.expect(:analyze, return_value, [String])  # String 引数で呼ばれたら return_value を返す
  AiClient.stub(:new, mock) do
    yield
  end
  mock.verify  # 呼ばれなければ MockExpectationError でテスト失敗
end
```

<br>

### 49. retry_on は通信エラーのみに絞る（#D-2）

<br>

`retry_on StandardError` で全エラーをリトライすると<br>
JSON パースエラー・ロジックエラーも無駄にリトライされる。<br>
通信エラー（`Faraday::Error` / `Timeout::Error`）のみをリトライ対象にすることで<br>
「リトライしても意味のないエラー」でリソースを無駄にしない設計になる。

<br>

```ruby
# ❌ StandardError → JSON エラーもロジックエラーもリトライ（無駄）
retry_on StandardError, wait: :exponentially_longer, attempts: 3

# ✅ 通信エラーのみリトライ
retry_on Faraday::Error,  wait: :exponentially_longer, attempts: 3
retry_on Timeout::Error,  wait: :exponentially_longer, attempts: 3
```

<br>

### 50. Turbo Stream の broadcast は transaction の外で reload してから行う（#D-2）

<br>

transaction 内で broadcast すると、DB のコミットが完了する前に UI が更新されてしまう。<br>
「完了」表示になったのに DB にはまだ `analyzing` が残っている状態が一瞬発生しうる。<br>
transaction が完了してから `user_purpose.reload` で最新の DB 状態を取得し、<br>
その状態を broadcast することで「UI と DB の状態が常に一致する」ことを保証できる。

<br>

### 51. solid_cable で開発環境でも Turbo Stream を確実に届ける（#D-3）

<br>

`config/cable.yml` の `development: adapter: async` はメモリ内通信のみ対応しており、<br>
GoodJob のバックグラウンドスレッドからのブロードキャストがブラウザに届かない制限がある。<br>
`solid_cable` アダプターに変更することで PostgreSQL をブローカーとして使い、<br>
プロセスをまたいでも通知を確実に届けられるようになる。<br>
Redis 不要・既存の PostgreSQL をそのまま使えるため Render 無料プランとも相性が良い。

<br>

```yaml
# ✅ solid_cable: DB をブローカーとして使いプロセス間通信を実現
development:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

<br>

`solid_cable` は `database.yml` に `cable:` 接続の定義が必要。<br>
`migrations_paths: db/cable_migrate` で通常のマイグレーションと分けて管理する。

<br>

### 52. solid_cable 3.0.12 が要求する channel_hash カラムの追加（#D-3）

<br>

`solid_cable:install` で生成されるマイグレーションには `channel_hash` カラムが含まれていないが、<br>
`solid_cable 3.0.12` は内部で `channel_hash` カラムを使ってチャンネルを高速検索する。<br>
カラムが存在しないと `ActiveModel::UnknownAttributeError: unknown attribute 'channel_hash'` が発生し<br>
ブロードキャストが失敗する。<br>
別途マイグレーションで `channel_hash bigint` カラムと対応インデックスを追加することで解消できる。

<br>

```ruby
def change
  add_column :solid_cable_messages, :channel_hash, :bigint, null: false, default: 0
  add_index  :solid_cable_messages, :channel_hash
  reversible do |dir|
    dir.up do
      execute "UPDATE solid_cable_messages SET channel_hash = hashtext(channel)"
    end
  end
end
```

<br>

### 53. broadcast_state_update に ai_analysis を渡さないとパーシャルが失敗する（#D-3）

<br>

`_analysis_status_banner.html.erb` パーシャルは completed 状態のときに<br>
`ai_analysis` ローカル変数を参照して「結果を見る →」リンクを表示する設計になっている。<br>
`broadcast_state_update` で `locals:` に `ai_analysis:` を渡さないと<br>
`undefined local variable or method 'ai_analysis'` エラーが発生してブロードキャストが失敗する。<br>
ジョブは `rescue => e` で失敗を無視するため、エラーログに埋もれて気づきにくいバグになる。

<br>

```ruby
def broadcast_state_update(user_purpose)
  # ai_analysis を取得して locals に必ず渡す
  ai_analysis = AiAnalysis.where(
    user_purpose_id: user_purpose.id,
    is_latest:       true,
    analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
  ).first

  Turbo::StreamsChannel.broadcast_replace_to(
    "user_purpose_#{user_purpose.id}",
    target:  "analysis_status_banner",
    partial: "user_purposes/analysis_status_banner",
    locals:  { user_purpose: user_purpose, ai_analysis: ai_analysis }
  )
end
```

<br>

### 54. インデックス番号で提案をPOSTするセキュリティ設計（#D-3）

<br>

AI 提案の登録フォームで提案のタイトルをそのままパラメータとして送ると、<br>
攻撃者がブラウザのデベロッパーツールでフォームを書き換えて任意の内容を送信できる。<br>
代わりにチェックボックスの value にインデックス番号（整数）を使い、<br>
サーバー側で `@ai_analysis.actions_json` から該当インデックスの提案を取り出す設計にすることで<br>
DB に保存される内容が必ず AI が生成したものになる。

<br>

```erb
<%# インデックス番号を value にする %>
<%= check_box_tag "habit_indices[]", idx, false, id: "habit_#{idx}" %>

<%# サーバー側: インデックスから提案を安全に取り出す %>
selected_habit_indices = Array(params[:habit_indices]).map(&:to_i)
selected_habit_indices.each do |idx|
  proposal = habit_proposals[idx]   # AI 分析結果から取り出す
  next unless proposal              # 範囲外インデックスは安全にスキップ
  current_user.habits.create!(...)
end
```

<br>

### 55. UserSetting は after_create で自動作成する（#D-4）

<br>

`UserSetting` がないユーザーに対してジョブを実行すると、<br>
`enqueue_analysis_job_if_eligible` の nil ガードで早期リターンし、ジョブがエンキューされない。<br>
`User` モデルの `after_create` コールバックで `UserSetting.create!(user: self)` を呼ぶことで<br>
ユーザー登録時に必ず `UserSetting` が作成される設計にする。<br>
`rescue ActiveRecord::RecordInvalid` でログを残しつつユーザー登録自体は成功させる。

<br>

**テストへの影響:**<br>
`after_create` 追加後は `User.create!` で `UserSetting` が自動作成されるため、<br>
テストの `setup` で `UserSetting.create!` を呼ぶと UNIQUE 制約違反になる。<br>
既存テストは `UserSetting.create!` を削除し、`user.user_setting` で参照する形に変更する。<br>
設定値が異なる場合は `user.user_setting.update!` で上書きする。<br>

```ruby
# ❌ after_create 追加後は重複エラー
@user_setting = UserSetting.create!(user: @user, ai_analysis_count: 0, ...)

# ✅ after_create で作成済みのものを参照・必要なら update! で上書き
@user_setting = @user.user_setting
@user_setting.update!(notification_enabled: true, ...)
```

<br>

### 56. update_all でカウントを原子的にインクリメントする（#D-4）

<br>

`increment!` は Ruby 側で現在値を読んで +1 する3ステップ操作のため、<br>
複数のジョブが同時実行されたとき「両方が同じ値を読んで +1 する」競合が発生する。<br>
`update_all("count = count + 1")` は DB 側で計算するため原子的操作（atomic）になる。<br>
AI 分析は非同期ジョブで実行されるため、特に並行実行時の競合対策が重要になる。<br>

```ruby
# ❌ increment! → Ruby 側で計算（競合が発生する）
user_setting.increment!(:ai_analysis_count)

# ✅ update_all → DB 側で計算（原子的操作・競合しない）
UserSetting.where(id: user_setting.id)
           .update_all("ai_analysis_count = ai_analysis_count + 1")
```

<br>

### 57. result.nil? 時は raise ではなく return する（#D-4）

<br>

`AiClient#analyze` が nil を返すのは「Gemini + Groq の両方でリトライも含め全て失敗した」最終結果。<br>
この段階で `raise` すると `retry_on` の対象外の例外として即 discard され<br>
GoodJob のリトライ機能が活用できなくなる。<br>
`return` してジョブを正常終了させ、次回の振り返り完了時に再挑戦できる設計にする。<br>

```ruby
# ❌ raise → retry_on 対象外の例外で即 discard される
raise "AI API Response is nil" if result.nil?

# ✅ return → ログだけ残して正常終了
if result.nil?
  Rails.logger.error "[WeeklyReflectionAnalysisJob] 全 AI プロバイダが失敗しました"
  return
end
```

<br>

### 58. include ActiveJob::TestHelper を明示しないと assert_enqueued_with が使えない（#D-4）

<br>

`assert_enqueued_with` / `assert_no_enqueued_jobs` は `ActionDispatch::IntegrationTest` には<br>
自動で include されるが、`ActiveSupport::TestCase` では明示的な include が必要。<br>
`NoMethodError: undefined method 'assert_enqueued_with'` が出た場合はこれが原因。<br>

```ruby
class WeeklyReflectionCompleteServiceTest < ActiveSupport::TestCase
  # ✅ 明示的に include する
  include ActiveJob::TestHelper
  ...
end
```

<br>

### 59. discard_on は GoodJob 4.x では perform_now でも機能する（#D-4）

<br>

GoodJob 4.x では `discard_on ActiveRecord::RecordNotFound` が `perform_now` でも機能し、<br>
例外は外に伝播せずジョブが静かに破棄される。<br>
テストでは「例外が発生しないこと」を `assert_nothing_raised` で確認する。<br>

```ruby
# ❌ perform_now で例外が来ると期待するが GoodJob 4.x では来ない
assert_raises ActiveRecord::RecordNotFound do
  WeeklyReflectionAnalysisJob.perform_now(999_999_999)
end

# ✅ 例外が外に出ないことを確認する
assert_nothing_raised do
  WeeklyReflectionAnalysisJob.perform_now(999_999_999)
end
```

<br>

### 60. 危機介入モーダルのリダイレクト先は「振り返り完了後の遷移先」に合わせる（#D-5）

<br>

振り返り完了後は `completed_at` がセットされるため、<br>
`/weekly_reflections/new` にリダイレクトすると `new` アクションの冒頭ガード<br>
（`completed? == true` → `/weekly_reflections` に強制リダイレクト）に引っかかる。<br>
結果として flash が2回のリダイレクトをまたいで届かず、モーダルが表示されない。<br>
crisis 時のリダイレクト先は「振り返り完了後に自然に遷移するページ」に合わせること。

<br>

```
通常完了時: /weekly_reflections（一覧）または /dashboard（ロック解除時）
crisis 時:  同じリダイレクト先 + flash[:crisis] = true でモーダルをトリガー
```

<br>

### 61. `flash.each` でカスタムフラグが「true」として表示されるバグ（#D-5）

<br>

`flash[:crisis] = true` を設定すると、`application.html.erb` の `flash.each` が<br>
`"crisis" => true` を拾い、「true」という文字列がトースト通知として表示されるバグが発生する。<br>
`flash.each` に `next if message_type.to_s == "crisis"` を追加することで<br>
内部フラグとして使う flash キーを通知表示の対象から除外できる。<br>
`ActionDispatch::Flash::FlashHash` には `except` メソッドが存在しないため、<br>
`flash.except("crisis").each` とは書けない点に注意すること。

<br>

```ruby
# ❌ FlashHash には except メソッドがない → NoMethodError
flash.except("crisis").each do |message_type, message|

# ✅ each の中で next でスキップする
flash.each do |message_type, message|
  next if message_type.to_s == "crisis"  # ← 内部フラグをスキップ
  ...
end
```

<br>

### 62. CSS の `clamp()` でモーダルのフォントサイズをレスポンシブ対応する（#D-5）

<br>

スマホ（375px）でモーダル内の電話番号が折り返されないようにするには<br>
`font-size: clamp(最小値, 推奨値, 最大値)` を使うことで画面幅に応じた自動調整ができる。<br>
`white-space: nowrap` + `flex-shrink: 0` を電話番号に適用することで折り返しを完全に防ぎ、<br>
左側の窓口名（`flex: 1 1 auto; min-width: 0`）が縮んで電話番号を守るレイアウトにする。

<br>

```css
/* 電話番号: 折り返し禁止・縮小禁止 */
font-size: clamp(14px, 3.8vw, 18px);
white-space: nowrap;
flex-shrink: 0;

/* 窓口名: 画面幅に合わせて縮小可 */
flex: 1 1 auto;
min-width: 0;
```

<br>

### 63. `render :new` + `flash.now` で入力内容を保持したままモーダルを表示する（#D-6）

<br>

上限チェックで `redirect_to` を使うとユーザーが書いた振り返り内容が全て消える。<br>
`render :new` を使うことで `@weekly_reflection` のインスタンス変数が保持され、<br>
フォームの入力済み内容がそのまま画面に残った状態でモーダルだけが浮かび上がる UX を実現できる。<br>
`flash.now` を使う理由は `flash`（`flash.now` なし）だと次のリクエストでもフラグが残り<br>
モーダルが二重起動してしまうためである。

<br>

```ruby
# create アクション内
@weekly_reflection.assign_attributes(weekly_reflection_params)  # 先に値をセット

if ai_limit_exceeded?
  flash.now[:ai_limit] = true          # このリクエスト内だけ有効
  setup_new_form_variables             # new ビューに必要な変数を準備
  render :new, status: :unprocessable_entity  # 入力内容が保持される
  return
end
```

<br>

### 64. モーダル専用フォームで hidden フィールドに値をコピーして送信する（#D-6）

<br>

`render :new` で描画されたフォームは action 属性がページ URL（相対パス）になるため、<br>
JavaScript でフォームの action を書き換える方式では 404/422 エラーが発生した。<br>
モーダル内に `complete_without_ai` 専用の独立したフォームを配置し、<br>
Stimulus の `submitWithoutAi()` でメインフォームの各フィールドの値を<br>
専用フォームの hidden フィールドにコピーしてから送信する方式が安定している。

<br>

```javascript
submitWithoutAi(event) {
  event.preventDefault()
  const fields = ["reflection_comment", "direct_reason", "background_situation", "next_action"]
  fields.forEach(fieldName => {
    const source = document.querySelector(`textarea[name="weekly_reflection[${fieldName}]"]`)
    const target = this.submitFormTarget.querySelector(`input[data-field="${fieldName}"]`)
    if (source && target) target.value = source.value
  })
  this.submitFormTarget.submit()  // 入力値コピー後に専用フォームを送信
}
```

<br>

### 65. `travel_to` はリクエスト内スレッドに引き継がれないため locked? のテストは DB 状態で検証する（#D-6）

<br>

`ActionDispatch::IntegrationTest` の `travel_to` による時刻固定は<br>
HTTPリクエストを処理する別スレッドに引き継がれないため、<br>
`locked?` のようなリクエスト内で呼ばれる時刻依存メソッドはテスト環境でリアル時間で動作する。<br>
「ロック状態でのリダイレクト先が `dashboard_path` になる」のような時刻依存の挙動は<br>
テストから正確に検証できない。<br>
代わりに「振り返りが保存されたか」「flash にメッセージがあるか」などの DB 状態で検証することで<br>
時刻に依存しない安定したテストになる。

<br>

### 66. スキップボタンは form_with の外に配置しないと form バリデーションが発火する（#D-7）

<br>

`button_to` は `<form method="post">` を生成するため、<br>
メインフォーム（`form_with`）の内側に置くと HTML の仕様違反（form の入れ子）になる。<br>
ブラウザはスキップボタンクリック時にメインフォームの submit を先に処理し、<br>
バリデーション（`at_least_one_field_present`）が発火して「少なくとも1つ入力してください」エラーになる。<br>
`<% end %>` の後（フォーム外）に `button_to` を配置することで解決する。<br>

```ruby
# ❌ form_with の内側 → メインフォームのバリデーションが発火
<%= form_with ... do |f| %>
  ...
  <%= button_to "スキップ", skip_path, method: :post %>  # ← バリデーションエラー
<% end %>

# ✅ form_with の外側 → 独立した POST になり正常動作
<%= form_with ... do |f| %>
  ...
<% end %>
<%= button_to "スキップ", skip_path, method: :post %>   # ← フォーム外
```

<br>

### 67. turbo_stream_from のチャンネル名は broadcast 側と完全一致させる（#D-7）

<br>

`PurposeAnalysisJob` が `broadcast_replace_to "user_purpose_#{user_purpose.id}"` と送信するとき、<br>
ビュー側が `turbo_stream_from "user_purpose_#{current_user.id}"` だとチャンネル名が一致せず<br>
ブラウザに通知が届かない。<br>
`current_user.id`（User の主キー）と `user_purpose.id`（UserPurpose の主キー）は異なる整数のため<br>
必ず同じ変数を使うこと。

```ruby
# ❌ current_user.id → User の ID（例: 5）
<%= turbo_stream_from "user_purpose_#{current_user.id}" %>

# ✅ @current_purpose.id → UserPurpose の ID（例: 46）
<%= turbo_stream_from "user_purpose_#{@current_purpose.id}" %>
```

<br>

### 68. set_habit の rescue が rescue_from より優先される（#D-8）

<br>

`ApplicationController` に `rescue_from ActiveRecord::RecordNotFound, with: :render_404` があっても、<br>
コントローラー内の `rescue` ブロックが先にキャッチするため404にはならない。<br>
`set_habit` の `rescue ActiveRecord::RecordNotFound → redirect_to habits_path` という実装では<br>
他ユーザーの習慣へのアクセスは404ではなく302リダイレクトになる。<br>
テストで `assert_response :not_found` が通らない場合は、この優先順位を確認すること。<br>
```ruby
# set_habit の rescue が rescue_from より先に動く
def set_habit
  @habit = current_user.habits.where(deleted_at: nil).find(params[:id])
rescue ActiveRecord::RecordNotFound
  flash[:alert] = "習慣が見つかりませんでした"
  redirect_to habits_path  # ← rescue_from の render_404 より先にここが実行される
end
```

<br>

### 69. input_snapshot バリデーションは「キーの存在」のみチェックする（#D-9）

<br>

`jsonb` カラムは自由形式のため、必須キーが欠落していてもDBに保存できてしまう。<br>
`valid?` + `errors.add` によるカスタムバリデーションで保存前にキーの存在を強制チェックする。<br>

<br>

**なぜ値の nil・空文字を許容するか:**<br>
`UserPurpose` の各フィールドは `allow_blank: true` の設計のため、<br>
未入力の場合に nil が保存される。`build_input_snapshot` はその nil をそのまま `input_snapshot` に含める。<br>
18番画面では `.presence || "未入力"` で nil を安全に表示できるため、<br>
バリデーションは「キーが存在するかどうか」のみで十分。<br>
`present?` まで要求すると、未入力フィールドを持つ UserPurpose の分析が全て失敗する設計になってしまう。<br>

```ruby
# ✅ キーの存在のみチェック（値の nil は許容）
missing_keys = required_keys.reject do |key|
  snapshot.key?(key)  # present? ではなく key? のみ
end
```

<br>

**2層バリデーション設計:**<br>

| 層 | 実装 | 役割 |
|:---|:---|:---|
| Model 層 | `validate :input_snapshot_schema_valid` | DB保存前の最終防波堤。`with_indifferent_access` でキー型の差を吸収 |
| Job 層 | `AiAnalysis.new(...).valid?` で事前チェック | `create!` 前に確実に検出。失敗時は `handle_failure` → `failed` 状態に遷移 |

<br>

**テストの落とし穴 - nil 値は「エラーになる」ではなく「通過する」:**<br>
当初「nil 値もエラーにする」設計で実装したが、`PurposeAnalysisJobTest` の正常系テストが失敗した。<br>
原因: テストの `@user_purpose` は `purpose` / `mission` 等を一部しか設定しておらず、<br>
`build_input_snapshot` が `mission: nil` のような Hash を生成するため `present?` チェックで弾かれた。<br>
`key?` のみのチェックに修正することで既存の全テスト（549件）が通過するようになった。

<br>

### 70. DB カラムのみで AI レート制限を実現する（#D-10）

<br>

Redis を使わず `user_settings.last_ai_requested_at` カラムのみで 1 分以内の重複リクエストを防ぐ設計を採用した。<br>
Render 無料プランでは Redis が利用できないため、既存の PostgreSQL のみで実現できる方式が必須要件だった。

<br>

| 方式 | 特徴 | 採用理由 |
|:---|:---|:---|
| Redis（rack-attack 等） | 高速・精密なレート制限が可能 | Render 無料プランでは利用不可 |
| DB カラム（`last_ai_requested_at`） | user_setting 取得のついでに確認できる | 追加インフラ不要・コスト 0 |

<br>

`update_columns` で単一カラムのみ更新することでバリデーション・コールバックをスキップし、<br>
タイムスタンプの記録を高速かつシンプルに実現した。<br>

```ruby
# UserSetting モデルに追加したメソッド
def ai_recently_requested?
  return false unless last_ai_requested_at.present?
  last_ai_requested_at > Time.current - 1.minute
end

def touch_ai_requested_at!
  update_columns(last_ai_requested_at: Time.current)
end
```

<br>

### 71. Stimulus コントローラーのタイマー管理はタイマーID を保持する（#D-10）

<br>

`setTimeout` の戻り値（タイマーID）を `this._cooldownTimer` に保持することで、<br>
Turbo Drive でページ遷移した場合でも `disconnect()` でタイマーをクリアできる。<br>
タイマーID を保持しないと「ページ遷移後にタイマーが残り続けるメモリリーク」が発生する。<br>

```javascript
// ✅ タイマーID を保持 → disconnect() でクリアできる
connect() {
  this._cooldownTimer = null
}

disconnect() {
  if (this._cooldownTimer) {
    clearTimeout(this._cooldownTimer)
    this._cooldownTimer = null
  }
}

throttle() {
  this._cooldownTimer = setTimeout(() => {
    // 1分後にボタンを有効に戻す
  }, this.cooldownValue)
}
```

<br>

### 72. Stimulus の data-action には複数コントローラーのメソッドをスペース区切りで並べる（#D-10）

<br>

1つの DOM イベントに対して複数のコントローラーメソッドを実行したい場合、<br>
`data-action` にスペース区切りで並べることで順番に実行できる。<br>
`data-controller` も同様にスペース区切りで複数コントローラーを適用できる。<br>

```erb
<%# form-submit と ai-throttle の両方を同一フォームに適用する %>
<%= form_with data: {
  controller: "form-submit ai-throttle",
  action: "submit->form-submit#submit submit->ai-throttle#throttle"
} do |f| %>
```

<br>

1 つのボタンに複数コントローラーのターゲットを同時に指定することも可能。<br>

```erb
<%= f.submit "送信",
    data: {
      "form-submit-target": "button",   # form-submit コントローラーのターゲット
      "ai-throttle-target": "button"    # ai-throttle コントローラーのターゲット
    } %>
```

<br>

### 73. format.any で未知フォーマットの UnknownFormat エラーを解消する（#D-10）

<br>

`respond_to` ブロックに `format.html` / `format.json` / `format.turbo_stream` のみを定義していると、<br>
`favicon.ico`（`ico` フォーマット）や `robots.txt`（`txt` フォーマット）のリクエストが<br>
catch-all ルートにマッチした際に `ActionController::UnknownFormat` が発生する。<br>
`format.any { head status }` を末尾に追加することで全ての未知フォーマットに対して<br>
ボディなしのステータスコードのみを返すようになり、エラーが解消される。<br>

```ruby
def render_error_page(template, status)
  respond_to do |format|
    format.turbo_stream { head status }
    format.html { render template: template, layout: "application", status: status }
    format.json { render json: { error: status.to_s }, status: status }
    # ✅ ico / xml / png 等の未知フォーマット → ボディなしでステータスのみ返す
    format.any { head status }
  end
end
```

<br>

### 74. AiClient のエラー設計は「Job側との契約」を守る（#D-11）

<br>

`AiClient#analyze` は「常に nil か Hash を返す」設計を維持することが重要。<br>
タイムアウト・認証エラーなどを `raise` した場合、`ApplicationJob` の `retry_on StandardError` が<br>
誤作動して「60秒後に再エンキュー」という D-11 要件と「GoodJob の自動リトライ」が二重に動いてしまう。<br>
エラーを Job 側に伝播させないことで「再エンキューの制御が Job の中の1箇所に集中する」設計になる。

<br>

```ruby
# ✅ analyze は常に nil か Hash を返す（例外を外に伝播させない）
rescue Faraday::TimeoutError, Timeout::Error => e
  notify_sentry(e, level: :warning, extra: { timeout_seconds: API_TIMEOUT })
  nil  # ← raise ではなく nil を返す

# ❌ raise すると ApplicationJob の retry_on StandardError が反応して二重リトライになる
rescue Faraday::TimeoutError => e
  raise e  # 危険
```

<br>

例外として `AuthError` だけは Job に伝播させる。<br>
理由: 401 はリトライしても必ず失敗するため、`discard_on AiClient::AuthError` で即座に破棄させる。<br>
その前に `handle_failure` を呼んでユーザーに通知する設計にすること。

<br>

### 75. HTTP エラー処理は共通メソッドに集約して DRY にする（#D-11）

<br>

Gemini と Groq は API レスポンス構造が異なるため「成功レスポンスの処理」は共通化できないが、<br>
「エラー処理（401/429/それ以外）」は全く同じ分岐になる。<br>
`handle_http_error(response, provider_name)` メソッドに集約することで<br>
`call_gemini` と `call_groq` の両方から呼び出せる DRY な設計になる。<br>
将来プロバイダが増えた場合もこのメソッドを呼ぶだけでエラー処理が統一される。

<br>

```ruby
def handle_http_error(response, provider_name)
  case response.status
  when 401
    auth_error = AuthError.new("#{provider_name} 認証エラー（401）")
    notify_sentry(auth_error, level: :fatal)
    raise auth_error
  when 429
    raise RateLimitError, "#{provider_name} レート制限（429）"
  else
    raise "#{provider_name} API エラー: HTTP #{response.status}"
  end
end
```

<br>

### 76. 全プロバイダ失敗時は perform_later で明示的に再エンキューする（#D-11）

<br>

GoodJob の `retry_on` はリトライ間隔を `wait: :exponentially_longer` のような動的計算のみ対応しており、<br>
`wait: 60.seconds` のような固定秒数を正確に指定できない制限がある。<br>
`PurposeAnalysisJob.set(wait: 60.seconds).perform_later(...)` を明示的に呼ぶことで<br>
「60秒後に確実に再実行」が実現できる。<br>
`reenqueue_count` を引数で渡すことで何回目の再試行かを追跡できる設計になる。

<br>

```ruby
# ✅ 明示的な再エンキューで固定60秒待機を実現
PurposeAnalysisJob.set(wait: REENQUEUE_WAIT_SECONDS.seconds)
                  .perform_later(user_purpose_id, reenqueue_count: next_count)
```

<br>

### 77. failed バナーのエラーメッセージは「種別判定 → 日本語変換」で表示する（#D-11）

<br>

`last_error_message` をそのまま表示すると「Gemini API エラー: HTTP 429 - Too Many Requests」<br>
のような英語エラーがユーザーに見えてしまう。<br>
ERB のビュー内でエラーメッセージの文字列に含まれるキーワードを判定し、<br>
ユーザーが理解できる日本語タイトル・詳細・アイコンの組み合わせに変換して表示する設計にする。<br>
`show_without_ai` フラグでタイムアウト時のみ「AIなしで続行する」ボタンを表示し、<br>
不適切なフォールバック誘導を防ぐ。

<br>

```erb
<%# エラー種別を判定して error_info Hash を生成する %>
<% error_info = if error_raw.include?("タイムアウト")
  { icon: "⏱️", title: "分析がタイムアウトしました", show_without_ai: true }
elsif error_raw.include?("接続できません")
  { icon: "🔑", title: "AIサービスに接続できません", show_without_ai: false }
# ...
end %>
```

<br>

### 78. Sentry 通知は defined?(Sentry) で条件分岐してI-5導入前でも安全に動かす（#D-11）

<br>

I-5（Sentry導入）タスクが完了する前でも Sentry 通知の「コード」は先に書いておける。<br>
`defined?(Sentry)` で実行時に gem の存在を確認し、<br>
gem がない場合はログのみ出力するフォールバックにすることで<br>
I-5 の前後でコードを変更せずに Sentry が自動で有効になる設計になる。

<br>

```ruby
def notify_sentry(exception, level: :error, extra: {})
  if defined?(Sentry)
    Sentry.capture_exception(exception, level: level, extra: extra)
  else
    # I-5 導入前はログのみ出力（導入後は自動で上の分岐が動く）
    Rails.logger.warn "[Sentry未導入] [#{level.upcase}] #{exception.class}: #{exception.message}"
  end
end
```

<br>

### 79. `travel_to` ブロック内のアサーションは Minitest にカウントされない（#E-1）

<br>

Minitest は `travel_to { assert ... }` のブロック内のアサーションをカウントしない仕様がある。<br>
`571 runs, 0 assertions` のような「Test is missing assertions」警告が出た場合はこれが原因。<br>
`travel_to / travel_back` の展開形式に変更することでアサーションがブロック外に出てカウントされるようになる。<br>

```ruby
# ❌ ブロック内のアサーションは Minitest にカウントされない
travel_to Time.zone.parse("2026-02-16 03:59:00") { assert reflection.pending? }

# ✅ 展開形式なら正しくカウントされる
travel_to Time.zone.parse("2026-02-16 03:59:00")
assert reflection.pending?, "AM3:59 では pending? は true のまま"
travel_back
```

<br>

### 80. フォーム共通パラメータはヘルパーメソッドに集約して必須フィールドの変更に強くする（#E-1）

<br>

テストで `post weekly_reflections_path, params: { weekly_reflection: { ... } }` を複数書くとき、<br>
必須フィールドが増えるたびに全テストを修正する必要が生じる。<br>
`valid_reflection_params` / `valid_purpose_params` のようなヘルパーメソッドを作成し、<br>
デフォルト値をまとめることで変更箇所を1か所に集約できる。<br>

```ruby
def valid_reflection_params(overrides = {})
  {
    reflection_comment:   "今週も頑張った！",
    direct_reason:        "残業が多かった",
    background_situation: "朝型に切り替える",
    next_action:          "他の習慣にも広げる"
  }.merge(overrides)
end

# 個別テストで差分だけ上書き
post weekly_reflections_path, params: {
  weekly_reflection: valid_reflection_params(reflection_comment: "1回目")
}
```

<br>

### 81. `numericality: { in: 1..5 }` は Rails 7 で使用不可（#E-1）

<br>

Rails 7 の `numericality` バリデーターは `in:` オプションをサポートしていない。<br>
`ArgumentError: Unknown options: [:in]` が発生してアプリが起動できなくなる。<br>
範囲チェックには `greater_than_or_equal_to` と `less_than_or_equal_to` を組み合わせる。<br>

```ruby
# ❌ Rails 7 では ArgumentError
validates :mood, numericality: { in: 1..5 }, allow_nil: true

# ✅ Rails 7 での正しい書き方
validates :mood,
          numericality: {
            only_integer:             true,
            greater_than_or_equal_to: 1,
            less_than_or_equal_to:    5
          },
          allow_nil: true
```

<br>

### 82. スクリプト生成したコードはカンマ漏れを必ずチェックする（#E-1）

<br>

Ruby の Hash リテラルで途中の要素末尾にカンマが欠落すると `SyntaxError` になる。<br>
スクリプトや自動ツールで `reflection_comment: "..." # コメント` の行の後に新フィールドを挿入する際、<br>
コメントが付いている行の末尾カンマが抜け落ちるパターンが繰り返し発生した。<br>
スクリプト生成後は以下のチェックを必ず行うこと。<br>

```python
# カンマ漏れを検出するチェックパターン
for line in lines:
    if 'フィールド名:' in line and '# コメント' in line:
        code_part = line.split('#')[0].rstrip()
        if not code_part.endswith(','):
            print(f"MISSING COMMA: {line}")
```

<br>

また `reflection_comment: "..." # E-1 追加` のように「コメントを外すとカンマがない」形式は<br>
`code_part = line.split('#')[0].rstrip()` でコード部分だけを抽出してからカンマ有無を確認する。

<br>

### 83. actual_value.present? でスナップショットの型判定をする（#E-2）

<br>

`weekly_reflection_habit_summaries` の `habit_id` は `on_delete: :nullify` のため、<br>
習慣が削除されると `NULL` になる可能性がある。<br>
`habit.numeric_type?` で型判定するとこのケースで `NoMethodError` になる。<br>
`actual_value.present?` で判定することでスナップショットデータを信頼し、<br>
習慣が削除された後も「数値型だったか」を正確に判定できる。

<br>

```ruby
# ❌ habit が nil の可能性がある
def numeric?
  habit&.numeric_type?
end

# ✅ スナップショットデータから判定する
def numeric?
  actual_value.present?  # 0.0.present? == true のため実績0の数値型も正しく判定される
end
```

<br>

`0.0.present? == true` である点に注意。<br>
「今週0分だった数値型習慣」も `numeric? = true` となり、「0 / 120 分（0%）」と表示される。<br>
チェック型（`actual_value: nil`）との区別が正しく行える。

<br>

### 84. 同名の input が2つあるとブラウザは後の値を優先する（#E-2）

<br>

`name="habit[weekly_target]"` を持つ `number_field` と `hidden_field` が両方 DOM に存在すると、<br>
ブラウザはフォーム送信時に後の方の値（`hidden_field` の `value=7`）を優先する。<br>
`hidden` 属性を div に付けても内部の input は送信されるため、<br>
`disabled` 属性の付与も Stimulus のターゲット取得タイミングの問題で不完全になった。<br>
根本解決は **「同名の input を1つだけにする」** こと。<br>
`number_field` 1つだけを DOM に残し、Stimulus でチェック型のとき `value=7` に固定して<br>
数値型のとき入力可能にする設計が最も安定する。

<br>

```javascript
// ✅ 1つの input をJSで状態制御する
if (isNumeric) {
  weeklyTargetField.removeAttribute("hidden")
  weeklyTargetInput.removeAttribute("max")
  if (!weeklyTargetInput.value || weeklyTargetInput.value === "7") {
    weeklyTargetInput.value = 5  // 初期値をリセット
  }
} else {
  weeklyTargetField.setAttribute("hidden", "")
  weeklyTargetInput.value = 7   // チェック型は7に固定
  weeklyTargetInput.setAttribute("max", "7")
}
```

<br>

### 85. Stimulus の targets より querySelector の方が Turbo 環境で安定する場合がある（#E-2）

<br>

Stimulus の `this.xxxTarget` はコントローラーの `connect()` タイミングやTurboキャッシュの影響で<br>
正しく取得できないケースが稀に発生する。<br>
`form.querySelector("[data-habit-form-target='weeklyTargetField']")` のように<br>
`this.element`（フォーム要素）から直接 `querySelector` で取得することで<br>
DOM から毎回直接参照するため Turbo 環境でも安定して動作する。<br>
特に「toggle 系の表示切替」に関わるターゲットは `querySelector` ベースにすることを検討すること。

<br>

### 86. テストの HabitRecord 取得は user と habit で絞り込む（#E-2）

<br>

`HabitRecord.order(created_at: :desc).first` は全ユーザーの最新レコードを取得するため、<br>
フィクスチャの挿入順序（テストシードの変化）によって別ユーザーのレコードを拾う<br>
フレーキーテストになる。<br>
`HabitRecord.find_by!(user: @user, habit: new_habit)` のように<br>
ユーザーと習慣で絞り込むことで確実に対象レコードを取得できる。<br>
フィクスチャを追加した際は既存テストの「件数や最新レコードに依存した取得」を<br>
必ず見直すこと。

<br>

### 87. referer でリクエスト元ページを判定して Turbo Stream 応答を切り替える（#E-3）

<br>

チェックボックス操作後の Turbo Stream レスポンスは「どのページから来たか」で最適な更新対象が異なる。<br>
`/habits` ページ: カード全体（プログレスバー含む）を置き換える必要がある。<br>
`/dashboard` ページ: チェックボックス行と達成率バーの2件を同時更新する必要がある。<br>
既存の JavaScript を変更せずに `request.referer` でページを判定し、Turbo Stream の対象を動的に切り替える設計を採用した。<br>

```ruby
def build_turbo_stream_response(habit_record)
  from_habits_page = request.referer&.include?("/habits")

  if from_habits_page
    # /habits: カード全体（プログレスバー含む）を置き換える
    turbo_stream.replace("habit_record_#{@habit.id}", partial: "habits/habit_card", ...)
  else
    # /dashboard: チェックボックス + 達成率バーの2件を同時更新
    [
      turbo_stream.replace("habit_record_row_#{@habit.id}", ...),
      turbo_stream.replace("dashboard_habit_stat_#{@habit.id}", ...)
    ]
  end
end
```

<br>

Turbo Stream は配列で複数の操作を1レスポンスで返すことができる。<br>
`render turbo_stream: [stream1, stream2]` で渡すと全ての `<turbo-stream>` 要素が順番に処理される。<br>
`request.referer` が nil の場合はダッシュボード側の動作（安全側）にフォールバックする設計にした。

<br>

### 88. Turbo Stream で変更を受け取るパーシャルには必ず id を付けてパーシャル化する（#E-3）

<br>

Turbo Stream の `replace` / `update` の対象は DOM 上の id で識別される。<br>
「リアルタイム更新したい要素」は最初からパーシャルに切り出し、かつ最外側の要素に id を付ける設計にすること。<br>
ダッシュボードの習慣達成率バーは当初ループ内に直書きされており id がなかった。<br>
`_habit_stat_row.html.erb` に切り出して `id="dashboard_habit_stat_#{habit.id}"` を付けることで<br>
Turbo Stream の更新対象として認識できるようになった。<br>

```html

...


...
```

<br>

### 89. content_for :modals でモーダルをレンダリングした後に Turbo Stream から open イベントを送る（#E-3）

<br>

AI提案モーダルは `weekly_reflections/index.html.erb` でレンダリングされており、<br>
Turbo Stream バナー更新後に「AI提案を確認する →」ボタンが DOM に追加される。<br>
ボタンの `onclick` に直接 JavaScript を書くのではなく、<br>
`window.dispatchEvent(new CustomEvent('open-ai-proposal-modal'))` でカスタムイベントを発火させ、<br>
Stimulus コントローラーの `connect()` で登録したリスナーが受け取る設計にした。<br>
これにより Turbo Stream 更新後に DOM が差し替わっても<br>
モーダルコントローラーが別の場所に存在していれば確実に開くことができる。<br>
`disconnect()` でリスナーを必ず解放することで Turbo Back 時の重複登録を防いでいる。

<br>

### 90. ログイン後のディープリンク遷移とオープンリダイレクト防止（#E-4）

<br>

**① `hidden_field_tag` で POST body に `redirect_to` を維持する**

<br>

ログインフォームの送信先URLにクエリパラメータを付けるだけでは不十分。<br>
ログイン失敗時に `render :new` でフォームを再描画するとブラウザのURLが変わり、<br>
クエリパラメータが失われる場合がある。<br>
`hidden_field_tag :redirect_to, params[:redirect_to]` を使うことで<br>
POST body にパラメータを含め、ログイン失敗後の再送信でも確実に維持できる。

<br>

**② ダブルスラッシュ攻撃（`//evil.com`）への対策**

<br>

`URI.parse("//evil.com").host` は `"evil.com"` を返す。<br>
`uri.host.nil?` だけでチェックすると `//evil.com` が通過してしまうため、<br>
`path.start_with?("//")` を先頭に追加して明示的に弾く二重チェックが必要。<br>

```ruby
def safe_redirect_path?(path)
  return false if path.blank?
  return false if path.start_with?("//")  # ← ダブルスラッシュを先に弾く
  uri = URI.parse(path)
  uri.host.nil? && path.start_with?("/")
rescue URI::InvalidURIError
  false
end
```

<br>

**③ `determine_redirect_path` で優先順位を1か所に集約する**

<br>

onboarding チェック・redirect_to チェック・デフォルトの3分岐を<br>
`SessionsController` の private メソッドに集約することで、<br>
`create` アクションがシンプルに読めるようになる。<br>
将来「パスワードリセット後のリダイレクト」等が加わっても1か所を修正するだけで済む（DRY原則）。

<br>

**④ 既存テストは `%r{/login}` 正規表現で対応する**

<br>

`assert_redirected_to login_path` はクエリパラメータなしの完全一致を期待する。<br>
E-4 実装後は `/login?redirect_to=...` となるため22テストが一斉に失敗した。<br>
`assert_redirected_to %r{/login}` に変更することで「/login を含む URL へのリダイレクト」を確認できる。<br>
`%r{\A/login}` は Rails がフルURL（`http://www.example.com/login?...`）を返すため<br>
マッチしない。`%r{/login}` で「/login を含む」判定にすることが正しい。

<br>

### 91. fetch ポーリングで非同期AI分析の完了を検知する（#E-5）

<br>

AI分析はバックグラウンドジョブで実行されるため、ページ表示時点では未完了の場合がある。<br>
Turbo Stream のサーバープッシュではなく、クライアントサイドの fetch ポーリングで解決した。

<br>

**なぜ Turbo Stream を使わなかったのか:**<br>
振り返り詳細ページ（`show`）は Turbo Stream チャンネルを持たない設計になっており、<br>
バックエンドのジョブからブロードキャストを受け取る仕組みがない。<br>
fetch ポーリングで同じページを再取得し、AI分析セクションの内容を比較する方式で実現した。

<br>

```javascript
// ✅ outerHTML 差し替えでスクロール位置を維持しつつ部分更新
const currentSection = document.getElementById("ai-analysis-section")
if (currentSection) {
  currentSection.outerHTML = newSection.outerHTML
}
```

<br>

`Turbo.visit`（ページ全体リロード）ではなく `outerHTML` の差し替えを使う理由:<br>
`Turbo.visit` はページ全体を再取得してスクロール位置が先頭に戻ってしまう。<br>
`outerHTML` の差し替えはAI分析セクションだけを更新するためスクロール位置が維持される。

<br>

### 92. 待機中UIの消滅でポーリング完了を検知する設計（#E-5）

<br>

「分析が完了したか」を判定するために専用のAPIエンドポイントを作らず、<br>
「待機中のUI要素が DOM に存在するか」で判定する設計にした。

<br>

```javascript
// 新しいHTMLに待機中UIがなければ完了
const stillWaiting = newSection.querySelector("[data-controller='ai-analysis-polling']")
if (!stillWaiting) {
  this.#stopPolling()  // ポーリング停止
}
```

<br>

待機中UIの `div` に `data-controller="ai-analysis-polling"` が付いており、<br>
分析完了後は完了UIに差し替えられてこの属性が消える。<br>
「属性が消えた = 完了」という状態変化をセレクターで検知することで<br>
専用エンドポイントなしにポーリングの停止タイミングを判定できる。

<br>

### 93. CSS preload警告は開発環境限定で抑制する（#E-5）

<br>

Rails 7.2 + Turbo の組み合わせでは、Turboのページ遷移のたびに<br>
`Link: rel=preload` ヘッダーが自動付与され、「使われなかった preload」として<br>
ブラウザのコンソールに警告が出る。

<br>

**なぜ `application_controller.rb` で `response.headers.delete("Link")` しないのか:**<br>
Link ヘッダーには将来的にページネーション（`rel="next"`等）やAPIの重要情報が含まれる可能性がある。<br>
全Linkヘッダーを削除すると将来の機能追加時に原因不明のバグになる。

<br>

```ruby
# ✅ Action View が生成するアセット用ヘッダーだけを安全に停止
if config.action_view.respond_to?(:preload_links_header=)
  config.action_view.preload_links_header = false
end
```

<br>

`respond_to?` で条件分岐することで、将来の Rails バージョンで設定名が変わっても<br>
`NoMethodError` で起動できなくなる問題を防いでいる。<br>
`development.rb` 限定にすることで本番・テスト環境への影響をゼロにした。

<br>

### 94. `button_to` のブロック形式は無限ループを引き起こす（#F-1）

<br>

`button_to` に `do...end` ブロックを渡すと Rails がレイアウトを再レンダリングし、<br>
無限ループになりスタックオーバーフローエラーが発生する。<br>
ボタン内にカスタムコンテンツが必要な場合は `form_tag` + `<button type="submit">` で代替する。<br>

```erb
<%# ❌ button_to のブロック形式 → 無限ループ %>
<%= button_to auth_google_oauth2_path do %>
   Google でログイン
<% end %>

<%# ✅ form_tag + button 方式 %>
<%= form_tag(auth_google_oauth2_path, method: :post) do %>
  
     Google でログイン
  
<% end %>
```

<br>

### 95. ERBコメント内の `<%= %>` は実際に実行される（#F-1）

<br>

`<%# コメント %>` 内に `<%= render "..." %>` を書くと、<br>
ERB はコメントを無視してレンダリングを実行してしまう。<br>
「このパーシャルを使う予定のコード例」をコメントとして残したい場合は<br>
`<%# render "shared/google_auth_button" %>` ではなく<br>
プレーンテキスト（ERB タグなし）でコメントを書くこと。

<br>

### 96. `has_secure_password validations: false` は `password_confirmation` の自動バリデーションも無効化する（#F-1）

<br>

Google ユーザーはパスワード不要のため `has_secure_password validations: false` を使うが、<br>
これにより `password_confirmation` の「一致確認バリデーション」まで無効化される。<br>
メールログインユーザー向けに明示的に以下を追加すること。<br>

```ruby
validates :password, confirmation: true, if: ->(u) { u.provider.blank? || u.provider == "email" }
validates :password_confirmation, presence: true,
          if: ->(u) { (u.provider.blank? || u.provider == "email") && u.password.present? }
```

<br>

### 97. `private` メソッドを validates の `if:` シンボルで指定すると Rails 7 では呼び出せない（#F-1）

<br>

`validates :password, if: :email_provider?` のようにシンボルで指定したとき、<br>
`email_provider?` が `private` メソッドだと Rails 7 では呼び出せず<br>
`NoMethodError: private method 'email_provider?' called` が発生する。<br>
ラムダに変更することで回避できる。<br>

```ruby
# ❌ private メソッドへのシンボル参照
validates :password, if: :email_provider?

# ✅ ラムダで直接判定
validates :password, if: ->(u) { u.provider.blank? || u.provider == "email" }
```

<br>

### 98. Google ユーザーは `password_digest NOT NULL` 制約を解除する必要がある（#F-1）

<br>

既存スキーマの `password_digest` に NOT NULL 制約がある場合、<br>
Google ユーザーはパスワードを設定しないため `User.create!` で `PG::NotNullViolation` が発生する。<br>
`change_column_null :users, :password_digest, true` のマイグレーションで制約を解除し、<br>
パスワードバリデーションの `if:` 条件でメールユーザーのみ必須にする設計にすること。

<br>

### 99. `update_columns` でメールマージすると uniqueness バリデーション衝突を回避できる（#F-1）

<br>

Google ログイン時に既存メールアカウントと同一メールのユーザーが存在する場合、<br>
`user.update!(provider: "google_oauth2", uid: uid)` では<br>
`validates :email, uniqueness: true` が既存レコード自身に対して走り衝突することがある。<br>
`user.update_columns(provider: "google_oauth2", uid: uid)` ではバリデーションをスキップするため安全にマージできる。

<br>

### 100. omniauth-line-v2_1 の provider シンボルは `:line_v2_1`（#F-2）

<br>

`omniauth-line-v2_1` gem のストラテジークラス名は `OmniAuth::Strategies::LineV21`。<br>
OmniAuth は provider シンボルを CamelCase に変換してストラテジークラスを探すため、<br>
`:line` → `Line`・`:line_v21` → `LineV21`・`:line_v2_1` → `LineV21` のいずれかになる。<br>
実際のファイルが `omniauth/strategies/line_v2_1.rb` のため `:line_v2_1` が最も明確。<br>
コールバック URL は `/auth/line_v2_1/callback` になるため routes.rb と LINE Developers Console も合わせる。

<br>

### 101. LINE はメールアドレスを返さないためDBレベルの NOT NULL 制約解除が必要（#F-2）

<br>

Rails の `allow_nil: true` はRailsバリデーションをスキップするだけで、<br>
PostgreSQL の NOT NULL 制約には効果がない。<br>
`PG::NotNullViolation` は INSERT 時にDBが直接エラーを返すため、<br>
`change_column_null :users, :email, true` のマイグレーションで制約を解除する必要がある。<br>
F-1（Google）実装時に `allow_nil: true` を追加したが DB 制約の解除が漏れており、<br>
F-2 で初めて email=nil の INSERT が実際に走ったため発覚した。

<br>

### 102. LINE の uid（sub）と line_user_id（Messaging API userId）は別物（#F-2）

<br>

| 識別子 | 取得元 | 用途 | カラム |
|:---|:---|:---|:---|
| sub（uid） | LINE Login の OpenID Connect | ログイン認証・ユーザー識別 | `users.uid` |
| userId | LINE Messaging API | プッシュ通知の送信先 | `users.line_user_id` |

<br>

両者は異なる文字列であり互換性がない。<br>
`uid` を `line_user_id` の代わりに使うと #G-1（LINE 通知実装）で事故が発生する。<br>
設計時点でコメントに明記し、カラムの用途を混同しないよう徹底すること。

<br>

### 103. docker-compose.yml の environment に明示しないと .env の値がコンテナに入らない（#F-2）

<br>

Docker Compose は `.env` ファイルを自動で読み込むが、<br>
`docker-compose.yml` の `environment:` セクションに `KEY: ${KEY}` の形式で<br>
明示的に記載しないとコンテナ内の環境変数として設定されない。<br>
`docker compose restart web` だけでは変更が反映されないケースもあるため、<br>
環境変数を追加した後は必ず `docker compose down` → `docker compose up -d` を実行すること。

<br>

### 104. `terms_agreed?` は public に置かないと ApplicationController から呼べない（#F-3）

<br>

`before_action` / `before_validation` の条件判定で使うメソッドは private に置きがちだが、<br>
`ApplicationController` の全画面ガード（`redirect_to_terms_agreement_if_needed`）から<br>
`user.terms_agreed?` を呼ぶ場合は public に定義する必要がある。<br>
`private` に置くと `NoMethodError: private method 'terms_agreed?' called` が発生し、<br>
全ページで 500 エラーになる致命的なバグになる。<br>
`set_terms_agreed_at`（コールバックで呼ばれるだけ）は private でよいが、<br>
`terms_agreed?`（外部から参照される述語メソッド）は public ブロックに置くこと。

<br>

### 105. fixture全ユーザーへの `terms_agreed_at` 追加は「テスト保護の定石」（#F-3）

<br>

全画面ガード（`redirect_to_terms_agreement_if_needed`）を追加すると、<br>
`terms_agreed_at` が nil のユーザーでテストがログインするたびに<br>
`/terms_agreement` にリダイレクトされ、既存テストが全て失敗する。<br>
新機能がリダイレクトフックを追加する場合、fixture全ユーザーにデフォルト値を追加し、<br>
`log_in_as` のような共通ヘルパーで自動的に条件を満たす設計にすることで<br>
既存テストへの影響を最小化できる。<br>
未同意状態が必要なテストだけ `user.update_column(:terms_agreed_at, nil)` で明示的に戻す方針が安全。

<br>

### 106. Docker環境では letter_opener_web を使う

<br>

`letter_opener` は送信時にブラウザを自動起動しようとするが、<br>
Dockerコンテナ内にはブラウザが存在しないため何も起動されずメールを確認できない。<br>
GoodJob で `deliver_later` を使っている場合、ログには `Performed ActionMailer::MailDeliveryJob` が<br>
出力されていても `http://localhost:3000/letter_opener` にアクセスできないため確認できない。<br>
Docker環境では最初から `letter_opener_web` を導入すること。<br>
routes.rb の `mount LetterOpenerWeb::Engine` は `if Rails.env.development?` ブロック内に<br>
**1つだけ**配置すること。2箇所に分かれると `Invalid route name 'error_404'` エラーになる。

<br>

### 107. パスワードリセットトークンは BCrypt 保存・UNIQUE制約・24時間有効期限の三点セット

<br>

パスワードリセットトークンの設計で最低限必要な三点セット：<br>
① `token_digest`（BCryptハッシュ化保存）: DB漏洩時にリセットURLを復元不可にする<br>
② `user_id` に UNIQUE制約: 1ユーザーに複数の有効トークンが発行されることを防ぐ<br>
③ `expires_at`（24時間有効期限）: 古いリセットリンクが永遠に有効な状態を防ぐ<br>
加えて使用後に `is_used=true` で無効化し、パスワード変更と無効化を同一トランザクションで処理すること。

<br>

### 108. if Rails.env.development? ブロックは1か所に統合する

<br>

`config/routes.rb` で `if Rails.env.development?` ブロックが2か所に分かれると、<br>
`get "/404", to: "pages#error_404", as: :error_404` のような名前付きルートが<br>
2度定義されて `Invalid route name, already in use: 'error_404'` エラーが発生し起動できなくなる。<br>
開発環境専用のルート（エラーページ・letter_opener_web・GoodJob等）は<br>
**1つの `if Rails.env.development?` ブロック**にまとめること。

<br>

### 109. rack-attack のテストは `unless Rails.env.test?` + setup 内登録の二段構えで解決する

<br>

`rack_attack.rb` でthrottleルールをテスト環境でも登録してしまうと、<br>
ログインテストや統合テストが意図せずブロックされて全テストが崩壊する。<br>
テスト環境での throttle 無効化には以下の2点が必要。

<br>

**① `unless Rails.env.test?` で initializer 全体を囲む**

<br>

```ruby
# ❌ class Rack::Attack do ... return ... end → return が SyntaxError になる
class Rack::Attack
  return if Rails.env.test?  # SyntaxError
  throttle(...)
end

# ✅ unless Rails.env.test? でブロック全体を囲む
unless Rails.env.test?
  Rack::Attack.throttle("login/ip", ...) { ... }
  Rack::Attack.cache.store = Rails.cache
end
```

<br>

**② テストファイルの setup/teardown でルールを直接登録・クリアする**

<br>

```ruby
# test/integration/rack_attack_test.rb
setup do
  Rack::Attack.enabled = true
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  # initializer ではテスト環境で登録されないため、テスト用ルールを直接登録する
  Rack::Attack.throttle("login/ip", limit: 10, period: 300) do |req|
    req.ip if req.path == "/login" && req.post?
  end
  Rack::Attack.throttled_responder = lambda { |request|
    [429, { "Retry-After" => "60" }, ["Too Many Requests"]]
  }
end

teardown do
  Rack::Attack.enabled = false
  Rack::Attack.throttles.clear
  Rack::Attack.throttled_responder = nil
  Rack::Attack.cache.store.clear
end
```

<br>

この設計により rack-attack のテストが完全に分離され、他のテストに影響を与えない。<br>
teardown で `throttles.clear` をしないと次のテストで throttle が二重登録される。

<br>

### 110. Docker 環境の safelist は localhost と ブリッジIP（172.18.0.1）の両方が必要

<br>

Docker Compose 環境では Web コンテナが `localhost`（`127.0.0.1` / `::1`）ではなく<br>
Dockerブリッジネットワークの IP アドレス（デフォルト `172.18.0.1`）から<br>
自分自身にアクセスする場合がある。<br>
rack-attack の safelist に `127.0.0.1` と `::1` だけ追加しても<br>
Docker 環境でブロックされるため `172.18.0.1` も追加すること。<br>

```ruby
# safelist は development 環境のみ適用
if Rails.env.development?
  Rack::Attack.safelist("localhost and docker") do |req|
    ["127.0.0.1", "::1", "0.0.0.0", "172.18.0.1"].include?(req.ip)
  end
end
```

<br>

本番環境（Render）で safelist を適用しないことでセキュリティを維持する。<br>
Docker のブリッジIP は `docker network inspect bridge` で確認できる。

<br>

### 111. ユーザー退会は「論理削除 + 匿名化」の組み合わせで設計する（#F-6）

<br>

退会処理のデータ方針には「物理削除」「論理削除のみ」「論理削除 + 匿名化」の3パターンがある。

<br>

| 方針 | 利点 | 欠点 |
|:---|:---|:---|
| 物理削除 | シンプル・確実 | 統計データが消える・外部キー制約が複雑 |
| 論理削除のみ | 復元可能 | 個人情報が残り続けるため GDPR 等の法規対応が困難 |
| 論理削除 + 匿名化 | 統計保持・個人情報削除・再登録対応 | 実装が複雑 |

<br>

HabitFlow では「活動データを AI 改善に活用する」という設計目標のため B案（論理削除 + 匿名化）を採用。<br>
`users.deleted_at` に退会日時を記録しつつ、個人識別情報を上書きで匿名化する。<br>
`has_many` の `dependent: :destroy` を外すことで習慣・タスク等の活動データを保持する。

<br>

### 112. email の unique 制約を部分インデックスにすることで再登録を可能にする（#F-6）

<br>

全行対象の unique インデックス（`index_users_on_email`）では、退会後のメールアドレスが<br>
DB に残り続けるため同じアドレスでの再登録ができない。<br>
`WHERE deleted_at IS NULL` の部分インデックスに変更することで<br>
「有効ユーザー間での uniqueness は維持しつつ退会ユーザーは制約対象外」にできる。<br>
Rails バリデーション側も `conditions: -> { where(deleted_at: nil) }` で DB と完全一致させることが重要。<br>
`scope: :deleted_at` を使うと秒単位で衝突するリスクがあるため使用しないこと。

<br>

```ruby
# DB レベル（マイグレーション）
add_index :users, :email,
          unique: true,
          where:  "deleted_at IS NULL",
          name:   "index_users_on_email_active"

# Rails バリデーション（DB の部分インデックスと完全一致）
validates :email,
          uniqueness: {
            case_sensitive: false,
            conditions:     -> { where(deleted_at: nil) }
          },
          allow_nil: true
```

<br>

### 113. マイグレーションで既存インデックスを変更する場合は up/down を分離する（#F-6）

<br>

`change` メソッド内で `remove_index` を行うと、Rails は rollback 時に<br>
「元のインデックスがどんな設定だったか」を自動復元できずエラーになる。<br>
インデックスの変更（削除 + 再作成）を伴うマイグレーションは `up/down` を明示的に分けることで<br>
`db:rollback` を安全に実行できる。

<br>

### 114. LINE Login と Messaging API は同一プロバイダーに配置する（#G-1）

<br>

LINE には「LINE Login チャネル」と「Messaging API チャネル」の2種類があり、<br>
OmniAuth で取得する `uid`（LINE Login の sub）と<br>
Messaging API で通知を送る `line_user_id`（userId）の関係に注意が必要。

<br>

**同一プロバイダーに配置することで `uid == userId` が保証される:**

<br>

| 設定 | uid / userId |
|:---|:---|
| 同一プロバイダー内の LINE Login + Messaging API | ✅ uid == userId |
| 異なるプロバイダーの LINE Login + Messaging API | ❌ uid ≠ userId（別の値になる） |

<br>

同一プロバイダー内であれば、OmniAuth コールバックで取得した `auth.uid` を<br>
そのまま `users.line_user_id` として保存し、Messaging API の Push Message 送信先として使用できる。<br>
別プロバイダーに配置すると両者が異なる文字列になり通知が届かない致命的なバグになる。

<br>

### 115. LINE Push Message は Net::HTTP で直接呼び出す（#G-1）

<br>

LINE Messaging API 専用の公式 Ruby SDK が存在しないため、<br>
faraday（`AiClient` と同じアプローチ）ではなく Rails 標準の `Net::HTTP` で直接呼び出す設計を採用した。<br>
`require "net/http"` と `require "json"` だけで動作するため追加 gem が不要になる。<br>
エンドポイントは `https://api.line.me/v2/bot/message/push` に POST し、<br>
Authorization ヘッダーに `Bearer #{LINE_CHANNEL_ACCESS_TOKEN}` を付ける方式。

<br>

```ruby
# LineNotificationService の呼び出し例
uri  = URI("https://api.line.me/v2/bot/message/push")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Post.new(uri.path)
request["Content-Type"]  = "application/json"
request["Authorization"] = "Bearer #{ENV['LINE_CHANNEL_ACCESS_TOKEN']}"
request.body = {
  to:       line_user_id,
  messages: [{ type: "text", text: message }]
}.to_json

response = http.request(request)
```

<br>

HTTP 401 は「トークンが無効」を意味する。開発中は LINE Developers Console で<br>
「チャネルアクセストークン（長期）」を再確認し、`.env` の値と一致しているか必ず確認すること。

<br>

### 116. Render Free プランでの LINE 通知基盤の制約（#G-1）

<br>

Render Free プランでは Background Worker（別プロセス）が利用できないため、<br>
GoodJob は `execution_mode: :async`（Web プロセス内実行）で動作している。<br>
LINE 通知は `TaskAlarmJob` 経由で `NotificationService` を呼ぶ設計のため、<br>
Worker なしでも Web プロセス内のバックグラウンドスレッドで通知が送信される。

<br>

`render.yaml` には `habitflow-worker` の定義を残さない設計にした。<br>
将来有料プランに移行する場合は `render.yaml` に Worker 設定を追加し、<br>
`config/environments/production.rb` の `execution_mode` を `:external` に変更することで分離できる。

<br>

### 117. メイラーのビューで ApplicationHelper を使うには `helper :application` が必要（#G-2）

<br>

ActionMailer はデフォルトでは `ApplicationHelper` のメソッドをビューテンプレートに<br>
自動インクルードしない場合がある。<br>
`app/views/weekly_report_mailer/report.html.erb` 内で `achievement_color(stat[:rate])` を<br>
呼び出した際に `undefined method 'achievement_color'` が発生してメールの render に失敗する。<br>
`WeeklyReportMailer` クラスに `helper :application` を明示することで<br>
確実に `ApplicationHelper` がビューに読み込まれ、ヘルパーメソッドが使えるようになる。

<br>

```ruby
class WeeklyReportMailer < ApplicationMailer
  helper :application  # ← これがないとビューで achievement_color が NoMethodError になる
  ...
end
```

<br>

### 118. メイラー内の URL 生成は `new_weekly_reflection_url` を明示する（#G-2）

<br>

タスク要件の `deep_link_url = "/weekly_reflections/new"` に対して、<br>
`weekly_reflections_url` を使うと一覧ページ（`/weekly_reflections`）を指してしまう誤りになる。<br>
`new_weekly_reflection_url` が振り返り入力ページ（`/weekly_reflections/new`）の正しいヘルパー名。<br>
またメイラー内で `default_url_options[:host]` を参照すると<br>
`ActionMailer::Base#default_url_options`（インスタンスメソッド）と混同するリスクがあるため、<br>
`Rails.application.config.action_mailer.default_url_options` を明示的に参照することで<br>
環境ごとの設定値（`habitflow.onrender.com` 等）を確実に取得できる。

<br>

### 119. GoodJob の cron エントリを追加するときは直前エントリのカンマを確認する（#G-2）

<br>

`config/initializers/good_job.rb` の `cron:` ハッシュに新しいエントリを追加するとき、<br>
直前のエントリ末尾にカンマがないと `SyntaxError` が発生してアプリが起動できなくなる。<br>

<br>

```ruby
# ❌ カンマなし → SyntaxError
cleanup_finished_jobs: {
  cron: "0 18 * * *",
  ...
}  # ← カンマなし

weekly_report_mail: { ... }  # SyntaxError

# ✅ カンマあり
cleanup_finished_jobs: {
  cron: "0 18 * * *",
  ...
},  # ← カンマあり

weekly_report_mail: { ... }
```

<br>

特に複数行コメントが直前エントリの末尾 `}` と新エントリの間に挟まる場合、<br>
コメントに目が行ってカンマの存在を見落としやすい。<br>
cron エントリを追加した後は必ず `docker compose up` で起動確認すること。

<br>

### 120. fixtures の `weekly_report_enabled` は全ユーザーを考慮してテストを設計する（#G-2）

<br>

`fixtures :all` により `test/fixtures/user_settings.yml` の全データがテスト DB に読み込まれる。<br>
`weekly_report_enabled: true` の fixture ユーザーが複数存在すると、<br>
`WeeklyReportJobTest` の `assert_emails 1` が「1件のはずが3件送られた」として失敗する。<br>
テスト前に `UserSetting.update_all(weekly_report_enabled: false)` で全件リセットし、<br>
その後テスト用ユーザーのみを `true` に設定することで fixture の影響を受けないテストになる。

<br>

```ruby
def setup
  # fixture ユーザーの weekly_report_enabled を全て false にリセットする
  UserSetting.update_all(weekly_report_enabled: false)

  @target_user = User.create!(...)
  @target_user.user_setting.update!(weekly_report_enabled: true)
  ...
end
```

<br>

### 121. Tailwind v4 の peer-checked: は直接隣接する兄弟要素のみに適用される（#G-3）

<br>

Tailwind v4 は `peer-checked:` の実装を `CSS :has()` + `~*`（汎用兄弟結合子）から<br>
`:is(:where(.peer):checked ~ *)` に変更している。<br>
これにより `.peer` の直接隣接する兄弟要素のみがターゲットになる。<br>
`span` の中に `peer-checked:` を書いても、`span` は `peer` の兄弟ではなく子孫のため効かない。<br>
トグルスイッチを実装する際は、`span` を廃止して `label` 自体に全クラスを付与することで解消できる。<br>

```html


  





```

<br>

### 122. Turbo フォーム送信と `status: :see_other` の組み合わせ（#G-3）

<br>

通常の `redirect_to` は 302 を返すが、Turbo が処理するフォーム送信では<br>
302 リダイレクト後のフラッシュメッセージが表示されないことがある。<br>
`data: { turbo: false }` でフォームを通常の HTML フォーム送信に変更し、<br>
コントローラーで `status: :see_other`（303）を明示することで<br>
ブラウザが POST → GET に変換して確実にフラッシュを表示できる。<br>
`turbo-cache-control: no-cache` メタタグとの組み合わせで「戻る」操作時のキャッシュ問題も解消できる。

<br>

### 123. content_for :modals のスコープ外ボタンは addEventListener で制御する（#G-4）

<br>

`content_for :modals` でモーダルが `</body>` 直前に出力されると、<br>
モーダル内のボタンは `data-controller` のスコープ外に出るため<br>
`data-action="click->rest-mode-modal#submitForm"` は Stimulus から認識されない。<br>
B-5/C-3 と同じ `_setupModalListeners()` パターンで `addEventListener` を直接登録し、<br>
`_listenersAttached` フラグで二重登録を防ぐ設計を採用した（#G-4 で実践）。<br>
各ボタンに固定 `id`（`rest-mode-submit-btn` 等）を付与し `document.getElementById()` で取得する。

<br>

### 124. form_with url: には scope: :user_setting を付けてパラメータ名を統一する（#G-4）

<br>

`form_with url:` 形式では `scope:` を指定しないと `f.date_field :rest_mode_until` が<br>
`rest_mode_until=...` として送信され、コントローラーの `params[:user_setting][:rest_mode_until]` が nil になる。<br>
`scope: :user_setting` を追加することで `user_setting[rest_mode_until]=...` として正しく送信される。<br>
`form_with model:` 形式では自動でスコープが付くが、`url:` 形式では必ず明示すること。

<br>

### 125. Turbo + send_data の競合は View 側の data-turbo="false" で解決する（#G-5）

<br>

Turbo が有効な状態で `button_to` からフォームをPOSTすると、Turbo が fetch API でリクエストを送るため、<br>
コントローラーの `redirect_to`（303）後にGETで `download` アクションを追従しても<br>
`send_data` のバイナリレスポンスをTurboがインターセプトしてブラウザにファイルが届かない。

<br>

| 試みた解決策 | 問題点 |
|:---|:---|
| Turbo Streamで `<script>window.location.href=...` | Turbo Stream で挿入した `<script>` は実行されない場合がある |
| 303リダイレクト方式 | GETリクエストもTurboが追従して `send_data` を飲み込む |
| **View側でdata-turbo="false"付与（採用）** | Turboを経由しない通常HTMLリクエスト → send_dataが届く |

<br>

**正しい解決策：SettingsControllerで件数を取得し、View側でボタンの種別を切り替える**

<br>

```ruby
# SettingsController#show
@habit_record_count      = current_user.habit_records.where(deleted_at: nil).count
@task_count              = current_user.tasks.where(deleted_at: nil).count
@weekly_reflection_count = current_user.weekly_reflections.count
```

<br>

```erb
<%# _csv_export_button.html.erb: 1,000件以下はdata-turbo="false" %>
<% immediate = count <= CsvExportService::LARGE_DATA_THRESHOLD %>

<% if immediate %>
  <%= button_to export_path_for(export_type),
      method: :post,
      data:   { turbo: false } do %>  <%# ← Turboを無効化 %>
    📥 <%= label %>
  <% end %>
<% else %>
  <%= button_to export_path_for(export_type), method: :post do %>
    📥 <%= label %>  <%# ← 通常Turbo → Turbo Streamで生成中ボタンに更新 %>
  <% end %>
<% end %>
```

<br>

ログで `Processing as HTML`（Turbo無効）か `Processing as TURBO_STREAM`（Turbo有効）かを確認し、<br>
1,000件以下のリクエストが `as HTML` になっていることを必ず検証すること。

<br>

### 126. パーソナライズAIはインコンテキスト学習で実現・ファインチューニング不要（#H-8）

蓄積された習慣記録・振り返り・AI分析結果を
`UserContextBuilderService` が週次で集計し、
「このユーザーは読書85%達成・運動30%・仕事疲れが原因に多い」
という傾向テキストを生成。既存の Gemini/Groq へのプロンプト先頭に
注入するだけでパーソナライズされた提案を実現する。

| アプローチ | コスト | 採用 |
|:---|:---|:---:|
| モデルのファインチューニング | GPU・数百万円 | ❌ |
| **インコンテキスト学習（採用）** | 追加インフラ不要 | ✅ |

プロファイルが存在しないユーザー（新規・データ不足）では
`context_text_for` が空文字を返し、既存プロンプトがそのまま動作する
フォールバック設計により、既存機能への影響ゼロで導入できる。

<br>

### 127. OmniAuth 2.x は GET リクエストを拒否する（#G-6）

<br>

OmniAuth 2.x のセキュリティ強化により、`/auth/:provider` への GET リクエストが<br>
`OmniAuth::Strategies::OAuth2::DisallowedError` として拒否されるようになった。<br>
`link_to + data-method: :post`（Turbo 疑似 POST）では不十分で、<br>
`button_to` による実際の `<form method="post">` が必要になる。<br>
設定ページの「LINEでログイン」ボタンを `link_to(GET)` から `button_to(POST)` に変更することで解消した。<br>

```ruby
<%# ❌ GET リクエスト → OmniAuth 2.x で DisallowedError %>
<%= link_to "LINE でログイン", user_line_v2_1_omniauth_authorize_path %>

<%# ✅ form POST → OmniAuth 2.x で正常動作 %>
<%= button_to "LINE でログイン",
    user_line_v2_1_omniauth_authorize_path,
    method: :post,
    form: { class: "inline" } %>
```

<br>

### 128. disabled を使わずに opacity + pointer-events-none で操作無効化する（#G-6 G-3）

<br>

フォーム内のチェックボックスやスライダーを `disabled` にすると、<br>
フォーム送信時にその値が送信されなくなり、設定が `false` に上書きされてしまう。<br>
`opacity-50 pointer-events-none` の CSS クラスを付与することで<br>
「見た目は操作不可・値は保持したまま送信される」状態を実現できる。<br>
マスタースイッチOFF時に各チャネルの設定値を保持したまま操作を禁止する G-3 の設計で採用した。

<br>

### 129. Stimulus の data-action は content_for :modals のスコープ外では効かない（#G-6 再確認）

<br>

G-6 でも B-5/C-3/G-4 と同じ問題が発生した。`content_for :modals` でモーダルを `</body>` 直前に出力すると、<br>
モーダル内ボタンは `data-controller` のスコープ外に出るため `data-action` が効かない。<br>
モーダルボタンへのイベント登録は `addEventListener` 方式で行い、`_listenersAttached` フラグで二重登録を防ぐこと。<br>
これは HabitFlow の「モーダル設計の標準パターン」として B-5 から一貫して採用している。

<br>

### 130. NotificationService の通知設計は「フォールバック」か「独立制御」かを最初に決める（#G-3修正）

<br>

LINE通知とメール通知を「LINEが使えなければメールで代替（フォールバック）」と設計するか、<br>
「それぞれ独立したON/OFFスイッチ（独立制御）」と設計するかによってコードが大きく変わる。<br>
UIが独立したトグルスイッチになっている場合は独立制御が自然。<br>
フォールバック設計では「LINE通知OFFなのにメールが来る」という意図しない動作になるため、<br>
UIの設計とバックエンドの設計を必ず一致させること。<br>

```ruby
# ❌ フォールバック設計 → LINE通知OFFでもメールが送られる
if use_line?
  send_line_notification(...)
elsif use_email?          # ← LINE通知OFFのとき自動的にメールへ
  send_email_notification(...)
end

# ✅ 独立制御 → 各スイッチが独立して動作する
if use_line?
  send_line_notification(...)
end
if use_email?             # ← LINE通知のON/OFFとは無関係
  send_email_notification(...)
end
```

<br>

また通知ロジックの確認は `rails runner` で実際に `NotificationService` を呼び出して<br>
ログ出力で確認するのが確実。UIのグレーアウトはあくまで見た目の制御であり、<br>
バックエンドの動作とは別に検証が必要。

<br>

### 131. `validates :password` に `on: :create` がないと更新時にバリデーションエラーになる（#G-6）

<br>

`validates :password, length: { minimum: 6 }` を `on:` 指定なしで書くと、<br>
`update` 時にも `password` の存在・長さが検証される。<br>
プロフィール編集（名前の変更のみ）で `user.update(name: "...")` を呼ぶと<br>
`password` が nil のため `ActiveRecord::RecordInvalid` が発生するバグになる。<br>
パスワードのバリデーションには必ず `on: :create` を付けること。<br>

```ruby
# ❌ on: なし → update 時にも password バリデーションが走る
validates :password, length: { minimum: 6 }

# ✅ on: :create → 新規作成時のみ検証
validates :password, length: { minimum: 6 }, on: :create
```

<br>

### 132. `turbo_stream_from` はif条件ブロックの外に置く（#G-7）

<br>

ダッシュボードで `if @current_purpose` ブロックの内側に `turbo_stream_from` を配置すると、<br>
PMVV未入力ユーザーはチャンネルを購読できず振り返りAI分析バナーも届かなくなる。<br>
特定の変数が nil の場合でも購読が必要なチャンネルは、条件ブロックの外に置くこと。<br>
```ruby
<%# ❌ @current_purpose が nil のユーザーはチャンネルを購読できない %>
<% if @current_purpose %>
  <%= turbo_stream_from "dashboard_notifications_#{current_user.id}" %>
<% end %>

<%# ✅ 条件ブロックの外に移動 → 全ユーザーが購読できる %>
<%= turbo_stream_from "dashboard_notifications_#{current_user.id}" %>
<% if @current_purpose %>
  ...
<% end %>
```

<br>

### 133. Turbo Stream 差し替え後のバナー重複は ERB 側で non-active コンテンツを非表示にする（#G-7）

<br>

PMVV分析完了バナーが `broadcast_replace_to` で届く前から、<br>
`analysis_status_banner`（completed 状態の通常バナー）が表示されている場合、<br>
両方が同時に表示されるバナー重複が発生する。<br>
ERB の条件分岐で `analysis_state == :completed` のとき `analysis_status_banner` の<br>
中身を `if !user_purpose.completed?` のように出力しない設計にすることで解消できる。<br>
JavaScript で後から非表示にする方式より、サーバー側で制御する方が確実。

<br>

### 134. コンソールでの `travel_to` の制約と代替確認手法（#G-8）

<br>

`ActiveSupport::Testing::TimeHelpers`（`travel_to` を提供するモジュール）は<br>
テスト環境のみに読み込まれるため、本番・開発コンソールでは使用不可。<br>
`include ActiveSupport::Testing::TimeHelpers` をコンソールで実行しても<br>
`uninitialized constant ActiveSupport::Testing (NameError)` が発生する。

<br>

**代替確認手法：**

<br>

| 確認内容 | コンソールでの代替手法 |
|:---|:---|
| 月初リセット処理の動作 | `UserSetting.update_all(ai_analysis_count: 0)` → 全件0を確認 |
| 月初以外のスキップ動作 | `MonthlyAiCountResetJob.perform_now` → ログに「スキップ」が出ることを確認 |
| `travel_to` を使った月初シミュレート | テストファイル内の `travel_to Time.zone.local(...)` でのみ実現 |

<br>

テストコード内での `travel_to` による月初シミュレートが、<br>
「月初に確実にリセットされる」動作保証の唯一の手段であることを理解しておくこと。

<br>

### 135. `update_all` 後は必ず `.reload` でDBキャッシュを更新する（#G-8）

<br>

`UserSetting.update_all(ai_analysis_count: 0)` はSQLを直接発行するため、<br>
Rubyオブジェクト（`@user_setting_1` 等のインスタンス変数）の内部状態は更新されない。<br>
テストで `update_all` の結果を確認するには必ず `@user_setting_1.reload` を呼んでから<br>
`@user_setting_1.ai_analysis_count` を参照すること。<br>
`reload` を省略すると「更新前の古い値（10 等）」が参照されてテストが正常に通過してしまう偽陽性になる。<br>

```ruby
# ❌ reload なし → update_all 前の古い値（10）が残る
MonthlyAiCountResetJob.perform_now
assert_equal 0, @user_setting_1.ai_analysis_count  # 10 のまま → 失敗するはずが通過（偽陽性）

# ✅ reload で最新DB値を取得してから確認する
MonthlyAiCountResetJob.perform_now
@user_setting_1.reload
assert_equal 0, @user_setting_1.ai_analysis_count  # 0 → 正しく確認できる
```

<br>

### 136. Turbo Stream ストリームは配信先ページ別に分離する（#G-9）

<br>

ダッシュボードとPMVVページが同一ストリーム名（`user_purpose_#{id}`）を購読していると、<br>
PMVVページ向けのパーシャル（「AI分析が完了しました」＋「結果を見る →」）が<br>
ダッシュボードにも届いてしまい、既存の「目標分析が完了しました」バナーと二重表示になる。

<br>

**解決策：ページ別にストリーム名を分離する**

<br>

| ストリーム | 購読先 | 配信内容 |
|:---|:---|:---|
| `user_purpose_#{id}` | PMVVページのみ | 全状態バナー（completed 時も「結果を見る →」付き） |
| `dashboard_user_purpose_#{id}` | ダッシュボードのみ | completed 時は空HTML（バナーを消す）・それ以外はスピナー |

<br>

ダッシュボードへの配信で completed 時に「空HTML」を送る理由は、<br>
ダッシュボードにはすでに `dashboard_pmvv_completion_banner`（G-7実装）があるため、<br>
PMVVページ向けのバナーを配信する必要がないから。

<br>

### 137. `broadcast_state_update` の重複定義はRubyの仕様でファイル後方が有効（#G-9）

<br>

同一クラス内に同名メソッド（`broadcast_state_update`）が2箇所定義されている場合、<br>
Rubyはファイルの後方にある定義を有効にする（上書き）。<br>
477行目に追加した新実装より533行目の旧実装が後方にあるため、<br>
意図と逆の古い実装が動作していた。<br>
旧実装（533行目付近）を削除して1本にまとめることで解消した。<br>
同名メソッドを複数定義してしまうバグは `grep -n "def broadcast_state_update"` で即座に発見できる。

<br>

### 138. `maxOutputTokens` は AI プロンプトの拡張と同時に見直す（#G-9）

<br>

AI のレスポンスが途中で切れる（318文字等で終了する）場合は `maxOutputTokens` の不足が原因。<br>
プロンプトの内容量を増やした場合は期待するレスポンス量も増えるため、<br>
`maxOutputTokens` / `max_tokens` を同時に拡張すること。<br>
G-9 では習慣・タスク一覧のプロンプト追加と goal_review スキーマ追加により<br>
レスポンス量が増加したため 4096 → 8192 に変更した。<br>
`AiClient` に複数箇所（Gemini用・Groq用）定義があるため両方を更新すること。

<br>

### 139. Rubyの `0` はtruthy — バッジ件数は `?` なしのIntegerで返す（#H-1）

<br>

`bn_ai_analysis_count?` という命名でbooleanを返す設計にすると、<br>
「0件のとき `0` はtruthyなのでバッジが非表示にならない」バグが発生する。<br>
メソッド名から `?` を外し Integer を返す設計にして、ビュー側で `if ai_count > 0` と明示的に判定すること。<br>

```ruby
# ❌ 0 は Ruby では truthy → if bn_ai_analysis_count? が常に true になる
def bn_ai_analysis_count?
  count > 0
end

# ✅ Integer を返してビュー側で > 0 で判定
def bn_ai_analysis_count   # ? なし
  count  # 0以上の整数
end
```

ビュー側での判定:
```erb
<% if (ai_count = bn_ai_analysis_count) > 0 %>
  <span class="..."><%= ai_count %></span>
<% end %>
```

<br>

`bn_must_incomplete_count` も同様の設計。コメントに「`?` を外した理由」を明記しておくこと。

<br>

### 140. 非同期タイマー競合は「呼び出し元でキャンセル」するのが最も確実（#H-2）

<br>

close()のsetTimeout(300ms)が_openMobile()の実行後に完了すると<br>
`style.transition = "none"` が後から上書きされ、2回目のスライドインアニメーションが消えるバグが発生した。<br>
`getComputedStyle(el).transition` で「none」が残っていることを発見。<br>
「タイマーが終わるのを待つ（350ms待機）」は UX を犠牲にする回避策であり、<br>
**open()の冒頭でclearTimeout(_closeTimer)してタイマー自体をキャンセルする**のが正しい設計。<br>
タイマーをキャンセルした後は `style.cssText = ""` でインラインスタイルを完全クリアし、<br>
`requestAnimationFrame` を二重呼び出しすることでブラウザが確実に1フレーム描画してからアニメーション開始する。

<br>

```javascript
open() {
  // 閉じるアニメーション中に再度開かれた場合、タイマーをキャンセルする
  if (this._closeTimer) {
    clearTimeout(this._closeTimer)
    this._closeTimer = null
  }
  ...
  // style.cssText="" でインラインスタイルを完全クリアしてクラスのみで制御
  this.sheetPanelTarget.style.cssText = ""
  ...
  // requestAnimationFrame 二重呼び出しで確実に1フレーム後にスライドイン開始
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      this.sheetPanelTarget.classList.remove("translate-y-full")
      this.sheetPanelTarget.classList.add("translate-y-0")
    })
  })
}
```

<br>

### 141. User.unscoped.delete_all が seeds.rb での唯一の安全なユーザー削除手段（#H-5）

<br>

`User.destroy_all` は開発環境でも `before_destroy :prevent_physical_destroy` コールバックが発火し<br>
`RuntimeError: 物理削除は禁止されています` が発生する。<br>
これは F-6 で実装した退会ポリシーのガードが seeds.rb にも影響するため。<br>
`User.delete_all` は `scope :active`（`deleted_at IS NULL`）が適用され退会済みユーザーが残る。<br>
`User.unscoped.delete_all` はコールバックとデフォルトスコープの両方を回避してSQLで直接削除する。<br>
seeds.rb でユーザーをリセットする場合は必ず `unscoped.delete_all` を使うこと。<br>

```ruby
# ❌ destroy_all → prevent_physical_destroy が発火して RuntimeError
User.destroy_all

# ❌ delete_all → scope :active (deleted_at IS NULL) が適用されて退会済みが残る
User.delete_all

# ✅ unscoped.delete_all → コールバックもスコープもバイパスして全件削除
User.unscoped.delete_all
```

<br>

「既存ユーザーがいない状態でも問題なかった」理由は、<br>
`prevent_physical_destroy` の `raise` は `before_destroy` コールバックのため<br>
削除対象レコードが0件のとき `destroy_all` は何もしない（コールバックも発火しない）から。<br>
ユーザーが存在する状態で初めてエラーが発生するため、開発初期に気づかなかった。

<br>

### 142. require_unlocked_unless_onboarding は二重条件チェックで不正スキップを防ぐ（#H-5）

<br>

PDCAロック中でもオンボーディング経由では習慣を作成できる設計にする際、<br>
`params[:from_onboarding] == "true"` だけを条件にすると<br>
通常フォームに `from_onboarding=true` を追加するだけでロックをバイパスできてしまう。<br>
`first_login_at.nil?`（オンボーディング未完了ユーザー）との AND条件を加えることで<br>
「初回ユーザーがオンボーディング経由で操作する場合のみ」に限定できる。<br>

```ruby
def require_unlocked_unless_onboarding
  # オンボーディング経由（from_onboarding=true）かつ初回ユーザー（first_login_at未設定）の場合はスキップ
  return if params[:from_onboarding] == "true" && current_user.first_login_at.nil?
  require_unlocked
end
```

<br>

オンボーディング完了時に `first_login_at` が記録されるため、<br>
完了後は `first_login_at.present?` になってスキップ条件が外れる自己終了設計になっている。

<br>

### 143. importmap の importmap:cache のキャッシュ問題はブラウザキャッシュ強制クリアで解消する（#H-5）

<br>

Stimulus コントローラーを新規追加（`onboarding_template_controller.js`）した後、<br>
ブラウザで「コントローラーが読み込まれていない」症状が発生することがある。<br>
原因は importmap のブラウザキャッシュ（`importmap.json` のキャッシュ）が古いままのため。<br>
`Cmd+Shift+R`（Mac）/ `Ctrl+Shift+R`（Windows）で強制リフレッシュするか、<br>
DevTools → Application → Storage → Clear site data で解消できる。<br>
`docker compose exec web bin/rails importmap:cache` は開発環境では不要だが、<br>
新規コントローラー追加後にキャッシュ問題が疑われる場合は試してみること。

<br>

### 144. iOS Safari の input 自動ズーム防止は text-base（16px）の全フォーム統一で解決する（#H-6）

<br>

iOS Safari は 16px 未満のフォントサイズを持つ `input` / `textarea` / `select` をタップすると<br>
ページを自動ズームする仕様がある。ズーム後はユーザーが手動で縮小する必要があり UX を著しく損なう。<br>
Tailwind の `text-base`（= 16px）を全フォームの入力要素に統一することで防止できる。<br>
`text-sm`（14px）が Tailwind のデフォルト的な使われ方のため見落としやすく、<br>
フォームを新規作成するたびに意識的に `text-base` を選ぶ習慣をつけること。

<br>

```ruby
# ❌ text-sm（14px）→ iOS でタップ時に自動ズームが発生する
class: "w-full px-4 py-3 border border-gray-300 rounded-md text-sm focus:ring-2 ..."

# ✅ text-base（16px）→ 自動ズームが発生しない
class: "w-full px-4 py-3 border border-gray-300 rounded-md text-base focus:ring-2 ..."
```

<br>

対象は `input` だけでなく `textarea`（振り返り入力・PMVV入力・音声入力フィールド）と<br>
`select`（通知設定のドロップダウン等）も含む。<br>
パーシャル（`_voice_field.html.erb` 等）を修正することで複数ページに一括適用できる。

<br>

### 145. WCAG 2.1 のタップ領域 44px 確保は py-3 が基準値（#H-6）

<br>

スマホのタップ操作において、WCAG 2.1 達成基準 2.5.5 は最低 44×44px のタップ領域を推奨している。<br>
Tailwind の `py-3`（上下 12px 余白）+ テキスト高さ（約 20px）= 約 44px になるため、<br>
フォームの送信ボタン・キャンセルボタンは `py-2`（約 36px）や `py-2.5`（約 40px）ではなく<br>
最低 `py-3` を使うことを標準とする。

<br>

### 146. CSS Grid 内のカード高さ統一は h-full + flex で実現する（#H-6）

<br>

`grid-cols-3` で並べた優先度カード（Must/Should/Could）で、<br>
説明文が2行になるカードだけ高さが揃わない問題が発生した。<br>
CSS Grid は各セルを「最も高いセル」に合わせる仕様があるため、<br>
`label` に `h-full` を追加することでセルの高さいっぱいに広がる。<br>
さらに内側の `div` に `h-full flex flex-col items-center justify-center` を追加することで、<br>
アイコン・タイトル・説明文が縦中央揃えになり、3カードが常に同一高さで表示される。<br>

```html


  
    アイコン / タイトル / 説明文
  

```

<br>

### 147. Empty State は「パーシャル化 + CTA + testid」の3点セットで設計する（#H-7）

<br>

Empty State（データ0件時の案内UI）を各画面に個別実装すると、<br>
デザイン変更のたびに全ファイルを修正する必要が生じる。<br>
共通パーシャル化により1ファイルの変更が全画面に反映されるため、<br>
レビュー指摘（py-10への変更・font-semibold追加等）も1箇所の修正で完結した。

<br>

**CTAの出し分けは「渡さない = 非表示」で設計する:**<br>
ロック中はCTAボタンを表示しない設計が必要だが、<br>
パーシャル内に `if @locked` を書くとパーシャルがコントローラーの状態を知る必要が生じ責務が混在する。<br>
`cta_label: nil` を渡せばボタンが表示されない設計にすることで、<br>
パーシャルはロック状態を知らなくてよくなる（単一責任の原則）。

<br>

**testid は変更に強いテストの要（#C-6との一貫性）:**<br>
`analytics_controller_test.rb` が参照していた `data-testid="analytics-empty-state"` は<br>
パーシャル化後も `testid: "analytics-empty-state"` を明示的に渡すことで維持した。<br>
CSSクラスやHTML構造が変わってもtestidが残る限りテストは壊れない。

<br>

### 148. `render partial: locals:` の明示形式は意図が伝わりやすい（#H-7）

<br>

省略記法 `render "shared/empty_state"` でも動作するが、<br>
`render partial: "shared/empty_state", locals: { icon: "📋", ... }` と書くことで<br>
「パーシャルにローカル変数を渡している」という意図がコードレビュー時に明確に伝わる。<br>
また省略記法はRailsのバージョンや名前空間の設定によって解決先が変わるリスクがあるため、<br>
共通パーシャルのような「多くの画面から呼ばれるファイル」ほど明示形式が安全。

<br>

### 149. py-16 はカード内のEmpty Stateには大きすぎる（#H-7）

<br>

ページ全体に単独表示するEmpty Stateでは `py-16`（64px）でも問題ないが、<br>
ダッシュボードの「今週の習慣達成率」カード内に配置する場合はカード自体の高さが<br>
大きく膨らんでレイアウトバランスが崩れる。<br>
外部レビューの指摘を受けて `py-10`（40px）に調整した。<br>
Empty Stateの余白設計は「どこに配置されるか」を考慮してデフォルト値を決めること。<br>
汎用パーシャルのデフォルト値は「最も使われる文脈」に合わせ、<br>
例外的な文脈では `cta_class` のようなオーバーライド手段を用意するのがよい設計。

<br>

### 150. `t.references` に `index: false` を明示して重複インデックスを防ぐ（#H-8）

<br>

Rails 7 の `t.references` はデフォルトで `index: true`（通常インデックス）を自動付与する。<br>
同一カラムに対して `add_index` で UNIQUE インデックスも追加すると、<br>
PostgreSQL が重複インデックス警告を出してパフォーマンスが低下する。<br>
UNIQUE インデックスのみを管理したいカラムは `t.references` に `index: false` を明示し、<br>
`add_index` の UNIQUE インデックスだけを残す設計にすること。

<br>

```ruby
# ❌ 重複インデックスが作られる
t.references :user, null: false, foreign_key: true
add_index :ai_user_profiles, :user_id, unique: true  # 通常 + UNIQUE の二重

# ✅ index: false で通常インデックスを抑制し UNIQUE のみ管理
t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
add_index :ai_user_profiles, :user_id, unique: true, name: "index_ai_user_profiles_on_user_id_unique"
```

<br>

### 151. jsonb カラムには必ず `default: {}, null: false` を付与する（#H-8）

<br>

jsonb カラムに `default` を指定しないと、レコード作成直後に `nil` が入る場合がある。<br>
サービス側で `profile.habit_patterns[:strong]` のようにハッシュとしてアクセスすると<br>
`NoMethodError: undefined method '[]' for nil` が発生する。<br>
`default: {}, null: false` を付与することで、初回作成直後でも<br>
nil チェックなしに安全にアクセスできる。

<br>

### 152. モデルの `stale?` が参照する定数はサービス側の定数に一元化する（#H-8）

<br>

「7日以上古いか」という閾値を `AiUserProfile::STALE_DAYS = 7` と<br>
`UserContextBuilderService::STALE_DAYS = 7` の2箇所で定義すると、<br>
将来どちらかを変更したときに不整合が生まれる（定数の二重管理）。<br>
`AiUserProfile#stale?` から `UserContextBuilderService::STALE_DAYS.days.ago` を<br>
参照する設計にすることで、定数の定義を1箇所に集約できる。

<br>

### 153. rescue はエラー種別ごとに分類してログ解析を容易にする（#H-8）

<br>

`rescue => e`（`StandardError` 全捕捉）だけでは、バリデーションエラー・DB制約違反・<br>
ネットワークエラーを区別できずログ解析が困難になる。<br>
少なくとも以下の3段階に分類するとエラー対応の効率が上がる。<br>

<br>

| rescue 対象 | ログ出力 | 意味 |
|:---|:---|:---|
| `ActiveRecord::RecordInvalid` | バリデーションエラー | uniqueness 違反など |
| `ActiveRecord::StatementInvalid` | DBエラー | UNIQUE インデックス競合など |
| `StandardError` | 予期しないエラー | 上記以外の全エラー |

<br>

### 154. `.pluck` は preload を無視して常にSQLを発行する（#H-9）

<br>

`includes(:habit_excluded_days)` で preload しても、モデルメソッド内で<br>
`habit_excluded_days.pluck(:day_of_week)` を使うと、ロード済み association を無視して<br>
毎回新しい SELECT が発行される。一覧ページでは習慣数だけクエリが飛び N+1 になる。<br>
`.map(&:day_of_week)` に変えると preload 済み配列を読むだけで追加クエリは0件になる。<br>
bullet の「Unused Eager Loading detected」は、preload したのに reader 経由で使われていない<br>
（＝`.pluck` 等でバイパスしている）ことを知らせるシグナルである。

<br>

```ruby
# ❌ preload を無視して習慣ごとに SELECT が飛ぶ（N+1 + Unused Eager Loading 警告）
def excluded_day_numbers
  habit_excluded_days.pluck(:day_of_week).sort
end

# ✅ preload 済み association を使う（追加クエリ0件）
def excluded_day_numbers
  habit_excluded_days.map(&:day_of_week).sort
end
```

<br>

### 155. Issueのチェックリストより「実コード」を優先する（#H-9）

<br>

Issue に「`includes(:habit_records)` を追加」とあっても、実装が既に<br>
`group(:habit_id)` 集計＋ハッシュ参照で N+1 を解消している場合、<br>
`includes` を足すと全レコードをメモリに eager load するだけで逆効果になる。<br>
AI提案モーダルのように `actions_json`（JSONB）から描画していて<br>
`ai_proposed_*` テーブルを参照しないケースでは `includes` は no-op。<br>
チェックリストを機械的に消化せず、実コードを bullet で検証してから対応を決めること。

<br>

### 156. リアルタイム通知バナーを「✖まで残す」には閉じた状態をサーバーに保存する（#H-9）

<br>

Turbo Stream の broadcast 専用バナー（プレースホルダは空div）は、<br>
ライブ配信の瞬間だけ表示され、リロードすると必ず消える。<br>
「✖を押すまでリロード後も残す」には、クライアント側で hidden にするだけでは不十分で<br>
（リロードで復活する）、「閉じた日時」を `user_settings` に保存し、<br>
サーバー描画時に「最新分析の `created_at` > 閉じた日時」で復元表示を判定する必要がある。<br>
再分析すると新しい分析の `created_at` が閉じた日時を上回るため自然に再表示される。

<br>

### 157. 「actions_json の有無」だけで分析完了を判定すると危機介入スキップを誤判定する（#H-10）

<br>

ダッシュボードの「振り返りAI分析中」判定を<br>
`ai_analyses.latest.where.not(actions_json: nil).first` で行っていたため、<br>
危機介入（#D-5）でスキップされたレコード（`crisis_detected: true` / `actions_json: nil`）が<br>
最新になると「分析結果が1件も無い＝分析中」と誤解釈され、スピナーバナーが永久表示された。<br>
`is_latest: true` は部分ユニークインデックスで「1振り返り＝最新1件」が保証されているので、<br>
`actions_json` で絞り込まずに最新1件をそのまま取得し、`crisis_detected` で分岐するのが正しい。<br>
`@reflection_crisis_skipped` を立てて pending 条件に `!@reflection_crisis_skipped` を加え、<br>
「分析中（待ち）」と「意図的にスキップ（確定）」を状態として明確に分離することで解消した。<br>
バナー文言は `config/locales/ja.yml` に集約（i18n化）し、テストは文言依存を避けて<br>
`data-testid` で構造検証することで、将来の文言変更に強い回帰テストにした。<br>
教訓: 「無い（nil）」には “これから来る（待ち）” と “来ないと確定した（スキップ）” の<br>
2種類があり、両者を同じ nil で表現すると必ず誤判定を生む。確定状態は専用フラグで区別すること。<br>
なお完了判定を `actions_json` の有無に依存する構造自体は本質的に脆いため、<br>
将来 `status` カラムを導入する際に AiAnalysis の述語メソッドへ切り出すと、より堅牢になる。

<br>

### 158. ヘッダーナビが狭いPC幅で語中改行して読みづらい問題のレスポンシブ対応（ヘッダー改善）

<br>

ナビ項目が7つに増えた結果、md(768px)以上で固定サイズ（`text-sm` / `px-3` / `space-x-4`）のまま<br>
横並びになり、狭いPC幅で1行に収まらず「ダッシュボード」が「ダッシュ／ボード」のように<br>
語中で2行に折り返して読みづらくなっていた。<br>
対策は3点。①各リンクに `whitespace-nowrap` を付け、語中改行そのものを禁止する。<br>
②文字サイズ・左右余白・項目間隔を md / lg / xl のブレークポイントで可変にし、<br>
狭い画面ほど詰めて広い画面ほどゆったり表示する（例: `md:text-xs lg:text-sm`、`md:px-2 lg:px-3`）。<br>
③`aria-hidden` な装飾要素であるユーザー名表示は、窮屈な md 帯では `hidden` で隠し、<br>
lg 以上でのみ表示して横幅を確保する（氏名はログアウトボタンの `aria-label` に含むため支障なし）。<br>
教訓: 項目数が増えるナビは「固定サイズ＋折り返し任せ」だと必ず崩れる。<br>
`whitespace-nowrap` で改行を止め、サイズ自体をブレークポイントで可変にするのが定石。<br>
また `aria-hidden` な装飾要素は、狭い画面で優先的に隠して情報密度を下げてよい。

### 159. 統合テストは「実装に完全一致」させ、存在しないメソッド名で書かない（#I-1）

<br>

テストを実装より先に推測で書くと、存在しないメソッド（`calculate_achievement_rate` 等）や<br>
存在しないenum値（`analysis_state: "none"`）で書いてしまい、実行前に破綻する。<br>
実ファイルを確認し、実在するスコープ（`Task.active`/`Task.overdue`）・メソッド（`weekly_progress_stats`）・<br>
enum（`pending`/`analyzing`/`completed`/`failed`）・ルート（`get "/auth/:provider/callback"`）だけを使って書くのが定石。

<br>

### 160. `db:migrate:status` の `NO FILE` は多重DB構成の正常表示（#I-1）

<br>

`NO FILE` は「マイグレーションファイルが実在するのに表示されない」というバグではない。<br>
`primary`（`db/migrate`）と `cable`（`db/cable_migrate`）の2接続が同一DBを指すため、<br>
`db:migrate:status` は接続ごとに status ブロックを出力し、各接続の `migrations_paths` に無いものが `NO FILE` になる。<br>
原因を切り分ける前に Docker やキャッシュを疑わず、まず出力の構造（接続ごとのブロック）を読むこと。

<br>

### 161. メールのマルチパート本文検証は `decoded` してから照合する（#I-1）

<br>

`mail.body.encoded` は Base64 エンコードされた生の MIME 文字列を返すため、`assert_match(/download_csv/, ...)` が一致しない。<br>
`mail.text_part.body.decoded` / `mail.html_part.body.decoded` で復号してから本文を検証する。<br>
教訓: メール本文のアサーションは「エンコード形式」を意識する。

<br>

### 162. 統合テストが `AiAnalysis` の D-9 検証をすり抜けた本番バグを検出（#I-1）

<br>

PMVV危機検出時の監査 `AiAnalysis`（`purpose_breakdown`）が、`input_snapshot` に5キーを含めていなかったため<br>
#D-9 のスキーマ検証で弾かれ、`create`（非bang）が黙って保存失敗していた。<br>
統合テスト（`AiAnalysis.count` が +1 する期待）がこの「サイレント失敗」を炙り出した。<br>
教訓: `create`（非bang）を使う箇所は「保存失敗が握りつぶされる」ため、テストで永続化まで検証する。

<br>

### 163. 達成率は計算経路で丸めが違う（`floor` vs `round(2)`）ので境界値を経路ごとに検証する（#I-1）

<br>

数値型習慣の達成率は、画面表示用 `Habit#weekly_progress_stats` が `floor`（整数%）、<br>
振り返りスナップショット `WeeklyReflectionHabitSummary.build_from_habit` が `round(2)`（小数2桁）と丸めが異なる。<br>
`149/150` は前者で `99`、後者で `99.33` になる。境界値テストは「どちらの経路か」を意識して分けて書く。

<br>

### 164. Solid Cache は Redis を足さずに PostgreSQL だけでキャッシュを実現する（#I-6）

<br>

Render 無料プランでは Redis は有料アドオンになる。<br>
Solid Cache は既存の PostgreSQL（Neon）に `solid_cache_entries` テーブルを作り、そこをキャッシュストアにする。<br>
`config/cache.yml` で `database:` を指定しなければ `ActiveRecord::Base` のコネクションプールを共有するため、<br>
コネクション数が1本も増えず、Neon の接続上限も `db:migrate:status` のブロック数も変わらない。<br>
GoodJob・solid_cable と合わせて「Redis を足さず PostgreSQL だけで完結させる」構成方針で一貫させた。

<br>

### 165. `SolidCache::Store` は `delete_matched` を実装していない（#I-6）

<br>

Redis や MemoryStore なら `Rails.cache.delete_matched("dashboard:5:*")` でまとめて消せるが、<br>
Solid Cache でこれを呼ぶと `NotImplementedError` で500エラーになる。<br>
そのためキャッシュキーは「消す側がDBを引かずに完全に組み立て直せる材料」だけで構成し、<br>
`Rails.cache.delete(決定的キー)` で1件ずつ確実に消す方式にした。<br>
キー生成と削除は `ApplicationRecord` の1ファイルに集約し、作る側と消す側でキーがズレる事故を防いだ。

<br>

### 166. キャッシュ対象は「重いDBアクセス」だけにし、CPUで済む計算はキャッシュしない（#I-6）

<br>

ダッシュボードの達成率は「習慣記録の集計 ÷ 目標回数」で求まる。<br>
このうちキャッシュしたのは前半（DBへの集計クエリ2本）だけで、後半の割り算は毎回 Ruby で実行する。<br>
`effective_weekly_target`（除外日を考慮した目標回数）は preload 済みの配列を数えるだけで追加クエリ0件のため、<br>
割り算を毎回行っても速度はほぼ変わらず、かつ **目標値や除外日の変更が即座に画面へ反映**される。<br>
「キャッシュするのはDBアクセスだけ。一瞬で終わる計算はキャッシュしない」という原則で、速度と正確さを両立した。

<br>

### 167. フォーム（authenticity_token）は絶対にフラグメントキャッシュに入れない（#I-6）

<br>

`form_with` が生成する `authenticity_token`（CSRFトークン）はユーザーのセッションごとに異なる。<br>
これをフラグメントキャッシュに含めると、トークンが焼き付き、同じユーザーが再ログインした後に<br>
サーバーが期待するトークンと一致せず **422 InvalidAuthenticityToken** で送信が失敗する。<br>
ローカルでは1セッションしか使わないため気づけず、本番で「たまに反映できない」再現困難なバグになる。<br>
18番では `cache @ai_analysis do` で包むのを読み取り専用の表示部だけに限定し、フォームは範囲外に置いた。

<br>

### 168. immutable なレコードは「新レコード＝新ID」でキャッシュが自動失効する（#I-6）

<br>

`cache @ai_analysis` は `ai_analyses/{id}-{updated_at}` を自動でキーにする。<br>
AI再分析は既存レコードを書き換えず `AiAnalysis.create!` で**新しいレコード（新ID）**を作る設計のため、<br>
IDが変わるだけでキャッシュキーが変わり、古いキャッシュは誰にも読まれなくなる（`max_age` で自動掃除）。<br>
この設計により、ISSUE が挙げていた `touch: true` や「AI分析完了時の手動expire」が一切不要になり、<br>
`user_purposes` への無駄な `UPDATE` を1回減らせた。実ログでも再分析時にキーが `43→45` へ自動で切り替わることを確認した。

<br>

### 169. Sentry エラー監視基盤の設計ポイント（#I-5）

<br>

**① `rescue_from StandardError` が Sentry の自動捕捉を無効化する落とし穴**

<br>

本番の `ApplicationController` は `rescue_from StandardError` で 500 画面を描画するため、例外が Rack 層（sentry-rails の自動捕捉ミドルウェア）まで伝播しない。<br>
そのままでは「エラー画面は出るが Sentry には届かない」状態になるため、`render_500` 内で明示的に `Sentry.capture_exception` を呼んで初めて本番エラーが通知される。これが本タスク最大の要点。

<br>

**② JS 監視は self-host 方式（実行時 CDN 非依存）**

<br>

Sentry Browser SDK を `public/sentry/bundle.min.js` として自己ホストし、classic `<script>` で `<head>` の先頭付近から読み込む。<br>
外部 CDN の障害でアプリが巻き添えにならず、importmap 構成とも競合しない。Stimulus/Turbo より前に読み込むことで初期段階の JS エラーも取りこぼさない。

<br>

**③ 「入れる」より「ノイズを出さない」capture 設計**

<br>

監視は通知を増やすほど良いわけではなく、本物の障害が埋もれないことが重要。<br>
404 系は既定除外。LINE 通知は予期しないインフラ障害のみ通知し、Bot 未友達追加(400)・レート上限(429)等の想定内失敗は送らない。<br>
メール送信失敗は再 raise により sentry-rails が自動捕捉するため、手動 capture を足さず二重通知を回避している。

<br>

**④ テスト時の Sentry は「破棄イベント統計」の送信に注意**

<br>

`before_send` で捨てたイベントは Sentry が client reports（破棄統計）として集計し、`Sentry.close` 時に実送信を試みる。<br>
テストでは `config.send_client_reports = false` で無効化し、ダミー DSN への実ネットワークアクセスを断つことで安定させている。

<br>

### 170. Brakeman の EOLRails は「依存の寿命告知」であり CheckEOLRails 名で skip する（#I-2）

<br>

`brakeman -A` の唯一の警告 `EOLRails` は、Rails のサポート期限が近いことを知らせるもので、コードの脆弱性ではない。<br>
`config/brakeman.yml` の `skip_checks` で除外するが、CLI の `--except EOLRails` と異なり **YAML はクラス名 `CheckEOLRails`（Check 付き）** を要求する点に注意。<br>
（本アプリはその後 Rails 8.1 化で 7.2 の EOL が解消したため、この skip は解除した。）

<br>

### 171. AI編集のアクセス制御は URL パラメータではなくセッションで検証する（#I-2 再確認）

<br>

AI提案経由の習慣・タスク編集は、対象 ID を `session[:ai_context_habit_id]` / `session[:ai_context_task_id]`（Rails が暗号化する Cookie）に保存し、<br>
`verify_ai_context` で `@habit.id` / `@task.id` と一致検証する。URL パラメータのフラグではなくサーバー側セッションで完結するため改ざんできない。

<br>

### 172. CSV ダウンロードは MessageVerifier 署名トークンで「期限＋改ざん検知＋所有者照合」を実現する（#I-2 再確認）

<br>

`CsvDownloadTokenService` は `Rails.application.message_verifier("csv_download")`（HMAC・purpose 分離）でトークンを署名し、<br>
`expires_at`（即時5分／非同期24時間）を検証、さらにコントローラで `payload["user_id"] == current_user.id` を照合する三重防御。<br>
Rails 標準の `signed_id` を使わずとも、複数値ペイロードを安全に受け渡せる。

<br>

### 173. Rails 8 では enum のキーワード形式が ArgumentError になる（Rails 8.1 アップグレード）

<br>

Rails 7 の `enum status: { ... }`（キーワード形式）は Rails 8 で **削除**され、`ArgumentError` でモデルが読み込めずアプリが起動しない。<br>
`enum :status, { ... }`（位置引数形式）へ全件変換が必須。`_prefix:` / `_suffix:` も非アンダースコアの `prefix:` / `suffix:` に変わる。<br>
（本アプリは既に位置引数形式だったため変更ゼロで済んだが、アップグレード前に `grep -rn 'enum ' app/models` で全数確認するのが定石。）

<br>

### 174. gem をイメージに焼き込む Docker 構成では Gemfile.lock 変更時に再ビルドが必要（Rails 8.1 アップグレード）

<br>

`Dockerfile` が `COPY Gemfile Gemfile.lock` → `RUN bundle install` で gem をイメージに焼き込み、かつ `docker-compose.yml` に `/usr/local/bundle` のボリュームが無い構成では、<br>
`bundle update` はコンテナの一時レイヤーに入るだけで、`docker compose down`→`up` で旧バージョンへ逆戻りする。<br>
Gemfile.lock を変えたら **`docker compose build` で焼き直す**のが確実（`restart` はそのセッション内でのみ有効）。

<br>

### 175. app:update は差分確認（d）で手動統合し、load_defaults は段階移行する（Rails 8.1 アップグレード）

<br>

`bin/rails app:update` の上書き確認で `a`（全上書き）を選ぶと、CSP・filter_parameter・本番設定などのカスタム初期化ファイルが Rails 標準版で消える。<br>
`d`（diff）で差分を確認して手動統合し、`config.load_defaults` は一旦現行のまま維持 → `new_framework_defaults` を 1 つずつ有効化して段階移行するのが安全。<br>
（万一上書きしても、コミット前なら `git restore` で復旧できる。）

### 176. 無料 PaaS では「深夜 cron」は発火しない前提で設計する（#I-3）

<br>

Render 無料 Web サービスは 15 分アクセスがないとスリープするため、深夜のアプリ内 cron（GoodJob の定時ジョブ）は発火しない。<br>
ストリークのように「毎日更新される保存値」を cron だけに依存させると、記録しても 0 のままになる。<br>
`HabitRecordSaveService` に保存後の `calculate_streak!` を足して cron 非依存でリアルタイム反映しつつ、日次ジョブはバックアップとして残す二重化にした。

<br>

### 177. 付随処理の失敗を主機能（保存）の巻き添えにしない（#I-3）

<br>

ストリーク再計算は「記録保存」に対する付随処理。トランザクション内で失敗させると PostgreSQL がトランザクションを汚染し、記録保存まで巻き添えでロールバックされる。<br>
再計算は **トランザクションの外**で実行し、`rescue StandardError` で分離。失敗しても記録は保存済みのまま返し、失敗は `Sentry.capture_exception` で可視化する（握りつぶさない）。

<br>

### 178. CSP `form-action` はリダイレクト先まで検査される（#I-3）

<br>

Chrome / Safari はフォーム送信後の 302 リダイレクト先も `form-action` で検査する（Firefox は検査しない）。<br>
OmniAuth の「/auth/xxx へ POST → 認可サーバーへリダイレクト」で、リダイレクト先が許可リストに無いとブロックされる。<br>
`:https`（過度に広い）ではなく `https://*.line.me` のように **必要なドメインだけ**を許可するのが安全。

<br>

### 179. Rails 標準ヘルスチェック `/up` は catch-all より前に置く（#I-3）

<br>

`match "*path"` の catch-all を末尾に置くルーティングでは、`/up`（`rails/health#show`）を明示的に、かつ **catch-all より前**に定義しないと 404 に飲み込まれる。<br>
Render のヘルスチェックが 200 を受け取れず不健全判定になり得るため、ルート先頭で定義する。

<br>

### 180. Performance スコアの頭打ちは TTFB（ホスティング）で切り分ける（#I-3）

<br>

Lighthouse の Performance が上がらないとき、まず LCP の内訳で **TTFB（サーバー応答）** の割合を見る。<br>
TTFB が支配的なら未使用 JS 削減や minify を頑張ってもスコアは動かない（無料 PaaS のサーバー速度が要因）。<br>
アプリ側で打てる手（キャッシュ制御・FCP/CLS/TBT の最適化）を尽くしたら、残りは有料プラン / CDN というインフラ判断として切り分ける。

<br>

### 181. `bundle audit` は `bundle exec bundle-audit` で回す（#I-3）

<br>

`bundler-audit` の実行ファイルは Docker の PATH に無いことがあり、`bundle audit`（サブコマンド）も認識されない場合がある。<br>
`docker compose exec web bundle exec bundle-audit check --update` が確実。<br>
CI/手元で定期実行し、`No vulnerabilities found` を保つ（Dependabot と併用で二重の監視）。