# test/jobs/purpose_analysis_job_test.rb
#
# ==============================================================================
# PurposeAnalysisJob テスト（G-7 追加分）
# ==============================================================================
require "test_helper"

class PurposeAnalysisJobTest < ActiveJob::TestCase

  setup do
    @user = User.create!(
      name:                  "G7テストユーザー",
      email:                 "purpose_job_test_g7@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    @user_setting = @user.user_setting || UserSetting.create!(user: @user)

    @user_purpose = UserPurpose.create!(
      user:              @user,
      purpose:           "テスト Purpose",
      mission:           "テスト Mission",
      vision:            "テスト Vision",
      value:             "テスト Value",
      current_situation: "テスト Current",
      version:           1,
      is_active:         true,
      analysis_state:    :pending
    )

    # AiClient#analyze のスタブに使う正常レスポンス（3テスト共通）
    # 【@mock_result をインスタンス変数にする理由】
    #   同じ値を3つのテストで使うため setup で1回だけ定義してDRYにする。
    @mock_result = {
      text:  '{"analysis_comment":"テスト分析","root_cause":"テスト原因",' \
             '"coaching_message":"テストコーチング","improvement_suggestions":"テスト改善",' \
             '"actions":[],"crisis_detected":false}',
      model: "gemini-2.5-flash"
    }
  end

  teardown do
    @user_purpose&.destroy
    @user_setting&.destroy
    @user&.destroy
  end

  # ============================================================
  # G-7 テスト1: 完了時に broadcast_dashboard_completion が呼ばれること
  # ============================================================
  test "G-7: AI分析完了時に broadcast_dashboard_completion が呼ばれること" do
    # 【スタブ方法の説明】
    #   AiClient.new が返すインスタンスをスタブするには
    #   AiClient クラス自体の new メソッドをスタブして
    #   analyze が mock_result を返すオブジェクトを返す方法を使う。
    #
    #   Minitest の Object#stub は「オブジェクトの特定のメソッドを
    #   ブロック内だけ差し替える」機能。
    #   AiClient.stub(:new, fake_client) で
    #   「AiClient.new を呼ぶと fake_client が返る」ようにする。
    #
    #   fake_client は analyze メソッドだけ持つ匿名オブジェクト。
    #   Struct.new を使うと手軽に作れる。
    mock_result_value = @mock_result
    fake_client = Object.new
    fake_client.define_singleton_method(:analyze) { |_prompt| mock_result_value }

    AiClient.stub(:new, fake_client) do
      job = PurposeAnalysisJob.new

      called = false
      job.define_singleton_method(:broadcast_dashboard_completion) do |_up|
        called = true
      end

      job.perform(@user_purpose.id)

      assert called, "broadcast_dashboard_completion が呼ばれませんでした"
    end
  end

  # ============================================================
  # G-7 テスト2: broadcast_replace_to がダッシュボード用ストリームで呼ばれること
  # ============================================================
  test "G-7: broadcast_replace_to がダッシュボード用ストリームと正しいターゲットで呼ばれること" do
    mock_result_value = @mock_result
    fake_client = Object.new
    fake_client.define_singleton_method(:analyze) { |_prompt| mock_result_value }

    broadcast_calls = []

    # Turbo::StreamsChannel.broadcast_replace_to をスタブして呼び出しを記録する。
    # 【スタブ方法の説明】
    #   Turbo::StreamsChannel はクラスメソッド broadcast_replace_to を持つ。
    #   Turbo::StreamsChannel.stub(:broadcast_replace_to, lambda) で
    #   ブロック内だけ差し替えられる。
    #   lambda の引数は (stream, **opts) の形で受け取る。
    Turbo::StreamsChannel.stub(:broadcast_replace_to,
      ->(stream, **opts) { broadcast_calls << { stream: stream, target: opts[:target] } }
    ) do
      AiClient.stub(:new, fake_client) do
        PurposeAnalysisJob.perform_now(@user_purpose.id)
      end
    end

    dashboard_stream = "dashboard_notifications_#{@user.id}"
    dashboard_call   = broadcast_calls.find { |c| c[:stream] == dashboard_stream }

    assert_not_nil dashboard_call,
      "ダッシュボード用ストリーム '#{dashboard_stream}' へのブロードキャストが見つかりませんでした。\n" \
      "実際に呼ばれたストリーム: #{broadcast_calls.map { |c| c[:stream] }.inspect}"

    assert_equal "dashboard_pmvv_completion_banner", dashboard_call[:target],
      "target が 'dashboard_pmvv_completion_banner' ではありませんでした。\n" \
      "実際の target: #{dashboard_call[:target]}"
  end

  # ============================================================
  # G-7 テスト3: failed 確定時に broadcast_dashboard_completion が呼ばれないこと
  # ============================================================
  test "G-7: failed 確定時に broadcast_dashboard_completion は呼ばれないこと" do
    # AiClient#analyze が nil を返す = 全プロバイダ失敗をシミュレート
    fake_client_nil = Object.new
    fake_client_nil.define_singleton_method(:analyze) { |_prompt| nil }

    AiClient.stub(:new, fake_client_nil) do
      job = PurposeAnalysisJob.new

      dashboard_broadcast_called = false
      job.define_singleton_method(:broadcast_dashboard_completion) do |_up|
        dashboard_broadcast_called = true
      end

      # reenqueue_count: 3 = MAX_REENQUEUE_COUNT を渡して failed 確定にする。
      # 3 < 3 は false なので再エンキューせず handle_failure が呼ばれる。
      job.perform(@user_purpose.id, reenqueue_count: 3)

      assert_not dashboard_broadcast_called,
        "failed 状態のときに broadcast_dashboard_completion が呼ばれました（呼ばれてはいけない）"
    end
  end
end