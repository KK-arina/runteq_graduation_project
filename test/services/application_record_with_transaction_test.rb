# test/services/application_record_with_transaction_test.rb
#
# ============================================================
# 【修正内容】
# with_transaction から rescue が削除されたため、テストを修正する。
#
# 【新しい with_transaction の動作】
# - 成功時: ブロックの戻り値を返す（Hash ではなく yield の戻り値）
# - 失敗時: 例外をそのまま raise する（サービスクラス側で rescue する）
#
# → テストでは例外が raise されることを assert_raises で確認する
# ============================================================

require "test_helper"

class ApplicationRecordWithTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  # 【テスト1】成功時はブロックの戻り値を返すこと
  test "with_transaction が成功したときブロックの戻り値を返すこと" do
    result = ApplicationRecord.with_transaction do
      # ブロックの最後の式が戻り値になる
      "成功"
    end

    assert_equal "成功", result
  end

  # 【テスト2】成功時に DB が更新されること
  test "with_transaction が成功したとき DB に保存されること" do
    assert_difference "Habit.count", 1 do
      ApplicationRecord.with_transaction do
        @user.habits.create!(name: "トランザクションテスト習慣", weekly_target: 5)
      end
    end
  end

  # 【テスト3】RecordInvalid 時にロールバックして例外を raise すること
  test "RecordInvalid が発生したとき DB がロールバックされて例外が raise されること" do
    user_count_before = User.count

    # with_transaction が例外を raise することを確認する
    assert_raises ActiveRecord::RecordInvalid do
      ApplicationRecord.with_transaction do
        invalid_user = User.new(name: "", email: "rollback_test@test.com", password: "password123")
        invalid_user.save!
      end
    end

    # ロールバックにより件数が変わっていないこと
    assert_equal user_count_before, User.count,
                 "RecordInvalid 後はロールバックされ User の件数が変わらないこと"
  end

  # 【テスト4】StandardError 時にロールバックして例外を raise すること
  test "StandardError が発生したとき DB がロールバックされて例外が raise されること" do
    habit_count_before = Habit.count

    assert_raises StandardError do
      ApplicationRecord.with_transaction do
        @user.habits.create!(name: "ロールバックテスト用習慣", weekly_target: 5)
        raise StandardError, "テスト用の強制エラー"
      end
    end

    assert_equal habit_count_before, Habit.count,
                 "StandardError 後はロールバックされ Habit の件数が変わらないこと"
  end

  # 【テスト5】ネストしたトランザクションで全ロールバックされること
  #
  # 【なぜ全ロールバックされるのか】
  # with_transaction は rescue を持たないため、内側で例外が発生すると
  # 外側の transaction まで伝播する。
  # Rails のデフォルトのトランザクションネスト（savepoint なし）では
  # 内側の例外が外側のトランザクションを全てロールバックする。
  #
  # 実行の流れ:
  # 1. 外側 transaction 開始
  # 2. 習慣1を作成（DB には未コミット）
  # 3. 内側 transaction 開始（外側に合流）
  # 4. 習慣2を作成（DB には未コミット）
  # 5. 例外発生
  # 6. 例外が外側まで伝播する
  # 7. 外側 transaction がロールバック（習慣1も習慣2も消える）
  # 8. 外側の assert_raises が例外をキャッチ
  test "ネストしたトランザクションで内側が失敗したとき外側も含めて全ロールバックされること" do
    habit_count_before = Habit.count

    assert_raises ActiveRecord::RecordInvalid do
      ApplicationRecord.with_transaction do
        # 外側: 習慣1を作成
        @user.habits.create!(name: "外側テスト習慣", weekly_target: 3)

        # 内側: with_transaction を呼ぶ（rescue がないため例外が外に伝播する）
        ApplicationRecord.with_transaction do
          @user.habits.create!(name: "内側テスト習慣", weekly_target: 5)
          # 意図的に失敗させる
          invalid = @user.habits.new(name: "", weekly_target: 1)
          invalid.save!
        end
      end
    end

    # 外側も内側も全てロールバックされること
    assert_equal habit_count_before, Habit.count,
                 "ネスト時に内側が失敗したとき外側も含めて全ロールバックされること"
  end
end