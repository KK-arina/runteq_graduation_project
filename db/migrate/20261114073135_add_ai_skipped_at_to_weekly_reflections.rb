# db/migrate/XXXXXXXXXXXXXX_add_ai_skipped_at_to_weekly_reflections.rb
#
# ==============================================================================
# weekly_reflections に ai_skipped_at（AI分析をしなかった日時）を追加する
# ==============================================================================
# 【なぜ必要か】
#   AI分析の結果（ai_analyses）が無い振り返りが、
#     ・AI分析を待っている途中なのか
#     ・最初から AI分析をしないで完了したのか
#   を区別できず、「AI分析中です…」が出たままになっていた。
#   AI分析をしなかったときにこの列へ日時を入れて、区別できるようにする。
#
# 【null を許す理由】
#   AI分析を行う通常の振り返りでは値が入らない（nil のまま）。
#   既存のデータも nil のままで問題ない。
#
# 【インデックスを付けない理由】
#   この列で検索・並び替えはしない（取得済みの振り返りの値を見るだけ）。
# ==============================================================================
class AddAiSkippedAtToWeeklyReflections < ActiveRecord::Migration[8.1]
  def change
    add_column :weekly_reflections, :ai_skipped_at, :datetime
  end
end