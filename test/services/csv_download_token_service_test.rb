# test/services/csv_download_token_service_test.rb
#
# ==============================================================================
# CsvDownloadTokenService のテスト
# ==============================================================================
require "test_helper"

class CsvDownloadTokenServiceTest < ActiveSupport::TestCase

  setup do
    @user = users(:one)
  end

  # ==============================================================================
  # generate と verify の往復テスト
  # ==============================================================================

  test "generate したトークンを verify で正しく検証できる" do
    token   = CsvDownloadTokenService.generate(user: @user, export_type: :habit_records)
    payload = CsvDownloadTokenService.verify(token)

    # verify がペイロードを返すことを確認
    assert_not_nil payload
    assert_equal @user.id,        payload["user_id"]
    assert_equal "habit_records", payload["export_type"]
    # expires_at が未来の時刻であることを確認
    assert payload["expires_at"] > Time.current.to_i
  end

  test "不正なトークンを verify すると nil を返す" do
    # 【なぜ assert_nil を使うのか】
    #   CsvDownloadTokenService.verify は例外を raise せずに nil を返す設計。
    #   コントローラーで rescue 不要なシンプルな設計にするためのテスト。
    payload = CsvDownloadTokenService.verify("invalid_token_string")
    assert_nil payload
  end

  test "期限切れトークンを verify すると nil を返す" do
    # travel_to で時刻を操作して期限切れを再現する
    # CsvDownloadTokenService::TOKEN_EXPIRES_IN = 24.hours
    # 25時間後に移動することでトークンを期限切れにする
    token = CsvDownloadTokenService.generate(user: @user, export_type: :tasks)

    travel_to(25.hours.from_now) do
      payload = CsvDownloadTokenService.verify(token)
      assert_nil payload
    end
  end

  test "空文字のトークンを verify すると nil を返す" do
    payload = CsvDownloadTokenService.verify("")
    assert_nil payload
  end

  test "nil のトークンを verify すると nil を返す" do
    payload = CsvDownloadTokenService.verify(nil)
    assert_nil payload
  end
end