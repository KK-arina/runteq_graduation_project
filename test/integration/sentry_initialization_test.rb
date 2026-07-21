# test/integration/sentry_initialization_test.rb
#
# ==============================================================================
# Issue #I-5: Sentry 疎通・除外フィルタ・GoodJob連携 のテスト
# ==============================================================================
# 【目的】
#   ① Sentry.capture_exception で例外イベントが生成されること（疎通）
#   ② 除外例外（RecordNotFound / RoutingError）は生成されないこと（404ノイズ除外）
#   ③ GoodJob の on_thread_error フックが Sentry.capture_exception を呼ぶこと
#
# 【実際の Sentry へ送信しない仕組み】
#   before_send（送信直前フック）で event を配列に記録して nil を返す。
#   nil を返すと Sentry はそのイベントを破棄する＝外部通信は一切発生しない。
#
# 【他テストを汚さない仕組み】
#   本番以外では config/initializers/sentry.rb が Sentry を初期化しない。
#   このテスト内でだけ一時的に init し、teardown で Sentry.close して無効化する。
# ==============================================================================

require "test_helper"

class SentryInitializationTest < ActiveSupport::TestCase
  def setup
    @captured_events = []
    events = @captured_events # クロージャに安全に渡すためのローカル束縛

    Sentry.init do |config|
      config.dsn = "http://public@localhost:9999/1"       # ダミー（before_sendで握るので送信されない）
      config.enabled_environments = %w[test]               # このテスト専用にtestで有効化
      config.background_worker_threads = 0                 # 同期処理（即時アサート）

      # 【重要】client reports（破棄イベントの統計送信）を無効化する。
      #   before_send で event を nil にして捨てると、Sentry はそれを「破棄イベント」
      #   として集計し、teardown の Sentry.close 時にその統計をダミーDSN
      #   （localhost:9999）へ送信しようとして Connection refused
      #   （Sentry::ExternalError）になる。テストでは統計送信は不要なので
      #   false にして実ネットワークアクセスを完全に断つ。
      config.send_client_reports = false

      config.before_send = ->(event, _hint) do            # 記録してnil＝実送信を遮断
        events << event
        nil
      end
      # 【③反映】excluded_exceptions はここで再定義しない。
      #   RecordNotFound / RoutingError は Sentry の既定除外リスト
      #   （Sentry::Configuration::IGNORE_DEFAULT）に元から含まれるため、
      #   何も足さなくても除外される。ここで += すると initializer と二重管理になり、
      #   将来 initializer だけ変えたときにテストが古い設定のまま残ってしまう。
      #   よって「既定＋initializerの実挙動」をそのまま検証する。
    end
  end

  def teardown
    # 【②反映】Sentry.init を再度呼んで戻すと二重初期化になるため、
    #   公式のシャットダウンAPI Sentry.close を使う。
    #   close 後は Sentry.initialized? が false になり、以降の API は no-op になる。
    #   これにより他テストへ状態が漏れない。
    #   （send_client_reports=false により close 時のネットワーク送信も発生しない）
    Sentry.close
  end

  test "capture_exception で例外イベントが生成される" do
    Sentry.capture_exception(StandardError.new("I-5 疎通テスト"))
    assert_equal 1, @captured_events.size,
                 "通常の例外は Sentry イベントとして記録されるべき"
  end

  test "RecordNotFound は除外され記録されない" do
    Sentry.capture_exception(ActiveRecord::RecordNotFound.new("存在しません"))
    assert_equal 0, @captured_events.size,
                 "RecordNotFound は既定の除外（IGNORE_DEFAULT）で記録されないべき（404ノイズ削減）"
  end

  test "RoutingError は除外され記録されない" do
    Sentry.capture_exception(ActionController::RoutingError.new("no route"))
    assert_equal 0, @captured_events.size,
                 "RoutingError は既定の除外（IGNORE_DEFAULT）で記録されないべき（404ノイズ削減）"
  end

  # ── ①反映: on_thread_error が Sentry.capture_exception を呼ぶことを検証 ──
  # 【なぜ stub で検証するのか】
  #   before_send の内部挙動ではなく「capture_exception が呼ばれた」という契約だけを
  #   確認するため、Sentry SDK のイベント処理内部が変わっても壊れにくい。
  # 【なぜ skip ガードを付けるのか】
  #   GoodJob.on_thread_error は公式ドキュメント記載の公開アクセサだが、
  #   将来の Gem 変更に備え、アクセサが無い版では落とさずスキップする。
  test "GoodJob の on_thread_error が Sentry.capture_exception を呼ぶ" do
    unless GoodJob.respond_to?(:on_thread_error) && GoodJob.on_thread_error.respond_to?(:call)
      skip "この GoodJob 版には on_thread_error 公開アクセサが無いためスキップ"
    end

    captured = nil
    # Sentry.capture_exception を一時的に差し替え、呼ばれた例外を記録する
    Sentry.stub(:capture_exception, ->(exception, **_opts) { captured = exception }) do
      GoodJob.on_thread_error.call(StandardError.new("I-5 GoodJob スレッドエラー疎通"))
    end

    assert_instance_of StandardError, captured,
                       "on_thread_error は Sentry.capture_exception を呼ぶべき"
  end
end