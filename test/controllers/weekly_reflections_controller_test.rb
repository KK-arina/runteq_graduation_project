# test/controllers/weekly_reflections_controller_test.rb
#
# WeeklyReflectionsController のテスト
# Issue #21: index アクションのテスト
#
# ================================================================
# 【設計方針】テストデータに固定日付を使わない理由
# ================================================================
# ❌ 悪い例: Date.new(2025, 12, 1) のような固定日付
#   - fixtures のデータと衝突する可能性がある
#   - 将来 fixtures が増えたとき再び壊れる
#   - なぜその日付なのかコードを読んでも分からない
#
# ✅ 良い例: travel_to + WeeklyReflection.current_week_start_date
#   - アプリの週計算ロジックそのものを使うため、ロジック変更に自動追従する
#   - fixtures と絶対に衝突しない（未来・過去の固定時刻を使うため）
#   - 「この時刻にいる状態」が明確で、コードの意図が読みやすい
# ================================================================

require "test_helper"

class WeeklyReflectionsControllerTest < ActionDispatch::IntegrationTest
  # ================================================================
  # ActiveSupport::Testing::TimeHelpers を include する理由:
  # travel_to メソッドを使えるようにするためです。
  # ActionDispatch::IntegrationTest は自動で include していますが、
  # 明示的に書くことで「このテストは時刻操作を使う」という意図を示します。
  # ================================================================
  include ActiveSupport::Testing::TimeHelpers

  setup do
    # fixtures(:users) はテスト用の固定データを参照します
    # test/fixtures/users.yml に定義された one ユーザーを使います
    @user = users(:one)
  end

  # ===========================================================
  # 未ログイン時のテスト
  # ===========================================================
  test "未ログイン時は一覧ページにアクセスできないこと" do
    get weekly_reflections_path
    # require_login の動作確認: ログインページへリダイレクトされる
    assert_redirected_to login_path
  end

  # ===========================================================
  # ログイン済み時の基本表示テスト
  # ===========================================================
  test "ログイン済みで一覧ページが表示されること" do
    log_in_as(@user)
    get weekly_reflections_path
    assert_response :success
  end

  test "ページに「週次振り返り」タイトルが含まれること" do
    log_in_as(@user)
    get weekly_reflections_path
    assert_select "h1", text: /週次振り返り/
  end

  # ===========================================================
  # 過去の振り返りデータ表示テスト
  # ================================================================
  # travel_to を使う理由:
  # WeeklyReflection.current_week_start_date は「現在時刻」を元に
  # 今週の月曜日を計算します。
  # travel_to で時刻を固定することで:
  # 1. 何度テストを実行しても同じ週が返ってくる（再現性）
  # 2. fixtures の今週データと衝突しない過去の週を確実に指定できる
  # 3. 「アプリのロジックで計算した月曜日」を使うため曜日計算ミスがない
  # ================================================================
  test "過去の振り返りが表示されること" do
    log_in_as(@user)

    # 2025/12/03（水曜日）に時刻を固定します。
    # fixtures の現在週データと重複しない、明らかに過去の時刻を選んでいます。
    # current_week_start_date が「その週の月曜日(2025/12/01)」を返すことを利用します。
    travel_to Time.zone.local(2025, 12, 3, 10, 0, 0) do
      # アプリの週計算ロジックで今週の月曜日を取得します
      # Date.new(2025, 12, 1) と直書きしないことで、
      # ロジックが変わっても自動追従できます
      week_start = WeeklyReflection.current_week_start_date

      reflection = WeeklyReflection.create!(
        user:               @user,
        week_start_date:    week_start,
        week_end_date:      week_start + 6.days,
        reflection_comment: "テスト振り返りコメント",
        is_locked:          true
      )

      get weekly_reflections_path
      assert_select "body", text: /テスト振り返りコメント/
    end
  end

  test "他ユーザーの振り返りは表示されないこと" do
    log_in_as(@user)

    other_user = users(:two)

    # 同様に travel_to + current_week_start_date でデータを作成します
    travel_to Time.zone.local(2025, 12, 3, 10, 0, 0) do
      week_start = WeeklyReflection.current_week_start_date

      other_reflection = WeeklyReflection.create!(
        user:            other_user,
        week_start_date: week_start,
        week_end_date:   week_start + 6.days,
        is_locked:       true
      )

      get weekly_reflections_path
      assert_response :success

      # 他ユーザーの振り返り詳細ページへのリンクが存在しないことを確認します
      # これによりデータ隔離（自分のデータのみ表示）が正しく動作しているか検証します
      refute_match %r{/weekly_reflections/#{other_reflection.id}},
                   response.body
    end
  end

  # ===========================================================
  # 日曜日 AM4:00 判定テスト
  # ================================================================
  # すべて travel_to で「テストがどの時刻で動いているか」を明示します。
  # Time.zone.local を使う理由:
  #   Time.new だとサーバーのローカルタイムゾーンになりますが、
  #   Time.zone.local は Rails の config.time_zone（Asia/Tokyo など）に
  #   従った時刻を生成するため、本番環境と同じ条件でテストできます。
  # ================================================================
  test "日曜AM4:00ちょうどは振り返り作成ボタンが表示されること" do
    log_in_as(@user)

    # 2026/02/22 は日曜日。AM4:00 ちょうどが境界値（>=で判定しているため含まれる）
    travel_to Time.zone.local(2026, 2, 22, 4, 0, 0) do
      get weekly_reflections_path
      assert_response :success
      assert_select "a[href='#{new_weekly_reflection_path}']"
    end
  end

  test "日曜AM3:59は振り返り作成ボタンが表示されないこと" do
    log_in_as(@user)

    # AM4:00 の1分前。is_after_4am が false になることを確認する境界値テスト
    travel_to Time.zone.local(2026, 2, 22, 3, 59, 0) do
      get weekly_reflections_path
      assert_response :success
      assert_select "a[href='#{new_weekly_reflection_path}']", count: 0
    end
  end

  test "日曜AM5:00は振り返り作成ボタンが表示されること" do
    log_in_as(@user)

    travel_to Time.zone.local(2026, 2, 22, 5, 0, 0) do
      get weekly_reflections_path
      assert_response :success
      assert_select "a[href='#{new_weekly_reflection_path}']"
    end
  end

  test "平日（月曜AM10:00）は振り返り作成ボタンが表示されないこと" do
    log_in_as(@user)

    travel_to Time.zone.local(2026, 2, 16, 10, 0, 0) do
      get weekly_reflections_path
      assert_response :success
      assert_select "a[href='#{new_weekly_reflection_path}']", count: 0
    end
  end
end