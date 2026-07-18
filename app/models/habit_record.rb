# app/models/habit_record.rb
#
# ==============================================================================
# HabitRecord（習慣日次記録）モデル
# ==============================================================================
#
# 【B-7 での変更内容】
#
#   ① memo バリデーションを追加
#      200文字以内。nil（未入力）は許容する。
#      allow_blank: true を使う理由:
#        メモは任意項目なので空文字や nil でも保存できるようにする。
#        presence バリデーションを付けると「メモなし」で保存できなくなる。
#
# 【以前からの設計方針（変更なし）】
#
#   ② recorded? メソッド
#      「今日の記録が存在するか（入力済みかどうか）」を返す。
#
#   ③ first_recorded_today? メソッド
#      「今日初めて記録されたか（created_at が今日か）」を返す。
#
#   ④ updated_today? メソッド
#      「今日更新されたか（updated_at が today と created_at より新しいか）」を返す。
#
# 【表示ロジックの整理】
#   habit_record が nil                  → 未記録
#   habit_record.first_recorded_today?   → 記録済み（今日初入力）
#   habit_record.updated_today?          → 更新済み（今日変更）
#   habit_record が昨日以前に作成済み    → 記録済み（昨日以前の入力が残っている）
#
# ==============================================================================

class HabitRecord < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :user
  # 【理由】
  #   habit_records テーブルには user_id カラムがあり、
  #   1つの記録は必ず1人のユーザーに属する。
  belongs_to :user

  # belongs_to :habit
  # 【理由】
  #   habit_records テーブルには habit_id カラムがあり、
  #   1つの記録は必ず1つの習慣に属する。
  belongs_to :habit

  # ============================================================
  # バリデーション
  # ============================================================

  # record_date は必須
  validates :record_date, presence: true

  # 同じユーザー・習慣・日付の組み合わせは1件のみ（重複防止）
  # DB の UNIQUE制約(user_id, habit_id, record_date) と二重防御
  validates :record_date, uniqueness: { scope: [ :user_id, :habit_id ] }

  # completed は true か false のどちらかでなければならない（nil は不可）
  validates :completed, inclusion: { in: [ true, false ] }

  # numeric_value は 0 以上の数値。nil は許容する（チェック型は nil でよい）
  validates :numeric_value,
            numericality: {
              greater_than_or_equal_to: 0,
              message: "は0以上の数値を入力してください"
            },
            allow_nil: true

  # 数値型習慣では numeric_value が必須（カスタムバリデーション）
  validate :numeric_value_required_for_numeric_type

  # ── B-7 追加: memo バリデーション ─────────────────────────────────────────
  #
  # 【allow_blank: true を使う理由】
  #   メモは任意項目なので、空文字や nil でも保存できる必要がある。
  #   allow_blank: true を付けると「空文字・nil の場合はこのバリデーションをスキップ」
  #   という意味になる。
  #   付けない場合、空文字でも「最大200文字チェック」が走り問題はないが、
  #   明示的に「任意項目」であることを示すために付けている。
  #
  # 【maximum: 200 の理由】
  #   AIのroot_cause分析に使う短いメモを想定している。
  #   長すぎるとプロンプトのトークン数が増えAIコストが上がるため200文字に制限する。
  validates :memo,
            length: { maximum: 200, message: "は200文字以内で入力してください" },
            allow_blank: true
  # ──────────────────────────────────────────────────────────────────────────

  # ============================================================
  # Issue #I-6: キャッシュの無効化（after_commit）
  # ============================================================
  #
  # 【役割】
  #   習慣の記録が保存・更新・削除されたとき、
  #   その記録を元に計算しているキャッシュを削除する。
  #   これにより ISSUE の完了条件
  #   「habit_record 保存後にダッシュボードが最新データを表示する」を満たす。
  #
  # 【❗なぜ after_save や after_commit のどちらかで after_commit なのか】
  #   after_save は「トランザクションがコミットされる前」に呼ばれる。
  #   もし後続の処理で例外が起きてロールバックされると、
  #   DBの記録は元に戻るのにキャッシュだけ消えた状態になる。
  #   （この場合は再計算されるだけなので実害は小さいが）
  #
  #   逆に深刻なのは Solid Cache 特有の事情である。
  #   config/cache.yml で database: を指定していないため、
  #   Solid Cache はアプリ本体と同じコネクション・同じトランザクションを使う。
  #   つまり after_save でキャッシュを消すと、その DELETE も
  #   同じトランザクションに入り、ロールバック時に「消したはずのキャッシュが復活」する。
  #
  #   after_commit は「COMMIT が完全に成功した後」に1回だけ呼ばれるため、
  #   ・DBに確実に保存された後にキャッシュを消せる
  #   ・キャッシュ削除がロールバックの巻き添えにならない
  #   の両方を満たす。ISSUE の指定どおり after_commit を使う。
  #
  # 【引数なしの after_commit は create / update / destroy すべてで発火する】
  #   on: :create のように限定しないことで、
  #   ・新規チェック（create）
  #   ・チェックを外す・数値を変更（update）
  #   ・記録の削除（destroy）
  #   のすべてでキャッシュが確実に消える。
  #
  # 【WeeklyReflectionCompleteService との関係（重要）】
  #   振り返り完了時の数値補正（apply_numeric_corrections!）は
  #   ApplicationRecord.with_transaction の内側で habit_record を更新する。
  #   after_commit はそのトランザクションが COMMIT された後に発火するため、
  #   「トランザクション内はDBアクセスのみ」という #A-7 の原則を守れる。
  after_commit :expire_related_caches

  # ============================================================
  # スコープ
  # ============================================================

  # for_date: 指定した日付のレコードだけを返す
  scope :for_date,          ->(date) { where(record_date: date) }

  # for_user: 指定したユーザーのレコードだけを返す
  scope :for_user,          ->(user) { where(user: user) }

  # completed_records: 完了済みのレコードだけを返す
  scope :completed_records, ->       { where(completed: true) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # today_for_record
  # 【役割】
  #   AM4:00 を「1日の境界」として扱い、現在の「日付」を返す。
  #   深夜 0:00〜3:59 の記録は「前日の記録」として扱うため、
  #   単純な Date.current や Date.today を使わずにこのメソッドを使う。
  #
  # 【仕組み】
  #   今日の AM4:00 を boundary として設定し、
  #   現在時刻がそれより前なら「前日の日付」を返す。
  #   例: 3:59 → 前日の日付 / 4:00 → 当日の日付
  def self.today_for_record
    now      = Time.current
    boundary = now.change(hour: 4, min: 0, sec: 0)
    now < boundary ? now.to_date - 1.day : now.to_date
  end

  # find_or_create_for（数値型対応版）
  # 【役割】
  #   指定した日付の記録が存在すれば取得し、なければ新規作成する。
  #   数値型習慣では新規作成時に numeric_value: 0.0 を初期値としてセット。
  #
  # 【なぜ create_with を使うのか】
  #   find_or_create_by! に直接 numeric_value: 0.0 を渡すと
  #   「検索条件」にも含まれてしまい、値が変わったときに別レコードを
  #   作成してしまう。
  #   create_with は「新規作成時だけ」適用されるため、検索条件には含まれない。
  #
  # 【引数】
  #   user  : ログインユーザー
  #   habit : 対象の習慣
  #   date  : 記録日（デフォルトは today_for_record）
  def self.find_or_create_for(user, habit, date = today_for_record)
    if habit.numeric_type?
      # 数値型: 新規作成時に numeric_value: 0.0 / completed: false を初期値にセット
      # create_with の値は「既存レコードが見つかった場合」は無視される
      create_with(numeric_value: 0.0, completed: false)
        .find_or_create_by!(user: user, habit: habit, record_date: date)
    else
      # チェック型: 従来通り（completed はデフォルト false で問題なし）
      find_or_create_by!(user: user, habit: habit, record_date: date)
    end
  end

  # ============================================================
  # インスタンスメソッド（既存）
  # ============================================================

  # update_completed!: チェック型習慣の completed 値を更新する
  def update_completed!(value)
    update!(completed: value)
  end

  # toggle_completed!: チェック型習慣の completed を反転させる
  def toggle_completed!
    toggle!(:completed)
  end

  # update_numeric_value!: 数値型習慣の numeric_value を更新する
  def update_numeric_value!(value)
    update!(numeric_value: value)
  end

  # ============================================================
  # B-3 追加: 表示状態を判定するインスタンスメソッド
  # ============================================================

  # recorded?
  # 【役割】
  #   このレコードが「記録済み（入力済み）」かどうかを返す。
  #
  # 【判定ロジック】
  #   チェック型: completed が true なら記録済みとみなす
  #   数値型:     numeric_value が存在して 0 より大きければ記録済みとみなす
  def recorded?
    if habit.check_type?
      completed
    else
      numeric_value.present? && numeric_value > 0
    end
  end

  # first_recorded_today?
  # 【役割】
  #   「今日初めて記録されたか（created_at が今日か）」を返す。
  def first_recorded_today?
    created_at.in_time_zone.to_date == HabitRecord.today_for_record
  end

  # updated_today?
  # 【役割】
  #   「今日更新されたか（updated_at が created_at より新しく、かつ今日の日付か）」を返す。
  def updated_today?
    return false if updated_at.to_i == created_at.to_i
    updated_at.in_time_zone.to_date == HabitRecord.today_for_record
  end

  # ── B-7 追加: メモ関連のインスタンスメソッド ──────────────────────────────

  # has_memo?
  # 【役割】
  #   このレコードにメモが入力されているかどうかを返す。
  #
  # 【present? を使う理由】
  #   memo が nil の場合も空文字 "" の場合も「メモなし」として扱いたい。
  #   present? は nil と "" の両方に対して false を返すため、
  #   両パターンを1行でカバーできる。
  #   !memo.blank? と同義。
  def has_memo?
    memo.present?
  end
  # ──────────────────────────────────────────────────────────────────────────

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # numeric_value_required_for_numeric_type
  # 【役割】
  #   数値型習慣では numeric_value の入力を必須にするカスタムバリデーション。
  #   habit が numeric_type? のとき numeric_value が nil ならエラーを追加する。
  def numeric_value_required_for_numeric_type
    return unless habit.present? && habit.numeric_type?
    return unless numeric_value.nil?
    errors.add(:numeric_value, "を入力してください（数値型習慣では必須です）")
  end

  # ── Issue #I-6 追加: expire_related_caches ────────────────────────────────
  #
  # 【役割】
  #   この記録の変更によって「計算し直しが必要になるキャッシュ」を削除する。
  #
  # 【なぜダッシュボードとグラフの両方を消すのか】
  #   ダッシュボード（5-1番）: 今週の習慣達成率が変わる
  #   グラフページ（19番）:    週次達成率の折れ線・当月サマリーが変わる
  #   どちらも habit_records を集計しているため、両方消さないと
  #   「ダッシュボードは更新されたのにグラフだけ古い」という
  #   ユーザーが混乱する状態になる。
  #
  #   ISSUE には「グラフは振り返り保存時に expire」としか書かれていないが、
  #   それだけだとチェックを入れた直後にグラフを開いても
  #   最大6時間は反映されないことになる。
  #   ISSUE の意図（キャッシュが正しく無効化されること）を優先し、
  #   習慣記録の保存時にもグラフのキャッシュを消す。
  #
  # 【user_id を使う理由（user を使わない）】
  #   self.user と書くと users テーブルへの SELECT が1回発生する。
  #   habit_records テーブルは user_id カラムを持っているため、
  #   user_id を直接使えば追加のDBアクセスは一切発生しない。
  #
  # 【destroy 時も user_id が読める理由】
  #   after_commit は destroy 後も呼ばれるが、
  #   そのときインスタンスはメモリ上に属性値を保持したまま（frozen）なので
  #   user_id は問題なく読み取れる。
  def expire_related_caches
    ApplicationRecord.expire_dashboard_habit_stats_cache(user_id)
    ApplicationRecord.expire_analytics_cache(user_id)
  end
  # ──────────────────────────────────────────────────────────────────────────
end