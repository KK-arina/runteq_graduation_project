# app/controllers/admin/base_controller.rb
#
# ==============================================================================
# Admin::BaseController: 管理画面（/admin 以下）すべてのコントローラーの親クラス
# ==============================================================================
#
# 【このファイルの役割】
#   管理画面のコントローラーは、すべてこのクラスを継承する。
#   ここに「誰が見てよいか」「どう返すか」をまとめておくことで、
#   新しい管理画面を追加したときに、認可の入れ忘れが起きないようにする。
#
# 【チェックの順番（before_action は書いた順に実行される）】
#   ① require_admin!
#        管理者（User#admin?）でなければ 404 を返す。未ログインも同じく 404。
#        ログイン画面へリダイレクトしないので、管理画面があること自体が分からない。
#   ② set_admin_response_headers
#        管理者に返す画面には「キャッシュしない」「検索エンジンに載せない」ヘッダーを付ける。
#        ① の 404 には付けない（ふつうの 404 と見分けがつかないようにするため）。
#   ③ require_recent_interactive_login!
#        ログイン画面から手でログインしてから12時間以内でなければ、
#        「もう一度ログインしてください」の画面を出す。
#        「ログインしたままにする」で自動的にログインした状態では開けない。
#
# 【管理画面は読み取り専用】
#   ユーザーの編集・削除は行わない（GET の画面だけを用意する）。
# ==============================================================================
module Admin
  class BaseController < ApplicationController
    # 手でログインしてから、管理画面を開けるまでの時間
    #   1日1回ログインし直す程度の手間で、盗まれた Cookie が長く使われるのを防ぐ。
    REAUTH_INTERVAL = 12.hours

    # 利用規約に同意していないユーザーを同意ページへ移動させる処理を、管理画面では止める
    #
    # 【止める理由】
    #   止めないと、未同意のユーザーが /admin を開いたときだけ「同意ページへの移動」になり、
    #   存在しない URL（同意ページへは移動せず 404）と反応が変わってしまう。
    #   その違いから、/admin に何かがあることが分かってしまうため。
    #   管理者かどうかの判定は、このあとの require_admin! で必ず行う。
    skip_before_action :redirect_to_terms_agreement_if_needed

    before_action :require_admin!
    before_action :set_admin_response_headers
    before_action :require_recent_interactive_login!

    private

    # require_admin!
    #
    # 【役割】管理者でなければ 404 を返し、処理をそこで止める。
    #
    # 【current_user&.admin? の &.（ぼっち演算子）】
    #   未ログイン（current_user が nil）のときは admin? を呼ばずに nil になり、
    #   unless の条件が成り立つので 404 になる。
    #
    # 【render_404（ApplicationController）を使う理由】
    #   存在しない URL（errors#not_found）と同じ画面・同じステータスを返すため。
    #   before_action の中で render すると、Rails はそこで処理を止める（アクションは実行されない）。
    def require_admin!
      render_404 unless current_user&.admin?
    end

    # set_admin_response_headers
    #
    # 【no_store】
    #   Cache-Control: no-store を付ける Rails のメソッド。
    #   ブラウザや途中のサーバーに、この画面を一切保存させない
    #   （共用のパソコンで「戻る」を押しても、前の人の管理画面が出ないようにする）。
    #
    # 【X-Robots-Tag: noindex, nofollow】
    #   検索エンジンに「このページを検索結果に載せない・リンクをたどらない」と伝えるヘッダー。
    #   robots.txt に /admin を書かない理由:
    #     robots.txt はだれでも読めるので、書くと管理画面の場所を自分で知らせることになる。
    #     また、robots.txt でクロールを止めると、この noindex が読まれなくなる。
    def set_admin_response_headers
      no_store
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end

    # require_recent_interactive_login!
    #
    # 【役割】
    #   手でログインしてから REAUTH_INTERVAL（12時間）以内でなければ、
    #   「もう一度ログインしてください」の画面（app/views/admin/reauth.html.erb）を出す。
    #
    # 【status: :forbidden（403）にする理由】
    #   「あなたが誰かは分かっているが、今の状態では開けない」という意味のステータスのため。
    #   ここに来るのは管理者だと確認できた人だけなので、管理画面の存在が他人に分かることはない。
    def require_recent_interactive_login!
      return if recent_interactive_login?

      render "admin/reauth", status: :forbidden
    end

    # recent_interactive_login?
    #
    # 【役割】手でログインした時刻（concerns/remember_login.rb の log_in で記録）が、
    #   12時間以内なら true を返す。
    #
    # 【.to_i を使う理由】
    #   値がない（自動ログイン・この機能を入れる前のセッション）場合は nil で、
    #   nil.to_i は 0 になる。0 は positive? が false なので、再ログインの案内になる。
    #
    # 【Time.zone.at】
    #   保存した秒数（整数）を、アプリのタイムゾーン（東京）の時刻に戻す。
    def recent_interactive_login?
      logged_in_at = session[:interactive_login_at].to_i
      return false unless logged_in_at.positive?

      Time.zone.at(logged_in_at) > REAUTH_INTERVAL.ago
    end
  end
end
