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
  # 【なぜ :external にするのか】
  # 本番環境（Render）では Web サービスと Worker サービスを分離して運用する。
  # :external モードにより、Web プロセスはジョブをキューに積むだけになり、
  # Render の Worker サービス（bundle exec good_job start）が実行を担当する。
  # これにより Web サーバーの応答速度を確保しつつ、バックグラウンド処理ができる。
  config.good_job.execution_mode = :external
end
