# test/models/ai_analysis_test.rb
#
# ==============================================================================
# AiAnalysis モデルテスト
# ==============================================================================
#
# 【D-9 での追加内容】
#   - input_snapshot スキーマバリデーションのテストを追加
#   - valid_input_snapshot ヘルパーメソッドを追加（ファイル末尾の private セクション）
#
# 【テスト設計の方針】
#   - フィクスチャ（yml ファイル）には依存せず create! でデータを作る
#     【理由】フィクスチャの有無に関わらずテストが動作するようにするため
#   - weekly_reflection も create! で作る
#     【理由】weekly_reflections(:one) フィクスチャの存在が保証できないため
#   - input_snapshot のバリデーションは「キーの存在」のみチェック
#     【理由】値の nil・空文字は UserPurpose の allow_blank: true 設計に従い許容する
#
# ==============================================================================

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

  # ============================================================
  # 既存テスト（D-9 バリデーション追加後も全て通過することを確認）
  # ============================================================

  test "必須フィールドが揃っている場合は有効である" do
    # 【D-9 との関係】
    #   input_snapshot を渡していないが、nil の場合はスキップする設計のため
    #   このテストは D-9 追加後も引き続き通過する。
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
    ai_analysis = AiAnalysis.new(
      user_purpose:     @user_purpose,
      analysis_comment: "テスト"
    )
    ai_analysis.write_attribute(:analysis_type, nil)

    assert_not ai_analysis.valid?,  "analysis_type が nil の場合は無効であるはず"
    assert ai_analysis.errors[:analysis_type].any?, "analysis_type のエラーが存在するはず"
  end

  test "user_purpose_id と weekly_reflection_id が両方 nil の場合は無効である" do
    ai_analysis = AiAnalysis.new(
      analysis_type:    :purpose_breakdown,
      analysis_comment: "テスト"
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
    other_purpose = UserPurpose.create!(
      user:           @user,
      purpose:        "別の Purpose",
      analysis_state: :completed
    )

    latest = AiAnalysis.create!(
      user_purpose:     @user_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "最新の分析",
      is_latest:        true
    )

    old_analysis = AiAnalysis.create!(
      user_purpose:     other_purpose,
      analysis_type:    :purpose_breakdown,
      analysis_comment: "古い分析",
      is_latest:        true
    )
    old_analysis.update_columns(is_latest: false)

    latest_records = AiAnalysis.latest
    assert_includes     latest_records, latest,       "latest は scope に含まれるはず"
    assert_not_includes latest_records, old_analysis, "old_analysis は scope に含まれないはず"
  end

  # ============================================================
  # D-9 追加テスト: input_snapshot スキーマバリデーション
  # ============================================================

  # ----------------------------------------------------------
  # 正常系テスト
  # ----------------------------------------------------------

  test "D-9: 全5キーが揃った input_snapshot は有効である" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot,
      is_latest:      true
    )

    assert ai_analysis.valid?,
           "全5キーが揃っている場合は有効のはず。エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: input_snapshot が nil の場合はバリデーションをスキップして有効になる" do
    # 【nil をスキップする設計の理由】
    #   実運用では build_input_snapshot が必ず Hash を返すため nil にならない。
    #   テストの利便性のためスキップ設計にし、ジョブ側の事前チェックで保護する。
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: nil,
      is_latest:      true
    )

    assert ai_analysis.valid?,
           "input_snapshot が nil の場合はスキップされて有効になるはず。エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: purpose の値が nil でもキーが存在すればバリデーションを通過する" do
    # 【このテストの目的】
    #   キーは存在するが値が nil の場合はバリデーションを通過することを確認する。
    #   UserPurpose の各フィールドは allow_blank: true の設計のため、
    #   未入力の場合に nil が保存される。build_input_snapshot はその nil を
    #   そのまま input_snapshot に含めるため、nil 値はバリデーションエラーにしない。
    #   nil 値の表示制御は 18番画面の View 側（.presence || "未入力"）で行う。
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.merge("purpose" => nil),
      is_latest:      true
    )

    assert ai_analysis.valid?,
           "キーが存在すれば値が nil でも有効のはず。エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: シンボルキーの input_snapshot でも正常にバリデーションが通過する" do
    # 【このテストの目的】
    #   build_input_snapshot はシンボルキー（:purpose 等）で Hash を作るが、
    #   with_indifferent_access により文字列・シンボル両方のキー形式に対応できることを確認する。
    snapshot_with_symbol_keys = {
      purpose:           "テストPurpose",
      mission:           "テストMission",
      vision:            "テストVision",
      value:             "テストValue",
      current_situation: "テストCurrent",
      version:           1,
      analyzed_at:       Time.current.iso8601
    }

    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: snapshot_with_symbol_keys,
      is_latest:      true
    )

    assert ai_analysis.valid?,
           "シンボルキーでも有効のはず。エラー: #{ai_analysis.errors.full_messages}"
  end

  test "D-9: weekly_reflection 分析の場合は input_snapshot のPMVVキーチェックをスキップする" do
    # 【weekly_reflections(:one) を使わない理由】
    #   フィクスチャの存在が保証できないため create! でデータを作成する。
    weekly_reflection = WeeklyReflection.create!(
      user:            @user,
      week_start_date: Date.current.beginning_of_week,
      week_end_date:   Date.current.end_of_week,
      year:            Date.current.year,
      week_number:     Date.current.cweek
    )

    reflection_snapshot = {
      "weekly_reflection_id" => weekly_reflection.id,
      "direct_reason"        => "仕事が忙しかった",
      "analyzed_at"          => Time.current.iso8601
      # purpose / mission / vision / value / current_situation は含まない
    }

    ai_analysis = AiAnalysis.new(
      weekly_reflection: weekly_reflection,
      analysis_type:     :weekly_reflection,
      input_snapshot:    reflection_snapshot,
      is_latest:         true
    )

    assert ai_analysis.valid?,
           "weekly_reflection 分析の場合はスキップされるはず。エラー: #{ai_analysis.errors.full_messages}"
  end

  # ----------------------------------------------------------
  # 異常系テスト: 各キー欠落パターン
  # ----------------------------------------------------------

  test "D-9: purpose キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("purpose"),
      is_latest:      true
    )

    assert_not ai_analysis.valid?,      "purpose が欠落した場合は無効のはず"
    assert ai_analysis.errors[:input_snapshot].any?, "input_snapshot にエラーが存在するはず"
    assert_match "purpose", ai_analysis.errors[:input_snapshot].first,
                 "エラーメッセージに 'purpose' が含まれるはず"
  end

  test "D-9: mission キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("mission"),
      is_latest:      true
    )

    assert_not ai_analysis.valid?, "mission が欠落した場合は無効のはず"
    assert_match "mission", ai_analysis.errors[:input_snapshot].first,
                 "エラーメッセージに 'mission' が含まれるはず"
  end

  test "D-9: vision キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("vision"),
      is_latest:      true
    )

    assert_not ai_analysis.valid?, "vision が欠落した場合は無効のはず"
    assert_match "vision", ai_analysis.errors[:input_snapshot].first,
                 "エラーメッセージに 'vision' が含まれるはず"
  end

  test "D-9: value キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("value"),
      is_latest:      true
    )

    assert_not ai_analysis.valid?, "value が欠落した場合は無効のはず"
    assert_match "value", ai_analysis.errors[:input_snapshot].first,
                 "エラーメッセージに 'value' が含まれるはず"
  end

  test "D-9: current_situation キーが欠落した input_snapshot はバリデーションエラーになる" do
    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: valid_input_snapshot.except("current_situation"),
      is_latest:      true
    )

    assert_not ai_analysis.valid?, "current_situation が欠落した場合は無効のはず"
    assert_match "current_situation", ai_analysis.errors[:input_snapshot].first,
                 "エラーメッセージに 'current_situation' が含まれるはず"
  end

  test "D-9: 5キー全て欠落した場合は全キーがエラーメッセージに含まれる" do
    snapshot_without_pmvv_keys = {
      "version"     => 1,
      "analyzed_at" => Time.current.iso8601
      # purpose / mission / vision / value / current_situation が全て欠落
    }

    ai_analysis = AiAnalysis.new(
      user_purpose:   @user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: snapshot_without_pmvv_keys,
      is_latest:      true
    )

    assert_not ai_analysis.valid?, "全5キー欠落の場合は無効のはず"

    error_message = ai_analysis.errors[:input_snapshot].first

    %w[purpose mission vision value current_situation].each do |key|
      assert_match key, error_message,
                   "エラーメッセージに '#{key}' が含まれるはず。実際: #{error_message}"
    end
  end

  # ============================================================
  # プライベートヘルパーメソッド
  # ============================================================
  # 【private をファイル末尾に置く理由】
  #   Minitest の test ブロックは public メソッドとして扱われる。
  #   private 宣言をここに置くことで、その前の test ブロックが
  #   誤って private になることを防ぐ。
  private

  # 全5キーが揃った正常な input_snapshot を返すヘルパー
  # 【文字列キーにする理由】
  #   DB から読み出した jsonb は文字列キーになるため、
  #   本番環境に近い形でテストできる。
  # 【使い方】
  #   valid_input_snapshot.except("purpose")  → purpose キーを除いた Hash
  #   valid_input_snapshot.merge("purpose" => nil) → purpose の値を nil にした Hash
  def valid_input_snapshot
    {
      "purpose"           => "テストPurpose",
      "mission"           => "テストMission",
      "vision"            => "テストVision",
      "value"             => "テストValue",
      "current_situation" => "テストCurrent",
      "version"           => 1,
      "analyzed_at"       => Time.current.iso8601
    }
  end
end