ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # ========================================================================
    # テストヘルパーの読み込み
    # ========================================================================
    
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # ========================================================================
    # 【追加】TimeHelpers のインクルード
    # ========================================================================
    # - travel_to メソッドを使用するために必要
    # - 時間を任意の時刻に固定してテストを実行できる
    # - Issue #14 の AM 4:00 基準テストで使用
    # ========================================================================
    include ActiveSupport::Testing::TimeHelpers

    # Add more helper methods to be used by all tests here...
  end
end
