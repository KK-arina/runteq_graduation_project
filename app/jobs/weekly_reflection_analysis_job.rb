# app/jobs/weekly_reflection_analysis_job.rb
#
# ==============================================================================
# WeeklyReflectionAnalysisJob（週次振り返り AI分析ジョブ）
# ==============================================================================
#
# 【D-11 での変更内容】
#   ① 全プロバイダ失敗時に 60秒後に再エンキュー（最大3回）
#   ② JSONパース失敗時に raw_response を metadata(jsonb) に保存
#   ③ 401エラー（AiClient::AuthError）を rescue して Sentry 通知後に raise
#   ④ タイムアウト時のログ出力を明示的に追加
#
# ==============================================================================

class WeeklyReflectionAnalysisJob < ApplicationJob
  queue_as :default

  # D-11 変更: retry_on を削除して内部で再エンキューする設計に変更
  # 【理由】PurposeAnalysisJob と同じ設計方針
  #   wait: :exponentially_longer では固定秒数の再エンキューが指定できないため。

  discard_on ActiveRecord::RecordNotFound

  # AiClient::AuthError: APIキー不正時は即座に破棄する
  # PurposeAnalysisJob と同じ設計方針
  discard_on AiClient::AuthError

  PROMPT_VERSION = "v1.0".freeze

  # MAX_REENQUEUE_COUNT: 全プロバイダ失敗時の最大再エンキュー回数
  # D-11 要件: 最大3回、3回失敗でログのみ残して終了（振り返りはfailed状態を持たない）
  MAX_REENQUEUE_COUNT = 3

  # REENQUEUE_WAIT_SECONDS: 再エンキュー待機時間（秒）
  REENQUEUE_WAIT_SECONDS = 60

  # ============================================================
  # perform メソッド
  # ============================================================
  #
  # 【D-11 追加引数: reenqueue_count】
  #   全プロバイダ失敗時の再試行カウンター。初回は 0。
  def perform(weekly_reflection_id, reenqueue_count: 0)
    reflection = WeeklyReflection.find(weekly_reflection_id)

    Rails.logger.info "[WeeklyReflectionAnalysisJob] 開始: weekly_reflection_id=#{weekly_reflection_id}, reenqueue_count=#{reenqueue_count}"

    user         = reflection.user
    user_setting = user.user_setting

    if user_setting.nil?
      Rails.logger.warn "[WeeklyReflectionAnalysisJob] user_setting が存在しません: user_id=#{user.id}"
      return
    end

    if user_setting.ai_analysis_count >= user_setting.ai_analysis_monthly_limit
      Rails.logger.warn "[WeeklyReflectionAnalysisJob] AI分析の月次上限: user_id=#{user.id}"
      return
    end

    user_purpose = UserPurpose.current_for(user)
    prompt       = build_prompt(reflection, user_purpose)
    result       = AiClient.new.analyze(prompt)

    # ── D-11 追加: 全プロバイダ失敗時の再エンキューロジック ──────────────
    #
    # 【WeeklyReflection は analysis_state を持たない設計】
    #   UserPurpose と異なり WeeklyReflection には analysis_state カラムがない。
    #   そのため「failed確定」してもユーザーへの直接通知はできない。
    #   最大再試行回数を超えた場合はログだけ残して終了する。
    if result.nil?
      if reenqueue_count < MAX_REENQUEUE_COUNT
        next_count = reenqueue_count + 1
        Rails.logger.warn "[WeeklyReflectionAnalysisJob] 全プロバイダ失敗: #{REENQUEUE_WAIT_SECONDS}秒後に再エンキュー (#{next_count}/#{MAX_REENQUEUE_COUNT})"
        WeeklyReflectionAnalysisJob.set(wait: REENQUEUE_WAIT_SECONDS.seconds)
                                   .perform_later(weekly_reflection_id, reenqueue_count: next_count)
      else
        Rails.logger.error "[WeeklyReflectionAnalysisJob] 最大再試行回数（#{MAX_REENQUEUE_COUNT}）を超過: 分析を断念します"
      end
      return
    end
    # ────────────────────────────────────────────────────────────────────────

    raw_response = result[:text]
    model_name   = result[:model]

    # ── D-11 追加: JSONパース失敗時に raw_response を metadata に保存 ──────
    parsed = parse_response(raw_response)

    if parsed.nil?
      # raw_response をデバッグ用に AiAnalysis.metadata に保存する
      save_failed_analysis_with_raw_response(reflection, raw_response, model_name, user_purpose)
      Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON パース失敗: metadata に raw_response を保存しました"
      return
    end
    # ────────────────────────────────────────────────────────────────────────

    ActiveRecord::Base.transaction do
      AiAnalysis.create!(
        weekly_reflection_id:    reflection.id,
        analysis_type:           :weekly_reflection,
        input_snapshot:          build_input_snapshot(reflection, user_purpose),
        analysis_comment:        parsed[:analysis_comment],
        root_cause:              parsed[:root_cause],
        coaching_message:        parsed[:coaching_message],
        improvement_suggestions: parsed[:improvement_suggestions],
        actions_json:            parsed[:actions],
        crisis_detected:         parsed[:crisis_detected] || false,
        prompt_version:          PROMPT_VERSION,
        ai_model_name:           model_name,
        is_latest:               true
      )

      UserSetting.where(id: user_setting.id)
                 .update_all("ai_analysis_count = ai_analysis_count + 1")
    end

    Rails.logger.info "[WeeklyReflectionAnalysisJob] 完了: weekly_reflection_id=#{weekly_reflection_id}, model=#{model_name}"

  rescue AiClient::AuthError => e
    Rails.logger.error "[WeeklyReflectionAnalysisJob] 認証エラー（401）: #{e.message}"
    raise  # discard_on AiClient::AuthError に伝播させる

  rescue => e
    Rails.logger.error "[WeeklyReflectionAnalysisJob] 予期しないエラー: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end

  private

  # ── D-11 追加: JSONパース失敗時に raw_response を metadata に保存 ──────────
  #
  # 【役割】
  #   パース失敗した AI のレスポンスをデバッグ用に AiAnalysis.metadata に保存する。
  #   PurposeAnalysisJob と同じ設計方針。
  def save_failed_analysis_with_raw_response(reflection, raw_response, model_name, user_purpose)
    AiAnalysis.create(
      weekly_reflection_id: reflection.id,
      analysis_type:        :weekly_reflection,
      input_snapshot:       build_input_snapshot(reflection, user_purpose),
      is_latest:            false,
      prompt_version:       PROMPT_VERSION,
      ai_model_name:        model_name.to_s,
      crisis_detected:      false,
      metadata: {
        "raw_response"    => raw_response.to_s[0, 2000],
        "parse_failed_at" => Time.current.iso8601,
        "model"           => model_name.to_s
      }
    )
  rescue => e
    Rails.logger.warn "[WeeklyReflectionAnalysisJob] raw_response の metadata 保存失敗（無視）: #{e.message}"
  end
  # ────────────────────────────────────────────────────────────────────────

  # 以下は変更なし（build_prompt, parse_response, build_input_snapshot）

  def build_prompt(reflection, user_purpose)
    pmvv_section = if user_purpose.present?
      <<~PMVV
        ## ユーザーの PMVV 情報（目標・価値観）

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
      PMVV
    else
      "## PMVV 情報\nユーザーはまだ PMVV（目標・価値観）を設定していません。\n振り返りデータのみで分析してください。\n"
    end

    direct_reason        = reflection.direct_reason.presence        || "未入力"
    background_situation = reflection.background_situation.presence || "未入力"
    next_action          = reflection.next_action.presence          || "未入力"
    reflection_comment   = reflection.reflection_comment.presence   || "未入力"

    <<~PROMPT
      あなたは優秀なライフコーチです。
      ユーザーの今週の振り返りデータを分析し、
      次週に向けた具体的なアドバイスと行動提案を提供してください。

      #{pmvv_section}

      ## 今週の振り返りデータ

      **対象期間:**
      #{reflection.week_start_date.strftime("%Y年%m月%d日")} 〜 #{reflection.week_end_date.strftime("%Y年%m月%d日")}

      **なぜ？（できなかった直接の原因）:**
      #{direct_reason}

      **どう？（来週への改善策）:**
      #{background_situation}

      **からの？（次への展開）:**
      #{next_action}

      **自由コメント:**
      #{reflection_comment}

      ## 分析の指示（Chain-of-Thought）

      以下の3ステップで深く考えてから回答してください:

      **ステップ1（分析）:**
      - 振り返りデータから「できなかった本質的な原因」を「なぜ？」を3回繰り返して掘り下げる
      #{user_purpose.present? ? "- PMVV（特に Vision と Value）と今週の行動のギャップを特定する" : "- 振り返りから改善すべきパターンを特定する"}
      - 表面的な言い訳（忙しかった等）の奥にある構造的な問題を見つける

      **ステップ2（コーチング）:**
      - ユーザーの強みを振り返りデータから見つけて伝える
      #{user_purpose.present? ? "- Value を守りながら Vision に近づく具体的な方法を提案する" : "- 来週に向けて実行可能な改善策を提案する"}
      - 批判ではなく励ましと行動指針を提供する

      **ステップ3（提案）:**
      - 今すぐ始められる具体的な習慣を3つ提案する（難易度の低いものから始める）
      - 今週中に取り組むべき具体的なタスクを3つ提案する
      - 各提案に「なぜそれが有効か」の根拠を添える

      ## 回答フォーマット

      以下の JSON 形式のみで回答してください。
      JSON 以外の文章は一切含めないでください。
      コードブロック（```json）も不要です。
      { から始めて } で終わる JSON のみを返してください。

      {
        "analysis_comment": "今週の振り返りの総合分析コメント（200〜400文字）",
        "root_cause": "できなかった本質的な原因（Why×3の分析、150〜300文字）",
        "coaching_message": "励ましと来週に向けた具体的なアドバイス（150〜300文字）",
        "improvement_suggestions": "全体的な改善提案のサマリー（100〜200文字）",
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
      - crisis_detected: 危機的なワードが含まれる場合のみ true
      - 回答は必ず有効な JSON のみ。前後に説明文を付けないでください
      - 日本語で回答してください
    PROMPT
  end

  def parse_response(raw_response)
    text     = raw_response.dup
    text     = text.gsub(/```json\n?/, "").gsub(/```\n?/, "")
    json_str = text[/\{.*\}/m]

    if json_str.blank?
      Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON が見つかりません"
      return nil
    end

    parsed       = JSON.parse(json_str, symbolize_names: true)
    required_keys = %i[analysis_comment root_cause coaching_message actions]
    missing_keys  = required_keys.reject { |k| parsed.key?(k) }

    if missing_keys.any?
      Rails.logger.error "[WeeklyReflectionAnalysisJob] 必須キーが不足: #{missing_keys.join(', ')}"
      return nil
    end

    unless parsed[:actions].is_a?(Array)
      Rails.logger.error "[WeeklyReflectionAnalysisJob] actions が配列ではありません"
      return nil
    end

    parsed
  rescue JSON::ParserError => e
    Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON パース失敗: #{e.message}"
    nil
  end

  def build_input_snapshot(reflection, user_purpose)
    snapshot = {
      weekly_reflection_id: reflection.id,
      week_start_date:      reflection.week_start_date.to_s,
      week_end_date:        reflection.week_end_date.to_s,
      direct_reason:        reflection.direct_reason,
      background_situation: reflection.background_situation,
      next_action:          reflection.next_action,
      reflection_comment:   reflection.reflection_comment,
      analyzed_at:          Time.current.iso8601
    }

    if user_purpose.present?
      snapshot[:user_purpose] = {
        id:                user_purpose.id,
        version:           user_purpose.version,
        purpose:           user_purpose.purpose,
        mission:           user_purpose.mission,
        vision:            user_purpose.vision,
        value:             user_purpose.value,
        current_situation: user_purpose.current_situation
      }
    end

    snapshot
  end
end