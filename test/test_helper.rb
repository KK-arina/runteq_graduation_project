# test/test_helper.rb
# =============================================================
# テストの共通設定ファイル
# すべてのテストファイルから require される
# =============================================================

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# =============================================================
# TestLoginHelper モジュール
# ログイン処理を1箇所にまとめることで、将来ログイン実装が
# 変わっても test_helper.rb だけ修正すれば済む
# =============================================================
module TestLoginHelper
  # log_in_as(user) : 指定ユーザーでログインする
  # post login_path で実際のHTTPリクエストを通じてログインする
  # これにより SessionsController の動作も含めてテストできる
  def log_in_as(user)
    post login_path, params: {
      session: {
        email: user.email,
        password: "password"  # fixturesで設定したパスワード
      }
    }
  end
end

module ActiveSupport
  class TestCase
    # fixtures :all : test/fixtures/ 以下のすべてのYAMLをテストデータとして読み込む
    fixtures :all
  end
end

# ActionDispatch::IntegrationTest（統合テスト）で
# TestLoginHelper のメソッドが使えるよう組み込む
class ActionDispatch::IntegrationTest
  include TestLoginHelper
end