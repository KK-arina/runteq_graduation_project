# app/jobs/weekly_reflection_analysis_job.rb
#
# ==============================================================================
# WeeklyReflectionAnalysisJob（週次振り返り AI分析ジョブ）
# ==============================================================================
#
# 【このファイルの役割】
#   WeeklyReflection（週次振り返り）が完了した後に GoodJob によって非同期実行される。
#   振り返りデータと、ユーザーが設定していれば PMVV データも合わせて
#   Gemini API に送信し、分析結果を ai_analyses テーブルに保存する。
#
# 【PurposeAnalysisJob との違い】
#   PurposeAnalysisJob : UserPurpose（PMVV）単体を分析する
#   このジョブ         : WeeklyReflection（週次振り返り）を中心に分析する
#                        PMVV が存在する場合は整合性チェックも行う
#
# 【ai_proposed_habit / ai_proposed_task モデルについて】
#   このプロジェクトでは専用モデルは存在しない。
#   習慣・タスクの提案は actions_json（jsonb）カラムに配列で保存し、
#   後続の処理（AI提案モーダル表示など）でここから読み取る設計。
#
# 【analysis_type の値】
#   AiAnalysis.analysis_types[:weekly_reflection] = 0
#   ai_analyses テーブルの analysis_type カラムに保存される整数値。
#
# ==============================================================================

class WeeklyReflectionAnalysisJob < ApplicationJob
  # queue_as :default
  # 【理由】
  #   GoodJob のデフォルトキューを使用する。
  #   AI分析は重要だが緊急ではないため、デフォルトキューで問題ない。
  queue_as :default

  # retry_on: 通信エラーのみリトライ対象にする
  # 【なぜ Faraday::Error と Timeout::Error だけか】
  #   JSON パースエラーやロジックエラーをリトライしても意味がない。
  #   ネットワーク起因のエラーのみを対象にすることで無駄なリトライを防ぐ。
  #
  # wait: :exponentially_longer → リトライ間隔を指数的に延ばす（1秒→2秒→4秒...）
  # attempts: 3 → 最大3回まで試みる
  retry_on Faraday::Error,  wait: :exponentially_longer, attempts: 3
  retry_on Timeout::Error,  wait: :exponentially_longer, attempts: 3

  # discard_on: 対象レコードが削除された場合はジョブを静かに破棄する
  # 【理由】
  #   ユーザーが退会して WeeklyReflection が削除された場合に
  #   ジョブがエラーを出し続けるのを防ぐ。
  discard_on ActiveRecord::RecordNotFound

  # PROMPT_VERSION: プロンプトのバージョン文字列
  # 【目的】
  #   プロンプトを改善したときにバージョンを上げることで
  #   どのプロンプトで生成した分析かを ai_analyses テーブルで追跡できる。
  PROMPT_VERSION = "v1.0".freeze

  # ============================================================
  # perform メソッド: GoodJob から呼び出されるメインメソッド
  # ============================================================
  #
  # 【引数】
  #   weekly_reflection_id : 分析対象の WeeklyReflection の ID（整数）
  #   ※ モデルインスタンスではなく ID を渡す理由:
  #     GoodJob はジョブの引数を JSON 形式で DB に保存する。
  #     ActiveRecord のインスタンスは JSON シリアライズできないため、
  #     ID（整数）を渡してジョブ内部で find する設計にする。
  def perform(weekly_reflection_id)
    # ----------------------------------------------------------
    # Step 1: WeeklyReflection を取得する
    # ----------------------------------------------------------
    # find: レコードが存在しない場合は RecordNotFound を発生させる。
    # discard_on ActiveRecord::RecordNotFound により、ジョブは静かに破棄される。
    reflection = WeeklyReflection.find(weekly_reflection_id)

    Rails.logger.info "[WeeklyReflectionAnalysisJob] 開始: weekly_reflection_id=#{weekly_reflection_id}, user_id=#{reflection.user_id}"

    # ----------------------------------------------------------
    # Step 2: ユーザーとその関連データを取得する
    # ----------------------------------------------------------
    user         = reflection.user
    user_setting = user.user_setting

    # user_setting が存在しない場合のガード
    # 【理由】
    #   user_setting は通常オンボーディング時に作成されるが、
    #   古いユーザーや何らかの不整合で存在しない可能性がある。
    #   nil チェックをしないと NoMethodError が発生してジョブが落ちる。
    if user_setting.nil?
      Rails.logger.warn "[WeeklyReflectionAnalysisJob] user_setting が存在しません: user_id=#{user.id}"
      return
    end

    # ----------------------------------------------------------
    # Step 3: 月次 AI 利用回数の上限チェック
    # ----------------------------------------------------------
    # 月の利用回数が上限に達している場合はジョブをスキップする。
    # 【なぜここでチェックするか】
    #   サービス側でもチェックしているが、ジョブ実行時点で再チェックすることで
    #   二重エンキューやタイムラグによる超過を防ぐ二重防御。
    if user_setting.ai_analysis_count >= user_setting.ai_analysis_monthly_limit
      Rails.logger.warn "[WeeklyReflectionAnalysisJob] AI分析の月次上限に達しています: user_id=#{user.id}, count=#{user_setting.ai_analysis_count}/#{user_setting.ai_analysis_monthly_limit}"
      return
    end

    # ----------------------------------------------------------
    # Step 4: ユーザーの現在有効な PMVV を取得する（存在する場合のみ）
    # ----------------------------------------------------------
    # PMVV が設定されていない場合は nil になる。
    # nil の場合でもジョブは続行する（PMVV なしで分析する）。
    #
    # 【UserPurpose.current_for とは】
    #   is_active=true かつ最新バージョンの UserPurpose を返すクラスメソッド。
    #   user_purpose.rb に定義済み。
    user_purpose = UserPurpose.current_for(user)

    # ----------------------------------------------------------
    # Step 5: AI API を呼び出す
    # ----------------------------------------------------------
    # build_prompt: 振り返りデータ + PMVV（存在する場合）を組み合わせたプロンプトを生成
    prompt = build_prompt(reflection, user_purpose)
    result = AiClient.new.analyze(prompt)

    # result が nil の場合: 全プロバイダ（Gemini + Groq）が失敗済み
    #
    # 【なぜ raise ではなく return するか】
    #   AiClient が nil を返すのは「Gemini + Groq の両方でリトライも含め全て失敗した」
    #   最終結果を意味する。
    #   ここで raise すると retry_on の対象外の例外として即 discard されてしまい、
    #   GoodJob の retry 機能が活用できなくなる。
    #   ログだけ残して正常終了することで、次回の振り返り時に再挑戦できる。
    if result.nil?
      Rails.logger.error "[WeeklyReflectionAnalysisJob] 全 AI プロバイダが失敗しました: weekly_reflection_id=#{weekly_reflection_id}"
      return
    end

    raw_response = result[:text]
    model_name   = result[:model]

    # ----------------------------------------------------------
    # Step 6: AI レスポンスを JSON でパースする
    # ----------------------------------------------------------
    parsed = parse_response(raw_response)

    # パース失敗の場合もジョブは正常終了（ログだけ残す）
    # 【理由】
    #   不正な JSON が返った場合にリトライしても同じ結果になる可能性が高い。
    #   ログを残してデバッグに役立てる。
    if parsed.nil?
      Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON パース失敗: weekly_reflection_id=#{weekly_reflection_id}"
      return
    end

    # ----------------------------------------------------------
    # Step 7: AiAnalysis レコードを保存し、ai_analysis_count をインクリメント
    # ----------------------------------------------------------
    # トランザクションで2つの DB 更新をまとめる。
    # 【理由】
    #   AiAnalysis の保存は成功したが ai_analysis_count の更新が失敗する
    #   という中途半端な状態を防ぐ。
    ActiveRecord::Base.transaction do
      # AiAnalysis レコードを作成する
      AiAnalysis.create!(
        # weekly_reflection_id: この分析が属する振り返り ID
        weekly_reflection_id:    reflection.id,

        # analysis_type: 週次振り返り分析であることを示す（enum の :weekly_reflection = 0）
        analysis_type:           :weekly_reflection,

        # input_snapshot: 分析実行時のデータのスナップショット（jsonb）
        # 後から振り返りデータが変更されても、分析時点のデータを参照できる
        input_snapshot:          build_input_snapshot(reflection, user_purpose),

        # 分析結果の各フィールド
        analysis_comment:        parsed[:analysis_comment],
        root_cause:              parsed[:root_cause],
        coaching_message:        parsed[:coaching_message],
        improvement_suggestions: parsed[:improvement_suggestions],

        # actions_json: 習慣・タスクの提案を配列で保存（jsonb）
        # ai_proposed_habit / ai_proposed_task モデルは存在しないため
        # このフィールドに全て格納する
        actions_json:            parsed[:actions],

        # crisis_detected: 危機ワードが検出された場合は true
        # parsed に含まれない場合は false をデフォルト値として使う
        crisis_detected:         parsed[:crisis_detected] || false,

        # プロンプトバージョンと使用モデル名を記録（デバッグ・分析品質追跡用）
        prompt_version:          PROMPT_VERSION,
        ai_model_name:           model_name,

        # is_latest: この分析が最新であることを示す
        # before_create :deactivate_previous_analyses コールバックにより
        # 同じ weekly_reflection_id の古い分析は自動的に is_latest=false になる
        is_latest:               true
      )

      # ai_analysis_count を原子的にインクリメントする
      #
      # 【なぜ update_all を使うか（increment! を使わない理由）】
      #   increment! は Ruby 側で現在の値を読み込み +1 して保存する。
      #   複数のジョブが同時実行された場合、同じ値を読み込んで +1 するため
      #   カウントがズレる「競合状態（Race Condition）」が発生する。
      #
      #   update_all で SQL の "count = count + 1" を使うと
      #   DB が計算を行うため、複数同時実行でも正確にカウントできる（原子的操作）。
      #
      #   例: 同時に2つのジョブが動いた場合
      #     increment!    : 両方が count=0 を読んで 1 にする → 結果 count=1（❌ バグ）
      #     update_all    : DB が 0→1→2 と順番に処理する    → 結果 count=2（✅ 正確）
      UserSetting.where(id: user_setting.id)
                 .update_all("ai_analysis_count = ai_analysis_count + 1")
    end

    Rails.logger.info "[WeeklyReflectionAnalysisJob] 完了: weekly_reflection_id=#{weekly_reflection_id}, model=#{model_name}"

  rescue => e
    # 予期しない例外が発生した場合のセーフティネット
    # バックトレースも記録して原因調査できるようにする
    Rails.logger.error "[WeeklyReflectionAnalysisJob] 予期しないエラー: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    # raise することで GoodJob の retry_on / discard_on が機能する
    raise
  end

  private

  # ==============================================================
  # build_prompt(reflection, user_purpose)
  # ==============================================================
  # 【役割】
  #   AI に送信するプロンプトを生成する。
  #   振り返りデータを必須情報として含め、
  #   PMVV が存在する場合はその整合性チェックも依頼する。
  #
  # 【引数】
  #   reflection   : WeeklyReflection インスタンス
  #   user_purpose : UserPurpose インスタンス（nil の場合もある）
  #
  # 【プロンプト設計の工夫】
  #   - Chain-of-Thought で3ステップの思考を促す
  #   - PMVV の有無で条件分岐してプロンプトを動的に変える
  #   - JSON のみで返すよう強く指示する（前後の文章を防ぐ）
  # ==============================================================
  def build_prompt(reflection, user_purpose)
    # PMVV セクションを動的に構築する
    # user_purpose が nil の場合は「未設定」の旨を伝える
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

    # 振り返りの各フィールドを取得する
    # presence を使うことで nil と空文字の両方を「未入力」に変換できる
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

      【重要】
      - crisis_detected は「死にたい」「消えたい」などの危機的なワードが含まれる場合のみ true にしてください
      - 回答は必ず有効な JSON のみ。前後に説明文を付けないでください
      - 日本語で回答してください
    PROMPT
  end

  # ==============================================================
  # parse_response(raw_response)
  # ==============================================================
  # 【役割】
  #   AI のレスポンス文字列から JSON 部分を抽出してパースする。
  #
  # 【AI のレスポンスパターンへの対応】
  #   パターン①: 純粋な JSON のみ（理想）
  #   パターン②: ```json\n{...}\n``` （コードブロック付き）
  #   パターン③: "はい、分析結果です：\n{...}" （前置き文あり ← 高確率）
  #   パターン④: "{...}\n\n以上です。" （後置き文あり）
  #
  # 【戻り値】
  #   成功時: パース済み Hash（シンボルキー）
  #   失敗時: nil
  # ==============================================================
  def parse_response(raw_response)
    text = raw_response.dup

    # ① コードブロック記号を除去する
    text = text.gsub(/```json\n?/, "").gsub(/```\n?/, "")

    # ② { から } の範囲を正規表現で抽出する
    # /\{.*\}/m の m フラグ: . が改行にもマッチするため複数行対応
    # これにより前置き・後置き文章があっても JSON 部分だけを取り出せる
    json_str = text[/\{.*\}/m]

    if json_str.blank?
      Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON が見つかりません"
      Rails.logger.error "[WeeklyReflectionAnalysisJob] 元のレスポンス（先頭300文字）: #{raw_response[0..300]}"
      return nil
    end

    # ③ JSON をパースしてシンボルキーの Hash に変換する
    # symbolize_names: true により parsed[:analysis_comment] のようにアクセスできる
    parsed = JSON.parse(json_str, symbolize_names: true)

    # ④ 必須キーのバリデーション
    # これらのキーがない場合は AI の応答が期待通りでないため nil を返す
    required_keys = %i[analysis_comment root_cause coaching_message actions]
    missing_keys  = required_keys.reject { |k| parsed.key?(k) }

    if missing_keys.any?
      Rails.logger.error "[WeeklyReflectionAnalysisJob] 必須キーが不足: #{missing_keys.join(", ")}"
      return nil
    end

    # ⑤ actions が配列かどうかをバリデーションする
    # AI が稀に配列以外（文字列や null）を返すことがある
    unless parsed[:actions].is_a?(Array)
      Rails.logger.error "[WeeklyReflectionAnalysisJob] actions が配列ではありません: #{parsed[:actions].class}"
      return nil
    end

    parsed

  rescue JSON::ParserError => e
    Rails.logger.error "[WeeklyReflectionAnalysisJob] JSON パース失敗: #{e.message}"
    Rails.logger.error "[WeeklyReflectionAnalysisJob] 元のレスポンス（先頭500文字）: #{raw_response[0..500]}"
    nil
  end

  # ==============================================================
  # build_input_snapshot(reflection, user_purpose)
  # ==============================================================
  # 【役割】
  #   分析実行時点のデータを jsonb として保存するための Hash を構築する。
  #
  # 【なぜ as_json を使わないか】
  #   as_json はモデルの全カラム（password_digest 等のセキュリティ情報も含む）を
  #   出力してしまう。明示的にフィールドを指定することで
  #   「必要なデータのみ」を安全に保存できる。
  #
  # 【なぜスナップショットを保存するか】
  #   振り返りデータは後から変更される可能性がある。
  #   「この分析はこのデータで行われた」という記録を残すことで
  #   分析結果の再現性と追跡可能性を確保する。
  # ==============================================================
  def build_input_snapshot(reflection, user_purpose)
    snapshot = {
      # 振り返りの基本情報
      weekly_reflection_id: reflection.id,
      week_start_date:      reflection.week_start_date.to_s,
      week_end_date:        reflection.week_end_date.to_s,

      # 振り返りの各フィールド
      direct_reason:        reflection.direct_reason,
      background_situation: reflection.background_situation,
      next_action:          reflection.next_action,
      reflection_comment:   reflection.reflection_comment,

      # 分析実行日時（UTC の ISO8601 形式）
      analyzed_at: Time.current.iso8601
    }

    # PMVV が存在する場合はそのデータも含める
    # 【理由】
    #   「このPMVVに基づいて分析した」という記録を残すため。
    #   PMVV が後から更新されても分析時点の内容を参照できる。
    #   as_json は使わず必要なフィールドのみ明示的に指定する。
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