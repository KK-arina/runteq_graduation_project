# test/models/task_test.rb
#
# ==============================================================================
# Task モデルテスト（C-1: 基本CRUD）
# ==============================================================================
# 【レビュー指摘対応】
#   ① travel_to をブロック外に移動し teardown で travel_back する
#      理由: travel_to do...end はブロックを抜けると時間が元に戻る。
#            setup でブロック形式を使うと、テスト本体（test "..." do）の
#            実行時には時間が戻ってしまい、日付依存テストが不安定になる。
#            setup で travel_to（ブロックなし）+ teardown で travel_back が正しい。
#
#   ② fixed_time メソッドで時刻定数を一元管理する
#      理由: 同じ時刻を複数箇所に書くと、変更時に全箇所修正が必要になる。
#            メソッドに集約することで1か所の変更で済む（DRY原則）。
#
#   ③ enum テストを assert_includes に変更
#      理由: assert_equal 0, Task.priorities[:must] は enum の順番を変えると
#            壊れる。「キーが存在するか」を検証する方が将来変更に強い。
# ==============================================================================
require "test_helper"

class TaskTest < ActiveSupport::TestCase
  # ============================================================
  # fixed_time: テスト全体で使う固定時刻を返すメソッド
  # ============================================================
  # 【なぜメソッドにするのか】
  #   同じ Time.zone.local(2026, 4, 9, 10, 0, 0) を複数箇所に書くと、
  #   「テストの基準日を変えたい」ときに全箇所修正が必要になる。
  #   メソッドにまとめれば1か所だけ変更すれば済む。
  #
  # 2026年4月9日（木曜日）AM10:00 を選んだ理由:
  #   - 木曜日 → 月曜日ではないので locked? が false になりやすい
  #   - AM10:00 → AM4:00 を過ぎているので today_for_record が当日の日付を返す
  def fixed_time
    Time.zone.local(2026, 4, 9, 10, 0, 0)
  end

  # ============================================================
  # setup: 各テストの前に実行される共通処理
  # ============================================================
  # 【レビュー修正】
  #   travel_to をブロックなしで呼び出す。
  #   これによりテスト本体の実行中も時間が固定されたままになる。
  #
  # 【travel_to ブロックあり vs なしの違い】
  #   ブロックあり（修正前・NG）:
  #     travel_to fixed_time do
  #       @user = User.create!(...)  ← ここは固定時間
  #     end
  #     # ← ここから元の時間に戻ってしまう
  #     # テスト本体はリアル時間で動く → 不安定
  #
  #   ブロックなし（修正後・OK）:
  #     travel_to fixed_time
  #     @user = User.create!(...)
  #     # テスト本体も同じ固定時間で動く → 安定
  def setup
    travel_to fixed_time

    @user = User.create!(
      name:                  "テストユーザー",
      email:                 "task_test@example.com",
      password:              "password123",
      password_confirmation: "password123"
    )

    @valid_task = Task.new(
      user:     @user,
      title:    "企画書作成",
      priority: :should
    )
  end

  # ============================================================
  # teardown: 各テストの後に実行される後処理
  # ============================================================
  # 【なぜ travel_back が必要なのか】
  #   travel_to（ブロックなし）は「テスト終了後も時間を固定したまま」にする。
  #   次のテストに影響しないよう、teardown で必ず travel_back で元に戻す。
  #   teardown は test "..." が終わるたびに自動で呼ばれる。
  def teardown
    travel_back
  end

  # ============================================================
  # バリデーションテスト
  # ============================================================

  test "タイトル・ユーザー・優先度があれば有効" do
    assert @valid_task.valid?, @valid_task.errors.full_messages.to_s
  end

  test "タイトルが空なら無効" do
    @valid_task.title = ""
    assert_not @valid_task.valid?
    # 【修正】
    # ja.yml で task.attributes.title = "タスク名" と定義したため、
    # Rails は「属性名 + メッセージ」を連結して
    # "タスク名を入力してください" ではなく
    # full_messages では "タスク名を入力してください" になる。
    #
    # errors[:title] には属性名なしのメッセージ部分だけが入る。
    # full_messages には "タスク名を入力してください" が入る。
    #
    # errors[:title] → ["を入力してください"]
    # errors.full_messages → ["タスク名を入力してください"]
    #
    # テストでは errors[:title] を検証しているので
    # 属性名なしの "を入力してください" が正しい期待値になる。
    assert_includes @valid_task.errors[:title], "を入力してください"
  end

  test "タイトルが101文字以上なら無効" do
    @valid_task.title = "あ" * 101
    assert_not @valid_task.valid?
    assert @valid_task.errors[:title].any?, @valid_task.errors.full_messages.to_s
  end

  test "タイトルが100文字なら有効" do
    @valid_task.title = "あ" * 100
    assert @valid_task.valid?, @valid_task.errors.full_messages.to_s
  end

  test "estimated_hours が 0 以下なら無効" do
    @valid_task.estimated_hours = 0
    assert_not @valid_task.valid?
    assert @valid_task.errors[:estimated_hours].any?, @valid_task.errors.full_messages.to_s
  end

  test "estimated_hours が nil なら有効（任意項目）" do
    @valid_task.estimated_hours = nil
    assert @valid_task.valid?, @valid_task.errors.full_messages.to_s
  end

  test "estimated_hours が 0.5 なら有効" do
    @valid_task.estimated_hours = 0.5
    assert @valid_task.valid?, @valid_task.errors.full_messages.to_s
  end

  # ============================================================
  # enum テスト
  # ============================================================
  # 【レビュー修正】
  #   assert_equal 0, Task.priorities[:must] → assert_includes に変更。
  #
  # 【なぜ assert_includes のほうが良いのか】
  #   assert_equal 0, Task.priorities[:must] は「must の数値が 0 であること」を検証する。
  #   もし将来 enum の順番を変えると（例: must を 3 にする）テストが壊れる。
  #   実際に検証すべきは「must というキーが enum に定義されているか」なので、
  #   assert_includes Task.priorities.keys, "must" が意図に沿っている。
  #
  # 【Task.priorities.keys とは】
  #   Task.priorities は { "must" => 0, "should" => 1, "could" => 2 } を返す。
  #   .keys で ["must", "should", "could"] の配列になる。
  #   assert_includes はその配列に指定の要素が含まれるかを検証する。

  test "priority enum に must / should / could が定義されている" do
    assert_includes Task.priorities.keys, "must",   "must が priority enum に定義されていない"
    assert_includes Task.priorities.keys, "should", "should が priority enum に定義されていない"
    assert_includes Task.priorities.keys, "could",  "could が priority enum に定義されていない"
  end

  test "status enum に todo / doing / done / archived が定義されている" do
    assert_includes Task.statuses.keys, "todo",     "todo が status enum に定義されていない"
    assert_includes Task.statuses.keys, "doing",    "doing が status enum に定義されていない"
    assert_includes Task.statuses.keys, "done",     "done が status enum に定義されていない"
    assert_includes Task.statuses.keys, "archived", "archived が status enum に定義されていない"
  end

  test "must? / should? / could? が正しく動作する" do
    @valid_task.priority = :must
    assert @valid_task.must?
    assert_not @valid_task.should?

    @valid_task.priority = :should
    assert @valid_task.should?

    @valid_task.priority = :could
    assert @valid_task.could?
  end

  # ============================================================
  # スコープテスト
  # ============================================================
  # 【注意】travel_to は setup で設定済みなのでここでは不要。
  #         setup で作成した @user を使えばよい。

  test "scope active が deleted_at IS NULL を返す" do
    @valid_task.save!
    deleted_task = Task.create!(
      user:       @user,
      title:      "削除済みタスク",
      priority:   :could,
      deleted_at: Time.current
    )

    active_ids = Task.active.where(user: @user).pluck(:id)
    assert_includes     active_ids, @valid_task.id
    assert_not_includes active_ids, deleted_task.id
  end

  test "scope not_archived が archived を除外する" do
    @valid_task.save!
    archived_task = Task.create!(
      user:     @user,
      title:    "アーカイブ済み",
      priority: :could,
      status:   :archived
    )

    not_archived_ids = Task.active.not_archived.where(user: @user).pluck(:id)
    assert_includes     not_archived_ids, @valid_task.id
    assert_not_includes not_archived_ids, archived_task.id
  end

  test "scope must / should / could が優先度で絞り込む" do
    must_task   = Task.create!(user: @user, title: "Must",   priority: :must)
    should_task = Task.create!(user: @user, title: "Should", priority: :should)
    could_task  = Task.create!(user: @user, title: "Could",  priority: :could)

    must_ids   = Task.active.must.where(user:   @user).pluck(:id)
    should_ids = Task.active.should.where(user: @user).pluck(:id)
    could_ids  = Task.active.could.where(user:  @user).pluck(:id)

    assert_includes must_ids,   must_task.id
    assert_includes should_ids, should_task.id
    assert_includes could_ids,  could_task.id

    assert_not_includes must_ids,   should_task.id
    assert_not_includes should_ids, must_task.id
  end

  test "scope today が今日の due_date のタスクを返す" do
    today_task  = Task.create!(
      user:     @user,
      title:    "今日期限",
      priority: :must,
      due_date: HabitRecord.today_for_record
    )
    future_task = Task.create!(
      user:     @user,
      title:    "未来期限",
      priority: :must,
      due_date: HabitRecord.today_for_record + 1.day
    )

    today_ids = Task.active.today.where(user: @user).pluck(:id)
    assert_includes     today_ids, today_task.id
    assert_not_includes today_ids, future_task.id
  end

  # ============================================================
  # インスタンスメソッドテスト
  # ============================================================

  test "soft_delete が deleted_at を設定する" do
    @valid_task.save!
    assert_nil @valid_task.deleted_at

    @valid_task.soft_delete
    assert_not_nil @valid_task.reload.deleted_at
  end

  test "overdue? が期限切れを正しく判定する" do
    @valid_task.due_date = HabitRecord.today_for_record - 1.day
    assert @valid_task.overdue?, "昨日が期限なのに overdue? が false を返した"

    @valid_task.due_date = HabitRecord.today_for_record + 1.day
    assert_not @valid_task.overdue?, "明日が期限なのに overdue? が true を返した"

    # 完了済みは期限切れにならない
    @valid_task.due_date = HabitRecord.today_for_record - 1.day
    @valid_task.status   = :done
    assert_not @valid_task.overdue?, "完了済みタスクが overdue? = true を返した"
  end

  test "due_today? が今日の期限を正しく判定する" do
    @valid_task.due_date = HabitRecord.today_for_record
    assert @valid_task.due_today?, "今日が期限なのに due_today? が false を返した"

    @valid_task.due_date = HabitRecord.today_for_record + 1.day
    assert_not @valid_task.due_today?, "明日が期限なのに due_today? が true を返した"
  end

  # ============================================================
  # C-2 追加テスト: toggle_complete!
  # ============================================================

  test "toggle_complete!: todo タスクを done にできる" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      task = Task.new(
        user:     users(:one),
        title:    "完了テスト",
        priority: :must,
        status:   :todo
      )
      task.save!

      task.toggle_complete!

      assert task.done?, "status が done になること"
      assert_not_nil task.completed_at, "completed_at が設定されること"
    end
  end

  test "toggle_complete!: done タスクを todo に戻せる" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      task = Task.new(
        user:         users(:one),
        title:        "未完了に戻すテスト",
        priority:     :should,
        status:       :done,
        completed_at: Time.current
      )
      task.save!

      task.toggle_complete!

      assert task.todo?, "status が todo に戻ること"
      assert_nil task.completed_at, "completed_at が nil になること"
    end
  end

  test "toggle_complete!: archived タスクは操作されない" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      task = Task.new(
        user:         users(:one),
        title:        "アーカイブ済みテスト",
        priority:     :could,
        status:       :archived,
        completed_at: Time.current
      )
      task.save!

      task.toggle_complete!

      # archived のまま変わらない
      assert task.archived?, "archived のままであること"
    end
  end

  test "archive!: done タスクを archived にできる" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      task = Task.new(
        user:         users(:one),
        title:        "アーカイブテスト",
        priority:     :must,
        status:       :done,
        completed_at: Time.current
      )
      task.save!

      task.archive!

      assert task.archived?, "status が archived になること"
      assert_not_nil task.completed_at, "completed_at は保持されること"
    end
  end

  test "archive!: すでに archived のタスクは二重にアーカイブされない" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      task = Task.new(
        user:         users(:one),
        title:        "二重アーカイブ防止テスト",
        priority:     :must,
        status:       :archived,
        completed_at: Time.current
      )
      task.save!

      original_updated_at = task.updated_at

      task.archive!

      task.reload
      # updated_at が変わっていないことを確認（DB更新が起きていない）
      assert_equal original_updated_at, task.updated_at, "二重アーカイブは発生しないこと"
    end
  end

  # ============================================================
  # C-2 修正追加テスト: archive! のガード
  # ============================================================

  test "archive!: todo タスクはアーカイブできない" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      task = Task.new(
        user:     users(:one),
        title:    "未完了アーカイブ禁止テスト",
        priority: :must,
        status:   :todo
      )
      task.save!

      original_status = task.status

      # todo タスクに archive! を呼ぶ
      task.archive!

      # status が変わっていないことを確認
      task.reload
      assert_equal original_status, task.status,
                  "todo タスクは archive! しても status が変わらないこと"
    end
  end

  test "archive!: doing タスクはアーカイブできない" do
    travel_to Time.zone.local(2026, 4, 8, 10, 0, 0) do
      task = Task.new(
        user:     users(:one),
        title:    "進行中アーカイブ禁止テスト",
        priority: :should,
        status:   :doing
      )
      task.save!

      task.archive!

      task.reload
      assert task.doing?, "doing タスクは archive! しても doing のままであること"
    end
  end

  # ============================================================
  # C-3: soft_delete / ai_generated のテスト（修正版）
  # ============================================================
  #
  # 【@task を使わない理由】
  #   task_test.rb の setup に @task の定義がないため
  #   @task を使うと NoMethodError: undefined method '...' for nil になる。
  #   各テスト内で Task.create! してローカル変数として使う。

  test "soft_delete は deleted_at を現在時刻に設定する" do
    task = Task.create!(
      user:     users(:one),
      title:    "soft_delete テスト",
      priority: :must
    )

    # 作成直後は deleted_at が nil のはず
    assert_nil task.deleted_at

    task.soft_delete

    # reload でDBから最新値を取得する
    # soft_delete は touch(:deleted_at) を実行するが
    # Rubyオブジェクトのキャッシュは自動更新されないため reload が必要
    assert_not_nil task.reload.deleted_at
  end

  test "soft_delete 後のタスクは active スコープに含まれない" do
    task = Task.create!(
      user:     users(:one),
      title:    "soft_delete スコープテスト",
      priority: :must
    )

    task.soft_delete

    # Task.active は deleted_at: nil のもののみ返す
    assert_not_includes Task.active, task.reload
  end

  test "ai_generated が true のタスクは ai_generated? が true を返す" do
    # tasks.yml の ai_generated_task フィクスチャを使う
    ai_task = tasks(:ai_generated_task)
    assert ai_task.ai_generated?
  end

  test "ai_generated が false のタスクは ai_generated? が false を返す" do
    task = Task.create!(
      user:         users(:one),
      title:        "手動タスク",
      priority:     :must,
      ai_generated: false
    )
    assert_not task.ai_generated?
  end
end