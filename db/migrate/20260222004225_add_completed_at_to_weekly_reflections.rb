# ファイルパス: db/migrate/YYYYMMDDHHMMSS_add_completed_at_to_weekly_reflections.rb
#
# ⚠️ このファイルをそのままコピーしてはいけません。
# 以下のコマンドで正しいタイムスタンプ付きのファイルを生成してから、
# 中身だけをこのコードで置き換えてください：
#
#   docker compose exec web rails generate migration AddCompletedAtToWeeklyReflections
#
# 生成されたファイル名の例: db/migrate/20260222123456_add_completed_at_to_weekly_reflections.rb
# そのファイルをVSCodeで開いて、下記のコードで中身を丸ごと置き換えてください。
#
# ============================================================
# 【なぜこの migration が必要なのか？】
# ============================================================
#
# 現在の weekly_reflections テーブルには「振り返りをいつ完了したか」を
# 記録するカラムがありません。
#
# Issue #25 で実装した complete! メソッドは
# completed_at（完了日時）に現在時刻を保存することで「完了済み」を表します。
# このカラムが存在しないと、rails test や実際の動作でエラーが発生します。
#
# 【なぜ is_locked(boolean) を使わないのか？】
#
# schema.rb に is_locked カラムが既に存在しています。
# 「このカラムを使えばいいのでは？」と思うかもしれませんが、
# is_locked と completed_at は「役割が違う概念」です：
#
#   is_locked（boolean）= 「ユーザーが今ロック中かどうか」を表すフラグ
#                          → User モデルの locked? メソッドで計算している
#                          → 時間（月曜AM4:00以降か）との組み合わせで変わる
#                          → WeeklyReflection には本来不要なカラム（将来削除候補）
#
#   completed_at（datetime）= 「この振り返りをいつ完了したか」という事実の記録
#                              → 一度設定されたら変わらない（履歴として残る）
#                              → NULL = 未完了 / 時刻あり = 完了済み
#
# 「完了した事実」と「ロック状態」は別物として管理するのが
# 将来のバグを防ぐ正しい設計です。

class AddCompletedAtToWeeklyReflections < ActiveRecord::Migration[7.2]
  def change
    # add_column でカラムを追加する
    #
    # :weekly_reflections → 追加するテーブル名
    # :completed_at       → 追加するカラム名
    # :datetime           → データ型（日付と時刻を保存できる型）
    # default: nil        → デフォルト値は nil（未完了 = NULL）
    #
    # 【:datetime とは？】
    # 「2026-02-22 14:30:00」のように「日付 + 時刻」を保存できる型。
    # :date は日付のみ（「2026-02-22」）、:datetime は時刻まで保存できる。
    # 「いつ完了したか」を正確に記録したいので :datetime を使う。
    #
    # 【なぜ default: nil にするのか？】
    # 既存のレコード（過去に作成された振り返り）は「未完了扱い」にしたい。
    # default: nil にすることで、既存レコードの completed_at は NULL になる。
    # NULL = 未完了、時刻あり = 完了済み という設計を維持できる。
    add_column :weekly_reflections, :completed_at, :datetime, default: nil
  end
end
