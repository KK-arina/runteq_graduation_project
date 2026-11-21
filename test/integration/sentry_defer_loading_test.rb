# test/integration/sentry_defer_loading_test.rb
#
# 【このテストの目的】
#   Sentry Browser SDK を defer で読み込む形が崩れていないことを確かめる。
#   Sentry のタグは本番（SENTRY_DSN がある時）だけ出力されるため、テスト環境の画面には出てこない。
#   そこで、レイアウトのファイルの中身そのものを読んで確かめる。
#   ・SDK 本体と初期化の両方に defer が付いていること
#   ・SDK 本体 → 初期化 → importmap の順に書かれていること（defer は書いた順に実行されるため）
#   ・レイアウトに Sentry.init を直接書いていないこと（インラインの script には defer が効かない）
#   ・初期化のファイルが読む meta タグの名前と、レイアウトの meta タグの名前が一致していること
#   ・初期化のファイルが静的ファイルとして返ること

require "test_helper"

class SentryDeferLoadingTest < ActionDispatch::IntegrationTest
  LAYOUT_PATH = Rails.root.join("app", "views", "layouts", "application.html.erb")
  INIT_PATH = Rails.root.join("public", "sentry", "init-v1.js")

  setup do
    @layout = File.read(LAYOUT_PATH)
  end

  test "SDK 本体と初期化を defer で読み込む" do
    assert_includes @layout, '<script src="/sentry/bundle.min.js" defer></script>'
    assert_includes @layout, '<script src="/sentry/init-v1.js" defer></script>'
  end

  test "SDK 本体 → 初期化 → importmap の順に書かれている" do
    # index … 文字列が最初に出てくる位置（何文字目か）。見つからなければ nil
    bundle_position = @layout.index('src="/sentry/bundle.min.js" defer')
    init_position = @layout.index('src="/sentry/init-v1.js" defer')
    importmap_position = @layout.index("<%= javascript_importmap_tags")

    assert bundle_position && init_position && importmap_position,
           "Sentry の script タグか javascript_importmap_tags が見つかりません。"
    assert bundle_position < init_position, "初期化が SDK 本体より先に書かれています。"
    assert init_position < importmap_position, "importmap が Sentry より先に書かれています。"
  end

  test "レイアウトに Sentry.init を直接書いていない" do
    refute_includes @layout, "Sentry.init(",
                    "インラインの script には defer が効かないため、初期化は public/sentry/init-v1.js に書いてください。"
  end

  test "初期化のファイルが読む meta タグの名前と、レイアウトの meta タグの名前が一致している" do
    init_source = File.read(INIT_PATH)

    %w[sentry-dsn sentry-release].each do |name|
      assert_includes init_source, %("#{name}"), "init-v1.js が #{name} を読んでいません。"
      assert_includes @layout, %(<meta name="#{name}"), "レイアウトに #{name} の meta タグがありません。"
    end
  end

  test "初期化のファイルは静的ファイルとして 200 で返る" do
    # public/ 配下のファイルは ActionDispatch::Static が Rails のルーティングより前に返す
    get "/sentry/init-v1.js"

    assert_response :ok
  end
end