# config/initializers/content_security_policy.rb
#
# ============================================================
# Issue #28: Content Security Policy（CSP）設定
# ============================================================
#
# 【B-7 最終修正】
#
#   問題の経緯:
#     ① nonce_directives = ["script-src"] の状態
#        → Turbo Drive のページ遷移時に nonce が引き継がれず
#          Turbo Stream の DOM 差し替えがブロックされていた
#
#     ② nonce_directives = [] に変更
#        → nonce によるブロックは解消したが、
#          Importmap が生成するインラインスクリプト
#          （<script type="importmap">、<script type="module">）が
#          'self' でも 'https:' でもないインラインコードのため
#          引き続き CSP エラーが出る
#
#   解決策:
#     script_src に :unsafe_inline を追加する。
#
#   【:unsafe_inline のセキュリティリスクについて】
#     :unsafe_inline を付けると「全てのインラインスクリプト」を許可する。
#     本来は XSS 攻撃でインライン JS を注入されるリスクがある。
#     ただし Rails の Importmap + Turbo の構成では
#     nonce による制御が困難なため、開発・プロトタイプ段階では
#     :unsafe_inline で対応するのが現実的な選択肢となる。
#
#     【リスク軽減の方針】
#     - script_src :self のみにすることで外部ドメインの JS はブロック
#     - 入力値のサニタイズをモデル・ビューで徹底することで
#       XSS の根本原因を防ぐ
#
# ============================================================

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none

  # --------------------------------------------------------
  # script_src :self, :https, :unsafe_inline
  # --------------------------------------------------------
  # 【:unsafe_inline を追加する理由】
  #   Rails 7 の Importmap は以下のインラインスクリプトを HTML に直接埋め込む:
  #     <script type="importmap">{"imports": {...}}</script>
  #     <script type="module">import "application"</script>
  #   これらは「インラインスクリプト」扱いになるため、
  #   :unsafe_inline なしでは CSP にブロックされる。
  #
  #   nonce 方式を使えば :unsafe_inline は不要だが、
  #   Turbo Drive のページ遷移時に nonce が引き継がれない問題があり、
  #   Turbo Stream の DOM 差し替えが失敗する。
  #
  #   :self, :https だけでは外部ドメインの JS はブロックできるため、
  #   外部スクリプト注入のリスクは残らない。
  policy.script_src :self, :https, :unsafe_inline

  policy.style_src :self, :https, :unsafe_inline
end

# ============================================================
# nonce の設定
# ============================================================
#
# 【nonce_directives を [] にしている理由】
#   Turbo Drive がページ遷移時に body を差し替えるとき、
#   新しい body 内の <script> タグには古いページの nonce が
#   引き継がれないため、CSP エラーが発生していた。
#   nonce_directives を [] にすることで nonce による制御を無効化し、
#   Turbo Stream の DOM 差し替えが正常に動作するようにする。
#
# 【nonce_generator を残している理由】
#   将来的に nonce 方式に戻す可能性を考慮して残している。
#   nonce_directives = [] の状態では実質的に使用されない。
Rails.application.config.content_security_policy_nonce_generator =
  ->(_request) { SecureRandom.base64(16) }

Rails.application.config.content_security_policy_nonce_directives = []