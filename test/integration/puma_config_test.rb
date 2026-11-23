# test/integration/puma_config_test.rb
require "test_helper"

# config/puma.rb で、Puma 8 で削除される古い設定名を使っていないことを確認するテスト
#
# 【なぜファイルの中身を確認するのか】
#   Puma の設定は本番（マルチプロセス）で起動したときにしか読まれない部分があり、
#   通常のテストでは実行されない。そのため、設定ファイルの文字列で確認する。
class PumaConfigTest < ActiveSupport::TestCase
  PUMA_CONFIG = Rails.root.join("config/puma.rb").read

  test "Worker 起動時の DB 再接続は新しい名前 before_worker_boot で設定されている" do
    assert_match(/^\s*before_worker_boot do$/, PUMA_CONFIG)
  end

  test "Puma 8 で削除される on_worker_boot を使っていない" do
    assert_no_match(/^\s*on_worker_boot\b/, PUMA_CONFIG)
  end
end
