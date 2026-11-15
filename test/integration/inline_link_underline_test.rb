# test/integration/inline_link_underline_test.rb
#
# ==============================================================================
# 文の途中にあるリンクに、常に下線が付いていることの統合テスト
# ==============================================================================
#
# 【なぜ必要か】
#   文の途中にあるリンクを色だけで区別すると、色覚の違いによって
#   周りの文字と見分けられないことがある（WCAG 1.4.1「色の使用」）。
#   Lighthouse でも「リンクは色に依存して識別可能です」と指摘される。
#   マウスを乗せたときだけ下線を出す（hover:underline）のではなく、
#   常に下線（underline）を表示する。
#
# 【underline-offset-2 で確かめる理由】
#   今回の修正で付けたクラスなので、「直したリンク」を確実に見分けられる。
#   ヘッダーやフッターの単独のリンク（文の途中ではないもの）は対象外のため、
#   それらに一致しないクラスを使う。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/inline_link_underline_test.rb
# ==============================================================================
require "test_helper"

class InlineLinkUnderlineTest < ActionDispatch::IntegrationTest
  test "ログイン画面の「新規登録」リンクに常に下線が付いている" do
    get login_path
    assert_response :success

    assert_select "a.underline.underline-offset-2[href='#{new_user_path}']", text: "新規登録", count: 1
  end

  test "新規登録画面の文の途中にあるリンクに常に下線が付いている" do
    get new_user_path
    assert_response :success

    # 利用規約・プライバシーポリシーへの同意の文と、「〜の方は ログイン」の文の3つ
    assert_select "a.underline.underline-offset-2", minimum: 3
  end
end