# app/services/habit_record_save_service.rb
#
# ==============================================================================
# HabitRecordSaveService（B-7 最終修正版）
# ==============================================================================
#
# 【修正内容】
#
#   ① 「部分更新」設計に変更（最重要修正）
#
#      【修正前の問題】
#        initialize の引数のデフォルトを nil にしていた。
#        memo: nil を受け取ると「メモを nil で上書きする」という操作と
#        「memo を送らなかった（更新不要）」の区別ができなかった。
#
#        例: チェックボックスを操作したとき
#          JS が completed だけ送り、memo を送らない場合
#          → memo: nil として扱われ、既存のメモが消えてしまう
#
#      【修正後の設計】
#        引数のデフォルト値に :not_provided というシンボルを使う。
#        Ruby のシンボルは「ユニークなオブジェクト」なので
#        「送られなかった」という状態を nil と区別して表現できる。
#
#        :not_provided が渡されたとき  → update_params に含めない（更新しない）
#        nil / "" が渡されたとき       → update_params に含める（nil/空で上書き）
#        "文字列" が渡されたとき       → update_params に含める（文字列で上書き）
#
#   ② update_params ハッシュで更新対象を動的に構築
#      「送られてきた項目だけ」を update! に渡す。
#      送られなかった項目はハッシュに含まれないため、DBが変更されない。
#
# ==============================================================================

class HabitRecordSaveService
  # ── NOT_PROVIDED センチネル値の定義 ─────────────────────────────────────────
  #
  # 【なぜ :not_provided シンボルを使うのか】
  #   nil は「値がない」という意味だが、
  #   引数として nil を渡した場合も「デフォルト値の nil」と区別できない。
  #
  #   例えば memo: nil を受け取った場合、
  #   「メモを空にする操作」なのか「memoパラメータ自体が送られなかった」のか
  #   判断できない。
  #
  #   そこで :not_provided という専用のシンボルをデフォルト値にする。
  #   シンボルは Ruby のオブジェクトなので nil とは別物として扱える。
  #   「引数が渡されなかった」という状態を明示的に表現できる。
  #
  NOT_PROVIDED = :not_provided
  # ──────────────────────────────────────────────────────────────────────────

  # initialize
  # 【引数】
  #   user:          ログインユーザー
  #   habit:         対象の習慣
  #   completed:     Boolean / NOT_PROVIDED（渡されなければ更新しない）
  #   numeric_value: Float / nil / NOT_PROVIDED（渡されなければ更新しない）
  #   memo:          String / nil / NOT_PROVIDED（渡されなければ更新しない）
  #
  # 【デフォルト値を NOT_PROVIDED にする理由】
  #   チェック操作時は completed だけ送る。
  #   数値操作時は numeric_value だけ送る。
  #   メモ操作時は memo だけ送る。
  #   それぞれ「送らなかった項目は更新しない」という動作を実現するため、
  #   「送られなかった」= NOT_PROVIDED として区別する。
  def initialize(user:, habit:, completed: NOT_PROVIDED, numeric_value: NOT_PROVIDED, memo: NOT_PROVIDED)
    @user          = user
    @habit         = habit
    @completed     = completed
    @numeric_value = numeric_value
    @memo          = memo
  end

  # call
  # 【戻り値】
  #   成功: { success: true,  habit_record: HabitRecord, errors: [] }
  #   失敗: { success: false, habit_record: nil,         errors: [エラー文字列] }
  def call
    habit_record = nil

    ApplicationRecord.with_transaction do
      habit_record = HabitRecord.find_or_create_for(@user, @habit)

      # ── 部分更新パラメータの構築 ───────────────────────────────────────────
      #
      # update_params に「更新する項目だけ」を詰める。
      # NOT_PROVIDED が渡された項目はハッシュに含めないことで
      # その項目は DB で変更されない。
      #
      # 例:
      #   completed: true が渡された場合  → { completed: true }
      #   completed が NOT_PROVIDED の場合 → {} （completedはDBを変更しない）
      update_params = {}

      # ── completed の処理 ──────────────────────────────────────────────────
      #
      # 【チェック型の場合のみ completed を更新する理由】
      #   数値型習慣では completed はサービス内で自動計算する。
      #   フロントから completed を明示的に受け取るのはチェック型のみ。
      #   数値型のとき completed: NOT_PROVIDED が渡るため、このブロックに入らない。
      unless @completed == NOT_PROVIDED
        update_params[:completed] = @completed
      end

      # ── numeric_value と completed（数値型の自動計算）の処理 ───────────────
      #
      # 数値型の場合: numeric_value が送られてきたときだけ処理する
      # NOT_PROVIDED のままなら numeric_value は変更しない
      unless @numeric_value == NOT_PROVIDED
        value = @numeric_value.nil? ? nil : @numeric_value.to_f
        update_params[:numeric_value] = value

        # 数値型では completed を numeric_value から自動計算する
        # nil → false / 0 → false / 0より大きい → true
        update_params[:completed] = value.nil? ? false : value > 0
      end

      # ── memo の処理 ────────────────────────────────────────────────────────
      #
      # memo が NOT_PROVIDED の場合はハッシュに含めない（メモを変更しない）
      # nil / "" が渡された場合は presence で nil に変換してハッシュに含める
      # 文字列が渡された場合はその値をハッシュに含める
      unless @memo == NOT_PROVIDED
        update_params[:memo] = @memo.presence
      end
      # ────────────────────────────────────────────────────────────────────────

      # update_params が空の場合は更新しない
      # （チェック型の新規作成直後など、何も送らないケースへの安全策）
      habit_record.update!(update_params) unless update_params.empty?
    end

    # ── 記録保存後にストリークを即時再計算する（#I-3）────────────────────────
    #
    # 【なぜここで再計算するのか】
    #   current_streak / longest_streak は本来 StreakCalculationJob（日次 cron）
    #   が更新する。しかし Render の無料 Web サービスは15分アクセスが無いと
    #   停止するため、深夜の cron が発火せず、記録してもストリークが更新されない
    #   ことがある。そこでアプリ内の定期処理に依存せず、記録の保存が成功した直後に
    #   その習慣のストリークを再計算して即時反映する。
    #   （日次の StreakCalculationJob は整合性のためのバックアップとして残すが、
    #    無料枠では発火が保証されない点に注意。「記録しなかった日のストリーク
    #    切れ」など、保存が発生しないケースはこの保存時再計算では補えない。）
    #
    # 【なぜトランザクションの外で呼ぶのか】
    #   HabitRecord の保存を先に確定させ、DB 変更がコミットされた後で計算する。
    #   ストリーク計算が失敗しても、保存済みの記録まで失敗扱いにしないため。
    #   （calculate_streak! は update_columns で書き込み、コールバックを発火しない）
    #
    # 【例外の握り方】
    #   rescue StandardError とし、通常のアプリ例外のみ捕捉する（Exception 系は
    #   捕まえない）。ストリーク計算の失敗で記録保存まで失敗させないが、原因調査の
    #   ためログとバックトレース先頭を必ず残す。
    begin
      @habit.calculate_streak!
    rescue StandardError => e
      Rails.logger.error "[HabitRecordSaveService] ストリーク再計算に失敗しました: habit_id=#{@habit.id}, error=#{e.class}: #{e.message}"
      Rails.logger.error e.backtrace&.first(5)&.join("\n")
    end

    { success: true, habit_record: habit_record, errors: [] }

  rescue ActiveRecord::RecordInvalid => e
    errors = e.record&.errors&.full_messages || [ e.message ]
    { success: false, habit_record: nil, errors: errors }

  rescue ActiveRecord::RecordNotFound
    { success: false, habit_record: nil, errors: [ "習慣が見つかりませんでした" ] }

  rescue StandardError => e
    Rails.logger.error "HabitRecordSaveService error: #{e.message}"
    Rails.logger.error e.backtrace&.first(5)&.join("\n")
    { success: false, habit_record: nil, errors: [ "保存中にエラーが発生しました" ] }
  end
end