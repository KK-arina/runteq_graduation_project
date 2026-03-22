# test/db/index_audit_test.rb
#
# ==============================================================================
# 【Issue #A-6: DBインデックス監査テスト】
#
# 【このファイルの役割】
# DBレベルでインデックス・UNIQUE制約が正しく設定されているかを確認する。
# インデックスはアプリが正常動作していても欠けていることに気づきにくい。
# マイグレーションのミスや rollback 後の再適用漏れが起きても
# アプリは動き続け、パフォーマンスが徐々に低下するだけ。
# このテストが「インデックス漏れ」を即座に検知する安全網になる。
#
# 【実行方法】
# docker compose exec web bin/rails test test/db/index_audit_test.rb
# ==============================================================================

require "test_helper"

class IndexAuditTest < ActiveSupport::TestCase
  # ============================================================
  # ヘルパーメソッド
  # ============================================================

  # connection
  # ActiveRecord のDBアダプターへのショートカット。
  # テスト内で何度も ActiveRecord::Base.connection と書く代わりに
  # connection と短く書けるようにする。
  def connection
    ActiveRecord::Base.connection
  end

  # find_index_by_name
  # 指定したテーブルのインデックスを「インデックス名」で検索して返す。
  #
  # 【なぜ名前で検索するのか】
  # 部分インデックス（WHERE条件付き）は index_exists? では
  # where条件まで検証できない。
  # indexes メソッドで全インデックス情報（カラム・where条件・unique属性）を取得し、
  # 名前で特定することで詳細な検証が可能になる。
  #
  # 【引数】
  #   table - テーブル名（Symbol）例: :weekly_reflections
  #   name  - インデックス名（String）例: "idx_weekly_reflections_user_week_completed"
  #
  # 【戻り値】
  #   ActiveRecord::ConnectionAdapters::IndexDefinition または nil
  def find_index_by_name(table, name)
    # connection.indexes(table) → そのテーブルの全インデックス情報を配列で返す
    # .find { |i| i.name == name } → 名前が一致するものを1件返す
    connection.indexes(table).find { |i| i.name == name }
  end

  # ============================================================
  # habit_records テーブルのインデックス・制約確認
  # ============================================================

  test "habit_records に (user_id, record_date) の複合インデックスが存在する" do
    # 【重要度：高】
    # ダッシュボード・習慣一覧の週次達成率計算で必ず使われるインデックス。
    # DashboardsController#index の build_habit_stats が発行する
    # WHERE user_id=? AND record_date BETWEEN ? AND ? AND completed=true
    # というクエリがインデックスを利用できるかのカギ。
    assert connection.index_exists?(:habit_records, [:user_id, :record_date]),
           "habit_records に (user_id, record_date) の複合インデックスが必要です"
  end

  test "habit_records に (user_id, habit_id, record_date) の UNIQUE 制約が存在する" do
    # 【重要度：最高】
    # 「同じユーザーが同じ習慣を同じ日に2回記録できない」というビジネスルールを
    # DBレベルで強制する。
    # アプリのバリデーションだけでは同時リクエストで突破されることがあるが、
    # DBのUNIQUE制約があれば必ずどちらかがエラーになり2重記録を防げる。
    assert connection.index_exists?(
      :habit_records,
      [:user_id, :habit_id, :record_date],
      unique: true
    ), "habit_records に (user_id, habit_id, record_date) の UNIQUE 制約が必要です"
  end

  # ============================================================
  # tasks テーブルのインデックス確認
  # ============================================================

  test "tasks に (user_id, status, due_date) の複合インデックスが存在する" do
    # 【重要度：高】
    # タスク一覧のフィルタリング（WHERE user_id=? AND status=0 ORDER BY due_date）
    # を高速化する既存インデックス。
    assert connection.index_exists?(:tasks, [:user_id, :status, :due_date]),
           "tasks に (user_id, status, due_date) の複合インデックスが必要です"
  end

  test "tasks に アクティブタスク用の複合部分インデックスが存在する" do
    # 【重要度：高】
    # ★ レビュー指摘①：tasks.deleted_at 単体では弱い → 複合部分INDEXに変更
    #
    # 実クエリ:
    #   WHERE user_id=? AND status=0 AND deleted_at IS NULL ORDER BY due_date
    # このクエリは (user_id, status, deleted_at, due_date) の複合インデックス +
    # WHERE deleted_at IS NULL の部分インデックスで最適化する。
    #
    # 【なぜ index_exists? ではなく find_index_by_name を使うのか】
    # 部分インデックスの WHERE 条件は index_exists? では検証できないため、
    # find_index_by_name でインデックスオブジェクトを取得して
    # where 属性を直接確認する。

    # まず名前でインデックスを探す
    idx = find_index_by_name(:tasks, "idx_tasks_active_tasks")

    # インデックス自体の存在確認
    assert idx.present?,
           "tasks に idx_tasks_active_tasks インデックスが必要です（#A-6で追加）"

    # 対象カラムの確認
    # idx.columns → ["user_id", "status", "deleted_at", "due_date"] のような配列
    assert_equal ["user_id", "status", "deleted_at", "due_date"],
                 idx.columns.map(&:to_s).sort == ["deleted_at", "due_date", "status", "user_id"] ? idx.columns.map(&:to_s) : idx.columns.map(&:to_s),
                 "idx_tasks_active_tasks のカラム構成が正しくありません"

    # WHERE条件（部分インデックス）の確認
    # idx.where → "deleted_at IS NULL" のような文字列
    assert idx.where&.include?("deleted_at IS NULL"),
           "idx_tasks_active_tasks に WHERE deleted_at IS NULL 条件が必要です"
  end

  test "tasks に (alarm_enabled, scheduled_at) の複合インデックスが存在する" do
    # 【重要度：中】
    # GoodJob がアラーム通知対象タスクを検索する
    # WHERE alarm_enabled=true AND scheduled_at<=? というクエリを高速化する。
    assert connection.index_exists?(:tasks, [:alarm_enabled, :scheduled_at]),
           "tasks に (alarm_enabled, scheduled_at) の複合インデックスが必要です"
  end

  # ============================================================
  # notification_logs テーブルのインデックス確認
  # ============================================================

  test "notification_logs に (user_id, created_at) の複合インデックスが存在する" do
    # 【重要度：高】
    # 通知履歴の取得・1日の送信回数チェックで使われる。
    assert connection.index_exists?(:notification_logs, [:user_id, :created_at]),
           "notification_logs に (user_id, created_at) の複合インデックスが必要です"
  end

  test "notification_logs に deep_link_url のインデックスが存在する" do
    # 【重要度：中】
    # ★ 今回のマイグレーション（#A-6）で追加したインデックス。
    # 通知種別ごとの遷移先分析クエリを高速化する。
    assert connection.index_exists?(:notification_logs, :deep_link_url),
           "notification_logs に deep_link_url のインデックスが必要です（#A-6で追加）"
  end

  # ============================================================
  # weekly_reflections テーブルの部分インデックス確認（強化版）
  # ============================================================

  test "weekly_reflections に (user_id, week_start_date) の UNIQUE 制約が存在する" do
    # 【重要度：最高】
    # 同じユーザーが同じ週に2つ振り返りを作れないようにするDB制約。
    assert connection.index_exists?(
      :weekly_reflections,
      [:user_id, :week_start_date],
      unique: true
    ), "weekly_reflections に (user_id, week_start_date) の UNIQUE 制約が必要です"
  end

  test "weekly_reflections に completed_at IS NOT NULL の部分インデックスが存在する" do
    # 【重要度：高】
    # ★ レビュー指摘⑦：部分INDEXはwhere条件まで検証する
    #
    # User#locked? と WeeklyReflectionsController が使う
    # WHERE user_id=? AND week_start_date=? AND completed_at IS NOT NULL
    # というクエリを高速化する部分インデックス。
    #
    # このインデックスは schema.rb に既に存在するが、
    # テストで「存在すること」を明示的に保証することで
    # 誰かが誤って rollback した場合でも即座に検知できる。

    idx = find_index_by_name(
      :weekly_reflections,
      "idx_weekly_reflections_user_week_completed"
    )

    # インデックスの存在確認
    assert idx.present?,
           "weekly_reflections に idx_weekly_reflections_user_week_completed が必要です"

    # WHERE条件（部分インデックス）の確認
    # idx.where は "completed_at IS NOT NULL" という文字列を返す
    assert idx.where&.include?("completed_at IS NOT NULL"),
           "idx_weekly_reflections_user_week_completed に WHERE completed_at IS NOT NULL 条件が必要です"
  end

  # ============================================================
  # users テーブルのインデックス確認
  # ============================================================

  test "users に (provider, uid) の UNIQUE 制約が存在する" do
    # 【重要度：高】
    # OmniAuth（Google/LINEログイン）で同じアカウントが重複登録されないようにする。
    assert connection.index_exists?(
      :users, [:provider, :uid], unique: true
    ), "users に (provider, uid) の UNIQUE 制約が必要です"
  end

  test "users に email の UNIQUE 制約が存在する" do
    # 【重要度：最高】
    # 同じメールアドレスで複数アカウントが作られることをDBレベルで防ぐ。
    assert connection.index_exists?(:users, :email, unique: true),
           "users に email の UNIQUE 制約が必要です"
  end
end