# test/jobs/monthly_ai_count_reset_job_test.rb
#
# ==============================================================================
# MonthlyAiCountResetJob のテスト（G-8: AI分析カウント月次リセットバッチ）
# ==============================================================================
#
# 【このテストファイルの役割】
#   毎月1日 JST 00:00 に ai_analysis_count を 0 にリセットするジョブが
#   正しく動作することを確認する。
#
# 【テスト設計の方針】
#   ① 月初（1日）のとき: 全ユーザーの ai_analysis_count が 0 になること
#   ② 月初以外のとき: ai_analysis_count が変化しないこと（スキップされること）
#   ③ 月末（31日）でも変化しないこと（境界値テスト）
#   ④ 正常終了すること（例外が発生しないこと）
#   ⑤ GoodJob cron に正しく登録されていること
#   ⑥ 全件 maximum が 0 になること（確実な全員リセット確認）
#
# 【ActiveJob::TestCase を継承する理由】
#   GoodJob ジョブのテストは ActiveJob::TestCase を継承することで
#   perform_now（同期実行）が使えるようになる。
#   perform_now: キューに積まずにジョブを即時実行するテスト用メソッド。
#
# 【fixture を使わず User.create! する理由】
#   fixtures(:all) で読み込まれる既存データと ai_analysis_count の値が
#   干渉しないようにするため。
#   独立したテスト用ユーザーを作ることで、他のテストの影響を受けない
#   「安全・安定」なテスト環境を作る。
#
# 【teardown で destroy しない理由（他の方レビュー指摘）】
#   Rails のテストはデフォルトで use_transactional_tests = true が有効。
#   各テストをトランザクションで囲み、テスト終了後に自動ロールバックするため、
#   手動 destroy は不要。むしろ dependent: :destroy の連鎖で
#   テストが遅くなるリスクがある。
# ==============================================================================
require "test_helper"

class MonthlyAiCountResetJobTest < ActiveJob::TestCase

  # ============================================================
  # セットアップ
  # ============================================================
  setup do
    # ----------------------------------------------------------
    # テスト用ユーザー 1: AI分析を10回使い切ったユーザー（上限到達）
    # ----------------------------------------------------------
    #
    # 【SecureRandom.hex(4) を使う理由】
    #   テストを複数回実行したときにメールアドレスが重複してエラーにならないよう
    #   "g8_test_1_XXXXXXXX@example.com" という形でユニークなアドレスを生成する。
    @user_1 = User.create!(
      name:                  "G8テストユーザー1",
      email:                 "g8_test_1_#{SecureRandom.hex(4)}@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    # User.create! 後に after_create :create_user_setting が実行され
    # UserSetting が自動生成される（D-4 の設計に基づく）。
    # update! で ai_analysis_count を上限まで設定する。
    @user_setting_1 = @user_1.user_setting
    @user_setting_1.update!(
      ai_analysis_count:         10, # 上限に達した状態
      ai_analysis_monthly_limit: 10  # 月間上限 10 回
    )

    # ----------------------------------------------------------
    # テスト用ユーザー 2: AI分析を5回使ったユーザー（途中）
    # ----------------------------------------------------------
    @user_2 = User.create!(
      name:                  "G8テストユーザー2",
      email:                 "g8_test_2_#{SecureRandom.hex(4)}@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    @user_setting_2 = @user_2.user_setting
    @user_setting_2.update!(
      ai_analysis_count:         5, # 途中まで使った状態
      ai_analysis_monthly_limit: 10
    )

    # ----------------------------------------------------------
    # テスト用ユーザー 3: まだ使っていないユーザー（count = 0）
    # ----------------------------------------------------------
    #
    # 【count = 0 のユーザーも含める理由】
    #   update_all が「0 → 0」の更新でもエラーなく動くことを確認するため。
    @user_3 = User.create!(
      name:                  "G8テストユーザー3",
      email:                 "g8_test_3_#{SecureRandom.hex(4)}@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    @user_setting_3 = @user_3.user_setting
    @user_setting_3.update!(
      ai_analysis_count:         0, # まだ使っていない状態（デフォルト値と同じだが明示）
      ai_analysis_monthly_limit: 10
    )

    # ----------------------------------------------------------
    # setup で作成した3ユーザーの id を記録しておく
    # ----------------------------------------------------------
    #
    # 【なぜ id を記録するのか】
    #   テスト 6 で「このテストで作ったユーザーだけに絞り込んで maximum を確認」するため。
    #   fixtures(:all) で読み込まれる他のユーザーの ai_analysis_count が
    #   0 以外だった場合に誤検知しないようにする。
    @test_user_setting_ids = [
      @user_setting_1.id,
      @user_setting_2.id,
      @user_setting_3.id
    ]
  end

  # ============================================================
  # テスト 1: 月初（1日）のとき ai_analysis_count が 0 にリセットされる
  # ============================================================
  #
  # 【travel_to を使う理由】
  #   Time.current の値をテスト内で固定する Rails の組み込みヘルパー。
  #   ジョブ内の「today.day == 1」チェックを通過させるために
  #   「月初の日時」をシミュレートする。
  #
  # 【Time.zone.local(2026, 7, 1, 0, 0, 0) の意味】
  #   2026年7月1日 00:00:00 JST を作成する。
  #   Time.local ではなく Time.zone.local を使う理由:
  #   Rails の config.time_zone = "Tokyo" に基づいてタイムゾーンを解釈するため。
  test "月初（1日）のとき: 全ユーザーの ai_analysis_count が 0 にリセットされる" do
    travel_to Time.zone.local(2026, 7, 1, 0, 0, 0) do
      MonthlyAiCountResetJob.perform_now

      # 【reload が必要な理由（初心者最頻出ハマりポイント）】
      #   update_all は SQL を直接発行するため、Ruby オブジェクトの
      #   インスタンス変数は古い値のまま。
      #   reload で DB の最新値を強制的に取得する。
      @user_setting_1.reload
      @user_setting_2.reload
      @user_setting_3.reload

      assert_equal 0, @user_setting_1.ai_analysis_count,
                   "上限に達していたユーザー1の ai_analysis_count が 0 になるべきです"
      assert_equal 0, @user_setting_2.ai_analysis_count,
                   "途中まで使っていたユーザー2の ai_analysis_count が 0 になるべきです"
      assert_equal 0, @user_setting_3.ai_analysis_count,
                   "まだ使っていないユーザー3の ai_analysis_count は 0 のままであるべきです"
    end
  end

  # ============================================================
  # テスト 2: 月初以外のとき ai_analysis_count が変化しない
  # ============================================================
  #
  # 【このテストが重要な理由】
  #   ジョブは毎日 JST 00:00 に実行される（cron: "0 15 * * *"）。
  #   月初（1日）以外の日は何もしないことを確認する。
  #   もし「today.day == 1」の条件が壊れると、毎日リセットされてしまう。
  test "月初以外（15日）のとき: ai_analysis_count が変化しない" do
    travel_to Time.zone.local(2026, 7, 15, 0, 0, 0) do
      MonthlyAiCountResetJob.perform_now

      @user_setting_1.reload
      @user_setting_2.reload

      assert_equal 10, @user_setting_1.ai_analysis_count,
                   "月初以外のとき ユーザー1の ai_analysis_count は変化しないべきです"
      assert_equal 5, @user_setting_2.ai_analysis_count,
                   "月初以外のとき ユーザー2の ai_analysis_count は変化しないべきです"
    end
  end

  # ============================================================
  # テスト 3: 月末（31日）のとき ai_analysis_count が変化しない（境界値テスト）
  # ============================================================
  #
  # 【境界値テスト】
  #   「1日以外はスキップ」の条件が月末でも正しく機能することを検証する。
  test "月末（31日）のとき: ai_analysis_count が変化しない" do
    travel_to Time.zone.local(2026, 7, 31, 0, 0, 0) do
      MonthlyAiCountResetJob.perform_now

      @user_setting_1.reload

      assert_equal 10, @user_setting_1.ai_analysis_count,
                   "月末のとき ai_analysis_count は変化しないべきです"
    end
  end

  # ============================================================
  # テスト 4: 月初の実行で例外なく正常完了する
  # ============================================================
  #
  # 【assert_nothing_raised を使う理由】
  #   ジョブの実行中に予期しない例外が発生しないことを確認する。
  #   例外が発生すると GoodJob はジョブを failed 状態にしてリトライする。
  #
  # 【assert_nothing_raised の注意点（他の方レビュー指摘）】
  #   Rails バージョンによっては存在しない場合があるが、
  #   Rails 7.x では ActiveSupport::Testing::Assertions に含まれており使用可能。
  #   問題が発生する場合は「perform_now して assert true」で代替できる。
  test "月初の実行で例外なく正常完了する" do
    travel_to Time.zone.local(2026, 8, 1, 0, 0, 0) do
      assert_nothing_raised do
        MonthlyAiCountResetJob.perform_now
      end
    end
  end

  # ============================================================
  # テスト 5: GoodJob cron に月次リセットジョブが登録されている
  # ============================================================
  #
  # 【このテストの重要性】
  #   good_job.rb の cron 設定に monthly_ai_count_reset が
  #   正しく登録されていることを確認する。
  #   設定漏れがあると本番でジョブが自動実行されない。
  #
  # 【to_s でキーを比較する理由（他の方レビュー指摘）】
  #   GoodJob の設定は環境によってキーが Symbol の場合と String の場合がある。
  #   .key?(:monthly_ai_count_reset) だけだと String キーの場合に false になる。
  #   .keys.map(&:to_s) で文字列に統一してから include? で比較することで
  #   Symbol/String どちらでも確実に検出できる。
  test "GoodJob cron に monthly_ai_count_reset が登録されている" do
    cron_config = Rails.application.config.good_job.cron

    assert_not_nil cron_config,
                   "GoodJob の cron 設定が存在しません（good_job.rb を確認してください）"

    # Symbol と String の両方に対応するため to_s で文字列に統一して比較する
    cron_keys_as_strings = cron_config.keys.map(&:to_s)

    assert_includes cron_keys_as_strings,
                    "monthly_ai_count_reset",
                    "cron に monthly_ai_count_reset が登録されていません（good_job.rb を確認してください）"

    # キーを Symbol / String どちらでも取れるよう両方試みる
    # 【transform_keys(&:to_sym) を使う理由】
    #   キーを全て Symbol に統一してから取得することで、
    #   Symbol/String どちらのキー形式でも安全にアクセスできる。
    normalized_config = cron_config.transform_keys(&:to_sym)
    monthly_reset_setting = normalized_config[:monthly_ai_count_reset]

    assert_equal "MonthlyAiCountResetJob",
                 monthly_reset_setting[:class],
                 "monthly_ai_count_reset の class が MonthlyAiCountResetJob ではありません"
  end

  # ============================================================
  # テスト 6: 全件 maximum が 0 になること（確実な全員リセット確認）
  # ============================================================
  #
  # 【このテストを追加する理由（他の方レビュー指摘）】
  #   テスト 1 では個別の @user_setting を reload して確認している。
  #   しかし update_all が「一部のレコードだけ更新する」バグがあった場合に
  #   テスト 1 だけでは検出できない可能性がある。
  #   「テストで作ったユーザー設定の中で最大値が 0」を確認することで
  #   全員確実にリセットされたことを SQL レベルで保証する。
  #
  # 【UserSetting.where(id: @test_user_setting_ids) で絞り込む理由】
  #   fixtures(:all) で読み込まれる他のユーザーの ai_analysis_count が
  #   0 以外の場合に誤検知しないよう、このテストで作った設定 ID に絞り込む。
  test "月初実行後: テスト対象ユーザー全員の maximum が 0 になること" do
    travel_to Time.zone.local(2026, 7, 1, 0, 0, 0) do
      MonthlyAiCountResetJob.perform_now

      # テストで作ったユーザー設定だけを対象に maximum を確認する
      max_count = UserSetting
                    .where(id: @test_user_setting_ids)
                    .maximum(:ai_analysis_count)

      assert_equal 0, max_count,
                   "月次リセット後: テスト対象の全 UserSetting の ai_analysis_count の最大値が 0 であるべきです"
    end
  end

  # ============================================================
  # テスト 7: リセット後に 14-B モーダルが表示されない状態になる（間接確認）
  # ============================================================
  #
  # 【このテストの目的】
  #   月次リセット後に ai_analysis_count が 0 になるため、
  #   14-B（AI上限エラーモーダル）の表示条件が解消されることを確認する。
  #
  #   コントローラーでは「ai_analysis_count >= ai_analysis_monthly_limit」のとき
  #   14-B モーダルを表示する設計になっている。
  #   リセット後は count=0 < limit=10 になるため、モーダルが出なくなる。
  test "月次リセット後: ai_analysis_count が monthly_limit 未満になり 14-B モーダルが表示されなくなる" do
    # リセット前: 上限に達しているため 14-B モーダルが表示される状態
    assert @user_setting_1.ai_analysis_count >= @user_setting_1.ai_analysis_monthly_limit,
           "テスト前提: ユーザー1は上限に達しているべきです"

    travel_to Time.zone.local(2026, 9, 1, 0, 0, 0) do
      MonthlyAiCountResetJob.perform_now
    end

    @user_setting_1.reload

    # リセット後: count < limit になり、14-B モーダルは表示されない状態になる
    assert @user_setting_1.ai_analysis_count < @user_setting_1.ai_analysis_monthly_limit,
           "月次リセット後: ai_analysis_count が monthly_limit より小さくなるべきです（14-B モーダルが消える）"

    assert_equal 0, @user_setting_1.ai_analysis_count,
                 "月次リセット後: ai_analysis_count が 0 になるべきです"
  end
end