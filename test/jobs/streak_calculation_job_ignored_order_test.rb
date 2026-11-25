# test/jobs/streak_calculation_job_ignored_order_test.rb
#
# ==============================================================================
# StreakCalculationJob で「Scoped order is ignored」の警告が出ないことのテスト
# ==============================================================================
#
# 【このテストを追加した理由】
#   Habit.active には画面表示用の並び順（order）が付いている。
#   find_each は ID の順でしか取り出せないため、並び順が付いたまま使うと
#   「Scoped order is ignored」の警告が本番のログに出ていた。
#
# 【error_on_ignored_order を true にする理由】
#   ふだんは警告（ログ）が出るだけなので、テストでは気づけない。
#   このテストの間だけ「並び順が無視されたら例外を出す」設定にして、
#   警告が出る状態ならテストが失敗するようにする。終わったら元の値に戻す。
#
# 【perform_now ではなく new.perform を使う理由】
#   ApplicationJob の retry_on により、perform_now ではエラーが起きても
#   やり直しの予約に回され、テストでは例外として見えない。
#   new.perform はジョブの中身を直接実行するため、例外がそのまま表に出る。
# ==============================================================================
require "test_helper"

class StreakCalculationJobIgnoredOrderTest < ActiveSupport::TestCase
  setup do
    @original_error_on_ignored_order = ActiveRecord.error_on_ignored_order
    ActiveRecord.error_on_ignored_order = true
  end

  teardown do
    ActiveRecord.error_on_ignored_order = @original_error_on_ignored_order
  end

  test "Habit.active の並び順があっても、find_each で並び順が無視されたという例外が出ない" do
    # 処理する習慣が1件もないと find_each の確認にならないため、fixture にあることを先に確かめる
    assert Habit.active.exists?, "fixture に有効な習慣がありません"

    assert_nothing_raised do
      StreakCalculationJob.new.perform
    end
  end
end
