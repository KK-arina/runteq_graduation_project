# config/initializers/content_security_policy.rb
#
# ============================================================
# F-1 追加: Google OAuth2 のための CSP 設定更新
# F-2 追加: LINE Login のための CSP 設定を追加
# ============================================================
#
# 【変更内容】
#   form_action に LINE の認証エンドポイントを追加する。
#
# 【なぜ form_action の設定が必要なのか】
#   OmniAuth は button_to（フォーム POST）で認証を開始する。
#   CSP の form-action ディレクティブは「このフォームの送信先（action属性）
#   として許可するURL」を制御する。
#
#   form_action を設定しない場合、デフォルトは default_src の設定に従う。
#   :self のみでは外部URL（access.line.me）へのフォーム送信が
#   ブロックされてしまう。
#
#   → form_action に :self と Google/LINE 認証 URL のドメインを追加する。
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none

  # ── #I-3 追加: :blob を許可する理由 ──────────────────────────────
  #
  # importmap-rails は古いブラウザ互換のために polyfill「es_module_shims」を
  # 読み込む。es_module_shims はモジュールを変換して実行する際に
  # `blob:` スキームの一時スクリプトを生成することがある。
  #
  # これまでの script_src（:self :https :unsafe_inline）には blob: が
  # 含まれていなかったため、本番コンソールで
  #   Loading the script 'blob:https://.../...' violates the following
  #   Content Security Policy directive: "script-src 'self' https: 'unsafe-inline'"
  # というエラーが出て、その blob スクリプトがブロックされていた。
  # （script-src-elem は未設定のため script-src がフォールバックとして使われる）
  #
  # すでに :unsafe_inline と :https を許可している十分ゆるい設定なので、
  # :blob の追加は整合的で、es_module_shims を正しく動かせるようになる。
  policy.script_src  :self, :https, :unsafe_inline, :blob
  policy.style_src   :self, :https, :unsafe_inline

  # ── Issue #I-5 追加: Sentry(ブラウザSDK) のエラー送信先への通信を許可 ──
  #
  # 【なぜ connect_src の追加が必要か】
  #   CSP はブラウザからの外部通信（fetch / XHR / sendBeacon / WebSocket）を
  #   既定で default_src(:self) に制限している。Sentry の Browser SDK は
  #   捕捉した JS エラーを Sentry の収集サーバー（ingest エンドポイント）へ
  #   POST 送信するため、その宛先を明示的に許可しないとブラウザが
  #   「不正な外部通信」としてブロックし、エラーが1件も届かなくなる。
  #
  # 【なぜ "https://*.sentry.io" なのか】
  #   Sentry の ingest ホストはプロジェクトのリージョンにより
  #   o0000.ingest.us.sentry.io / o0000.ingest.de.sentry.io のように変化する。
  #   "*.sentry.io" は .sentry.io で終わる全ホスト（=全リージョンの ingest）に
  #   マッチするため、DSN を将来変えても CSP を直さずに済む。
  #
  # 【なぜ :self を残すのか】
  #   同一オリジンへの通信（Turbo の fetch や ActionCable の WebSocket 等）を
  #   引き続き許可するため。これを外すと既存のリアルタイム機能が壊れる。
  policy.connect_src :self, "https://*.sentry.io"
  # ── F-1/F-2/#I-3: フォーム送信先（OAuth リダイレクト連鎖）の許可設定 ──────
  #
  # form_action:
  #   フォームの action 属性・およびフォーム送信後の「リダイレクト先」を
  #   制御する CSP ディレクティブ。
  #   Chrome / Safari は、フォーム送信 → サーバーの 302 リダイレクトが起きたとき
  #   その【リダイレクト先】も form-action と照合する（Firefox は照合しない）。
  #
  # 【方針: :https ではなく LINE / Google のドメインだけを許可する】
  #   :https（=任意の https 送信先を許可）は範囲が広すぎるため使わない。
  #   ただし LINE Login の認可フローは access.line.me だけでなく LINE の
  #   複数サブドメインを 302 で経由しうる（ログ上 request phase は正常に開始し、
  #   サーバーは LINE へリダイレクトしているが、Chrome が form-action で
  #   リダイレクト連鎖を検査してブロックしていた）。
  #   そこで access.line.me 単体ではなく LINE 全ドメイン（*.line.me と line.me）を
  #   許可して連鎖を通す。Google は accounts.google.com のみ。
  #
  #   :self  … 自アプリへのフォーム送信（OmniAuth の /auth/xxx POST 等）
  #   Google … accounts.google.com（OAuth2 認可）
  #   LINE   … *.line.me / line.me（LINE Login の認可・ログイン画面の連鎖）
  #
  # 【それでもブロックが残る場合】
  #   実際のリダイレクト先が line.me 以外（CDN 等）の可能性がある。
  #   DevTools → Network → line_v2_1 リクエスト → Response Headers の
  #   「location」で実ドメインを確認し、そのドメインをここに追加する。
  policy.form_action :self,
                     "https://accounts.google.com",
                     "https://*.line.me",
                     "https://line.me"
end
Rails.application.config.content_security_policy_nonce_generator =
  ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = []
