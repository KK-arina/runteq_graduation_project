# test/integration/privacy_page_test.rb
require "test_helper"

# プライバシーポリシー（app/views/pages/privacy.html.erb）の記載を確かめるテスト
#
# 【このテストで確かめること】
#   管理画面での利用状況の集計を始めたので、その説明と、
#   実際に使っている外部サービス（Sentry・LINE 通知）が書かれていること。
#   未ログインでも開けること（利用規約に同意する前にも読めるようにするため）。
class PrivacyPageTest < ActionDispatch::IntegrationTest
  # 【assert_match ではなく assert_select を使う理由】
  #   assert_match "…", response.body は、一致しなかったときにページの HTML をまるごと表示し、
  #   原因が読み取りにくい。assert_select なら「どの要素を探して何件見つかったか」だけが表示される。

  test "未ログインでも開け、利用状況の集計についての説明がある" do
    get privacy_path

    assert_response :success
    assert_select "h2", text: "4-3. 利用状況の集計について"
    # 外部のアクセス解析ツールを使っていないこと、入力内容を表示しないことが書かれている
    assert_select "p", text: /外部のアクセス解析ツールは使用しません/
    assert_select "p", text: /ユーザーが入力した内容は表示しません/
  end

  test "実際に使っている外部サービス（Sentry・LINE 通知）が載っている" do
    get privacy_path

    assert_select "li", text: /\ASentry（エラー監視/
    assert_select "li", text: /\ALINE Messaging API（LINE 通知/
  end

  test "退会は設定ページからできると書かれている" do
    get privacy_path

    assert_select "p", text: /設定ページから退会（アカウントの削除）の手続きができます/
  end
end
