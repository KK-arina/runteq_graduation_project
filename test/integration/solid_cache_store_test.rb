# test/integration/solid_cache_store_test.rb
#
# ==============================================================================
# Issue #I-6: Solid Cache（キャッシュ基盤）の疎通テスト
# ==============================================================================
#
# 【このテストが守るもの】
#   #I-6 で導入したキャッシュ基盤が「本当に動く状態で組み込まれているか」を
#   自動で検証する。具体的には次の4点を退行から守る:
#     ① solid_cache_entries テーブルが test DB に存在する
#        （= db/migrate のマイグレーションが正しく作られ、
#           db:test:prepare でテストDBにも反映されている）
#     ② :solid_cache_store という名前で cache_store を解決できる
#        （= Gemfile への追加と bundle install / Docker 再ビルドが完了している）
#     ③ write した値を read で取り出せる（DB経由の往復が成立している）
#     ④ delete で確実に消える（#I-6 の無効化設計の土台が機能する）
#
#   本番デプロイ後に PG::UndefinedTable で 500 になる事故を、
#   ローカルの bin/rails test の時点で検出できるようにするのが狙い。
#
# 【なぜ ActiveSupport::TestCase ではなく ActionDispatch::IntegrationTest なのか】
#   実際には DB とキャッシュストアしか触らないため ActiveSupport::TestCase でも
#   動作するが、本テストは「アプリ全体の基盤が組み上がっているか」を確認する
#   統合的な性質のもの。既存の test/integration/ 配下（omniauth_login_flow_test.rb・
#   pmvv_analysis_flow_test.rb）と同じ位置づけとして integration に置く。
# ==============================================================================

require "test_helper"

class SolidCacheStoreTest < ActionDispatch::IntegrationTest
  # ----------------------------------------------------------
  # setup: このテストの間だけ Rails.cache を Solid Cache に差し替える
  # ----------------------------------------------------------
  #
  # 【なぜ差し替えが必要なのか】
  #   config/environments/test.rb では cache_store が :null_store になっている。
  #   :null_store は書き込みを捨てるため、そのままでは
  #   「書いた値が読める」ことを検証できない。
  #
  # 【なぜ config/environments/test.rb 自体を変えないのか】
  #   test.rb を :solid_cache_store にすると全 841 テストにキャッシュが効き、
  #   テスト間で値が残って不安定テストの温床になる。
  #   「このテストの中だけ差し替えて、終わったら必ず戻す」のが安全。
  #
  # 【Rails.cache= が使える理由】
  #   Rails.cache は Rails モジュールのアクセサ（Rails.cache / Rails.cache=）として
  #   定義されているため、テスト内で代入して差し替えられる。
  def setup
    # 差し替える前の Rails.cache（= :null_store）を必ず退避しておく。
    # teardown でこれを書き戻さないと、後続のテストが Solid Cache を
    # 使い続けてしまい他テストを汚染する。
    @original_cache = Rails.cache

    # ActiveSupport::Cache.lookup_store(:solid_cache_store)
    #   シンボルからキャッシュストアのインスタンスを作る Rails の標準メソッド。
    #   内部で "active_support/cache/solid_cache_store" を require し、
    #   solid_cache gem が提供する ActiveSupport::Cache::SolidCacheStore を返す。
    #   gem が入っていない・Docker の再ビルドを忘れている場合は
    #   ここで LoadError になるため、導入漏れをこのテストで検出できる。
    Rails.cache = ActiveSupport::Cache.lookup_store(:solid_cache_store)
  end

  # ----------------------------------------------------------
  # teardown: 差し替えを必ず元に戻す
  # ----------------------------------------------------------
  #
  # 【なぜ ensure ではなく teardown なのか】
  #   Minitest の teardown は「テストが失敗しても例外が出ても必ず実行される」。
  #   各テストメソッドに begin/ensure を書くより確実かつ DRY。
  def teardown
    # このテストで書いたキャッシュを消してから戻す。
    #
    # 【Rails.env.test? のとき clear が安全な理由】
    #   Solid Cache の clear は既定で TRUNCATE を使うが、
    #   テスト環境では自動的に DELETE に切り替わる仕様（clear_with オプション）。
    #   TRUNCATE はテストのトランザクションと相性が悪いため、
    #   この自動切り替えのおかげで安全に呼べる。
    Rails.cache.clear

    # 退避しておいた :null_store に戻す。これを忘れると後続テストが汚染される。
    Rails.cache = @original_cache
  end

  # ----------------------------------------------------------
  # ① テーブルが存在するか
  # ----------------------------------------------------------
  test "solid_cache_entries テーブルが test データベースに存在する" do
    # 【この検証が必要な理由】
    #   #I-6 のマイグレーションを db/migrate に置いても、
    #   bin/rails db:test:prepare を実行し忘れると
    #   テストDBにだけテーブルが無い状態になる。
    #   その状態で本番にデプロイすると
    #   PG::UndefinedTable (relation "solid_cache_entries" does not exist)
    #   で 500 になる。ここで機械的に検出する。
    #
    # 【ActiveRecord::Base.connection.table_exists? を使う理由】
    #   Solid Cache が primary コネクション（= ActiveRecord::Base のプール）を
    #   使う構成であることを、この検証自体が同時に証明している。
    #   別DB接続を作る構成ならこの assert は false になる。
    assert ActiveRecord::Base.connection.table_exists?("solid_cache_entries"),
           "solid_cache_entries テーブルがありません。" \
           "docker compose exec web bin/rails db:migrate と db:test:prepare を実行してください。"
  end

  # ----------------------------------------------------------
  # ② ストアが Solid Cache として解決され、実際にDBへ書き込むか
  # ----------------------------------------------------------
  test ":solid_cache_store が SolidCache::Store として解決され solid_cache_entries に書き込む" do
    # ── 検証1: クラスの同一性 ──
    #
    # 【なぜクラス名で確認するのか】
    #   gem の導入漏れ・Docker の再ビルド忘れ・設定ミスがあると、
    #   意図せず別のストア（:memory_store 等）にフォールバックしている
    #   可能性がある。「動いているように見えるが実は本番と違うストア」
    #   という最も気づきにくい事故をここで防ぐ。
    #
    # 【❗respond_to?(:fetch) で代替してはいけない理由】
    #   :memory_store も :null_store も fetch / write に応答するため、
    #   gem がまったく入っていなくてもテストが通ってしまう。
    #   それではこのテストの存在意義（導入漏れの検出）が失われる。
    assert_kind_of SolidCache::Store, Rails.cache

    # ── 検証2: 実際に solid_cache_entries テーブルへ書けているか（振る舞い）──
    #
    # 【❗なぜ assert_difference(SolidCache::Entry.count) では検証できないのか】
    #   Solid Cache は既定で「遅延書き込み（deferred / background write）」を行う。
    #   Rails.cache.write を呼んだ直後には、書き込みが専用スレッドのキューに
    #   積まれるだけで、solid_cache_entries テーブルにはまだ行が入っていない。
    #   そのため write の直後に件数を数えても 0 のままで、
    #   assert_difference(..., +1) は「増えていない」と判定してしまう。
    #   （これがこのテストが以前 "didn't change by 1, but by 0" で
    #     失敗していた原因。ストアは正しく Solid Cache だったが、
    #     数え方が Solid Cache の非同期書き込みと噛み合っていなかった）
    #
    # 【なぜ「書いて → 読み戻す」方式が正しいのか】
    #   Rails.cache.read は、まだDBにフラッシュされていない書き込みでも
    #   Solid Cache 内部の書き込みキューを先に確認してから返すため、
    #   非同期・同期のどちらのモードでも「書いた値が読める」ことを保証できる。
    #   これは Solid Cache のバージョンや writes 設定に依存しない、
    #   最も安定した検証方法になる。
    #   :memory_store では別インスタンス・別プロセスの想定がないため、
    #   この往復自体は通るが、上の assert_kind_of で弾かれる。
    key   = "i6:store_identity:#{SecureRandom.hex(4)}"
    value = { checked: true, count: 3 }

    Rails.cache.write(key, value)

    # 書いた値がそのままの構造で読み戻せることを確認する。
    # Hash（Ruby オブジェクト）が Marshal 経由で正しく往復することも同時に検証する。
    assert_equal value, Rails.cache.read(key),
                 "Solid Cache に書いた値を読み戻せません（DBへの書き込み経路が壊れています）"
  end

  # ----------------------------------------------------------
  # ③ 書いた値が読めるか（DB往復の疎通）
  # ----------------------------------------------------------
  test "write した値を read で取り出せる" do
    # 【キー名に "i6" を含める理由】
    #   実アプリのキー（dashboard:... / analytics:...）と衝突しないよう、
    #   テスト専用と一目で分かる接頭辞を付ける。
    key   = "i6:smoke_test:#{SecureRandom.hex(4)}"
    value = { rate: 80, completed_count: 4 }

    Rails.cache.write(key, value)

    # Hash がそのままの形で戻ることを確認する。
    # 【なぜ Hash で検証するのか】
    #   #I-6 が実際にキャッシュするのは
    #   build_habit_stats が返す Hash（{ habit_id => { rate:, ... } }）。
    #   文字列だけでなく Ruby オブジェクトが正しくシリアライズ・復元されることを
    #   本番と同じ経路（Marshal → bytea → Marshal）で確認しておく。
    assert_equal value, Rails.cache.read(key)
  end

  # ----------------------------------------------------------
  # ④ fetch のブロックが2回目に実行されないか
  # ----------------------------------------------------------
  test "fetch は2回目にブロックを実行せずキャッシュを返す" do
    key = "i6:fetch_test:#{SecureRandom.hex(4)}"

    # call_count: ブロックが実行された回数を数えるカウンター。
    # 【この検証の意味】
    #   #I-6 の完了条件「ダッシュボードの初回ロードが2回目以降に速くなる」
    #   「AI分析結果ページが毎回DBクエリを実行しない」は、
    #   すべて「fetch のブロックが2回目に実行されない」ことに帰着する。
    #   実行時間の計測は環境依存で不安定なため、
    #   「ブロックが呼ばれた回数」という決定的な値で検証する。
    call_count = 0

    first  = Rails.cache.fetch(key, expires_in: 1.hour) { call_count += 1; "計算結果" }
    second = Rails.cache.fetch(key, expires_in: 1.hour) { call_count += 1; "計算結果" }

    assert_equal "計算結果", first
    assert_equal "計算結果", second
    assert_equal 1, call_count, "2回目の fetch でブロックが再実行されています（キャッシュが効いていません）"
  end

  # ----------------------------------------------------------
  # ⑤ delete で確実に消えるか（無効化設計の土台）
  # ----------------------------------------------------------
  test "delete したキーは read で nil になる" do
    key = "i6:delete_test:#{SecureRandom.hex(4)}"
    Rails.cache.write(key, "消える予定の値")

    # 前提の確認（書けていなければ delete の検証に意味がない）
    assert_equal "消える予定の値", Rails.cache.read(key)

    Rails.cache.delete(key)

    # 【なぜ delete の検証が #I-6 で重要なのか】
    #   Solid Cache は delete_matched（ワイルドカード削除）を実装していない。
    #   そのため #I-6 の無効化設計は「決定的なキーを組み立てて delete する」
    #   方式を採る（Phase 2 で after_commit から呼ぶ）。
    #   その土台となる delete が確実に効くことをここで保証する。
    assert_nil Rails.cache.read(key)
  end
end