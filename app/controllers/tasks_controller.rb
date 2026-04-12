# app/controllers/tasks_controller.rb
#
# ==============================================================================
# TasksController（C-5 変更: アラームジョブのエンキュー・再スケジュールを追加）
# ==============================================================================
#
# 【C-5 での変更点】
#   1. create アクション: タスク保存後にアラームジョブをエンキュー
#   2. update アクション: 新規追加。タスク更新後に古いジョブを削除して再エンキュー
#   3. enqueue_alarm_job_if_needed: アラーム条件チェックとジョブ予約
#   4. cancel_existing_alarm_jobs: 既存ジョブの安全な削除
# ==============================================================================

class TasksController < ApplicationController
  include ActionView::RecordIdentifier
  include ActionView::Helpers::TagHelper

  before_action :require_login

  # before_action :set_task
  # 【なぜ :update を追加するのか】
  #   update アクションでも @task を事前に取得する必要がある。
  #   current_user.tasks.find(params[:id]) とすることで
  #   他ユーザーのタスクへのアクセスを RecordNotFound（404）で弾く。
  before_action :set_task, only: [ :toggle_complete, :archive, :destroy, :update ]

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
  # create アクション（C-5 変更: ジョブエンキューを追加）
  # ============================================================
  #
  # 【C-5 での変更点】
  #   タスク保存成功後、alarm_enabled=true かつ scheduled_at が設定されていれば
  #   TaskAlarmJob をスケジュールする処理を追加した。
  def create
    return if require_unlocked

    @task = current_user.tasks.build(task_params)

    if @task.save
      # --------------------------------------------------------
      # C-5 追加: アラームジョブのエンキュー
      # --------------------------------------------------------
      # 条件を満たす場合のみジョブを予約する（詳細は enqueue_alarm_job_if_needed を参照）
      enqueue_alarm_job_if_needed(@task)

      redirect_to tasks_path, notice: "タスクを作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # update アクション（C-5 新規追加）
  # ============================================================
  #
  # 【なぜ update が必要か】
  #   scheduled_at や alarm_minutes_before を後から変更した場合、
  #   古い時刻でスケジュールされたジョブがそのまま残ってしまう。
  #   → 「変更前の時刻に通知が届く」「二重通知になる」事故が起きる。
  #
  # 【対策】
  #   更新前に古いジョブを削除し、更新後に新しいジョブを再登録する。
  #
  # 【ロック中でも update を許可するか】
  #   タスクの内容変更（scheduled_at の変更）は「タスクの編集」に当たるため
  #   ロック中は制限する（require_unlocked を通す）。
  def update
    return if require_unlocked

    # 更新前に既存のアラームジョブを削除する
    # 【なぜ update の前に削除するのか】
    #   update が成功するかどうかに関わらず古いジョブを消しておき、
    #   update 成功時のみ新しいジョブを登録する（失敗時はジョブを登録しない）。
    cancel_existing_alarm_jobs(@task)

    if @task.update(task_params)
      # 更新後の内容でジョブを再スケジュールする
      enqueue_alarm_job_if_needed(@task)

      redirect_to tasks_path, notice: "タスクを更新しました"
    else
      render :edit, status: :unprocessable_entity
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

  # ============================================================
  # C-5 追加: enqueue_alarm_job_if_needed
  # ============================================================
  #
  # 【役割】
  #   アラーム条件を確認し、必要なら TaskAlarmJob をスケジュールする。
  #   create と update の両方から呼び出す。
  #
  # 【scheduled_at のタイムゾーンについて】
  #   Rails は DB から取得した datetime を自動的に UTC の ActiveSupport::TimeWithZone
  #   オブジェクトとして扱う。
  #   Time.current も UTC ベースの ActiveSupport::TimeWithZone を返すため、
  #   notify_at > Time.current の比較は同一基準で行われ正確に機能する。
  #   「ユーザーのタイムゾーンで表示する」処理はメールビュー側（in_time_zone）で行う。
  #   スケジュールの計算自体は UTC で統一するのが正しい設計。
  def enqueue_alarm_job_if_needed(task)
    # アラームが有効でない場合は何もしない
    return unless task.alarm_enabled?

    # scheduled_at が設定されていない場合は何もしない
    return unless task.scheduled_at.present?

    # alarm_minutes_before が未設定の場合は 0 として扱う
    minutes_before = task.alarm_minutes_before.to_i

    # 通知時刻を計算する（UTC で計算する・Rails が自動で UTC 管理するため一致する）
    notify_at = task.scheduled_at - minutes_before.minutes

    # 通知時刻が過去なら何もしない（過去時刻のアラームは不要）
    return unless notify_at > Time.current

    # GoodJob でジョブを指定時刻にスケジュールする
    # 【set(wait_until:) の意味】
    #   notify_at の時刻が来たらジョブを実行するよう good_jobs テーブルに登録する。
    #   GoodJob はポーリング（30秒ごと）または LISTEN/NOTIFY でこの時刻を検知して実行する。
    TaskAlarmJob.set(wait_until: notify_at).perform_later(task.id)

    Rails.logger.info "[TasksController] TaskAlarmJob をスケジュール: task_id=#{task.id}, notify_at=#{notify_at}"
  end

  # ============================================================
  # C-5 追加: cancel_existing_alarm_jobs（update 時に使用）
  # ============================================================
  #
  # 【役割】
  #   タスク更新時に、まだ実行されていない古いアラームジョブを削除する。
  #
  # 【なぜ LIKE 検索ではなく job_class + serialized_params を使うのか】
  #   レビューで指摘のあった LIKE 検索（"%#{task.id}%"）には以下のリスクがある:
  #   1. task.id が 1 の場合、id=10, 100 なども誤ってマッチする（誤削除）
  #   2. 将来的に serialized_params の JSON 構造が変わるとマッチしなくなる
  #
  #   正しい方法は GoodJob の構造を利用して:
  #   - job_class が "TaskAlarmJob" であること
  #   - serialized_params の arguments に task_id が含まれること
  #   - finished_at が nil（まだ実行されていない）であること
  #   の3条件で絞り込む。
  #
  # 【serialized_params の構造（GoodJob が保存する JSON）】
  #   {
  #     "job_class": "TaskAlarmJob",
  #     "arguments": [1],   ← task.id が入る
  #     ...
  #   }
  #
  # 【@>（JSONB containment operator）とは】
  #   PostgreSQL の JSONB 型専用演算子。
  #   左辺の JSONB が右辺の JSONB を「含む」かどうかを判定する。
  #   例: '{"a":1,"b":2}'::jsonb @> '{"a":1}'::jsonb → true
  #   LIKE よりも正確で、インデックスも効くため高速。
  def cancel_existing_alarm_jobs(task)
    deleted_count = GoodJob::Job
      .where(job_class: "TaskAlarmJob")
      .where(finished_at: nil)
      .where(
        "serialized_params @> ?",
        # arguments 配列の最初の要素が task.id と一致するものを取得する
        # to_json で正しい JSON 文字列 {"arguments":[1]} を生成する
        { arguments: [ task.id ] }.to_json
      )
      .delete_all

    Rails.logger.info "[TasksController] 古いアラームジョブを削除: task_id=#{task.id}, 削除数=#{deleted_count}"
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