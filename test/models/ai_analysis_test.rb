# test/models/ai_analysis_test.rb

require "test_helper"

class AiAnalysisTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @user_purpose = UserPurpose.create!(
      user:           @user,
      purpose:        "テスト Purpose",
      vision:         "テスト Vision",
      analysis_state: :completed
    )
  end

  test "必須フィールドが揃っている場合は有効である" do
    ai_analysis = AiAnalysis.new(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "テスト分析コメント",
      root_cause:       "テスト根本原因",
      coaching_message: "テストコーチングメッセージ",
      is_latest:        true
    )
    assert ai_analysis.valid?, "バリデーションエラー: #{ai_analysis.errors.full_messages}"
  end

  test "analysis_type が未設定の場合は無効である" do
    # 【修正】
    # enum のデフォルト値（0 = weekly_reflection）があるため
    # analysis_type を省略しても自動でセットされてしまう。
    # そのため「無効なanalysis_type」でテストする方針に変更する。
    #
    # Rails の enum は整数で管理されており、
    # 定義されていない値（例: 999）を文字列で渡すと
    # ArgumentError が発生して invalid になる。
    # ただし enum バリデーションで invalid を確認するより、
    # 「presence: true」の意図に沿ったテストに修正する。
    ai_analysis = AiAnalysis.new(
      user_purpose:     @user_purpose,
      analysis_comment: "テスト"
      # analysis_type を省略すると enum のデフォルト(0)が使われるため
      # このテストは「analysis_typeを意図的に nil にする」必要がある
    )
    # analysis_type を強制的に nil にする
    # 【理由】enum のデフォルト値があるため省略するだけでは nil にならない
    #         write_attribute を使うと enum のセッターを経由せず直接 nil を設定できる
    ai_analysis.write_attribute(:analysis_type, nil)

    assert_not ai_analysis.valid?,
               "analysis_type が nil の場合は無効であるはず"
    assert ai_analysis.errors[:analysis_type].any?,
           "analysis_type のエラーが存在するはず"
  end

  test "user_purpose_id と weekly_reflection_id が両方 nil の場合は無効である" do
    ai_analysis = AiAnalysis.new(
      analysis_type:    :purpose_breakdown,
      analysis_comment: "テスト"
      # user_purpose も weekly_reflection も設定しない
    )
    assert_not ai_analysis.valid?
    assert_includes ai_analysis.errors[:base],
                    "weekly_reflection_id または user_purpose_id のどちらかは必須です"
  end

  test "新しい分析を作成すると古い分析の is_latest が false になる" do
    first_analysis = AiAnalysis.create!(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "1回目の分析",
      is_latest:        true
    )
    assert first_analysis.is_latest, "1回目は is_latest=true のはず"

    second_analysis = AiAnalysis.create!(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "2回目の分析",
      is_latest:        true
    )

    first_analysis.reload
    assert_not first_analysis.is_latest, "1回目は is_latest=false になっているはず"
    assert second_analysis.is_latest,    "2回目は is_latest=true のはず"
  end

  test "scope latest は is_latest=true のレコードのみ返す" do
    # 【修正】
    # 2つのレコードを作ると before_create の deactivate_previous_analyses が走り
    # 1つ目の is_latest が false になってしまう。
    # そのため異なる user_purpose を使って独立したレコードを作る。

    # 2つ目の UserPurpose を作成して、別の分析として扱う
    other_purpose = UserPurpose.create!(
      user:           @user,
      purpose:        "別の Purpose",
      analysis_state: :completed
    )

    # is_latest=true のレコード（@user_purpose に対する分析）
    latest = AiAnalysis.create!(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "最新の分析",
      is_latest:        true
    )

    # is_latest=false のレコード（other_purpose に対する分析を手動で false にする）
    old_analysis = AiAnalysis.create!(
      user_purpose:     other_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "古い分析",
      is_latest:        true
    )
    # 手動で is_latest を false にする
    # update_columns: バリデーション・コールバックをスキップして直接更新する
    # ここではテスト用に強制的に false にするため意図的に使う
    old_analysis.update_columns(is_latest: false)

    latest_records = AiAnalysis.latest
    assert_includes     latest_records, latest,       "latest は scope に含まれるはず"
    assert_not_includes latest_records, old_analysis, "old_analysis は scope に含まれないはず"
  end
end