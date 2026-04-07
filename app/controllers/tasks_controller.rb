# app/controllers/tasks_controller.rb
#
# ==============================================================================
# TasksController（C-2: 完了チェック・ステータス管理を追加）
# ==============================================================================
#
# 【C-2 エラー修正】
#   dom_id / content_tag はビューヘルパーメソッドのため、
#   コントローラーからそのまま呼ぶと NoMethodError になる。
#
#   解決方法: 必要なヘルパーモジュールを include する。
#
#   ActionView::RecordIdentifier:
#     dom_id / dom_class を提供するモジュール。
#     dom_id(@task) → "task_1" のような文字列を生成する。
#     Turbo Stream の replace / remove のターゲット id に使う。
#
#   ActionView::Helpers::TagHelper:
#     content_tag を提供するモジュール。
#     content_tag(:p, "テキスト", class: "...") → <p class="...">テキスト</p>
#     archive_all_done の Turbo Stream レスポンスで空状態のHTMLを生成するために使う。
#
#   なぜコントローラーに include するのか:
#     Rails のコントローラーはデフォルトでビューヘルパーを持っていない。
#     ビューヘルパーはビューファイル（.html.erb）でのみ自動で使える。
#     コントローラーのアクション内で使うには明示的に include が必要。
# ==============================================================================

class TasksController < ApplicationController
  # ============================================================
  # ビューヘルパーの include（C-2 追加）
  # ============================================================

  # ActionView::RecordIdentifier を include することで
  # dom_id / dom_class がコントローラー内で使えるようになる
  include ActionView::RecordIdentifier

  # ActionView::Helpers::TagHelper を include することで
  # content_tag がコントローラー内で使えるようになる
  include ActionView::Helpers::TagHelper

  before_action :require_login
  before_action :set_task, only: [ :toggle_complete, :archive ]

  # ============================================================
  # index アクション（C-1 から変更なし）
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
              # 【C-2 修正】done のみ（archived を除外する）
              # 修正前: where(status: [done, archived])
              # 修正後: where(status: :done) のみ
              #
              # 理由:
              #   archived タスクは「非表示」が正しい設計（パターンA採用）。
              #   done タブに archived を混ぜると
              #   「アーカイブボタンが出ない archived タスク」が表示されて混乱する。
              #   archived は DB に保持するが UI からは見えなくする。
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
  # new アクション（C-1 から変更なし）
  # ============================================================
  def new
    @task = Task.new
    @task.priority = :should
  end

  # ============================================================
  # create アクション（C-1 から変更なし）
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
  # C-2 修正: toggle_complete アクション
  # ============================================================
  # 【修正内容】
  #   「全て」タブでチェックしたとき、行が消えてしまう問題を修正する。
  #
  # 【問題の原因】
  #   done タブにいないとき id="done-tasks-list" が存在しないため
  #   prepend は何も起きない。しかし remove は成功してしまい
  #   タスク行が消えるだけになっていた。
  #
  # 【修正方針】
  #   現在のタブによって動作を分岐する:
  #
  #   done タブを見ているとき（toggle で未完了→完了）:
  #     → remove + prepend（done リストに移動）
  #
  #   done タブ以外を見ているとき（toggle で未完了→完了）:
  #     → その場で replace（取り消し線付きに変える）のみ
  #     → 行を消さない。完了タブへの移動はタブ遷移で確認できる。
  #
  #   done タブで完了→未完了に戻すとき:
  #     → remove（done リストから削除）+ prepend（active リストに追加）
  def toggle_complete
    @task.toggle_complete!
    recalculate_counts

    current_tab = params[:tab] || "all"

    respond_to do |format|
      format.turbo_stream do
        streams = []

        if @task.done?
          # ────────────────────────────────────────────────────
          # 未完了 → 完了 の場合
          # ────────────────────────────────────────────────────
          if current_tab == "done"
            # done タブで操作することは通常ないが念のため対処
            streams << turbo_stream.remove(dom_id(@task))
          else
            # 「全て」「Must」「Should」「Could」タブのとき:
            #   行をその場で「完了タスク行」に replace する（消さない）。
            #   ページリロードなしで取り消し線・チェック済みの見た目に変わる。
            #   ユーザーが「完了済み」タブに切り替えると移動したタスクが見える。
            #
            #   【なぜ remove + prepend にしないのか】
            #     done タブにいないため id="done-tasks-list" が存在せず
            #     prepend の行先が見つからない。
            #     remove だけ成功してタスクが消えるより、
            #     その場で完了の見た目に変えるほうが UX が良い。
            streams << turbo_stream.replace(
              dom_id(@task),
              partial: "tasks/done_task_row",
              locals:  { task: @task, locked: locked? }
            )
          end
        else
          # ────────────────────────────────────────────────────
          # 完了 → 未完了 の場合
          # ────────────────────────────────────────────────────
          if current_tab == "done"
            # done タブで完了を外した場合:
            #   done リストから削除して active リストに戻す。
            #   ただし active リストは別タブにあるため prepend 先が存在しない。
            #   remove だけ実行してタスクを done タブから消す。
            #   ユーザーが「全て」タブに戻るとタスクが復元されている。
            streams << turbo_stream.remove(dom_id(@task))
          else
            # 「全て」等のタブで完了を外した場合（通常は完了タスクが表示されている状態）:
            #   その場で「未完了タスク行」に replace する。
            streams << turbo_stream.replace(
              dom_id(@task),
              partial: "tasks/task_row",
              locals:  { task: @task, locked: locked? }
            )
          end
        end

        # タブ件数バッジを更新する
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

        # ────────────────────────────────────────────────────
        # タスク件数表示（「○件のタスク」）を更新する
        # ────────────────────────────────────────────────────
        # 【問題の原因】
        #   「○件のタスク」はビュー上の @tasks.count を表示しているが、
        #   @tasks はこのアクションでは存在しない。
        #   Turbo Stream で件数テキストも同時に更新する必要がある。
        #
        # 【修正方針】
        #   id="task-count-display" の要素を Turbo Stream で更新する。
        #   index.html.erb 側でこの id を付ける（後述）。
        #
        # 現在表示中のタスク件数を計算する
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
  # archive アクション（C-2 追加）
  # ============================================================
  # PATCH /tasks/:id/archive
  #
  # 【概要】
  #   完了タスクの「アーカイブ」ボタンを押すと呼ばれるアクション。
  #   @task.status を archived（3）に変更する。
  #
  # 【ロック制限について】
  #   アーカイブはロック中でも可能な設計にする。
  #   完了したタスクを整理する操作なので、
  #   ロックの「新規追加・編集・削除をブロック」には該当しない。
  #
  # 【Turbo Stream の動作】
  #   アーカイブしたタスクを一覧から消す（remove）。
  #   タブの件数バッジは変わらないが（archived は done タブに残るため）
  #   表示上の「完了タブ」の行が消えた際の空判定を更新する。
  def archive
    @task.archive!
    recalculate_counts

    current_tab = params[:tab] || "done"

    # アーカイブ後の done タスク件数
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

          # 件数表示を更新する
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
  # archive_all_done アクション（C-2 追加）
  # ============================================================
  # PATCH /tasks/archive_all_done
  #
  # 【概要】
  #   「すべてアーカイブ」ボタンを押すと呼ばれるアクション。
  #   ログイン中ユーザーの完了済み（done）タスクを一括で archived に変更する。
  #
  # 【update_all を使う理由】
  #   each do |task| task.archive! end と書くと
  #   タスクの件数分だけ UPDATE SQL が発行される（N+1）。
  #   update_all を使うと1回の SQL で全件更新できる（高速・効率的）。
  #
  #   注意: update_all はコールバック・バリデーションをスキップする。
  #   今回は status カラムの変更のみなので問題ない。
  #   completed_at は変更しない（完了日時の記録を保持する）。
  #
  # 【Turbo Stream の動作】
  #   完了タブ全体のタスク一覧を再描画する代わりに、
  #   個別行を remove するのではなく完了タブの空状態を表示する。
  #   id="done-tasks-list" の要素を空のHTMLで置き換える。
  # archive_all_done アクション（修正版）
  #
  # 【修正内容】
  #   「すべてアーカイブ」後に「○件のタスク」が更新されない問題を修正する。
  #
  # 【問題の原因】
  #   archive_all_done では id="task-count-display" の Turbo Stream 更新が
  #   実装されていなかった。
  #   toggle_complete / archive には追加したが、
  #   archive_all_done への追加を漏らしていた。
  def archive_all_done
    count = current_user.tasks
                        .active
                        .where(status: Task.statuses[:done])
                        .update_all(status: Task.statuses[:archived])

    recalculate_counts

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # 完了タスク一覧エリアを空の状態に置き換える
          turbo_stream.replace(
            "done-tasks-list",
            html: content_tag(
              :p,
              "完了済みのタスクはありません",
              class: "text-sm text-gray-400 py-8 text-center"
            )
          ),

          # タブ件数バッジを更新する
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

          # ────────────────────────────────────────────────────
          # 「○件のタスク」件数表示を更新する（修正追加）
          # ────────────────────────────────────────────────────
          # すべてアーカイブ後は done タスクが 0 件になるため
          # 件数表示を 0 に更新する。
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

  private

  # set_task
  #   before_action で呼ばれる。
  #   params[:id] に対応するタスクを @task にセットする。
  #
  #   current_user.tasks.find(params[:id]):
  #     current_user.tasks → ログイン中ユーザーのタスクのみを対象にする。
  #     .find(params[:id]) → id が一致するタスクを取得する。
  #     他ユーザーのタスクはこのスコープに含まれないため、
  #     アクセスしようとすると ActiveRecord::RecordNotFound が発生し、
  #     ApplicationController の rescue_from で 404 が返る（セキュリティ）。
  def set_task
    @task = current_user.tasks.find(params[:id])
  end

  # recalculate_counts
  #   タブの件数バッジを Turbo Stream で更新するための再計算メソッド。
  #   toggle_complete / archive / archive_all_done の後に呼ぶ。
  #
  #   なぜ再計算が必要か:
  #     タスクの status が変わると、各タブの件数も変わる。
  #     Turbo Stream でタブバッジを更新するためにインスタンス変数に格納する。
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