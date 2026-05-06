# app/services/ai_client.rb
#
# ==============================================================================
# AiClient（AI API 抽象化クラス）faraday REST API 版
# ==============================================================================
#
# 【このファイルの役割】
#   Gemini REST API と Groq API への接続を faraday で一元管理する。
#   呼び出し元（PurposeAnalysisJob 等）は AiClient#analyze を呼ぶだけでよく、
#   どの API を使っているかを意識しなくてよい設計にする。
#
# 【D-11 での変更内容】
#   ① タイムアウト（Timeout::Error）を明示的に rescue して Sentry に Capture
#   ② 401エラーを専用クラス（AuthError）で検知して即座にエラーを発生させる
#   ③ 429エラーを専用クラス（RateLimitError）で検知して指数バックオフリトライ
#   ④ Sentry 通知ヘルパー（notify_sentry）を追加（Sentry gem がなくても動く）
#   ⑤ handle_http_error メソッドで HTTP エラー処理を共通化（DRY化）
#
# 【設計の絶対原則】
#   analyze メソッドは「常に nil か Hash を返す」。
#   例外を Job 側に伝播させない（AuthError のみ例外）。
#   Job 側は戻り値が nil かどうかだけで判定できる。
#
# 【戻り値の設計】
#   成功時: { text: "AIのレスポンステキスト", model: "使用モデル名" }
#   失敗時: nil
#
# ==============================================================================

class AiClient
  # ============================================================
  # カスタムエラークラス定義
  # ============================================================
  #
  # 【なぜカスタムエラークラスを定義するのか】
  #   「Gemini 401エラー」と「429レート制限」を
  #   呼び出し元（Job側・gemini_with_retry）で個別にハンドリングするためには
  #   エラーの種類を判別できるクラスが必要。
  #   StandardError の message 文字列で判定するのは脆弱なため、
  #   明示的なエラークラスで rescue する。

  # AuthError: APIキー不正・認証エラー（HTTP 401）
  # 【即座に failed にする理由】
  #   APIキーが間違っている場合、リトライしても必ず失敗する。
  #   GoodJobのリトライは無意味なので即座にfailed確定させ、
  #   Sentryで開発者に通知して早期解決を促す。
  AuthError = Class.new(StandardError)

  # RateLimitError: レート制限エラー（HTTP 429）
  # 【専用クラスを作る理由】
  #   gemini_with_retry の rescue で「429なのか」を
  #   rescue AiClient::RateLimitError と明示的に書けるため意図が明確になる。
  RateLimitError = Class.new(StandardError)

  # ============================================================
  # 定数定義
  # ============================================================

  # MAX_RETRIES: Gemini API で 429 エラーが発生したときの最大リトライ回数
  # 1回目: 1秒待機 → 2回目: 2秒待機 → 3回失敗で Groq にフォールバック
  MAX_RETRIES = 2

  # GEMINI_MODEL: 使用する Gemini のモデル名
  GEMINI_MODEL = "gemini-2.5-flash".freeze

  # GEMINI_API_BASE: Gemini REST API のベース URL
  GEMINI_API_BASE = "https://generativelanguage.googleapis.com".freeze

  # GROQ_MODEL: フォールバック時に使用する Groq のモデル名
  GROQ_MODEL = "llama-3.3-70b-versatile".freeze

  # GROQ_API_BASE: Groq API のベース URL
  GROQ_API_BASE = "https://api.groq.com".freeze

  # GEMINI_BLOCKED_CACHE_KEY: Rails.cache に記録する Gemini ブロックフラグのキー
  GEMINI_BLOCKED_CACHE_KEY = "ai_client:gemini_blocked".freeze

  # GEMINI_BLOCK_DURATION: Gemini がブロックされる期間（5分）
  GEMINI_BLOCK_DURATION = 5.minutes

  # API_TIMEOUT: HTTP リクエストのタイムアウト時間（秒）
  # D-11 要件: 30秒でタイムアウト設定
  API_TIMEOUT = 30

  # ============================================================
  # 初期化
  # ============================================================
  def initialize(provider: ENV.fetch("AI_PROVIDER", "gemini"))
    @provider = provider
  end

  # ============================================================
  # メインメソッド: analyze
  # ============================================================
  #
  # 【設計の核心】
  #   このメソッドは「必ず nil か Hash を返す」。
  #   例外を外部（Job側）に伝播させない。
  #   AuthError だけは例外として伝播させる（リトライ不要なため）。
  #
  # 【なぜ raise しないのか（コメント案の設計が危険な理由）】
  #   Job 側で rescue => e して raise すると
  #   GoodJob の ApplicationJob に定義された
  #   retry_on StandardError が反応してしまい、
  #   「60秒後に再エンキュー」という D-11 要件と
  #   「GoodJobの自動リトライ」が二重に動いてしまう。
  #   「nil を返す → Job 側で再エンキュー判定」という設計を守ることで
  #   リトライロジックが1箇所に集中して保守しやすくなる。
  def analyze(prompt)
    if @provider == "groq"
      call_groq(prompt)
    elsif gemini_available?
      gemini_with_retry(prompt)
    else
      Rails.logger.warn "[AiClient] Gemini はブロック中のため Groq にフォールバックします"
      call_groq(prompt)
    end

  rescue AuthError
    # AuthError だけは Job 側に伝播させる（discard_on で即失敗確定にするため）
    # Sentry への通知は call_gemini / call_groq 内の handle_http_error で行われる
    raise

  rescue Faraday::TimeoutError, Timeout::Error => e
    # タイムアウトは Sentry に記録して nil を返す
    # 【nil を返す理由】
    #   Job 側の再エンキューロジック（result.nil? の分岐）に乗せるため。
    #   raise すると ApplicationJob の retry_on StandardError が誤作動する。
    notify_sentry(e, level: :warning, extra: { timeout_seconds: API_TIMEOUT })
    Rails.logger.error "[AiClient] タイムアウト（#{API_TIMEOUT}秒）: #{e.class} → Sentry 通知済み"
    nil

  rescue => e
    # 予期しない例外のセーフティネット
    Rails.logger.error "[AiClient] 全プロバイダで失敗しました: #{e.class} - #{e.message}"
    nil
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # ----------------------------------------------------------
  # gemini_available?
  # ----------------------------------------------------------
  # Gemini が現在使用可能かどうかを判定する。
  # D-11 要件「① 事前フォールバック判定」の実装。
  def gemini_available?
    Rails.cache.read(GEMINI_BLOCKED_CACHE_KEY) != "true"
  end

  # ----------------------------------------------------------
  # gemini_with_retry(prompt, retries:)
  # ----------------------------------------------------------
  # Gemini API を呼び出し、429 エラーの場合は指数バックオフでリトライする。
  # D-11 要件「② 429 指数バックオフリトライ」の実装。
  #
  # 【AuthError は rescue しない理由】
  #   401 はリトライしても必ず失敗するため、
  #   rescue せずに analyze メソッドに伝播させる。
  def gemini_with_retry(prompt, retries: 0)
    call_gemini(prompt)
  rescue RateLimitError => e
    if retries < MAX_RETRIES
      wait_seconds = retries + 1  # 1回目: 1秒, 2回目: 2秒
      Rails.logger.warn "[AiClient] Gemini 429 レート制限: #{wait_seconds}秒後にリトライ (#{retries + 1}/#{MAX_RETRIES})"
      sleep(wait_seconds)
      gemini_with_retry(prompt, retries: retries + 1)
    else
      # リトライ上限超過 → 5分間ブロックフラグを立てて Groq へ
      Rails.logger.warn "[AiClient] Gemini 429 リトライ上限超過: 5分間ブロックして Groq にフォールバック"
      Rails.cache.write(GEMINI_BLOCKED_CACHE_KEY, "true", expires_in: GEMINI_BLOCK_DURATION)
      call_groq(prompt)
    end
  rescue AuthError
    # 401 は analyze に伝播させる
    raise
  rescue => e
    # 429 以外のエラー → Groq にフォールバック
    Rails.logger.warn "[AiClient] Gemini 失敗 (#{e.class}): Groq にフォールバックします"
    Rails.cache.write(GEMINI_BLOCKED_CACHE_KEY, "true", expires_in: GEMINI_BLOCK_DURATION)
    call_groq(prompt)
  end

  # ----------------------------------------------------------
  # call_gemini(prompt)
  # ----------------------------------------------------------
  # faraday を使って Gemini REST API を直接呼び出す。
  # D-11 変更: handle_http_error メソッドで HTTP エラー処理を共通化。
  def call_gemini(prompt)
    api_key = ENV["GEMINI_API_KEY"]
    raise ArgumentError, "GEMINI_API_KEY が設定されていません" if api_key.blank?

    conn     = build_faraday_connection(GEMINI_API_BASE)
    endpoint = "/v1beta/models/#{GEMINI_MODEL}:generateContent"

    response = conn.post(endpoint) do |req|
      req.params["key"]           = api_key
      req.headers["Content-Type"] = "application/json"
      req.body = {
        contents: [
          { parts: [{ text: prompt }] }
        ],
        generationConfig: {
          temperature:     0.7,
          maxOutputTokens: 4096
        }
      }
    end

    # HTTPステータスコードごとの専用エラー処理
    # handle_http_error は Gemini / Groq 共通のメソッド（DRY化）
    handle_http_error(response, "Gemini") unless response.success?

    text = response.body.dig("candidates", 0, "content", "parts", 0, "text")
    raise "Gemini API からレスポンステキストを取得できませんでした" if text.blank?

    Rails.logger.info "[AiClient] Gemini REST API 呼び出し成功（モデル: #{GEMINI_MODEL}）"
    { text: text, model: GEMINI_MODEL }
  end

  # ----------------------------------------------------------
  # call_groq(prompt)
  # ----------------------------------------------------------
  # Groq API（OpenAI 互換）を faraday で呼び出す。
  # D-11 変更: handle_http_error メソッドで HTTP エラー処理を共通化。
  def call_groq(prompt)
    api_key = ENV["GROQ_API_KEY"]

    if api_key.blank?
      Rails.logger.warn "[AiClient] GROQ_API_KEY が未設定のため Groq をスキップします"
      return nil
    end

    conn = build_faraday_connection(GROQ_API_BASE)

    response = conn.post("/openai/v1/chat/completions") do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"]  = "application/json"
      req.body = {
        model:    GROQ_MODEL,
        messages: [
          {
            role:    "system",
            content: "あなたは優秀なライフコーチです。必ず指定された JSON 形式のみで回答してください。"
          },
          {
            role:    "user",
            content: prompt
          }
        ],
        temperature: 0.7,
        max_tokens:  4096
      }
    end

    handle_http_error(response, "Groq") unless response.success?

    text = response.body.dig("choices", 0, "message", "content")
    raise "Groq API からレスポンステキストを取得できませんでした" if text.blank?

    Rails.logger.info "[AiClient] Groq API 呼び出し成功（モデル: #{GROQ_MODEL}）"
    { text: text, model: GROQ_MODEL }
  end

  # ----------------------------------------------------------
  # handle_http_error(response, provider_name)
  # ----------------------------------------------------------
  # 【役割】
  #   Gemini・Groq 共通の HTTP エラー処理メソッド。
  #   コメント案の「handle_response で共通化する」という提案の良い部分を
  #   安全な形で取り込んだもの。
  #
  # 【コメント案との違い】
  #   コメント案は成功レスポンスの処理も含めて共通化しようとしていたが、
  #   Gemini と Groq はレスポンス構造が異なるため共通化できない。
  #   エラー処理だけを共通化することで DRY 原則を守りつつ安全に実装する。
  #
  # 【なぜ raise するのか】
  #   このメソッドは call_gemini / call_groq から呼ばれる。
  #   raise した例外は gemini_with_retry → analyze の順に伝播し、
  #   それぞれの rescue で適切にハンドリングされる。
  #
  # 【引数】
  #   response      : Faraday::Response オブジェクト
  #   provider_name : ログに表示するプロバイダ名（"Gemini" or "Groq"）
  def handle_http_error(response, provider_name)
    status     = response.status
    error_body = if response.body.is_a?(Hash)
                   response.body.dig("error", "message").to_s
                 else
                   response.body.to_s[0, 200]  # 長すぎるボディを切り詰める
                 end

    Rails.logger.error "[AiClient] #{provider_name} HTTP #{status}: #{error_body}"

    case status
    when 401
      # 認証エラー: Sentry に fatal 通知してから AuthError を raise
      # AuthError は analyze まで伝播して Job 側で discard_on に捕捉される
      auth_error = AuthError.new("#{provider_name} 認証エラー（401）: #{error_body}")
      notify_sentry(auth_error, level: :fatal, extra: { provider: provider_name, status: 401 })
      raise auth_error
    when 429
      # レート制限: RateLimitError を raise して gemini_with_retry でリトライさせる
      raise RateLimitError, "#{provider_name} レート制限（429）: #{error_body}"
    else
      # その他（500系など）: 汎用エラーを raise → Groq にフォールバック
      raise "#{provider_name} API エラー: HTTP #{status} - #{error_body}"
    end
  end

  # ----------------------------------------------------------
  # build_faraday_connection(base_url)
  # ----------------------------------------------------------
  # 共通の faraday コネクションを生成する。
  # Gemini と Groq で同じタイムアウト設定を使うため共通化（DRY）。
  def build_faraday_connection(base_url)
    Faraday.new(url: base_url) do |f|
      # open_timeout: TCP接続確立の最大待機時間（秒）
      f.options.open_timeout = 10
      # timeout: レスポンス受信の最大待機時間（秒）= API_TIMEOUT（30秒）
      # D-11 要件: 30秒でタイムアウト
      f.options.timeout      = API_TIMEOUT
      # f.request :json → リクエストボディを自動的に JSON 文字列に変換する
      f.request  :json
      # f.response :json → レスポンスボディを自動的に Ruby Hash に変換する
      f.response :json
    end
  end

  # ----------------------------------------------------------
  # notify_sentry(exception, level:, extra: {})
  # ----------------------------------------------------------
  # Sentry に例外を通知するヘルパーメソッド。
  # Sentry gem がない環境でもエラーを起こさず動作する（ログだけ出す）。
  #
  # 【defined?(Sentry) で判定する理由】
  #   I-5（Sentry導入）タスク完了前でも安全に動作する。
  #   導入後は自動的に Sentry 通知が有効になる。
  def notify_sentry(exception, level: :error, extra: {})
    if defined?(Sentry)
      Sentry.capture_exception(
        exception,
        level: level,
        extra: extra.merge(
          ai_provider: @provider,
          timestamp:   Time.current.iso8601
        )
      )
      Rails.logger.info "[AiClient] Sentry 通知完了: level=#{level}, #{exception.class}"
    else
      Rails.logger.warn "[AiClient] Sentry 未導入のためログのみ: [#{level.upcase}] #{exception.class} - #{exception.message}"
    end
  end
end