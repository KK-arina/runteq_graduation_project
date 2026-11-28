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
  /\Acode\z/, /\Astate\z/,

  # ----------------------------------------------------------------
  # 利用者が入力した文章をログに残さない
  # ----------------------------------------------------------------
  #
  # 【なぜ隠すのか】
  #   振り返りや PMVV には、仕事・家族・体調など、利用者の個人的な内容が書かれる。
  #   隠さないと、送信のたびに本番のログ（Render の Logs）へ文章がそのまま記録される。
  #   管理画面で「入力内容は表示しない」と決めたのと同じ考え方で、ログでも伏せる。
  #
  # 【なぜ完全一致（\A 〜 \z）にするのか】
  #   部分一致だと、:value が numeric_value（記録の数値）に、
  #   :purpose が親の user_purpose（PMVV のまとまり全体）にも当たってしまい、
  #   何が隠れるのかが分かりにくくなるため。
  #
  # 【ほかへの影響】
  #   Rails はこの設定を、モデルを表示するとき（inspect）にも使う。
  #   そのため、コンソールで Habit などを表示すると name も [FILTERED] と表示される。
  #   値は habit.name のように個別に呼べば見られる。

  # 振り返り（weekly_reflections）
  /\Areflection_comment\z/, /\Adirect_reason\z/, /\Abackground_situation\z/, /\Anext_action\z/,

  # PMVV（user_purposes・オンボーディング）
  /\Apurpose\z/, /\Amission\z/, /\Avision\z/, /\Avalue\z/, /\Acurrent_situation\z/,

  # 習慣の名前・タスクの題名・記録のメモ・休息モードの理由・利用者の名前
  /\Aname\z/, /\Atitle\z/, /\Amemo\z/, /\Arest_mode_reason\z/
]
