# app/controllers/user_purposes_controller.rb
#
# ==============================================================================
# UserPurposesController（PMVV 目標管理コントローラー）
# ==============================================================================
#
# 【このファイルの役割】
#   PMVV の入力・更新・AI分析結果表示を管理する。
#
# 【D-3 での追加】
#   ai_result       → 18番: AI分析結果ページを表示する
#   apply_proposals → チェックした提案を習慣・タスクとして登録する
#
# 【アクション一覧】
#   show             → 16番: 現在の PMVV と分析状態を表示する
#   new              → 17番: 新規入力フォームを表示する
#   create           → 17番フォームを送信して新規 PMVV を保存する
#   edit             → 17番: 編集フォームを表示する
#   update           → 編集フォームを送信して PMVV を更新保存する
#   retry_analysis   → 失敗した AI 分析を再実行する
#   ai_result        → 18番: AI分析結果ページを表示する（D-3 追加）
#   apply_proposals  → 提案を習慣・タスクとして登録する（D-3 追加）
# ==============================================================================

class UserPurposesController < ApplicationController
  # ============================================================
  # before_action
  # ============================================================

  # require_login: 未ログインのアクセスをブロックする
  # 【理由】PMVV はユーザーの個人情報に相当するため、
  #   ログインしていないユーザーはアクセスできないようにする。
  #   ApplicationController に定義された共通メソッドを使う。
  before_action :require_login

  # ============================================================
  # show アクション（16番: PMVV目標管理ページ）
  # ============================================================
  #
  # 【役割】
  #   現在有効な PMVV（is_active=true）を表示する。
  #   analysis_state に応じて UI を切り替える。
  #   4状態: nil（未入力）/ pending / analyzing / completed / failed
  #
  # 【@current_purpose】
  #   UserPurpose.current_for(current_user) で is_active=true のレコードを取得する。
  #   存在しない場合は nil → ビューで「目標が未入力」状態を表示する。
  #
  # 【@ai_analysis】
  #   completed 状態のとき「結果を見る →」リンクを表示するために使う。
  #   @current_purpose が nil の場合は取得しない。
  #
  # 【@past_purposes】
  #   過去のバージョン（is_active=false）の一覧をバージョン降順で取得する。
  def show
    @current_purpose = UserPurpose.current_for(current_user)

    # AI分析結果を取得する（completed 状態のバナーで使用）
    # 【AiAnalysis.where の条件】
    #   user_purpose_id: @current_purpose.id → この PMVV の分析結果のみ
    #   is_latest: true                       → 最新の分析結果のみ
    #   分析種別は purpose_breakdown（PMVV 分析）のみを対象にする
    if @current_purpose
      @ai_analysis = AiAnalysis.where(
        user_purpose_id: @current_purpose.id,
        is_latest:       true,
        analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
      ).first
    end

    # 過去バージョン一覧: is_active=false のレコードをバージョン降順で取得する
    @past_purposes = current_user.user_purposes
                                 .where(is_active: false)
                                 .order(version: :desc)
  end

  # ============================================================
  # new アクション（17番: PMVV入力ページ・新規）
  # ============================================================
  def new
    # UserPurpose.new: DB に保存しない空のインスタンスを作成する
    # form_with model: @user_purpose で送信先が自動決定される
    @user_purpose = UserPurpose.new
  end

  # ============================================================
  # create アクション
  # ============================================================
  #
  # 【役割】
  #   17番フォームの送信を受けて新しい PMVV を保存する。
  #   保存成功時: analysis_state を pending に設定し AI 分析ジョブをエンキューする。
  #   保存失敗時: エラーを表示してフォームを再表示する。
  def create
    @user_purpose = current_user.user_purposes.build(user_purpose_params)

    # analysis_state を明示的に pending に設定する
    # 【理由】schema.rb の default: 0 で pending になるが、
    #   コードを読む人に「保存直後は pending」という意図を明確に伝える。
    @user_purpose.analysis_state = :pending

    if @user_purpose.save
      # 保存成功: AI 分析ジョブをバックグラウンドで実行する
      # perform_later: GoodJob キューに追加して非同期で実行する
      # id を渡す理由: ジョブ引数は JSON シリアライズされるためインスタンスは渡せない
      PurposeAnalysisJob.perform_later(@user_purpose.id)

      redirect_to user_purpose_path,
                  notice: "目標を保存しました。AIによる分析を開始しています..."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # edit アクション（17番: PMVV入力ページ・編集）
  # ============================================================
  def edit
    @user_purpose = UserPurpose.current_for(current_user)

    unless @user_purpose
      redirect_to new_user_purpose_path,
                  alert: "まだ目標が登録されていません。新規登録してください。"
    end
  end

  # ============================================================
  # update アクション
  # ============================================================
  #
  # 【なぜ「更新」が実質「新規作成」なのか】
  #   過去の AI 分析結果は作成時の PMVV に紐付いているため、
  #   既存レコードを上書きすると「この分析はどの PMVV に基づくか」が
  #   不明になる。新しいレコードを作ることで履歴が保持される。
  def update
    @user_purpose = current_user.user_purposes.build(user_purpose_params)
    @user_purpose.analysis_state = :pending

    if @user_purpose.save
      PurposeAnalysisJob.perform_later(@user_purpose.id)

      redirect_to user_purpose_path,
                  notice: "目標を更新しました。AIによる再分析を開始しています..."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # retry_analysis アクション（D-2 実装済み）
  # ============================================================
  #
  # 【役割】
  #   失敗した AI 分析を再実行する。
  #   analysis_state を pending に戻してジョブをエンキューする。
  #
  # 【なぜ button_to + POST か】
  #   link_to はデフォルトで GET リクエストを送る。
  #   GET はサーバーの状態を変更しない「読み取り専用」の原則があり、
  #   「ジョブを再実行する」という状態変更は POST で行うべき。
  def retry_analysis
    # current_user.user_purposes 経由で取得するため
    # 他ユーザーの UserPurpose を操作できない
    @user_purpose = UserPurpose.current_for(current_user)

    unless @user_purpose
      redirect_to new_user_purpose_path, alert: "目標が登録されていません。"
      return
    end

    @user_purpose.update!(
      analysis_state:     :pending,
      last_error_message: nil
    )

    PurposeAnalysisJob.perform_later(@user_purpose.id)

    redirect_to user_purpose_path,
                notice: "再分析を開始しました。しばらくお待ちください。"
  end

  # ============================================================
  # ai_result アクション（18番: AI分析結果ページ）※D-3 新規追加
  # ============================================================
  #
  # 【役割】
  #   AI分析が完了した PMVV の詳細結果を表示する。
  #   ① input_snapshot から PMVV 5要素を取り出してビューに渡す
  #   ② actions_json から習慣提案・タスク提案に分離してビューに渡す
  #
  # 【なぜ @current_purpose ではなく input_snapshot を使うのか】
  #   ユーザーが PMVV を更新した後でも、この分析が実行された時点の
  #   PMVV データを正確に表示する必要がある。
  #   input_snapshot は分析実行時のスナップショット（固定値）なので
  #   後から PMVV が更新されても影響を受けない。
  #
  # 【with_indifferent_access の理由】
  #   PostgreSQL の JSONB から取り出した Hash のキーは文字列（"purpose"）になっている。
  #   with_indifferent_access を使うと文字列キーでもシンボルキーでも
  #   アクセスできるようになる（:purpose でも "purpose" でも OK）。
  def ai_result
    @current_purpose = UserPurpose.current_for(current_user)

    unless @current_purpose
      redirect_to new_user_purpose_path,
                  alert: "目標が登録されていません。"
      return
    end

    # 最新の AI 分析結果を取得する
    # 【schema.rb の UNIQUE 制約】
    #   index "index_ai_analyses_latest_purpose_type_unique" (user_purpose_id, analysis_type)
    #   WHERE user_purpose_id IS NOT NULL AND is_latest = true
    #   → 同一 user_purpose_id + analysis_type の is_latest=true は常に1件のみ
    @ai_analysis = AiAnalysis.where(
      user_purpose_id: @current_purpose.id,
      is_latest:       true,
      analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
    ).first

    unless @ai_analysis
      redirect_to user_purpose_path,
                  alert: "AI分析結果がまだ存在しません。分析が完了するまでお待ちください。"
      return
    end

    # ──────────────────────────────────────────────────
    # input_snapshot から PMVV 5要素を取り出す
    # ──────────────────────────────────────────────────
    # input_snapshot は JSONB 型なので Hash として取り出せる。
    # nil の場合（古いデータ等）は空 Hash をデフォルトにする。
    snapshot = (@ai_analysis.input_snapshot || {}).with_indifferent_access
    @snapshot_purpose           = snapshot[:purpose]
    @snapshot_mission           = snapshot[:mission]
    @snapshot_vision            = snapshot[:vision]
    @snapshot_value             = snapshot[:value]
    @snapshot_current_situation = snapshot[:current_situation]
    @snapshot_version           = snapshot[:version]

    # ──────────────────────────────────────────────────
    # actions_json から習慣提案・タスク提案を分離する
    # ──────────────────────────────────────────────────
    # actions_json の構造（PurposeAnalysisJob が保存した配列）:
    #   [
    #     { "type": "habit", "title": "読書", "description": "...", "priority": "must" },
    #     { "type": "task",  "title": "企画書作成", "description": "...", "priority": "should" }
    #   ]
    #
    # .map { |a| a.with_indifferent_access }:
    #   配列の各 Hash 要素を indifferent_access にする。
    #   これにより a[:type] でも a["type"] でもアクセス可能になる。
    actions = (@ai_analysis.actions_json || []).map { |a|
      a.is_a?(Hash) ? a.with_indifferent_access : a
    }

    # type == "habit" の提案を習慣提案として分離する
    @habit_proposals = actions.select { |a| a[:type] == "habit" }

    # type == "task" の提案をタスク提案として分離する
    @task_proposals  = actions.select { |a| a[:type] == "task" }
  end

  # ============================================================
  # apply_proposals アクション ※D-3 新規追加
  # ============================================================
  #
  # 【役割】
  #   18番ページでチェックした習慣・タスク提案を
  #   実際の habits / tasks テーブルに登録する。
  #
  # 【セキュリティ設計】
  #   提案のタイトルをそのままパラメータで受け取ると、
  #   攻撃者が任意のタイトルを送信できるリスクがある。
  #   代わりにインデックス番号（整数）を受け取り、
  #   サーバー側で AI 分析結果から該当提案を取り出す。
  #   これにより DB に保存される内容は必ず AI が生成したものになる。
  #
  # 【トランザクションの理由】
  #   習慣・タスクの作成が途中で失敗した場合に
  #   「一部だけ登録される」中途半端な状態を防ぐ。
  #
  # 【params の構造】
  #   habit_indices[]=0&habit_indices[]=2 → [0, 2]
  #   task_indices[]=1                    → [1]
  def apply_proposals
    @current_purpose = UserPurpose.current_for(current_user)

    unless @current_purpose
      redirect_to new_user_purpose_path, alert: "目標が登録されていません。"
      return
    end

    @ai_analysis = AiAnalysis.where(
      user_purpose_id: @current_purpose.id,
      is_latest:       true,
      analysis_type:   AiAnalysis.analysis_types[:purpose_breakdown]
    ).first

    unless @ai_analysis
      redirect_to user_purpose_path, alert: "AI分析結果が見つかりません。"
      return
    end

    # actions_json から全提案を取り出す
    actions = (@ai_analysis.actions_json || []).map { |a|
      a.is_a?(Hash) ? a.with_indifferent_access : a
    }
    habit_proposals = actions.select { |a| a[:type] == "habit" }
    task_proposals  = actions.select { |a| a[:type] == "task" }

    # チェックされたインデックスを取得する
    # params[:habit_indices] が nil の場合は [] を使う（Array() で安全に変換）
    # .map(&:to_i) で文字列 "0" を整数 0 に変換する
    selected_habit_indices = Array(params[:habit_indices]).map(&:to_i)
    selected_task_indices  = Array(params[:task_indices]).map(&:to_i)

    # 何もチェックされていない場合はエラーメッセージを表示して戻す
    if selected_habit_indices.empty? && selected_task_indices.empty?
      redirect_to ai_result_user_purpose_path,
                  alert: "少なくとも1つの提案を選択してください。"
      return
    end

    created_habits = 0
    created_tasks  = 0

    # ActiveRecord::Base.transaction:
    #   ブロック内の全 DB 操作を1つのトランザクションとして扱う。
    #   例外が発生するとブロック内の全操作がロールバックされる。
    ActiveRecord::Base.transaction do

      # ── チェックされた習慣提案を登録する ──────────────────────
      selected_habit_indices.each do |idx|
        # インデックスが範囲外の場合は安全にスキップする
        proposal = habit_proposals[idx]
        next unless proposal

        current_user.habits.create!(
          # truncate(50): habits.name は50文字制限（schema.rb で limit: 50）
          name:             proposal[:title].to_s.truncate(50),
          # チェック型をデフォルトにする（AI 提案は基本的にチェック型）
          measurement_type: :check_type,
          # 週次目標は一般的な5回/週をデフォルトにする
          # ユーザーが後から習慣編集ページで変更できる
          weekly_target:    5
        )
        created_habits += 1
      end

      # ── チェックされたタスク提案を登録する ──────────────────────
      selected_task_indices.each do |idx|
        proposal = task_proposals[idx]
        next unless proposal

        # priority の変換: AI が返す文字列 "must"/"should"/"could" を
        # enum シンボルに変換する
        # 【なぜ case 文で変換するのか】
        #   AI が予期しない文字列を返しても :should というデフォルト値で安全に扱える
        priority_value = case proposal[:priority].to_s.downcase
                         when "must"   then :must
                         when "should" then :should
                         when "could"  then :could
                         else               :should
                         end

        current_user.tasks.create!(
          # truncate(100): tasks.title は100文字制限（schema.rb で null: false）
          title:        proposal[:title].to_s.truncate(100),
          priority:     priority_value,
          # task_type: :improve → AI提案から生成されたタスク（enum で 2）
          task_type:    :improve,
          # ai_generated: true → C-3 実装の「手動タスクのみ削除可能」と連動する
          #   ai_generated=true のタスクはタスク一覧の「⋯」メニューが非表示になる
          ai_generated: true
        )
        created_tasks += 1
      end
    end

    # 成功メッセージを組み立てる
    # 【なぜ parts 配列を使うのか】
    #   習慣のみ、タスクのみ、両方の3パターンに対応するため
    parts = []
    parts << "習慣 #{created_habits} 件" if created_habits > 0
    parts << "タスク #{created_tasks} 件" if created_tasks > 0
    success_message = "#{parts.join('、')}をダッシュボードに追加しました！"

    redirect_to dashboard_path, notice: success_message

  rescue ActiveRecord::RecordInvalid => e
    # バリデーションエラーで作成失敗した場合
    # トランザクションがロールバックされているため DB は変更されていない
    Rails.logger.error "[apply_proposals] RecordInvalid: #{e.message}"
    redirect_to ai_result_user_purpose_path,
                alert: "提案の登録中にエラーが発生しました。もう一度お試しください。"
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # user_purpose_params
  # 【役割】フォームから送信されたパラメータをホワイトリスト化する（Strong Parameters）。
  # version / is_active / analysis_state はコントローラー側で制御するため除外する。
  def user_purpose_params
    params.require(:user_purpose).permit(
      :purpose,
      :mission,
      :vision,
      :value,
      :current_situation
    )
  end
end