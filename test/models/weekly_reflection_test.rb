# frozen_string_literal: true

# ==============================================================================
# WeeklyReflectionモデルテスト
#
# 【テストの方針】
# 1. バリデーション（正常系・異常系）
# 2. アソシエーション
# 3. スコープ
# 4. クラスメソッド（AM4:00境界値含む）
# 5. インスタンスメソッド
# 6. UNIQUE制約
# 7. カスタムバリデーション（週範囲）
#
# 【テスト実行コマンド】
# docker compose exec web bin/rails test test/models/weekly_reflection_test.rb
# ==============================================================================
require 'test_helper'

class WeeklyReflectionTest < ActiveSupport::TestCase
  # --------------------------------------------------------------------------
  # travel_to メソッドを使うために必要なモジュールをincludeする。
  #
  # 【travel_toとは】
  # テスト内でシステム時刻を任意の日時に固定するメソッド。
  # AM4:00境界値テストで「特定の時間に固定して動作を確認する」ために使う。
  #
  # 【なぜincludeが必要か】
  # travel_to は ActiveSupport::Testing::TimeHelpers に定義されており、
  # このモジュールをincludeしないと NoMethodError が発生する。
  # --------------------------------------------------------------------------
  include ActiveSupport::Testing::TimeHelpers

  # ============================================================================
  # setupメソッド
  # 各テストの前に実行される準備処理。
  # ============================================================================
  setup do
    @user       = users(:one)
    @other_user = users(:two)
    @start_date = Date.new(2026, 2, 16) # 月曜日
    @end_date   = Date.new(2026, 2, 22) # 日曜日

    # フィクスチャとの衝突を防ぐため、テスト開始前に今週分のレコードを削除する
    WeeklyReflection.where(user: @user, week_start_date: @start_date).destroy_all
  end

  # ============================================================================
  # バリデーションテスト（正常系）
  # ============================================================================

  test '正常なデータで保存できること' do
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )
    assert reflection.valid?, "バリデーションエラー: #{reflection.errors.full_messages}"
  end

  test 'reflection_commentが空でも保存できること' do
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )
    assert reflection.valid?
  end

  test 'reflection_commentが1000文字で保存できること' do
    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    @start_date,
      week_end_date:      @end_date,
      reflection_comment: 'a' * 1000,
      is_locked:          false
    )
    assert reflection.valid?, "1000文字でバリデーションエラー: #{reflection.errors.full_messages}"
  end

  # ============================================================================
  # バリデーションテスト（異常系）
  # ============================================================================

  test 'week_start_dateがnilの場合はバリデーションエラーになること' do
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: nil,
      week_end_date:   @end_date,
      is_locked:       false
    )
    assert_not reflection.valid?
    assert reflection.errors.of_kind?(:week_start_date, :blank)
  end

  test 'week_end_dateがnilの場合はバリデーションエラーになること' do
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   nil,
      is_locked:       false
    )
    assert_not reflection.valid?
    assert reflection.errors.of_kind?(:week_end_date, :blank)
  end

  test 'reflection_commentが1001文字でバリデーションエラーになること' do
    reflection = WeeklyReflection.new(
      user:               @user,
      week_start_date:    @start_date,
      week_end_date:      @end_date,
      reflection_comment: 'a' * 1001,
      is_locked:          false
    )
    assert_not reflection.valid?
    assert reflection.errors.of_kind?(:reflection_comment, :too_long)
  end

  # ============================================================================
  # カスタムバリデーションテスト（週範囲の整合性）
  # ============================================================================

  test 'week_end_dateがweek_start_dateの6日後でなければバリデーションエラーになること' do
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @start_date + 5.days,
      is_locked:       false
    )
    assert_not reflection.valid?
    # of_kind? はRailsが内部で管理するエラーキー（:blank, :too_longなど）を確認するメソッド。
    # カスタムバリデーションで errors.add(:week_end_date, '文字列') と書いた場合は
    # キーが :invalid ではなく文字列そのものになるため、include? で確認する。
    assert_includes reflection.errors[:week_end_date], 'は開始日の6日後でなければなりません'
  end

  test 'week_end_dateがweek_start_dateより前でもバリデーションエラーになること' do
    reflection = WeeklyReflection.new(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @start_date - 1.day,
      is_locked:       false
    )
    assert_not reflection.valid?
    assert_includes reflection.errors[:week_end_date], 'は開始日の6日後でなければなりません'
  end

  # ============================================================================
  # UNIQUE制約テスト
  # ============================================================================

  test '同じユーザーと週の組み合わせで重複作成できないこと' do
    WeeklyReflection.create!(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )

    duplicate = WeeklyReflection.new(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:week_start_date, :taken)
  end

  test '別ユーザーなら同じ週でも作成できること' do
    WeeklyReflection.create!(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )

    other_reflection = WeeklyReflection.new(
      user:            @other_user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )
    assert other_reflection.valid?
  end

  # ============================================================================
  # アソシエーションテスト
  # ============================================================================

  test 'Userに紐づいていること' do
    reflection = WeeklyReflection.create!(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )
    assert_equal @user, reflection.user
  end

  test 'Userを削除したとき振り返りも削除されること' do
    test_user = User.create!(
      name:                  'テスト用ユーザー',
      email:                 "test_cascade_#{SecureRandom.hex(4)}@example.com",
      password:              'password123',
      password_confirmation: 'password123'
    )
    WeeklyReflection.create!(
      user:            test_user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )

    user_id = test_user.id
    test_user.destroy

    assert_equal 0, WeeklyReflection.where(user_id: user_id).count
  end

  # ============================================================================
  # スコープテスト
  # ============================================================================

  test 'completedスコープが完了済みレコードを返すこと' do
    completed = WeeklyReflection.create!(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       true
    )
    assert_includes WeeklyReflection.completed, completed
  end

  test 'pendingスコープが未完了レコードを返すこと' do
    pending_reflection = WeeklyReflection.create!(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )
    assert_includes     WeeklyReflection.pending,    pending_reflection
    assert_not_includes WeeklyReflection.completed,  pending_reflection
  end

  # ============================================================================
  # クラスメソッドテスト（AM4:00境界値）
  # ============================================================================

  test 'AM4:00以降は当日の週の月曜日を返すこと' do
    # 月曜AM4:00ちょうど → 今週扱い → 今週の月曜日を返す
    travel_to Time.zone.local(2026, 2, 16, 4, 0, 0) do
      assert_equal Date.new(2026, 2, 16), WeeklyReflection.current_week_start_date
    end
  end

  test 'AM4:00前は前週の月曜日を返すこと' do
    # 月曜AM3:59 → まだ日曜扱い → 先週の月曜日を返す
    travel_to Time.zone.local(2026, 2, 16, 3, 59, 0) do
      assert_equal Date.new(2026, 2, 9), WeeklyReflection.current_week_start_date
    end
  end

  test 'week_start_date_forが正しい月曜日を返すこと' do
    wednesday = Date.new(2026, 2, 18)
    assert_equal Date.new(2026, 2, 16), WeeklyReflection.week_start_date_for(wednesday)
  end

  test 'find_or_build_for_current_weekが既存レコードを返すこと' do
    travel_to Time.zone.local(2026, 2, 18, 12, 0, 0) do
      existing = WeeklyReflection.create!(
        user:            @user,
        week_start_date: Date.new(2026, 2, 16),
        week_end_date:   Date.new(2026, 2, 22),
        is_locked:       false
      )
      result = WeeklyReflection.find_or_build_for_current_week(@user)
      assert_equal existing.id, result.id
      assert result.persisted?
    end
  end

  test 'find_or_build_for_current_weekが新規インスタンスを返すこと' do
    travel_to Time.zone.local(2026, 2, 18, 12, 0, 0) do
      result = WeeklyReflection.find_or_build_for_current_week(@user)
      assert_not result.persisted?
      assert_equal Date.new(2026, 2, 16), result.week_start_date
      assert_equal Date.new(2026, 2, 22), result.week_end_date
    end
  end

  # ============================================================================
  # インスタンスメソッドテスト
  # ============================================================================

  test 'complete!でis_lockedがtrueになること' do
    reflection = WeeklyReflection.create!(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       false
    )
    reflection.complete!
    assert reflection.reload.is_locked
  end

  test 'completed?が完了状態を正しく返すこと' do
    reflection = WeeklyReflection.create!(
      user:            @user,
      week_start_date: @start_date,
      week_end_date:   @end_date,
      is_locked:       true
    )
    assert     reflection.completed?
    assert_not reflection.pending?
  end

  test 'week_labelが正しいフォーマットを返すこと' do
    reflection = WeeklyReflection.new(
      week_start_date: Date.new(2026, 2, 16),
      week_end_date:   Date.new(2026, 2, 22)
    )
    assert_equal '2026/02/16 - 02/22', reflection.week_label
  end

  # test/models/weekly_reflection_test.rb
  # ※ 既存ファイルに以下のテストを追記してください
  # （ファイル末尾の end の前に追加）

  # ===========================================================
  # Issue #21 で追加: can_create_reflection? に関連するロジックのテスト
  # ===========================================================

  # 日曜日の AM4:00 以降であることを確認するテスト
  # wday メソッドが正しく日曜を判定できるか確認します
  test "日曜日の AM4:00 以降は wday が 0 を返すこと" do
    # travel_to は指定した日時にシステム時刻を固定するメソッドです
    # 2026/02/22（日曜日）の AM5:00 に固定します
    travel_to Time.zone.local(2026, 2, 22, 5, 0, 0) do
      today = HabitRecord.today_for_record
      assert_equal 0, today.wday, "日曜日は wday が 0 であること"
    end
  end

  test "土曜日は wday が 6 を返すこと" do
    # 2026/02/21（土曜日）の AM10:00 に固定します
    travel_to Time.zone.local(2026, 2, 21, 10, 0, 0) do
      today = HabitRecord.today_for_record
      assert_equal 6, today.wday, "土曜日は wday が 6 であること"
    end
  end
end