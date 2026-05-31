# app/services/line_notification_service.rb
#
# ==============================================================================
# LineNotificationService - LINE Messaging API 通知送信サービス（G-1 新規作成）
# ==============================================================================
#
# 【このクラスの役割】
#   LINE Messaging API の Push Message エンドポイントを呼び出して
#   ユーザーにプッシュ通知を送信する。
#   Net::HTTP（Ruby 標準ライブラリ）を使うため、外部 gem は不要。
#
# 【依存関係】
#   - users.line_user_id（LINE の userId）が存在するユーザーのみ送信可能
#   - 環境変数 LINE_CHANNEL_ACCESS_TOKEN が設定されていること
#
# 【LINE Messaging API の仕様（2025年時点）】
#   エンドポイント: POST https://api.line.me/v2/bot/message/push
#   認証ヘッダー:   Authorization: Bearer {channel_access_token}
#   リクエスト形式: JSON
#   無料枠:         Communication プラン で月 200 通まで
#   超過時:         送信エラー（課金なし）→ メール通知に自動切替
#
# 【設計原則】
#   A-7 トランザクション原則に従い、このクラスは外部 API 呼び出しのみを担当する。
#   notification_logs への記録・daily_notification_count の更新は呼び出し元で行う。
#
# 【使い方】
#   result = LineNotificationService.new(
#     line_user_id: user.line_user_id,
#     message:      "メッセージ本文"
#   ).call
#
#   result[:success] # => true / false
#   result[:error]   # => エラーメッセージ（失敗時のみ）
#   result[:response_body] # => LINE API のレスポンス JSON（成功時）
# ==============================================================================
class LineNotificationService
  # ============================================================
  # 定数定義
  # ============================================================

  # LINE_API_ENDPOINT: LINE Messaging API の Push Message エンドポイント
  #
  # 【なぜ定数にするのか】
  #   URL を文字列リテラルで直書きすると、将来 API バージョンが変わったとき
  #   複数箇所を直す必要がある（DRY 原則違反）。
  #   定数にすれば変更箇所が1ヶ所で済む。
  #
  # 【⚠️ 重要：LINE Push Message 送信の前提条件】
  #
  #   LINE Messaging API の Push Message は、
  #   「ユーザーが Messaging API チャネル（Bot）を友達追加している」場合のみ送信可能。
  #   LINE Login だけでは Push Message を送れない。
  #
  #   未追加ユーザーへの送信時:
  #     HTTP 400 { "message": "Invalid userId" }
  #
  #   【対策】
  #     LINE ログイン完了後の画面（terms_agreement や onboarding）に
  #     「LINE通知を受け取るには Bot を友達追加してください」という案内と
  #     友達追加リンクを表示する。
  #     友達追加 URL 形式: https://line.me/R/ti/p/@{チャネルID}
  #
  #   【コードでの扱い】
  #     友達未追加 = HTTP 400 エラー = 通知失敗として処理し、メールにフォールバックする。
  #     line_user_id は保存済みのままにしておくことで、
  #     後から友達追加されたとき自動的に LINE 通知が有効になる。
  LINE_API_ENDPOINT = "https://api.line.me/v2/bot/message/push".freeze

  # TIMEOUT_SECONDS: HTTP リクエストのタイムアウト秒数
  #
  # 【なぜ 10 秒か】
  #   LINE API の平均レスポンスタイムは 1〜3 秒。
  #   GoodJob のジョブ内から呼ばれるため、長すぎると他のジョブをブロックする。
  #   10 秒は「十分な余裕」と「リソース節約」のバランス点。
  TIMEOUT_SECONDS = 10

  # ============================================================
  # 初期化
  # ============================================================
  #
  # 【引数】
  #   line_user_id: 送信先ユーザーの LINE userId（例: "U4af4980629..."）
  #   message:      送信するテキストメッセージ本文
  #
  # 【freeze の理由】
  #   String に freeze を付けると文字列が不変オブジェクトになり、
  #   Ruby 2.3 以降のメモリ最適化が有効になる。
  #   この値はインスタンス内で書き換えることがないため適切。
  def initialize(line_user_id:, message:)
    @line_user_id = line_user_id.freeze
    @message      = message.freeze
  end

  # ============================================================
  # call: LINE にメッセージを送信する
  # ============================================================
  #
  # 【戻り値の設計（Result オブジェクト風ハッシュ）】
  #   呼び出し元が成功/失敗を判定しやすいよう、常にハッシュを返す。
  #   例外を raise しない設計にすることで、呼び出し元の rescue が不要になる。
  #   ただし、呼び出し元（NotificationService）が例外を再 raise するため、
  #   send! メソッドに処理を委譲して例外はそこで発生させる。
  #
  # 【戻り値の例】
  #   成功: { success: true,  response_body: { "sentMessages" => [...] } }
  #   失敗: { success: false, error: "HTTP 400: Bad Request - ..." }
  def call
    # LINE_CHANNEL_ACCESS_TOKEN が設定されていなければ送信不可
    # ENV.fetch は環境変数が存在しない場合に KeyError を raise する。
    # nil チェックよりも明確なエラーメッセージが得られる。
    token = ENV.fetch("LINE_CHANNEL_ACCESS_TOKEN", nil)

    if token.blank?
      Rails.logger.error "[LineNotificationService] LINE_CHANNEL_ACCESS_TOKEN が設定されていません"
      return { success: false, error: "LINE_CHANNEL_ACCESS_TOKEN が未設定です" }
    end

    send_push_message(token)

  rescue => e
    # 予期しない例外（ネットワークエラー等）をキャッチしてログに記録する
    # rescue => e: StandardError 以上の例外をすべて捕まえる省略形
    Rails.logger.error "[LineNotificationService] 予期しないエラー: #{e.class} #{e.message}"
    { success: false, error: "#{e.class}: #{e.message}" }
  end

  private

  # attr_reader で @line_user_id / @message に外部からアクセスできないようにする
  #
  # 【private の下に attr_reader を書く理由】
  #   private キーワード以降に定義したメソッドは自動的に private になる。
  #   これにより line_user_id / message を外部から呼び出せなくなり、
  #   カプセル化（オブジェクトの内部状態を外部から隠す設計）が実現できる。
  attr_reader :line_user_id, :message

  # ============================================================
  # send_push_message: LINE API への HTTP リクエストを送信する
  # ============================================================
  #
  # 【Net::HTTP を使う理由（gem を使わない理由）】
  #   LINE 公式の Ruby SDK は存在しない（2025年時点）。
  #   サードパーティ gem は廃止・破壊的変更リスクがある。
  #   Net::HTTP は Ruby 標準ライブラリのため:
  #     - 追加の gem インストール不要
  #     - Ruby バージョンアップでも確実に使える
  #     - LINE API の仕様通りの実装ができる
  def send_push_message(token)
    # URI.parse: URL 文字列を URI オブジェクトに変換する
    # URI オブジェクトはホスト名・パス・ポート等を個別に取得できる
    uri = URI.parse(LINE_API_ENDPOINT)

    # Net::HTTP::Post.new: POST リクエストオブジェクトを作成する
    # uri.request_uri: パス部分のみを取得（例: "/v2/bot/message/push"）
    request = Net::HTTP::Post.new(uri.request_uri)

    # リクエストヘッダーを設定する
    #
    # Content-Type: application/json
    #   リクエストボディが JSON 形式であることを LINE サーバーに伝える
    #   これがないと LINE サーバーがボディを正しく解析できない
    #
    # Authorization: Bearer {token}
    #   チャネルアクセストークンで認証する。LINE API の標準認証方式。
    #   "Bearer " + token の形式であることに注意（スペースが必要）
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{token}"

    # リクエストボディを JSON 形式で設定する
    #
    # LINE Push Message のリクエスト形式:
    #   {
    #     "to": "U{userId}",          ← 送信先の LINE userId
    #     "messages": [               ← 送信するメッセージの配列（最大5件）
    #       {
    #         "type": "text",         ← テキストメッセージ
    #         "text": "メッセージ本文" ← 本文（最大5000文字）
    #       }
    #     ]
    #   }
    #
    # .to_json: Ruby のハッシュを JSON 文字列に変換する
    # Rails の ActiveSupport が to_json を提供している
    request.body = {
      to:       line_user_id,
      messages: [
        {
          type: "text",
          text: message
        }
      ]
    }.to_json

    # Net::HTTP.start: HTTPS 接続を開始する
    #
    # uri.host:   接続先ホスト（"api.line.me"）
    # uri.port:   接続先ポート（443 = HTTPS の標準ポート）
    # use_ssl:    HTTPS を使う（true にすることで SSL/TLS 暗号化が有効になる）
    # read_timeout / open_timeout:
    #   タイムアウト秒数。LINE API が応答しない場合に無限待機を防ぐ。
    #   read_timeout:  レスポンスを待つ最大秒数
    #   open_timeout:  TCP 接続確立の最大秒数
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl:      true,
      read_timeout: TIMEOUT_SECONDS,
      open_timeout: TIMEOUT_SECONDS
    ) do |http|
      # http.request(request): 実際に HTTP リクエストを送信する
      # ブロックの中で実行することで接続が自動的にクローズされる（リソースリーク防止）
      http.request(request)
    end

    # レスポンスを処理する
    handle_response(response)
  end

  # ============================================================
  # handle_response: LINE API のレスポンスを処理する
  # ============================================================
  #
  # 【LINE API のレスポンスコード】
  #   200: 成功
  #   400: リクエストが不正（JSON 形式エラー、必須フィールド不足など）
  #   401: 認証失敗（channel_access_token が無効）
  #   403: 権限なし（ユーザーがブロックしているなど）
  #   429: レート制限超過
  #   500: LINE サーバーエラー
  def handle_response(response)
    # response.code: HTTP ステータスコードを文字列で返す（例: "200"）
    # .to_i で整数に変換して比較する
    http_status = response.code.to_i

    if http_status == 200
      # 成功: レスポンスボディを JSON としてパースして返す
      #
      # JSON.parse: JSON 文字列を Ruby のハッシュに変換する
      # rescue JSON::ParserError: 万が一レスポンスが JSON でない場合のフォールバック
      response_body = begin
                        JSON.parse(response.body)
                      rescue JSON::ParserError
                        # JSON パースに失敗してもエラーにしない（成功は成功）
                        {}
                      end

      Rails.logger.info "[LineNotificationService] LINE送信成功: line_user_id=#{line_user_id}"
      { success: true, response_body: response_body }

    else
      # 失敗: エラーメッセージを組み立ててログに記録する
      #
      # response.body: エラーの詳細（JSON）が含まれることが多い
      # 例: {"message":"The user ID is invalid.","details":[]}
      error_message = "HTTP #{http_status}: #{response.message} - #{response.body}"

      Rails.logger.error "[LineNotificationService] LINE送信失敗: #{error_message}, line_user_id=#{line_user_id}"
      { success: false, error: error_message }
    end
  end
end