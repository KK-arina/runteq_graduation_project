# frozen_string_literal: true

# config/initializers/rack_attack.rb
#
# ==============================================================================
# F-5 追加: rack-attack によるブルートフォース対策・レート制限
# ==============================================================================
#
# 【テスト環境で無効化する理由】
#   テストは同一プロセス内で順番に実行されるため、
#   あるテストの POST /login カウントが次のテストに持ち越され
#   無関係なテストが 429 を受け取ってしまう。
#   テスト環境では無効化し、rack_attack_test.rb 内でのみ明示的に有効化する。
#
# 【unless Rails.env.test? で囲む理由】
#   class/module 本体では return が使えない（SyntaxError になる）。
#   トップレベルで書く場合、Rack::Attack のメソッドはすべて
#   Rack::Attack.メソッド名 と明示的に呼び出す必要がある。
# ==============================================================================

unless Rails.env.test?
  # ============================================================================
  # キャッシュストアの設定
  # ============================================================================
  #
  # 【環境ごとに切り替える理由】
  #   開発環境で cache_store が :null_store の場合、カウントが保存されず
  #   レート制限が全く機能しなくなる。
  #   開発環境は MemoryStore を明示、本番は Rails.cache をそのまま使用する。
  if Rails.env.development?
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  else
    # 本番（Render）: Rails.cache（デフォルト FileStore）をそのまま使用。
    # 将来 Redis に切り替えても config/environments/production.rb を
    # 変えるだけで自動対応できる。
    Rack::Attack.cache.store = Rails.cache
  end

  # ============================================================================
  # ① safelist: 開発環境の localhost・Docker IP を除外
  # ============================================================================
  #
  # 【development? に限定する理由】
  #   本番環境でこの safelist が有効だとプロキシ経由で
  #   これらの IP が渡った場合に攻撃を全スルーする穴になる。
  #   開発環境のみに限定し、本番に余計な穴を空けない。
  #
  # 【"172.18.0.1" を含める理由】
  #   Docker Desktop（Linux/Windows/Mac）環境では、
  #   ブラウザからのリクエストが docker0 ブリッジネットワーク経由で届くため
  #   req.ip が "172.18.0.1" になる。
  #   これを safelist に含めないと開発中に自分がブロックされる。
  #
  # 【"0.0.0.0" を含める理由】
  #   Docker 環境ではコンテナ内部からのリクエストが
  #   "0.0.0.0" として渡るケースがある。
  if Rails.env.development?
    Rack::Attack.safelist("allow-localhost") do |req|
      ["127.0.0.1", "::1", "0.0.0.0", "172.18.0.1"].include?(req.ip)
    end
  end

  # ============================================================================
  # ② throttle: 同一 IP からのログイン試行回数制限（ブルートフォース対策）
  # ============================================================================
  #
  # 【throttle を選ぶ理由（Fail2Ban を使わない理由）】
  #   Fail2Ban は SessionsController の env に
  #   "rack.attack.login_failed" フラグをセットする必要があるが、
  #   Rack ミドルウェアと Rails コントローラーの env 伝達は
  #   Render 等のプロキシ環境で保証されないため throttle を採用。
  #   公式 README も Allow2Ban サンプルで POST /login リクエスト自体を
  #   カウントしており、失敗判定はしていない。
  Rack::Attack.throttle("login/ip", limit: 10, period: 300) do |req|
    req.ip if req.path == "/login" && req.post?
  end

  # ============================================================================
  # ③ throttle: メールアドレス単位のログイン試行制限（分散攻撃対策）
  # ============================================================================
  #
  # 【なぜ IP 制限だけでは不十分なのか】
  #   複数 IP（ボットネット）を使い分けると IP 単位の制限を回避できる。
  #   メールアドレス単位でも制限することで分散攻撃にも対応する。
  Rack::Attack.throttle("login/email", limit: 10, period: 1200) do |req|
    if req.path == "/login" && req.post?
      req.params.dig("session", "email").to_s.downcase.strip.presence
    end
  end

  # ============================================================================
  # ④ throttle: API 全体のレート制限（DoS・スクレイピング対策）
  # ============================================================================
  #
  # 【アセットを除外する理由】
  #   ブラウザは1ページで JS・CSS・画像等を並列大量リクエストするため
  #   アセットをカウントすると正常ユーザーがすぐ上限に達してしまう。
  Rack::Attack.throttle("req/ip", limit: 100, period: 60) do |req|
    unless req.path.start_with?("/assets/", "/packs/", "/rails/active_storage/") ||
           req.path == "/favicon.ico"
      req.ip
    end
  end

  # ============================================================================
  # ⑤ throttle: パスワードリセットメール送信の制限（メール爆弾対策）
  # ============================================================================
  #
  # 【なぜ必要か】
  #   攻撃者が他人のメールアドレスで何度もリセット要求すると
  #   大量のメールが届く（メール爆弾攻撃）。
  #   Resend の無料枠（月3,000通・1日100通）を不正消費される恐れもある。
  Rack::Attack.throttle("password_reset/ip", limit: 5, period: 900) do |req|
    req.ip if req.path == "/password_resets" && req.post?
  end

  # ============================================================================
  # ⑥ カスタムレスポンス: 429 エラー時の日本語 HTML 返却
  # ============================================================================
  #
  # 【なぜ Rack レスポンス形式で書くのか】
  #   rack-attack は Rails の外側（Rack 層）で動作するため
  #   Rails の render メソッドや共通レイアウトは使えない。
  #   Rack の規約（[ステータスコード, ヘッダーHash, ボディ配列]）で直接返す。
  Rack::Attack.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    period = match_data[:period]

    [
      429,
      {
        "Content-Type"  => "text/html; charset=utf-8",
        "Retry-After"   => period.to_s,
        "Cache-Control" => "no-cache, no-store"
      },
      [<<~HTML]
        <!DOCTYPE html>
        <html lang="ja">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>429 Too Many Requests | HabitFlow</title>
            <style>
              body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                background: #f3f4f6;
                margin: 0;
                padding: 0;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 100vh;
                text-align: center;
              }
              .card {
                background: white;
                max-width: 450px;
                padding: 2.5rem;
                border-radius: 1rem;
                box-shadow: 0 10px 25px -5px rgba(0,0,0,0.1);
                margin: 1rem;
              }
              .error-code {
                font-size: 5rem;
                font-weight: 800;
                color: #ef4444;
                margin: 0;
                line-height: 1;
              }
              .icon { font-size: 4rem; margin: 1rem 0; }
              h1 {
                font-size: 1.5rem;
                font-weight: 700;
                color: #1f2937;
                margin: 0 0 0.5rem;
              }
              p {
                color: #4b5563;
                font-size: 0.95rem;
                line-height: 1.6;
                margin: 0 0 1.5rem;
              }
              .hint {
                font-size: 0.85rem;
                color: #9ca3af;
                margin-bottom: 1.5rem;
              }
              a {
                display: inline-block;
                width: 100%;
                padding: 0.75rem;
                background: #2563eb;
                color: white;
                border-radius: 0.5rem;
                text-decoration: none;
                font-weight: 600;
                box-sizing: border-box;
              }
              a:hover { background: #1d4ed8; }
            </style>
          </head>
          <body>
            <div class="card">
              <p class="error-code">429</p>
              <div class="icon">🚦</div>
              <h1>アクセスが集中しています</h1>
              <p>
                短時間に多くのリクエストが送信されたため、<br>
                一時的にアクセスを制限しています。
              </p>
              <p class="hint">約 #{period} 秒ほど待ってから再度お試しください。</p>
              <a href="/">トップページへ戻る</a>
            </div>
          </body>
        </html>
      HTML
    ]
  end

  # ============================================================================
  # ⑦ ログ出力: 制限発動時の記録
  # ============================================================================
  #
  # 【なぜログを残すのか】
  #   Render の本番ログから攻撃状況を把握するため。
  #   攻撃が継続する場合は IP を blocklist に追加する判断材料になる。
  ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _request_id, payload|
    req = payload[:request]
    if req.env["rack.attack.match_type"] == :throttle
      Rails.logger.warn(
        "[Rack::Attack] Throttled | IP: #{req.ip} | Path: #{req.path} | " \
        "Rule: #{req.env['rack.attack.matched']}"
      )
    end
  end
end