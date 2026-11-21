# test/integration/good_job_cron_config_test.rb
#
# 【このテストの目的】
#   GoodJob の cron（config/initializers/good_job.rb）の設定が壊れていないことを確かめる。
#   本番で cron が一度も動いていなかったことが分かったため、
#   ・すべての cron のジョブのクラスが実在すること（名前の打ち間違いが無いこと）
#   ・すべての cron 式を、GoodJob が使っている Fugit で読めること
#   ・LISTEN/NOTIFY を無効にしていること（Neon の pooler でエラーが出るため）
#   ・cron を本番だけ有効にする設定が書かれていること
#   を確かめる。

require "test_helper"

class GoodJobCronConfigTest < ActiveSupport::TestCase
  # Rails.application.config.good_job … config.good_job.xxx = … で設定した値の入れ物
  GOOD_JOB_CONFIG = Rails.application.config.good_job
  INITIALIZER_PATH = Rails.root.join("config", "initializers", "good_job.rb")

  test "すべての cron のジョブのクラスが実在する" do
    GOOD_JOB_CONFIG.cron.each do |key, entry|
      # safe_constantize … 文字列のクラス名から本物のクラスを探す。見つからなければ nil を返す
      assert entry[:class].safe_constantize,
             "cron「#{key}」のクラス #{entry[:class]} が見つかりません。"
    end
  end

  test "すべての cron 式を Fugit で読める" do
    GOOD_JOB_CONFIG.cron.each do |key, entry|
      # Fugit::Cron.parse … cron 式を読む。読めない書き方なら nil を返す
      assert Fugit::Cron.parse(entry[:cron]),
             "cron「#{key}」の cron 式「#{entry[:cron]}」を読めません。"
    end
  end

  test "LISTEN/NOTIFY を無効にしている" do
    assert_equal false, GOOD_JOB_CONFIG.enable_listen_notify
  end

  test "cron は本番だけ有効にする設定になっている" do
    # テスト環境では cron を動かさないので値は false になる。
    # 本番で有効になることは値では確かめられないため、設定の書き方そのものを確かめる
    assert_equal false, GOOD_JOB_CONFIG.enable_cron
    assert_includes File.read(INITIALIZER_PATH),
                    "config.good_job.enable_cron = Rails.env.production?"
  end
end
