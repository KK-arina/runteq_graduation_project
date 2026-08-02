require "active_support/core_ext/integer/time"

Rails.application.configure do
  # ============================================================
  # 基本設定
  # ============================================================

  # cache_classes: true
  #   本番環境ではクラスをキャッシュする（変更があっても再読み込みしない）。
  #   開発環境では false にしてコード変更を即時反映させるが、
  #   本番環境では true にしてパフォーマンスを最大化する。
  config.cache_classes = true

  # eager_load: true
  #   アプリ起動時にすべてのコードを一括で読み込む。
  #   本番環境では必須（起動は遅くなるが、リクエスト処理が速くなる）。
  #   また、マルチスレッド環境での競合状態（Race Condition）を防ぐ。
  config.eager_load = true

  # ============================================================
  # 静的ファイル配信
  # ============================================================

  # public_file_server.enabled:
  #   環境変数 RAILS_SERVE_STATIC_FILES が設定されている場合、
  #   Rails が静的ファイル（CSS, JS, 画像など）を直接配信する。
  #   Render では Nginx などのリバースプロキシがないため、この設定が必要。
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # ============================================================
  # SSL / HTTPS 設定
  # ============================================================

  # assume_ssl: true
  #   Render のロードバランサーは HTTPS を受け取った後、
  #   Rails に HTTP として転送する（SSL終端）。
  #   この設定を true にすることで、Rails が「自分は HTTPS で動いている」
  #   と正しく認識できる。
  #   これがないと request.ssl? が false になり、
  #   redirect_to が HTTP URL を生成してしまう問題が起きる。
  config.assume_ssl = true

  # force_ssl: true
  #   HTTP でアクセスしてきたリクエストを HTTPS にリダイレクトする。
  #   同時に以下のセキュリティ機能も有効になる:
  #   - Strict-Transport-Security（HSTS）ヘッダーの付与
  #     → 一度 HTTPS でアクセスしたブラウザは、
  #       次回から強制的に HTTPS を使う（中間者攻撃を防ぐ）
  #   - secure フラグ付き Cookie の強制
  #     → Cookie が HTTPS 通信でのみ送信されるようになる
  config.force_ssl = true

  # ============================================================
  # ログ設定（Issue #35: 本番環境最適化）
  # ============================================================

  # ------------------------------------------------------------
  # 1. ログレベルの設定
  # ------------------------------------------------------------
  # :info を採用する理由：
  #
  # 本番環境では以下の情報を記録すれば十分：
  # - リクエスト開始（Started GET "/dashboard"）
  # - コントローラー処理（Processing by DashboardsController#index）
  # - レスポンス終了（Completed 200 OK in 45ms）
  # - エラー情報（ERROR -- : ActiveRecord::RecordNotFound）
  #
  # :debug にすると全 SQL 文が出力されログが爆発的に増え、
  # ストレージを圧迫しパフォーマンスが低下するため
  # 本番環境では :info がベストプラクティス。
  #
  # ログレベルの種類（詳細度の低い順）:
  # :debug → 全情報（SQL含む）。開発向け。
  # :info  → アクセスログ＋エラー。本番向け。← HabitFlow はここ
  # :warn  → 警告とエラーのみ。
  # :error → エラーのみ。
  # :fatal → 致命的エラーのみ。
  config.log_level = :info

  # ------------------------------------------------------------
  # 2. STDOUT 出力設定（Render 対応）
  # ------------------------------------------------------------
  # なぜ STDOUT（標準出力）に出力するのか？:
  # Render のようなクラウド環境（PaaS）は「コンテナの標準出力」を
  # 自動で収集してダッシュボードに表示する仕組みになっている。
  # コンテナ内のファイルにログを書いても、コンテナ再起動で消えてしまうため
  # ファイル出力は使わない。STDOUT への出力が PaaS のベストプラクティス。
  #
  # なぜ ENV["RAILS_LOG_TO_STDOUT"] で条件分岐するのか？:
  # render.yaml で RAILS_LOG_TO_STDOUT=true を設定することで
  # Render 環境でのみ STDOUT ロガーを有効にできる。
  # 将来、別のホスティング環境（AWS等）に移行する際も
  # この環境変数を設定するだけで対応できる。
  # コードを書き換えずに環境ごとの挙動を切り替えられるのが利点。
  #
  # なぜ TaggedLogging を使うのか？:
  # 複数のユーザーが同時にアクセスした際、どの行が誰のリクエストなのか
  # 判別できるように「リクエスト ID タグ」を付けるためのラッパー。
  # log_tags の :request_id と組み合わせることで機能する。
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    # STDOUT へ書き出すロガーを作成
    logger           = ActiveSupport::Logger.new(STDOUT)

    # ログの形式（タイムスタンプ・重要度・メッセージ）を Rails 標準形式に設定
    # config.log_formatter は Rails がデフォルトで持つフォーマッターを返す
    logger.formatter = config.log_formatter

    # タグ付け機能（log_tags）を有効化してロガーを確定
    config.logger    = ActiveSupport::TaggedLogging.new(logger)
  end

  # ------------------------------------------------------------
  # 3. リクエスト ID タグの付与
  # ------------------------------------------------------------
  # 各ログ行の先頭に [abc123ef] のようなリクエスト ID を付与する。
  #
  # これにより、特定のユーザーでエラーが起きた際に
  # そのリクエスト ID でログを絞り込んで一連の流れを追跡できる:
  # [abc123ef] Started POST "/habits"
  # [abc123ef] Processing by HabitsController#create as HTML
  # [abc123ef] ERROR -- : ActiveRecord::RecordInvalid
  # [abc123ef] Completed 422 Unprocessable Entity in 15ms
  #
  # TaggedLogging（上の logger 設定）が有効なときのみ機能する。
  config.log_tags = [ :request_id ]

  # ------------------------------------------------------------
  # 4. 機密情報の保護（参照）
  # ------------------------------------------------------------
  # パスワード・メールアドレス・トークンなどの機密情報は
  # config/initializers/filter_parameters.rb で設定されており、
  # ログ上では自動的に [FILTERED] に置換される。
  # エンジニアでもユーザーのパスワードをログから見ることはできない。

  # ============================================================
  # Issue #28: セキュリティレスポンスヘッダーの追加設定
  # ============================================================
  # HTTP レスポンスヘッダーにセキュリティ関連の設定を付与することで、
  # ブラウザ側でも攻撃を防御できるようにする。
  #
  # 【重要】merge! を使う理由
  #   = （代入）で書くと Rails 7.2 がデフォルトで設定している
  #   Content-Security-Policy や Permissions-Policy などの
  #   重要なセキュリティヘッダーがすべて消えてしまう。
  #   merge! を使うことで「既存のヘッダーを維持しつつ追加・上書き」できる。
  #
  # 【Rails 7.2 のデフォルトヘッダー（merge! で維持されるもの）】
  #   - Content-Security-Policy（CSP）
  #   - Permissions-Policy
  #   - X-Content-Type-Options: nosniff（すでに設定済み）
  #   これらを消さないために merge! は必須。
  config.action_dispatch.default_headers.merge!(
    {
      # X-Frame-Options: SAMEORIGIN
      #   このページを <iframe> で埋め込めるのを同一オリジンのみに制限する。
      #   「クリックジャッキング攻撃」を防ぐ。
      #   クリックジャッキング: 攻撃者が透明な iframe でターゲットサイトを重ね、
      #   ユーザーに意図せずクリックさせる攻撃。
      "X-Frame-Options"          => "SAMEORIGIN",

      # X-XSS-Protection: 0
      #   古いブラウザの XSS フィルター機能を無効にする。
      #   なぜ "0"（無効）にするのか？
      #   → 古い XSS フィルターはむしろ新しい XSS 攻撃の踏み台になることがある。
      #   → 現代は Content-Security-Policy（CSP）で対策するのが標準。
      #   → W3C・Google・Mozilla も "0" 推奨。
      "X-XSS-Protection"         => "0",

      # X-Content-Type-Options: nosniff
      #   ブラウザが Content-Type を無視してファイルの内容から
      #   MIMEタイプを推測する「MIME スニッフィング」を禁止する。
      #   攻撃者が画像ファイルに見せかけた JavaScript をアップロードしても
      #   実行されなくなる。
      "X-Content-Type-Options"   => "nosniff",

      # X-Download-Options: noopen
      #   Internet Explorer 専用の設定。
      #   ダウンロードしたファイルをブラウザ内で直接開けないようにする。
      "X-Download-Options"       => "noopen",

      # X-Permitted-Cross-Domain-Policies: none
      #   Adobe Flash / Acrobat が別ドメインからデータを読み込む際の制限。
      "X-Permitted-Cross-Domain-Policies" => "none",

      # Referrer-Policy: strict-origin-when-cross-origin
      #   リンクをクリックしたときにどの URL 情報を遷移先のサーバーに送るかを制御する。
      #
      #   strict-origin-when-cross-origin の動作:
      #   - 同一オリジン内のリンク → フルURL（パス含む）を送信
      #   - 別オリジンへのリンク  → オリジン部分のみ送信（パスは送らない）
      #   - HTTP → HTTPS へのリンク → Referer を送らない
      #
      #   URL に含まれるトークンなどの機密情報が外部サイトに漏れるのを防ぐ。
      "Referrer-Policy"          => "strict-origin-when-cross-origin"
    }
  )

  # ============================================================
  # Issue #A-3: 本番環境の GoodJob execution_mode 設定
  # ============================================================
  #
  # 【:async に変更した理由】
  # RenderのBackground WorkerはFreeプランが存在しない（最低$7/月）。
  # ポートフォリオ用途のため費用をかけない方針で
  # :external（別Workerプロセス必要）から :async（Webプロセス内で実行）に変更。
  #
  # 【:async モードの動作】
  # PumaのWebプロセス内でGoodJobがバックグラウンドスレッドを起動してジョブを処理する。
  # Workerを別途起動しなくてもジョブが実行される。
  #
  # 【:async の注意点・制約】
  # ① Webが落ちるとジョブも停止するが、GoodJobはPostgreSQLにジョブを保存しているため
  #   再起動後に自動で再実行される（ジョブは消えない）
  # ② 重い処理（CSV生成・AI分析）はWebのレスポンス速度に影響する可能性がある
  # ③ Render Freeプランはリソースが少ないため、スレッド数を制限して暴走を防ぐ
  #
  # 【将来有料プランに移行する場合】
  # execution_mode を :external に戻し、render.yaml の Worker設定を有効化する。
  config.good_job.execution_mode = :async

  # ============================================================
  # GoodJob 最大スレッド数の制限
  # ============================================================
  #
  # 【なぜ max_threads を制限するのか】
  # GoodJob のデフォルトスレッド数は 5。
  # Render Freeプランは CPU・メモリが限られているため
  # スレッドを無制限に立てるとアプリ全体が遅くなる・落ちる可能性がある。
  #
  # 【2に設定する理由】
  # Webプロセス: Puma Worker(2) × Thread(3) = 最大6コネクション
  # GoodJob:     2スレッド × 1コネクション = 最大2コネクション
  # 合計: 8コネクション → Neon無料プランの上限（10〜20）以内で安全
  #
  # 【スレッド数を増やしたい場合】
  # Neonの接続上限を超えないよう計算してから変更すること
  config.good_job.max_threads = 2

  # ============================================================
  # Issue #I-6: キャッシュストアの設定（Solid Cache）
  # ============================================================
  #
  # 【変更前の状態と、それが問題だった理由】
  #   これまで production.rb に config.cache_store の記述が無かったため、
  #   Rails の既定値である :file_store（tmp/cache 配下にファイルを書く）が
  #   使われていた。これは Render では2重の意味で機能しない:
  #     ① Render はデプロイのたびにコンテナを作り直すため、
  #        tmp/cache のファイルは毎回消える（エフェメラルなファイルシステム）
  #     ② Puma は Worker 2プロセス構成のため、Worker1 が書いたキャッシュを
  #        Worker2 が消せず、片方だけ古い値を返し続ける事故が起きうる
  #
  # 【:solid_cache_store にすると何が変わるか】
  #   キャッシュの実体が PostgreSQL（Neon）の solid_cache_entries テーブルになる。
  #     ・デプロイしてもキャッシュが残る（DBは永続）
  #     ・全 Worker が同じテーブルを見るため、無効化が全プロセスに即時反映される
  #     ・Redis を追加しないので Render の追加コストが 0 円のまま
  #
  # 【接続先はどこになるのか】
  #   config/cache.yml で database: を指定していないため、
  #   Solid Cache は ActiveRecord::Base のコネクションプール（= primary）を使う。
  #   つまり Neon の既存DBの中に solid_cache_entries が作られ、
  #   新しいコネクションプールは一切増えない（Neon の接続上限を守れる）。
  #
  # 【テーブルが無いとどうなるか】
  #   最初のキャッシュアクセスで
  #   PG::UndefinedTable (relation "solid_cache_entries" does not exist)
  #   が発生して 500 エラーになる。
  #   Render の Build Command には bin/rails db:migrate が含まれており、
  #   #I-6 のマイグレーション（db/migrate 配下）が起動前に適用されるため
  #   この事故は起きない。Build Command は変更不要。
  config.cache_store = :solid_cache_store

  # ------------------------------------------------------------
  # フラグメントキャッシュの有効化を明示する
  # ------------------------------------------------------------
  # perform_caching: true
  #   ビューの <% cache ... do %> ブロック（フラグメントキャッシュ）を
  #   実際に機能させるためのスイッチ。
  #
  # 【もともと Rails の既定値が true なのに、なぜあえて書くのか】
  #   ① development.rb には明示されているのに production.rb には無く、
  #      「本番でキャッシュが効いているのか」がコードを読んだだけでは分からない
  #   ② #I-6 で 18番（AI分析結果）ページにフラグメントキャッシュを入れるため、
  #      この設定が前提であることをコード上に残しておきたい
  #   ③ 将来 Rails をアップグレードして既定値が変わった場合でも
  #      挙動が変わらないよう固定する
  #   動作は変わらない（既定値と同じ true を明示するだけ）ので安全な追記。
  config.action_controller.perform_caching = true

  # ============================================================
  # Issue #A-4 / #I-3: Action Mailer 本番環境設定（Resend）
  # ============================================================

  # 送信エンジン: Resend の HTTP API を使う（SMTP より高速・トラッキング可）
  config.action_mailer.delivery_method = :resend

  # 送信失敗時に例外を出す（Sentry で検知できる／「送ったつもり」事故を防ぐ）
  config.action_mailer.raise_delivery_errors = true

  # ------------------------------------------------------------
  # メール内URL・画像のホスト（#I-3: 環境変数化）
  # ------------------------------------------------------------
  # 【なぜ環境変数（APP_HOST）にするのか】
  #   パスワードリセット・週次レポート・タスクアラーム・CSV完了メールの
  #   リンクや画像URLは絶対URL（https://ホスト/...）で生成する必要がある。
  #   このホストをコードに直書きすると、将来 独自ドメイン（例: habitflow.jp）へ
  #   移行したときに production.rb を書き換える必要が出てしまう。
  #   APP_HOST という環境変数に逃がしておけば、移行時は Render の環境変数を
  #   変えるだけで済み、コードは一切修正不要になる。
  #
  # 【なぜ ENV.fetch に第2引数（既定値）を付けるのか】
  #   ENV.fetch("APP_HOST") のように既定値なしにすると、APP_HOST が未設定のとき
  #   KeyError で【アプリが起動できなくなる】。この設定は起動時に読まれるため、
  #   Render に APP_HOST を入れ忘れただけでデプロイが落ちてしまう。
  #   第2引数に現在の本番URL "habitflow-web.onrender.com" を既定値として持たせる
  #   ことで、未設定でも安全に現行URLで動き、必要なときだけ上書きできる。
  #
  # 【現在の本番URL】
  #   Render のサービス名が "habitflow-web" のため、既定の公開URLは
  #   https://habitflow-web.onrender.com。旧設定 "habitflow.onrender.com" は
  #   存在しない別ホストで、メール内リンクが全滅していたため実URLに一致させる。
  app_host = ENV.fetch("APP_HOST", "habitflow-web.onrender.com")

  # default_url_options:
  #   edit_password_reset_url などの URL ヘルパーがメール内で使われたとき、
  #   自動的に付与するドメインとプロトコル。protocol は本番なので常に https。
  config.action_mailer.default_url_options = {
    host:     app_host,
    protocol: "https"
  }

  # asset_host:
  #   メールHTML内の image_url / stylesheet_url を絶対URLにするためのホスト。
  #   メールクライアントは相対パスを解決できないため絶対URLが必須。
  #   default_url_options と同じ app_host を使い、食い違いによる画像リンク切れを防ぐ。
  config.action_mailer.asset_host = "https://#{app_host}"

  # メールのテンプレートはキャッシュしない（毎回最新内容で生成する）
  config.action_mailer.perform_caching = false
end
