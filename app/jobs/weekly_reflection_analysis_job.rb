# app/jobs/weekly_reflection_analysis_job.rb
#
# ==============================================================================
# WeeklyReflectionAnalysisJob（週次振り返り AI分析ジョブ）
# ==============================================================================
#
# 【G-9 での変更内容】
#   ① build_prompt に現在の習慣一覧・タスク一覧・PMVVを追加
#      既存習慣・既存タスクをプロンプトに含めることで、
#      AIが「新規追加」だけでなく「既存の修正・削除・目標見直し」も提案できるようになる。
#
#   ② actions_json のスキーマに以下の4種類の type を追加:
#      - "habit_modify"  : 既存習慣の修正提案（週次目標・除外日等の変更）
#      - "habit_delete"  : 既存習慣の削除提案（達成・不要になった習慣）
#      - "task_modify"   : 既存タスクの修正提案（優先度・期限等の変更）
#      - "goal_review"   : 目標（PMVV）の見直し提案（DBへの変更なし）
#
#   ③ build_input_snapshot に習慣・タスクのスナップショットを追加
#      「この分析時点でどんな習慣・タスクがあったか」を記録することで
#      後から確認・デバッグしやすくなる。
#
#   ④ 既存の "habit" / "task"（新規追加）type の処理は変更しない（後方互換性保証）
#
# ==============================================================================

class WeeklyReflectionAnalysisJob < ApplicationJob
  queue_as :default

  # D-11 変更: retry_on を削除して内部で再エンキューする設計に変更
  discard_on ActiveRecord::RecordNotFound

  # AiClient::AuthError: APIキー不正時は即座に破棄する
  discard_on AiClient::AuthError

  PROMPT_VERSION = "v2.0".freeze  # G-9: スキーマ拡張につきバージョンを上げる

  # MAX_REENQUEUE_COUNT: 全プロバイダ失敗時の最大再エンキュー回数（変更なし）
  MAX_REENQUEUE_COUNT = 3

  # REENQUEUE_WAIT_SECONDS: 再エンキュー待機時間（秒）（変更なし）
  REENQUEUE_WAIT_SECONDS = 60

  # ============================================================
  # perform メソッド（変更なし: G-9 は build_prompt・parse_response・
  #                   build_input_snapshot・confirm_proposals の変更のみ）
  # ============================================================
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

    # ── G-9 追加: 現在の習慣一覧・タスク一覧を取得してプロンプトに含める ──
    #
    # 【なぜここで取得するのか】
    #   build_prompt に渡すことで、AIが「ユーザーの現在の習慣・タスク状況」を
    #   踏まえた提案（修正・削除・新規）ができるようになる。
    #   active スコープを使うことで削除済み・アーカイブ済みを除外できる。
    current_habits = user.habits.active.includes(:habit_excluded_days).to_a
    current_tasks  = user.tasks.active.not_archived.to_a
    # ──────────────────────────────────────────────────────────────────────────

    prompt = build_prompt(reflection, user_purpose, current_habits, current_tasks)
    result = AiClient.new.analyze(prompt)

    # 全プロバイダ失敗時の再エンキューロジック（変更なし）
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

    raw_response = result[:text]
    model_name   = result[:model]

    # JSONパース失敗時の処理（変更なし）
    parsed = parse_response(raw_response)

    if parsed.nil?
      save_failed_analysis_with_raw_response(reflection, raw_response, model_name, user_purpose)
      Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON パース失敗: metadata に raw_response を保存しました"
      return
    end

    ActiveRecord::Base.transaction do
      AiAnalysis.create!(
        weekly_reflection_id:    reflection.id,
        analysis_type:           :weekly_reflection,
        # ── G-9 変更: build_input_snapshot に習慣・タスクを追加 ──
        input_snapshot:          build_input_snapshot(reflection, user_purpose, current_habits, current_tasks),
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

    # E-3 追加: AI分析完了を weekly_reflections/index にリアルタイム通知（変更なし）
    broadcast_completion(reflection)
    # G-7 追加: ダッシュボード向け振り返り分析完了バナーのブロードキャスト（変更なし）
    broadcast_dashboard_completion(reflection)

  rescue AiClient::AuthError => e
    Rails.logger.error "[WeeklyReflectionAnalysisJob] 認証エラー（401）: #{e.message}"
    raise

  rescue => e
    Rails.logger.error "[WeeklyReflectionAnalysisJob] 予期しないエラー: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end

  # VALID_ACTION_TYPES: AIが返す actions の type として有効な値の一覧（G-9 追加）
  # 【なぜクラスレベルで定義するのか】
  #   Ruby では def...end の内部に定数を定義すると
  #   "dynamic constant assignment" エラーになる。
  #   定数はクラスレベルで定義する必要がある。
  VALID_ACTION_TYPES = %w[habit task habit_modify habit_delete task_modify goal_review].freeze

  private

  # save_failed_analysis_with_raw_response（変更なし）
  def save_failed_analysis_with_raw_response(reflection, raw_response, model_name, user_purpose)
    AiAnalysis.create(
      weekly_reflection_id: reflection.id,
      analysis_type:        :weekly_reflection,
      input_snapshot:       build_input_snapshot(reflection, user_purpose, [], []),
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

  # ============================================================
  # ── G-9 変更: build_prompt（習慣・タスク情報を追加）──────────────
  # ============================================================
  #
  # 【変更前の引数】 build_prompt(reflection, user_purpose)
  # 【変更後の引数】 build_prompt(reflection, user_purpose, current_habits, current_tasks)
  #
  # 【なぜ習慣・タスク一覧をプロンプトに含めるのか】
  #   「新しい習慣・タスクを追加する」だけでなく、
  #   「頑張りすぎている習慣の目標を下げる」「達成できていないタスクを修正する」
  #   という提案もできるようにするため。
  #   AIが「現状のユーザーのリスト」を知っていることが前提となる。
  def build_prompt(reflection, user_purpose, current_habits, current_tasks)
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

    # ── G-9 追加: 現在の習慣一覧セクション ─────────────────────────────
    #
    # 【なぜ習慣一覧をプロンプトに含めるのか】
    #   AIが「どんな習慣がすでにあるか」を知ることで、
    #   重複した提案をしたり、修正すべき習慣の名前を間違えたりするのを防ぐ。
    #   habit_name で既存習慣を特定するため、正確な名前が必要。
    #
    # 【なぜ excessive? を判定するのか】
    #   週次目標が効果的週次目標（除外日考慮）と乖離している習慣は
    #   「頑張りすぎ」の可能性があるためAIへのヒントとして追加する。
    habits_section = if current_habits.any?
      habit_lines = current_habits.map do |h|
        effective = h.effective_weekly_target
        target    = h.weekly_target
        # 実際の実施可能日数よりも目標が高い場合は「高負荷」と伝える
        overload_note = (target > effective) ? "（除外日あり: 実質#{effective}回/週）" : ""
        streak_note   = h.current_streak > 0 ? "、現在#{h.current_streak}日連続" : ""
        "  - #{h.name}（#{h.check_type? ? 'チェック型' : "数値型/#{h.unit}"}、週次目標#{target}回#{overload_note}#{streak_note}）"
      end.join("\n")

      <<~HABITS
        ## 現在登録されている習慣一覧（アクティブなもの）

        #{habit_lines}

        ※ この一覧を参考に、修正・削除が必要な習慣があれば提案してください。
        ※ 習慣名は一覧の名前と完全一致させてください（コントローラーで名前マッチングします）。
      HABITS
    else
      "## 現在の習慣\nまだアクティブな習慣がありません。\n"
    end

    # ── G-9 追加: 現在のタスク一覧セクション ────────────────────────────
    #
    # 【なぜタスク一覧をプロンプトに含めるのか】
    #   既存タスクの優先度・期限が実態と合っていない場合に
    #   AIが修正提案できるようにするため。
    #   task_title で既存タスクを特定するため、正確な名前が必要。
    tasks_section = if current_tasks.any?
      # 表示件数を絞ることでプロンプトが長くなりすぎるのを防ぐ
      # Must/Should タスクのみ表示（Could は優先度が低いためAIへのヒントとしては省略）
      priority_tasks = current_tasks.select { |t| t.must? || t.should? }.first(10)
      if priority_tasks.any?
        task_lines = priority_tasks.map do |t|
          due_note = t.due_date.present? ? "（期限: #{t.due_date.strftime('%m/%d')}）" : ""
          "  - #{t.title}（#{t.priority.upcase}#{due_note}）"
        end.join("\n")
        <<~TASKS
          ## 現在登録されているタスク一覧（Must/Should のみ、最大10件）

          #{task_lines}

          ※ この一覧を参考に、優先度変更・修正が必要なタスクがあれば提案してください。
          ※ タスク名は一覧の名前と完全一致させてください（コントローラーで名前マッチングします）。
        TASKS
      else
        "## 現在のタスク\nMust/Shouldの未完了タスクはありません。\n"
      end
    else
      "## 現在のタスク\nまだアクティブなタスクがありません。\n"
    end
    # ─────────────────────────────────────────────────────────────────────────

    direct_reason        = reflection.direct_reason.presence        || "未入力"
    background_situation = reflection.background_situation.presence || "未入力"
    next_action          = reflection.next_action.presence          || "未入力"
    reflection_comment   = reflection.reflection_comment.presence   || "未入力"

    <<~PROMPT
      あなたは優秀なライフコーチです。
      ユーザーの今週の振り返りデータを分析し、
      次週に向けた具体的なアドバイスと行動提案を提供してください。

      #{pmvv_section}

      #{habits_section}

      #{tasks_section}

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
      - 現在の習慣・タスク一覧を参照し、「負荷が高すぎる習慣」「達成できていない習慣」を特定する
      - 現在のタスク一覧を参照し、「優先度が実態と合っていないタスク」を特定する

      **ステップ2（コーチング）:**
      - ユーザーの強みを振り返りデータから見つけて伝える
      #{user_purpose.present? ? "- Value を守りながら Vision に近づく具体的な方法を提案する" : "- 来週に向けて実行可能な改善策を提案する"}

      **ステップ3（提案）:**
      - 新しく始める習慣を最大2件（必要な場合のみ）
      - 新しく追加するタスクを最大2件（必要な場合のみ）
      - 既存習慣の修正・削除が必要な場合は提案する（一覧の習慣名と完全一致させること）
      - 既存タスクの修正が必要な場合は提案する（一覧のタスク名と完全一致させること）
      - PMVVとのギャップが大きい場合は目標見直しを提案する

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
            "title": "新しく追加する習慣名（20文字以内）",
            "description": "なぜこの習慣が有効か（50〜100文字）",
            "frequency": "毎日 or 週N回",
            "priority": "must or should or could"
          },
          {
            "type": "task",
            "title": "新しく追加するタスク名（30文字以内）",
            "description": "なぜこのタスクが有効か（50〜100文字）",
            "priority": "must or should or could"
          },
          {
            "type": "habit_modify",
            "habit_name": "修正対象の既存習慣名（一覧の名前と完全一致）",
            "changes": { "weekly_target": 4 },
            "reason": "なぜ修正を提案するか（50〜100文字）",
            "priority": "must or should or could"
          },
          {
            "type": "habit_delete",
            "habit_name": "削除対象の既存習慣名（一覧の名前と完全一致）",
            "reason": "なぜ削除を提案するか（50〜100文字）",
            "priority": "could"
          },
          {
            "type": "task_modify",
            "task_title": "修正対象の既存タスク名（一覧の名前と完全一致）",
            "changes": { "priority": "must" },
            "reason": "なぜ修正を提案するか（50〜100文字）",
            "priority": "should"
          },
          {
            "type": "goal_review",
            "review_point": "PMVVのどの部分を見直すべきかの要約（100〜200文字）",
            "purpose_suggestion": "Purpose（人生で大切にしていること）の具体的な改善案（50文字以内）",
            "mission_suggestion": "Mission（今最も必要なこと）の具体的な改善案（50文字以内）",
            "vision_suggestion": "Vision（1年後の理想の自分）の具体的な改善案（50文字以内）",
            "value_suggestion": "Value（絶対に譲れないこと）の具体的な改善案（50文字以内）",
            "current_suggestion": "Current（今の自分の現状）の具体的な改善案（50文字以内）",
            "reason": "なぜ今見直しが必要か（50〜100文字）",
            "priority": "could"
          }
        ],
        "crisis_detected": false
      }

      【重要ルール】
      - actions 配列には必要な提案のみ含める。不要なら空配列 [] でも可。
      - habit_modify/habit_delete の habit_name は上記「現在の習慣一覧」の名前と完全一致させること
      - task_modify の task_title は上記「現在のタスク一覧」の名前と完全一致させること
      - goal_review は PMVV が設定されている場合のみ提案すること
      - goal_review の suggestions には、現在のユーザーのPMVV内容を踏まえた
        具体的な改善文案を Purpose / Mission / Vision / Value / Current の
        5項目それぞれについて記載すること
      - crisis_detected: 危機的なワードが含まれる場合のみ true
      - 回答は必ず有効な JSON のみ。前後に説明文を付けないでください
      - 日本語で回答してください
    PROMPT
  end

  # ============================================================
  # parse_response（G-9: 新 type の存在チェックを追加）
  # ============================================================
  #
  # 【G-9 での変更点】
  #   actions_json に含まれる各アクションの type が有効な値かを確認する。
  #   無効な type は警告ログを出してスキップするのではなく、
  #   そのまま残す（Controller側でスキップするため）。
  #   これにより、将来 type が追加されても古いコードが壊れない（後方互換性）。
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

    action_types = parsed[:actions].map { |a| a[:type] }.tally
    Rails.logger.info "[WeeklyReflectionAnalysisJob] actions の type 集計: #{action_types.inspect}"

    unknown_types = parsed[:actions].map { |a| a[:type] }.uniq - VALID_ACTION_TYPES
    if unknown_types.any?
      Rails.logger.warn "[WeeklyReflectionAnalysisJob] 未知の action type が含まれています（無視します）: #{unknown_types.inspect}"
    end
    # ──────────────────────────────────────────────────────────────────────────

    parsed
  rescue JSON::ParserError => e
    Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON パース失敗: #{e.message}"
    nil
  end

  # ============================================================
  # ── G-9 変更: build_input_snapshot（習慣・タスクを追加）──────────
  # ============================================================
  #
  # 【変更前の引数】 build_input_snapshot(reflection, user_purpose)
  # 【変更後の引数】 build_input_snapshot(reflection, user_purpose, habits, tasks)
  #
  # 【なぜスナップショットに習慣・タスクを含めるのか】
  #   「この分析時点でどんな習慣・タスクがあったか」を記録することで、
  #   habit_modify/habit_delete の "habit_name" が実際に何を指していたかを
  #   後から確認・デバッグできる。
  def build_input_snapshot(reflection, user_purpose, habits = [], tasks = [])
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

    # ── G-9 追加: 習慣・タスクのスナップショット ─────────────────────────
    if habits.any?
      snapshot[:habits] = habits.map do |h|
        {
          id:           h.id,
          name:         h.name,
          weekly_target: h.weekly_target,
          measurement_type: h.measurement_type
        }
      end
    end

    if tasks.any?
      snapshot[:tasks] = tasks.first(10).map do |t|
        {
          id:       t.id,
          title:    t.title,
          priority: t.priority,
          status:   t.status
        }
      end
    end
    # ──────────────────────────────────────────────────────────────────────────

    snapshot
  end

  # broadcast_completion / broadcast_dashboard_completion は変更なし
  def broadcast_completion(reflection)
    ai_analysis  = reflection.ai_analyses.latest.where.not(actions_json: nil).first
    user_purpose = UserPurpose.current_for(reflection.user)
    Turbo::StreamsChannel.broadcast_replace_to(
      "weekly_reflection_#{reflection.id}",
      target:  "weekly_reflection_ai_banner",
      partial: "weekly_reflections/ai_proposal_banner",
      locals:  {
        latest_reflection:  reflection,
        latest_ai_analysis: ai_analysis,
        current_purpose:    user_purpose
      }
    )
    Rails.logger.info "[WeeklyReflectionAnalysisJob] Turbo Stream 通知完了: reflection_id=#{reflection.id}"
  rescue => e
    Rails.logger.warn "[WeeklyReflectionAnalysisJob] Turbo Stream 通知失敗（無視）: #{e.message}"
  end

  def broadcast_dashboard_completion(reflection)
    ai_analysis = reflection.ai_analyses.latest.where.not(actions_json: nil).first

    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard_notifications_#{reflection.user_id}",
      target:  "dashboard_reflection_completion_banner",
      partial: "dashboards/reflection_completion_banner",
      locals:  { reflection: reflection, ai_analysis: ai_analysis }
    )
    Rails.logger.info "[WeeklyReflectionAnalysisJob] ダッシュボード通知完了: reflection_id=#{reflection.id}"
  rescue => e
    Rails.logger.warn "[WeeklyReflectionAnalysisJob] ダッシュボード通知失敗（無視）: #{e.message}"
  end
end