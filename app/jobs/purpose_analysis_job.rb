# app/jobs/purpose_analysis_job.rb
#
# ==============================================================================
# PurposeAnalysisJob（PMVV AI分析ジョブ）
# ==============================================================================
#
# 【このファイルの役割】
#   UserPurpose が保存された後に GoodJob によって非同期実行される。
#   PMVV データを Gemini API に送信して分析結果を取得し、
#   ai_analyses テーブルに保存する。
#   analysis_state を pending → analyzing → completed/failed に遷移させ、
#   Turbo Stream でフロントエンドをリアルタイム更新する。
#
# 【D-9 での変更内容】
#   ① Step 4 に input_snapshot の事前バリデーションチェックを追加
#      - build_input_snapshot で生成したスナップショットを
#        AiAnalysis.new で事前にバリデーションし、
#        失敗した場合は handle_failure して早期リターンする
#      - これにより「Gemini APIのレスポンスパース後・DB保存前に必ずバリデーションを通過」
#        という要件を満たす
#
# ==============================================================================

class PurposeAnalysisJob < ApplicationJob
  queue_as :default

  # retry_on: 通信エラーのみリトライする
  # 【なぜ Faraday::Error と Timeout::Error だけか】
  #   JSON パースエラーやロジックエラーをリトライしても無意味なため、
  #   ネットワーク系エラーのみを対象にする。
  retry_on Faraday::Error,  wait: :exponentially_longer, attempts: 3
  retry_on Timeout::Error,  wait: :exponentially_longer, attempts: 3

  # discard_on: 対象レコードが削除された場合はジョブを静かに破棄する
  discard_on ActiveRecord::RecordNotFound

  # PROMPT_VERSION: プロンプトのバージョン文字列
  # プロンプトを改善したときにバージョンを上げることで
  # どのプロンプトで生成した分析かを追跡できる
  PROMPT_VERSION = "v1.1".freeze

  # ============================================================
  # perform メソッド
  # ============================================================
  def perform(user_purpose_id)
    # ----------------------------------------------------------
    # Step 1: UserPurpose を取得する
    # ----------------------------------------------------------
    # find: 存在しない場合は RecordNotFound → discard_on で静かに破棄
    user_purpose = UserPurpose.find(user_purpose_id)

    Rails.logger.info "[PurposeAnalysisJob] 開始: user_purpose_id=#{user_purpose_id}"

    # ----------------------------------------------------------
    # Step 2: analysis_state を analyzing に更新する
    # ----------------------------------------------------------
    # update! を使う理由:
    #   update_columns はバリデーション・コールバックをスキップするため
    #   将来コールバックを追加したときに状態不整合が起きる危険がある。
    #   update! を使うことでバリデーションが通る。
    user_purpose.update!(analysis_state: :analyzing)

    # Turbo Stream で「分析中」状態を UI に反映する
    broadcast_state_update(user_purpose)

    # ----------------------------------------------------------
    # Step 3: AI API を呼び出す
    # ----------------------------------------------------------
    prompt = build_prompt(user_purpose)
    result = AiClient.new.analyze(prompt)

    # result が nil の場合: 全プロバイダ失敗
    if result.nil?
      handle_failure(user_purpose, "AI API に接続できませんでした。しばらくしてから再試行してください。")
      return
    end

    raw_response = result[:text]
    model_name   = result[:model]

    # ----------------------------------------------------------
    # Step 4: JSON パースと input_snapshot の事前バリデーション
    # ----------------------------------------------------------
    parsed = parse_response(raw_response)

    if parsed.nil?
      handle_failure(user_purpose, "AI の応答を解析できませんでした。再試行してください。")
      return
    end

    # ── D-9 追加: input_snapshot のスキーマを DB保存前に事前検証する ──────────
    #
    # 【なぜここで事前バリデーションするか】
    #   AiAnalysis.create! 時にもバリデーションが走るが、
    #   create! でバリデーションエラーが発生すると ActiveRecord::RecordInvalid が
    #   raise される。rescue => e でキャッチしてジョブ全体を raise し直すと
    #   GoodJob が「予期しないエラー」として扱い、user_purpose の状態が
    #   analyzing のまま stuck する可能性がある。
    #   create! の前に明示的に valid? チェックすることで確実に handle_failure を呼び、
    #   画面を正しく「失敗」状態に遷移させる。
    #
    # 【AiAnalysis.new で valid? を実行する理由】
    #   実際の保存（create!）と同じバリデーションロジックを使うことで
    #   「モデルのバリデーションと事前チェックの乖離」を防ぐ。
    #   将来バリデーションを変更しても両方に自動で反映される。
    input_snapshot = build_input_snapshot(user_purpose)

    # AiAnalysis.new で仮インスタンスを作成してバリデーションのみ実行する
    # 【仮インスタンスを使う理由】
    #   save! や create! をせずにバリデーションだけを実行できる。
    #   DB には何も書き込まれないため安全。
    pre_check = AiAnalysis.new(
      user_purpose:   user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: input_snapshot,
      is_latest:      true
    )

    # valid? メソッドでバリデーションを実行する
    # 【true の場合】全バリデーション通過 → 処理を続行する
    # 【false の場合】バリデーションエラーあり → handle_failure して早期リターン
    unless pre_check.valid?
      # errors.full_messages: ["PMVV分析データ に必須キーが不足しています: purpose"] のような配列
      # join(', ') で1つの文字列に結合して last_error_message に保存する
      error_detail = pre_check.errors.full_messages.join(", ")

      Rails.logger.error "[PurposeAnalysisJob] input_snapshot バリデーション失敗: #{error_detail}, user_purpose_id=#{user_purpose_id}"

      handle_failure(
        user_purpose,
        "分析データの形式が正しくありません（#{error_detail}）。再試行してください。"
      )
      return
    end

    Rails.logger.info "[PurposeAnalysisJob] input_snapshot バリデーション通過: user_purpose_id=#{user_purpose_id}"
    # ──────────────────────────────────────────────────────────────────────────

    # ----------------------------------------------------------
    # Step 5: AiAnalysis の保存と UserPurpose の状態更新
    # ----------------------------------------------------------
    ActiveRecord::Base.transaction do
      AiAnalysis.create!(
        user_purpose_id:         user_purpose.id,
        analysis_type:           :purpose_breakdown,
        input_snapshot:          input_snapshot,  # D-9: 事前検証済みの変数を使う（再計算しない）
        analysis_comment:        parsed[:analysis_comment],
        improvement_suggestions: parsed[:improvement_suggestions],
        root_cause:              parsed[:root_cause],
        coaching_message:        parsed[:coaching_message],
        actions_json:            parsed[:actions],
        crisis_detected:         parsed[:crisis_detected] || false,
        prompt_version:          PROMPT_VERSION,
        ai_model_name:           model_name,
        is_latest:               true
      )

      user_purpose.update!(
        analysis_state:     :completed,
        last_error_message: nil
      )
    end

    # ----------------------------------------------------------
    # Step 6: 完了状態を Turbo Stream で通知する
    # ----------------------------------------------------------
    # transaction 完了後に broadcast する
    # 【理由】DB コミット前に UI が更新されることを防ぐ
    broadcast_state_update(user_purpose.reload)

    Rails.logger.info "[PurposeAnalysisJob] 完了: user_purpose_id=#{user_purpose_id}"

  rescue => e
    Rails.logger.error "[PurposeAnalysisJob] 予期しないエラー: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    handle_failure(user_purpose, "予期しないエラーが発生しました。しばらくしてから再試行してください。") if defined?(user_purpose) && user_purpose
    raise
  end

  private

  # ----------------------------------------------------------
  # build_prompt(user_purpose)
  # ----------------------------------------------------------
  # Chain-of-Thought 3ステップのプロンプト
  def build_prompt(user_purpose)
    <<~PROMPT
      あなたは優秀なライフコーチです。
      ユーザーの PMVV（Purpose/Mission/Vision/Value/Current）を分析し、
      具体的なアドバイスを提供してください。

      ## ユーザーの PMVV 情報

      **Purpose（人生で大切にしていること）:**
      #{user_purpose.purpose.presence || "未入力"}

      **Mission（今最も必要なこと）:**
      #{user_purpose.mission.presence || "未入力"}

      **Vision（1年後の理想の自分）:**
      #{user_purpose.vision.presence || "未入力"}

      **Value（絶対に譲れないこと）:**
      #{user_purpose.value.presence || "未入力"}

      **Current（今の自分の現状）:**
      #{user_purpose.current_situation.presence || "未入力"}

      ## 分析の指示（Chain-of-Thought）

      以下の3ステップで深く考えてから回答してください:

      **ステップ1（分析）:**
      - Purpose・Mission・Vision・Value の整合性を確認する
      - Current（現状）と Vision（理想）のギャップを特定する
      - 目標達成を妨げている根本的な原因を「なぜ？」を3回繰り返して掘り下げる

      **ステップ2（コーチング）:**
      - ユーザーの強みと改善点を特定する
      - Value を守りながら Vision に近づく方法を考える
      - 励ましと具体的な行動指針を提供する

      **ステップ3（提案）:**
      - 今すぐ実行できる具体的な習慣を3つ提案する
      - 今すぐ取り組むべき具体的なタスクを3つ提案する
      - 各提案に「なぜそれが有効か」の理由を添える

      ## 回答フォーマット

      以下の JSON 形式のみで回答してください。
      JSON 以外の文章は一切含めないでください。
      コードブロック（```json）も不要です。
      { から始めて } で終わる JSON のみを返してください。

      {
        "analysis_comment": "PMVVの総合分析コメント（200〜400文字）",
        "root_cause": "現状とVisionのギャップの根本原因（Why×3の分析、150〜300文字）",
        "coaching_message": "励ましと具体的なアドバイス（150〜300文字）",
        "improvement_suggestions": "改善のための全体的な提案（100〜200文字）",
        "actions": [
          {
            "type": "habit",
            "title": "習慣名（20文字以内）",
            "description": "なぜこの習慣が有効か（50〜100文字）",
            "frequency": "毎日 or 週N回",
            "priority": "must or should or could"
          },
          {
            "type": "habit",
            "title": "習慣名（20文字以内）",
            "description": "なぜこの習慣が有効か（50〜100文字）",
            "frequency": "毎日 or 週N回",
            "priority": "must or should or could"
          },
          {
            "type": "habit",
            "title": "習慣名（20文字以内）",
            "description": "なぜこの習慣が有効か（50〜100文字）",
            "frequency": "毎日 or 週N回",
            "priority": "must or should or could"
          },
          {
            "type": "task",
            "title": "タスク名（30文字以内）",
            "description": "なぜこのタスクが有効か（50〜100文字）",
            "priority": "must or should or could"
          },
          {
            "type": "task",
            "title": "タスク名（30文字以内）",
            "description": "なぜこのタスクが有効か（50〜100文字）",
            "priority": "must or should or could"
          },
          {
            "type": "task",
            "title": "タスク名（30文字以内）",
            "description": "なぜこのタスクが有効か（50〜100文字）",
            "priority": "must or should or could"
          }
        ],
        "crisis_detected": false
      }

      【重要・安全ルール】
      - crisis_detected: 入力テキストに「死にたい」「消えたい」「消えてしまいたい」
        「死んでしまいたい」「いなくなりたい」「生きていたくない」「死ぬしかない」
        「遺書」「自殺」「リストカット」「過剰服薬」などの危機的なワードが含まれる場合のみ
        true にしてください。通常の落ち込みや失望の表現（「つらい」「疲れた」等）では
        true にしないでください。
      - 回答は必ず有効な JSON のみ。前後に説明文を付けないでください
      - 日本語で回答してください
    PROMPT
  end

  # ----------------------------------------------------------
  # parse_response(raw_response)
  # ----------------------------------------------------------
  # 【AI のレスポンスパターンへの対応】
  #   パターン①: 純粋な JSON のみ（理想）
  #   パターン②: ```json\n{...}\n``` （コードブロック付き）
  #   パターン③: "はい、分析結果です：\n{...}" （前置き文あり ← 高確率）
  #   パターン④: "{...}\n\n以上です。" （後置き文あり）
  def parse_response(raw_response)
    text = raw_response.dup

    # ① コードブロック記号を除去する
    text = text.gsub(/```json\n?/, "").gsub(/```\n?/, "")

    # ② { から } の範囲を正規表現で抽出する
    # /\{.*\}/m の m フラグ: . が改行にもマッチするようにする（複数行対応）
    json_str = text[/\{.*\}/m]

    if json_str.blank?
      Rails.logger.error "[PurposeAnalysisJob] JSON が見つかりません"
      Rails.logger.error "[PurposeAnalysisJob] 元のレスポンス（先頭300文字）: #{raw_response[0..300]}"
      return nil
    end

    # ③ JSON をパースしてシンボルキーの Hash に変換する
    parsed = JSON.parse(json_str, symbolize_names: true)

    # ④ 必須キーのバリデーション
    required_keys = %i[analysis_comment root_cause coaching_message actions]
    missing_keys  = required_keys.reject { |k| parsed.key?(k) }

    if missing_keys.any?
      Rails.logger.error "[PurposeAnalysisJob] JSON に必須キーが不足: #{missing_keys.join(', ')}"
      return nil
    end

    # ⑤ actions が配列かどうかをバリデーションする
    unless parsed[:actions].is_a?(Array)
      Rails.logger.error "[PurposeAnalysisJob] actions が配列ではありません: #{parsed[:actions].class}"
      return nil
    end

    parsed

  rescue JSON::ParserError => e
    Rails.logger.error "[PurposeAnalysisJob] JSON パース失敗: #{e.message}"
    Rails.logger.error "[PurposeAnalysisJob] 元のレスポンス（先頭500文字）: #{raw_response[0..500]}"
    nil
  end

  # ----------------------------------------------------------
  # build_input_snapshot(user_purpose)
  # ----------------------------------------------------------
  # 分析実行時の PMVV データのスナップショットを Hash で返す
  # 【as_json を使わない理由】
  #   不要なカラムまで含まれる。明示的に指定することで
  #   「意味のあるデータのみ」を保存できる。
  #
  # 【D-9 との関連】
  #   このメソッドが返す Hash のキーが input_snapshot_schema_valid で
  #   チェックされる5つの必須キーを含む必要がある。
  #   purpose / mission / vision / value / current_situation の5キーは
  #   全て含まれているため、バリデーションを通過できる。
  def build_input_snapshot(user_purpose)
    {
      purpose:           user_purpose.purpose,
      mission:           user_purpose.mission,
      vision:            user_purpose.vision,
      value:             user_purpose.value,
      current_situation: user_purpose.current_situation,
      version:           user_purpose.version,
      analyzed_at:       Time.current.iso8601
    }
  end

  # ----------------------------------------------------------
  # handle_failure(user_purpose, error_message)
  # ----------------------------------------------------------
  def handle_failure(user_purpose, error_message)
    user_purpose.update!(
      analysis_state:     :failed,
      last_error_message: error_message
    )

    Rails.logger.error "[PurposeAnalysisJob] 失敗: user_purpose_id=#{user_purpose.id}, error=#{error_message}"

    broadcast_state_update(user_purpose)
  end

  # ----------------------------------------------------------
  # broadcast_state_update(user_purpose)
  # ----------------------------------------------------------
  # Turbo Streams でブラウザの 16番ページをリアルタイム更新する
  def broadcast_state_update(user_purpose)
    ai_analysis = AiAnalysis.where(
      user_purpose_id: user_purpose.id,
      is_latest:       true,
      analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
    ).first

    Turbo::StreamsChannel.broadcast_replace_to(
      "user_purpose_#{user_purpose.id}",
      target:  "analysis_status_banner",
      partial: "user_purposes/analysis_status_banner",
      locals:  { user_purpose: user_purpose, ai_analysis: ai_analysis }
    )
  rescue => e
    Rails.logger.warn "[PurposeAnalysisJob] Turbo Stream 更新失敗（無視）: #{e.message}"
  end
end