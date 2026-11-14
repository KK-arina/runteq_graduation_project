# test/integration/settings_accessibility_test.rb
#
# ==============================================================================
# 設定画面（20番）のアクセシビリティテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   設定画面のフォーム内にあるすべての label が、正しく入力欄と結び付いている
#   （for の値と同じ id の要素がある、または label の中に入力欄がある）
#   特に、プロフィール編集の「ユーザー名」が入力欄（id="user_name"）と結び付いていること。
#
# 【なぜテストにするのか】
#   今後、設定画面にセクションを追加・修正したときに、
#   for のない label や、id とずれた label が入り込んでも気付けるようにするため。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/settings_accessibility_test.rb
# ==============================================================================
require "test_helper"

class SettingsAccessibilityTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    log_in_as(@user)
  end

  test "プロフィール編集の「ユーザー名」の見出しが入力欄と結び付いている" do
    get settings_path

    assert_response :success
    # f.label :name が for="user_name" を出力していること
    assert_select "label[for='user_name']", text: "ユーザー名"
    # 結び付く相手の入力欄（f.text_field :name）が id="user_name" であること
    assert_select "input[id='user_name']"
  end

  test "設定画面のフォーム内の label はすべて入力欄と結び付いている" do
    get settings_path

    # 「form label」でフォームの中にある label だけを検査する
    labels = css_select("form label")
    assert labels.any?, "フォーム内に label が1つもない（セレクターの間違いの可能性）"

    labels.each do |label|
      target_id = label["for"]
      if target_id.present?
        # [id='...'] で探す理由: id に記号が含まれても安全に検索できるため
        assert css_select("[id='#{target_id}']").any?,
               "label（#{label.text.squish}）の for=#{target_id} に対応する id の要素がない"
      else
        assert label.css("input, select, textarea").any?,
               "for も中の入力欄もない label がある: #{label.text.squish}"
      end
    end
  end
end