# app/controllers/habits_controller.rb
#
# ==============================================================================
# HabitsController（D-8 変更: ai_edit / ai_update アクションを追加）
# ==============================================================================
#
# 【D-8 での変更点】
#   1. before_action :set_habit に :ai_edit / :ai_update を追加
#   2. ai_edit アクション: AI提案モーダル経由のみアクセス可能な習慣編集フォームを表示
#   3. ai_update アクション: ai_edit フォームの保存処理
#   4. require_unlocked の対象に :ai_update を追加
#      （AI経由でも PDCAロック中は習慣の更新を拒否するため）
#   5. private に set_ai_context / verify_ai_context / clear_ai_context /
#      ai_update_params を追加
#
# 【C-7（TasksController）との対称性】
#   tasks の ai_edit / ai_update と全く同じ session フラグ方式を採用。
#   コードベース全体でパターンを統一することで、
#   将来の保守・レビューが容易になる。
# ==============================================================================

class HabitsController < ApplicationController
  before_action :require_login

  # ============================================================
  # before_action :require_unlocked（D-8 変更: :ai_update を追加）
  # ============================================================
  #
  # 【:ai_update を追加する理由】
  #   AI提案モーダル経由でも、PDCAロック中は習慣の更新を禁止する。
  #   ロックは「振り返りを完了するまで新規追加・編集をブロックする」仕組みであり、
  #   AI経由かどうかに関わらず適用すべきルール。
  #
  # 【:ai_edit を追加しない理由】
  #   ai_edit は「フォームを表示する」だけで DB を変更しない（GET リクエスト）。
  #   ロック中でも編集画面を表示して「ロック中は保存できない」ことを
  #   ユーザーに伝えるほうが UX として自然。
  before_action :require_unlocked, only: [ :create, :update, :destroy, :archive, :sort, :ai_update ]

  # ============================================================
  # before_action :set_habit（D-8 変更: :ai_edit / :ai_update を追加）
  # ============================================================
  #
  # 【:ai_edit / :ai_update に set_habit を追加する理由】
  #   どちらのアクションも params[:id] で特定の習慣を取得する必要がある。
  #   set_habit は current_user.habits.where(deleted_at: nil).find(params[:id]) で
  #   取得するため、他ユーザーの習慣 ID を指定されても
  #   RecordNotFound（404）で弾ける（認可チェックを兼ねる）。
  before_action :set_habit, only: [ :edit, :update, :destroy, :archive, :unarchive, :ai_edit, :ai_update ]

  # ============================================================
  # GET /habits
  # ============================================================
  def index
    @habits = current_user.habits.active
                          .includes(:habit_excluded_days)

    today = HabitRecord.today_for_record
    @today_records_hash = HabitRecord
      .where(user: current_user, habit: @habits, record_date: today)
      .index_by(&:habit_id)

    @habit_stats = build_habit_stats(@habits, current_user)
    @locked      = locked?
  end

  # ============================================================
  # GET /habits/archived
  # ============================================================
  def archived
    @archived_habits = current_user.habits.archived
                                   .includes(:habit_excluded_days)
                                   .order(archived_at: :desc)
  end

  # ============================================================
  # GET /habits/new
  # ============================================================
  def new
    @habit = current_user.habits.build
  end

  # ============================================================
  # GET /habits/:id/edit
  # ============================================================
  def edit
  end

  # ============================================================
  # PATCH /habits/:id
  # ============================================================
  def update
    result = ApplicationRecord.with_transaction do
      @habit.update!(habit_params)
      save_excluded_days!(@habit, params[:excluded_day_numbers])
      true
    end

    if result
      flash[:notice] = "習慣を更新しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の更新に失敗しました"
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "習慣の更新に失敗しました"
    render :edit, status: :unprocessable_entity
  end

  # ============================================================
  # POST /habits
  # ============================================================
  def create
    @habit = current_user.habits.build(habit_params)

    result = ApplicationRecord.with_transaction do
      @habit.save!
      save_excluded_days!(@habit, params[:excluded_day_numbers])
      true
    end

    if result
      flash[:notice] = "習慣を登録しました"
      redirect_to habits_path
    else
      flash.now[:alert] = "習慣の登録に失敗しました"
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "習慣の登録に失敗しました"
    render :new, status: :unprocessable_entity
  end

  # ============================================================
  # DELETE /habits/:id
  # ============================================================
  def destroy
    if @habit.soft_delete
      flash[:notice] = "習慣を削除しました"
      redirect_to habits_path, status: :see_other
    else
      flash[:alert] = "習慣の削除に失敗しました"
      redirect_to habits_path, status: :see_other
    end
  end

  # ============================================================
  # POST /habits/:id/archive
  # ============================================================
  def archive
    @habit.archive!
    flash[:notice] = "「#{@habit.name}」をアーカイブしました"
    redirect_to habits_path, status: :see_other
  rescue ActiveRecord::RecordInvalid
    flash[:alert] = "アーカイブに失敗しました"
    redirect_to habits_path, status: :see_other
  end

  # ============================================================
  # PATCH /habits/:id/unarchive
  # ============================================================
  def unarchive
    @habit.unarchive!
    flash[:notice] = "「#{@habit.name}」を復元しました"
    redirect_to archived_habits_path, status: :see_other
  rescue RuntimeError => e
    flash[:alert] = e.message
    redirect_to archived_habits_path, status: :see_other
  rescue ActiveRecord::RecordInvalid
    flash[:alert] = "復元に失敗しました"
    redirect_to archived_habits_path, status: :see_other
  end

  # ============================================================
  # PATCH /habits/sort（B-6 実装済み）
  # ============================================================
  def sort
    habit_ids = Array(params[:habit_ids])

    habit_ids.each_with_index do |habit_id, index|
      habit = current_user.habits.find_by(id: habit_id)
      next unless habit
      habit.insert_at(index + 1)
    end

    head :ok
  end

  # ============================================================
  # D-8 追加: ai_edit アクション
  # ============================================================
  #
  # 【このアクションの役割】
  #   AI提案モーダルの「✏️ 習慣を編集」リンクをクリックしたときに呼ばれる。
  #   8番（習慣編集ページ・AI経由限定）を表示する。
  #
  # 【アクセス制御の流れ】
  #   Step 1: set_ai_context を呼んで session に ai_context フラグを立てる
  #           「どの習慣の ai_edit を経由したか」を task_id ならぬ habit_id で記録する
  #   Step 2: @habit を表示用に準備して app/views/habits/ai_edit.html.erb を描画する
  #
  # 【なぜ session を使うのか】
  #   「AI提案モーダルから来たかどうか」はサーバー側で証明が必要。
  #   URL パラメータ（?from=ai_modal など）はユーザーが直接書き換えられる。
  #   session はサーバーが暗号化して Cookie に保存するため改ざんできない。
  #   C-7（tasks#ai_edit）と全く同じ方式を採用しコードパターンを統一する。
  #
  # 【E-3（AI提案モーダル）未実装時の動作】
  #   E-3 が実装されるまでは、直接 URL で
  #   GET /habits/:id/ai_edit にアクセスして動作確認する。
  #   E-3 実装後はモーダルの「編集」ボタンから自動的に遷移する。
  def ai_edit
    # AI提案モーダル経由であることを session に記録する
    # 詳細は private の set_ai_context を参照
    set_ai_context

    # @habit は before_action :set_habit で取得済み
    # ai_edit.html.erb をレンダリングする（明示的な render は不要）
  end

  # ============================================================
  # D-8 追加: ai_update アクション
  # ============================================================
  #
  # 【このアクションの役割】
  #   ai_edit フォームの送信先。
  #   習慣名・週次目標・除外日を保存して、習慣一覧に戻る。
  #   （E-3実装後は AI提案モーダルに戻るよう変更する）
  #
  # 【アクセス制御の流れ】
  #   Step 1: verify_ai_context で session のフラグを確認する
  #           フラグなし → 403 相当のリダイレクトで処理を中断する
  #   Step 2: ai_update_params（限定パラメータ）でトランザクション内で保存する
  #           measurement_type は ai_update_params に含めないため変更不可
  #   Step 3: 保存成功 → session のフラグをクリアして habits_path へリダイレクト
  #           保存失敗 → ai_edit ビューを再描画してエラーを表示する
  #
  # 【トランザクションを使う理由】
  #   習慣の update! と除外日の save_excluded_days! は
  #   A-7 の設計原則に従い、必ず1つのトランザクションで包む。
  #   片方が失敗したとき、もう片方もロールバックされる。
  #
  # 【E-3 実装後の変更予定】
  #   E-3（AI提案モーダル）が実装されたら
  #   redirect_to session[:ai_proposal_return_path] のように
  #   モーダルへの戻りパスをセッションに持たせる設計に変更する。
  #   現時点では AI提案モーダルのルートが存在しないため
  #   habits_path（習慣一覧）へリダイレクトする。
  def ai_update
    # AI提案モーダル経由かどうかを検証する
    # session にフラグがない場合は redirect して処理が止まる
    # verify_ai_context が true を返したとき（=不正アクセス）は後続処理を止める
    return if verify_ai_context

    # トランザクション内で習慣と除外日を一括更新する
    # A-7 の設計原則: 複数テーブルにまたがる更新は必ずトランザクションで包む
    result = ApplicationRecord.with_transaction do
      # ai_update_params: 習慣名・週次目標のみ許可
      # measurement_type は含めないため変更不可（二重防御のサーバー側）
      @habit.update!(ai_update_params)
      # 除外日も同じトランザクション内で保存する
      save_excluded_days!(@habit, params[:excluded_day_numbers])
      true
    end

    if result
      # 保存成功: session のフラグをクリアして習慣一覧へ遷移する
      # clear_ai_context: 1回の ai_edit → ai_update が完了したらフラグを消す
      clear_ai_context

      # 【E-3実装後の変更予定】
      #   E-3（AI提案モーダル）が実装されたら
      #   モーダルへのリダイレクトに変更する。
      flash[:notice] = "習慣を更新しました（AI編集）"
      redirect_to habits_path
    else
      # 保存失敗: ai_edit ビューを再描画してバリデーションエラーを表示する
      # status: :unprocessable_entity → HTTP 422 を返す（フォームバリデーション失敗の標準）
      render :ai_edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    # RecordInvalid は update! が失敗したときに発生する
    # バリデーションエラーは @habit.errors に入っているので ai_edit を再描画する
    render :ai_edit, status: :unprocessable_entity
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  def habit_params
    params.require(:habit).permit(:name, :weekly_target, :measurement_type, :unit, :color, :icon)
  end

  def set_habit
    @habit = current_user.habits.where(deleted_at: nil).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "習慣が見つかりませんでした"
    redirect_to habits_path
  end

  def save_excluded_days!(habit, excluded_day_params)
    habit.habit_excluded_days.destroy_all
    return if excluded_day_params.blank?
    day_numbers = Array(excluded_day_params)
                    .map(&:to_i)
                    .select { |d| d.between?(0, 6) }
                    .uniq
    day_numbers.each do |day|
      habit.habit_excluded_days.create!(day_of_week: day)
    end
  end

  def build_habit_stats(habits, user)
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_range = week_start..today

    check_habit_ids   = habits.select(&:check_type?).map(&:id)
    numeric_habit_ids = habits.select(&:numeric_type?).map(&:id)

    check_counts = if check_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: check_habit_ids, record_date: week_range, completed: true)
        .group(:habit_id)
        .count
    else
      {}
    end

    numeric_sums = if numeric_habit_ids.any?
      HabitRecord
        .where(user: user, habit_id: numeric_habit_ids, record_date: week_range, deleted_at: nil)
        .group(:habit_id)
        .sum(:numeric_value)
    else
      {}
    end

    habits.each_with_object({}) do |habit, hash|
      if habit.check_type?
        target          = habit.effective_weekly_target
        completed_count = check_counts[habit.id] || 0
        rate = target.zero? ? 0 :
          ((completed_count.to_f / target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: completed_count, numeric_sum: nil,
                           effective_target: target }
      else
        numeric_sum = (numeric_sums[habit.id] || 0).to_f
        rate = habit.weekly_target.zero? ? 0 :
          ((numeric_sum / habit.weekly_target) * 100).clamp(0, 100).floor
        hash[habit.id] = { rate: rate, completed_count: nil, numeric_sum: numeric_sum,
                           effective_target: habit.weekly_target }
      end
    end
  end

  # ============================================================
  # D-8 追加: set_ai_context
  # ============================================================
  #
  # 【役割】
  #   ai_edit アクション（GET）が呼ばれたとき、
  #   session に ai_context フラグを立てる。
  #
  # 【session[:ai_context_habit_id] に habit_id を入れる理由】
  #   tasks と同様、単純な boolean フラグではなく habit_id を保存する。
  #   これにより:
  #     ① habitA の ai_edit → habitB の ai_update という不正な操作を弾ける
  #     ② 「どの習慣の編集セッションか」がサーバー側で明確になる
  #
  # 【tasks の ai_context_task_id との命名分離】
  #   habits と tasks で別々のキー名を使うことで
  #   両方の ai_edit が同時に開かれた場合でも互いに干渉しない。
  def set_ai_context
    session[:ai_context_habit_id] = @habit.id
  end

  # ============================================================
  # D-8 追加: verify_ai_context
  # ============================================================
  #
  # 【役割】
  #   ai_update アクション（PATCH）が呼ばれたとき、
  #   session の ai_context フラグを確認する。
  #
  # 【戻り値の設計（before_action 風に使うための工夫）】
  #   return if verify_ai_context という使い方をするため:
  #     - フラグなし（不正アクセス）→ true を返す → ai_update の処理が止まる
  #     - フラグあり（正常）         → false を返す → ai_update の処理が続く
  #
  # 【チェック内容】
  #   ① session[:ai_context_habit_id] が @habit.id と一致するか
  #   どちらかが満たされなければ不正アクセスとして処理を中断する。
  #
  # 【C-7（tasks#verify_ai_context）との差異】
  #   キー名が :ai_context_task_id → :ai_context_habit_id に変わるだけで
  #   ロジックは完全に同一。
  def verify_ai_context
    unless session[:ai_context_habit_id] == @habit.id
      respond_to do |format|
        format.html do
          # redirect_to は HTTP 302 を返す
          # flash[:alert] でユーザーに不正アクセスを通知する
          redirect_to habits_path,
                      alert: "この操作はAI提案モーダル経由でのみ実行できます"
        end
        format.turbo_stream do
          # Turbo Stream（fetch 経由）の場合は 403 を返す
          head :forbidden
        end
      end
      # true を返すことで return if verify_ai_context が後続処理を止める
      return true
    end

    # 正常（フラグあり・habit_id 一致）→ false を返して処理を続行する
    false
  end

  # ============================================================
  # D-8 追加: clear_ai_context
  # ============================================================
  #
  # 【役割】
  #   ai_update 保存成功後に session のフラグを削除する。
  #
  # 【なぜ必ず削除するのか】
  #   session にフラグを残すと次回も ai_update を直接叩けてしまう。
  #   1回の ai_edit → ai_update のサイクルが完了したら
  #   必ずフラグをクリアして「次回は ai_edit から入り直す」状態に戻す。
  def clear_ai_context
    session.delete(:ai_context_habit_id)
  end

  # ============================================================
  # D-8 追加: ai_update_params
  # ============================================================
  #
  # 【役割】
  #   ai_update アクション専用の Strong Parameters。
  #   通常の habit_params と異なり、以下のフィールドのみ許可する:
  #     :name           → 習慣名（変更可能）
  #     :weekly_target  → 週次目標値（変更可能）
  #
  # 【意図的に除外しているフィールドとその理由】
  #   :measurement_type → 過去データの整合性のため変更不可
  #   :unit             → measurement_type と対になるため変更不可
  #   :color            → AI 編集では外観変更は不要
  #   :icon             → 同上
  #
  # 【二重防御の考え方】
  #   ① UI（ai_edit.html.erb）で measurement_type を読み取り専用表示にする（見た目の防御）
  #   ② ai_update_params に :measurement_type を含めない（サーバー側の防御）
  #   直接 PATCH リクエストを送れば ① は無意味なため ② のサーバー側防御が必須。
  def ai_update_params
    params.require(:habit).permit(
      :name,
      :weekly_target
    )
  end
end