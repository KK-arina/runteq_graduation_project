# db/migrate/20260324000000_add_next_action_to_weekly_reflections.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
#   リフレクション学習法の「からの？（Next）」に対応するカラムを
#   weekly_reflections テーブルに追加する。
#
# 【背景】
#   週次振り返りフォームに3つのリフレクション項目を実装するにあたり、
#   「なぜ？」→ direct_reason   （既存カラム）
#   「どう？」→ background_situation（既存カラムを流用・意味変更）
#   「からの？」→ next_action    （このマイグレーションで追加）
#   の3カラム体制にする。
#
# 【なぜ background_situation を再利用するのか？】
#   既存マイグレーションを変更するルールがあるため、
#   background_situation カラムのリネームは行わない。
#   View 側のラベルだけ「どう？（改善策）」に変更することで対応する。
#
# 【注意: db:migrate を使うこと】
#   Neon Serverless PostgreSQL では CREATE DATABASE 権限がないため、
#   db:prepare は使用不可。必ず以下のコマンドを使う:
#   docker compose exec web bin/rails db:migrate
# ==============================================================================
class AddNextActionToWeeklyReflections < ActiveRecord::Migration[7.2]
  def change
    # next_action カラムを weekly_reflections テーブルに追加する
    #
    # 【型を text にする理由】
    #   string 型は最大255文字の制限があるが、振り返りのコメントは
    #   長文になる可能性があるため text 型（制限なし）を使う。
    #   direct_reason、background_situation、reflection_comment も
    #   同じく text 型で定義されている。
    #
    # 【null: true（デフォルト）にする理由】
    #   既存データへの影響を避けるため NOT NULL 制約は付けない。
    #   バリデーションはモデル側で「任意入力」として扱う（UI設計に合わせる）。
    #
    # 【after: :background_situation にする理由】
    #   カラムの並び順を UI の表示順（なぜ→どう→からの）に合わせる。
    #   PostgreSQL では after はサポートされないため、
    #   実際のカラム順序は DB ツールで確認すること（動作には影響なし）。
    add_column :weekly_reflections, :next_action, :text
  end
end
