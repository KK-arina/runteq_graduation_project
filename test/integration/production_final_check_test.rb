# test/integration/production_final_check_test.rb
#
# ============================================================
# 【このファイルの役割】
# Issue #37「本番環境での最終動作確認」に対応するテストファイルです。
#
# 本番環境でのチェック項目をテストコードとして記述しています。
# テストを実行することで以下を自動検証します：
#   1. ユーザー登録・ログイン
#   2. 習慣管理（作成・削除・ロック）
#   3. ダッシュボード表示
#   4. 週次振り返り（作成・詳細表示）
#   5. PDCAロック機能（ロック中の制限・解除フロー）
#
# ============================================================
# 【テスト設計の方針】
#
# ・travel_to で日時を固定する
#   → テストを実行する日時によって結果が変わるのを防ぐため
#   → AM4:00 前後の境界値テストも正確に行えるようにするため
#
# ・fixtures を使わず User / Habit を直接作成する
#   → fixtures の並び順やデータに依存した不安定なテストを避けるため
#   → find_by(name:) で「名前で特定」して order に依存しないようにするため
#
# ・各テストは独立して動作する（テスト間で状態を共有しない）
#   → テストの実行順序が変わっても結果が一致するようにするため
#
# ============================================================
# 【重要】このテストと本番確認の関係
#
# このテストは「test環境（ローカル）」でロジックを検証するものです。
# Issue #37の完了条件「本番環境で正常に動作すること」を満たすには、
# このテストに加えて、以下も必ず実施してください：
#
#   1. デプロイ済みURL（Render）での手動チェックリスト確認
#      → docs/production_check_issue_37.md を参照
#
#   2. Renderのログ画面でエラー（500系）が出ていないことを確認
#      → Dashboard → habitflow-web → Logs
#
# ============================================================

require "test_helper"

class ProductionFinalCheckTest < ActionDispatch::IntegrationTest
  # ============================================================
  # setup: 各テストの前に必ず実行されるメソッド
  # ============================================================
  # 【なぜ setup で共通データを作るのか】
  # 各テストで同じユーザーを毎回作ると記述が重複するため、
  # setup にまとめることでDRY（繰り返しを避ける）な設計にする。
  # setup は Minitest が各テストメソッドの直前に自動で呼ぶ。
  #
  # 【create! と create の違い】
  # create  → 保存失敗時に false を返す（エラーに気づきにくい）
  # create! → 保存失敗時に例外を発生させる（即座に原因が分かる）
  # テストデータの作成には create! を使うことで、
  # 「データが正しく作れなかった」という問題を早期発見できる。
  def setup
    @user = User.create!(
      name:                  "最終確認ユーザー",
      email:                 "final_check@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )
  end

  # ============================================================
  # teardown: 各テストの後に必ず実行されるメソッド
  # ============================================================
  # 【なぜ travel_back が必要なのか】
  # travel_to で時間を操作したままにすると、後続のテストの
  # 時刻判定（ロック判定など）が狂ってしまう。
  # teardown で必ず travel_back を呼ぶことで、
  # 「このテストの時刻操作が他のテストに漏れない」ことを保証する。
  def teardown
    travel_back
  end

  # ============================================================
  # 1. ユーザー登録・ログインのテスト
  # ============================================================

  # ----------------------------------------------------------
  # テスト: ユーザー登録が正常にできること
  # ----------------------------------------------------------
  # 【検証内容】
  # 新規ユーザーがフォームから登録でき、
  # 登録後にダッシュボードへリダイレクトされることを確認する。
  test "ユーザー登録が正常にできること" do
    # travel_to: テスト実行中の時刻を固定する（タイムマシン機能）
    # 水曜日のAM10:00に固定する理由：
    # PDCAロックは「月曜AM4:00以降かつ前週振り返り未完了」で発動する。
    # 水曜AM10:00は月曜AM4:00を過ぎているが、前週レコードが存在しないため
    # ロックは発動しない（ApplicationController#locked? の Step3 でreturn false）。
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do

      # assert_difference の使い方：
      # assert_difference "User.count", 1 do ... end
      # ↓
      # ブロックの実行前後で User.count が「1」増えることを検証する。
      # もし増えなければテスト失敗 → データが保存されていないことが分かる。
      assert_difference "User.count", 1 do
        post users_path, params: {
          user: {
            name:                  "新規テストユーザー",
            email:                 "new_user_test@example.com",
            password:              "password123",
            password_confirmation: "password123"
          }
        }
      end

      # assert_redirected_to: レスポンスが指定したURLへのリダイレクトか確認する。
      # 登録成功後はダッシュボードへ遷移するのがこのアプリの正しい仕様。
      assert_redirected_to dashboard_path
    end
  end

  # ----------------------------------------------------------
  # テスト: ログインが正常にできること
  # ----------------------------------------------------------
  test "ログインが正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # POST /login: SessionsController#create を呼び出す。
      # params に email と password を渡すことでログインを試みる。
      post login_path, params: {
        session: {
          email:    @user.email,
          password: "password123"
        }
      }

      # ログイン成功後はダッシュボードへリダイレクトされる。
      assert_redirected_to dashboard_path
    end
  end

  # ----------------------------------------------------------
  # テスト: 誤ったパスワードではログインできないこと
  # ----------------------------------------------------------
  # 【検証内容】
  # 誤ったパスワードを入力した場合、ログインが失敗して
  # ログインページに留まることを確認する（セキュリティ確認）。
  test "誤ったパスワードではログインできないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: {
        session: {
          email:    @user.email,
          password: "wrong_password"
        }
      }

      # SessionsController#create は認証失敗時に
      # render :new, status: :unprocessable_entity を実行する。
      # そのため 422 Unprocessable Content が正しい期待値。
      # （Turbo Drive がフォームエラーを正しく扱うために422を返す設計）
      assert_response :unprocessable_entity
    end
  end

  # ----------------------------------------------------------
  # テスト: ログアウトが正常にできること
  # ----------------------------------------------------------
  test "ログアウトが正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # まずログインしてセッションを確立する。
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # DELETE /logout: SessionsController#destroy を呼び出す。
      # セッションを破棄してログアウトする。
      delete logout_path

      # ログアウト後はルートパス（ランディングページ）へリダイレクトされる。
      assert_redirected_to root_path
    end
  end

  # ============================================================
  # 2. 習慣管理のテスト
  # ============================================================

  # ----------------------------------------------------------
  # テスト: 習慣の作成が正常にできること
  # ----------------------------------------------------------
  test "習慣の作成が正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # ログイン処理（習慣作成には認証が必要）。
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # Habit.count が1増えることを検証する。
      assert_difference "Habit.count", 1 do
        post habits_path, params: {
          habit: {
            name:          "テスト習慣",
            weekly_target: 5
          }
        }
      end

      # 作成成功後は習慣一覧へリダイレクトされる。
      assert_redirected_to habits_path
    end
  end

  # ----------------------------------------------------------
  # テスト: 習慣の論理削除が正常にできること
  # ----------------------------------------------------------
  # 【論理削除とは】
  # レコードをDBから物理的に削除するのではなく、
  # deleted_at カラムに「削除した日時」を記録することで
  # 「削除済み」扱いにする仕組み。
  # 過去の振り返りデータとの整合性を保つために使用している。
  test "習慣の論理削除が正常にできること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # テスト用習慣を事前に作成しておく。
      habit = @user.habits.create!(name: "削除テスト習慣", weekly_target: 7)

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # DELETE /habits/:id を送信する。
      delete habit_path(habit)

      assert_redirected_to habits_path

      # habit.reload: DBからデータを再取得する。
      # 【なぜ reload が必要なのか】
      # Rubyオブジェクト（habit変数）はメモリ上のキャッシュを持っている。
      # deleted_at が更新されてもオブジェクトに反映されない場合があるため、
      # reload でDBから最新データを取り直す必要がある。
      habit.reload

      # deleted_at が nil でないこと = 論理削除されていること。
      assert_not_nil habit.deleted_at
    end
  end

  # ----------------------------------------------------------
  # テスト: 未ログイン状態では習慣一覧にアクセスできないこと
  # ----------------------------------------------------------
  test "未ログイン状態では習慣一覧にアクセスできないこと" do
    # ログインせずに直接アクセスする（未認証状態の確認）。
    get habits_path

    # ログインページへリダイレクトされることを確認する。
    # これにより「ログインしていないと見られない」という認証ガードが
    # 正しく機能していることを保証できる。
    assert_redirected_to login_path
  end

  # ============================================================
  # 3. ダッシュボード表示のテスト
  # ============================================================

  # ----------------------------------------------------------
  # テスト: ダッシュボードが正常に表示されること
  # ----------------------------------------------------------
  test "ダッシュボードが正常に表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      @user.habits.create!(name: "読書", weekly_target: 7)
      @user.habits.create!(name: "筋トレ", weekly_target: 5)

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      get dashboard_path

      # 200 OK が返ること（エラーなくページが表示されること）。
      assert_response :success
    end
  end

  # ----------------------------------------------------------
  # テスト: 習慣がない状態でもダッシュボードが表示されること
  # ----------------------------------------------------------
  # 【なぜこのテストが必要なのか】
  # 習慣が0件のとき、進捗計算ロジックで「ゼロ除算」や「空配列への操作」が
  # 発生しないか確認するためのエッジケーステスト。
  # 初回ログインユーザーは必ず習慣0件の状態を通るため重要。
  test "習慣がない状態でもダッシュボードが表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      get dashboard_path

      assert_response :success
    end
  end

  # ----------------------------------------------------------
  # テスト: 習慣が10件あってもダッシュボードが正常に表示されること
  # ----------------------------------------------------------
  # 【このテストとN+1問題の関係】
  # このテストはN+1問題を「直接」検知するものではありません。
  # 習慣が10件あっても200 OKが返ることを確認する「間接的な」性能確認です。
  #
  # N+1問題が発生しているかどうかを厳密に確認するには、
  # 本番環境（Render）のログや Bullet gem の警告を確認してください。
  # → Render Dashboard → habitflow-web → Logs
  test "習慣が10件あってもダッシュボードが正常に表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # 10件の習慣を作成する。
      10.times do |i|
        @user.habits.create!(name: "習慣#{i + 1}", weekly_target: 7)
      end

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      get dashboard_path

      # 10件の習慣があっても 200 OK が返ること。
      assert_response :success
    end
  end

  # ============================================================
  # 4. 週次振り返りのテスト
  # ============================================================

  # ----------------------------------------------------------
  # テスト: 週次振り返りを作成できること
  # ----------------------------------------------------------
  # 【travel_to の日時について】
  # 2026-03-09(月) AM10:00 に固定する。
  # この時点では「前週(3/2〜3/8)」の振り返りレコードが存在しないため
  # PDCAロックは発動しない（初週ユーザー扱い）。
  test "週次振り返りを作成できること" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      @user.habits.create!(name: "読書", weekly_target: 7)

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # WeeklyReflection.count が1増えることを検証する。
      assert_difference "WeeklyReflection.count", 1 do
        post weekly_reflections_path, params: {
          weekly_reflection: {
            reflection_comment: "今週は読書を7日間達成できました。"
          }
        }
      end

      # 作成成功後はリダイレクトされる（ロック状態によりダッシュボードまたは一覧）。
      assert_response :redirect
    end
  end

  # ----------------------------------------------------------
  # テスト: 週次振り返り一覧ページが表示されること
  # ----------------------------------------------------------
  test "週次振り返り一覧ページが表示されること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      get weekly_reflections_path

      assert_response :success
    end
  end

  # ----------------------------------------------------------
  # テスト: 週次振り返り詳細ページが表示されること
  # ----------------------------------------------------------
  test "週次振り返り詳細ページが表示されること" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      # 完了済みの振り返りレコードを直接作成する。
      # 【なぜ直接作成するのか】
      # show アクションの動作確認だけが目的のため、
      # 振り返り作成フロー全体を再現する必要はない。
      # 必要なデータだけを最小限で用意する（テストの独立性を保つ）。
      reflection = @user.weekly_reflections.create!(
        week_start_date: Date.new(2026, 3, 2),
        week_end_date:   Date.new(2026, 3, 8),
        reflection_comment: "テスト振り返りコメント",
        completed_at:    Time.zone.local(2026, 3, 9, 9, 0, 0),
        is_locked:       true
      )

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      get weekly_reflection_path(reflection)

      assert_response :success
    end
  end

  # ============================================================
  # 5. PDCAロック機能のテスト
  # ============================================================

  # ----------------------------------------------------------
  # テスト: ロック中は習慣を作成できないこと
  # ----------------------------------------------------------
  # 【ロック発動条件の再現方法】
  # Step1: 月曜AM4:00以降に時刻を固定する
  # Step2: 前週（2/23〜3/1）の振り返りを「未完了」状態で作成する
  #        completed_at: nil = 未完了
  # → ApplicationController#locked? の全条件が満たされる
  test "ロック中は習慣を作成できないこと" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      # 【week_start_date の計算根拠】
      # travel_to: 2026-03-09（月）JST AM10:00
      # today_for_record → 2026-03-09（JST）
      # .beginning_of_week(:monday) → 2026-03-09
      # - 1.week → 2026-03-02
      # つまり locked? が検索する「前週」は 2026-03-02 始まりの週
      @user.weekly_reflections.create!(
        week_start_date: Date.new(2026, 3, 2),
        week_end_date:   Date.new(2026, 3, 8),
        completed_at:    nil,
        is_locked:       false
      )

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      assert_no_difference "Habit.count" do
        post habits_path, params: {
          habit: { name: "ロック中の習慣", weekly_target: 7 }
        }
      end

      assert_response :redirect
    end
  end

  # ----------------------------------------------------------
  # テスト: 月曜AM3:59はロックが発動しないこと（境界値テスト・下限）
  # ----------------------------------------------------------
  # 【なぜ境界値テストが重要なのか】
  # AM4:00 ちょうどの前後でロック判定が変わる仕様のため、
  # 境界値（3:59 と 4:00）での動作が正しいか必ず確認する必要がある。
  # 境界値の1分前（3:59）でロックが発動しないことを確認する。
  test "月曜AM3:59はロックが発動しないこと" do
    travel_to Time.zone.local(2026, 3, 9, 3, 59, 0) do
      # 【week_start_date の計算根拠】
      # travel_to: 2026-03-09（月）JST AM3:59
      # locked? の Step1:
      #   this_monday_4am = 2026-03-09 04:00 JST
      #   now(3:59) < this_monday_4am(4:00) → true → return false
      # AM3:59 はロック判定に達する前に return false で終わるため
      # 振り返りレコードの日付はロック判定に影響しない。
      # ただし意図を明示するため前週のレコードを作成しておく。
      @user.weekly_reflections.create!(
        week_start_date: Date.new(2026, 3, 2),
        week_end_date:   Date.new(2026, 3, 8),
        completed_at:    nil,
        is_locked:       false
      )

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      assert_difference "Habit.count", 1 do
        post habits_path, params: {
          habit: { name: "AM4時前の習慣", weekly_target: 7 }
        }
      end

      assert_redirected_to habits_path
    end
  end

  # ----------------------------------------------------------
  # テスト: 月曜AM4:00ちょうどでロックが発動すること（境界値テスト・上限）
  # ----------------------------------------------------------
  # 【レビュー指摘により追加】
  # 3:59（ロックなし）のテストだけでは「4:00ちょうど」の挙動が未検証のため、
  # 境界値の正確な動作を確認するためにこのテストを追加する。
  #
  # 【仕様の確認】
  # ApplicationController#locked? の判定：
  #   return false if now < this_monday_4am
  #   ↓
  #   now = 4:00:00, this_monday_4am = 4:00:00 の場合
  #   now < this_monday_4am → false（等しいので「より小さい」は偽）
  #   → return false しない → ロック判定に進む → ロックあり
  test "月曜AM4:00ちょうどでロックが発動すること" do
    travel_to Time.zone.local(2026, 3, 9, 4, 0, 0) do
      # 【week_start_date の計算根拠】
      # travel_to: 2026-03-09（月）JST AM4:00ちょうど
      # today_for_record: now(4:00) < boundary(4:00) → false → 2026-03-09
      # beginning_of_week → 2026-03-09、- 1.week → 2026-03-02
      @user.weekly_reflections.create!(
        week_start_date: Date.new(2026, 3, 2),
        week_end_date:   Date.new(2026, 3, 8),
        completed_at:    nil,
        is_locked:       false
      )

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      assert_no_difference "Habit.count" do
        post habits_path, params: {
          habit: { name: "境界値テスト習慣", weekly_target: 7 }
        }
      end

      assert_response :redirect
    end
  end

  # test/integration/production_final_check_test.rb
  # （修正箇所は「振り返り完了でロックが解除されること」テストのみ）
  #
  # 【Issue #41 修正点】
  #   「振り返り完了でロックが解除されること」テストのアサーション修正。
  #
  #   【修正前の問題点】
  #     assert_match "振り返りが完了しました", response.body
  #     → assert_match は文字列の部分一致チェック。
  #       実際のメッセージ "🔓 振り返りが完了しました！PDCAロックが解除されました。..."
  #       には「振り返りが完了しました」が含まれるため通過するが、
  #       flash[:unlock] キーでレンダリングされているかを確認できていない。
  #       また絵文字（🔓）がエンコードされる環境では assert_match が失敗する可能性がある。
  #
  #   【修正後の対応】
  #     assert_select で DOM ノードの存在を確認する方式に変更。
  #     flash[:unlock] キーは layout で unlock クラスの緑バナーとして表示されるため、
  #     「PDCAロックが解除されました」という文字列の存在を確認する。
  #     これにより絵文字エンコードの問題も回避できる。
  #
  #   ※ このテストファイル全体のうち、変更するのはこの1テストのアサーション部分のみ。
  #   ※ ファイル全体を置き換える場合はこのコメントを先頭に含めること。

  # ----------------------------------------------------------
  # テスト: 振り返り完了でロックが解除されること（修正後）
  # ----------------------------------------------------------
  test "振り返り完了でロックが解除されること" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      # locked? が探す前週 = 2026-03-02 始まりの週
      @user.weekly_reflections.create!(
        week_start_date: Date.new(2026, 3, 2),
        week_end_date:   Date.new(2026, 3, 8),
        completed_at:    nil,
        is_locked:       false
      )

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      post weekly_reflections_path, params: {
        weekly_reflection: {
          reflection_comment: "ロック解除テスト用の振り返りコメント。"
        }
      }

      # was_locked = true のため dashboard_path にリダイレクトされる。
      assert_redirected_to dashboard_path
      follow_redirect!

      # ── 【Issue #41 修正】アサーションを assert_match から assert_select に変更 ──
      #
      # 【修正前】
      #   assert_match "振り返りが完了しました", response.body
      #   → 文字列の部分一致チェックのため、どの DOM 要素に表示されているかが不明。
      #   → 絵文字（🔓）を含む文字列の前後でエンコード差異が生じる可能性がある。
      #
      # 【修正後】
      #   assert_select で DOM のテキストノードを確認する。
      #   flash[:unlock] は layout の when 'unlock' ブランチでレンダリングされ、
      #   "PDCAロックが解除されました" というテキストを含む要素が表示される。
      #   絵文字を含まない部分を検索することでエンコード問題を回避する。
      #
      # assert_select の使い方:
      #   assert_select "セレクタ", text: /正規表現/
      #   → 指定セレクタの要素のテキストが正規表現にマッチすることを検証する。
      #   "body" を使うことでページ内のどこに表示されていても検出できる。
      assert_select "body", text: /PDCAロックが解除されました/
    end
  end

  # ============================================================
  # 6. エラーハンドリングのテスト
  # ============================================================

  # ----------------------------------------------------------
  # テスト: 存在しないURLにアクセスすると404が返ること
  # ----------------------------------------------------------
  # 【検証内容】
  # routes.rb の catch-all ルートが受け取り ErrorsController#not_found へ
  # ルーティングされ、カスタム404ページが返ることを確認する（Issue #27 の動作確認）。
  test "存在しないURLにアクセスすると404が返ること" do
    get "/this_path_does_not_exist"

    # assert_response :not_found は HTTPステータスが 404 であることを検証する。
    assert_response :not_found
  end

  # ----------------------------------------------------------
  # テスト: 他のユーザーの習慣は削除できないこと（認可テスト）
  # ----------------------------------------------------------
  # 【検証内容】
  # 別ユーザーが作成した習慣を削除しようとしてもできないことを確認する。
  # セキュリティ上の重要なテスト（認可制御の確認）。
  test "他のユーザーの習慣は削除できないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # 別のユーザーとその習慣を作成する。
      other_user = User.create!(
        name:                  "他ユーザー",
        email:                 "other_user@example.com",
        password:              "password123",
        password_confirmation: "password123"
      )
      other_habit = other_user.habits.create!(name: "他ユーザーの習慣", weekly_target: 7)

      # @user としてログインする。
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # @user が other_habit を削除しようとする。
      # assert_no_difference: Habit.count が変化しないことを検証する。
      assert_no_difference "Habit.count" do
        delete habit_path(other_habit)
      end

      # other_habit の deleted_at が nil のまま（削除されていない）であること。
      other_habit.reload
      assert_nil other_habit.deleted_at
    end
  end
end