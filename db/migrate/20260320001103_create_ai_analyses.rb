# db/migrate/YYYYMMDDHHMMSS_create_ai_analyses.rb
#
# ==============================================================================
# 【このマイグレーションの目的】
# ai_analyses テーブルを新規作成する。
#
# 【このテーブルの役割】
# AI（Gemini API など）による分析結果を保存するテーブル。
# 週次振り返り分析と PMVV 目標分析の2種類を管理する。
#
# 【analysis_type（分析種別）の値】
#   0: weekly_reflection   → 週次振り返りに基づく AI 分析
#   1: purpose_breakdown   → PMVV 目標に基づく AI 分析
#   2: monthly_review      → 月次レビュー（将来拡張用）
#
# 【input_snapshot とは？】
# 分析実行時点の入力データ（PMVV や振り返りコメント）を JSON 形式でそのまま保存する。
# 後から PMVV を更新しても「あのとき何を入力して分析したか」を正確に再現できる。
#
# 【actions_json とは？】
# AI が提案する「来週の改善アクション」を JSON 形式で保存する。
# 例: [{"type": "habit", "name": "就寝ルーティン", "reason": "..."}, ...]
# ==============================================================================

class CreateAiAnalyses < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_analyses do |t|
      # ─────────────────────────────────────────────────────────────────────
      # weekly_reflection_id: 関連する週次振り返り（オプション）
      # ─────────────────────────────────────────────────────────────────────
      # analysis_type = 0（週次振り返り分析）のときに使用する
      # null: true → PMVV 分析の場合は振り返りと紐づかないため NULL 許可
      # on_delete: :cascade → 振り返りが削除されたら分析結果も一緒に削除
      # index: false → 後で個別にインデックスを追加するため自動生成を抑制
      t.references :weekly_reflection,
                   null: true,
                   foreign_key: { on_delete: :cascade },
                   index: false

      # ─────────────────────────────────────────────────────────────────────
      # user_purpose_id: 関連する PMVV 目標（オプション）
      # ─────────────────────────────────────────────────────────────────────
      # analysis_type = 1（PMVV 分析）のときに使用する
      # null: true → 週次振り返り分析の場合は NULL
      # on_delete: :cascade → PMVV が削除されたら分析結果も一緒に削除
      # bigint 型: id カラムは bigint（大きな整数）が Rails のデフォルト
      t.bigint :user_purpose_id

      # ─────────────────────────────────────────────────────────────────────
      # analysis_type: 分析の種類
      # ─────────────────────────────────────────────────────────────────────
      # integer 型: Rails の enum で管理する（0: 週次 / 1: PMVV / 2: 月次）
      # default: 0 → デフォルトは週次振り返り分析
      # null: false → 必須項目
      t.integer :analysis_type, null: false, default: 0

      # ─────────────────────────────────────────────────────────────────────
      # input_snapshot: 分析実行時の入力データのスナップショット
      # ─────────────────────────────────────────────────────────────────────
      # jsonb 型: JSON をバイナリ形式で保存する PostgreSQL 専用の型
      # 【jsonb の利点】
      #   - JSON データを保存・検索できる
      #   - バイナリ形式なので検索が高速
      #   - インデックスも作成できる（text 型の JSON より優秀）
      # 分析時点の PMVV や振り返りコメントを丸ごと保存する
      t.jsonb :input_snapshot

      # ─────────────────────────────────────────────────────────────────────
      # analysis_comment: AI の全体的な分析コメント
      # ─────────────────────────────────────────────────────────────────────
      # text 型: 長い文章を保存できる
      # NULL 許可: 分析が失敗した場合などは NULL になることがある
      t.text :analysis_comment

      # ─────────────────────────────────────────────────────────────────────
      # improvement_suggestions: 改善提案のテキスト（全体サマリー）
      # ─────────────────────────────────────────────────────────────────────
      # text 型: NULL 許可
      t.text :improvement_suggestions

      # ─────────────────────────────────────────────────────────────────────
      # root_cause: 真の原因（Why×3 の分析結果）
      # ─────────────────────────────────────────────────────────────────────
      # AI が「なぜ習慣が続かないか」を3回 Why を繰り返して導き出した根本原因
      # text 型: NULL 許可
      t.text :root_cause

      # ─────────────────────────────────────────────────────────────────────
      # coaching_message: AI からのコーチングメッセージ
      # ─────────────────────────────────────────────────────────────────────
      # ユーザーを励ます・具体的なアドバイスをするメッセージ
      # text 型: NULL 許可
      t.text :coaching_message

      # ─────────────────────────────────────────────────────────────────────
      # actions_json: AI が提案する具体的なアクション（JSON 形式）
      # ─────────────────────────────────────────────────────────────────────
      # jsonb 型: 提案する習慣・タスクのリストを JSON で保存する
      # 例: {"habits": [...], "tasks": [...], "habit_changes": [...]}
      t.jsonb :actions_json

      # ─────────────────────────────────────────────────────────────────────
      # crisis_detected: 危機ワード検出フラグ
      # ─────────────────────────────────────────────────────────────────────
      # true  → 振り返りコメントに「死にたい」などの危機ワードを検出した
      #         この場合は AI 分析をスキップし、支援窓口を表示する
      # false → 危機ワードなし（通常の分析を実行する）
      # boolean 型
      # default: false → デフォルトは危機なし
      # null: false → NULL は不可
      t.boolean :crisis_detected, null: false, default: false

      # ─────────────────────────────────────────────────────────────────────
      # prompt_version: 使用したプロンプトのバージョン
      # ─────────────────────────────────────────────────────────────────────
      # プロンプトを改善したときに「どのバージョンで分析したか」を記録する
      # 例: 'v1.0' / 'v1.2'
      # string 型: NULL 許可
      t.string :prompt_version

      # ─────────────────────────────────────────────────────────────────────
      # model_name: 使用した AI モデル名
      # ─────────────────────────────────────────────────────────────────────
      # 例: 'gemini-2.5-flash' / 'llama-3.3-70b-versatile'（Groq）
      # string 型: NULL 許可
      t.string :model_name

      # ─────────────────────────────────────────────────────────────────────
      # metadata: API レスポンスの詳細情報（JSON 形式）
      # ─────────────────────────────────────────────────────────────────────
      # トークン数・処理時間・エラー情報などを保存するデバッグ用フィールド
      # jsonb 型: NULL 許可
      t.jsonb :metadata

      # created_at・updated_at を自動で追加する
      t.timestamps
    end

    # ─────────────────────────────────────────────────────────────────────────
    # 外部キー制約の追加
    # ─────────────────────────────────────────────────────────────────────────

    # user_purpose_id への外部キー制約を手動で追加
    # （t.references を使わなかったため、別途 add_foreign_key で追加する）
    # user_purposes テーブルが後のマイグレーションで作成されるため、
    # ここでは外部キーを追加しない（user_purposes の CREATE より先に実行されると失敗する）
    # ★ user_purposes テーブル作成後に別マイグレーションで追加するか、
    #   アプリ側でバリデーションにより整合性を保つ

    # ─────────────────────────────────────────────────────────────────────────
    # INDEX の追加
    # ─────────────────────────────────────────────────────────────────────────

    # weekly_reflection_id へのインデックス
    # 「この振り返りの AI 分析結果を取得する」クエリを高速化
    add_index :ai_analyses,
              :weekly_reflection_id,
              name: 'index_ai_analyses_on_weekly_reflection_id'

    # user_purpose_id へのインデックス
    # 「この PMVV の AI 分析結果を取得する」クエリを高速化
    add_index :ai_analyses,
              :user_purpose_id,
              name: 'index_ai_analyses_on_user_purpose_id'

    # analysis_type へのインデックス
    # 「週次分析だけ取得する」「PMVV 分析だけ取得する」クエリを高速化
    add_index :ai_analyses,
              :analysis_type,
              name: 'index_ai_analyses_on_analysis_type'

    # ─────────────────────────────────────────────────────────────────────────
    # UNIQUE 制約の追加（2種類）
    # ─────────────────────────────────────────────────────────────────────────

    # UNIQUE 制約 1: (weekly_reflection_id)
    # 1つの振り返りに対して AI 分析は1件のみ作成できる（二重実行防止）
    # NULL は UNIQUE 制約から除外される（PMVV 分析のレコードは NULL なので問題なし）
    add_index :ai_analyses,
              :weekly_reflection_id,
              unique: true,
              where: 'weekly_reflection_id IS NOT NULL',
              name: 'index_ai_analyses_on_weekly_reflection_id_unique'

    # UNIQUE 制約 2: (user_purpose_id, analysis_type)
    # 同じ PMVV に対して同じ分析種別が重複して作成されることを防ぐ
    add_index :ai_analyses,
              [ :user_purpose_id, :analysis_type ],
              unique: true,
              where: 'user_purpose_id IS NOT NULL',
              name: 'index_ai_analyses_on_purpose_and_type_unique'
  end
end
