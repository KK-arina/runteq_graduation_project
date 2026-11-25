# test/integration/missing_javascript_file_test.rb
#
# ==============================================================================
# 存在しない .js の URL にアクセスしたときに、500 ではなく 404 を返すことのテスト
# ==============================================================================
#
# 【このテストを追加した理由】
#   本番で、存在しない .js の URL へのアクセスが 500 エラー（DoubleRenderError）になっていた。
#   404 のレスポンスが JavaScript 形式だったため、Rails の CSRF 対策
#   （verify_same_origin_request）が InvalidCrossOriginRequest を出していたのが原因。
#
# 【allow_forgery_protection を true にする理由】
#   テスト環境では CSRF 対策が無効（false）になっているため、そのままでは本番の不具合を再現できない。
#   このテストの間だけ本番と同じ true にし、終わったら元の値に戻す（ほかのテストに影響させない）。
# ==============================================================================
require "test_helper"

class MissingJavascriptFileTest < ActionDispatch::IntegrationTest
  setup do
    @original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @original_forgery_protection
  end

  test "存在しない .js の URL は 500 ではなく 404 を返す" do
    get "/not_existing_script.js"

    assert_response :not_found
  end

  test "存在しない .js の URL のレスポンスは JavaScript として返さない" do
    get "/not_existing_script.js"

    # JavaScript として返すと、CSRF 対策に止められて 500 になるため
    assert_not_equal "text/javascript", response.media_type
  end

  test "存在しない HTML のページは、これまでどおり 404 のエラー画面を返す" do
    get "/not_existing_page"

    assert_response :not_found
    assert_equal "text/html", response.media_type
  end
end
