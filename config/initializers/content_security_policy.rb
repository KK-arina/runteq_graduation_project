# config/initializers/content_security_policy.rb
#
# ============================================================
# Issue #28: Content Security Policy（CSP）設定
# ============================================================
# CSP は XSS（クロスサイトスクリプティング）攻撃を根本から防ぐ
# 最も重要なセキュリティ設定の一つ。
#
# 【CSP とは何か？】
#   ブラウザに対して「このページは〇〇からのリソースしか読み込まない」
#   と宣言するルール。攻撃者が悪意のあるスクリプトを注入しても、
#   ブラウザが CSP ルールに違反するとして実行を拒否する。
#
# 【HabitFlow の構成と CSP の関係】
#   Rails 7 の Importmap は <script type="importmap"> という
#   インラインスクリプトを HTML に直接埋め込む仕組みを使う。
#   これが script-src の :unsafe_inline なしではブロックされる。
#
#   解決策は2つ：
#   A) nonce を使う（毎リクエストごとにランダムな値を生成して許可する）← 推奨
#   B) :unsafe_inline を使う（全インラインスクリプトを許可）← 簡易だが緩い
#
#   HabitFlow では nonce 方式を採用する。
#   nonce 方式なら「Railsが生成したインラインスクリプトのみ」を許可でき、
#   攻撃者が注入したスクリプトは nonce がないためブロックされる。
# ============================================================

Rails.application.config.content_security_policy do |policy|
  # --------------------------------------------------------
  # default_src :self
  # --------------------------------------------------------
  # 他のディレクティブで指定されていないリソースのデフォルトルール。
  # :self は「同じオリジン（同じドメイン＋ポート）からのみ許可」。
  policy.default_src :self

  # --------------------------------------------------------
  # font_src :self, :https, :data
  # --------------------------------------------------------
  # フォントファイルの読み込み元を制限する。
  policy.font_src :self, :https, :data

  # --------------------------------------------------------
  # img_src :self, :https, :data
  # --------------------------------------------------------
  # 画像の読み込み元を制限する。
  policy.img_src :self, :https, :data

  # --------------------------------------------------------
  # object_src :none
  # --------------------------------------------------------
  # <object>（Flash等）の埋め込みを完全に禁止する。
  policy.object_src :none

  # --------------------------------------------------------
  # script_src :self, :https
  # --------------------------------------------------------
  # JavaScript の読み込み元を設定する。
  #
  # 【nonce を使う理由】
  #   Rails 7 の Importmap は以下のようなインラインスクリプトを生成する:
  #     <script type="importmap">{"imports": {...}}</script>
  #     <script type="module">import "application"</script>
  #   これらは外部ファイルではなく HTML に直接書かれたスクリプトのため、
  #   :unsafe_inline なしではブロックされてしまう。
  #
  #   nonce（ワンタイムトークン）を使うと:
  #   - Railsが毎リクエストごとにランダムな nonce 値を生成する
  #   - その nonce を持つスクリプトのみ実行を許可する
  #   - 攻撃者が注入したスクリプトには nonce がないためブロックされる
  #   → :unsafe_inline より安全にインラインスクリプトを許可できる
  #
  # 【:https を追加する理由】
  #   将来的に CDN 経由の外部ライブラリを使う場合に備えて許可している。
  #   現時点では Importmap で管理しているため実質不要だが、
  #   拡張性を考慮して追加している。
  policy.script_src :self, :https

  # --------------------------------------------------------
  # style_src :self, :https, :unsafe_inline
  # --------------------------------------------------------
  # CSS の読み込み元と適用ルールを設定する。
  #
  # 【:unsafe_inline が必要な理由】
  #   HabitFlow のプログレスバーは動的な幅をインラインスタイルで指定している:
  #     style="width: <%= stats[:rate] %>%"
  #   この style 属性は nonce では対応できない（nonce はスクリプト専用）。
  #   style 属性を許可するには :unsafe_inline が必要。
  #
  # 【セキュリティ上のトレードオフ】
  #   style の :unsafe_inline はスクリプトの :unsafe_inline より危険度が低い。
  #   CSS インジェクションは情報漏洩リスクはあるが、
  #   JS 実行ほどの深刻な被害にはなりにくい。
  #   また script_src に :unsafe_inline を入れていないため JS は保護済み。
  policy.style_src :self, :https, :unsafe_inline
end

# ============================================================
# nonce の自動付与設定
# ============================================================
# content_security_policy_nonce_generator:
#   毎リクエストごとにランダムな nonce 値を生成する。
#   SecureRandom.base64 はランダムな Base64 文字列を返す。
#   この nonce は以下に自動で付与される:
#   - javascript_include_tag が生成する <script> タグ
#   - Importmap が生成するインラインスクリプト
#
# content_security_policy_nonce_directives:
#   nonce を適用するディレクティブを指定する。
#   "script-src" のみに適用する（style には nonce は不要 = :unsafe_inline で対応済み）
Rails.application.config.content_security_policy_nonce_generator =
  ->(_request) { SecureRandom.base64(16) }

Rails.application.config.content_security_policy_nonce_directives = [ "script-src" ]
