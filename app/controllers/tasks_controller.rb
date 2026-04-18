# app/controllers/tasks_controller.rb
#
# ==============================================================================
# TasksController（C-7 変更: ai_edit / ai_update アクションを追加）
# ==============================================================================
#
# 【C-7 での変更点】
#   1. before_action :set_task に :ai_edit / :ai_update を追加
#   2. ai_edit アクション: AI提案モーダル経由のみアクセス可能なタスク編集フォームを表示
#   3. ai_update アクション: ai_edit フォームの保存処理
#   4. private に set_ai_context / verify_ai_context を追加
# ==============================================================================

class TasksController < ApplicationController
  include ActionView::RecordIdentifier
  include ActionView::Helpers::TagHelper

  before_action :require_login

  # ============================================================
  # before_action :set_task（C-7 変更: ai_edit / ai_update を追加）
  # ============================================================
  #
  # 【なぜ ai_edit / ai_update にも set_task を追加するのか】
  #   ai_edit と ai_update はどちらも params[:id] を使って
  #   タスクを取得する必要がある。
  #   set_task は current_user.tasks.find(params[:id]) で取得するため、
  #   他ユーザーのタスクへのアクセスを RecordNotFound（404）で弾ける。
  before_action :set_task, only: [ :toggle_complete, :archive, :destroy, :update, :ai_edit, :ai_update ]

  # ============================================================
  # index アクション（変更なし）
  # ============================================================
  def index
    @locked = locked?
    @current_tab = params[:tab] || "all"

    base_tasks = current_user.tasks.active

    @tasks = case @current_tab
            when "must"
              base_tasks.not_archived.must
            when "should"
              base_tasks.not_archived.should
            when "could"
              base_tasks.not_archived.could
            when "done"
              base_tasks.where(status: Task.statuses[:done])
            else
              base_tasks.not_archived
            end

    priority_counts = base_tasks.not_archived.unscope(:order).group(:priority).count

    @must_count   = priority_counts[Task.priorities[:must]]   || 0
    @should_count = priority_counts[Task.priorities[:should]] || 0
    @could_count  = priority_counts[Task.priorities[:could]]  || 0
    @all_count    = @must_count + @should_count + @could_count
  end

  # ============================================================
  # new アクション（変更なし）
  # ============================================================
  def new
    @task = Task.new
    @task.priority = :should
  end

  # ============================================================
  # create アクション（変更なし）
  # ============================================================
  def create
    return if require_unlocked

    @task = current_user.tasks.build(task_params)

    if @task.save
      enqueue_alarm_job_if_needed(@task)
      redirect_to tasks_path, notice: "タスクを作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # update アクション（変更なし）
  # ============================================================
  def update
    return if require_unlocked

    cancel_existing_alarm_jobs(@task)

    if @task.update(task_params)
      enqueue_alarm_job_if_needed(@task)
      redirect_to tasks_path, notice: "タスクを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # C-7 追加: ai_edit アクション
  # ============================================================
  #
  # 【このアクションの役割】
  #   AI提案モーダルの「✏️ 編集する」リンクをクリックしたときに呼ばれる。
  #   11番（タスク編集ページ・AI経由限定）を表示する。
  #
  # 【アクセス制御の流れ】
  #   Step 1: set_ai_context を呼んで session に ai_context フラグを立てる
  #   Step 2: @task を表示用に準備して app/views/tasks/ai_edit.html.erb を描画する
  #
  # 【なぜ session を使うのか】
  #   「AI提案モーダルから来たかどうか」をサーバー側で証明する手段が必要。
  #   URL パラメータ（?from=ai_modal など）はユーザーが直接書き換えられるため不適切。
  #   session はサーバーが暗号化して Cookie に保存するため改ざんできない。
  #
  # 【set_ai_context の呼び出しタイミング】
  #   ai_edit（GET）を呼んだ時点で session にフラグを立てる。
  #   その後 ai_update（PATCH）でフラグを検証する（verify_ai_context）。
  #   ai_edit を経由せずに ai_update を直接叩いた場合、
  #   session にフラグがないため 403 で弾かれる。
  def ai_edit
    # AI提案モーダル経由であることを session に記録する
    # 詳細は private の set_ai_context を参照
    set_ai_context

    # @task は before_action :set_task で取得済み
    # ai_edit.html.erb をレンダリングする
  end

  # ============================================================
  # C-7 追加: ai_update アクション（修正版: アラームジョブ再スケジュールを追加）
  # ============================================================
  #
  # 【このアクションの役割】
  #   ai_edit フォームの送信先。
  #   タスク名・期限・見積時間を保存して、タスク一覧に戻る。
  #   （E-3実装後は AI提案モーダルに戻るよう変更する）
  #
  # 【アクセス制御の流れ】
  #   Step 1: verify_ai_context で session のフラグを確認する
  #           フラグなし → 403 Forbidden を返して処理を中断する
  #   Step 2: cancel_existing_alarm_jobs で古いアラームジョブを削除する
  #           【なぜ削除が必要か】
  #           due_date が変更されると scheduled_at も変わる可能性がある。
  #           古い時刻のジョブが残っていると「変更前の時刻に通知が届く」
  #           「二重通知になる」事故が起きるため、更新前に必ず削除する。
  #   Step 3: ai_update_params（限定パラメータ）で保存する
  #           優先度（priority）は ai_update_params に含めないため変更不可
  #   Step 4: 保存成功 → enqueue_alarm_job_if_needed でアラームを再スケジュール
  #           session のフラグをクリアして tasks_path へリダイレクト
  #           保存失敗 → ai_edit ビューを再描画してエラーを表示する
  #
  # 【アラームジョブの扱い】
  #   ai_edit では scheduled_at / alarm_enabled フィールドを表示しないが、
  #   タスクに既存のアラーム設定がある場合は:
  #   ① 古いジョブを削除する（cancel_existing_alarm_jobs）
  #   ② 保存後に現在の scheduled_at / alarm_enabled で再登録する（enqueue_alarm_job_if_needed）
  #   この処理をしないと、既存のアラームが意図しない時刻に発火する恐れがある。
  def ai_update
    # AI提案モーダル経由かどうかを検証する
    # session にフラグがない場合は 403 を返してここで処理が止まる
    return if verify_ai_context

    # 更新前に既存のアラームジョブを削除する
    # 【なぜ update の前に削除するのか】
    #   update が成功するかどうかに関わらず古いジョブを消しておき、
    #   update 成功時のみ新しいジョブを登録する。
    #   失敗時はジョブを登録しないため、古いアラームが残り続けることはない。
    cancel_existing_alarm_jobs(@task)

    # ai_update_params: タスク名・期限・見積時間のみ許可
    # priority は含めないため、どんなリクエストを送っても変更できない
    if @task.update(ai_update_params)
      # 保存成功後: 現在の scheduled_at / alarm_enabled 設定でアラームを再登録する
      # ai_edit フォームでは scheduled_at を変更できないが、
      # 既存設定のまま再スケジュールすることで整合性を保つ
      enqueue_alarm_job_if_needed(@task)

      # 保存成功: session のフラグをクリアしてタスク一覧へ遷移する
      # 【なぜ clear_ai_context を呼ぶのか】
      #   1回の編集が終わったら session のフラグを消す。
      #   消さないと「次回も ai_update を直接叩けてしまう」状態が続く。
      clear_ai_context

      # 【E-3実装後の変更予定】
      #   E-3（AI提案モーダル）が実装されたら
      #   redirect_to ai_proposals_path に変更する。
      #   現時点では AI提案モーダルのルートが存在しないため
      #   tasks_path（タスク一覧）へリダイレクトする。
      redirect_to tasks_path, notice: "タスクを更新しました（AI編集）"
    else
      # 保存失敗: ai_edit ビューを再描画してバリデーションエラーを表示する
      # status: :unprocessable_entity → HTTP 422 を返す
      # 422 を返す理由: フォームバリデーション失敗の標準的な HTTP ステータスコード
      render :ai_edit, status: :unprocessable_entity
    end
  end

  # ============================================================
  # toggle_complete アクション（変更なし）
  # ============================================================
  def toggle_complete
    @task.toggle_complete!
    recalculate_counts

    current_tab = params[:tab] || "all"

    respond_to do |format|
      format.turbo_stream do
        streams = []

        if @task.done?
          if current_tab == "done"
            streams << turbo_stream.remove(dom_id(@task))
          else
            streams << turbo_stream.replace(
              dom_id(@task),
              partial: "tasks/done_task_row",
              locals:  { task: @task, locked: locked? }
            )
          end
        else
          if current_tab == "done"
            streams << turbo_stream.remove(dom_id(@task))
          else
            streams << turbo_stream.replace(
              dom_id(@task),
              partial: "tasks/task_row",
              locals:  { task: @task, locked: locked? }
            )

            unless @task.ai_generated?
              streams << turbo_stream.replace(
                "task-modal-#{@task.id}",
                partial: "tasks/task_modal",
                locals:  { task: @task }
              )
            end
          end
        end

        streams << turbo_stream.replace(
          "task-tab-counts",
          partial: "tasks/tab_counts",
          locals:  {
            current_tab:  current_tab,
            must_count:   @must_count,
            should_count: @should_count,
            could_count:  @could_count,
            all_count:    @all_count
          }
        )

        current_count = case current_tab
                        when "must"   then current_user.tasks.active.not_archived.must.count
                        when "should" then current_user.tasks.active.not_archived.should.count
                        when "could"  then current_user.tasks.active.not_archived.could.count
                        when "done"   then current_user.tasks.active.where(status: Task.statuses[:done]).count
                        else               current_user.tasks.active.not_archived.count
                        end

        streams << turbo_stream.replace(
          "task-count-display",
          html: content_tag(:div,
                            "#{current_count}件のタスク",
                            id: "task-count-display",
                            class: "mt-4 text-center text-xs text-gray-400")
        )

        render turbo_stream: streams
      end

      format.html do
        redirect_to tasks_path(tab: params[:tab]),
                    notice: @task.done? ? "タスクを完了しました" : "タスクを未完了に戻しました"
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "flash-messages",
          html: content_tag(:p, "更新に失敗しました: #{e.message}", class: "text-red-600 text-sm p-4")
        )
      end
      format.html { redirect_to tasks_path, alert: "更新に失敗しました" }
    end
  end

  # ============================================================
  # archive アクション（変更なし）
  # ============================================================
  def archive
    @task.archive!
    recalculate_counts

    current_tab = params[:tab] || "done"

    done_count = current_user.tasks.active.where(status: Task.statuses[:done]).count

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(dom_id(@task)),

          turbo_stream.replace(
            "task-tab-counts",
            partial: "tasks/tab_counts",
            locals:  {
              current_tab:  current_tab,
              must_count:   @must_count,
              should_count: @should_count,
              could_count:  @could_count,
              all_count:    @all_count
            }
          ),

          turbo_stream.replace(
            "task-count-display",
            html: content_tag(:div,
                              "#{done_count}件のタスク",
                              id: "task-count-display",
                              class: "mt-4 text-center text-xs text-gray-400")
          )
        ]
      end

      format.html do
        redirect_to tasks_path(tab: "done"), notice: "タスクをアーカイブしました"
      end
    end
  end

  # ============================================================
  # archive_all_done アクション（変更なし）
  # ============================================================
  def archive_all_done
    count = current_user.tasks
                        .active
                        .where(status: Task.statuses[:done])
                        .update_all(status: Task.statuses[:archived])

    recalculate_counts

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            "done-tasks-list",
            html: content_tag(
              :p,
              "完了済みのタスクはありません",
              class: "text-sm text-gray-400 py-8 text-center"
            )
          ),

          turbo_stream.replace(
            "task-tab-counts",
            partial: "tasks/tab_counts",
            locals:  {
              current_tab:  "done",
              must_count:   @must_count,
              should_count: @should_count,
              could_count:  @could_count,
              all_count:    @all_count
            }
          ),

          turbo_stream.replace(
            "task-count-display",
            html: content_tag(:div,
                              "0件のタスク",
                              id: "task-count-display",
                              class: "mt-4 text-center text-xs text-gray-400")
          )
        ]
      end

      format.html do
        redirect_to tasks_path(tab: "done"),
                    notice: "#{count}件のタスクをアーカイブしました"
      end
    end
  end

  # ============================================================
  # destroy アクション（変更なし）
  # ============================================================
  def destroy
    if @task.ai_generated?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.prepend(
            "flash-area",
            partial: "shared/flash_message",
            locals:  { type: "alert", message: "AI生成タスクはこの方法では削除できません" }
          ), status: :forbidden
        end
        format.html do
          redirect_to tasks_path,
                      alert:  "AI生成タスクはこの方法では削除できません",
                      status: :forbidden
        end
      end
      return
    end

    return if require_unlocked

    @task.soft_delete
    recalculate_counts

    current_tab = params[:tab] || "all"

    current_count = case current_tab
                    when "must"   then current_user.tasks.active.not_archived.must.count
                    when "should" then current_user.tasks.active.not_archived.should.count
                    when "could"  then current_user.tasks.active.not_archived.could.count
                    when "done"   then current_user.tasks.active.where(status: Task.statuses[:done]).count
                    else               current_user.tasks.active.not_archived.count
                    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(dom_id(@task)),
          turbo_stream.replace(
            "task-tab-counts",
            partial: "tasks/tab_counts",
            locals:  {
              current_tab:  current_tab,
              must_count:   @must_count,
              should_count: @should_count,
              could_count:  @could_count,
              all_count:    @all_count
            }
          ),
          turbo_stream.replace(
            "task-count-display",
            html: content_tag(:div,
                              "#{current_count}件のタスク",
                              id: "task-count-display",
                              class: "mt-4 text-center text-xs text-gray-400")
          ),
          turbo_stream.prepend(
            "flash-area",
            partial: "shared/flash_message",
            locals:  { type: "notice", message: "タスクを削除しました" }
          )
        ]
      end

      format.html do
        redirect_to tasks_path(tab: current_tab), notice: "タスクを削除しました"
      end
    end
  end

  private

  # ============================================================
  # set_task（変更なし）
  # ============================================================
  def set_task
    @task = current_user.tasks.find(params[:id])
  end

  # ============================================================
  # recalculate_counts（変更なし）
  # ============================================================
  def recalculate_counts
    base_tasks = current_user.tasks.active
    priority_counts = base_tasks.not_archived.unscope(:order).group(:priority).count

    @must_count   = priority_counts[Task.priorities[:must]]   || 0
    @should_count = priority_counts[Task.priorities[:should]] || 0
    @could_count  = priority_counts[Task.priorities[:could]]  || 0
    @all_count    = @must_count + @should_count + @could_count
  end

  # ============================================================
  # C-7 追加: set_ai_context
  # ============================================================
  #
  # 【役割】
  #   ai_edit アクション（GET）が呼ばれたとき、
  #   session に ai_context フラグを立てる。
  #
  # 【session[:ai_context_task_id] に task_id を入れる理由】
  #   単純に session[:ai_context] = true にすると
  #   「どのタスクの ai_edit を経由したか」がわからなくなる。
  #   task_id を保存することで、
  #   「ai_edit で見ていたタスクとは別のタスクの ai_update を叩いた」
  #   ケースも弾ける（verify_ai_context でチェックする）。
  #
  # 【session はどこに保存されるのか】
  #   Rails のデフォルト設定では暗号化された Cookie として保存される。
  #   ユーザーが Cookie を見ても中身を解読・改ざんできないため安全。
  def set_ai_context
    session[:ai_context_task_id] = @task.id
  end

  # ============================================================
  # C-7 追加: verify_ai_context（コメント修正版）
  # ============================================================
  #
  # 【役割】
  #   ai_update アクション（PATCH）が呼ばれたとき、
  #   session の ai_context フラグを確認する。
  #
  # 【戻り値の設計（before_action 風に使うための工夫）】
  #   return if verify_ai_context という使い方をするため、
  #     - フラグなし（不正アクセスの場合）→ true を返す → ai_update の処理が止まる
  #     - フラグあり（正常）             → false を返す → ai_update の処理が続く
  #
  # 【HTTP レスポンスについて】
  #   format.html の redirect_to は常に HTTP 302 を返す。
  #   status: :forbidden を渡してもリダイレクトのステータスには影響しない。
  #   「アプリのロジック上は 403 相当の操作を拒否している」という意味で
  #   flash[:alert] にメッセージを渡し、ユーザーに通知する。
  #
  # 【チェック内容】
  #   ① session[:ai_context_task_id] が存在するか
  #   ② session に保存された task_id が @task.id と一致するか
  #   どちらかが満たされなければ不正アクセスとして処理を中断する。
  def verify_ai_context
    unless session[:ai_context_task_id] == @task.id
      respond_to do |format|
        format.html do
          # redirect_to は HTTP 302 を返す（status: を渡しても 302 になる）
          # flash[:alert] でユーザーに「不正アクセス」を通知する
          redirect_to tasks_path,
                      alert: "この操作はAI提案モーダル経由でのみ実行できます"
        end
        format.turbo_stream do
          # Turbo Stream リクエスト（fetch 経由）の場合は 403 を返す
          # head :forbidden はボディなしで HTTP 403 を返す
          head :forbidden
        end
      end
      # true を返すことで、呼び出し元の return if verify_ai_context が
      # ai_update の後続処理を止められる設計にしている
      return true
    end

    # 正常（フラグあり・task_id 一致）→ false を返して処理を続行する
    false
  end

  # ============================================================
  # C-7 追加: clear_ai_context
  # ============================================================
  #
  # 【役割】
  #   ai_update 保存成功後に session のフラグを削除する。
  #
  # 【なぜ必ず削除するのか】
  #   session にフラグを残したままにすると、
  #   別のタイミングで ai_update を直接叩いたときに
  #   フラグが残っているため 403 で弾かれない状態になってしまう。
  #   1回の ai_edit → ai_update のサイクルが完了したら
  #   必ずフラグをクリアして「次回は ai_edit から入り直す」状態に戻す。
  def clear_ai_context
    session.delete(:ai_context_task_id)
  end

  # ============================================================
  # enqueue_alarm_job_if_needed（変更なし）
  # ============================================================
  def enqueue_alarm_job_if_needed(task)
    return unless task.alarm_enabled?
    return unless task.scheduled_at.present?

    minutes_before = task.alarm_minutes_before.to_i
    notify_at = task.scheduled_at - minutes_before.minutes

    return unless notify_at > Time.current

    TaskAlarmJob.set(wait_until: notify_at).perform_later(task.id)

    Rails.logger.info "[TasksController] TaskAlarmJob をスケジュール: task_id=#{task.id}, notify_at=#{notify_at}"
  end

  # ============================================================
  # cancel_existing_alarm_jobs（変更なし）
  # ============================================================
  def cancel_existing_alarm_jobs(task)
    deleted_count = GoodJob::Job
      .where(job_class: "TaskAlarmJob")
      .where(finished_at: nil)
      .where(
        "serialized_params @> ?",
        { arguments: [ task.id ] }.to_json
      )
      .delete_all

    Rails.logger.info "[TasksController] 古いアラームジョブを削除: task_id=#{task.id}, 削除数=#{deleted_count}"
  end

  # ============================================================
  # task_params（変更なし）
  # ============================================================
  def task_params
    params.require(:task).permit(
      :title,
      :priority,
      :task_type,
      :due_date,
      :estimated_hours,
      :scheduled_at,
      :alarm_enabled,
      :alarm_minutes_before
    )
  end

  # ============================================================
  # C-7 追加: ai_update_params
  # ============================================================
  #
  # 【役割】
  #   ai_update アクション専用の Strong Parameters。
  #   通常の task_params と異なり、以下のフィールドのみ許可する:
  #     :title          → タスク名（変更可能）
  #     :due_date       → 期限日（変更可能）
  #     :estimated_hours → 見積時間（変更可能）
  #
  # 【意図的に除外しているフィールドとその理由】
  #   :priority       → AI が決定した優先度をユーザーに変えさせない
  #   :task_type      → AI 生成タスクの種別を変えると分類が壊れる
  #   :status         → 完了・アーカイブ状態を編集フォームから変えない
  #   :scheduled_at   → アラーム設定は ai_edit では扱わない
  #   :alarm_enabled  → 同上
  #   :alarm_minutes_before → 同上
  #   :ai_generated   → 強制的に true のままにする（変更不要）
  #
  # 【二重防御の考え方】
  #   ① UI（ai_edit.html.erb）で priority フィールドを読み取り専用表示にする（見た目の防御）
  #   ② ai_update_params に :priority を含めない（サーバー側の防御）
  #   どちらか一方だけでは不十分。直接 PATCH リクエストを送れば ① は無意味なため
  #   ② のサーバー側防御が必須。
  def ai_update_params
    params.require(:task).permit(
      :title,
      :due_date,
      :estimated_hours
    )
  end
end