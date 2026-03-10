# test/integration/final_check_additional_test.rb
#
# ============================================================
# 【このファイルの役割】
# Issue #39「最終動作確認チェックリスト」の追加テストファイルです。
#
# production_final_check_test.rb では主にログイン・習慣・ダッシュボード・
# PDCAロックを確認しましたが、このファイルでは以下を追加確認します：
#   1. 週次振り返りの詳細表示・認可確認
#   2. バリデーションエラー表示確認
#   3. エラーページの確認（404, 422）
#   4. セキュリティ追加確認（XSS, 他ユーザーの振り返りアクセス拒否）
#   5. ナビゲーション・フラッシュメッセージ確認
#
# ============================================================
# 【テスト設計方針】
#   production_final_check_test.rb と同じ方針を踏襲します：
#   - travel_to で日時を固定する（タイムゾーンを含む時刻ロジックのズレ防止）
#   - fixtures を使わず create! でデータを作成する（テスト間の独立性確保）
#   - find_by(name:) で特定する（order 依存のテストを避ける）
# ============================================================

require "test_helper"

class FinalCheckAdditionalTest < ActionDispatch::IntegrationTest

  # ============================================================
  # setup: 各テストの前に共通データを作成する
  # ============================================================
  # 【なぜ setup に書くか】
  # 各テストで毎回同じユーザー作成コードを書くと重複が多くなる。
  # setup はテストごとに自動で呼ばれるので DRY に書ける。
  def setup
    @user = User.create!(
      name:                  "追加確認ユーザー",
      email:                 "additional_check@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )
  end

  # ============================================================
  # teardown: travel_to の後片付け
  # ============================================================
  # 【なぜ travel_back が必要か】
  # travel_to で操作した時刻を元に戻さないと、
  # 後続テストの時刻判定（ロック判定など）が正しく動かなくなる。
  # teardown は各テストメソッドの直後に自動で呼ばれる。
  def teardown
    travel_back
  end

  # ============================================================
  # 1. 週次振り返り詳細の認可テスト
  # ============================================================

  # ----------------------------------------------------------
  # テスト: 他のユーザーの週次振り返り詳細はアクセスできないこと
  # ----------------------------------------------------------
  # 【検証内容】
  # /weekly_reflections/:id の show アクションで、
  # 他ユーザーの振り返りは current_user.weekly_reflections.find(id) で
  # 取得するため ActiveRecord::RecordNotFound が発生し、
  # 一覧にリダイレクトされることを確認する。
  test "他のユーザーの週次振り返り詳細にアクセスできないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do

      # 別ユーザーとその振り返りを作成する
      other_user = User.create!(
        name:                  "他ユーザー振り返り",
        email:                 "other_reflection@example.com",
        password:              "password123",
        password_confirmation: "password123"
      )
      # 完了済みの振り返りレコードを直接作成する
      # completed_at: nil でないもの = 完了済み
      other_reflection = other_user.weekly_reflections.create!(
        week_start_date: Date.new(2026, 2, 23),
        week_end_date:   Date.new(2026, 3, 1),
        reflection_comment: "他ユーザーの振り返りコメント",
        completed_at:    Time.zone.local(2026, 3, 2, 10, 0, 0),
        is_locked:       true
      )

      # @user でログインする（other_user ではない）
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # other_reflection の詳細ページへアクセスする
      get weekly_reflection_path(other_reflection)

      # WeeklyReflectionsController#show の set_weekly_reflection で
      # current_user.weekly_reflections.find が RecordNotFound を発生させる。
      # rescue 節で weekly_reflections_path へリダイレクトされることを確認。
      assert_redirected_to weekly_reflections_path
    end
  end

  # ============================================================
  # 2. バリデーションエラー表示の確認
  # ============================================================

  # ----------------------------------------------------------
  # テスト: 習慣名が空白の場合バリデーションエラーが返ること
  # ----------------------------------------------------------
  # 【検証内容】
  # HabitsController#create でバリデーション失敗時に
  # render :new, status: :unprocessable_entity を返すことを確認する。
  # 422 が返ることでブラウザ（Turbo Drive）がエラーを正しく扱える。
  test "習慣名が空の場合422エラーが返ること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # 習慣名を空にしてPOSTする
      # assert_no_difference: Habit.count が変化しないことを確認する
      assert_no_difference "Habit.count" do
        post habits_path, params: {
          habit: {
            name:          "",    # バリデーション違反：空文字
            weekly_target: 5
          }
        }
      end

      # Rails の Turbo 対応では、バリデーション失敗時に 422 を返す必要がある
      # （200 を返すと Turbo Drive がエラーと認識しない）
      assert_response :unprocessable_entity
    end
  end

  # ----------------------------------------------------------
  # テスト: 週次目標が範囲外の場合バリデーションエラーが返ること
  # ----------------------------------------------------------
  test "週次目標が8の場合422エラーが返ること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      assert_no_difference "Habit.count" do
        post habits_path, params: {
          habit: {
            name:          "バリデーションテスト習慣",
            weekly_target: 8    # バリデーション違反：7を超える値
          }
        }
      end

      assert_response :unprocessable_entity
    end
  end

  # ----------------------------------------------------------
  # テスト: 重複メールアドレスで登録しようとすると422エラーが返ること
  # ----------------------------------------------------------
  # 【検証内容】
  # User モデルの validates :email, uniqueness を確認する。
  # 既に登録済みのメールアドレスで再登録しようとした場合のエラーを検証する。
  test "重複メールアドレスで登録すると422エラーが返ること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # @user はすでに "additional_check@example.com" で登録済み

      # 同じメールアドレスで再度登録を試みる
      # assert_no_difference: User.count が増えないことを確認する
      assert_no_difference "User.count" do
        post users_path, params: {
          user: {
            name:                  "重複ユーザー",
            email:                 "additional_check@example.com",  # 既存と同じ
            password:              "password123",
            password_confirmation: "password123"
          }
        }
      end

      # バリデーションエラーなので422を返す
      assert_response :unprocessable_entity
    end
  end

  # ============================================================
  # 3. エラーページの確認
  # ============================================================

  # ----------------------------------------------------------
  # テスト: 存在しないパスへのPOSTも404を返すこと
  # ----------------------------------------------------------
  # 【検証内容】
  # routes.rb の `match "*path", to: "errors#not_found", via: :all` が
  # GET 以外のメソッドにも対応していることを確認する（via: :all のテスト）。
  test "存在しないURLへのPOSTリクエストも404が返ること" do
    # via: :all で全 HTTP メソッドに対応しているかを POST で確認する
    post "/this_path_also_does_not_exist"

    # via: :all が正しく設定されていれば 404 になる
    assert_response :not_found
  end

  # ----------------------------------------------------------
  # テスト: 存在しないURLへのDELETEも404を返すこと
  # ----------------------------------------------------------
  test "存在しないURLへのDELETEリクエストも404が返ること" do
    delete "/this_path_does_not_exist_either"

    assert_response :not_found
  end

  # ============================================================
  # 4. セキュリティ確認
  # ============================================================

  # ----------------------------------------------------------
  # テスト: XSS対策（スクリプトが実行されずエスケープされること）
  # ----------------------------------------------------------
  # 【検証内容】
  # 習慣名に XSS 攻撃的なスクリプトを入力しても、
  # レスポンスの HTML でエスケープされて表示されることを確認する。
  #
  # Rails の ERB は <%= %> で自動エスケープするため、
  # <script> が &lt;script&gt; に変換される。
  # このテストはその動作を確認している。
  test "習慣名に含まれるスクリプトタグがエスケープされること" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # XSS 攻撃パターンを習慣名として登録する
      xss_name = "<script>alert('XSS')</script>"
      post habits_path, params: {
        habit: { name: xss_name, weekly_target: 3 }
      }

      # 習慣一覧ページへ遷移して、エスケープ確認
      get habits_path

      # assert_response :success: 200 OK が返ること
      assert_response :success

      # response.body: レスポンスの HTML 文字列
      #
      # 【なぜ assert_includes を使うのか】
      # assert_no_match で「<script> が含まれない」を確認するより、
      # assert_includes で「&lt;script&gt; が含まれる」を確認する方が確実。
      #
      # 理由: assert_no_match は「エスケープされた or そもそも保存されなかった」
      # の両方で通過してしまう。
      # assert_includes は「エスケープされた文字列が実際にレスポンスにある」
      # ことを陽性確認するため、Rails の自動エスケープが確実に動いていると言える。
      #
      # Rails の ERB は <%= %> で <script> を &lt;script&gt; に変換する。
      # この文字列が HTML に含まれていれば XSS 対策 OK。
      assert_includes response.body, "&lt;script&gt;"
    end
  end

  # ----------------------------------------------------------
  # テスト: パスワード8文字未満で登録できないこと
  # ----------------------------------------------------------
  # 【検証内容】
  # User モデルの validates :password, length: { minimum: 8 } を確認する。
  # 短いパスワードでの登録を防ぎ、アカウントを総当たり攻撃から守る。
  test "パスワードが8文字未満では登録できないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      assert_no_difference "User.count" do
        post users_path, params: {
          user: {
            name:                  "短パスワードユーザー",
            email:                 "short_pass@example.com",
            password:              "abc",   # 3文字：最小8文字に違反
            password_confirmation: "abc"
          }
        }
      end

      # バリデーションエラーで 422 を返す
      assert_response :unprocessable_entity
    end
  end

  # ============================================================
  # 5. ログアウト後のリダイレクト確認
  # ============================================================

  # ----------------------------------------------------------
  # テスト: ログアウト後にログイン必須ページへのアクセスは拒否されること
  # ----------------------------------------------------------
  # 【検証内容】
  # ログアウト後にセッションが完全にクリアされていることを確認する。
  # reset_session が正しく動作していれば、ログアウト後に
  # ダッシュボードへ直接アクセスしてもリダイレクトされる。
  test "ログアウト後はダッシュボードにアクセスできないこと" do
    travel_to Time.zone.local(2026, 3, 4, 10, 0, 0) do
      # まずログインする
      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # ログアウトする（SessionsController#destroy で reset_session が呼ばれる）
      delete logout_path

      # ログアウト後にダッシュボードへ直接アクセスを試みる
      get dashboard_path

      # セッションがクリアされているため require_login が働き、
      # login_path へリダイレクトされることを確認する
      assert_redirected_to login_path
    end
  end

  # ============================================================
  # 6. ロック中の操作制限確認（追加）
  # ============================================================

  # ----------------------------------------------------------
  # テスト: ロック中に習慣を削除しようとするとリダイレクトされること
  # ----------------------------------------------------------
  # 【検証内容】
  # require_unlocked が destroy にも設定されていることを確認する。
  # ロック中に DELETE /habits/:id を送っても論理削除されないことを保証する。
  test "ロック中は習慣を削除できないこと" do
    travel_to Time.zone.local(2026, 3, 9, 10, 0, 0) do
      # ロック条件を作る：前週（2026-03-02始まり）の振り返りが未完了
      @user.weekly_reflections.create!(
        week_start_date: Date.new(2026, 3, 2),
        week_end_date:   Date.new(2026, 3, 8),
        completed_at:    nil,    # nil = 未完了 = ロック発動
        is_locked:       false
      )

      # 事前に習慣を作成しておく
      habit = @user.habits.create!(name: "削除禁止テスト習慣", weekly_target: 7)

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # DELETE リクエストを送信する（ロック中なので require_unlocked が働く）
      delete habit_path(habit)

      # Habit.count が変化していないことを確認する
      # （論理削除は deleted_at を更新するが、count は変わらない）
      # deleted_at が nil のままであることを確認する
      habit.reload
      assert_nil habit.deleted_at, "ロック中に習慣が削除されてしまいました"
    end
  end

  # ----------------------------------------------------------
  # テスト: 前週の振り返りが完了済みなら火曜日もロックが発動しないこと
  # ----------------------------------------------------------
  # 【検証内容】
  # PDCAロックは「今週月曜AM4:00以降 + 前週振り返り未完了」の両条件で発動する。
  # つまり月曜に限らず、前週振り返りが未完了のまま週を越えると
  # 火曜・水曜・…と週を通じてロックが継続する。
  #
  # 逆に言えば、前週の振り返りが「完了済み」であれば
  # 火曜日でもロックは発動しない（習慣を作成できる）。
  #
  # 【修正理由】
  # 旧テストは「火曜日はロックしない」という誤った仕様理解に基づいていた。
  # 実際の locked? は「今週月曜AM4:00以降かつ前週未完了」で判定するため、
  # 火曜でも前週未完了ならロックが継続する。
  # このテストでは「前週完了済み → ロックなし」を正しく検証する。
  test "前週の振り返りが完了済みなら火曜日もロックが発動しないこと" do
    travel_to Time.zone.local(2026, 3, 10, 10, 0, 0) do  # 2026-03-10 は火曜日

      # 前週の振り返りを「完了済み」で作成する
      # completed_at に値がある = 完了済み = ロック解除状態
      #
      # 【注意】is_locked: false にすること
      # is_locked: true にすると locked? が reflection.is_locked を参照している場合、
      # completed_at があってもロック状態と判定されてしまう。
      # 「振り返りを完了した = ロック解除済み」を正確に表現するために false を指定する。
      @user.weekly_reflections.create!(
        week_start_date:    Date.new(2026, 3, 2),
        week_end_date:      Date.new(2026, 3, 8),
        reflection_comment: "完了済み",
        completed_at:       Time.zone.local(2026, 3, 9, 10, 0, 0),
        is_locked:          false
      )

      post login_path, params: {
        session: { email: @user.email, password: "password123" }
      }

      # 前週振り返り完了済みなのでロックが発動しない → 習慣が作成できる
      #
      # 【なぜ @user.habits.count を使うのか】
      # Habit.count は全ユーザーの習慣数を数えるため、
      # 他のテストで別ユーザーの習慣が作成された場合に誤って通過してしまうリスクがある。
      # @user.habits.count にすることで「このユーザーの習慣だけ」を確認できる。
      assert_difference "@user.habits.count", 1 do
        post habits_path, params: {
          habit: { name: "火曜日の習慣", weekly_target: 5 }
        }
      end

      assert_redirected_to habits_path
    end
  end

end
