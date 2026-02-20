# test/test_helper.rb
# ============================================================
# テスト全体の設定ファイル
#
# 【このファイルの役割】
# - テスト実行前の共通設定
# - 全テストで使えるヘルパーモジュールの読み込み
# ============================================================

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# ActiveSupport::TestCase: Railsの標準テストベースクラス
module ActiveSupport
  class TestCase
    # ============================================================
    # parallel_tests の設定
    # parallelize: テストを並列実行してスピードアップする設定
    # workers: :number_of_processors → CPUコア数に応じてワーカー数を決定
    # ============================================================
    parallelize(workers: :number_of_processors)

    # ============================================================
    # fixtures :all
    # test/fixtures/ ディレクトリの全YAMLファイルを
    # テスト開始前にDBへロードする設定
    # ============================================================
    fixtures :all

    # ============================================================
    # include ActiveSupport::Testing::TimeHelpers
    # travel_to メソッドを使うために必要なモジュール
    # travel_to を使うことで、テスト中のシステム時刻を任意の時間に変更できます
    # AM4:00 境界値テストで使用しています
    # ============================================================
    include ActiveSupport::Testing::TimeHelpers
  end
end