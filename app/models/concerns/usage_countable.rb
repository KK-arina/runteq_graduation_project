# app/models/concerns/usage_countable.rb
#
# ==============================================================================
# UsageCountable: 管理画面の集計の対象にするユーザーを決める scope
# ==============================================================================
#
# 【このファイルの役割】
#   User に include して、User.countable_for_usage で
#   「集計に含めてよいユーザー」だけを取り出せるようにする。
#   管理画面の全体の集計とユーザー一覧の両方で、必ずこの scope から始める。
#   （集計ごとに条件を書くと、どこかで外し忘れが起きるため、1か所にまとめる）
#
# 【集計から外すユーザー】
#   ① 退会済み（deleted_at が NULL でない）
#        → User.active で外す。退会済みは名前・メールが匿名化されている
#   ② デモ・テスト用アカウント（example.com などの予約ドメインのアドレス）
#        → ReservedDomainInterceptor（メールを止める仕組み）と同じ判定を SQL で行う
#   ③ 管理者自身（ADMIN_EMAILS に書いたアドレス）
#        → 自分の操作で数字が増えないようにする。ログイン方法に関係なく外す
#
# 【メールアドレスが NULL のユーザー（LINE ログイン）を残すための書き方】
#   SQL では、NULL と比べた結果は「真でも偽でもない（NULL）」になり、WHERE で外れてしまう。
#   そのため、②③ の条件には必ず「users.email IS NULL OR …」を付けて、
#   メールのない LINE ユーザーが集計から消えないようにしている。
#
# 【ADMIN_EMAILS が空のときに ③ の条件を付けない理由】
#   空の一覧で NOT IN を書くと、Rails は NOT IN (NULL) という SQL を作る。
#   これは全員について「真でも偽でもない」になり、全ユーザーが集計から外れてしまう。
# ==============================================================================
module UsageCountable
  extend ActiveSupport::Concern

  included do
    # countable_for_usage
    #
    # 【!~ とは】
    #   PostgreSQL の「正規表現に一致しない」という演算子（一致する、は ~）。
    #
    # 【SPLIT_PART(users.email, '@', 2)】
    #   メールアドレスを "@" で区切った2つ目（ドメイン部分）を取り出す。
    #
    # 【? を使う理由】
    #   正規表現やメールアドレスの一覧を、SQL の文字列に直接つなげず、
    #   Rails に安全に埋め込ませる（SQL インジェクションを防ぐ）。
    scope :countable_for_usage, -> {
      relation = active.where(
        "users.email IS NULL OR LOWER(SPLIT_PART(users.email, '@', 2)) !~ ?",
        ReservedDomainInterceptor::RESERVED_DOMAIN_SQL_PATTERN
      )

      admin_emails = User.admin_emails.to_a
      if admin_emails.empty?
        relation
      else
        relation.where("users.email IS NULL OR LOWER(TRIM(users.email)) NOT IN (?)", admin_emails)
      end
    }
  end
end
