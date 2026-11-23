# test/integration/active_storage_config_test.rb
require "test_helper"

# Active Storage の画像変換が無効になっていることを確認するテスト
class ActiveStorageConfigTest < ActiveSupport::TestCase
  test "画像変換（variant）は無効に設定されている" do
    assert_equal :disabled, ActiveStorage.variant_processor
  end
end
