# test/services/line_notification_service_test.rb
#
# ==============================================================================
# LineNotificationService のテスト（G-1 新規作成）
# ==============================================================================
#
# 【テスト方針】
#   LINE API への実際の HTTP リクエストは発生させない（外部依存をなくす）。
#   Net::HTTP をスタブ化して、サービスの内部ロジックだけをテストする。
#
# 【主な修正点（レビュー対応）】
#   1. require "ostruct" を追加（Ruby環境によっては自動ロードされないため必須）
#   2. stub_http_response をブロック形式に修正（yield への block 渡し漏れを修正）
#   3. ネットワークエラーテストのスタブ方式を修正
# ==============================================================================
require "test_helper"
require "ostruct"
# 【require "ostruct" が必要な理由】
#   OpenStruct は Ruby の標準ライブラリだが、Ruby 3.x 以降は明示的に
#   require しないと NameError: uninitialized constant OpenStruct が発生する。
#   test_helper.rb で自動 require される保証がないため、ここで明示する。

class LineNotificationServiceTest < ActiveSupport::TestCase
  DUMMY_USER_ID = "U1234567890abcdef1234567890abcdef".freeze
  DUMMY_TOKEN   = "test_channel_access_token".freeze
  DUMMY_MESSAGE = "テストメッセージ".freeze

  setup do
    @original_token = ENV["LINE_CHANNEL_ACCESS_TOKEN"]
    ENV["LINE_CHANNEL_ACCESS_TOKEN"] = DUMMY_TOKEN
  end

  teardown do
    ENV["LINE_CHANNEL_ACCESS_TOKEN"] = @original_token
  end

  # ============================================================
  # テスト1: LINE_CHANNEL_ACCESS_TOKEN が未設定の場合
  # ============================================================
  test "LINE_CHANNEL_ACCESS_TOKEN が未設定のとき失敗を返す" do
    ENV["LINE_CHANNEL_ACCESS_TOKEN"] = nil

    result = LineNotificationService.new(
      line_user_id: DUMMY_USER_ID,
      message:      DUMMY_MESSAGE
    ).call

    assert_equal false, result[:success]
    assert_includes result[:error], "未設定"
  end

  # ============================================================
  # テスト2: LINE API が 200 を返した場合（成功）
  # ============================================================
  test "LINE API が 200 を返したとき成功を返す" do
    # stub_http_response をブロック形式で呼ぶ
    # 【修正ポイント】
    #   stub_http_response は yield でブロックを受け取る実装になっているため、
    #   呼び出し側も do...end ブロックを渡す必要がある。
    #   ブロックなしで呼ぶと LocalJumpError: no block given (yield) になる。
    stub_http_response(
      code: "200",
      body: '{"sentMessages":[{"id":"123","quoteToken":"abc"}]}'
    ) do
      result = LineNotificationService.new(
        line_user_id: DUMMY_USER_ID,
        message:      DUMMY_MESSAGE
      ).call

      assert_equal true, result[:success]
      assert_not_nil result[:response_body]
      assert_equal "123", result[:response_body]["sentMessages"][0]["id"]
    end
  end

  # ============================================================
  # テスト3: LINE API が 400 を返した場合（不正リクエスト）
  # ============================================================
  test "LINE API が 400 を返したとき失敗を返す" do
    stub_http_response(
      code: "400",
      body: '{"message":"The user ID is invalid.","details":[]}'
    ) do
      result = LineNotificationService.new(
        line_user_id: "invalid_user_id",
        message:      DUMMY_MESSAGE
      ).call

      assert_equal false, result[:success]
      assert_includes result[:error], "400"
      # LINE API のエラー本文がエラーメッセージに含まれることを確認
      assert_includes result[:error], "The user ID is invalid"
    end
  end

  # ============================================================
  # テスト4: LINE API が 401 を返した場合（認証失敗）
  # ============================================================
  test "LINE API が 401 を返したとき失敗を返す" do
    stub_http_response(
      code: "401",
      body: '{"message":"The access token is invalid","details":[]}'
    ) do
      result = LineNotificationService.new(
        line_user_id: DUMMY_USER_ID,
        message:      DUMMY_MESSAGE
      ).call

      assert_equal false, result[:success]
      assert_includes result[:error], "401"
    end
  end

  # ============================================================
  # テスト5: ネットワークエラーが発生した場合
  # ============================================================
  test "ネットワークエラーが発生したとき失敗を返す" do
    # 【スタブ方式の修正ポイント】
    #   LineNotificationService 内で Net::HTTP.start はブロック付きで呼ばれる:
    #     Net::HTTP.start(...) do |http|
    #       http.request(request)
    #     end
    #   そのため、スタブも「ブロックを受け取れる形式」にする必要がある。
    #   ここでは例外を raise する lambda を渡すことで、
    #   ブロックの実行前に例外を発生させる。
    Net::HTTP.stub(
      :start,
      ->(*_args, **_kwargs, &_block) { raise Net::OpenTimeout, "接続タイムアウト" }
    ) do
      result = LineNotificationService.new(
        line_user_id: DUMMY_USER_ID,
        message:      DUMMY_MESSAGE
      ).call

      assert_equal false, result[:success]
      assert_includes result[:error], "Net::OpenTimeout"
    end
  end

  private

  # stub_http_response: Net::HTTP レスポンスをスタブ化するヘルパー
  #
  # 【ブロック形式にする理由】
  #   Net::HTTP.start はブロックを受け取る設計になっている:
  #     Net::HTTP.start(...) do |http|
  #       http.request(request)  ← このブロック内でリクエストを送る
  #     end
  #   スタブも同様に「ブロックを受け取って mock_http を yield する」形式にしないと
  #   実際のコードフローと一致せず、テストが正しく動作しない。
  #
  # 【引数】
  #   code: HTTP ステータスコード文字列（"200", "400" など）
  #   body: レスポンスボディ文字列（JSON文字列）
  #
  # 【呼び出し方（必ずブロックを渡すこと）】
  #   stub_http_response(code: "200", body: '...') do
  #     # ここで service.call を実行する
  #   end
  def stub_http_response(code:, body:)
    # ダミーのレスポンスオブジェクトを作成する
    # OpenStruct は任意のメソッドを持つオブジェクトを動的に作る Ruby の仕組み
    mock_response = OpenStruct.new(
      code:    code,
      message: code == "200" ? "OK" : "Error",
      body:    body
    )

    # ダミーの http セッションオブジェクト
    # 【修正ポイント】
    #   OpenStruct に lambda を渡しても .call が必要になり
    #   http.request(req) の形式で呼べない。
    #   Struct を使って request メソッドを正しく定義する。
    mock_http = Struct.new(:mock_response) do
      def request(_req)
        mock_response
      end
    end.new(mock_response)

    # Net::HTTP.start をスタブ化する
    Net::HTTP.stub(
      :start,
      ->(*_args, **_kwargs, &block) { block.call(mock_http) }
    ) do
      yield
    end
  end
end