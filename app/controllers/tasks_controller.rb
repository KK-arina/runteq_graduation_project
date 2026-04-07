# app/controllers/tasks_controller.rb
#
# ==============================================================================
# TasksController（C-1: 基本CRUD実装）
# ==============================================================================
#
# 【このファイルの役割】
#   タスクの一覧表示・新規作成を担当するコントローラー。
#
# 【C-1 で実装するアクション】
#   index  → GET  /tasks        → タスク一覧ページ（9番画面）
#   new    → GET  /tasks/new    → タスク新規作成ページ（10番画面）
#   create → POST /tasks        → タスク作成処理
#
# 【before_action の設計】
#   require_login:
#     ApplicationController で定義済み。
#     未ログインユーザーをログインページにリダイレクトする。
#     全アクションに適用（only: は指定しない）。
#
# 【セキュリティ設計】
#   current_user.tasks で検索することで、
#   他のユーザーのタスクには絶対にアクセスできない設計にする。
#   tasks.find(id) ではなく current_user.tasks.find(id) を使う。
# ==============================================================================

class TasksController < ApplicationController
  # before_action :require_login
  #   全アクション実行前にログイン確認を行う。
  #   ログインしていない場合は require_login がリダイレクトして
  #   アクションの処理を中断する。
  before_action :require_login

  # ============================================================
  # index アクション
  # ============================================================
  # GET /tasks
  # タスク一覧ページを表示する（9番画面）。
  #
  # 【フィルタタブの実装方針】
  #   params[:tab] でどのタブが選択されているかを判断する。
  #   タブ: all（全て）/ must / should / could / done（完了済み）
  #   デフォルトは "all"。
  #
  # 【@tasks の取得設計】
  #   current_user.tasks → 自分のタスクのみ（他ユーザーのタスクは取得しない）
  #   .active            → 論理削除されていないもの
  #   タブに応じてさらに絞り込む。
  def index
    @locked = locked?

    # 選択中のタブを params[:tab] から取得する。
    # params[:tab] が nil（タブ未指定）の場合は "all" をデフォルトにする。
    # || "all": params[:tab] が nil または空文字の場合に "all" を使う Ruby の演算子。
    @current_tab = params[:tab] || "all"

    # ベースとなるタスクのクエリを組み立てる。
    # current_user.tasks:
    #   has_many :tasks で定義された関連を使い、ログイン中ユーザーのタスクのみを取得する。
    #   SQL: WHERE user_id = current_user.id
    #
    # .active:
    #   Task モデルの scope :active → WHERE deleted_at IS NULL ORDER BY priority, due_date, created_at
    base_tasks = current_user.tasks.active

    # タブに応じてクエリを絞り込む。
    # case 文で @current_tab の値に応じて異なるスコープを適用する。
    @tasks = case @current_tab
             when "must"
               # Must（絶対にやる）タスクのみ表示。
               # .not_archived で完了・アーカイブ済みを除外する。
               base_tasks.not_archived.must
             when "should"
               # Should（できればやる）タスクのみ表示。
               base_tasks.not_archived.should
             when "could"
               # Could（余裕があればやる）タスクのみ表示。
               base_tasks.not_archived.could
             when "done"
               # 完了済み（done または archived）タスクを表示する。
               # not_archived は適用しない（完了タブなのでアーカイブも含める）。
               base_tasks.where(status: [ Task.statuses[:done], Task.statuses[:archived] ])
             else
               # "all"（デフォルト）: 未完了・進行中のタスクを表示する。
               # done と archived は「完了済みタブ」に移動するので通常の一覧には含めない。
               base_tasks.not_archived
             end

    # タスクの件数をタブごとに集計する。
    # タブのバッジ（件数表示）に使う。
    #
    # 【修正理由】
    # base_tasks は scope :active を含んでおり、
    # ORDER BY priority ASC, due_date ASC NULLS LAST が付いている。
    # PostgreSQL では GROUP BY priority のとき、
    # SELECT / ORDER BY に含まれるカラムは GROUP BY にも含める必要がある。
    # due_date が ORDER BY に含まれているため PG::GroupingError が発生する。
    #
    # 【解決方法】
    # unscope(:order) で scope :active が付けた ORDER BY を除去してから
    # GROUP BY を実行する。
    # unscope(:order) は ORDER BY 句だけを取り除き、WHERE 句は保持する。
    # そのため「deleted_at IS NULL」「status != archived」の絞り込みは維持される。
    priority_counts = base_tasks.not_archived.unscope(:order).group(:priority).count

    # priority_counts は { 0 => 3, 1 => 2 } のような整数キーのハッシュになるため、
    # Task.priorities で整数に変換してアクセスする。
    # Task.priorities は { "must" => 0, "should" => 1, "could" => 2 } を返す。
    @must_count   = priority_counts[Task.priorities[:must]]   || 0
    @should_count = priority_counts[Task.priorities[:should]] || 0
    @could_count  = priority_counts[Task.priorities[:could]]  || 0

    # 未完了タスクの合計件数（all タブのバッジ用）
    @all_count = @must_count + @should_count + @could_count
  end

  # ============================================================
  # new アクション
  # ============================================================
  # GET /tasks/new
  # タスク新規作成フォームを表示する（10番画面）。
  #
  # @task = Task.new:
  #   空の Task インスタンスを作成してビューに渡す。
  #   form_with model: @task はこのインスタンスを元に
  #   <form action="/tasks" method="post"> を生成する。
  #   （@task が保存済みなら action="/tasks/1" method="patch" になる）
  #
  # require_unlocked を before_action に追加しない理由:
  #   new アクション（フォーム表示）は参照のみなのでロックに関係なく表示する。
  #   create アクション（保存処理）にのみロックチェックを入れる。
  def new
    @task = Task.new
    # デフォルトの優先度を should にしておく（schema.rb の default に合わせる）
    @task.priority = :should
  end

  # ============================================================
  # create アクション
  # ============================================================
  # POST /tasks
  # フォームから送信されたデータでタスクを作成する。
  #
  # require_unlocked（ロックチェック）:
  #   ロック中は create アクション実行前に ApplicationController の
  #   require_unlocked が呼ばれてリダイレクトされる。
  #   before_action として定義せず、アクション内で直接呼び出す理由:
  #     index / new はロックに関係なく表示するが、
  #     create のみロックを適用したいから。
  #     before_action で only: [:create] と書いても同じだが、
  #     アクション内に書く方がロックの対象範囲が明確になる。
  def create
    # ロックチェック。ロック中は require_unlocked がリダイレクトして
    # この行以降のコードは実行されない。
    return if require_unlocked

    # Task.new(task_params):
    #   Strong Parameters（task_params メソッド）で許可したパラメータのみで
    #   Task オブジェクトを作成する。
    #   current_user を設定することで、必ずログイン中ユーザーのタスクになる。
    @task = current_user.tasks.build(task_params)

    if @task.save
      # 保存成功: タスク一覧ページにリダイレクトする。
      # flash[:notice] でトースト通知（「タスクを作成しました」）を表示する。
      redirect_to tasks_path, notice: "タスクを作成しました"
    else
      # 保存失敗: フォームを再表示してエラーメッセージを見せる。
      # render :new → app/views/tasks/new.html.erb を描画する。
      # status: :unprocessable_entity:
      #   HTTP ステータス 422 を返す。
      #   Turbo Drive はこのステータスを見てページ遷移せずに
      #   フォームを再描画するための挙動をとる。
      render :new, status: :unprocessable_entity
    end
  end

  # ============================================================
  # private メソッド
  # ============================================================
  private

  # task_params（Strong Parameters）
  #   フォームから受け取るパラメータを明示的に許可する。
  #   ホワイトリスト方式: ここで許可したパラメータのみが
  #   Task.new() に渡される。
  #   許可していないパラメータ（例: ai_generated: true）は無視される。
  #
  # params.require(:task):
  #   フォームデータが { task: { title: "...", priority: "..." } } の形式で
  #   送られてくることを期待する。
  #   :task キーが存在しない場合は ActionController::ParameterMissing エラーになる。
  #
  # .permit(...):
  #   許可するカラム名を列挙する。
  #
  # 許可するパラメータの説明:
  #   :title          → タスク名（必須）
  #   :priority       → 優先度（must/should/could）
  #   :task_type      → 種別（normal/habit/improve）
  #   :due_date       → 期限日（任意）
  #   :estimated_hours→ 見積時間（任意）
  #   :scheduled_at   → 実施予定日時（任意）
  #   :alarm_enabled  → アラームON/OFF（任意）
  #   :alarm_minutes_before → 何分前に通知するか（任意）
  #
  # 許可しないパラメータ（セキュリティ上の理由）:
  #   :ai_generated → AI 生成フラグ。ユーザーが直接設定できないようにする。
  #   :status       → タスクの状態。作成時は todo が自動設定される。
  #   :completed_at → 完了日時。完了操作（C-2）で別途設定する。
  #   :deleted_at   → 論理削除。削除操作（C-3）で別途設定する。
  #   :habit_id     → AI 提案から設定されるもの。ユーザーが直接設定しない。
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