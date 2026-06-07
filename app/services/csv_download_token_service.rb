# app/services/csv_download_token_service.rb
#
# ==============================================================================
# CsvDownloadTokenService - セキュアなCSVダウンロードURL生成サービス
# ==============================================================================
#
# 【このクラスの役割】
#   CSVダウンロード用の署名付きトークンを生成・検証する。
#   Rails標準の MessageVerifier を使い、改ざん検知と有効期限管理を行う。
#
# 【なぜ ActiveRecord#signed_id を使わないのか】
#   ActiveRecord#signed_id は「特定のモデルのIDに署名する」機能。
#   CSVダウンロードのトークンには user_id + export_type の2つの情報が必要で、
#   signed_id には乗せられない。
#   Rails.application.message_verifier は任意のペイロードに署名できるため
#   このユースケースに適している。
#
# 【即時ダウンロード（5分）とバックグラウンド処理（24時間）で期限を使い分ける】
#   即時ダウンロード: 今すぐ使うトークンなので5分で十分
#   バックグラウンド処理: メールが届いてからダウンロードするまでの時間が必要なため24時間
#   generate メソッドの expires_in 引数で柔軟に指定できる設計にしている。
#
# ==============================================================================
class CsvDownloadTokenService

  # デフォルトのトークン有効期間（バックグラウンド処理用）
  DEFAULT_EXPIRES_IN = 24.hours

  # VERIFIER_PURPOSE: MessageVerifierの用途識別子
  # 【なぜpurposeを設定するのか】
  #   同じsecret_key_baseを使う別の用途のトークン
  #   （パスワードリセット等）と混同しないようにするため。
  VERIFIER_PURPOSE = "csv_download".freeze

  # ==============================================================================
  # generate - 署名付きダウンロードトークンを生成する
  # ==============================================================================
  #
  # 【引数】
  #   user:        Userインスタンス
  #   export_type: :habit_records / :tasks / :weekly_reflections
  #   expires_in:  有効期限（Duration、省略時は24時間）
  #                即時ダウンロードは 5.minutes を渡す
  #                バックグラウンド処理は 24.hours（デフォルト）
  def self.generate(user:, export_type:, expires_in: DEFAULT_EXPIRES_IN)
    payload = {
      # 文字列キーで統一する（verify 側でも文字列キーでアクセスするため）
      "user_id"     => user.id,
      "export_type" => export_type.to_s,
      # UNIX時刻（整数）で保存する
      # 【なぜ整数にするのか】
      #   Timeオブジェクトはシリアライズ時に文字列になり、
      #   復元時の型変換が必要になる。
      #   整数（UNIX時刻）なら Time.at() で確実に復元できる。
      "expires_at"  => expires_in.from_now.to_i
    }

    Rails.application.message_verifier(VERIFIER_PURPOSE).generate(payload)
  end

  # ==============================================================================
  # verify - トークンを検証してペイロードを返す
  # ==============================================================================
  #
  # 【戻り値】
  #   成功時: { "user_id" => 1, "export_type" => "habit_records", "expires_at" => ... }
  #   失敗時: nil（無効・改ざん・期限切れ）
  def self.verify(token)
    # nilや空文字は早期リターン
    return nil if token.blank?

    payload = Rails.application.message_verifier(VERIFIER_PURPOSE).verify(token)

    # 有効期限チェック
    # payload は文字列キーなので payload["expires_at"] でアクセスする
    expires_at = payload["expires_at"]
    if expires_at.blank? || Time.at(expires_at) < Time.current
      Rails.logger.warn "[CsvDownloadTokenService] トークン期限切れ: user_id=#{payload['user_id']}"
      return nil
    end

    payload
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    # 署名が無効（改ざん・不正なトークン）
    Rails.logger.warn "[CsvDownloadTokenService] 無効なトークン"
    nil
  rescue => e
    Rails.logger.error "[CsvDownloadTokenService] トークン検証エラー: #{e.message}"
    nil
  end
end