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
end