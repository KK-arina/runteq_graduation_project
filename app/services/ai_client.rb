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
# 【なぜ gem なしで REST API を直接呼ぶのか】
#   Google 公式の Gemini Ruby SDK が存在しないため、
#   サードパーティ gem に頼らず faraday で REST API を直接呼ぶ。
#   公式ドキュメント通りの JSON 構造をそのまま使えるため安定している。
#
# 【Gemini REST API のエンドポイント】
#   POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}
#   リクエスト/レスポンスの JSON 構造は以下の公式ドキュメントに従う:
#   https://ai.google.dev/api/generate-content
#
# 【戻り値の設計】
#   成功時: { text: "AIのレスポンステキスト", model: "使用モデル名" }
#   失敗時: nil
#
# ==============================================================================

class AiClient
  # ============================================================
  # 定数定義
  # ============================================================

  # MAX_RETRIES: Gemini API で 429 エラーが発生したときの最大リトライ回数
  # 【なぜ 2 回か】
  #   1回目: 1秒待機 → 2回目: 2秒待機 → 3回失敗で Groq にフォールバック
  #   これ以上増やすとジョブの実行時間が長くなりすぎる
  MAX_RETRIES = 2

  # GEMINI_MODEL: 使用する Gemini のモデル名
  # 【gemini-2.0-flash を選んだ理由】
  #   - 無料枠が広い（1分15リクエスト・1日1500リクエスト）
  #   - 応答速度が速い（flash = 高速モデル）
  #   - PMVV 分析程度のタスクには十分な精度がある
  GEMINI_MODEL = "gemini-2.5-flash".freeze  # 2.0-flash → 2.5-flash に変更

  # GEMINI_API_BASE: Gemini REST API のベース URL
  # v1beta: 最新機能が含まれる安定版（v1 より機能が多い）
  GEMINI_API_BASE = "https://generativelanguage.googleapis.com".freeze

  # GROQ_MODEL: フォールバック時に使用する Groq のモデル名
  # 【llama-3.3-70b-versatile を選んだ理由】
  #   - Groq の無料枠で利用可能
  #   - 70B パラメータで高品質な日本語対応
  #   - OpenAI 互換 API なので faraday + JSON で簡単に呼び出せる
  GROQ_MODEL = "llama-3.3-70b-versatile".freeze

  # GROQ_API_BASE: Groq API のベース URL
  GROQ_API_BASE = "https://api.groq.com".freeze

  # GEMINI_BLOCKED_CACHE_KEY: Rails.cache に記録する Gemini ブロックフラグのキー
  # 【なぜ定数にするか】
  #   文字列を直接書くとタイポのリスクがある。定数にすることで安全に参照できる。
  GEMINI_BLOCKED_CACHE_KEY = "ai_client:gemini_blocked".freeze

  # GEMINI_BLOCK_DURATION: Gemini がブロックされる期間
  # 429 エラー連発後、5分間は Gemini を使わず Groq を使う
  GEMINI_BLOCK_DURATION = 5.minutes

  # API_TIMEOUT: HTTP リクエストのタイムアウト時間（秒）
  # 【なぜ 30 秒か】
  #   Gemini の応答は通常 5〜15 秒。30 秒で十分な余裕がある。
  #   これ以上待つとジョブが詰まってサーバーリソースを圧迫する。
  API_TIMEOUT = 30

  # ============================================================
  # 初期化
  # ============================================================

  # initialize(provider:)
  # 【引数】
  #   provider: 使用する AI プロバイダ。
  #             ENV["AI_PROVIDER"] が設定されていればその値を使う。
  #             未設定なら "gemini" をデフォルトとして使う。
  def initialize(provider: ENV.fetch("AI_PROVIDER", "gemini"))
    @provider = provider
  end

  # ============================================================
  # メインメソッド: analyze
  # ============================================================

  # analyze(prompt)
  # 【役割】
  #   プロンプト文字列を受け取り、AI に送信して結果を返す。
  #   Gemini → Groq の順でフォールバックを試み、
  #   全プロバイダが失敗した場合は nil を返す。
  #
  # 【戻り値】
  #   成功時: { text: "AIのレスポンステキスト", model: "使用モデル名" }
  #   失敗時: nil
  def analyze(prompt)
    if @provider == "groq"
      # 環境変数で Groq 強制指定された場合
      call_groq(prompt)
    else
      if gemini_available?
        gemini_with_retry(prompt)
      else
        Rails.logger.warn "[AiClient] Gemini はブロック中のため Groq にフォールバックします"
        call_groq(prompt)
      end
    end
  rescue => e
    # 予期しない例外が発生した場合のセーフティネット
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
  # 【役割】
  #   Gemini が現在使用可能かどうかを判定する。
  #   Rails.cache に gemini_blocked フラグが存在する場合は false を返す。
  def gemini_available?
    Rails.cache.read(GEMINI_BLOCKED_CACHE_KEY) != "true"
  end

  # ----------------------------------------------------------
  # gemini_with_retry(prompt, retries:)
  # ----------------------------------------------------------
  # 【役割】
  #   Gemini API を呼び出し、429 エラー（レート制限）の場合は
  #   指数バックオフでリトライする。
  #   最大リトライ回数を超えた場合は Groq にフォールバックする。
  def gemini_with_retry(prompt, retries: 0)
    call_gemini(prompt)
  rescue => e
    if e.message.to_s.include?("429") && retries < MAX_RETRIES
      wait_seconds = retries + 1
      Rails.logger.warn "[AiClient] Gemini 429 レート制限: #{wait_seconds}秒後にリトライ (#{retries + 1}/#{MAX_RETRIES})"
      sleep(wait_seconds)
      gemini_with_retry(prompt, retries: retries + 1)
    else
      Rails.logger.warn "[AiClient] Gemini 失敗 (#{e.class}: #{e.message}): Groq にフォールバックします"
      Rails.cache.write(GEMINI_BLOCKED_CACHE_KEY, "true", expires_in: GEMINI_BLOCK_DURATION)
      call_groq(prompt)
    end
  end

  # ----------------------------------------------------------
  # call_gemini(prompt)
  # ----------------------------------------------------------
  # 【役割】
  #   faraday を使って Gemini REST API を直接呼び出す。
  #   Google 公式の Ruby SDK が存在しないため、REST API を直接叩く。
  #
  # 【Gemini REST API のリクエスト構造】
  #   POST /v1beta/models/{model}:generateContent?key={api_key}
  #   {
  #     "contents": [{ "parts": [{ "text": "プロンプト" }] }],
  #     "generationConfig": { "temperature": 0.7, "maxOutputTokens": 4096 }
  #   }
  #
  # 【Gemini REST API のレスポンス構造】
  #   {
  #     "candidates": [{
  #       "content": {
  #         "parts": [{ "text": "AIの応答テキスト" }]
  #       }
  #     }]
  #   }
  #
  # 【GEMINI_API_KEY の取得方法】
  #   https://aistudio.google.com/ でアカウント作成後に無料発行できる。
  #   クレカ不要・上限超過時は課金なし（リクエスト拒否のみ）。
  def call_gemini(prompt)
    api_key = ENV["GEMINI_API_KEY"]
    raise ArgumentError, "GEMINI_API_KEY が設定されていません" if api_key.blank?

    # faraday クライアントを作成する
    # GEMINI_API_BASE をベース URL として設定する
    conn = build_faraday_connection(GEMINI_API_BASE)

    # Gemini REST API エンドポイント
    # /v1beta/models/{モデル名}:generateContent?key={APIキー}
    endpoint = "/v1beta/models/#{GEMINI_MODEL}:generateContent"

    response = conn.post(endpoint) do |req|
      # クエリパラメータに API キーを設定する
      # Gemini API は Authorization ヘッダーではなく ?key= クエリパラメータで認証する
      req.params["key"] = api_key
      req.headers["Content-Type"] = "application/json"

      # リクエストボディ（Gemini REST API の公式フォーマット）
      req.body = {
        # contents: メッセージの配列
        # parts: テキストの配列（今回は1つのプロンプトのみ）
        contents: [
          {
            parts: [
              { text: prompt }
            ]
          }
        ],
        # generationConfig: レスポンスの生成設定
        # temperature: 0.7 → やや創造的な回答（0=決定的、1=最もランダム）
        # maxOutputTokens: 4096 → 最大トークン数（長い JSON 応答に対応）
        generationConfig: {
          temperature:     0.7,
          maxOutputTokens: 4096
        }
      }
    end

    # HTTP ステータスコードが 200 以外の場合はエラーを発生させる
    # 429 の場合は gemini_with_retry がキャッチしてリトライする
    unless response.success?
      error_body = response.body.is_a?(Hash) ? response.body.dig("error", "message") : response.body.to_s
      raise "Gemini API エラー: HTTP #{response.status} - #{error_body}"
    end

    # レスポンスからテキストを抽出する
    # candidates[0].content.parts[0].text の構造になっている
    # dig を使って安全にネストした値を取得する（nil セーフ）
    text = response.body.dig("candidates", 0, "content", "parts", 0, "text")
    raise "Gemini API からレスポンステキストを取得できませんでした" if text.blank?

    Rails.logger.info "[AiClient] Gemini REST API 呼び出し成功（モデル: #{GEMINI_MODEL}）"

    # 使用したモデル名と一緒に返す
    # Job 側で正確なモデル名を DB に記録できる
    { text: text, model: GEMINI_MODEL }
  end

  # ----------------------------------------------------------
  # call_groq(prompt)
  # ----------------------------------------------------------
  # 【役割】
  #   Groq API（OpenAI 互換エンドポイント）を faraday で呼び出す。
  #   Gemini が失敗した場合のフォールバックとして使用する。
  #
  # 【Groq API の特徴】
  #   - OpenAI と同じ API インターフェース（/v1/chat/completions）
  #   - 無料枠: 1分30リクエスト・1日14,400リクエスト
  #   - API キー: https://console.groq.com で無料取得
  def call_groq(prompt)
    api_key = ENV["GROQ_API_KEY"]

    if api_key.blank?
      Rails.logger.warn "[AiClient] GROQ_API_KEY が設定されていません。Groq フォールバックをスキップします"
      return nil
    end

    conn = build_faraday_connection(GROQ_API_BASE)

    response = conn.post("/openai/v1/chat/completions") do |req|
      # Groq API は Bearer 認証形式で API キーを渡す
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"]  = "application/json"

      req.body = {
        model:    GROQ_MODEL,
        messages: [
          # system: AI の役割・振る舞いを定義するシステムメッセージ
          {
            role:    "system",
            content: "あなたは優秀なライフコーチです。ユーザーの目標分析を行い、必ず指定された JSON 形式のみで回答してください。"
          },
          # user: ユーザーからのメッセージ（分析プロンプト）
          {
            role:    "user",
            content: prompt
          }
        ],
        temperature: 0.7,
        max_tokens:  4096
      }
    end

    unless response.success?
      raise "Groq API エラー: HTTP #{response.status} - #{response.body}"
    end

    # Groq（OpenAI 互換）のレスポンス構造:
    #   choices[0].message.content
    text = response.body.dig("choices", 0, "message", "content")
    raise "Groq API からレスポンステキストを取得できませんでした" if text.blank?

    Rails.logger.info "[AiClient] Groq API 呼び出し成功（モデル: #{GROQ_MODEL}）"
    { text: text, model: GROQ_MODEL }
  end

  # ----------------------------------------------------------
  # build_faraday_connection(base_url)
  # ----------------------------------------------------------
  # 【役割】
  #   共通の faraday コネクションを生成する。
  #   Gemini と Groq で同じ設定（タイムアウト・JSON 変換）を使うため
  #   メソッドに切り出して DRY にする。
  #
  # 【各設定の意味】
  #   open_timeout: 接続確立の最大待機時間（秒）
  #   timeout:      レスポンス受信の最大待機時間（秒）
  #   f.request :json  → リクエストボディを自動的に JSON 文字列に変換する
  #   f.response :json → レスポンスボディを自動的に Ruby Hash に変換する
  def build_faraday_connection(base_url)
    Faraday.new(url: base_url) do |f|
      f.options.open_timeout = 10
      f.options.timeout      = API_TIMEOUT
      f.request  :json
      f.response :json
    end
  end
end