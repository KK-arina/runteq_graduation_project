# test/integration/pwa_home_screen_test.rb
#
# ==============================================================================
# ホーム画面に追加（PWA）: マニフェスト・アイコン・<head> のタグ・案内表示の統合テスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① マニフェストが正しい Content-Type で返り、必要な項目（名前・起動ページ・表示方法など）がそろっている
#   ② マニフェストのアイコンと iPhone 用アイコンが実際に返り、画像の大きさが宣言どおり
#   ③ ログイン前・ログイン後のページの <head> に、マニフェスト・アイコン・テーマ色のタグがある
#   ④ Service Worker を登録していない（ファイル・ルート・登録処理のどれも無い）
#   ⑤ 起動ページ（/dashboard）は、未ログインならログイン画面へ移動し、ログイン後に戻ってこられる
#   ⑥ 設定ページに案内カード、ログイン画面に注意書き（最初は非表示）がある
#
# 【public/ のファイルを get で取得できる理由】
#   テスト環境でも ActionDispatch::Static（public/ のファイルを返すミドルウェア）が有効なため、
#   本番と同じく、Rails のコントローラーを通らずにファイルが返る。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/pwa_home_screen_test.rb
# ==============================================================================
require "test_helper"

class PwaHomeScreenTest < ActionDispatch::IntegrationTest
  MANIFEST_PATH         = "/pwa/manifest-v1.webmanifest".freeze
  APPLE_TOUCH_ICON_PATH = "/pwa/apple-touch-icon-v1.png".freeze
  FAVICON_PATH          = "/pwa/favicon-32-v1.png".freeze
  THEME_COLOR           = "#2563eb".freeze

  # PNG ファイルのはじめの8バイトは、必ずこの決まった値（PNG の署名）になる
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze

  # ── テスト用のヘルパーメソッド ─────────────────────────────────────────

  # public/ の中のファイルの絶対パスを返す（例: "/pwa/icon-192-v1.png" → .../public/pwa/icon-192-v1.png）
  #   delete_prefix("/"): 先頭の / を外さないと、join したときにルートからのパスとして扱われてしまう
  def public_file(path)
    Rails.public_path.join(path.delete_prefix("/"))
  end

  # PNG ファイルの「幅 x 高さ」を [幅, 高さ] で返す
  #
  # 【gem を使わずに読める理由】
  #   PNG は「署名8バイト → IHDR チャンク」の順に並ぶ決まりで、
  #   ファイルの 16〜23 バイト目に幅と高さが4バイトずつ（ビッグエンディアン）入っている。
  #   unpack("NN") は「4バイトの符号なし整数（ビッグエンディアン）を2つ」読み取る指定。
  def png_size(path)
    header = File.binread(path, 24)
    assert_equal PNG_SIGNATURE, header[0, 8], "#{path} が PNG ではありません"
    header[16, 8].unpack("NN")
  end

  # マニフェストを取得して、JSON を Ruby の Hash にして返す
  def fetch_manifest
    get MANIFEST_PATH
    assert_response :success
    JSON.parse(response.body)
  end

  # ── ① マニフェスト ──────────────────────────────────────────────────────
  test "マニフェストが application/manifest+json で返り、必要な項目がそろっている" do
    manifest = fetch_manifest

    # media_type: Content-Type から "; charset=..." を除いた部分
    assert_equal "application/manifest+json", response.media_type

    assert_equal "/",          manifest["id"]
    assert_equal "HabitFlow",  manifest["name"]
    assert_equal "HabitFlow",  manifest["short_name"]
    assert_equal "ja",         manifest["lang"]
    assert_equal "standalone", manifest["display"]
    assert_equal THEME_COLOR,  manifest["theme_color"]

    # 起動ページはダッシュボード。実際にルートが存在することも確かめる
    assert_equal "/dashboard", manifest["start_url"]
    assert_equal dashboard_path, manifest["start_url"]

    # scope は "/"（ログイン画面と OmniAuth のコールバックもアプリの範囲に含めるため）
    assert_equal "/", manifest["scope"]
    assert manifest["start_url"].start_with?(manifest["scope"]),
           "start_url が scope の外にあると、アイコンから開いたときにアプリとして扱われません"
  end

  # ── ② アイコン ──────────────────────────────────────────────────────────
  test "マニフェストのアイコンが実際に返り、宣言した大きさの PNG になっている" do
    icons = fetch_manifest["icons"]

    # Chrome のインストール条件: 192px と 512px のアイコンが必要
    sizes = icons.map { |icon| icon["sizes"] }
    assert_includes sizes, "192x192"
    assert_includes sizes, "512x512"

    # Android の丸・角丸の切り抜き用（maskable）が1つ以上ある
    assert icons.any? { |icon| icon["purpose"] == "maskable" }, "maskable アイコンがありません"

    icons.each do |icon|
      # 宣言した大きさ（"192x192"）と、ファイルの実際の大きさが一致する
      expected = icon["sizes"].split("x").map(&:to_i)
      assert_equal expected, png_size(public_file(icon["src"])), "#{icon['src']} の大きさが違います"

      # HTTP でも画像として返る
      get icon["src"]
      assert_response :success
      assert_equal "image/png", response.media_type
    end
  end

  test "iPhone 用アイコンとファビコンが返り、public 直下のコピーも同じ画像になっている" do
    assert_equal [ 180, 180 ], png_size(public_file(APPLE_TOUCH_ICON_PATH))
    assert_equal [ 32, 32 ],   png_size(public_file(FAVICON_PATH))

    [ APPLE_TOUCH_ICON_PATH, FAVICON_PATH, "/apple-touch-icon.png", "/apple-touch-icon-precomposed.png" ].each do |path|
      get path
      assert_response :success
      assert_equal "image/png", response.media_type
    end

    # <link> を見ずに直接取りに来るアクセス用のコピーが、<link> で指定した画像と同じ中身か
    #   FileUtils.compare_file: 2つのファイルの中身が完全に同じなら true
    %w[apple-touch-icon.png apple-touch-icon-precomposed.png].each do |name|
      assert FileUtils.compare_file(public_file(APPLE_TOUCH_ICON_PATH), public_file(name)),
             "public/#{name} が apple-touch-icon-v1.png と違います（bin/generate_pwa_icons で作り直してください）"
    end
  end

  # ── ③ <head> のタグ ─────────────────────────────────────────────────────
  test "未ログインのページ（ログイン画面）の head にマニフェスト・アイコン・テーマ色のタグがある" do
    get login_path
    assert_response :success

    assert_select "head" do
      assert_select "link[rel='manifest'][href='#{MANIFEST_PATH}']", count: 1
      assert_select "link[rel='apple-touch-icon'][href='#{APPLE_TOUCH_ICON_PATH}'][sizes='180x180']", count: 1
      assert_select "link[rel='icon'][href='#{FAVICON_PATH}'][type='image/png']", count: 1
      assert_select "meta[name='theme-color'][content='#{THEME_COLOR}']", count: 1
      assert_select "meta[name='application-name'][content='HabitFlow']", count: 1
      assert_select "meta[name='apple-mobile-web-app-title'][content='HabitFlow']", count: 1
      assert_select "meta[name='mobile-web-app-capable'][content='yes']", count: 1
      assert_select "meta[name='apple-mobile-web-app-capable'][content='yes']", count: 1
      assert_select "meta[name='apple-mobile-web-app-status-bar-style'][content='default']", count: 1
    end
  end

  test "ログイン後のページ（設定ページ）の head にもマニフェストのタグがある" do
    # 設定ページを使う理由:
    #   ダッシュボードは、初回ログインのユーザーだとオンボーディングへ移動するため、
    #   fixture の状態によって結果が変わる。設定ページはオンボーディング前でも表示される
    #   （ApplicationController#redirect_to_onboarding_if_needed の除外リストに settings がある）。
    log_in_as(users(:one))

    get settings_path
    assert_response :success
    assert_select "head link[rel='manifest'][href='#{MANIFEST_PATH}']", count: 1
  end

  test "head で指定したファイルが、すべて public/ に存在する" do
    get login_path

    # css_select: assert_select と同じ書き方で要素を探し、配列で受け取る
    hrefs = css_select("head link[rel='manifest'], head link[rel='icon'], head link[rel='apple-touch-icon']")
              .map { |link| link["href"] }
              .select { |href| href.start_with?("/pwa/") }

    assert_equal 3, hrefs.size
    hrefs.each do |href|
      assert File.exist?(public_file(href)), "#{href} が public/ にありません"
    end
  end

  # ── ④ Service Worker を使っていない ────────────────────────────────────
  test "Service Worker のファイル・ルート・登録処理がない" do
    # Rails 8 の雛形（app/views/pwa/）と、public/ 直下の Service Worker が無い
    assert_not File.exist?(Rails.root.join("app/views/pwa/service-worker.js"))
    assert_not File.exist?(Rails.public_path.join("service-worker.js"))

    # /service-worker と /manifest は rails/pwa に割り当てず、末尾の catch-all（errors#not_found）になる
    %w[/service-worker /manifest].each do |path|
      route = Rails.application.routes.recognize_path(path)
      assert_equal "errors", route[:controller], "#{path} がルーティングされています"
    end

    # ページの中に Service Worker を登録する処理が無い
    get login_path
    assert_not_includes response.body, "serviceWorker"
  end

  # ── ⑤ 起動ページ ───────────────────────────────────────────────────────
  test "起動ページ（/dashboard）は、未ログインならログイン画面に移動し、ログイン後に戻る先を持っている" do
    get dashboard_path

    # require_login が redirect_to パラメータ付きでログイン画面へ移動させる
    assert_redirected_to login_path(redirect_to: dashboard_path)
  end

  # ── ⑥ 案内の表示 ───────────────────────────────────────────────────────
  test "設定ページに「ホーム画面に追加する」の案内カードと、端末ごとの手順がある" do
    log_in_as(users(:one))

    get settings_path
    assert_response :success

    assert_select "section#pwa-install-guide[data-testid='pwa-install-guide'][data-controller~='pwa-guide']" do
      # 端末ごとの手順（PwaGuideController の platform と同じ値）
      %w[ios android desktop inapp].each do |platform|
        assert_select "details[data-pwa-guide-target='panel'][data-platform='#{platform}']", count: 1
      end

      # ホーム画面から初めて開いたときのログインの案内（すべての端末で表示）
      assert_select "[data-testid='pwa-first-login-hint']",
                    text: /#{Regexp.escape(I18n.t("pwa_install.guide.first_login.body"))}/

      # ホーム画面から開いているときの表示と、インストールボタンは最初は非表示
      assert_select "[data-testid='pwa-standalone-status'][hidden]"
      assert_select "[data-pwa-guide-target='installArea'][hidden]"

      # LINE などから Safari / Chrome で開き直すリンク（LINE 公式の openExternalBrowser=1）
      assert_select "a[href*='openExternalBrowser=1'][href$='#pwa-install-guide']", count: 1
    end
  end

  test "ログイン保持していない端末では、ホーム画面から開いたときの表示が「保持していない」になる" do
    log_in_as(users(:one))

    get settings_path
    assert_select "[data-testid='pwa-standalone-status']",
                  text: /#{Regexp.escape(I18n.t("pwa_install.guide.standalone.not_remembered"))}/
  end

  test "ログイン保持している端末では、ホーム画面から開いたときの表示が「保持している」になる" do
    log_in_as(users(:one))
    post remember_device_settings_path

    get settings_path
    assert_select "[data-testid='pwa-standalone-status']",
                  text: /#{Regexp.escape(I18n.t("pwa_install.guide.standalone.remembered"))}/
  end

  test "ログイン画面に、ホーム画面から開いたとき用の注意書きが非表示の状態で入っている" do
    get login_path

    assert_select "[data-controller~='pwa-guide'] [data-testid='pwa-login-notice'][hidden]" do
      assert_select "[data-pwa-guide-target='iosStandaloneOnly'][hidden]", count: 1
    end
    assert_includes response.body, I18n.t("pwa_install.login.remember_hint")
  end
end
