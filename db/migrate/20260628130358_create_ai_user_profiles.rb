# db/migrate/[タイムスタンプ]_create_ai_user_profiles.rb
#
# ==============================================================================
# H-8: ai_user_profiles テーブルの作成
# ==============================================================================
class CreateAiUserProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_user_profiles do |t|
      # ------------------------------------------------------------------
      # user_id: このプロファイルが属するユーザー
      #
      # 【重要: index: false を指定する理由】
      #   t.references はデフォルトで index: true を付ける。
      #   このあと add_index で UNIQUE インデックスを追加するため、
      #   t.references 側のインデックスを無効化する。
      #   そうしないと user_id に「通常インデックス」と「UNIQUEインデックス」の
      #   2つが作られ、PostgreSQL が重複インデックス警告を出す。
      #
      # foreign_key: true → users テーブルへの参照整合性を保証する
      # on_delete: :cascade → ユーザーが削除されたときプロファイルも自動削除
      # ------------------------------------------------------------------
      t.references :user,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: false  # ← 重複防止のため false を明示する

      # ------------------------------------------------------------------
      # habit_patterns: 習慣達成パターンの分析結果（JSONB）
      #
      # 【default: {}, null: false を付ける理由】
      #   サービス側で profile.habit_patterns[:strong] のように
      #   ハッシュとしてアクセスするため、nil だと NoMethodError になる。
      #   デフォルト値を {} にすることで、初回作成直後でも
      #   nil チェックなしに安全にアクセスできる。
      # ------------------------------------------------------------------
      t.jsonb :habit_patterns,   default: {}, null: false

      # reflection_trends / proposal_adoption も同じ理由で {} をデフォルトにする
      t.jsonb :reflection_trends, default: {}, null: false
      t.jsonb :proposal_adoption, default: {}, null: false

      # ------------------------------------------------------------------
      # context_summary: AIプロンプトに注入するテキスト（TEXT型）
      #
      # text 型を使う理由:
      #   string（255文字制限）ではプロンプト文として不足するため。
      #   将来 5000 文字超になった場合も truncate で対応できる。
      # ------------------------------------------------------------------
      t.text :context_summary

      # ------------------------------------------------------------------
      # analyzed_at: 最終分析日時
      #
      # null: true を明示する理由:
      #   初回作成時（まだ分析していない状態）は nil になる設計のため、
      #   null: true であることをコードに明示して意図を明確にする。
      # ------------------------------------------------------------------
      t.datetime :analyzed_at  # null: true が暗黙のデフォルト（意図通り）

      t.timestamps
    end

    # ------------------------------------------------------------------
    # UNIQUE インデックス（1ユーザーに1プロファイルのみ許可）
    #
    # t.references 側で index: false にしたため、
    # ここの add_index だけが user_id に対するインデックスになる。
    # unique: true で DB レベルの重複防止も同時に実現する。
    # ------------------------------------------------------------------
    add_index :ai_user_profiles,
              :user_id,
              unique: true,
              name: "index_ai_user_profiles_on_user_id_unique"

    # ------------------------------------------------------------------
    # analyzed_at インデックス
    #
    # UpdateAiProfileJob の全ユーザー週次更新時に
    # 「7日以上前のプロファイル」を絞り込むクエリを高速化する。
    # ------------------------------------------------------------------
    add_index :ai_user_profiles,
              :analyzed_at,
              name: "index_ai_user_profiles_on_analyzed_at"
  end
end