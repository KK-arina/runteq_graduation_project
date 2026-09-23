## 🏆 開発を通じて得た主要な教訓

<br>

### タイムゾーン設定は必ず最初に行う

<br>

`config.time_zone = "Tokyo"` を設定しないと Rails は UTC で動作し、<br>
本番環境でロック時刻が9時間ズレる致命的なバグが発生します（Issue #37 で発見）。

<br>

### `Time.current` / `Date.current` を使う

<br>

`Time.now` / `Date.today` はサーバーのローカル時刻を返しタイムゾーン設定が無視されます。<br>
Rails アプリでは必ず `Time.current` / `Date.current` を使用してください。

<br>

### `form_with` の HTTP メソッド自動判定に注意

<br>

`form_with model:` は `persisted? = true` のレコードを渡すと自動で `PATCH` を送信します。<br>
routes に `update` がない設計の場合は `url:` と `method: :post` を明示してください。

<br>

### テストでは値で直接レコードを特定する

<br>

`order(created_at: :desc).first` は fixtures の `created_at` 順序に依存するため不安定です。<br>
`find_by(name: "...")` など値で特定し、`assert_not_nil` でセットで確認してください。

<br>

### 既存マイグレーションは絶対に変更しない

<br>

一度コミット・適用したマイグレーションファイルは修正せず、必ず新しいマイグレーションで対応する。<br>
既存ファイルを変更すると、チームメンバーや本番環境で `rails db:migrate` を実行したとき<br>
「実際のDBと schema.rb の差分」が発生し、原因不明のバグにつながる。<br>
レビューで修正点が見つかった場合も「追加マイグレーション」で対応する（#A-1 で実践）。

<br>

### Docker 環境では `bundle exec` を必ずつける

<br>

`docker compose exec web rails ...` は `rails` コマンドが PATH に存在しない場合にエラーになる。<br>
`docker compose exec web bundle exec rails ...` または `docker compose exec web bin/rails ...` を使う。<br>
`bin/rails` は `bundle exec rails` と同等の Binstub（実行ショートカット）であり、どちらでもよい。

<br>

### UNIQUE 制約は「再実行・再分析」のユースケースを先に考える

<br>

AI 分析テーブルに `UNIQUE(weekly_reflection_id)` のみ設定すると、<br>
プロンプト改善による再分析ができなくなる（UNIQUE 制約違反エラー）。<br>
`is_latest` フラグと部分インデックス `WHERE is_latest = true` を組み合わせることで、<br>
「最新分析は1件のみ」という制約を保ちつつ、過去分析の履歴も残せる設計になる。

<br>

### セキュリティ設計は最初から `token_digest` 方式にする

<br>

パスワードリセットトークンを平文で DB に保存すると、DB 漏洩時に全ユーザーのリセット URL が復元される。<br>
`SecureRandom.hex(32)` で生成した平文トークンをメール URL に含め、<br>
DB には `Digest::SHA256.hexdigest(token)` のみを保存する Devise 方式が安全。<br>
後から変更すると既存トークンが全て無効になるため、最初から実装すること。

<br>

### `disable_ddl_transaction!` は本番インデックス追加の必須知識

<br>

本番環境で `add_index` を通常実行すると、完了までテーブルに書き込みロックがかかりユーザーが操作できなくなる。<br>
`disable_ddl_transaction!` + `algorithm: :concurrently` を使うことでロックなしにインデックスを追加できる。<br>
ただしトランザクション内では使用できないため、マイグレーション内の処理はシンプルに保つこと。

<br>

### マネージド DB では `db:migrate` を使う

<br>

Neon・RDS・PlanetScale などのマネージド DB は「DB 作成権限（`CREATE DATABASE`）」が付与されていない。<br>
`db:prepare`（DB 作成 + マイグレーション）ではなく `db:migrate`（マイグレーションのみ）を使うこと。<br>
`bin/docker-entrypoint` でこの設定を誤ると `exit 1` → デプロイ失敗ループになる（#A-2 で発見）。

<br>

### `exec` を使わないと Graceful Shutdown が機能しない

<br>

`startCommand` や `docker-entrypoint` の最後で Puma を起動する際は必ず `exec` を付ける。<br>
`exec` なしだとシェルが PID 1 のまま残り、Render の SIGTERM が Puma に届かず強制終了される。<br>
`exec bundle exec puma -C config/puma.rb` と書くことで Puma が PID 1 になり正常に Graceful Shutdown できる。

<br>

### Render の環境変数と render.yaml の重複に注意

<br>

`render.yaml` に `sync: false` で定義した環境変数は Render ダッシュボードで手動設定する。<br>
`render.yaml` で `value:` を設定した環境変数は自動でセットされる。<br>
両方で同じ Key を設定すると「Duplicate keys are not allowed」エラーになる。<br>
`DATABASE_URL` を `sync: false` にしているにもかかわらず手動で追加すると重複するため注意（#A-2 で発生）。

<br>

### Puma の `on_worker_boot` は Worker 数が 1 以上のときに必須

<br>

マルチプロセスモード（`WEB_CONCURRENCY >= 1`）では、fork によって DB コネクションが複数 Worker で共有される。<br>
`on_worker_boot` で `ActiveRecord::Base.establish_connection` を呼ぶことで各 Worker が独立したコネクションを確立し直す。<br>
これがないと断続的な「DB コネクションが壊れた」エラーが発生する（特に高負荷時）。

<br>

### GoodJob のバージョンアップはスキーマも一緒に更新する

<br>

GoodJob は 3.x → 4.x でテーブル構成が大きく変わる（3.x: 2テーブル → 4.x: 5テーブル）。<br>
`good_job:update` はバージョンアップ用だが、前提テーブルが存在しないとマイグレーションが失敗する。<br>
古いテーブルを削除してから `good_job:install` を再実行するのが最もクリーンな移行方法。

<br>

### `:async` と `:external` の使い分けを環境ごとに明示する

<br>

GoodJob の `execution_mode` は `config/initializers/` で一括設定せず、<br>
`config/environments/development.rb` と `config/environments/production.rb` に分けて記述する。<br>
一括設定では環境判定ロジックが initializer に混入し、テストや CI での挙動が読みにくくなる。<br>
環境ファイルに分離することで「この環境ではこの設定」が明確になり、意図しない動作を防げる。

<br>

### Gemfile変更後は必ずDockerイメージを再ビルドする

<br>

`docker compose exec web bundle install` を実行してもコンテナ内に gem が反映されない場合がある。<br>
Dockerfile は `COPY Gemfile Gemfile.lock ./` → `bundle install` の順でビルドしているため、<br>
Gemfile を変更した場合は以下の手順が必要。<br>

```bash
# ① ローカルで bundle install を実行して Gemfile.lock を更新する
bundle install

# ② Gemfile.lock が更新されたことを確認する
grep "gem名" Gemfile.lock

# ③ Dockerイメージを再ビルドする（--no-cache でキャッシュを使わない）
docker compose down
docker compose build --no-cache
docker compose up -d
```

<br>

`bundle install` → `docker compose up -d`（再起動のみ）では gem が反映されない。<br>
必ず `docker compose build --no-cache` でイメージを再ビルドすること。

<br>

また Render での本番ビルドは `--frozen` モードで `bundle install` を実行するため、<br>
`Gemfile.lock` のチェックサムが不正（空エントリ）だとビルドが失敗する。<br>
1.530 Your lockfile has an empty CHECKSUMS entry for "acts_as_list"
このエラーが出た場合は `docker compose exec web bundle install` でローカルの `Gemfile.lock` を更新し、<br>
更新された `Gemfile.lock` を必ずコミットして push すること。

<br>

### APIキーは絶対にコードに直書きしない・チャットに貼らない

<br>

Resend の API キー（`re_` から始まる文字列）をコードに直書きすると GitHub に公開され悪用される。<br>
チャットや Issue に貼り付けた場合も同様にリスクがあるため、以下の対応を即座に実施する。<br>

<br>
```
1. Resend ダッシュボード → API Keys → 漏洩したキーを削除
2. 新しいキーを作成
3. Render ダッシュボード → Environment → 新しいキーの値に更新
```

<br>

環境変数（ENV）を使いコードには変数名のみを記載することで漏洩を防ぐ。<br>
```ruby
# ❌ 直書き（絶対にやってはいけない）
Resend.api_key = "re_xxxxxxxx"

# ✅ 環境変数から取得（正しい方法）
Resend.api_key = ENV.fetch("RESEND_API_KEY", nil)
```

<br>

### マネージド DB への本番テストは Shell 不要の方法を使う

<br>

Render の Free プランは Shell が利用不可（有料プランのみ）。<br>
本番環境での動作確認は以下の方法で代替できる。<br>

```bash
# curl コマンドで Resend API を直接呼び出してメール送信テスト
curl -X POST https://api.resend.com/emails \
  -H "Authorization: Bearer ${RESEND_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "from": "HabitFlow ",
    "to": ["your_email@example.com"],
    "subject": "テスト",
    "text": "テスト送信"
  }'
```

<br>

Resend ダッシュボード（Emails タブ）でステータスが `Delivered` になっていることを確認する。<br>
実際の機能テスト（パスワードリセット等）は各機能の実装時（#F-4 等）に実施する。

<br>

### seeds.rb はマスタデータの「唯一の正」として設計する

<br>

`find_or_create_by!` のブロック方式だと既存レコードが更新されず、<br>
本番環境でテンプレートの説明文や目標回数を修正したい場合に反映できなくなる。<br>
`find_or_initialize_by` + `assign_attributes` + `save!` を使うことで<br>
seeds.rb が「唯一の正（Single Source of Truth）」として機能し、<br>
`rails db:seed` を再実行するだけで本番 DB に変更を反映できる（#A-5 で採用）。

<br>

### `new_record?` は `assign_attributes` の前に確認する

<br>

`find_or_initialize_by` でインスタンスを取得後、`new_record?` で新規/既存を判定するとき、<br>
`assign_attributes` を呼んだ後に `new_record?` を確認すると<br>
インスタンスの内部状態が変化して正確な判定ができなくなる場合がある。<br>
必ず `assign_attributes` の**前**に `is_new = template.new_record?` として値を保存すること（#A-5 で実践）。

<br>

### gem の require 名と gem 名は異なる場合がある

<br>

Ruby の `require` はファイルシステム上のファイル名を指定するため、<br>
gem 名にハイフンが含まれていても require 名はアンダースコアになる。<br>

<br>

| 種類 | 記法 |
|:---|:---|
| gem 名（Gemfile に書く名前） | `rack-mini-profiler` |
| require 名（require に書く名前） | `rack_mini_profiler`（アンダースコア） |

<br>

ハイフンのまま `require "rack-mini-profiler"` と書くと `LoadError` が発生してアプリが起動できなくなる。<br>
gem の README や公式ドキュメントで require 名を必ず確認すること。<br>
また `rescue LoadError` を入れることで万が一の場合でもアプリが起動できなくなることを防げる（#A-6 で実践）。

<br>

### インデックスは「単体」より「実クエリに合わせた複合」が最適

<br>

インデックスはカラム単体で追加するより、実際に発行されるクエリの条件・順序に合わせた<br>
複合インデックスにすることで「Index Only Scan」が可能になり最大限の効果が得られる。<br>

```sql
-- ❌ deleted_at 単体インデックス
--    WHERE user_id=? AND status=0 AND deleted_at IS NULL ORDER BY due_date
--    → user_id / status / due_date はカバーできず Heap Fetch が大量発生

-- ✅ 複合部分インデックス (user_id, status, deleted_at, due_date) WHERE deleted_at IS NULL
--    → インデックスだけで WHERE + ORDER BY が完結（Index Only Scan）
```

<br>

インデックスを追加する前に `EXPLAIN ANALYZE` で実際のクエリプランを確認し、<br>
「Seq Scan」が発生していないかを必ず検証すること（`db/explain_analyze_audit.sql` を参照）。

<br>

### `Bullet.unused_eager_loading_enable` でオーバーフェッチも検出する

<br>

N+1問題（クエリが足りない）だけでなく、`includes` で先読みしたのに使わなかった<br>
「オーバーフェッチ」も `Bullet.unused_eager_loading_enable = true` で検出できる。<br>
N+1を直すために `includes` を追加しすぎると今度は不要なデータを大量取得する問題が起きる。<br>
両方向の最適化を `Bullet` で監視することでパフォーマンスを最良の状態に保てる（#A-6 で設定）。

<br>

### トランザクション内の rescue の位置は必ず外側にする（#A-7）

<br>

`ActiveRecord::Base.transaction do ... rescue ... end` と書くと rescue が transaction ブロックの内側になり、<br>
例外がロールバックをトリガーする前にキャッチされてしまう。DBが中途半端な状態でコミットされる最悪のパターン。<br>
`with_transaction` のような共通ラッパーを作る場合も rescue は書かず、呼び出し元（サービスクラス）に任せる。

<br>

### テストでクラスを直接書き換えるな。stub を使え（#A-7）

<br>

`WeeklyReflection.define_method(:complete!) { raise ... }` のようにクラスを直接書き換えると、<br>
`ensure` での `remove_method` が元のメソッドも削除してしまい、他テストで `NoMethodError` が発生するフレーキーテストになる。<br>
`test_helper.rb` に `require "minitest/mock"` を追加すれば `stub` が使え、<br>
ブロックを抜けると自動で元に戻るため安全。クラスのグローバル状態を汚染しない。

<br>

### `year` / `week_number` など UNIQUE 制約に使うカラムは `before_validation` でセットする（#A-7）

<br>

`before_save` はバリデーション後に実行されるため、UNIQUE 制約のバリデーションには間に合わない。<br>
また fixtures はモデルのコールバックを経由しないため、`before_validation` を追加しても<br>
既存 fixtures には `year: 値` を直接記述する必要がある。<br>
テストが単体では通るが複数テストをまとめて実行すると落ちる（フレーキー）場合は<br>
この種の「DB制約の前提データが nil」問題を疑うこと。

<br>

### `Float()` と `.to_f` は用途で使い分けること（#B-1）

<br>

`"abc".to_f` は `0.0` を返す（変換失敗をサイレントに無視する）。<br>
Controller でユーザー入力を `to_f` のまま変換すると、不正な文字列が `0` として保存されるバグになる。<br>
`Float("abc")` は `ArgumentError` を発生させるため、`rescue` で `nil` を返してモデルのバリデーションで弾ける。<br>
Controller の入力受け取りには必ず `Float()` + `rescue` を使うこと。
```ruby
# ❌ .to_f → "abc" が 0.0 になる（バグの温床）
params[:numeric_value].to_f

# ✅ Float() + rescue → 変換失敗は nil として扱いモデルのバリデーションで弾く
def parse_numeric_value(raw)
  Float(raw)
rescue ArgumentError, TypeError
  nil
end
```

<br>

### `format("%g")` で数値表示を全画面統一すること（#B-1）

<br>

`record.numeric_value.to_f` は `6.0` のように小数点以下のゼロをそのまま出力する。<br>
`format("%g", value.to_f)` を使うことで `6.0` → `6`、`6.5` → `6.5` と自然な表示になる。<br>
入力フィールドの `value` 属性・進捗表示・補正フィールドなど全ての数値表示で統一すること。<br>
1箇所でも `to_f` を使いっぱなしにすると画面間で表示が不統一になる。

<br>

### Stimulus の `connect()` で初期状態を必ず JS 側でも同期すること（#B-1）

<br>

ラジオボタンのカードハイライトをサーバー側（ERB）のみで制御すると、<br>
ユーザーがクリックして選択を切り替えたときに見た目が変わらないバグが発生する。<br>
Stimulus コントローラーに `connect()` を追加し、ページ読み込み時に JS でも初期状態を適用すること。<br>
「初期表示 = ERB の責務、ユーザー操作後 = JS の責務」と責務を分離するのが正しい設計。<br>
ERB 側でスタイルの条件分岐を書きつつ JS 側でも制御するという二重管理は避ける。

<br>

### `find_or_create_by!` に初期値を渡すときは `create_with` を使うこと（#B-1）

<br>

`find_or_create_by!(user:, habit:, record_date:, numeric_value: 0.0)` のように直接渡すと<br>
`numeric_value` も「検索条件」に含まれてしまい、値が異なる既存レコードが見つからず別レコードが作成される。<br>
`create_with(numeric_value: 0.0, completed: false).find_or_create_by!(...)` とすることで<br>
「検索条件はそのまま」「新規作成時のみ初期値をセット」という意図を正しく実装できる。
```ruby
# ❌ 直接渡す → 検索条件にも含まれてしまう
HabitRecord.find_or_create_by!(user: u, habit: h, record_date: d, numeric_value: 0.0)

# ✅ create_with で「新規作成時だけ」適用する
HabitRecord
  .create_with(numeric_value: 0.0, completed: false)
  .find_or_create_by!(user: u, habit: h, record_date: d)
```

<br>

### 差分補正方式で「元データ」と「補正データ」を分離すること（#B-1）

<br>

数値型習慣の週合計を手動補正する際、既存の日次記録を上書きすると履歴が失われる。<br>
「差分を week_end_date のレコードに加算する」差分補正方式を採用することで<br>
各日の記録（事実）はそのまま保持しながら、週合計だけを調整できる。<br>
補正レコードには `is_manual_input: true` を付与し、再補正時に `current_sum` の計算から除外することで<br>
「何度再補正しても元の記録を基準にする」安定した挙動を実現できる。

<br>

### テストの日付衝突は `travel_to` で各テストに別の日付を割り当てること（#B-1）

<br>

`Date.current` を複数テストで共有すると `UNIQUE(user_id, habit_id, record_date)` 制約が衝突し、<br>
「たまに失敗する（フレーキー）テスト」になる。Minitest はテストをランダム順で実行するため<br>
前のテストで同日のレコードが作成されていると次のテストが失敗する。<br>
各テストに `travel_to Time.zone.local(2026, 4, 10, ...)` で異なる日付を割り当てることで解消できる。
```ruby
# ❌ 全テストが同じ日付を使う → ランダム実行で衝突
test "A" do
  travel_to Time.zone.local(2026, 3, 22, 10, 0) do ... end
end
test "B" do
  travel_to Time.zone.local(2026, 3, 22, 10, 0) do ... end  # 衝突！
end

# ✅ 各テストに異なる日付を割り当てる
test "A" do
  travel_to Time.zone.local(2026, 4, 10, 10, 0) do ... end
end
test "B" do
  travel_to Time.zone.local(2026, 4, 11, 10, 0) do ... end
end
```

<br>

### フィクスチャはテーブル追加時に必ず内容を確認する（#B-2）

<br>

`bin/rails generate model` は自動でフィクスチャファイルを生成するが、<br>
`one: {}` は「全カラムが nil のレコード」を意味するため、<br>
`NOT NULL` 制約があるカラムが含まれると `ActiveRecord::NotNullViolation` が発生する。<br>
テストで setup メソッド内で動的にデータを作成する方式の場合、フィクスチャは不要なため削除する。<br>
空ファイルにするより削除する方が将来の事故を完全に防げる。<br>
```bash
# ❌ 自動生成のままにする（one: {} が NOT NULL 違反を引き起こす）
# test/fixtures/habit_excluded_days.yml に one: {} two: {} が残る

# ✅ 不要なフィクスチャファイルを削除する
git rm test/fixtures/habit_excluded_days.yml
```

<br>

### `save_excluded_days!` は必ず先頭で `destroy_all` する（#B-2）

<br>

除外日の更新処理で「チェックを全て外す」操作（`params[:excluded_day_numbers]` が nil）に対応するには、<br>
処理の先頭で `habit.habit_excluded_days.destroy_all` を実行してから保存し直す必要がある。<br>
`return if excluded_day_params.blank?` を先に書くと nil のとき既存データが削除されずバグになる。<br>
「リセット＆セーブ」方式により追加・削除・変更の全パターンを1つのロジックで処理できる。<br>
```ruby
# ❌ blank? チェックを先に書く → チェックを全て外しても除外日が残る
def save_excluded_days!(habit, params)
  return if params.blank?     # ← nil のとき destroy_all が呼ばれない
  habit.habit_excluded_days.destroy_all
  ...
end

# ✅ destroy_all を先頭に置く → 全解除も確実に反映される
def save_excluded_days!(habit, params)
  habit.habit_excluded_days.destroy_all  # ← 常に実行する
  return if params.blank?
  ...
end
```

<br>

### ストリーク計算でお休みモードは「日付単位」で判定すること（#B-3）

<br>

`on_rest_mode?`（現在時刻での判定）をストリーク計算に使うと、<br>
計算時点（AM4:05）ではお休みモードが終了していても、昨日はお休みモード中だったケースを正しく処理できない。<br>
過去日付を遡るストリーク計算では必ず `rest_mode_on_date?(date)` で日付単位の判定をすること。<br>
`rest_mode_until.to_date >= date` でその日がお休み期間内かどうかを正確に判定できる。

<br>

### travel_to のネストは Rails 7.x 以降では RuntimeError になる（#B-3）

<br>

「昨日作成されたレコード」を再現するために `travel_to` を入れ子にするパターンは使えない。<br>
代わりに `update_columns(created_at: 昨日の日時)` で直接タイムスタンプを書き換える方法を使う。<br>
`update_columns` はバリデーションと `updated_at` の自動更新をスキップするため、<br>
任意のタイムスタンプ値を設定できる（テスト専用の手法として有効）。

<br>

### フィクスチャは generate 後に必ず不要ファイルを削除する（#B-3）

<br>

`habit_excluded_days.yml` のように `setup` で動的にデータを作成するテストでは<br>
フィクスチャファイル自体が不要。残っていると存在しない habit_id を参照する外部キー違反が発生し<br>
全テストが `PG::ForeignKeyViolation` で落ちる。<br>
フィクスチャが不要と判断したら `git rm` で完全に削除し `db:test:prepare` でリセットすること。

<br>

### update_columns はストリークのような「計算結果カラム」の更新に最適（#B-3）

<br>

ストリーク計算はバッチジョブで全習慣に対して毎日実行される。<br>
`update!` はバリデーション・コールバック・`updated_at` の更新が走るため処理コストが高い。<br>
`update_columns` はバリデーションをスキップして直接 UPDATE するため高速。<br>
また `updated_at` が更新されないため「ストリーク計算による更新」と「ユーザーによる更新」を区別できる。<br>
`last_streak_calculated_at` に計算時刻を記録することでデバッグや再計算判定にも活用できる。

<br>

### set_habit のスコープは「削除済み除外」と「状態問わず取得」を分けて考えること（#B-4）

<br>

`scope :active`（`deleted_at: nil AND archived_at: nil`）で `set_habit` を絞り込むと、<br>
アーカイブ済み習慣を `unarchive` しようとしたとき RecordNotFound になって操作できない。<br>
かといってスコープなしの `.find` にすると論理削除済み習慣も取得できてしまい既存テストが壊れる。<br>
`where(deleted_at: nil).find` が最適解。「削除済みだけ排除・archived_at は問わない」設計にすることで<br>
アクティブ・アーカイブ済みの両方を操作対象にしつつ、削除済みへの操作は RecordNotFound で弾ける。

<br>

### 状態変更メソッドの状態ガードはモデルに集約すること（#B-4）

<br>

コントローラーで `if @habit.active?` と状態チェックを書くとコントローラーが肥大化し、<br>
将来 API や他コントローラーから同じメソッドを呼んだとき状態ガードが抜ける危険がある。<br>
`archive!` / `unarchive!` の中で `raise RuntimeError` で状態ガードをすることで、<br>
どこから呼んでも不正な状態遷移を防げる（二重アーカイブ・削除済み習慣のアーカイブ等）。<br>
コントローラー側は `rescue RuntimeError => e` で `flash[:alert] = e.message` するだけでよい。

<br>

### `link_to + data-turbo-method` はフォールバックが弱い。状態変更には `button_to` を使うこと（#B-4）

<br>

`link_to + data: { turbo_method: :post }` は Turbo が JS で POST に変換する疑似 POST のため、<br>
JavaScript が無効・Turbo の読み込み失敗時に GET リクエストになってしまう。<br>
`button_to` は `<form method="post">` として HTML に展開されるため JS なしでも確実に POST が送られる。<br>
横並びのボタン群の中で使う場合は `form: { style: "display:inline" }` でレイアウト崩れを防ぐこと。

<br>

### 異常系テストは正常系と同じくらい重要（#B-4）

<br>

正常系（happy path）だけテストしていると「二重アーカイブ」「削除済み習慣のアーカイブ」のような<br>
ありえない操作をしたときにどうなるかが保証されない。<br>
`assert_raises(RuntimeError)` で異常系テストを追加することで状態ガードが正しく機能することを確認できる。<br>
テスト件数が増えても `0 failures, 0 errors` を保てるよう異常系も網羅する習慣をつけること。

<br>

### CSS の `transition` は子孫要素の `fixed` を無効化する（#B-5）

<br>

CSSの仕様として、`transition` / `transform` / `will-change` プロパティを持つ祖先要素があると<br>
その子孫の `position: fixed` 要素が「ビューポート全体」ではなく「その祖先要素」を基準に配置される。<br>
Tailwind の `transition-shadow` クラスもこの罠にはまる。<br>
`fixed inset-0` のモーダルが正しく全画面を覆わない場合はこの仕様を疑うこと。<br>
解決策は `content_for :modals` + `yield :modals` でモーダルHTMLを `</body>` 直前に出力し、<br>
`transition` の影響を受けない場所にDOMを配置すること。<br>
```html


  モーダル  


<!-- ✅ content_for で  直前に出力 → transition の影響を受けない -->
<% content_for :modals do %>
  モーダル  
<% end %>
```

<br>

### Tailwind の `hidden`（`!important`）は `style.display` で上書きできない（#B-5）

<br>

Tailwind の `hidden` クラスは `display: none !important` を適用するため、<br>
JS で `classList.remove("hidden")` 後に `style.display = "flex"` を設定しても<br>
`!important` が勝ってしまい `flex` が適用されない。<br>
モーダルの初期状態を `style="display: none;"` にして Tailwind の `hidden` を使わないか、<br>
または `style.display` を直接制御することで解消できる。<br>
```html





```

<br>

### Stimulus スコープ外のDOM操作は `getElementById` + `addEventListener` を使う（#B-5）

<br>

Stimulus の `target`（`data-controller="xxx"` 要素の内側のみ有効）と<br>
`button_to` が生成する `<form>` タグを同じ `data-controller` 内に置くと<br>
イベントバブリングが `form` 要素を経由して `overlayClick` の判定が崩れる。<br>
モーダルを `data-controller` の外側に配置し、`getElementById()` で取得して<br>
`addEventListener` でイベントを設定することでこの干渉を回避できる。<br>
`stopPropagation` でパネル内クリックのバブリングをブロックし、<br>
オーバーレイに到達するクリックは必ずオーバーレイクリックと判定する設計にする。

<br>

### `content_for` のDOM出力タイミングと Stimulus の `connect()` のタイミングは異なる（#B-5）

<br>

`content_for :modals` はページ末尾（`</body>` 直前）に出力される。<br>
Stimulus の `connect()` は `data-controller` 要素がDOMに接続されたタイミングで呼ばれるが、<br>
ページのレンダリング順によっては `connect()` の時点でモーダルのDOMがまだ存在しないことがある。<br>
`connect()` 内で `getElementById()` が `null` を返してリスナーが設定されないバグを防ぐには、<br>
リスナーの設定を `openMenu()` 内（ユーザーが⋯ボタンをクリックした時点）に移動する。<br>
`_listenersAttached` フラグで初回のみ設定し二重登録を防ぐこと。

<br>

### `current_week_range` を使うテストは `travel_to` で曜日を固定すること（#B-5）

<br>

`current_week_range` は `week_start..today_for_record` の範囲で集計する。<br>
今日が月曜日の場合、`week_start` = 月曜・`today_for_record` = 月曜となり<br>
「今週の範囲が1日分」になって複数日に作成した記録がカウントされないバグが発生する。<br>
週中日（金曜・水曜など）に `travel_to` で固定することで曜日に依存しないテストにできる。<br>
```ruby
# ❌ 今日が月曜なら week_start..monday = 1日分のみ → 複数件作っても1件しかカウントされない
test "3日分の記録が表示されること" do
  3.times { |i| HabitRecord.create!(record_date: week_start + i.days, ...) }
  get habits_path
  assert_match(/3\/7日/, response.body)  # 今日が月曜なら失敗する
end

# ✅ 水曜に固定 → week_start..wednesday = 3日分が確実にカウントされる
test "3日分の記録が表示されること" do
  travel_to Time.zone.parse("2025-01-15 10:00:00") do  # 水曜
    3.times { |i| HabitRecord.create!(record_date: week_start + i.days, ...) }
    get habits_path
    assert_match(/3\/7日/, response.body)
  end
end
```

<br>

### Tailwind の動的クラスは JS や ERB 変数で生成してはいけない（#B-6）

<br>

Tailwind はビルド時にソースコードを静的解析して「使用するクラス一覧」を生成する。<br>
`"bg-#{color}"` のような動的生成や `classList.add("hover:scale-110")` のような JS での動的追加は<br>
Tailwind のビルド対象として認識されず、本番環境で CSS が当たらないバグになる。<br>
動的な値（カラーコード・JS で操作するスタイル）はインラインスタイルか `style` 属性を使い、<br>
`hover:` のような擬似クラスは HTML に直接記述してビルド対象に含めること。<br>
```erb
<%# ❌ 動的クラス → ビルド対象外 %>


<%# ✅ インラインスタイル → 動的カラーコードを安全に適用 %>

```

<br>

### CDN から importmap で ESM 形式を読み込む際はバージョンに注意すること（#B-6）

<br>

importmap は ECMAScript Module（ESM）形式のみ対応している。<br>
`cdnjs.cloudflare.com` の SortableJS `1.15.2` には ESM 版が存在せず 404 になる。<br>
CDN を変更する前に Network タブでステータスコードを確認し、<br>
404 の場合は別の CDN（jsdelivr 等）または別バージョンを試すこと。<br>
`cdn.jsdelivr.net/npm/sortablejs@1.15.0/modular/sortable.esm.js` が ESM 対応の安定版。

<br>

### `display: grid` のコンテナでは SortableJS に `forceFallback: true` が必要（#B-6）

<br>

SortableJS はデフォルトでブラウザのネイティブ Drag & Drop API を使用するが、<br>
`display: grid` のコンテナではドラッグイベントが正常に発火しない場合がある。<br>
`forceFallback: true` を設定することで SortableJS 独自の実装（マウスイベントベース）に切り替わり、<br>
グリッドレイアウトでも正常にドラッグ操作が機能するようになる。<br>
```javascript
// ❌ display:grid では onStart/onEnd が発火しないことがある
Sortable.create(element, { handle: "[data-sort-handle]" })

// ✅ forceFallback: true でグリッドレイアウトに対応
Sortable.create(element, {
  handle: "[data-sort-handle]",
  forceFallback: true,
  fallbackClass: "opacity-75"
})
```

<br>

### Stimulus の Values API を必ず定義してから使うこと（#B-6）

<br>

`this.sortUrlValue` のように Stimulus の Values API を使う場合、<br>
`static values = { sortUrl: String }` の定義が必ないと `undefined` になりエラーになる。<br>
定義が漏れていると「コントローラーは connect されているのに動かない」という分かりにくいバグになる。<br>
Boolean 型（`locked: Boolean`）を使うと HTML の `"true"/"false"` 文字列が自動で `true/false` に変換される。<br>
```javascript
// ❌ static values 未定義 → this.sortUrlValue が undefined
export default class extends Controller {
  connect() {
    fetch(this.sortUrlValue, ...)  // undefined
  }
}

// ✅ 使用する Value を必ず定義する
export default class extends Controller {
  static values = { sortUrl: String, locked: Boolean }
  connect() {
    if (this.lockedValue) return
    fetch(this.sortUrlValue, ...)  // 正しく動作する
  }
}
```

<br>

### ドラッグ&ドロップのロック制御はサーバー・JS・UI の三重防御にすること（#B-6）

<br>

PDCAロック中に並び替えを防止するには以下の三重防御が必要。<br>
UI だけ（ハンドル非表示）では開発者ツールで DOM を操作されると突破できる。<br>
JS だけでも Rails の PATCH エンドポイントに直接リクエストされると突破できる。<br>

<br>

| 防御層 | 実装 | 効果 |
|:---|:---|:---|
| UI 層 | `<% unless @locked %>` でハンドルボタンを出力しない | ユーザーにドラッグ操作の導線を見せない |
| JS 層 | `if (this.lockedValue) return` で SortableJS を初期化しない | DOM 操作でハンドルを追加されても並び替え不可 |
| サーバー層 | `before_action :require_unlocked, only: [:sort]` | 直接 HTTP リクエストを送っても 403/redirect |

<br>

### `insert_at` のインデックスは 1 始まりであることに注意すること（#B-6）

<br>

`each_with_index` のインデックスは 0 始まりだが、<br>
`acts_as_list` の `insert_at(n)` は 1 始まりの position を設定する。<br>
`habit.insert_at(index)` ではなく `habit.insert_at(index + 1)` とすること。<br>
また `each_with_index` は `next` でスキップしてもインデックスは進む点に注意。<br>
存在しない ID（99999 等）を混入させた場合、スキップされた分 position にギャップが生じる。<br>
```ruby
# ❌ 0始まりのまま渡す → position=0 は acts_as_list の想定外
habit_ids.each_with_index do |id, index|
  habit.insert_at(index)  # 0始まり
end

# ✅ +1 して 1始まりにする
habit_ids.each_with_index do |id, index|
  habit = current_user.habits.find_by(id: id)
  next unless habit
  habit.insert_at(index + 1)  # 1始まり
end
```

<br>

### Turbo Stream 差し替え後はJS側の要素参照が無効になる（#B-7）

<br>

`window.Turbo.renderStreamMessage(responseText)` で DOM が差し替えられると、<br>
差し替え前の `this.memoToggleTarget` などへの参照は無効になる。<br>
差し替え後に `this.xxx` を呼ぶとエラーになるか、存在しない要素を操作するサイレントバグになる。<br>
Turbo Stream 差し替え後の UI 状態（💬の色・メモエリアの展開状態）は<br>
サーバーから返ってくる HTML（ERB）側で制御するのが正しい設計。<br>
JS 側では「差し替えを依頼する」だけに留め、結果の反映はサーバーに任せること。

<br>

### Stimulus のターゲットは `data-controller` の子孫要素のみ認識される（#B-7）

<br>

`data-controller="habit-record"` が付いた要素の「外側（兄弟要素・親要素）」に<br>
`data-habit-record-target="memoArea"` を置くと `Missing target element` エラーになる。<br>
Stimulus のスコープルール: `data-controller` が付いた要素の**子孫要素のみ**がターゲットとして認識される。<br>
メモエリアとチェック行を同じスコープに入れるには、両方を含む最外側の要素に `data-controller` を移動する。<br>
```html

  
  チェック行（💬ボタン含む）
  

  
  メモエリア（memoArea ターゲット）
```

<br>

### CSP の `nonce_directives` と Turbo Drive は競合する（#B-7）

<br>

`nonce_directives = ["script-src"]` を設定すると、Turbo Drive がページ遷移時に<br>
body を差し替えるとき新しい body の `<script>` タグに古いページの nonce が引き継がれず<br>
`Executing inline script violates CSP` エラーで Turbo Stream の DOM 差し替えがブロックされる。<br>
Rails 7 + Importmap + Turbo の構成では `nonce_directives = []` として nonce 制御を無効化し、<br>
`script_src :self, :https, :unsafe_inline` で Importmap のインラインスクリプトを許可するのが現実的な解決策。<br>
`script_src :self` を維持することで外部ドメインからのスクリプト注入は引き続きブロックされる。

<br>

### `NOT_PROVIDED` センチネル値で「未送信」と「nil送信」を区別する（#B-7）

<br>

デフォルト引数を `nil` にすると「引数が送られなかった（= 更新不要）」と<br>
「`nil` が明示的に送られた（= 空で上書き）」を区別できない。<br>
`:not_provided` シンボルをデフォルト値に使うことで<br>
「この引数は送られなかった → DBを変更しない」という意図を明示できる。<br>
```ruby
NOT_PROVIDED = :not_provided

def initialize(memo: NOT_PROVIDED)
  @memo = memo
end

# NOT_PROVIDED のままなら update_params に含めない → DB は変更されない
update_params[:memo] = @memo.presence unless @memo == NOT_PROVIDED
```

<br>

### 各 Stimulus アクションは「自分の担当項目だけ」送ること（#B-7）

<br>

`toggle()`（チェック操作）時に `memo` も一緒に送ると、<br>
ユーザーがメモを入力中（未保存）にチェックを操作した場合に入力途中のメモが誤って保存される。<br>
`saveMemo()` 時に `completed` を送ると、メモ保存がチェック状態をリセットするバグになる。<br>
各操作は「自分の担当項目だけ」を送り、サーバー側の `NOT_PROVIDED` 設計と組み合わせることで<br>
「操作した項目だけが更新される」安全な部分更新を実現できる。<br>
```javascript
// toggle: completed だけ送る
const body = `completed=${completed ? "1" : "0"}`

// saveNumeric: numeric_value だけ送る
const body = `numeric_value=${encodeURIComponent(numericValue)}`

// saveMemo: memo だけ送る
const body = `memo=${encodeURIComponent(memoValue)}`
```

<br>

### Bullet の誤検知は `add_safelist` で抑制する（#C-1）

<br>

`includes` で先読みした関連を Ruby レベルの条件分岐後に参照する場合、<br>
Bullet は「使っていない」と誤判定して `AVOID eager loading` 警告を出す。<br>
`includes` を削除すると N+1 が発生するため削除してはいけない。<br>
`Bullet.add_safelist` でモデルと関連名を指定して誤検知だけを抑制する。<br>
```ruby
# ❌ includes を削除 → チェック型習慣が増えると N+1 が発生する
@habits = current_user.habits.active

# ❌ unused_eager_loading_ignore= → Bullet にこのメソッドは存在しない
Bullet.unused_eager_loading_ignore = { "Habit" => [:habit_excluded_days] }

# ✅ add_safelist → 誤検知だけを抑制・N+1 監視は継続される
Bullet.add_safelist(
  type:        :unused_eager_loading,
  class_name:  "Habit",
  association: :habit_excluded_days
)
```
正しいメソッド名は `Bullet.methods.grep(/safe|white|skip|allow/)` で確認できる。<br>
`ignore` 系・`whitelist` 系のメソッド名は存在しないため注意すること。

<br>

### `travel_to` はブロックなし + `teardown` で `travel_back` すること（#C-1）

<br>

`setup` 内で `travel_to fixed_time do ... end` のブロック形式を使うと、<br>
ブロックを抜けた瞬間に時間が元に戻り、テスト本体（`test "..." do`）はリアル時間で動いてしまう。<br>
日付依存のテストが「ローカルでは通るが CI で落ちる」不安定なテストになる原因。<br>
```ruby
# ❌ ブロック形式 → setup を抜けると時間が戻る
def setup
  travel_to fixed_time do
    @user = User.create!(...)  # ← ここは固定時間
  end
  # ← ここから先はリアル時間（テスト本体もリアル時間で動く）
end

# ✅ ブロックなし + teardown で travel_back
def setup
  travel_to fixed_time      # ← テスト全体で固定される
  @user = User.create!(...)
end

def teardown
  travel_back               # ← 次のテストに影響しないよう後始末
end
```

<br>

### `GROUP BY` と `ORDER BY` の競合は `unscope(:order)` で解消する（#C-1）

<br>

Rails の scope はチェーンすると `ORDER BY` が引き継がれる。<br>
`scope :active` に `ORDER BY due_date` が含まれている場合、<br>
`group(:priority).count` と組み合わせると PostgreSQL が以下のエラーを出す。<br>
PG::GroupingError: column "tasks.due_date" must appear in the GROUP BY clause

<br>

`unscope(:order)` で `ORDER BY` 句だけを除去してから `GROUP BY` を実行することで解消できる。<br>
`WHERE` 句（`deleted_at IS NULL` 等）は `unscope(:order)` の影響を受けないため安全。<br>
```ruby
# ❌ scope :active の ORDER BY が GROUP BY と競合
priority_counts = base_tasks.not_archived.group(:priority).count

# ✅ ORDER BY を除去してから GROUP BY
priority_counts = base_tasks.not_archived.unscope(:order).group(:priority).count
```

<br>

### Tailwind の `peer-checked` は「外れた状態」を自動リセットしない（#C-1）

<br>

`peer-checked` は「ラジオボタンが checked のとき」にスタイルを適用するが、<br>
「他のラジオボタンが選ばれて checked が外れたとき」を自動で元に戻す機能はない。<br>
3枚カード（Must/Should/Could）で1つを選ぶと他の2枚の選択スタイルが残るバグになる。<br>
Stimulus コントローラーで全カードをリセットしてから選択カードだけをアクティブにすることで解決する。<br>
```javascript
// ✅ 全カードをリセット → 選択カードだけアクティブにする
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
      card.classList.remove(...activeClasses)  // ← 外れた状態を確実にリセット
      card.classList.add(...inactiveClasses)
    }
  })
}
```

<br>

### `before_validation` でデフォルト値を設定して NOT NULL 制約違反を防ぐ（#C-1）

<br>

フォームで `include_blank` を使うと未選択時に空文字が送信される。<br>
enum カラムは空文字を `nil` に変換しようとするが、`NOT NULL` 制約があると `PG::NotNullViolation` になる。<br>
`before_validation` で空文字・nil をデフォルト値に変換することで<br>
DB制約を安全に満たしつつフォームの利便性（任意選択）も保持できる。<br>
```ruby
# ❌ include_blank + NOT NULL カラム → 未選択で PG::NotNullViolation
f.select :task_type, [...], { include_blank: "選択してください" }

# ✅ before_validation でデフォルトを設定
before_validation :set_default_task_type

def set_default_task_type
  self.task_type = "normal" if task_type.blank?
end
```

<br>

### `has_many` の定義漏れは `NoMethodError` で気づく（#C-1）

<br>

`TasksController` で `current_user.tasks` を呼んでも `has_many :tasks` が `User` モデルに定義されていなければ<br>
`NoMethodError: undefined method 'tasks' for an instance of User` が発生する。<br>
テーブルが存在しアソシエーションの定義が漏れているだけのため、エラーメッセージから原因がわかりにくい。<br>
モデルを追加したら必ず親モデル（`User`）に `has_many` / `belongs_to` を追加すること。<br>
外部キー制約（`schema.rb` の `add_foreign_key`）はDB側の制約であり、Rails側の定義とは別物。<br>
```ruby
# ❌ user.rb に has_many がない → NoMethodError
class User < ApplicationRecord
  has_many :habits
  # has_many :tasks が抜けている
end

# ✅ 忘れずに追加する
class User < ApplicationRecord
  has_many :habits
  has_many :tasks, dependent: :destroy  # ← 追加
end
```

<br>

### `includes` した関連を `.to_a` で配列化してビューの `.count` を SQL なしにする（#C-1修正）

<br>

`includes` で関連を先読みしていても、ビューで `.count` を呼ぶと Bullet が<br>
`Need Counter Cache with Active Record size` 警告を出す場合がある。<br>
`.count` は常に `SELECT COUNT(*)` を DB に発行するため、<br>
`includes` 済みのデータでも SQL が追加発行されてしまう。<br>
コントローラーで `.to_a` を付けて配列化し、ビューでは `.size` を使うことで<br>
全ての計算がメモリ上で完結し SQL が発行されなくなる。<br>
```ruby
# ❌ includes 済みでも .count は COUNT(*) SQL を発行する
@habit_summaries = @weekly_reflection.habit_summaries
                                     .includes(:habit)
                                     .order(achievement_rate: :desc)
# ビューで summaries.count → SQL 発行

# ✅ .to_a で配列化 → ビューの .size はメモリ上でカウント
@habit_summaries = @weekly_reflection.habit_summaries
                                     .order(achievement_rate: :desc)
                                     .to_a
# ビューで @habit_summaries.size → SQL なし
```
`.count` と `.size` の使い分け: `count` は常にDB問い合わせ、`size` はロード済みならメモリ参照。<br>
ブロック付きの `.count { |s| s.rate >= 100 }` はRubyの列挙メソッドのためSQLを発行しない。

<br>

### `redirect_to` の `flash:` オプションは Rails では機能しない（#C-1修正）

<br>

`redirect_to path, flash: { unlock: "..." }` と書くと `flash[:flash]` として設定されてしまい、<br>
`flash[:unlock]` として参照しても値が取り出せないバグになる。<br>
`flash` はリダイレクト前に別途セットし、`redirect_to` と2行に分けて書くのが正しい。<br>
```ruby
# ❌ redirect_to の flash: オプション → flash[:flash] に格納されてしまう
redirect_to dashboard_path,
            flash: { unlock: "ロックが解除されました！🔓" }

# ✅ flash を先にセットしてから redirect_to
flash[:unlock] = "ロックが解除されました！🔓"
redirect_to dashboard_path
```
なお `notice:` / `alert:` は Rails が特別に処理するショートカットのため<br>
`redirect_to path, notice: "..."` は正しく動作する。<br>
カスタムキー（`unlock` 等）は必ず2行に分けること。

<br>

### 期限日フォームの `min` には `Date.today` ではなく `Date.current` を使う（#C-1修正）

<br>

`min: Date.today.to_s` はサーバーの OS ローカル時刻（UTC）を参照するため、<br>
JST（UTC+9）環境では「今日」が最大9時間ズレる。<br>
深夜0時〜AM4:00 の時間帯に「昨日」の日付が `min` として設定され、<br>
ユーザーが過去日を選択できてしまうバグが発生する。<br>
Rails アプリでは必ず `Date.current` を使い、`config.time_zone` の設定を正しく参照させること。<br>
```erb
<%# ❌ Date.today → UTC基準のため JST で最大9時間ズレる %>
<%= f.date_field :due_date, min: Date.today.to_s %>

<%# ✅ Date.current → config.time_zone（Tokyo）を参照する %>
<%= f.date_field :due_date, min: Date.current.to_s %>
```

<br>

### Turbo Stream でコントローラーからビューヘルパーを使うには include が必要（#C-2）

<br>

`dom_id` / `content_tag` は `ActionView` のモジュールに属するため、<br>
コントローラーには自動で include されない。<br>
`include ActionView::RecordIdentifier` と `include ActionView::Helpers::TagHelper` を<br>
コントローラーの先頭に追加することで使用できるようになる。<br>
Turbo Stream を多用するコントローラーでは定型的に必要になるため覚えておくこと。

<br>

### SessionsController のパラメータ構造をテストで合わせること（#C-2修正）

<br>

`SessionsController#create` が `params[:session][:email]` でメールを取得する設計の場合、<br>
テストのログイン処理を `params: { email: ..., password: ... }` で書くと<br>
`params[:session]` が `nil` になり `NoMethodError: undefined method '[]' for nil` が発生する。<br>
フォームの `form_with model: :session` に合わせて<br>
`params: { session: { email: ..., password: ... } }` と入れ子にすること。<br>
```ruby
# ❌ params[:session] が nil → NoMethodError
post login_path, params: { email: @user.email, password: "password" }

# ✅ :session キーで入れ子にする
post login_path, params: { session: { email: @user.email, password: "password" } }
```

<br>

### rescue_from がある場合は assert_raises ではなく assert_response :not_found を使う（#C-2修正）

<br>

`ApplicationController` に `rescue_from ActiveRecord::RecordNotFound, with: :render_404` がある場合、<br>
例外はコントローラー内でキャッチされて404レスポンスとして返される。<br>
テストで `assert_raises(ActiveRecord::RecordNotFound)` を使うと例外が伝播しないためテストが失敗する。<br>
代わりに `assert_response :not_found` でHTTPステータス404を確認すること。<br>
```ruby
# ❌ rescue_from がある場合は例外がテストに伝播しない
assert_raises(ActiveRecord::RecordNotFound) do
  patch toggle_complete_task_path(other_task), ...
end

# ✅ レスポンスコードで確認する
patch toggle_complete_task_path(other_task), ...
assert_response :not_found
```

<br>

### Turbo の確認ダイアログは data-turbo-confirm を使う（#C-2修正）

<br>

Rails 7 + Turbo 環境では確認ダイアログのキーが変わっている。<br>
`data: { confirm: "..." }` は Rails 6 以前の書き方で Turbo を使う環境では動作しない。<br>
`data: { turbo_confirm: "..." }` を使うことで Turbo が提供するネイティブの confirm ダイアログが表示される。<br>
```erb
<%# ❌ Rails 6 の書き方 → Turbo 環境では動作しない %>
<%= button_to "すべてアーカイブ", path, data: { confirm: "本当に？" } %>

<%# ✅ Turbo の書き方 %>
<%= button_to "すべてアーカイブ", path, data: { turbo_confirm: "本当に？" } %>
```

<br>

### before_action の実行順序が優先ロジックを破壊する（#C-3）

<br>

`before_action` は登録順に実行されるため、複数の前処理に優先順位がある場合は注意が必要。<br>
`before_action :require_unlocked, only: [:destroy]` と登録すると<br>
アクション内の `ai_generated` チェックより必ず先にロックチェックが実行される。<br>
「ロック中 + AI生成タスク削除」のとき 403 ではなく 302 が返るという優先順位の逆転バグが発生する。<br>
実行順序を明示的に制御したい場合は before_action を使わず、アクション内に直接書くこと。<br>
```ruby
# ❌ before_action → ai_generated チェックより先に実行されて 302 が返る
before_action :require_unlocked, only: [:destroy]

# ✅ destroy 内で明示的に順序を制御
def destroy
  if @task.ai_generated?   # ① 最優先
    render ..., status: :forbidden and return
  end
  return if require_unlocked  # ② 次
  @task.soft_delete
end
```

<br>

### Turbo Stream 再描画で複数行文字列内の `#{}` が評価されない（#C-3）

<br>

`link_to` の `class:` 引数が複数行にまたがる文字列の中で `#{}` を使うと、<br>
通常のページ表示では動作するように見えるが、Turbo Stream の `replace` による再描画時に<br>
`#{}` がそのまま HTML 文字列として出力されるバグが発生する。<br>
文字列結合（`"共通クラス " + (条件式)`）に変更することで確実に評価される。<br>
ERB テンプレート内で Ruby の文字列補間 `#{}` を使う場合は必ず1行に収めるか文字列結合を使うこと。

<br>

### `redirect_to` で 403 を返すには `status:` の明示が必要（#C-3）

<br>

`redirect_to` はデフォルトで 302 を返す。<br>
テストで `assert_response :forbidden` が期待通り通らない場合、<br>
`redirect_to` に `status: :forbidden` を明示しているか確認すること。<br>
```ruby
# ❌ デフォルトは 302
redirect_to tasks_path, alert: "AI生成タスクは削除できません"

# ✅ 明示的に 403 を返す
redirect_to tasks_path, alert: "AI生成タスクは削除できません", status: :forbidden
```

<br>

### travel_to ブロック内のセッション喪失は再ログインで解決する（#C-3）

<br>

`ActionDispatch::IntegrationTest` では `travel_to` ブロック内でセッションが引き継がれない。<br>
`setup` で行ったログインが無効になり `require_login` が先に動いて 302 が返るため、<br>
期待する 403 や 404 が確認できなくなる。<br>
対策: `travel_to` ブロックを使わなくてよいテストは setup の時刻をそのまま使う。<br>
どうしても `travel_to` ブロックが必要なテスト（ロック中テスト等）はブロック内で再ログインする。<br>
```ruby
# ✅ 月曜への時刻移動が必要なテストだけブロック内で再ログインする
travel_to Time.zone.local(2026, 4, 13, 10, 0, 0) do
  post login_path, params: { session: { email: @user.email, password: "password" } }
  delete task_path(task)
  assert_response :redirect
end
```

<br>

### content_for は Turbo Stream では機能しない。パーシャル分離で対応する（#C-4）

<br>

`content_for` はサーバーサイドのフルレンダリング時にのみ機能する。<br>
Turbo Stream で部分更新するとパーシャル内の `content_for` は `yield` に反映されず、<br>
モーダルや特定のDOMが消えるバグになる。<br>
モーダルのような「複数箇所から参照される UI」は最初から独立したパーシャルとして設計し、<br>
`content_for` に頼らずインライン出力する設計にすること。<br>
Turbo Stream で差し替える場合はコントローラーからそのパーシャルを `turbo_stream.replace` で再注入する。

<br>

### 同一 id は必ずページ全体で1つにする（#C-4）

<br>

HTML 仕様では同一ページに同じ `id` は1つだけ許可される。<br>
重複した `id` は `document.getElementById()` の返り値が不定になり、<br>
Turbo Stream / Stimulus のターゲット操作が意図しない要素に当たるバグになる。<br>
`flash-area` のような共通 ID は `application.html.erb` 内で必ず1箇所だけにする。<br>
レビューや実装追加時に「既存の同名 ID がないか」を常に確認すること。

<br>

### Arel は使わず SQL プレースホルダー形式を使う（#C-4）

<br>

Arel の `.constraints.reduce(:or)` のような書き方は可読性が低く、<br>
Rails のバージョンアップで挙動が変わる内部 API のため避けるべき。<br>
OR 条件は named bind variables（`:start` / `:end` 形式）を使ったプレースホルダー形式で書く。<br>
同じ値を複数箇所で使い回せて SQLインジェクション対策も自動で行われる。<br>

```ruby
# ❌ Arel を使う → バージョン差異で壊れるリスクあり・可読性低
tasks.where(
  user.tasks.where(due_date: week_range).arel.constraints.reduce(:or).or(...)
)

# ✅ プレースホルダー形式 → シンプル・安全・Rails 標準
tasks.where(
  "due_date BETWEEN :start AND :end
   OR created_at BETWEEN :start_dt AND :end_dt",
  start: week_start, end: week_end,
  start_dt: week_start.beginning_of_day, end_dt: week_end.end_of_day
)
```

<br>

### ジョブ引数は ID（整数）で渡す。インスタンスは渡せない（#C-5）

<br>

GoodJob はジョブの引数を JSON 形式で `good_jobs.serialized_params` に保存する。<br>
ActiveRecord のインスタンスは JSON シリアライズできないため、<br>
ジョブの引数には必ず id（整数）を渡し、`perform` 内で `find` して再取得する設計にする。<br>
`find` は対象が存在しない場合に `RecordNotFound` を発生させるため、<br>
`ApplicationJob` の `discard_on ActiveRecord::RecordNotFound` と組み合わせることで<br>
タスク削除後に残ったジョブを自動破棄できる。<br>

<br>

```ruby
# ❌ インスタンスを渡す → JSON シリアライズできない
TaskAlarmJob.perform_later(task)

# ✅ id を渡して perform 内で再取得する
TaskAlarmJob.perform_later(task.id)

def perform(task_id)
  task = Task.find(task_id)  # 存在しない場合は RecordNotFound → discard_on で自動破棄
  ...
end
```

<br>

### カウントの並行更新には update_all の DB 側計算を使う（#C-5）

<br>

`user_setting.update_columns(daily_notification_count: user_setting.daily_notification_count + 1)` は<br>
「Ruby が DB から値を読んで計算して書き込む」3ステップのため、<br>
同時実行時に複数プロセスが同じ値を読んでそれぞれ +1 すると実質 +1 しかされない競合が発生する。<br>
`update_all("daily_notification_count = daily_notification_count + 1")` は<br>
DB が直接計算するため原子的操作（atomic）になり競合しない。<br>
カウンターや合計値のような累積計算には必ず DB 側計算方式を使うこと。<br>

<br>

### フィクスチャの自動生成ファイルはモデル作成後すぐに確認・削除する（#C-5）

<br>

`bin/rails generate model` は自動でフィクスチャファイルを生成する。<br>
`one: {}` のまま放置すると全テストが `PG::NotNullViolation` でクラッシュする。<br>
モデル生成後は必ず `cat test/fixtures/モデル名.yml` で内容を確認し、<br>
setup で動的にデータを作成する方式なら即座に削除すること。<br>
B-2・B-3・C-5 で同じ失敗を繰り返したため、これは「生成したら即確認」を鉄則にする。

<br>

### discard_on は例外を外に伝播させない（テストの期待値に注意）（#C-5）

<br>

`ApplicationJob` に `discard_on ActiveRecord::RecordNotFound` があると、<br>
`RecordNotFound` が発生してもジョブが静かに破棄されるだけで例外は外に出ない。<br>
テストで `assert_raises(ActiveRecord::RecordNotFound)` を使うと<br>
「例外が来るはずなのに来ない」としてテストが失敗する。<br>
正しくは `assert_nothing_raised` で「例外が外に出ないこと」を確認し、<br>
`assert_equal 0, ActionMailer::Base.deliveries.size` で副作用がないことを確認する。<br>

<br>

```ruby
# ❌ discard_on がある場合は例外が外に伝播しない
assert_raises(ActiveRecord::RecordNotFound) do
  TaskAlarmJob.perform_now(999_999)
end

# ✅ 例外が外に出ないことを確認する
assert_nothing_raised do
  TaskAlarmJob.perform_now(999_999)
end
assert_equal 0, ActionMailer::Base.deliveries.size
```

<br>

### group(:priority).count のキーは文字列で返る（#C-6）

<br>

Rails の enum カラムを `group().count` すると、キーは整数（0/1/2）ではなく<br>
enum 名の文字列（`"must"/"should"/"could"`）で返る。<br>
`priority_map = Task.priorities.invert` による整数→文字列変換は不要で<br>
`total_counts["must"]` のように直接文字列キーでアクセスできる。<br>
```ruby
# group(:priority).count の実際の返り値
{ "must" => 3, "should" => 5 }  # Integer ではなく String
```

<br>

### Date 型と datetime 型の BETWEEN 比較は in_time_zone を挟む（#C-6）

<br>

`HabitRecord.today_for_record` は `Date` 型を返す。<br>
`created_at`（datetime 型）との BETWEEN 比較で<br>
`week_start.beginning_of_day` のまま使うと UTC 変換がズレてタスクが集計されないバグが発生する。<br>
`week_start.in_time_zone.beginning_of_day` と `today.in_time_zone.end_of_day` を使うことで<br>
JST 基準の明示的な Time オブジェクトに変換してから PostgreSQL に渡せる。<br>
```ruby
# ❌ Date#beginning_of_day → UTC 変換がズレる
week_start.beginning_of_day

# ✅ in_time_zone 経由で JST 基準の Time に変換する
week_start.in_time_zone.beginning_of_day  # 2026-04-13 00:00:00 +09:00
```

<br>

### Tailwind の動的クラスはインラインスタイルで代替する（#C-6）

<br>

`bg-<%= rate_color(rate) %>-500` のような ERB 変数を使った動的クラスは<br>
Tailwind のビルド時静的解析で検出されず、CSS が生成されないため本番で色が当たらない。<br>
`rate_hex_color` ヘルパーで16進数カラーコードを返し、<br>
`style="background-color: <%= rate_hex_color(rate) %>"` のようにインラインスタイルで指定すること。<br>
```erb
<%# ❌ 動的クラス → ビルド対象外 %>


<%# ✅ インラインスタイル → 動的カラーコードを安全に適用 %>

```

<br>

### テストの assert_select は data-testid で絞り込む（#C-6）

<br>

`assert_select "span", text: "Must"` のように広いセレクタを使うと、<br>
ページ上の他の `span` 要素（ユーザー名・ナビリンク等）にもマッチして誤検知が発生する。<br>
`data-testid` 属性を HTML に付与し、`assert_select "[data-testid='priority-badge-must']"` のように<br>
具体的なセレクタで絞り込むことで誤検知のない堅牢なテストになる。<br>
将来的にデザインやクラスが変更されても `data-testid` が残る限りテストは壊れない。<br>
```ruby
# ❌ 広いセレクタ → ユーザー名等の無関係な span にもマッチ
assert_select "span", text: "Must"

# ✅ data-testid で絞り込む → 意図した要素のみ
assert_select "[data-testid='priority-badge-must']", text: "Must"
```

<br>

### fixtures のタスクはテスト setup で論理削除する（#C-6）

<br>

`tasks.yml` に fixture タスク（`ai_generated_task`）があると、<br>
`created_at` が今週の BETWEEN 条件にヒットして集計に混入し、<br>
テストが意図しない件数を返す問題が発生する。<br>
`setup` で `@user.tasks.update_all(deleted_at: Time.current)` を実行して<br>
fixtures タスクを論理削除してからテスト用データを作成することで<br>
fixtures の影響を受けないクリーンな集計結果を制御できる。<br>
```ruby
def setup
  travel_to Time.zone.local(2026, 4, 15, 10, 0, 0)
  @user = users(:one)
  post login_path, ...
  # fixtures タスクを無効化してテストをクリーンな状態にする
  @user.tasks.update_all(deleted_at: Time.current)
end
```

<br>

### form_with の Turbo 干渉に注意する（#C-7）

<br>

Rails 7 の `form_with` はデフォルトで Turbo Drive が処理するため、<br>
サーバーが通常の HTML リダイレクトを返しても画面が遷移しないことがある。<br>
AI編集ページのように「シンプルなフォーム送信 → リダイレクト」で十分な場合は<br>
`data: { turbo: false }` を指定して Turbo を無効化する。<br>
また `form_with` のフォームフィールドは必ず `f.text_field` / `f.date_field` 等の<br>
`f.` メソッドを使うこと。`text_field_tag` 等を使うと `name="task[title]"` にならず<br>
`params[:task]` が nil になって `ActionController::ParameterMissing` が発生する。

<br>

### session によるアクセス制御は task_id まで照合する（#C-7）

<br>

「特定のフロー経由かどうか」を session で制御する場合、<br>
`session[:ai_context] = true` のようなフラグだけでは不十分。<br>
「タスクAのai_edit → タスクBのai_update」という不正なクロスアクセスを防ぐために<br>
`session[:ai_context_task_id] = @task.id` として task_id まで保存し、<br>
`ai_update` で `session[:ai_context_task_id] == @task.id` と照合すること。<br>
照合成功後は必ず `session.delete(:ai_context_task_id)` でフラグをクリアし、<br>
次回は必ず ai_edit から入り直す状態に戻す。

<br>

### 単数形リソース（resource）では form_with の url: 省略が NoMethodError を引き起こす（#D-1）

<br>

`resource :user_purpose`（単数形）を使うと URL に id が含まれない設計になるが、<br>
`form_with model: @user_purpose` では Rails が `user_purposes_path`（複数形）を探しに行き<br>
`NoMethodError: undefined method 'user_purposes_path'` が発生する。<br>
単数形リソースでは `url: user_purpose_path, method: :post` を必ず明示すること。<br>
「`url:` を省略すべき」というアドバイスは複数形リソース（`resources`）に限った話であり、<br>
単数形リソースには適用できない。実際に動かして確認することが大切。

<br>

### バージョン管理は「更新 = 新規作成」で設計すると履歴が自動保存される（#D-1）

<br>

既存レコードを上書きする通常の UPDATE 設計では過去のデータが失われる。<br>
「更新するたびに新しいレコードを作成し、古いレコードを `is_active=false` にする」設計にすると<br>
コントローラーは `build` → `save` するだけで履歴が自動的に保持される。<br>
`before_save` コールバックで旧バージョンの無効化を自動化することで<br>
「is_active=true が常に1件」という整合性をモデル層で保証できる。<br>
AI 分析結果（`ai_analyses`）と PMVV のバージョンを1対1で紐付けられるため<br>
「このバージョンで分析した」という履歴の正確性も担保される。

<br>

### before_validation と before_save のタイミングの違いを理解する（#D-1）

<br>

Rails のコールバック実行順序は `before_validation` → `validate` → `before_save` → `save`。<br>
`validates :version, presence: true` がある場合、`before_save` で version をセットしても遅すぎる。<br>
バリデーション実行前に値が必要なカラムは `before_validation` でセットすること。<br>
before_validation → バリデーション対象になるカラムの自動セット（version・year・week_number 等）<br>
before_save       → 保存直前の副作用処理（旧バージョンの無効化・分析状態の記録等）<br>
`before_validation on: :create` とすることで新規作成時のみ実行する制御も可能。

<br>

### API gem が存在しない場合は REST API を直接呼ぶ（#D-2）

<br>

Google Gemini のように公式 Ruby SDK が存在しない API は、<br>
サードパーティ gem に頼らず faraday で REST API を直接呼ぶ方が安定している。<br>
gem が存在しない → ビルド失敗というシンプルなエラーより、<br>
バージョン変更で突然動かなくなるサードパーティ gem の方がリスクが高い場合がある。<br>
公式ドキュメントの JSON 構造をそのまま使えるため、仕様変更への追従も容易になる。

<br>

### ActiveRecord の予約語はカラム名に使ってはいけない（#D-2）

<br>

`model_name` は ActiveRecord が内部で使用している予約済みメソッド名。<br>
テーブルに `model_name` カラムがあると `ActiveRecord::DangerousAttributeError` が発生し、<br>
モデルが全く使えなくなる。<br>
カラム名を設計するときは `bin/rails db:check_reserved_words` で予約語チェックを行う習慣をつけること。<br>
主な予約語: `type`（STI）/ `model_name` / `hash` / `class` / `id` / `errors`

<br>

### AI は必ず壊れた JSON を返す前提で設計する（#D-2）

<br>

AI に JSON 形式での回答を指示しても、高確率で前後に文章が付いたり<br>
コードブロック（```json）で囲まれたりする。<br>
JSON パースは「正規表現で `{ }` 範囲を抽出してからパース」する設計にすることで<br>
ほぼ全てのパターンに対応できる。<br>
さらに必須キーの存在確認・`actions` が配列かどうかの型チェックを追加して<br>
パース後のデータが想定通りであることを保証すること。

<br>

### AI クライアントは戻り値に使用モデル名を含めて正確に記録する（#D-2）

<br>

Gemini と Groq のフォールバック設計では「どちらのモデルで実際に生成したか」を<br>
呼び出し元が正確に知る必要がある。<br>
戻り値を `{ text: "...", model: "..." }` の Hash 形式にすることで<br>
DB への記録（`ai_model_name`）が正確になり、後から分析品質の追跡が可能になる。

<br>

### パーシャルのローカル変数はすべての呼び出し元で渡すこと（#D-3）

<br>

パーシャルがローカル変数を受け取る設計の場合、<br>
通常のビュー呼び出しと Turbo Stream の `broadcast` 呼び出しの両方で<br>
`locals:` に必要な変数を渡すこと。<br>
Turbo Stream 側で `locals:` の変数が欠けていても `rescue` で握り潰されてしまい<br>
ブラウザには何も届かないサイレント障害になる。

<br>

### solid_cable のバージョンと DB スキーマのギャップに注意する（#D-3）

<br>

gem のバージョンアップで必要なカラムが増えても、<br>
`install` コマンドが生成するマイグレーションに自動追加されるとは限らない。<br>
`ActiveModel::UnknownAttributeError` が発生したら、<br>
まず gem のソースコードで使っているカラムと実際のテーブルスキーマを照合すること。<br>
差分があれば追加マイグレーションで対応する（#D-3 の `channel_hash` 追加がその例）。

<br>

### async アダプターの制限を理解してから開発環境を設計する（#D-3）

<br>

`cable.yml` の `adapter: async` は同一プロセスのメモリ内でのみ動作する。<br>
GoodJob のバックグラウンドスレッドとブラウザの WebSocket は<br>
同じ Puma プロセス内で動いていても異なるスレッドコンテキストになるため、<br>
`async` アダプターでは `broadcast` がブラウザに届かないことがある。<br>
DB アダプター（`solid_cable`）を使うことでプロセス・スレッドをまたいで確実に通知できる。<br>
本番で Redis を使う場合は開発環境だけ `solid_cable` にするのが費用対効果が高い。

<br>

### User 登録時の関連レコード自動作成は after_create で保証する（#D-4）

<br>

`UserSetting` のように「User が存在すれば必ず1件存在すべき」関連レコードは、<br>
`after_create` コールバックで自動作成することで「存在しない状態」を設計上ありえなくする。<br>
コントローラー・ジョブ・サービスで nil ガードを書き続けるより根本的な解決になる。<br>
`rescue ActiveRecord::RecordInvalid` でバリデーション失敗時のログを残しつつ<br>
ユーザー登録自体は成功させる設計にすることで、障害が波及しない安全な実装になる。

<br>

### after_create 追加後は既存テストの UserSetting.create! を必ず更新する（#D-4）

<br>

`User` モデルに `after_create :create_user_setting` を追加すると、<br>
既存テストの `setup` で `UserSetting.create!(user: @user, ...)` を呼んでいる箇所が<br>
UNIQUE 制約違反（`PG::UniqueViolation`）で全てエラーになる。<br>
`grep -r "UserSetting.create" test/` でヒットした全ファイルを確認し、<br>
`user.user_setting` で参照する形に変更するか、設定値の違いは `user.user_setting.update!` で対応する。

<br>

### GoodJob のジョブは ID で渡して perform 内で find する設計にする（#D-4）

<br>

GoodJob はジョブ引数を JSON で `good_jobs.serialized_params` に保存するため、<br>
ActiveRecord インスタンスを渡すと JSON シリアライズできずエラーになる。<br>
ID（整数）を渡して `perform` 内で `find` し、`discard_on ActiveRecord::RecordNotFound` と<br>
組み合わせることで「レコード削除後の残存ジョブ」を自動破棄できる安全な設計になる。

<br>

### button_to はフォームの外に置かないとメインフォームのバリデーションが発火する（#D-7）

<br>

HTML の仕様では `<form>` の中に `<form>` を入れることができない。<br>
`button_to` は独自の `<form>` を生成するため、`form_with` の内側に置くと<br>
スキップ時にメインフォームの `submit` が先に処理されてバリデーションエラーが表示される。<br>
状態変更を伴うボタン（スキップ・キャンセル等）は必ず `form_with` の `<% end %>` の後に配置すること。

<br>

### Turbo Stream のチャンネル名は broadcast 側と完全一致させる（#D-7）

<br>

ビュー側の `turbo_stream_from` と、ジョブ側の `broadcast_replace_to` のチャンネル名は<br>
1文字でも違うとブラウザに通知が届かないサイレント障害になる。<br>
`current_user.id`（User の主キー）と `user_purpose.id`（UserPurpose の主キー）は別物であり、<br>
混同すると「AI分析待機中から変わらない」という症状になる。<br>
チャンネル名を変更する際は broadcast 側と subscribe 側を同時に確認すること。

<br>

### デバッグが長期化した場合はブランチをリセットして再実装する（#D-7）

<br>

#D-7 の実装では以下の複合的な不具合が同時に発生し、長期のデバッグセッションとなった。

<br>

| 不具合 | 原因 | 症状 |
|:---|:---|:---|
| Turbo Stream チャンネル名不一致 | `broadcast_replace_to` が `user_purpose.id` に送信していたが、ビューは `current_user.id` を購読 | バナーが「AI分析待機中...」から変わらない |
| `solid_cable` の `polling_interval` 形式エラー | YAML では Ruby 式（`0.1.seconds`）が評価されず文字列になり `NoMethodError` でポーリングスレッドが終了 | WebSocket は接続されているが `confirm_subscription` が届かない |
| フォームの入れ子問題 | スキップ `button_to` をメインフォーム内に配置していた | スキップ時にメインフォームのバリデーションが発火 |
| `id` の二重定義 | ダッシュボードの外側 `div` とパーシャル内に同名 `id="analysis_status_banner"` が存在 | Turbo Stream の DOM 更新が意図しない要素に当たる |

<br>

これらの不具合は相互に絡み合い、1つを修正しても別の問題が隠れているため原因の特定に時間がかかった。<br>
最終的に**ブランチを削除して再作成し、正しい実装を一から適用する**ことで解決した。

<br>

デバッグが長期化するサインと判断基準：<br>

- 修正と確認を3回以上繰り返しても同じ症状が続く<br>
- 複数の不具合が同時に存在し、どれが根本原因か判断できない<br>
- 動作確認の手順が複雑になり結果が安定しない

<br>

このような状況では**「デバッグを続けるコスト」と「リセットして再実装するコスト」を比較する**ことが重要。<br>
今回は判明した修正点を整理してからリセットしたため、再実装は短時間で完了した。<br>
「問題の原因を理解した上でリセットする」ことが、単純に再実装するより価値がある。

<br>

**再実装前に必ず行うこと：**<br>

1. 判明した全バグの根本原因をリスト化する<br>
2. 修正すべき箇所と正しいコードを文書化する<br>
3. ブランチを削除し、最初から正しい実装を適用する

<br>

### set_habit の rescue はテストの期待値に影響する（#D-8）

<br>

コントローラー内の `rescue ActiveRecord::RecordNotFound → redirect_to` は<br>
`ApplicationController` の `rescue_from` より優先度が高い。<br>
他ユーザーのリソースへのアクセスをテストする際、<br>
`assert_response :not_found`（404）ではなく `assert_redirected_to xxx_path`（302）が正しい期待値になる。<br>
テストが「Expected: 404, Actual: 302」で失敗する場合は `set_habit` の rescue 設計を確認すること。<br>
```ruby
# ❌ rescue_from がある → 404 を期待するが実際は 302
get ai_edit_habit_path(other_user_habit)
assert_response :not_found  # 失敗

# ✅ set_habit の rescue → 302 リダイレクト
get ai_edit_habit_path(other_user_habit)
assert_redirected_to habits_path  # 正解
```

<br>

### jsonb バリデーションは「存在チェック」と「値チェック」を分けて設計する（#D-9）

<br>

jsonb カラムへのバリデーションは「キーが存在するか」と「キーの値が空でないか」を<br>
別々に評価するか一体で評価するかを最初に決めてから実装すること。<br>

<br>

**存在チェック（`key?`）だけで十分な場合:**<br>
- 参照先フィールドが `allow_blank: true` の設計で、値が nil でも画面がクラッシュしない<br>
- 18番画面のように `.presence || "未入力"` で nil を安全に処理できる場合<br>
- `build_input_snapshot` が必ず Hash を作るため「キーがない」ことだけが問題の場合<br>

<br>

**存在チェック + 値チェック（`key?` + `present?`）が必要な場合:**<br>
- 画面がキーの値を直接 `Hash#fetch` 等で参照し、nil・空文字でクラッシュする場合<br>
- API の仕様上、必ず値が入っていることが保証されているべきカラムの場合<br>

<br>

`present?` まで要求すると、未入力フィールドを持つ正常なデータ（Purpose は入力済みだが Mission は未入力等）を<br>
全てバリデーションエラーにしてしまう。`UserPurpose` の設計（`allow_blank: true`）と<br>
バリデーションの設計を合わせることが重要。<br>

```ruby
# ❌ present? まで要求 → 未入力フィールドがある正常なデータも弾く
missing_keys = required_keys.reject { |key| snapshot.key?(key) && snapshot[key].present? }

# ✅ key? のみ → allow_blank: true 設計に準拠し、未入力（nil）は許容する
missing_keys = required_keys.reject { |key| snapshot.key?(key) }
```

<br>

また、バリデーションの設計変更はジョブテストにすぐに影響する。<br>
`present?` から `key?` に変更した場合、`PurposeAnalysisJobTest` の正常系テストが<br>
失敗から通過に変わる可能性がある（逆も同様）。<br>
モデルテストだけでなく必ず全テストを実行して影響範囲を確認すること。

<br>

### throttle チェックのテストは「throttle をバイパスしてから本来の挙動を検証する」（#D-10）

<br>

1回目の POST で `last_ai_requested_at` が更新されるため、<br>
同一テスト内で2回目の POST を送ると throttle に引っかかって元の挙動を確認できなくなる。<br>
テストの目的が「throttle」ではなく「2重送信防止の別ロジック」の場合は、<br>
`update_columns(last_ai_requested_at: 2.minutes.ago)` で throttle をバイパスしてから検証すること。<br>

```ruby
# D-10 対応: 2回目送信前に throttle をバイパスする
@user.user_setting.update_columns(
  last_ai_requested_at: 2.minutes.ago  # 1分以上前に設定して throttle を回避
)

assert_no_difference "WeeklyReflection.count" do
  post weekly_reflections_path, params: { ... }  # 本来の重複防止ロジックを検証
end
```

<br>

### format.any がないと favicon.ico のリクエストが UnknownFormat エラーになる（#D-10）

<br>

ブラウザは自動的に `/favicon.ico` へ GET リクエストを送る。<br>
catch-all ルート（`match "*path", to: "errors#not_found", via: :all`）がこのリクエストを受け取り、<br>
`render_error_page` の `respond_to` に `ico` フォーマットの処理がないと<br>
`ActionController::UnknownFormat` が発生する。<br>
「開発環境だから無視してよい」ではなく、エラーログが汚れ、本番でも同様に発生するため必ず修正すること。<br>
`format.any { head status }` を全ての `respond_to` ブロックの末尾に追加することで解消できる。

<br>

### ja.yml の `activerecord:` セクションは必ず1箇所にまとめる

<br>

YAML ファイルで同一トップレベルキー（`activerecord:`）が2箇所に存在すると、<br>
後の定義が前の定義を完全に上書きする。<br>
結果として「全エラーメッセージが消える・英語に戻る」という一見原因不明のバグになる。<br>
`ja.yml` に `activerecord:` セクションを追記する際は必ず既存のセクションに統合すること。<br>
`grep -n "^activerecord:" config/locales/ja.yml` で重複を確認できる。

<br>

### スクリプト・ツールで生成したコードは必ずカンマ漏れをチェックする

<br>

Ruby の Hash 末尾カンマが欠落すると `SyntaxError` が発生してテストが全て実行されない。<br>
`reflection_comment: "..." # E-1 追加` のようにコメント付きの行を自動挿入したとき、<br>
コメント前にカンマが付いていない場合が多い。<br>
スクリプト生成後は `split('#')[0].rstrip().endswith(',')` でコード部分だけを抽出してチェックすること。<br>
手動で修正するよりスクリプトで一括チェック・修正する方が信頼性が高い（E-1 で9ファイル同時修正した例）。

<br>

### `include CrisisDetector` のような横断的関心事は削除禁止とマークする

<br>

モデルに `include CrisisDetector` が定義されているとき、<br>
「未使用に見える」という理由で削除すると別の場所（コントローラー・テスト）が壊れる。<br>
横断的関心事（セキュリティチェック・監査ログ・危機検出等）は<br>
コード内に `# 削除禁止: OnboardingsController#complete で使用` のようなコメントを残すこと。<br>
E-1 ではこの削除により `crisis_word_detected?` が `NoMethodError` になり<br>
複数テストが一斉にエラーになった。

<br>

### ブラウザ確認チェックリストをPRにセットにする

<br>

実装完了後のブラウザ動作確認チェックリストを PR 本文に含めることで、<br>
「コードは通るがUIが壊れていた」という見落としを防げる。<br>
E-1 では気分スコアUI・必須バッジ・🎤ボタン・エラー表示・保存確認の全項目を<br>
ブラウザで一つずつ確認した後にマージすることで品質を担保した。

<br>

### Turbo Stream のリアルタイム更新には「パーシャル化 + id 付与 + チャンネル購読」の3点セットが必要（#E-3）

<br>

Turbo Stream でリアルタイム更新を実現するには3つの準備が同時に必要。<br>
1つでも欠けると「更新されない・エラーにもならない」サイレント障害になる。

<br>

| 準備 | 実装 | 欠けた場合の症状 |
|:---|:---|:---|
| パーシャル化 | 更新対象をパーシャルに切り出す | `partial:` で render できない |
| id 付与 | パーシャルの最外側要素に `id="xxx_#{id}"` を付ける | `turbo_stream.replace` の対象が見つからない |
| チャンネル購読 | ビューに `turbo_stream_from "チャンネル名"` を追加 | broadcast が届いても受信できない |

<br>

またチャンネル名は broadcast 側と subscribe 側で完全一致させる必要がある（1文字でもズレると届かない）。<br>
`WeeklyReflectionAnalysisJob` の `broadcast_completion` と `weekly_reflections/index.html.erb` の<br>
`turbo_stream_from` で同じ `"weekly_reflection_#{reflection.id}"` を使っていることを必ず確認すること。

<br>

### referer 判定は「同一ルートで複数ページから使われるコントローラー」の設計パターン（#E-3）

<br>

`habit_records_controller.rb` は `/habits` と `/dashboard` の両方からリクエストを受ける。<br>
両ページで更新したい DOM が異なる場合、`params` に `page:` を追加するより<br>
`request.referer` で判定する方が既存の JavaScript を変更せずに済む。<br>
`referer` が nil の場合は安全側（既存の動作）にフォールバックする設計にすること。<br>
将来ページが増えた場合は `case request.referer` で分岐を追加すれば拡張できる。

<br>

### オープンリダイレクト防止は `//` 始まりチェックを忘れずに

<br>

`URI.parse("//evil.com").host` は `"evil.com"` を返すため、<br>
`uri.host.nil?` だけでは `//evil.com` を安全と誤判定してしまう。<br>
`path.start_with?("//")` を先頭に追加する二重チェックが必要。<br>
ブラウザによっては `//evil.com` をホスト指定として解釈し外部サイトに飛ぶため、<br>
オープンリダイレクト防止は `blank?` / `//` / `URI.parse` / `start_with?("/")` の4段階で行う。

<br>

### 既存テストはクエリパラメータが付く変更に弱い

<br>

`assert_redirected_to login_path` は `"/login"` への完全一致を期待する。<br>
リダイレクト先に `?redirect_to=...` のようなクエリパラメータが付くようになると<br>
関連する全テストが一斉に失敗する。<br>
「ログインページへのリダイレクト」を検証する目的なら<br>
`assert_redirected_to %r{/login}` という正規表現マッチで書いておくと<br>
将来のクエリパラメータ追加にも耐性がある。<br>
ただし Rails テスト環境はフルURL（`http://www.example.com/login?...`）を返すため<br>
`%r{\A/login}` ではなく `%r{/login}` を使うこと。

<br>

### `hidden_field_tag` と URL クエリパラメータは用途が違う

<br>

フォームの送信先URLにクエリパラメータを付ける方式（`login_path(redirect_to: ...)`）は<br>
ブラウザのURL表示に含まれるため `render :new` でフォームを再描画すると失われることがある。<br>
`hidden_field_tag :redirect_to, params[:redirect_to]` を使って POST body に含める方式が安定している。<br>
「フォーム送信後にサーバーが必ず受け取る必要がある値」は hidden field で渡すのが基本。

<br>

### ポーリングのタイマーは必ず disconnect() でクリアする

<br>

Stimulus コントローラーの `connect()` で `setInterval` を開始した場合、<br>
Turbo によるページ遷移時に `disconnect()` でタイマーをクリアしないと<br>
「ページを離れてもポーリングが続くメモリリーク」が発生する。<br>
`this.timer` にタイマーIDを保持し、`disconnect()` で `clearInterval(this.timer)` するのが必須。

<br>

### 「ページ全体リロード」より「DOM部分差し替え」を優先する

<br>

AI分析の完了をユーザーに伝える際、`Turbo.visit(window.location.href)` でページ全体を<br>
再取得するとスクロール位置が先頭に戻りユーザー体験が悪化する。<br>
`document.getElementById` で対象要素を取得し `outerHTML` を差し替えることで<br>
スクロール位置を維持したまま対象セクションだけを更新できる。

<br>

### 非同期完了の検知はDOMの状態変化で行える

<br>

「分析が完了したか」を専用APIで確認する設計より、<br>
「待機中UIが消えたか」をDOMセレクターで判定する設計の方がシンプルで堅牢。<br>
サーバーとクライアントの状態が常に一致していることが前提になるが、<br>
今回のように「待機UIが表示されている = 未完了、表示されていない = 完了」という<br>
UIの状態とビジネスロジックが1対1で対応している場合に有効な設計パターン。

<br>

### OmniAuth gem のストラテジー名は gem 名から自動推測できない

<br>

gem 名（`omniauth-line-v2_1`）からストラテジーシンボル（`:line_v2_1`）を推測するには<br>
gem のソースコードを確認する必要がある。<br>
`Gem.find_files('omniauth/**/*.rb').select { |f| f.include?('line') }` で<br>
実際のストラテジーファイルパスを確認し、そのファイル名の snake_case を provider シンボルに使う。<br>
`:line` / `:line_v21` / `:line_v2_1` の3候補をエラーログの `Did you mean?` から特定する手順も有効。

<br>

### RailsバリデーションとDBレベル制約は別物

<br>

`allow_nil: true` はRailsの `validates` をスキップするだけ。<br>
PostgreSQL の NOT NULL 制約はDBが直接 INSERT を拒否するため、<br>
新機能で初めてその制約に引っかかるデータが登録されるまで気づかないことがある。<br>
ソーシャルログイン対応のように「nullable なフィールドを増やす設計変更」をする際は<br>
DBレベルの制約も合わせて確認・変更すること。

<br>

### 開発中チャネルのLINEログインは Tester 権限が必要

<br>

LINE Developers Console でチャネルが「開発中」ステータスの場合、<br>
Developer または Tester 権限を持つ LINE アカウントのみログインできる。<br>
「400 Bad Request: This channel is now developing status. User need to have developer role.」<br>
のエラーが出た場合は「権限設定」→「メールで招待」→ Role: Tester で自アカウントを招待する。<br>
公開ステータスにすれば全ユーザーがログインできるが、localhost でしか動いていない間は<br>
実質的にアクセス可能なのは自分のみのため、公開にしても問題ない。

<br>

### 退会処理は UserDestroyService に集約し before_destroy でガードする

<br>

論理削除設計では `User.destroy` を誤って呼ぶと外部キー制約違反が発生する。<br>
`before_destroy` で本番・開発環境の物理削除を禁止し、退会は必ず `UserDestroyService` 経由とする。<br>
テスト環境は `Rails.env.test?` で除外することで既存テストの `teardown { @user.destroy }` が壊れない。<br>
`PushSubscription` のようにモデルファイルが存在しないテーブルの削除は<br>
`ActiveRecord::Base.sanitize_sql_array` でSQLインジェクション対策をした直接SQL実行で対応する。

<br>

### LINE の uid（OmniAuth sub）と line_user_id（Messaging API userId）は同一プロバイダーで一致する

<br>

F-2 で実装した OmniAuth LINE ログインの `users.uid` と<br>
G-1 で使う `users.line_user_id`（Messaging API の Push 送信先）は<br>
同一プロバイダー内のチャネルであれば同一の値になる。<br>
OmniAuth コールバックで `auth.uid` を `line_user_id` として保存するだけで<br>
追加の API 呼び出しなしに通知の送信先が確定する設計になる。<br>
プロバイダーが異なると両者が別の値になり通知が届かないため、<br>
LINE Console でチャネルを作成するときは必ず同一プロバイダー下に配置すること。

<br>

### LINE の長期チャネルアクセストークンは再発行で古いトークンが失効する

<br>

LINE Developers Console で「チャネルアクセストークン（長期）」を再発行すると、<br>
以前発行したトークンは即座に失効する。<br>
HTTP 401 Unauthorized が返ってきた場合は `.env` の `LINE_CHANNEL_ACCESS_TOKEN` が<br>
Console に表示されている現在のトークンと一致しているか確認すること。<br>
発行し直した場合は `.env` を更新し、`docker compose down && docker compose up -d` で再起動する。<br>
本番環境（Render）も忘れずに Environment 変数を更新すること。

<br>

### fixture の週次レポート設定は全件リセットしてからテスト用データを作る（#G-2）

<br>

`fixtures :all` により全ての fixture ユーザー設定がテスト DB に読み込まれるため、<br>
`weekly_report_enabled: true` の fixture ユーザーが複数存在すると<br>
`assert_emails 1` が「期待1件、実際3件」として失敗する。<br>
`UserSetting.update_all(weekly_report_enabled: false)` で全件を先にリセットし、<br>
テスト用ユーザーのみを `true` に設定することで fixture の影響を受けないテストになる。<br>
同じパターンは他のフラグ系設定（`notification_enabled` 等）でも発生するため<br>
「全件リセット → テスト用のみ有効化」を標準パターンとして使うこと。

<br>

### GoodJob cron に新エントリを追加したら必ず直前エントリのカンマを確認する（#G-2）

<br>

`config/initializers/good_job.rb` の `cron:` ハッシュに新しいエントリを追加するとき、<br>
直前エントリの末尾 `}` にカンマがないと `SyntaxError` が発生してアプリが起動できなくなる。<br>
複数行コメントがカンマの直後に挿入されると目が行きにくくなるため、<br>
追加後は必ず `docker compose up` で起動確認してから次の作業に進むこと。

<br>

### メイラーのビューで ApplicationHelper を使うには `helper :application` を明示する（#G-2）

<br>

ActionMailer はデフォルトで `ApplicationHelper` をビューに自動インクルードしない場合がある。<br>
`helper :application` を Mailer クラスに明示しないと `achievement_color` 等のヘルパーメソッドが<br>
`NoMethodError` になってメールの render に失敗する。<br>
メイラーのビューでヘルパーメソッドを使う場合は必ず明示すること。

<br>

### Tailwind v4 では peer-checked: は label に直接付与する

<br>

トグルスイッチを実装する際、`peer` チェックボックスの兄弟である `label` の子孫 `span` に<br>
`peer-checked:` を書いても Tailwind v4 では効かない（直接兄弟要素のみが対象）。<br>
`span` を廃止して `label` 自体に `w-11 h-6 rounded-full bg-gray-200 peer-checked:bg-blue-600`<br>
などを直接付与することで正常に動作する（#G-3 で発見・修正）。

<br>

### Turbo + フラッシュ + キャッシュの三点セット対策

<br>

Turbo が有効なページでフォーム送信後のフラッシュが表示されない場合、<br>
以下の3点を同時に対応することで確実に解消できる。<br>
① フォームに `data: { turbo: false }` を付けて通常の HTML フォーム送信にする<br>
② コントローラーで `redirect_to ..., status: :see_other` と 303 を明示する<br>
③ `content_for :head` で `<meta name="turbo-cache-control" content="no-cache">` を出力し、<br>
　 `application.html.erb` の `<title>` 直後に `<%= yield :head %>` を追加する<br>
`button_to` で別フォームが必要なボタン（LINE連携等）は `form="外部フォームのid"` で紐付け、<br>
ページ末尾に `id` 付きの hidden フォームを配置する（#G-3 で採用した設計）。

<br>

### form_with url: で f.xxx を使う場合は scope: を必ず付ける（#G-4）

<br>

`form_with url: path` + `f.date_field :column_name` の組み合わせでは、<br>
`scope:` を省略するとフィールド名がトップレベル（`column_name=...`）で送信される。<br>
コントローラーが `params[:model_name][:column_name]` で取得しようとすると nil になり、<br>
バリデーションエラーが続いてデバッグが困難になる。<br>
`form_with model:` 形式が使えない場合（単数形リソース・カスタム URL 等）は<br>
`scope: :model_name` を必ず指定すること。

<br>

### Stimulus スコープ外のモーダルボタンは addEventListener で制御する（再確認）

<br>

G-4 でも B-5/C-3 と同じ「content_for :modals でスコープ外に出るボタンの問題」が発生した。<br>
`data-action` は `data-controller` 要素の子孫にしか効かないことを設計の最初から考慮し、<br>
モーダルを `content_for :modals` に入れる設計にした瞬間に<br>
モーダル内ボタンへの `data-action` を捨てて `addEventListener` 方式に切り替えることを徹底すること。

<br>

### `travel_to` はコンソールでは使用できない

<br>

`ActiveSupport::Testing::TimeHelpers` はテスト環境のみに読み込まれるRailsの仕組みのため、<br>
`bin/rails console` でいくら `include` しようとしても<br>
`uninitialized constant ActiveSupport::Testing (NameError)` が発生する。<br>
月初判定ロジックのように「特定日時のみ動作するジョブ」のコンソール確認は<br>
① ジョブの核心処理（`update_all` 等）を直接実行する<br>
② 月初以外は「スキップログが出ること」で条件分岐が正常なことを確認する<br>
という2段階アプローチで行うこと。「月初に実際にリセットされる」動作保証はテストに任せる。

<br>

### `update_all` の結果はテストで `.reload` して確認する

<br>

`update_all` はSQLを直接発行するためActiveRecordオブジェクトのキャッシュを更新しない。<br>
テストでは `update_all` 実行後に必ず `.reload` でDB最新値を取得してからアサーションすること。<br>
`reload` を忘れると「更新前の古い値」に対してアサーションを行い、<br>
テストが正常に通過してしまう偽陽性（false positive）になる。<br>
同じ問題は G-4 の `RestModeExpiryJob` テストでも発生しており、<br>
バッチ処理系ジョブのテストでは `reload` が必須パターンとして定着している。

<br>

### Rubyでは同名メソッドの後方定義が有効になる

<br>

同一クラスに同名メソッドが2箇所ある場合、Rubyはファイルの後方（末尾に近い方）を有効とする。<br>
リファクタリングで新実装を追加したとき、古い実装を削除し忘れると<br>
「修正したはずなのに古い動作のまま」という原因不明のバグになる。<br>
`grep -n "def メソッド名"` で重複を検出する習慣をつけること。

<br>

### AIプロンプト拡張時はmaxOutputTokensを必ず見直す

<br>

プロンプトの内容量を増やすとAIのレスポンス量も増えるため、<br>
`maxOutputTokens` が不足するとレスポンスが途中で切れる。<br>
APIクライアントに Gemini用・Groq用の複数箇所に設定がある場合は全て更新すること。<br>
レスポンスが不自然な文字数で終わっている場合はこの問題を疑うこと。

<br>

### Turbo Streamの二重表示は「送る側」と「受ける側」のストリーム名を確認する

<br>

複数ページが同一ストリームを購読していると、あるページ向けのパーシャルが<br>
他のページにも届いてしまう。症状は「バナーが二重表示になる」「意図しないUIが表示される」等。<br>
ストリームは配信先ページ別に分離し、送る内容もページに合わせて変える設計にすること。

<br>

### デバッグにconsole.logとgetComputedStyleを組み合わせる

<br>

`el.style.transition` が空文字を返しても実際のCSSが適用されているとは限らない。<br>
`style.*` はインラインスタイルのみを返すため、CSSクラス由来のスタイルを確認するには<br>
`getComputedStyle(el).transition` を使う必要がある。<br>
H-2では `[COMPUTED] none` というログで「transition: none がCSSとして適用されていた」ことが判明し、<br>
原因の特定に至った。インラインスタイルの確認と計算済みスタイルの確認は別物として使い分けること。

<br>

### リアルタイム性が必要な機能は「最終結果」だけでなく「途中経過」のAPIを活用する（#H-3）

<br>

Web Speech API の `interimResults` のように、多くのリアルタイムAPIには<br>
「確定結果」と「暫定結果（途中経過）」を分けて返す仕組みが用意されている。<br>
`interimResults: true` を設定しても、コールバック内で `isFinal: true` のみをフィルタリングすると<br>
実質的に `interimResults: false` と同じ挙動（話し終わるまで何も表示されない）になってしまう。<br>
「リアルタイムに見える」UXを実現するには、暫定結果も含めて毎回フィールドを再構築する設計が必要。<br>
```javascript
// ❌ 確定結果のみ反映 → 話し終わるまで画面に変化がない
if (event.results[i].isFinal) {
  finalTranscript += transcript
}
this.fieldTarget.value = this.startValue + finalTranscript

// ✅ 暫定結果も含めて毎回再構築 → 話している最中から文字が出る
this.fieldTarget.value =
  this.startValue + separator + finalTranscript + interimTranscript
```

<br>

### トースト通知の再利用設計は「見た目が消えた」と「DOMから削除された」を区別する（#H-3）

<br>

`flash_controller.js` の `dismiss()` のように、多くのフェードアウト実装は<br>
`opacity: 0` にしたあと `hidden` クラスを追加するだけで、要素自体はDOMに残り続ける。<br>
「同じメッセージが表示中なら再利用する」という重複防止ロジックを実装する際、<br>
`querySelector` で「DOM上に存在するか」だけを確認すると、<br>
見た目上は消えている（hidden状態の）古い要素を誤って検出し、<br>
2回目以降の表示が機能しなくなるバグになる。<br>
独自のトースト実装では既存のフラッシュシステムに依存せず、<br>
専用の属性（`data-voice-inline-toast`）で管理することで予測可能な動作にできる。

<br>

### position: relative はJS側で強制せずHTML側のclass属性で用意する（#H-3）

<br>

絶対配置（`position: absolute`）の要素をJavaScriptで動的生成する場合、<br>
基準となる `position: relative` を `element.style.position = "relative"` として<br>
JS側で強制的に付与したくなるが、これはレイアウトの責務をJSとHTML/CSSの両方に分散させてしまう。<br>
将来そのdivに `grid` や `flex` 等の別レイアウトを適用する際、JSが密かに<br>
`position` を上書きしていることに気づかず競合するリスクがある。<br>
`position: relative` のような構造的なスタイルはHTML側の `class="relative"` で明示し、<br>
JSは「絶対配置の要素を生成する」というロジックのみを担当する設計にすることで、<br>
レイアウトの責務を1箇所に集約できる。

<br>

### addEventListenerの重複登録はonclickへの代入で防げる（#H-3）

<br>

DOM要素を使い回す（生成済みの要素を再利用する）設計では、<br>
`addEventListener` を呼ぶたびにリスナーが追加されていく多重登録のリスクがある。<br>
`element.onclick = () => { ... }` のようにプロパティへの代入方式を使うことで、<br>
再代入のたびに前のハンドラーが自動的に上書きされ、常に1つだけのハンドラーが<br>
登録された状態を保証できる。「ボタンを複数回押すと閉じる処理が複数回走る」<br>
ようなバグを未然に防げる、再利用可能なUI部品の定石パターン。

<br>

### 機能テスト中に偶発的に発見したバグは「スコープを混在させない」ことを最優先する（#H-3 → #H-10）

<br>

ある機能（H-3：音声入力）の動作確認中に、別の機能の組み合わせ（D-5：危機介入 × G-9：ダッシュボード表示）<br>
に起因するバグを偶然発見することがある。このとき「ついでに直す」誘惑に駆られるが、<br>
責務の異なる修正を同一ブランチに混在させると、レビュー時に「何のための変更か」が不明瞭になり、<br>
1つのコミットの中に複数の意図が混じってロールバックや原因切り分けが困難になる。<br>
発見したバグは新しいISSUE番号（今回はH-10）を振って完全に別ブランチで対応し、<br>
発見の経緯（「H-3のテスト中に発見」）をISSUEの説明に明記しておくことで、<br>
後から見た人にも文脈が伝わる設計にすること。

<br>

### npmパッケージのCDN配布形式は「ESM版だから安全」とは限らない（#H-4）

<br>

`bin/importmap pin` でnpmパッケージを取得する際、ESM版（`dist/package.js`）は<br>
パッケージによって内部コードが複数の兄弟ファイルに分割されていることがあり、<br>
メインファイルだけを取得すると依存ファイルが解決できず404/422になることがある。<br>
`+esm` エンドポイント（jsdelivr等）も、配信元ドメイン上での解決を前提に<br>
ルート相対パスを埋め込むため、自サーバーに配置すると壊れる。<br>
全コードを1ファイルに完全インライン化した UMDビルドは、この種の問題が<br>
構造的に発生しない最も安定した選択肢になりうる。

<br>

### ES Modules は1箇所のimportエラーでサイト全体を機能停止させる（#H-4）

<br>

Stimulusの `controllers/index.js` は全コントローラーを静的 `import` しているため、<br>
1つのコントローラー（`analytics_chart_controller.js`）内の `import` 解決エラーや<br>
実行時エラーが、`controllers/index.js` 全体の読み込みを停止させ、<br>
グラフ機能と無関係なページ（新規登録フォームの利用規約チェックボックス制御等）まで<br>
巻き添えにして機能停止させることが実際に発生した。<br>
新しい外部ライブラリを導入する際は、そのライブラリを使わないページでも<br>
Consoleにエラーが出ないことを必ず確認する。

<br>

### 外部ライブラリのバージョン・ビルド差異に対しては防御的にコーディングする（#H-4）

<br>

Chart.js の UMDビルドは自動登録済みのため `Chart.registerables` が存在しない。<br>
これを知らずに `Chart.register(...Chart.registerables)` を無条件で呼ぶと<br>
`TypeError: Chart.registerables is not iterable` で例外が発生する。<br>
`Array.isArray()` で存在確認してから処理する防御的な実装にすることで、<br>
ビルド形式の違いに対して安全なコードになる。

<br>

### bashのヒストリー展開（`!`）はダブルクォート内でも発火する（#H-4）

<br>

`bin/rails runner "Habit.find_each(&:calculate_streak!)"` のように<br>
メソッド名の `!` をダブルクォート文字列内に含めると、bashが<br>
コマンド履歴の呼び出し記号として誤解釈し `event not found` エラーになる。<br>
Rails自体のエラーではなくシェルの仕様のため、`!` を含むRubyコードを<br>
ターミナルから直接実行する場合はシングルクォートで囲む。

<br>

### サーバーログだけで原因を断定せず、ブラウザのConsoleエラーで裏付けを取る（#H-4）

<br>

トラブルシューティング中、サーバーログの404パターンから原因を推測したが、<br>
実際にブラウザのConsoleタブで確認するまでは「高確度の推測」の域を出ない。<br>
複数の仮説が連続して外れた経験から、サーバーサイドの状況証拠と<br>
ブラウザ側の一次証拠（Consoleの赤文字エラー）を必ず突き合わせてから<br>
修正に着手する重要性を学んだ。

<br>

### 外部レビューの指摘はスコープを明確に区別して対応する（#H-6）

<br>

外部レビューで指摘を受けた場合、すべての指摘を「今のタスクで対応すべき」と判断してはいけない。<br>
指摘を以下の3種類に分類して対応方針を決めること。

<br>

| 分類 | 判断基準 | 対応 |
|:---|:---|:---|
| **今タスクで対応すべき** | H-6 の完了条件（iOS ズーム・44px・横スクロール）に直結する | 対応する |
| **スコープ外・別タスク相当** | 既存設計（B-6から存在するカラーボタン等）への変更を要する | スコープ外として記録し ISSUE 起票 |
| **誤検知・許容範囲** | 実装意図と合っている・ユーザー影響が軽微 | 判断根拠を記録して対応しない |

<br>

H-6 では「カラーボタン w-9=36px が 44px 未満」「grid-cols-8 で 40px 前後」という指摘を受けたが、<br>
いずれも B-6（カラー・アイコン選択）から存在する設計であり、<br>
H-6 で新規導入したわけではないためスコープ外と判断した。<br>
「ブランチを削除してやり直す」ことなく前進コミットのみで完了できた。

<br>

### N+1は「preload しても .pluck/.where/.count で再クエリが飛ぶ」

<br>

`includes(:habit_excluded_days)` で preload しても、モデルメソッド内で `.pluck(:day_of_week)` を使うと<br>
preload を無視して毎回 SELECT が発行され N+1 になる（#H-9 で `Habit#excluded_day_numbers` を `.map` に修正）。<br>
bullet の `Unused Eager Loading` 警告はこのパターンを検知するシグナルになる。<br>
また Issue のチェックリストに `includes(:habit_records)` とあっても、既に集計クエリでN+1フリーな場合は<br>
逆効果（メモリ肥大化）になるため追加しない、という「Issueより実コード優先」の判断も本ISSUEで実践した。

### 統合テストは「実在するAPIだけ」で書く（推測で書かない）

<br>

テストを実装より先に推測で書くと、存在しないメソッドやenum値で書いてしまい実行前に壊れる。<br>
必ず実ファイルを開き、実在するスコープ・メソッド・enum・ルートだけを使って書く。<br>
「現在の実装に完全一致するテストだけを追加する」ことが、ブランチのやり直しを防ぐ最も確実な方法（#I-1で実践）。

<br>

### テストは本番の「サイレント失敗」を炙り出す

<br>

`create`（非bang）は保存に失敗しても例外を出さずに握りつぶす。<br>
#I-1 の統合テストは、PMVV危機記録の `AiAnalysis` が #D-9 スキーマ検証で弾かれて<br>
黙って保存されていなかった本番バグを検出した。<br>
`create` を使う箇所は「永続化されたか（`persisted?`／`count` 変化）」までテストで検証すること。

<br>

### `NO FILE` は「バグ」と決めつけず、出力の構造から原因を特定する

<br>

`db:migrate:status` の `NO FILE` は、`primary`/`cable` の多重DB構成で接続ごとに<br>
`migrations_paths` が異なるための正常表示だった。Docker やキャッシュを疑う前に、<br>
「接続ごとにブロックが出力される」という仕組みを理解すれば一発で切り分けられる。<br>
`schema_migrations` と実ファイル（`db/migrate` + `db/cable_migrate`）の突き合わせで孤立ゼロを機械的に確認する。

<br>

### メール本文の検証はエンコード形式を意識する

<br>

`mail.body.encoded` は Base64 の生MIME文字列を返すため、本文の文字列一致が失敗する。<br>
`text_part.body.decoded` / `html_part.body.decoded` で復号してから検証する。<br>
「なぜ一致しないのか」の9割はエンコード／マルチパート構造の見落としである。

<br>

### Render 無料構成では Solid Cache が最適解（#I-6）

<br>

Render 無料プランで Redis を使うには有料アドオンが必要になる。<br>
Solid Cache は既存の PostgreSQL をキャッシュストアにできるため、追加費用0円で導入できる。<br>
`config/cache.yml` で `database:` を指定しなければアプリ本体と同じコネクションプールを共有するので、<br>
コネクション数も増えず、Neon 無料枠の接続上限を圧迫しない。<br>
GoodJob・solid_cable と同じ「Redis を足さず PostgreSQL で完結」という方針で一貫させると、インフラがシンプルに保てる。

<br>

### キャッシュの上限は容量（max_size）より件数（max_entries）が安全（#I-6）

<br>

`max_size`（容量ベース）は各行の `byte_size` を1,000件サンプリングして総容量を推定するため、<br>
PostgreSQL の実ディスク使用量と誤差が出るうえ、掃除判定のたびにサンプリングクエリが走って Neon 無料枠に負担をかける。<br>
`max_entries`（件数ベース）は `MAX(id) - MIN(id)` の集計2本だけで済み、軽量かつ直感的。<br>
容量が読みにくい無料DB環境では、件数上限のほうがコントロールしやすい。

<br>

### キャッシュキーはタイムゾーンとアプリ独自の日付境界に必ず合わせる（#I-6）

<br>

`Date.today` はサーバーのシステムタイムゾーンを見るため、本番（UTC）で `config.time_zone = "Tokyo"` を無視して日付が1日ズレる。<br>
さらに本アプリは AM4:00 を日付境界にしているため、`cweek`（週番号）をそのまま使うと深夜0:00〜3:59 だけキーが翌週に飛ぶ。<br>
キャッシュキーの日付は、必ずアプリ全体で使っている日付ヘルパー（`HabitRecord.today_for_record`）に揃える。<br>
「キャッシュキーの日付ズレ」は、他人のデータ表示や無効化漏れといった発見しづらいバグの温床になる。

<br>

### フラグメントキャッシュにフォームを含めると再ログインで422になる（#I-6）

<br>

`form_with` が出力する `authenticity_token`（CSRFトークン）はセッションごとに変わる。<br>
これをキャッシュに焼き付けると、ユーザーが再ログインした後に古いトークンが返され、`ActionController::InvalidAuthenticityToken`（422）で送信が失敗する。<br>
ローカルは1セッションで検証するため気づけず、本番で「たまに反映できない」再現困難なバグになる。<br>
フラグメントキャッシュで包むのは**読み取り専用の表示部だけ**にし、フォームは必ず範囲外に置く。これは Rails の鉄則。

<br>

### immutable なレコードは touch より「新レコード＝新ID」で無効化する（#I-6）

<br>

`cache @record` は `テーブル名/{id}-{updated_at}` を自動でキーにする。<br>
再作成のたびに新しいレコード（新ID）を作る設計なら、IDが変わるだけでキーが変わり、古いキャッシュは自動で読まれなくなる。<br>
このとき `belongs_to :parent, touch: true` を足すのは逆効果で、作成のたびに親テーブルへ無意味な `UPDATE` が1回増えるだけ。<br>
ISSUE に「touch: true を設定」と書かれていても、実際のデータの作られ方（更新か新規作成か）を見て、不要なら追加しない判断が正しい。

<br>

### `rescue_from` は Sentry の自動捕捉より先に例外を握る

<br>

コントローラで `rescue_from StandardError` を使ってエラー画面を出していると、例外がフレームワークの最外殻に伝播せず、<br>
sentry-rails の自動捕捉ミドルウェアが反応しない。エラー画面は出るのに監視ツールには何も届かない、という見落としが起きる。<br>
この場合はエラーハンドラ内で明示的に `Sentry.capture_exception` を呼ぶ必要がある（#I-5 で実践）。

<br>

### 監視は「入れる」より「ノイズを出さない」設計が本質

<br>

すべての失敗を通知すると、404 やユーザー操作起因の想定内エラーで画面が埋まり、本当の障害を見逃す。<br>
既定除外（404系）を活かし、外部通信の失敗は「予期しないインフラ障害のみ」に絞り、<br>
既に自動捕捉される経路には手動通知を足さない（二重通知の回避）ことで、通知の信頼性を保つ。

<br>

### 外部SDKのバージョン管理は self-host とCDNのトレードオフを理解して選ぶ

<br>

フロントの Sentry SDK は、CDN 読み込み（更新が楽だが実行時に外部依存）と self-host（更新は手動だが外部障害に強い）の二択。<br>
importmap 構成（バンドラなし）では npm 導入が大改修になるため、self-host を選び、更新手順を README に明記して保守性を担保した。

<br>

### テスト環境の外部SDKは「見えない外部通信」に注意する

<br>

Sentry はイベントを捨てても「破棄統計（client reports）」を溜め、シャットダウン時に送信を試みる。<br>
テストでダミーDSNを使うとこの送信が接続エラーになる。`send_client_reports = false` で統計送信を止め、<br>
外部通信を完全に断つことでテストを安定させた（実装ロジックではなくテストインフラ側の落とし穴）。

<br>

### セキュリティ監査は「grep・静的解析・テスト」を突き合わせて証明する（#I-2）

<br>

「他ユーザーのデータにアクセスできない」ことは、`current_user` スコープの目視だけでなく、<br>
`find` 全数の grep・Brakeman の `CheckUnscopedFind`（未スコープ検索の検出）・全自動テストの三方向で裏付けると、<br>
主観に頼らず機械的に証明できる。Brakeman の `EOLRails` のような「依存の寿命告知」は脆弱性と区別し、理由を残して除外する。

<br>

### メジャーアップグレードは「1 変数ずつ」検証し、Docker は焼き込み構成を理解する（Rails 8.1 / Ruby 3.4.10）

<br>

Rails・Ruby・依存 gem を一度にまとめて上げると、問題発生時の原因切り分けが困難になる。<br>
「Rails → Ruby → 依存 gem（基盤 → 影響大）」の順で 1 つずつ更新し、都度テストを挟むと安全。<br>
また gem をイメージに焼き込む Docker 構成では、`bundle update` 後に `docker compose build` で焼き直さないと、<br>
コンテナ再生成時に旧バージョンへ逆戻りする（`restart` はセッション内でのみ有効）点を理解しておく。

<br>

### 依存の最新化は「自動 PR × 段階マージ」で継続可能にする（Dependabot）

<br>

手動での `bundle update` は後回しになりがちなので、Dependabot で更新を PR 化して仕組みに落とす。<br>
パッチ／マイナーは集約 PR で手軽に、メジャーは個別 PR で慎重に、と分けることで「最新化」と「安定性」を両立できる。<br>
保留したいメジャーは `ignore` で PR を抑制し、対応する時に `ignore` を外す運用にすると、通知ノイズを抑えられる。

<br>

### 無料 PaaS の制約は「隠す」のではなく「明記」する（#I-3）

<br>

Render 無料枠では、深夜 cron が発火しない・SSH/Shell や one-off ジョブが使えない・サーバー応答（TTFB）が遅く Lighthouse Performance が頭打ちになる。<br>
これらは弱点ではなく前提条件であり、README に「既知の制約」として明記した方がポートフォリオとして誠実で評価される。<br>
コードで打てる手（recalc-on-save・キャッシュ制御・アクセシビリティ）は尽くし、残りはインフラ判断として切り分けた。

<br>

### 「テストが落ちた＝直前の変更が原因」とは限らない（#I-3）

<br>

本番確認中、`tasks/ai_edit` のテストが `@task` nil で落ちたが、直前のコントラスト変更（色クラスのみ）とは無関係だった。<br>
実ファイルを確認すると、`tasks/ai_edit.html.erb` に **habits 用（`@habit`）の中身が誤って配置**されていた（同名 `ai_edit.html.erb` の取り違え）。<br>
`git stash` で作業差分を除外して再現するか、`grep -c @task/@habit` で実ファイルを検証すると、変更起因かファイル取り違えかを切り分けられる。<br>
**同名ファイル（`index.html.erb` / `show.html.erb` 等）は、置き場所を必ず 1 行目のパスコメントで確認する。**

<br>

### `db:test:prepare` はテスト前に必ず回す（#I-3）

<br>

`bin/rails test` 単体で不可解な失敗が出たら、まず `db:environment:set RAILS_ENV=development` → `db:test:prepare` でテスト DB を作り直してから切り分ける。<br>
今回はテスト DB は原因ではなかったが、環境要因を先に潰すことで「実バグ」に集中できた。