# app/controllers/tasks_controller.rb
# （C-3 変更部分のみ抜粋 — before_action と destroy アクションを追加）
#
# ==============================================================================
# TasksController（C-3: タスク削除確認モーダル・手動タスク削除を追加）
# ==============================================================================

class TasksController < ApplicationController
  include ActionView::RecordIdentifier
  include ActionView::Helpers::TagHelper

  before_action :require_login

  # ============================================================
  # C-3 変更: before_action に :destroy を追加
  # ============================================================
  #
  # set_task:
  #   :destroy を追加することで destroy アクション実行前に
  #   current_user.tasks.find(params[:id]) で @task をセットする。
  #   他ユーザーのタスクは RecordNotFound → 404 で弾かれる（セキュリティ）。
  #
  # require_unlocked:
  #   :destroy を追加することでロック中の削除を禁止する。
  #   ロック中は「⋯」メニュー自体を非表示にするが、
  #   直接 HTTP リクエストを送られた場合もサーバー側で拒否する二重防御。
  #
  before_action :set_task, only: [ :toggle_complete, :archive, :destroy ]

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
      redirect_to tasks_path, notice: "タスクを作成しました"
    else
      render :new, status: :unprocessable_entity
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
  # C-3 追加: destroy アクション
  # ============================================================
  #
  # 【概要】
  #   手動作成タスク（ai_generated=false）を論理削除する。
  #   ai_generated=true のAI生成タスクは削除禁止（403 Forbidden）。
  #
  # 【なぜ論理削除（soft_delete）を使うのか】
  #   物理削除（destroy）すると、関連する週次振り返りスナップショットや
  #   将来の分析データとの整合性が取れなくなる可能性がある。
  #   deleted_at に現在時刻をセットする論理削除にすることで、
  #   DBにデータを残しつつUIから非表示にする。
  #
  # 【ai_generated チェックの二重防御】
  #   ① ビュー側: ai_generated=true のタスクには「⋯」メニューを表示しない
  #   ② サーバー側: このアクション内で ai_generated? の場合は 403 を返す
  #   ビューの非表示だけでは、直接 HTTP リクエストを送られると突破されるため
  #   サーバー側でも必ずチェックする（多層防御）。
  #
  # 【Turbo Stream の動作】
  #   削除後に以下を Turbo Stream で更新する:
  #   ① 削除したタスク行を一覧から除去（remove）
  #   ② タブ件数バッジを更新（replace）
  #   ③ 「○件のタスク」件数表示を更新（replace）
  #   ④ フラッシュメッセージを表示（prepend）
  #
  def destroy
    # ① AI生成タスクの削除を拒否する（最優先）
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

    # ② ロックチェック（手動タスクのみここに到達する）
    return if require_unlocked

    # ③ 論理削除を実行する
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

  def set_task
    @task = current_user.tasks.find(params[:id])
  end

  def recalculate_counts
    base_tasks = current_user.tasks.active
    priority_counts = base_tasks.not_archived.unscope(:order).group(:priority).count

    @must_count   = priority_counts[Task.priorities[:must]]   || 0
    @should_count = priority_counts[Task.priorities[:should]] || 0
    @could_count  = priority_counts[Task.priorities[:could]]  || 0
    @all_count    = @must_count + @should_count + @could_count
  end

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
end