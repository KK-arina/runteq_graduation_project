# frozen_string_literal: true

# test/integration/rack_attack_test.rb

require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  ATTACK_IP    = "1.2.3.4"
  LOCALHOST_IP = "127.0.0.1"

  setup do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    Rack::Attack.throttle("login/ip", limit: 10, period: 300) do |req|
      req.ip if req.path == "/login" && req.post?
    end

    Rack::Attack.throttle("login/email", limit: 10, period: 1200) do |req|
      if req.path == "/login" && req.post?
        req.params.dig("session", "email").to_s.downcase.strip.presence
      end
    end

    # throttled_responder もテスト環境では未登録のため登録する
    Rack::Attack.throttled_responder = lambda do |request|
      match_data = request.env["rack.attack.match_data"]
      period = match_data[:period]
      [
        429,
        {
          "Content-Type" => "text/html; charset=utf-8",
          "Retry-After"  => period.to_s,
          "Cache-Control" => "no-cache, no-store"
        },
        ["Too Many Requests"]
      ]
    end
  end

  teardown do
    Rack::Attack.enabled = false
    Rack::Attack.throttles.clear
    Rack::Attack.throttled_responder = nil
    Rack::Attack.cache.store.clear
  end

  test "10回以内のログイン試行はブロックされない" do
    10.times do
      post "/login",
           params:  { session: { email: "user@example.com", password: "wrong" } },
           headers: { "REMOTE_ADDR" => ATTACK_IP }
      assert_not_equal 429, response.status,
        "10回以内の試行でブロックされてはいけない（現在: #{response.status}）"
    end
  end

  test "11回目のログイン試行は 429 でブロックされる" do
    10.times do
      post "/login",
           params:  { session: { email: "attacker@example.com", password: "wrong" } },
           headers: { "REMOTE_ADDR" => ATTACK_IP }
    end

    post "/login",
         params:  { session: { email: "attacker@example.com", password: "wrong" } },
         headers: { "REMOTE_ADDR" => ATTACK_IP }

    assert_equal 429, response.status,
      "11回目は 429 でブロックされなければならない"
    assert response.headers["Retry-After"].present?,
      "429 レスポンスには Retry-After ヘッダーが必要"
  end

  test "異なる IP からのリクエストは独立してカウントされる" do
    10.times do
      post "/login",
           params:  { session: { email: "ip_test@example.com", password: "wrong" } },
           headers: { "REMOTE_ADDR" => ATTACK_IP }
    end

    # 別 IP・別メールで1回目 → ブロックされない
    post "/login",
         params:  { session: { email: "other_ip@example.com", password: "wrong" } },
         headers: { "REMOTE_ADDR" => "5.6.7.8" }

    assert_not_equal 429, response.status,
      "別 IP からのリクエストはブロックされてはいけない"
  end

  test "localhost からのリクエストは5回以内はブロックされない" do
    5.times do
      post "/login",
           params:  { session: { email: "local@example.com", password: "wrong" } },
           headers: { "REMOTE_ADDR" => LOCALHOST_IP }
      assert_not_equal 429, response.status,
        "5回以内の試行はブロックされてはいけない"
    end
  end
end