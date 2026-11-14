# test/integration/habit_form_accessibility_test.rb
#
# ==============================================================================
# 習慣フォーム（新規作成・編集）のアクセシビリティテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① フォーム内のすべての label が、正しく入力欄と結び付いている
#      （for の値と同じ id の要素がある、または label の中に入力欄がある）
#   ② 「カラー」「アイコン」「記録タイプ」「除外する曜日」が fieldset + legend で
#      グループとして見出しを持っている
#   ③ カラー・アイコンのボタンに aria-pressed があり、「選択中」がちょうど1つだけ
#
# 【なぜテストにするのか】
#   今後フォームを修正したときに、うっかり label の for がずれたり、
#   グループの見出しが label に戻ったりしても、テストで気付けるようにするため。
#
# 【実行方法】
#   docker compose exec web bin/rails test test/integration/habit_form_accessibility_test.rb
# ==============================================================================
require "test_helper"

class HabitFormAccessibilityTest < ActionDispatch::IntegrationTest
  # 習慣フォームを特定するセレクター
  #   ヘッダーのログアウトボタンなど、ほかのフォームを検査対象に含めないため、
  #   data-controller="habit-form" が付いたフォームだけに絞る。
  HABIT_FORM = "form[data-controller='habit-form']".freeze

  setup do
    @user = users(:one)
    log_in_as(@user)
  end

  # ── 共通の検査メソッド ─────────────────────────────────────────────

  # フォーム内のすべての label が入力欄と結び付いていることを確認する
  #   for がある label   → 同じ id の要素がページ内にあること
  #   for がない label   → label の中に input / select / textarea があること
  def assert_labels_are_associated
    labels = css_select("#{HABIT_FORM} label")
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

  # 指定した見出しの fieldset + legend があることを確認する
  def assert_fieldset_with_legend(text)
    assert_select "#{HABIT_FORM} fieldset > legend", text: text
  end

  # ── 新規作成フォーム ───────────────────────────────────────────────
  test "新規作成フォームの label はすべて入力欄と結び付いている" do
    get new_habit_path

    assert_response :success
    assert_labels_are_associated
  end

  test "新規作成フォームの選択肢グループは fieldset と legend で見出しを持つ" do
    get new_habit_path

    assert_fieldset_with_legend "カラー"
    assert_fieldset_with_legend "アイコン"
    assert_fieldset_with_legend "記録タイプ"
    assert_fieldset_with_legend "除外する曜日"
  end

  test "新規作成フォームでは初期値のブルーと📋だけが aria-pressed=true になっている" do
    get new_habit_path

    # 「選択中」はちょうど1つ（count: 1）
    assert_select "#{HABIT_FORM} [data-habit-form-target='colorSwatch'][aria-pressed='true']", count: 1
    assert_select "#{HABIT_FORM} [data-color-value='#3b82f6'][aria-pressed='true']"

    assert_select "#{HABIT_FORM} [data-habit-form-target='iconButton'][aria-pressed='true']", count: 1
    assert_select "#{HABIT_FORM} [data-icon-value='📋'][aria-pressed='true']"

    # それ以外は aria-pressed=false（属性そのものが付いていることも確認できる）
    assert_select "#{HABIT_FORM} [data-habit-form-target='colorSwatch'][aria-pressed='false']", count: 7
    assert_select "#{HABIT_FORM} [data-habit-form-target='iconButton'][aria-pressed='false']", count: 15
  end

  # ── 編集フォーム ───────────────────────────────────────────────────
  test "編集フォームの label はすべて入力欄と結び付き、保存済みの色とアイコンが aria-pressed=true になっている" do
    habit = Habit.create!(
      user:             @user,
      name:             "アクセシビリティ確認用",
      weekly_target:    7,
      measurement_type: :check_type,
      color:            "#10b981",
      icon:             "📚"
    )

    get edit_habit_path(habit)

    assert_response :success
    assert_labels_are_associated

    # 編集画面の記録タイプは表示だけなので fieldset にはしない。ほかの3つはグループ。
    assert_fieldset_with_legend "カラー"
    assert_fieldset_with_legend "アイコン"
    assert_fieldset_with_legend "除外する曜日"

    # DB に保存した色・アイコンだけが「選択中」
    assert_select "#{HABIT_FORM} [data-habit-form-target='colorSwatch'][aria-pressed='true']", count: 1
    assert_select "#{HABIT_FORM} [data-color-value='#10b981'][aria-pressed='true']"
    assert_select "#{HABIT_FORM} [data-habit-form-target='iconButton'][aria-pressed='true']", count: 1
    assert_select "#{HABIT_FORM} [data-icon-value='📚'][aria-pressed='true']"
  end
end