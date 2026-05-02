# test/models/concerns/crisis_detector_test.rb
#
# ==============================================================================
# CrisisDetector モジュールのテスト
# ==============================================================================
#
# 【フィクスチャを使わない設計にした理由】
#   weekly_reflections.yml に `:one` というキーが存在しないため、
#   WeeklyReflection.new でオブジェクトを直接生成する方式に変更する。
#   フィクスチャの構成に依存しないため、将来フィクスチャが変わっても壊れない。
#
# 【setup で共通オブジェクトを準備する理由】
#   各テストで同じ初期化処理を繰り返さないため。
#   users(:one) は users.yml に `one:` エントリが存在するため使用可能。
#
# 【WeeklyReflection.new で必要な最低限の属性】
#   user:            belongs_to :user のため必須
#   week_start_date: 月曜日の日付（before_validation で year/week_number を計算するため）
#   week_end_date:   week_start_date + 6日（バリデーションで必須）
# ==============================================================================

require "test_helper"

class CrisisDetectorTest < ActiveSupport::TestCase
  # ============================================================
  # setup: 各テストメソッドの実行前に自動で呼ばれる共通初期化
  # ============================================================
  setup do
    # users.yml の `one:` エントリを使う（存在確認済み）
    @user = users(:one)

    # WeeklyReflection をフィクスチャ非依存で直接生成する。
    # week_start_date は月曜日（2026-04-13）を指定する。
    # week_end_date は start + 6日（バリデーション要件）。
    # テキストフィールドは各テストで個別にセットするため nil にしておく。
    @reflection = WeeklyReflection.new(
      user:                 @user,
      week_start_date:      Date.new(2026, 4, 13), # 月曜日
      week_end_date:        Date.new(2026, 4, 19), # 6日後の日曜日
      direct_reason:        nil,
      background_situation: nil,
      next_action:          nil,
      reflection_comment:   nil
    )
  end

  # ============================================================
  # WeeklyReflection での検出テスト
  # ============================================================

  test "直接的な危機ワード「死にたい」を検出できる" do
    @reflection.direct_reason = "もう死にたいと思っています"

    # valid? を呼ぶと before_validation が実行され
    # CrisisDetector#check_crisis_keywords が動く
    @reflection.valid?

    assert @reflection.crisis_word_detected?,
           "「死にたい」が含まれる場合 crisis_word_detected? は true のはず"
  end

  test "「消えたい」を検出できる" do
    @reflection.background_situation = "消えてしまいたいです"
    @reflection.valid?
    assert @reflection.crisis_word_detected?,
           "「消えたい」が含まれる場合 crisis_word_detected? は true のはず"
  end

  test "「いなくなりたい」を検出できる" do
    @reflection.reflection_comment = "もういなくなってしまいたい"
    @reflection.valid?
    assert @reflection.crisis_word_detected?,
           "「いなくなりたい」が含まれる場合 crisis_word_detected? は true のはず"
  end

  test "「next_action」フィールドでも検出できる" do
    @reflection.next_action = "死ぬしかないと思っています"
    @reflection.valid?
    assert @reflection.crisis_word_detected?,
           "next_action フィールドでも危機ワードを検出できるはず"
  end

  test "通常の落ち込み表現「つらい」は検出しない" do
    @reflection.direct_reason = "今週はとてもつらかったです"
    @reflection.valid?
    assert_not @reflection.crisis_word_detected?,
               "「つらい」だけでは検出しないはず"
  end

  test "「疲れた」は検出しない" do
    @reflection.reflection_comment = "今週は本当に疲れました"
    @reflection.valid?
    assert_not @reflection.crisis_word_detected?,
               "「疲れた」だけでは検出しないはず"
  end

  test "「終わりにしたい」は検出する（危機ワードリストにある）" do
    @reflection.direct_reason = "もう全部終わりにしたい"
    @reflection.valid?
    assert @reflection.crisis_word_detected?,
           "「終わりにしたい」は危機ワードリストにあるため検出するはず"
  end

  test "全フィールドが空の場合は検出しない" do
    # setup で全フィールドを nil にしているのでそのまま valid? を呼ぶ
    @reflection.valid?
    assert_not @reflection.crisis_word_detected?,
               "全フィールドが空の場合は検出しないはず"
  end

  # ============================================================
  # UserPurpose での検出テスト
  # ============================================================

  test "UserPurpose の current_situation で検出できる" do
    user_purpose = UserPurpose.new(
      user:              @user,
      current_situation: "毎日死にたいと思っています",
      # at_least_one_field_present バリデーションのため purpose も入れる
      purpose:           "テスト用ダミー"
    )
    user_purpose.valid?
    assert user_purpose.crisis_word_detected?,
           "current_situation の危機ワードを検出できるはず"
  end

  test "UserPurpose の vision で検出できる" do
    user_purpose = UserPurpose.new(
      user:    @user,
      vision:  "消えてしまいたいと思っています",
      purpose: "テスト用ダミー"
    )
    user_purpose.valid?
    assert user_purpose.crisis_word_detected?,
           "vision の危機ワードを検出できるはず"
  end

  test "UserPurpose の通常入力は検出しない" do
    user_purpose = UserPurpose.new(
      user:    @user,
      purpose: "家族との時間を大切にしたい",
      vision:  "毎朝6時に起きて読書できる自分になりたい"
    )
    user_purpose.valid?
    assert_not user_purpose.crisis_word_detected?,
               "通常の入力では検出しないはず"
  end
end