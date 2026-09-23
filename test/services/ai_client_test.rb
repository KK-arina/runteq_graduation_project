# frozen_string_literal: true

require "test_helper"

# ==============================================================================
# AiClient の単体テスト
#   AI クライアントのフォールバック構造とエラーハンドリングを検証する。
# ==============================================================================
class AiClientTest < ActiveSupport::TestCase
  setup do
    # provider を明示せず生成（デフォルト = ENV["AI_PROVIDER"] または "gemini"）。
    @ai_client = AiClient.new
  end

  # ----------------------------------------------------------------------------
  # 【テストの目的】
  #   Gemini も Groq も失敗した「全プロバイダ失敗」の最悪ケースで、
  #   最終セーフティネットが notify_sentry を1回呼ぶことを保証する。
  #   将来 AiClient を修正しても「Sentry 通知の書き忘れ（先祖返り）」を自動検知できる。
  #
  # 【なぜ gemini_available? を false に stub するのか】
  #   実物の analyze は、gemini_available? が true だと gemini_with_retry を、
  #   false だと call_groq（フォールバック）を呼ぶ。ここでは経路を単純化するため
  #   gemini_available? を false に固定し、call_groq だけを失敗させて
  #   最終 rescue に確実に到達させる。
  # ----------------------------------------------------------------------------
  test "全プロバイダ失敗時に notify_sentry が1回呼ばれ、nil が返ること" do
    notifications = []

    # ① Gemini を使えない状態にして、必ず Groq フォールバックへ進ませる。
    @ai_client.stub(:gemini_available?, false) do
      # ② Groq も失敗させる（モデル廃止 404 を模したエラー）。
      @ai_client.stub(:call_groq, ->(_prompt) { raise StandardError, "Groq 404 Model Not Found" }) do
        # ③ notify_sentry を差し替え、「呼ばれた事実」と引数だけ記録する。
        #    実際に Sentry へネットワーク送信しないので、外部依存なくテストできる。
        @ai_client.stub(:notify_sentry, ->(exception, level:, extra:) {
          notifications << { exception_class: exception.class.name, level: level, extra: extra }
        }) do
          # ④ 実行。全プロバイダ失敗で最終 rescue に到達するはず。
          result = @ai_client.analyze("テスト用プロンプト")

          # 既存仕様どおり nil が返ることを確認。
          assert_nil result
        end
      end
    end

    # notify_sentry がちょうど1回呼ばれたこと（二重通知でない）。
    assert_equal 1, notifications.length

    # 通知レベルが :error であること。
    assert_equal :error, notifications.first[:level]

    # モデル廃止の診断に使う groq_model が記録されていること。
    assert_equal AiClient::GROQ_MODEL, notifications.first[:extra][:groq_model]

    # ★ ユーザーの prompt 本文を Sentry に送っていないこと（個人情報保護）。
    refute notifications.first[:extra].key?(:prompt_snippet)
    refute notifications.first[:extra].key?(:prompt)
  end
end