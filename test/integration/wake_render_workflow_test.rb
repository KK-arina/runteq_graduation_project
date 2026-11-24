# test/integration/wake_render_workflow_test.rb
require "test_helper"

# Render を起こすワークフロー（.github/workflows/wake_render.yml）の設定を確認するテスト
#
# 【ファイルの中身を確認する理由】
#   ワークフローは GitHub の上でしか動かないため、
#   「安全な設定になっているか」を設定ファイルの中身で確認する。
class WakeRenderWorkflowTest < ActiveSupport::TestCase
  WORKFLOW = YAML.safe_load(Rails.root.join(".github/workflows/wake_render.yml").read)

  test "API と手動でだけ起動し、遅れやすい schedule は使わない" do
    # YAML では on: が true（真偽値）として読まれるため、両方の書き方で取り出す
    triggers = WORKFLOW["on"] || WORKFLOW[true]

    assert_equal [ "workflow_dispatch" ], triggers.keys
  end

  test "リポジトリへの権限を何も渡さない" do
    assert_equal({}, WORKFLOW["permissions"])
  end

  test "止まらなくなっても打ち切られる" do
    assert_equal 10, WORKFLOW.dig("jobs", "wake", "timeout-minutes")
  end
end
