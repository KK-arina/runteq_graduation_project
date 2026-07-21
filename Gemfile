# ==================== Gemfile ====================
# このファイルは、Railsアプリケーションで使用するgemを管理します
# gem: Rubyのライブラリ・パッケージのこと
# bundle install コマンドで、ここに記載されたgemがインストールされます

# ==================== Gemの取得元 ====================
# RubyGemsの公式リポジトリからgemをダウンロード
source "https://rubygems.org"

# ==================== Rubyバージョン指定 ====================
# このアプリケーションで使用するRubyのバージョン
# Docker環境では、Dockerfileで指定したバージョンと一致させる
ruby "3.4.7"

# ==================== フレームワーク ====================

# Rails: Webアプリケーションフレームワーク
# ~> 7.2.3: バージョン7.2.x系の最新版を使用（7.3.0は使わない）
gem "rails", "~> 7.2.3"

# ==================== アセットパイプライン ====================

# sprockets-rails: CSS/JavaScriptファイルを管理・最適化
# Railsの伝統的なアセット管理システム
gem "sprockets-rails"

# ==================== データベース ====================

# pg: PostgreSQLデータベースへの接続用gem
# ~> 1.1: バージョン1.1.x系を使用
gem "pg", "~> 1.1"

# ==================== Webサーバー ====================

# Puma: 高性能なRails用Webサーバー
# ~> 7.0 の意味:
# 「7.0 以上 8.0 未満」を許可する。
# ログで Puma 7.1.0 が動作していることが確認できているため 7.x 系に固定する。
# >= 5.0 では 6系・7系・8系すべてインストール対象になり、
# メジャーバージョンアップで予期しない挙動変化が起きるリスクがある。
gem "puma", "~> 7.0"

# ==================== フロントエンド（JavaScript） ====================

# importmap-rails: JavaScriptをESモジュールとして管理
# Node.jsやwebpackを使わずにJavaScriptを扱える
gem "importmap-rails"

# turbo-rails: Hotwireの一部、ページ遷移を高速化
# SPAのような体験をJavaScriptなしで実現
gem "turbo-rails"

# stimulus-rails: Hotwireの一部、軽量なJavaScriptフレームワーク
# 必要な部分だけJavaScriptで動きを追加
gem "stimulus-rails"

# ==================== フロントエンド（CSS） ====================

# tailwindcss-rails: Tailwind CSSをRailsで使用
# ユーティリティファーストのCSSフレームワーク
gem "tailwindcss-rails"

# ==================== API・JSON ====================

# jbuilder: JSONレスポンスを簡単に構築
# APIエンドポイントを作る際に便利
gem "jbuilder"

# ==================== 認証 ====================

# bcrypt: パスワードをハッシュ化して安全に保存
# has_secure_passwordメソッドを使用する際に必須
# Issue #5で使用開始
gem "bcrypt", "~> 3.1.7"

# ============================================================
# F-5 追加: rack-attack（ブルートフォース対策・レート制限）
# ============================================================
#
# 【rack-attack とは何か】
#   Rack ミドルウェアとして動作するリクエスト制限ライブラリ。
#   Rails のコントローラーより手前の Rack 層でリクエストを検査・遮断するため、
#   コントローラーに到達する前に不正アクセスをブロックできる。
#
# 【なぜ rack-attack を使うのか】
#   ブルートフォース攻撃（パスワードを何度も試みる攻撃）に対して
#   IP アドレスごとにログイン試行回数を制限し、一定回数を超えたら
#   一定時間アクセスをブロックする。
#   Rails の has_secure_password だけではこの制御はできない。
#
# 【バージョンを ~> 6.8 で固定する理由】
#   最新安定版は 6.8.0（2025年10月14日リリース）。
#   ~> 6.8 は「6.8.x の最新パッチ」を許可しつつ、
#   7.0 への破壊的変更を自動で取り込まないよう制限する。
#   Redis 不要で Rails.cache（メモリキャッシュ）だけで動作する。
gem "rack-attack", "~> 6.8"

# ============================================================
# F-1 追加: OmniAuth Google OAuth2 ログイン
# ============================================================
#
# 【omniauth-google-oauth2 とは何か】
#   Google アカウントでのログイン・新規登録を実現する gem。
#   OmniAuth という認証統一インターフェースの Google 専用実装。
#   バージョン 1.x は OmniAuth 2.x に対応した安定版。
#
# 【omniauth-rails_csrf_protection とは何か】
#   OmniAuth の認証開始リクエスト（POST /auth/google_oauth2）に
#   Rails の CSRF 保護を適用するための gem。
#   CVE-2015-9284（CSRF 脆弱性）への対策として必須。
#   button_to で POST する際に authenticity_token を検証してくれる。
gem "omniauth-google-oauth2", "~> 1.2"
gem "omniauth-rails_csrf_protection"

# ==================== 非同期ジョブ処理 ====================
#
# ============================================================
# Issue #A-3: GoodJob 導入
# ============================================================
#
# 【GoodJobとは何か】
# Railsには「ActiveJob」という非同期処理の統一インターフェースがある。
# GoodJobはそのActiveJobのバックエンド（実際の実行エンジン）として機能する。
#
# 【なぜGoodJobを選んだのか】
# 非同期処理のバックエンドには複数の選択肢がある:
#   - Sidekiq  → 高性能だが「Redis」という別のデータベースが必要
#   - Resque   → 同様に Redis が必要
#   - GoodJob  → PostgreSQL のみで動作。Redis 不要！
#
# HabitFlow は Render（無料）+ Neon PostgreSQL で運用している。
# GoodJob なら既存の PostgreSQL をそのまま使えるため構成がシンプル。
#
# 【GoodJobが担う機能】
#   - AI 分析ジョブ（PMVV・週次振り返りのAI分析を非同期実行）
#   - LINE 通知送信（タスクのアラーム通知）
#   - CSV エクスポート（大量データの非同期生成）
#   - ストリーク計算バッチ（毎日AM4:05に全ユーザー対象）
#   - AI 使用回数の月次リセット（毎月1日00:00）
#   - 日次通知カウントリセット（毎日00:05）
#
# 【バージョンを固定しない理由】
# GoodJob はバージョンによって設定 API とDBスキーマが変わる:
#   3.3.x   → Rails 7.2 の新API（enqueue_after_transaction_commit?）に未対応
#   3.30.1  → 3.x 系の最終安定版
#   3.99.x  → 4.x への移行版
#   4.x     → Rails 7.2 / 8.x 正式対応。最新の設計。← これを使用
#
# バージョンを固定しないことで:
#   - セキュリティパッチが自動で適用される
#   - Rails のアップグレード時に追従しやすい
#
# 【4.x を使う際の注意点】
# GoodJob 4.x では DBスキーマに新しいカラムが追加されている。
# good_job:install（初回）ではなく good_job:update でマイグレーションを追加する。
gem "good_job"

# ============================================================
# Issue #D-2: Faraday（HTTP クライアント）
# ============================================================
#
# 【なぜ gem なしで faraday だけ使うのか】
# Google 公式の Gemini Ruby SDK は存在しない（2026年4月時点）。
# サードパーティ gem は API 変更で突然壊れるリスクがある。
# faraday で Gemini REST API を直接呼ぶ方が:
#   - 公式ドキュメント通りの安定した実装ができる
#   - gem の依存関係トラブルがない
#   - Groq API（OpenAI 互換）も同じ faraday で統一できる
#
# 【faraday とは】
# Ruby で HTTP リクエストを送るための汎用ライブラリ。
# タイムアウト・JSON 変換・リトライをシンプルに設定できる。
gem "faraday"

# ============================================================
# Issue #A-4: Resend メール送信サービス用 Gem
# ============================================================
#
# 【Resendとは何か】
# Resend は開発者向けに設計されたメール送信サービス（ESP）。
# 無料枠: 月3,000通 / 1日100通（クレカ不要）
#
# 【なぜResendを選んだのか】
# 他サービスとの比較:
#   SendGrid → 無料枠あり(100通/日)だが登録にクレカが必要
#   Mailgun  → 無料枠終了後に有料・設定がやや複雑
#   AWS SES  → AWS設定が複雑・サンドボックス解除が必要
#   Resend   → クレカ不要・月3,000通無料・Rails用gemが公式提供 ← 採用
#
# 【resend gemの役割】
# Action Mailerの delivery_method に :resend を指定できるようになる。
# これにより既存のメイラークラスは一切変更せず、
# 「送信エンジンだけResendに切り替える」構成が実現できる。
# 将来別のサービスに乗り換える際もこのgemを変えるだけでよい。
#
# 【バージョンを固定しない理由】
# セキュリティパッチを自動で取り込むため。
# Resend APIの後方互換性はResendが保証しているので最新版を追う。
gem "resend"

# ============================================================
# Issue #I-5: Sentry（エラー監視・本番ログ基盤）
# ============================================================
#
# 【Sentry とは何か】
#   本番環境で発生した例外（Railsエラー・AI APIエラー・ジョブ失敗など）を
#   リアルタイムに収集・通知してくれるエラー監視サービス。
#   無料枠（Developer プラン）で月5,000エラーまで無料。クレカ不要。
#
# 【なぜ2つの gem に分かれているのか】
#   sentry-ruby  … Ruby 汎用のコア（Sentry.capture_exception 等の本体）
#   sentry-rails … Rails 専用の統合。これを入れるだけで、
#                  ①コントローラで捕捉されなかった例外
#                  ②ActiveJob（=GoodJob）内で raise された例外
#                  を「設定なしで自動的に」Sentry へ送ってくれる。
#   AiClient は既に Sentry.capture_exception を呼ぶ実装（D-11）になっているため、
#   この gem を入れるだけで AI API エラーの通知も自動で有効になる。
#
# 【なぜ ~> 6.6 で固定するのか】
#   最新安定版は 6.6.2（2026年6月9日・MITライセンス・無料）。
#   ~> 6.6 は「6.6 以上 7.0 未満」を許可し、7.0 への破壊的変更を自動で
#   取り込まないようにする。必要 Ruby は >= 2.7（本アプリは 3.4.7）、
#   sentry-rails は railties >= 5.2 依存のため Rails 7.2.3 で問題なく動作する。
#   ネイティブ拡張を持たない純 Ruby gem なので、Gemfile.lock の
#   PLATFORMS（x86_64-linux 系）でもビルド不要でインストールできる。
gem "sentry-ruby", "~> 6.6"
gem "sentry-rails", "~> 6.6"

# ==================== パフォーマンス ====================

# bootsnap: アプリケーションの起動を高速化
# キャッシュを使って読み込み時間を短縮
# config/boot.rbで自動的に読み込まれる
gem "bootsnap", require: false

# ==================== タイムゾーン ====================

# tzinfo-data: タイムゾーン情報を提供
# WindowsやJRuby環境で必須（Linux/Macでは不要だが害もない）
gem "tzinfo-data", platforms: %i[ windows jruby ]

# ==================== 開発環境・テスト環境のみ ====================
# bundle install --without development test で除外可能

group :development, :test do
  # debug: デバッグ用gem
  # binding.break でコードを一時停止してデバッグ可能
  # platforms: %i[ mri windows ]: 標準Ruby（MRI）とWindows環境のみ
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # brakeman: セキュリティ脆弱性を自動検出
  # SQLインジェクション、XSSなどの脆弱性をチェック
  # require: false: 自動読み込みしない（コマンドラインツールとして使用）
  gem "brakeman", require: false

  # rubocop-rails-omakase: Railsのコーディング規約チェック
  # コードの品質を保つための静的解析ツール
  # require: false: 自動読み込みしない（コマンドラインツールとして使用）
  gem "rubocop-rails-omakase", require: false

  # ==============================================================================
  # minitest バージョン固定
  # ==============================================================================
  #
  # 【なぜ固定するのか】
  # GoodJob 3.3.x が minitest 6.x を依存関係として引き込む。
  # Rails 7.2 の test ヘルパーは minitest 5.x を前提としており、
  # 6.x が入ると run メソッドの引数が変わり
  # 「wrong number of arguments (given 3, expected 1..2)」エラーが発生する。
  # ~> 5.1 で 5.x 系の最新版に固定してバージョン競合を防ぐ。
  gem "minitest", "~> 5.1"
end

# ============================================================
# Issue #B-6: acts_as_list（習慣の並び替え）
# ============================================================
#
# 【acts_as_list とは何か】
# DB テーブルの「position カラム」を使って、レコードの順番を管理するための gem。
# リスト操作（上に移動・下に移動・先頭に移動）をシンプルなメソッドで実現できる。
#
# 【なぜ position カラムを直接操作しないのか】
# 並び替えでは「他の行の position も一緒に更新する」必要がある。
# 例: position=3 のアイテムを position=1 に移動するとき、
#     もともと position=1 と position=2 だったアイテムを
#     それぞれ 2 と 3 にずらさなければならない。
# acts_as_list がこの複雑な更新を自動で行ってくれる。
#
# 【schema.rb との対応】
# habits テーブルには既に position カラム（integer）が存在している。
# (t.integer "position" および index ["user_id", "position"])
# そのため、このタスクでは DB マイグレーションは不要。
gem "acts_as_list"

# ==================== 将来のRubyバージョン互換性 ====================
#
# ============================================================
# ostruct（将来の Ruby 3.5 デフォルトgem除外への事前対応）
# ============================================================
#
# 【この警告が出ていた理由】
#   test/services/line_notification_service_test.rb が OpenStruct を使用しているが、
#   現在（Ruby 3.4系）は ostruct が「デフォルトgem」として標準ライブラリに
#   バンドルされているため、明示的に Gemfile に書かなくても動いていた。
#
#   実行時に以下の警告が出る:
#     "ostruct.rb was loaded from the standard library,
#      but will no longer be part of the default gems starting from Ruby 3.5.0."
#
# 【なぜ「警告だから無視してよい」では済まされないのか】
#   Ruby 3.5 がリリースされ、プロジェクトをそのバージョンに上げた瞬間、
#   ostruct は標準では読み込まれなくなり LoadError でテストスイート全体が
#   即座に落ちる。警告は「今のうちに直しておけ」という事前通知であり、
#   放置すると将来必ず壊れることが確定している。
#
# 【gem "ostruct" を追加するとなぜ警告が消えるのか】
#   Gemfile に明記すると、Ruby の標準添付gemの仕組みではなく
#   Bundler がRubyGems経由で ostruct を管理するようになる。
#   これにより「標準ライブラリからの読み込み」という警告の発生条件自体が
#   なくなり、Ruby 3.5 になっても同じコードのまま動き続ける。
#
# 【development/test グループに限定せず、全環境で読み込む理由】
#   現時点で確認できているのは test/services/line_notification_service_test.rb
#   での使用だが、Rails本体や依存gem（Active Support 等）が内部的に
#   OpenStruct を使うケースもゼロではない。
#   1行追加するだけの低リスクな変更のため、環境を限定せず
#   全グループ共通（production含む）で読み込めるようにしておくことで
#   「テスト環境では動くが本番では LoadError になる」という事故を未然に防ぐ。
#
# 【バージョンを固定しない理由】
#   faraday・resend・good_job など、このGemfile内の他のユーティリティ系gemと
#   同様にバージョン固定せず、Bundlerに最新の安定版を解決させる。
gem "ostruct"

# ==================== 開発環境のみ ====================

group :development do
  # web-console: ブラウザ上でRailsコンソールを使用
  # エラー画面で直接コードを実行してデバッグ可能
  gem "web-console"

  # ============================================================
  # Issue #A-4: letter_opener（開発環境のメール確認用）
  # ============================================================
  #
  # 【なぜ開発環境にletter_openerが必要なのか】
  # 開発中にResendで実際にメールを送信してしまうと:
  #   - 無料枠（月3,000通）を無駄に消費する
  #   - 実在するアドレスに誤ってメールが届く危険がある
  #   - テストのたびにメールボックスを確認する手間がかかる
  #
  # letter_openerを使うと:
  #   - メールを実際に送信せずブラウザ上でプレビューできる
  #   - 件名・本文・HTMLの見た目を即座に確認できる
  #   - 開発スピードが大幅に上がる
  #
  # 【production環境には含めない理由】
  # development グループに限定することで、本番環境では
  # letter_openerが読み込まれず、Resendが使われる。
  #
  # 【なぜ letter_opener_web に変更するのか】
  #   letter_opener は送信時にブラウザを自動で開こうとするが、
  #   Docker コンテナ内にはブラウザが存在しないため開かれない。
  #   letter_opener_web は /letter_opener にアクセスするだけで
  #   送信済みメールの一覧を確認できる Web UI を提供する。
  #   Docker 環境での開発に最適。
  gem "letter_opener_web"

  # ============================================================
  # Issue #A-6: Bullet（N+1問題の自動検出）
  # ============================================================
  # bullet: N+1問題（必要以上にDBクエリが発行される問題）を
  # 自動で検出してくれるgemです。
  #
  # 【N+1問題とは？】
  # 例えば10件の習慣を表示するとき、各習慣の記録を
  # ループの中で毎回DBから取得すると
  # 「1(習慣一覧) + 10(記録取得)」= 11回のSQLが発行されてしまいます。
  # includesを使って事前に一括取得すれば「2回」のSQLで済みます。
  #
  # 【なぜ development グループのみか？】
  # Bulletは開発中にN+1を検出するためのツールです。
  # 本番環境で動かすとパフォーマンスが落ちるため、開発環境のみに限定します。
  gem "bullet"

  # ============================================================
  # Issue #A-6: rack-mini-profiler（クエリパフォーマンス可視化）
  # ============================================================
  #
  # 【rack-mini-profilerとは】
  # ブラウザの画面左上に「ページのSQLクエリ数・実行時間」を
  # リアルタイムで表示してくれるgemです。
  # どの画面でN+1が残っているか、どのクエリが遅いかを
  # ブラウザ上で視覚的に確認できます。
  #
  # 【require: false の意味】
  # Railsは通常gemを自動で読み込みますが（auto-require）、
  # require: false を指定すると自動読み込みをしません。
  # config/initializers/rack_mini_profiler.rb で
  # 明示的に require することで制御します。
  #
  # 【なぜ development グループのみか】
  # 本番環境でパフォーマンス情報を外部に見せないためです。
  # セキュリティ上、本番では絶対に有効化してはいけません。
  gem "rack-mini-profiler", require: false
end

# ==================== テスト環境のみ ====================

group :test do
  # capybara: E2Eテスト（ブラウザ操作テスト）用gem
  # ユーザーの操作をシミュレートしてテスト
  gem "capybara"

  # selenium-webdriver: ブラウザ自動操作ツール
  # Capybaraと組み合わせて、実際のブラウザでテスト
  gem "selenium-webdriver"
end

# ── D-3 追加: 開発環境で Turbo Stream を動かすための Action Cable アダプター ──
# solid_cable: PostgreSQL をブローカーとして使う Action Cable アダプター。
# Redis 不要で、既存の DB（PostgreSQL）を通じてプロセス間通信ができる。
# これにより GoodJob のバックグラウンドスレッドからブラウザへの
# Turbo Stream 通知が開発環境でも正しく届くようになる。
# 【参考】https://github.com/rails/solid_cable
gem "solid_cable"

# ============================================================
# Issue #I-6: Solid Cache（Redis不要のキャッシュストア）
# ============================================================
#
# 【Solid Cache とは何か】
#   PostgreSQL のテーブル（solid_cache_entries）を保存先として使う
#   ActiveSupport::Cache::Store の実装。
#   Rails.cache.fetch / Rails.cache.write などの標準APIがそのまま使える。
#
# 【なぜ Solid Cache を選ぶのか】
#   キャッシュの保存先には複数の選択肢がある:
#     - Redis / Memcached → 別サーバーが必要。Render では有料アドオンになる
#     - :memory_store     → プロセスごとに別のキャッシュを持つ。
#                            本番は Puma Worker が2つ動いているため、
#                            Worker1 が消したキャッシュが Worker2 に残り
#                            「古いデータが表示され続ける」事故が起きる
#     - :file_store（Rails既定） → Render はデプロイのたびにファイルが消える
#                                   （エフェメラルなファイルシステム）
#     - Solid Cache       → 既存の Neon PostgreSQL をそのまま使える。
#                            全 Worker が同じテーブルを見るため上記の不整合が起きない ← これを採用
#
#   HabitFlow は既に GoodJob（PostgreSQLベースのジョブ基盤）と
#   solid_cable（PostgreSQLベースの Action Cable）を採用しており、
#   「Redis を足さずに PostgreSQL だけで完結させる」という一貫した方針に合致する。
#
# 【なぜ "~> 1.0" でバージョンを固定するのか】
#   最新安定版は 1.0.10（2025年11月8日リリース・MITライセンス・無料）。
#   ~> 1.0 は「1.x 系の最新版」を許可し、2.0 への破壊的変更を自動で取り込まない。
#   solid_cable を "solid_cable"（固定なし）で書いている箇所もあるが、
#   Solid Cache は Rails 8 で標準採用された関係でメジャーバージョンが上がる
#   可能性があるため、rack-attack や omniauth-line-v2_1 と同じく明示的に固定する。
#
# 【Rails 7.2.3 で使えるのか】
#   solid_cache 1.0.10 の依存は activejob / activerecord / railties が
#   すべて ">= 7.2"。本アプリは Rails 7.2.3 なので条件を満たす。
#   Rails 8 では標準バックエンドになるため、将来 Rails 8 へ上げる際も
#   この gem 行を消すだけで移行できる（設定コードはそのまま使える）。
#
# 【参考】https://github.com/rails/solid_cache
gem "solid_cache", "~> 1.0"

# ==================== コメントアウト（未使用）のgem ====================

# Redis: インメモリデータベース
# Action Cable（WebSocket）やキャッシュで使用
# GoodJobを使うためRedisは不要
# gem "redis", ">= 4.0.1"

# Kredis: Redisをより便利に使うためのgem
# 現在は不要なのでコメントアウト
# gem "kredis"

# image_processing: 画像のリサイズ・変換
# Active Storageで画像を扱う際に必要
# 現在は不要なのでコメントアウト
# gem "image_processing", "~> 1.2"

# ============================================================
# F-2 追加: OmniAuth LINE ログイン
# ============================================================
#
# 【omniauth-line-v2_1 とは何か】
#   LINE アカウントでのログイン・新規登録を実現する gem。
#   OmniAuth 2.x に完全対応した公式互換の LINE ストラテジー。
#   旧 omniauth-line（kazasiki版）は OmniAuth 1.x 向けで廃止済み。
#   cadenza-tech 社製の omniauth-line-v2_1 が 2025年に新規開発され
#   最新の OmniAuth 2.x / Rails 7.x 環境で安定稼働する。
#   gem 名と require 名が異なる点に注意（require: "omniauth/line_v2_1"）。
#
# 【なぜ ~> 1.2 でバージョン固定するのか】
#   1.2.0 が 2025年11月の最新安定版。
#   ~> 1.2 は「1.2.x の最新パッチ」を許可し、2.0 への破壊的変更を防ぐ。
gem "omniauth-line-v2_1", "~> 1.2"