# test/integration/good_job_cron_config_test.rb
#
# 【このテストの目的】
#   GoodJob の cron（config/initializers/good_job.rb）の設定が壊れていないことを確かめる。
#   本番で cron が一度も動いていなかったこと、動き始めたら 9 時間ずれていたことが分かったため、
#   ・すべての cron のジョブのクラスが実在すること（名前の打ち間違いが無いこと）
#   ・すべての cron 式を、GoodJob が使っている Fugit で読めること
#   ・すべての cron 式に Asia/Tokyo が書かれていること（サーバーの設定に左右されないため）
#   ・すべての cron が、決めた日本時間（と曜日）に動くこと
#   ・LISTEN/NOTIFY を無効にしていること（Neon の pooler でエラーが出るため）
#   ・cron を本番だけ有効にする設定が書かれていること
#   を確かめる。

require "test_helper"

class GoodJobCronConfigTest < ActiveSupport::TestCase
  # Rails.application.config.good_job … config.good_job.xxx = … で設定した値の入れ物
  GOOD_JOB_CONFIG = Rails.application.config.good_job
  INITIALIZER_PATH = Rails.root.join("config", "initializers", "good_job.rb")

  # 各 cron が動くべき日本時間。wday は曜日（0 = 日曜 〜 6 = 土曜）。nil は毎日
  # cron-job.org で起こす時刻も、この表に合わせている
  EXPECTED_JST_SCHEDULE = {
    streak_daily_calculation:       { hour: 4, min: 5,  wday: nil },
    daily_notification_count_reset: { hour: 0, min: 5,  wday: nil },
    monthly_ai_count_reset:         { hour: 0, min: 0,  wday: nil },
    weekly_report_mail:             { hour: 9, min: 0,  wday: 1 },
    rest_mode_expiry:               { hour: 4, min: 10, wday: nil },
    update_ai_profiles:             { hour: 4, min: 15, wday: 1 }
  }.freeze

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

  test "すべての cron 式の末尾に Asia/Tokyo が書かれている" do
    GOOD_JOB_CONFIG.cron.each do |key, entry|
      assert entry[:cron].end_with?(" Asia/Tokyo"),
             "cron「#{key}」の cron 式「#{entry[:cron]}」に Asia/Tokyo がありません。日本時間で書いて、末尾に Asia/Tokyo を付けてください。"
    end
  end

  test "すべての cron が、決めた日本時間に動く" do
    # 表に載っている cron と、設定されている cron が、同じ顔ぶれであること
    assert_equal EXPECTED_JST_SCHEDULE.keys.sort, GOOD_JOB_CONFIG.cron.keys.map(&:to_sym).sort

    GOOD_JOB_CONFIG.cron.each do |key, entry|
      expected = EXPECTED_JST_SCHEDULE.fetch(key.to_sym)
      # 次に動く時刻を求めて、日本時間に直す
      next_time = Fugit::Cron.parse(entry[:cron]).next_time.to_t.in_time_zone("Asia/Tokyo")

      assert_equal expected[:hour], next_time.hour, "cron「#{key}」の時（日本時間）が違います。"
      assert_equal expected[:min], next_time.min, "cron「#{key}」の分が違います。"
      if expected[:wday]
        assert_equal expected[:wday], next_time.wday, "cron「#{key}」の曜日が違います。"
      end
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
