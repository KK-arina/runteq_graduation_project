require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RunteqGraduationProject
  class Application < Rails::Application
    # ============================================================
    # Rails のデフォルト設定の読み込み
    # ============================================================
    # config.load_defaults 7.2:
    #   Rails 7.2 で推奨されるデフォルトのセキュリティ・挙動設定を一括で有効化する。
    #   セキュリティ関連では以下が含まれる:
    #   - CSRF保護のデフォルト有効化
    #   - セッションの SameSite=Lax デフォルト設定
    #   - Content-Security-Policy (CSP) ヘッダーの基本設定
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # ============================================================
    # タイムゾーン設定（Issue #37 で追加）
    # ============================================================
    # 【なぜタイムゾーン設定が必要なのか】
    # このアプリは「AM4:00を日付の区切り」「月曜AM4:00でロック発動」という
    # 時間依存ロジックを持っている。
    # タイムゾーンを固定しないと以下の重大バグが発生する：
    #
    #   - 本番環境（Render）はUTCで動く
    #   - config.time_zone 未設定だと Time.zone もUTCになる
    #   - 「月曜AM4:00（JST）」がUTCでは「日曜PM19:00」になる
    #   - ロック判定・振り返り期間がすべて9時間ズレる
    #
    # 【config.time_zone = "Tokyo"】
    #   Time.zone.now や Time.current が常にJST（UTC+9）で動くようになる。
    #   travel_to Time.zone.local(...) もJSTとして解釈されるため、
    #   テストと本番環境で同じ時刻ロジックが適用される。
    #
    # 【config.active_record.default_timezone = :local】
    #   DBへの日時の読み書き時に「:local（= config.time_zoneで設定したJST）」
    #   を使うよう指定する。
    #   :utc（デフォルト）のままだと、DBにはUTCで保存されるが
    #   config.time_zone との変換が複雑になりバグの温床になる。
    config.time_zone = "Tokyo"
    config.active_record.default_timezone = :local

    # lib ディレクトリ以下のファイルを自動読み込みの対象にする（assetsとtasksは除外）。
    config.autoload_lib(ignore: %w[assets tasks])

    # ============================================================
    # Issue #28: セッションCookie のセキュリティ設定
    # ============================================================
    # Rails のセッションは暗号化された Cookie に保存される。
    # デフォルトでも一定のセキュリティはあるが、以下の設定で強化する。
    #
    # 【key】
    #   Cookie の名前。デフォルトは "_session" という汎用的な名前だが、
    #   アプリ固有の名前にすることで他のアプリとの Cookie 混在を防ぐ。
    #
    # 【secure】
    #   true にすると HTTPS 通信のときのみ Cookie を送信する。
    #   HTTP 通信では Cookie が送られないため、
    #   盗聴（中間者攻撃）によるセッションハイジャックを防げる。
    #   開発環境（HTTP）では Cookie が送れなくなるため、
    #   Rails.env.production? で本番環境のみ true にする。
    #
    # 【httponly】
    #   true にすると JavaScript の document.cookie から
    #   この Cookie を読み取れなくなる。
    #   XSS 攻撃でスクリプトを注入されても、
    #   セッション Cookie を盗まれにくくなる。
    #
    # 【same_site】
    #   CSRF（クロスサイトリクエストフォージェリ）対策の追加層。
    #   :strict → 外部サイトからのリクエストには Cookie を一切送らない
    #   :lax    → 外部サイトからの GET リクエストには Cookie を送る（推奨）
    #   :none   → 常に Cookie を送る（非推奨）
    #   HabitFlow は外部 OAuth 連携がないため :lax で十分。
    #
    # 【expire_after】
    #   セッションの有効期限。
    #   nil（デフォルト）はブラウザを閉じるまで有効。
    #   習慣管理アプリはUXと安全性のバランスから 14.days を選択。
    #   （金融系: 30分 / EC: 7日 / SNS: 14日 / 習慣管理: 14日が目安）
    #   将来的に「ログイン状態を保持する」チェックボックスを
    #   実装する場合は、チェックなし: 1日 / あり: 30日 のように
    #   セッション長を分けることを検討する。
    config.session_store :cookie_store,
                         key: "_habitflow_session",
                         secure: Rails.env.production?,
                         httponly: true,
                         same_site: :lax,
                         expire_after: 14.days
  
    config.i18n.default_locale = :ja
  end
end