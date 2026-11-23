# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,

  # ----------------------------------------------------------------
  # OAuth（Google / LINE ログイン）のコールバックで届く値をログに残さない
  # ----------------------------------------------------------------
  #
  # 【なぜ隠すのか】
  #   code  : ログイン用の「認可コード」。短時間・1回限りの値だが、ログに残さないのが安全。
  #   state : 不正なログイン要求を防ぐための照合用の値。
  #
  # 【なぜ :code ではなく正規表現（/\Acode\z/）なのか】
  #   この設定は「部分一致」で働くため、:code と書くと country_code など
  #   関係のない項目まで隠れてしまう。
  #   \A（文字列の先頭）と \z（文字列の末尾）で挟み、名前が完全に一致するものだけを隠す。
  /\Acode\z/, /\Astate\z/
]
