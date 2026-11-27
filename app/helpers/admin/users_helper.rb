# app/helpers/admin/users_helper.rb
#
# ==============================================================================
# Admin::UsersHelper: 管理画面のユーザー一覧で使う表示用のメソッド
# ==============================================================================
module Admin
  module UsersHelper
    # masked_email
    #
    # 【役割】メールアドレスの「@ より前」を1文字だけ残して伏せ字にする。
    #   例: "taro.yamada@gmail.com" → "t***@gmail.com"
    #
    # 【なぜ伏せ字にするのか】
    #   一覧の目的は「どんな人が使っているか（ドメインなど）」を知ることで、
    #   メールアドレスそのものは必要ないため（表示は必要最小限にする）。
    #   画面を人に見せたり、スクリーンショットを撮ったりしたときに漏れるのも防ぐ。
    #
    # 【引数が nil・空のとき】
    #   LINE ログインでメールがない人は nil。そのときは nil を返し、
    #   ビューで「（メールなし）」と表示する。
    def masked_email(email)
      return nil if email.blank?

      local, domain = email.to_s.split("@", 2)
      "#{local.to_s.first}***@#{domain}"
    end
  end
end
