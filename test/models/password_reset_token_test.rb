# test/models/password_reset_token_test.rb
#
# ==============================================================================
# PasswordResetToken モデルのテスト
# ==============================================================================
#
# 【テスト対象】
#   PasswordResetToken モデルの以下のメソッド:
#     - self.generate_token_for(user)
#     - self.find_by_raw_token(raw_token)
#     - valid_token?
#     - expire!
#
# 【テスト実行コマンド】
#   docker compose exec web bin/rails test test/models/password_reset_token_test.rb
# ==============================================================================
require "test_helper"

class PasswordResetTokenTest < ActiveSupport::TestCase
  # ============================================================
  # テスト用のユーザーをセットアップ
  # ============================================================
  setup do
    # fixtures(:one) はメール登録ユーザー
    @user = users(:one)
  end

  # ============================================================
  # generate_token_for のテスト
  # ============================================================

  test "generate_token_for はランダムな生トークンを返す" do
    raw_token = PasswordResetToken.generate_token_for(@user)

    # 生トークンが文字列であることを確認
    assert_instance_of String, raw_token

    # 空でないことを確認
    assert raw_token.present?
  end

  test "generate_token_for はDBにレコードを作成する" do
    assert_difference "PasswordResetToken.count", 1 do
      PasswordResetToken.generate_token_for(@user)
    end
  end

  test "generate_token_for を2回呼んでもレコードは1件のまま（upsert）" do
    PasswordResetToken.generate_token_for(@user)

    # 2回目の呼び出しでもレコード数が変わらない
    assert_no_difference "PasswordResetToken.count" do
      PasswordResetToken.generate_token_for(@user)
    end
  end

  test "generate_token_for でレコードの expires_at が24時間後に設定される" do
    travel_to Time.current do
      PasswordResetToken.generate_token_for(@user)
      record = PasswordResetToken.find_by(user: @user)

      # 24時間後（前後1秒以内）であることを確認
      assert_in_delta 24.hours.from_now.to_i, record.expires_at.to_i, 1
    end
  end

  test "generate_token_for で is_used が false にリセットされる" do
    # 最初にトークンを生成して使用済みにする
    PasswordResetToken.generate_token_for(@user)
    record = PasswordResetToken.find_by(user: @user)
    record.expire!
    assert record.is_used

    # 2回目の生成で is_used が false に戻る
    PasswordResetToken.generate_token_for(@user)
    record.reload
    assert_not record.is_used
  end

  # ============================================================
  # find_by_raw_token のテスト
  # ============================================================

  test "find_by_raw_token は正しいトークンでレコードを返す" do
    raw_token = PasswordResetToken.generate_token_for(@user)
    record = PasswordResetToken.find_by_raw_token(raw_token)

    assert_not_nil record
    assert_equal @user.id, record.user_id
  end

  test "find_by_raw_token は間違ったトークンで nil を返す" do
    PasswordResetToken.generate_token_for(@user)
    result = PasswordResetToken.find_by_raw_token("wrong_token")

    assert_nil result
  end

  test "find_by_raw_token は nil で nil を返す" do
    result = PasswordResetToken.find_by_raw_token(nil)
    assert_nil result
  end

  test "find_by_raw_token は空文字で nil を返す" do
    result = PasswordResetToken.find_by_raw_token("")
    assert_nil result
  end

  test "find_by_raw_token は期限切れトークンを見つけない" do
    raw_token = PasswordResetToken.generate_token_for(@user)

    # 25時間後に移動（期限切れ）
    travel_to 25.hours.from_now do
      result = PasswordResetToken.find_by_raw_token(raw_token)
      assert_nil result
    end
  end

  test "find_by_raw_token は使用済みトークンを見つけない" do
    raw_token = PasswordResetToken.generate_token_for(@user)
    record = PasswordResetToken.find_by(user: @user)
    record.expire!

    result = PasswordResetToken.find_by_raw_token(raw_token)
    assert_nil result
  end

  # ============================================================
  # valid_token? のテスト
  # ============================================================

  test "valid_token? は有効期限内かつ未使用のとき true を返す" do
    PasswordResetToken.generate_token_for(@user)
    record = PasswordResetToken.find_by(user: @user)

    assert record.valid_token?
  end

  test "valid_token? は期限切れのとき false を返す" do
    PasswordResetToken.generate_token_for(@user)
    record = PasswordResetToken.find_by(user: @user)

    travel_to 25.hours.from_now do
      assert_not record.valid_token?
    end
  end

  test "valid_token? は使用済みのとき false を返す" do
    PasswordResetToken.generate_token_for(@user)
    record = PasswordResetToken.find_by(user: @user)
    record.expire!

    assert_not record.valid_token?
  end

  # ============================================================
  # expire! のテスト
  # ============================================================

  test "expire! は is_used を true にする" do
    PasswordResetToken.generate_token_for(@user)
    record = PasswordResetToken.find_by(user: @user)

    assert_not record.is_used
    record.expire!
    record.reload
    assert record.is_used
  end
end