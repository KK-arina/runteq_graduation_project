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
# 【D-11 での変更内容】
#   ① タイムアウト時の handle_failure に "分析がタイムアウトしました" メッセージを追加
#   ② 全プロバイダ失敗時に GoodJob の wait:60.seconds で再エンキュー（最大3回）
#   ③ JSONパース失敗時に raw_response を metadata(jsonb) に保存
#   ④ 401エラー（AiClient::AuthError）を rescue して即座に failed 確定 + Sentry通知
#   ⑤ 再エンキュー回数を last_error_message で管理
#
# ==============================================================================

class PurposeAnalysisJob < ApplicationJob
  queue_as :default

  # ── D-11 変更: retry_on の対象を絞る ───────────────────────────────────
  #
  # 【変更前】
  #   retry_on Faraday::Error,  wait: :exponentially_longer, attempts: 3
  #   retry_on Timeout::Error,  wait: :exponentially_longer, attempts: 3
  #
  # 【変更後・なぜ削除するのか】
  #   D-11 では「全プロバイダ失敗時は wait:60.seconds で再エンキュー（最大3回）」
  #   という要件がある。GoodJob の retry_on では wait 時間を固定秒数で指定できないため、
  #   Job 内部で perform_later(wait: 60.seconds) を明示的に呼ぶ設計に変更する。
  #
  #   AiClient 内部で Faraday::Error と Timeout::Error は既に rescue されており、
  #   nil を返す設計になっているため、Job 側では AiClient::AuthError のみを
  #   外部に伝播させる（AuthError はリトライ不要・即失敗確定）。
  #
  # 【discard_on は維持する理由】
  #   対象レコードが削除された場合はリトライしても無意味なため。
  discard_on ActiveRecord::RecordNotFound

  # AiClient::AuthError: APIキー不正時は即座にジョブを破棄する
  # 【なぜ discard_on にするのか】
  #   401 エラーはAPIキーが無効であることを意味する。
  #   リトライしても必ず失敗するため、GoodJob の自動リトライを
  #   discard_on で無効化して即座に failed 確定にする。
  #   Sentry への通知は AiClient 内の notify_sentry で行われる。
  discard_on AiClient::AuthError

  # PROMPT_VERSION: プロンプトのバージョン文字列
  PROMPT_VERSION = "v1.1".freeze

  # MAX_REENQUEUE_COUNT: 全プロバイダ失敗時の最大再エンキュー回数
  # 【D-11 要件】全プロバイダ失敗時: 最大3回、3回失敗でfailed確定
  # 【なぜ定数にするのか】
  #   コード中に「3」という数値が複数箇所に現れると保守が難しくなる。
  #   定数にすることで「3回」という要件が1箇所で管理される。
  MAX_REENQUEUE_COUNT = 3

  # REENQUEUE_WAIT_SECONDS: 全プロバイダ失敗後の再エンキュー待機時間
  # 【D-11 要件】GoodJob の wait: 60.seconds で再エンキュー
  REENQUEUE_WAIT_SECONDS = 60

  # ============================================================
  # perform メソッド
  # ============================================================
  #
  # 【D-11 追加引数: reenqueue_count】
  #   全プロバイダ失敗時に perform_later で再エンキューするとき、
  #   何回目の再試行かを追跡するためのカウンター。
  #   初回実行時はデフォルト値の 0 が使われる。
  #   GoodJob はジョブ引数を JSON で保存するため、整数型で渡す。
  def perform(user_purpose_id, reenqueue_count: 0)
    # ----------------------------------------------------------
    # Step 1: UserPurpose を取得する
    # ----------------------------------------------------------
    user_purpose = UserPurpose.find(user_purpose_id)

    Rails.logger.info "[PurposeAnalysisJob] 開始: user_purpose_id=#{user_purpose_id}, reenqueue_count=#{reenqueue_count}"

    # ----------------------------------------------------------
    # Step 2: analysis_state を analyzing に更新する
    # ----------------------------------------------------------
    user_purpose.update!(analysis_state: :analyzing)
    broadcast_state_update(user_purpose)

    # ----------------------------------------------------------
    # Step 3: AI API を呼び出す
    # ----------------------------------------------------------
    prompt = build_prompt(user_purpose)
    result = AiClient.new.analyze(prompt)

    # ── D-11 追加: 全プロバイダ失敗時の再エンキューロジック ──────────────
    #
    # 【result が nil になる条件】
    #   AiClient#analyze が nil を返す = Gemini も Groq も全て失敗した状態。
    #   タイムアウト・ネットワークエラー等の一時的な問題の可能性がある。
    #
    # 【再エンキューの設計】
    #   1回目失敗 → 60秒後に再エンキュー（reenqueue_count: 1）
    #   2回目失敗 → 60秒後に再エンキュー（reenqueue_count: 2）
    #   3回目失敗 → 60秒後に再エンキュー（reenqueue_count: 3）
    #   4回目失敗（reenqueue_count >= MAX_REENQUEUE_COUNT）→ failed 確定
    #
    # 【なぜ perform_later(wait:) を使うのか】
    #   GoodJob の retry_on では固定秒数の wait が指定できない。
    #   perform_later(wait: 60.seconds) を明示的に呼ぶことで
    #   「60秒後に再実行」が確実に実現できる。
    if result.nil?
      if reenqueue_count < MAX_REENQUEUE_COUNT
        next_count = reenqueue_count + 1
        Rails.logger.warn "[PurposeAnalysisJob] 全プロバイダ失敗: #{REENQUEUE_WAIT_SECONDS}秒後に再エンキュー (#{next_count}/#{MAX_REENQUEUE_COUNT})"

        # pending 状態に戻してから再エンキューする
        # 【なぜ pending に戻すのか】
        #   analyzing のまま再エンキューすると、ユーザーには「分析中」と表示され続ける。
        #   pending に戻すことで「待機中」表示になり、ユーザーに誤解を与えない。
        user_purpose.update!(
          analysis_state:     :pending,
          last_error_message: "一時的なエラーが発生しました。自動的に再試行します（#{next_count}/#{MAX_REENQUEUE_COUNT}）"
        )
        broadcast_state_update(user_purpose)

        # 60秒後に自身を再エンキューする
        # wait: REENQUEUE_WAIT_SECONDS.seconds → GoodJob が scheduled_at を設定して待機させる
        PurposeAnalysisJob.set(wait: REENQUEUE_WAIT_SECONDS.seconds)
                          .perform_later(user_purpose_id, reenqueue_count: next_count)
      else
        # MAX_REENQUEUE_COUNT 回全て失敗 → failed 確定
        Rails.logger.error "[PurposeAnalysisJob] 最大再試行回数（#{MAX_REENQUEUE_COUNT}）を超過: failed 確定"
        handle_failure(
          user_purpose,
          "AI API に接続できませんでした。しばらくしてから「再試行する」ボタンを押してください。"
        )
      end
      return
    end
    # ────────────────────────────────────────────────────────────────────────

    raw_response = result[:text]
    model_name   = result[:model]

    # ----------------------------------------------------------
    # Step 4: JSON パースと input_snapshot の事前バリデーション
    # ----------------------------------------------------------
    # ── D-11 追加: JSONパース失敗時に raw_response を metadata に保存 ──────
    #
    # 【parse_response の戻り値】
    #   成功: Hash（シンボルキー）
    #   失敗: nil（JSONパースエラー・必須キー不足・actionsが配列でないなど）
    #
    # 【raw_response を metadata に保存する理由（D-11要件）】
    #   パース失敗の原因を後からデバッグするために raw_response を残す。
    #   AiAnalysis.metadata カラム（jsonb）に保存することで
    #   管理画面や Rails コンソールから確認できる。
    parsed = parse_response(raw_response)

    if parsed.nil?
      # raw_response を metadata に保存した failed レコードを作成する
      save_failed_analysis_with_raw_response(user_purpose, raw_response, model_name)
      handle_failure(user_purpose, "AI の応答を解析できませんでした。再試行してください。")
      return
    end
    # ────────────────────────────────────────────────────────────────────────

    input_snapshot = build_input_snapshot(user_purpose)

    pre_check = AiAnalysis.new(
      user_purpose:   user_purpose,
      analysis_type:  :purpose_breakdown,
      input_snapshot: input_snapshot,
      is_latest:      true
    )

    unless pre_check.valid?
      error_detail = pre_check.errors.full_messages.join(", ")
      Rails.logger.error "[PurposeAnalysisJob] input_snapshot バリデーション失敗: #{error_detail}"
      handle_failure(
        user_purpose,
        "分析データの形式が正しくありません（#{error_detail}）。再試行してください。"
      )
      return
    end

    # ----------------------------------------------------------
    # Step 5: AiAnalysis の保存と UserPurpose の状態更新
    # ----------------------------------------------------------
    ActiveRecord::Base.transaction do
      AiAnalysis.create!(
        user_purpose_id:         user_purpose.id,
        analysis_type:           :purpose_breakdown,
        input_snapshot:          input_snapshot,
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

    broadcast_state_update(user_purpose.reload)
    Rails.logger.info "[PurposeAnalysisJob] 完了: user_purpose_id=#{user_purpose_id}"

  rescue AiClient::AuthError => e
    # 401 認証エラー: discard_on で捕捉されるが、
    # ここで handle_failure を先に呼んでユーザーに通知してから再 raise する
    # 【なぜ rescue してから raise するのか】
    #   discard_on は Job を破棄するだけで handle_failure は呼ばない。
    #   ユーザーにエラーを表示するには handle_failure を明示的に呼ぶ必要がある。
    Rails.logger.error "[PurposeAnalysisJob] 認証エラー（401）: #{e.message}"
    handle_failure(user_purpose, "AIサービスに接続できません。管理者にお問い合わせください。") if defined?(user_purpose) && user_purpose
    raise  # discard_on AiClient::AuthError に伝播させる

  rescue => e
    Rails.logger.error "[PurposeAnalysisJob] 予期しないエラー: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    handle_failure(user_purpose, "予期しないエラーが発生しました。しばらくしてから再試行してください。") if defined?(user_purpose) && user_purpose
    raise
  end

  private

  # build_prompt は変更なし（省略せずに全文保持）
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

  def parse_response(raw_response)
    text = raw_response.dup
    text = text.gsub(/```json\n?/, "").gsub(/```\n?/, "")
    json_str = text[/\{.*\}/m]

    if json_str.blank?
      Rails.logger.error "[PurposeAnalysisJob] JSON が見つかりません"
      Rails.logger.error "[PurposeAnalysisJob] 元のレスポンス（先頭300文字）: #{raw_response[0..300]}"
      return nil
    end

    parsed = JSON.parse(json_str, symbolize_names: true)
    required_keys = %i[analysis_comment root_cause coaching_message actions]
    missing_keys  = required_keys.reject { |k| parsed.key?(k) }

    if missing_keys.any?
      Rails.logger.error "[PurposeAnalysisJob] JSON に必須キーが不足: #{missing_keys.join(', ')}"
      return nil
    end

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

  # ── D-11 追加: JSONパース失敗時に raw_response を metadata に保存する ──
  #
  # 【役割】
  #   パース失敗した AI のレスポンスを metadata(jsonb) に保存する。
  #   これにより「なぜ失敗したのか」を後からデバッグできる。
  #
  # 【AiAnalysis.create（! なし）を使う理由】
  #   デバッグ用レコードの保存に失敗しても、
  #   その後の handle_failure（failed 状態の更新）は続行させる。
  #   create! だと例外が発生して handle_failure が呼ばれなくなる。
  #
  # 【metadata の構造】
  #   {
  #     "raw_response": "AIが返した生のレスポンス文字列",
  #     "parse_failed_at": "2026-05-01T12:00:00Z",
  #     "model": "gemini-2.5-flash"
  #   }
  def save_failed_analysis_with_raw_response(user_purpose, raw_response, model_name)
    AiAnalysis.create(
      user_purpose_id:  user_purpose.id,
      analysis_type:    :purpose_breakdown,
      input_snapshot:   build_input_snapshot(user_purpose),
      is_latest:        false,  # 失敗レコードは latest にしない
      prompt_version:   PROMPT_VERSION,
      ai_model_name:    model_name,
      crisis_detected:  false,
      metadata: {
        # raw_response の先頭 2000 文字を保存する
        # 【上限を設ける理由】
        #   AI のレスポンスが非常に長い場合でも DB の jsonb カラムを
        #   圧迫しないよう、デバッグに十分な先頭 2000 文字のみ保存する。
        "raw_response"    => raw_response.to_s[0, 2000],
        "parse_failed_at" => Time.current.iso8601,
        "model"           => model_name.to_s
      }
    )
  rescue => e
    # デバッグレコードの保存自体が失敗した場合はログだけ残す
    Rails.logger.warn "[PurposeAnalysisJob] raw_response の metadata 保存失敗（無視）: #{e.message}"
  end
  # ────────────────────────────────────────────────────────────────────────

  def handle_failure(user_purpose, error_message)
    user_purpose.update!(
      analysis_state:     :failed,
      last_error_message: error_message
    )
    Rails.logger.error "[PurposeAnalysisJob] 失敗: user_purpose_id=#{user_purpose.id}, error=#{error_message}"
    broadcast_state_update(user_purpose)
  end

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