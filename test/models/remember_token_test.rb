# test/models/remember_token_test.rb
#
# ==============================================================================
# RememberToken モデルのテスト（ログイン保持）
# ==============================================================================
#
# 【このテストで保証すること】
#   ① DB には生のトークンではなく SHA-256 の値だけが保存される
#   ② 有効なトークンだけが見つかり、改ざん・期限切れは見つからない
#   ③ 期限の延長は1日に1回だけで、最長180日を超えない
#   ④ 端末数の上限（10台）を超えると古いものから削除される
#   ⑤ User#revoke_all_logins! で全トークン削除と auth_version の更新が行われる
#
# 【実行方法】
#   docker compose exec web bin/rails test test/models/remember_token_test.rb
# ==============================================================================
require "test_helper"

class RememberTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  # ── ① 保存されるのは digest だけ ─────────────────────────────────────
  test "発行すると生のトークンを返し、DB には SHA-256 の値だけを保存する" do
    record, raw_token = RememberToken.issue_for!(@user)

    # 生のトークンは推測できない長さ（32バイトを base64 にすると43文字）
    assert_operator raw_token.length, :>=, 43

    # DB の値は生のトークンそのものではなく、SHA-256 の値になっている
    assert_not_equal raw_token, record.token_digest
    assert_equal Digest::SHA256.hexdigest(raw_token), record.token_digest

    # 有効期限は約30日後になっている（1秒程度の誤差は許容する）
    assert_in_delta 30.days.from_now.to_f, record.expires_at.to_f, 2
  end

  # ── ② 有効なトークンだけが見つかる ───────────────────────────────────
  test "正しい生のトークンで有効なレコードが見つかる" do
    record, raw_token = RememberToken.issue_for!(@user)

    found = RememberToken.find_active_by_raw_token(raw_token)

    assert_equal record.id, found.id
    # eager_load しているので user も一緒に取得できている
    assert_equal @user.id, found.user.id
  end

  test "空・存在しないトークンでは見つからない" do
    RememberToken.issue_for!(@user)

    assert_nil RememberToken.find_active_by_raw_token(nil)
    assert_nil RememberToken.find_active_by_raw_token("")
    assert_nil RememberToken.find_active_by_raw_token("tampered-token")
  end

  test "30日間使われなかったトークンは期限切れで見つからない" do
    _record, raw_token = RememberToken.issue_for!(@user)

    # travel_to: テストの中だけ「現在時刻」を未来に進める
    travel_to 31.days.from_now do
      assert_nil RememberToken.find_active_by_raw_token(raw_token)
    end
  end

  # ── ③ 期限の延長 ──────────────────────────────────────────────────────
  test "前回から1日たっていなければ延長せず、DB に書き込まない" do
    record, _raw_token = RememberToken.issue_for!(@user)
    original_expires_at = record.expires_at

    travel_to 12.hours.from_now do
      assert_not record.slide_expiration!, "1日未満なので false を返すべき"
      assert_equal original_expires_at.to_i, record.reload.expires_at.to_i
    end
  end

  test "1日以上たってから使うと、そこから30日後まで延長される" do
    record, _raw_token = RememberToken.issue_for!(@user)

    travel_to 20.days.from_now do
      assert record.slide_expiration!, "1日以上たっているので true を返すべき"
      assert_in_delta 30.days.from_now.to_f, record.reload.expires_at.to_f, 2
    end
  end

  test "どれだけ使っても最初の発行から180日を超えて延長されない" do
    record, _raw_token = RememberToken.issue_for!(@user)

    # 発行から175日たっている状態を作る（あと5日で最長期限）
    record.update_columns(created_at: 175.days.ago, last_used_at: 2.days.ago)

    record.slide_expiration!

    # 「今から30日後」ではなく「発行から180日後」で止まっている
    assert_in_delta (record.created_at + 180.days).to_f,
                    record.reload.expires_at.to_f,
                    2
  end

  # ── ④ 掃除と上限 ──────────────────────────────────────────────────────
  test "新しく発行するとき、そのユーザーの期限切れトークンを削除する" do
    old_record, _old_raw = RememberToken.issue_for!(@user)
    old_record.update_columns(expires_at: 1.minute.ago)

    RememberToken.issue_for!(@user)

    assert_not RememberToken.exists?(old_record.id), "期限切れトークンは削除されるべき"
  end

  test "1ユーザー10台を超えると、古いトークンから削除される" do
    first_record, _raw = RememberToken.issue_for!(@user)
    10.times { RememberToken.issue_for!(@user) }

    assert_equal RememberToken::MAX_PER_USER, @user.remember_tokens.count
    assert_not RememberToken.exists?(first_record.id), "一番古いトークンが削除されるべき"
  end

  # ── ⑤ すべての端末の解除 ──────────────────────────────────────────────
  test "revoke_all_logins! で全トークンを削除し auth_version を1つ増やす" do
    2.times { RememberToken.issue_for!(@user) }
    before_version = @user.reload.auth_version

    @user.revoke_all_logins!

    assert_equal 0, @user.remember_tokens.count
    assert_equal before_version + 1, @user.reload.auth_version
  end

  test "revoke_all_logins! は他のユーザーのトークンを消さない" do
    other_user = users(:two)
    RememberToken.issue_for!(@user)
    RememberToken.issue_for!(other_user)

    @user.revoke_all_logins!

    assert_equal 1, other_user.remember_tokens.count
  end
end