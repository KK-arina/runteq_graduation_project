# app/models/concerns/admin_role.rb
#
# ==============================================================================
# AdminRole: 管理者（管理画面 /admin を見られる人）の判定
# ==============================================================================
#
# 【このファイルの役割】
#   User に include して、user.admin? で「このユーザーが管理者か」を判定できるようにする。
#   User モデルはすでに長いため、管理者まわりの処理だけをこのファイルに分けている。
#
# 【なぜ DB の列（users.admin など）ではなく環境変数 ADMIN_EMAILS で判定するのか】
#   Render の無料プランでは本番の rails console が使えないため、
#   DB の列に「管理者フラグ」を立てる操作が簡単にできない。
#   環境変数なら Render の画面で値を入れるだけで設定・変更でき、
#   値（メールアドレス）がコードや GitHub に残ることもない。
#
# 【ADMIN_EMAILS の書き方】
#   カンマ区切りで複数のメールアドレスを書ける。
#     例: ADMIN_EMAILS=me@example.com,sub@example.com
#   前後の空白・大文字小文字の違いは無視する（" Me@Example.com " でも一致する）。
#
# 【管理者になる条件（すべて満たしたときだけ true）】
#   ① 退会していない（deleted_at が NULL）
#   ② メールアドレスがある（LINE ログインでメールがない人は必ず false）
#   ③ ログイン方法（provider）が「メール」か「Google」
#   ④ メールアドレスが ADMIN_EMAILS のどれかと一致する
#
# 【③ で LINE ログインを対象外にする理由】
#   LINE がメールアドレスを返すのは、LINE Developers Console で申請が通った場合だけで、
#   メールがない（NULL の）ユーザーもいる。管理者はメールか Google でログインする、と決めて
#   判定の経路を減らしておくほうが安全で分かりやすい。
#   また User.from_omniauth は、同じメールアドレスのアカウントに LINE でログインすると
#   provider を "line_v2_1" に書き換える。この場合は管理者でなくなる（安全な側）に倒れる。
#
# 【ADMIN_EMAILS が未設定・空のとき】
#   一致するアドレスが1つもないので、誰も管理者にならない（安全な側に倒れる）。
# ==============================================================================
module AdminRole
  # ActiveSupport::Concern:
  #   include したクラスに、インスタンスメソッド（admin?）と
  #   クラスメソッド（class_methods の中身）をまとめて追加できるようにする Rails の仕組み。
  extend ActiveSupport::Concern

  # 管理者のメールアドレスを入れる環境変数の名前
  #   名前を定数にしておくと、テストやほかのファイルで同じ名前を使い回せる（打ち間違いを防ぐ）。
  ADMIN_EMAILS_ENV_KEY = "ADMIN_EMAILS".freeze

  # 管理者として認めるログイン方法（users.provider の値）
  #   "email"         : メールアドレスとパスワードで登録したユーザー（provider の初期値）
  #   "google_oauth2" : Google でログインしたユーザー（Google がメールの持ち主を確認している）
  ADMIN_PROVIDERS = %w[email google_oauth2].freeze

  class_methods do
    # admin_emails
    #
    # 【役割】環境変数 ADMIN_EMAILS から、管理者のメールアドレスの一覧（Set）を作って返す。
    #
    # 【処理の流れ】
    #   ENV.fetch(..., "")   : 未設定なら空文字として扱う（nil でエラーにしない）
    #   .split(",")          : カンマで区切って配列にする
    #   .map { 正規化 }      : 前後の空白を削り、小文字にそろえる
    #   .reject(&:blank?)    : 空の項目（",," や末尾のカンマ）を捨てる
    #   .to_set              : Set（重複なし・検索が速い集合）にする
    #
    # 【毎回 ENV を読む理由（メモ化しない理由）】
    #   アドレスは数件なので、毎回読んでも負担はない。
    #   テストで ENV を書き換えたときに、すぐに反映されるようにするため。
    def admin_emails
      ENV.fetch(ADMIN_EMAILS_ENV_KEY, "")
         .split(",")
         .map { |address| normalize_admin_email(address) }
         .reject(&:blank?)
         .to_set
    end

    # normalize_admin_email
    #
    # 【役割】メールアドレスの比較用に、前後の空白を削って小文字にそろえる。
    #   .to_s: nil が渡されても空文字として扱い、エラーにしない。
    def normalize_admin_email(address)
      address.to_s.strip.downcase
    end
  end

  # admin?
  #
  # 【役割】このユーザーが管理者なら true、それ以外は false を返す。
  #   条件はファイル冒頭の「管理者になる条件」を参照。
  #   上から順に、当てはまらない条件があればすぐに false を返す（早期リターン）。
  def admin?
    return false if deleted_at.present?
    return false if email.blank?
    return false unless admin_provider?

    self.class.admin_emails.include?(self.class.normalize_admin_email(email))
  end

  private

  # admin_provider?
  #
  # 【役割】ログイン方法が、管理者として認める方法（メール・Google）かどうかを返す。
  #   provider.blank?: provider が空のユーザーは「メール登録」として扱う
  #   （User#email_provider? と同じ考え方）。
  def admin_provider?
    provider.blank? || ADMIN_PROVIDERS.include?(provider)
  end
end
