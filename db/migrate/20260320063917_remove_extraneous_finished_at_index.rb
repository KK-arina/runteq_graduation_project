# ==============================================================================
# db/migrate/20260320063917_remove_extraneous_finished_at_index.rb
# ==============================================================================
#
# 【このマイグレーションの役割】
# GoodJob 4.x へのアップグレード時に good_job:update コマンドで自動生成された。
# good_jobs テーブルの不要な finished_at インデックスを削除する。
#
# 【経緯】
# good_job:update → 自動生成
# 一時的にファイルを削除 → schema_migrations に実行済み記録が残存
# ファイルを復元して schema_migrations の記録と整合させる
# ==============================================================================
class RemoveExtraneousFinishedAtIndex < ActiveRecord::Migration[7.2]
  def change
    # GoodJob 4.x では不要になった finished_at インデックスを削除する
    # if_exists: true → インデックスが存在しない場合もエラーにならない
    remove_index :good_jobs, name: :index_good_jobs_on_finished_at, if_exists: true
  end
end