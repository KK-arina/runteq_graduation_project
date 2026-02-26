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
  # ログ設定
  # ============================================================

  # log_level: :info
  #   本番環境では :debug より軽い :info レベルにする。
  #   :debug にするとすべての SQL クエリが記録されてログが膨大になる。
  #   :info は「アクセスログ＋エラー＋重要なイベント」だけを記録する。
  config.log_level = :info

  # logger: ActiveSupport::TaggedLogging
  #   Render などの PaaS は標準出力（STDOUT）のログを収集する仕組みになっている。
  #   STDOUT に出力しないとログが Render のダッシュボードに表示されない。
  #   TaggedLogging: ログに request_id などのタグを追加できるようにする。
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # log_tags: [ :request_id ]
  #   各ログ行の先頭に「リクエストID」を付与する。
  #   同じリクエストに関するログをまとめて追跡できるようになる。
  #   例: [abc123] Started GET "/dashboard"
  config.log_tags = [ :request_id ]

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
end