# db/migrate/20260717000001_create_solid_cache_entries.rb
#
# ==============================================================================
# Issue #I-6: Solid Cache のキャッシュ保存テーブルを作成する
# ==============================================================================
#
# 【❗なぜ db/cache_schema.rb ではなく通常のマイグレーションなのか】
#   solid_cache には bin/rails solid_cache:install という自動セットアップが
#   用意されているが、これは「Rails 8 のマルチDB構成」を前提としており、
#   db/cache_schema.rb というスキーマファイルを作る。
#   しかし db/cache_schema.rb は「マイグレーションではない」ため、
#   bin/rails db:migrate でも bin/rails db:prepare でも読み込まれない。
#   database.yml に cache: 接続を定義して初めて使われるファイルである。
#
#   HabitFlow は Neon 無料プラン（DBは1つだけ）で運用しており、
#   cache: 接続をあえて作らない方針（config/cache.yml のコメント参照）のため、
#   solid_cache:install は実行せず、この通常マイグレーションで
#   primary データベースに直接テーブルを作る。
#
#   これにより Render の Build Command（bin/rails db:migrate を含む）が
#   デプロイのたびに自動でこのテーブルを作ってくれる。
#
# 【テーブル定義の出どころ】
#   solid_cache 1.0.10 が生成する db/cache_schema.rb と
#   カラム・型・インデックスを完全に一致させている。
#   1つでもズレると SolidCache::Entry が SQL エラーを起こすため、
#   独自の判断でカラムを足したり削ったりしてはいけない。
# ==============================================================================

# ActiveRecord::Migration[7.2]
#   【7.2 を指定する理由】
#     マイグレーションの「振る舞いのバージョン」を宣言する。
#     本アプリは Rails 7.2.3 なので 7.2 を指定する。
#     ネット上のサンプルには [8.0] や [8.1] と書かれているものがあるが、
#     Rails 7.2 環境でそれを使うと
#     「Unknown migration version 8.0」エラーになるので必ず 7.2 にする。
class CreateSolidCacheEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :solid_cache_entries do |t|
      # key: キャッシュキーそのもの（例: "development:dashboard:1:2026-07-13"）
      #
      # 【なぜ string ではなく binary なのか】
      #   キャッシュキーには文字コードに依存しない任意のバイト列が入りうるため、
      #   solid_cache は binary（PostgreSQL では bytea 型）で保持する。
      #   limit: 1024 は「キーの最大バイト数」を示す意図で付いている。
      #   （PostgreSQL の bytea は limit を無視するが、MySQL 等との互換のため
      #     公式スキーマと同じ記述を残す。ここを変えると
      #     Solid Cache 側の max_key_bytesize 既定値 1024 と食い違うため変更しない）
      t.binary :key, limit: 1024, null: false

      # value: キャッシュされた値の本体（Marshal でシリアライズ済みのバイト列）
      #
      # 【limit: 536870912 の意味】
      #   536,870,912 バイト = 512MB。公式スキーマと同じ値。
      #   Rails.cache.fetch に渡した Hash や HTML 断片が
      #   ここにバイナリとして格納される。
      #   有効期限（expires_in）の情報もこの value の中に一緒に入っている。
      t.binary :value, limit: 536870912, null: false

      # created_at: エントリを書き込んだ日時
      #
      # 【なぜ t.timestamps ではないのか】
      #   solid_cache_entries には updated_at カラムが存在しない
      #   （キャッシュは上書き＝新規作成と同義のため更新日時が不要）。
      #   t.timestamps を使うと updated_at まで作られてしまい、
      #   公式スキーマと不一致になるので個別に定義する。
      #
      # 【このカラムの用途】
      #   Solid Cache 自身が max_age（config/cache.yml で7日に設定）を過ぎた
      #   古い行を掃除するための基準として使う。
      #   Rails.cache.fetch の expires_in 判定には使われない。
      t.datetime :created_at, null: false

      # key_hash: key を SHA256 でハッシュ化した 64bit 整数
      #
      # 【なぜ key 本体ではなく key_hash で検索するのか】
      #   1KB のバイナリ（key）に張るインデックスは巨大になり、
      #   DBがメモリ上に保持しきれず遅くなる。
      #   64bit 整数のインデックスは非常にコンパクトなため、
      #   ハッシュ値で引くほうが圧倒的に速い。
      #
      # 【limit: 8 の意味】
      #   8バイト = 64bit → PostgreSQL では bigint 型になる。
      #   limit を書き忘れると 4バイトの integer になり、
      #   ハッシュ値が範囲外になって PG::NumericValueOutOfRange で落ちる。
      t.integer :key_hash, limit: 8, null: false

      # byte_size: この行が占めるおおよそのバイト数
      #
      # 【用途】
      #   Solid Cache がキャッシュの総容量を推定するために使う列。
      #   HabitFlow は config/cache.yml で max_size（容量ベースの上限）ではなく
      #   max_entries（件数ベースの上限）を採用しているため、
      #   実際にはこの列によるサンプリング推定は行われない。
      #
      # 【使わないのに列を作る理由】
      #   solid_cache gem の SolidCache::Entry モデルが
      #   INSERT 時に必ず byte_size を書き込むため、
      #   列が無いと即座に PG::UndefinedColumn で落ちる。
      #   公式スキーマとの完全一致は必須で、独自判断で削ってはいけない。
      #
      # 【limit: 4 の意味】
      #   4バイト = 32bit → PostgreSQL では通常の integer 型。
      t.integer :byte_size, limit: 4, null: false

      # ── インデックス3種（すべて公式スキーマと同一）────────────────────
      #
      # index(byte_size): キャッシュサイズ推定のサンプリングを高速化する
      t.index :byte_size

      # index(key_hash, byte_size): 複合インデックス。
      #   Solid Cache の掃除処理が「key_hash と byte_size だけ」を
      #   SELECT するため、この2列だけでインデックスから答えを返せる
      #   （カバリングインデックス）。テーブル本体を読まずに済み高速。
      t.index [ :key_hash, :byte_size ]

      # index(key_hash) unique: キャッシュ読み書きの主役となるインデックス。
      #   unique: true にすることで、同じキーへの書き込みが
      #   INSERT ... ON CONFLICT (key_hash) DO UPDATE（upsert）として
      #   1回のSQLで完結する。これが無いと upsert が成立せず
      #   同じキーの行が重複して増え続けてしまう。
      t.index :key_hash, unique: true
    end
  end
end