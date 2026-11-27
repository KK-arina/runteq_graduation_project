# test/services/admin_user_list_service_test.rb
#
# ==============================================================================
# AdminUserListService（管理画面のユーザー一覧）のテスト
# ==============================================================================
#
# 【このテストで保証すること】
#   ① 集計の対象の人だけを出し、1人ずつの件数を数える
#   ② 絞り込み（未使用・休眠・継続中）と、状態の判定が合っている
#   ③ ページ送り（不正な値や大きすぎるページ番号も安全に扱う）
#
# 【テストの前提】
#   fixture のユーザーはすべて予約ドメイン（@example.com）なので一覧に出ない。
#   setup で users(:one) をふつうのドメインに書き換え、一覧に出る人を作る。
#   記録の有無をはっきりさせるため、users(:one) の記録はいったん全部削除済みにしてから始める。
# ==============================================================================
require "test_helper"

class AdminUserListServiceTest < ActiveSupport::TestCase
  setup do
    @original_admin_emails = ENV["ADMIN_EMAILS"]
    ENV.delete("ADMIN_EMAILS")

    @now  = Time.zone.local(2026, 11, 27, 12, 0, 0)
    @user = users(:one)
    @user.update_columns(email: "list-user@gmail.com", last_active_at: nil)
    # 記録を0件の状態にする（論理削除。テストが終わるとトランザクションで元に戻る）
    HabitRecord.where(user_id: @user.id).update_all(deleted_at: @now)
  end

  teardown do
    if @original_admin_emails.nil?
      ENV.delete("ADMIN_EMAILS")
    else
      ENV["ADMIN_EMAILS"] = @original_admin_emails
    end
  end

  # users(:one) に、記録を1件追加する
  #   insert! はバリデーションを通さずに1行入れる（テストの準備を短くするため）
  def add_record_for(user)
    habit_id = Habit.insert!({ user_id: user.id, name: "一覧テスト用の習慣", weekly_target: 7 }).rows.first.first
    HabitRecord.insert!({ user_id: user.id, habit_id: habit_id, record_date: @now.to_date - 30, completed: true })
  end

  def list(filter: "all", page: 1, per_page: AdminUserListService::PER_PAGE)
    AdminUserListService.new(filter: filter, page: page, per_page: per_page, now: @now).call
  end

  # ── ① 対象と件数 ─────────────────────────────────────────────────
  test "集計の対象の人だけを出す（予約ドメインの fixture ユーザーは出さない）" do
    result = list

    assert_equal [ @user.id ], result.rows.map(&:id)
    assert_equal 1, result.total_count
  end

  test "1人ずつの記録数を、削除済みの記録を除いて数える" do
    assert_equal 0, list.rows.first.records_count

    add_record_for(@user)

    assert_equal 1, list.rows.first.records_count
  end

  # ── ② 絞り込みと状態 ─────────────────────────────────────────────
  test "記録が0件の人は「未使用」に出て、状態も未使用になる" do
    row = list(filter: "unused").rows.first

    assert_equal @user.id, row.id
    assert_equal :unused, AdminUserListService.status_for(row, now: @now)
    assert_empty list(filter: "dormant").rows
  end

  test "記録があり、15日前から使っていない人は「休眠」に出る" do
    add_record_for(@user)
    @user.update_columns(last_active_at: @now - 15.days)

    row = list(filter: "dormant").rows.first

    assert_equal @user.id, row.id
    assert_equal :dormant, AdminUserListService.status_for(row, now: @now)
    assert_empty list(filter: "unused").rows
    assert_empty list(filter: "active").rows
  end

  test "記録があり、2日前に使った人は「継続中」に出る" do
    add_record_for(@user)
    @user.update_columns(last_active_at: @now - 2.days)

    row = list(filter: "active").rows.first

    assert_equal @user.id, row.id
    assert_equal :active, AdminUserListService.status_for(row, now: @now)
  end

  test "最後の利用が10日前の人は「様子見」で、休眠にも継続中にも出ない" do
    add_record_for(@user)
    @user.update_columns(last_active_at: @now - 10.days)

    assert_equal :cooling, AdminUserListService.status_for(list.rows.first, now: @now)
    assert_empty list(filter: "dormant").rows
    assert_empty list(filter: "active").rows
  end

  test "決まっていない絞り込みの値は「すべて」として扱う" do
    assert_equal "all", list(filter: "drop table users").filter
  end

  # ── ③ ページ送り ─────────────────────────────────────────────────
  test "ページ送りで、2ページ目には2人目が出る" do
    other = users(:two)
    other.update_columns(email: "list-user-2@gmail.com", last_active_at: @now - 1.day)
    @user.update_columns(last_active_at: @now)

    first_page  = list(page: 1, per_page: 1)
    second_page = list(page: 2, per_page: 1)

    assert_equal 2, first_page.total_pages
    assert_equal [ @user.id ], first_page.rows.map(&:id)
    assert_equal [ other.id ], second_page.rows.map(&:id)
  end

  test "ページ番号が不正・大きすぎるときは、1ページ目・最後のページにする" do
    assert_equal 1, list(page: "abc").page
    assert_equal 1, list(page: -3).page
    assert_equal 1, list(page: 999).page
  end
end
