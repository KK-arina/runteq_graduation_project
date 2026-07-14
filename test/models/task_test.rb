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
      password_confirmation: "password123",
      # D-7 追加: first_login_at が NULL だと /onboarding/step5 へリダイレクトされテストが失敗する
      first_login_at:        1.month.ago
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
    task = Task.new(title: "")
    assert_not task.valid?
    # 【修正】"を入力してください" → "タスク名を入力してください"
    # ja.yml で title の日本語名が "タスク名" に設定されているため
    # エラーメッセージは "タスク名を入力してください" になる
    assert_includes task.errors[:title], "タスク名を入力してください"
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

  # ============================================================
  # I-1 追加: task_type enum・set_default_task_type コールバック
  # ============================================================
  #
  # 【なぜ追加するのか】
  #   既存テストは priority / status の enum は検証していたが、
  #   task_type（normal / habit / improve）の enum と、
  #   task_type が未指定のときに normal を自動設定する
  #   before_validation :set_default_task_type コールバックが
  #   一度も検証されていなかった。I-1（本リリースのテスト網羅）で補う。

  test "task_type enum に normal / habit / improve が定義されている" do
    # 【assert_includes を使う理由】
    #   assert_equal 0, Task.task_types[:normal] だと enum の数値順を
    #   変えた瞬間に壊れる。「キーが存在するか」を見る方が将来変更に強い。
    assert_includes Task.task_types.keys, "normal",  "normal が task_type enum に定義されていない"
    assert_includes Task.task_types.keys, "habit",   "habit が task_type enum に定義されていない"
    assert_includes Task.task_types.keys, "improve", "improve が task_type enum に定義されていない"
  end

  test "normal? / habit? / improve? が正しく動作する" do
    # enum を定義すると Rails が自動で「◯◯?」という述語メソッドを生成する。
    # その述語が現在の task_type と一致したときだけ true を返すことを確認する。
    @valid_task.task_type = :habit
    assert @valid_task.habit?
    assert_not @valid_task.normal?

    @valid_task.task_type = :improve
    assert @valid_task.improve?
  end

  test "task_type が nil のとき set_default_task_type で normal が自動設定される" do
    # 【このテストが検証している実際のバグ】
    #   フォームで種別を選ばずに送信すると task_type が空（nil）で届く。
    #   tasks.task_type は NOT NULL 制約なので、そのまま保存すると
    #   DB エラー（NOT NULL 制約違反）になってしまう。
    #   before_validation :set_default_task_type がこれを防ぐ。
    #
    # 【なぜ new した直後ではなく nil を代入して検証するのか】
    #   Task.new は DB のデフォルト値(default: 0 = normal)を読み込むため、
    #   何も指定しなくても task_type は最初から "normal" になっている。
    #   そのため「コールバックが効いているか」を正しく確かめるには、
    #   一度 nil にリセットしてから valid?（＝before_validation発火）を通す必要がある。
    task = Task.new(user: @user, title: "種別未指定タスク", priority: :must)
    task.task_type = nil      # フォーム未選択で送られてきた状況を再現する
    assert_nil task.task_type # この時点ではまだ nil

    task.valid?               # valid? を呼ぶと before_validation が走る

    assert task.normal?, "task_type が nil のとき normal が自動設定されること"
  end

  # ============================================================
  # I-1 追加: priority の presence バリデーション
  # ============================================================
  #
  # 【なぜ追加するのか】
  #   既存テストは must?/should?/could? の動作は見ていたが、
  #   「priority が空なら無効」という presence バリデーション自体を
  #   検証していなかった。優先度は必須項目なので明示的にテストする。
  test "priority が nil なら無効（必須項目）" do
    # enum 属性には nil を代入できる（未選択状態を表現できる）。
    # その状態で presence: true のバリデーションが働くことを確認する。
    @valid_task.priority = nil
    assert_not @valid_task.valid?
    # ja.yml の errors.models.task.priority.blank = "を入力してください"
    # が使われるため、エラー配列にこの文言が含まれる。
    assert_includes @valid_task.errors[:priority], "を入力してください"
  end

  # ============================================================
  # I-1 追加: belongs_to :habit は optional（習慣に紐付かなくても有効）
  # ============================================================
  #
  # 【なぜ追加するのか】
  #   Task は habit_id が NULL 許容（習慣と無関係のタスクも作れる）。
  #   モデルで optional: true を付け忘れると "Habit must exist" エラーで
  #   全タスク作成が失敗する。回帰を防ぐため明示的に検証する。
  test "habit を紐付けなくてもタスクは有効" do
    @valid_task.habit = nil
    assert @valid_task.valid?, @valid_task.errors.full_messages.to_s
  end

  # ============================================================
  # I-1 追加: scope overdue（期限切れ かつ 未完了）
  # ============================================================
  #
  # 【なぜ追加するのか】
  #   既存テストには overdue?（インスタンスメソッド）のテストはあるが、
  #   一覧取得に使う Task.overdue（スコープ）のテストが無かった。
  #   メソッドとスコープは別物（片方だけ壊れることがある）なので個別に検証する。
  test "scope overdue は期限切れかつ done/archived 以外のタスクを返す" do
    # HabitRecord.today_for_record は AM4:00 基準の「今日」を返す共通メソッド。
    # 日付の基準を1箇所に統一するため、テストでもこれを使う。
    overdue_todo = Task.create!(
      user:     @user,
      title:    "期限切れ・未完了",
      priority: :must,
      status:   :todo,
      due_date: HabitRecord.today_for_record - 1.day   # 昨日が期限
    )
    overdue_done = Task.create!(
      user:     @user,
      title:    "期限切れ・完了済み",
      priority: :must,
      status:   :done,
      due_date: HabitRecord.today_for_record - 1.day
    )
    future_todo = Task.create!(
      user:     @user,
      title:    "未来期限・未完了",
      priority: :must,
      status:   :todo,
      due_date: HabitRecord.today_for_record + 1.day   # 明日が期限
    )

    overdue_ids = Task.overdue.where(user: @user).pluck(:id)
    assert_includes     overdue_ids, overdue_todo.id, "期限切れ未完了は overdue に含まれる"
    assert_not_includes overdue_ids, overdue_done.id, "完了済みは overdue から除外される"
    assert_not_includes overdue_ids, future_todo.id,  "未来期限は overdue に含まれない"
  end

  # ============================================================
  # I-1 追加: scope active の並び順
  # ============================================================
  #
  # 【なぜ追加するのか】
  #   既存テストは active が「deleted_at IS NULL を返す」ことは見ていたが、
  #   active スコープが持つ ORDER BY（priority ASC → due_date ASC NULLS LAST
  #   → created_at ASC）の並び順を検証していなかった。
  #   一覧の表示順はUXに直結するため、順序そのものを固定テストで守る。
  test "scope active は priority昇順 → due_date昇順(NULLは最後) の順に並ぶ" do
    # @user は setup で作った新規ユーザーなので、既存タスクは持たない。
    # そのため下記3件だけで並び順を厳密に検証できる。
    must_today = Task.create!(
      user: @user, title: "must-今日", priority: :must,
      due_date: HabitRecord.today_for_record
    )
    must_no_due = Task.create!(
      user: @user, title: "must-期限なし", priority: :must
      # due_date を指定しない → NULL（NULLS LAST で最後に並ぶ）
    )
    should_today = Task.create!(
      user: @user, title: "should-今日", priority: :should,
      due_date: HabitRecord.today_for_record
    )

    ordered_ids = Task.active.where(user: @user).pluck(:id)

    # 期待順:
    #   1. must-今日     … priority=must(0)・due_dateあり
    #   2. must-期限なし … priority=must(0)・due_dateがNULL → 同じpriority内では最後
    #   3. should-今日   … priority=should(1) → mustより後
    assert_equal [ must_today.id, must_no_due.id, should_today.id ], ordered_ids,
                 "active スコープの並び順が priority昇順→due_date昇順(NULL最後) になっていない"
  end
end