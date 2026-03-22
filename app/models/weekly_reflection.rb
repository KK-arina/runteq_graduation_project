# app/models/weekly_reflection.rb
#
# ファイルパス: app/models/weekly_reflection.rb
#
# ============================================================
# 【このファイルの役割】
# 週次振り返りを表すモデル。
#
# 【Issue #A-7 での変更箇所】
# before_validation コールバックを追加。
#
# 【追加した理由】
# weekly_reflections テーブルには以下の UNIQUE 制約がある:
#   - (user_id, year, week_number)  → index_weekly_reflections_on_user_year_week
#
# year と week_number が nil のまま保存されると:
#   - 複数レコードで (user_id, nil, nil) が重複して UNIQUE 制約違反になる
#   - 振り返りの重複防止が機能しない
#
# before_validation で week_start_date から year と week_number を
# 自動計算して設定することで、常に正しい値が入るようにする。
# ============================================================

class WeeklyReflection < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================
  belongs_to :user

  has_many :habit_summaries,
           class_name: "WeeklyReflectionHabitSummary",
           dependent: :destroy

  # ============================================================
  # コールバック（Issue #A-7 で追加）
  # ============================================================

  # before_validation :set_year_and_week_number
  # → バリデーション実行「前」に year と week_number を自動セットする。
  #
  # 【なぜ before_save ではなく before_validation なのか？】
  # before_save はバリデーション「後」に実行される。
  # UNIQUE制約のバリデーション（validates uniqueness）が
  # year/week_number を参照する場合、バリデーション前に値が必要なため
  # before_validation を使う。
  #
  # 【なぜ before_create ではなく before_validation なのか？】
  # before_create は新規作成時のみ実行される。
  # 更新時にも year/week_number が正しい値を保つよう
  # before_validation（作成・更新両方）を使う。
  before_validation :set_year_and_week_number

  # ============================================================
  # バリデーション
  # ============================================================
  validates :week_start_date, presence: true
  validates :week_end_date,   presence: true
  validates :reflection_comment, length: { maximum: 1000 }
  validate :week_end_date_must_be_six_days_after_start

  # ============================================================
  # スコープ
  # ============================================================
  scope :completed, -> { where.not(completed_at: nil) }
  scope :pending,   -> { where(completed_at: nil) }
  scope :recent,    -> { order(week_start_date: :desc) }
  scope :for_week,  ->(date) { where(week_start_date: date) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  def self.current_week_start_date
    (Time.current - 4.hours).beginning_of_week(:monday).to_date
  end

  def self.find_or_build_for_current_week(user)
    start_date = current_week_start_date

    user.weekly_reflections.find_or_initialize_by(
      week_start_date: start_date
    ) do |reflection|
      reflection.week_end_date = start_date + 6.days
    end
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  def completed?
    completed_at.present?
  end

  def week_label
    "#{week_start_date.strftime('%Y/%m/%d')} - #{week_end_date.strftime('%m/%d')}"
  end

  def pending?
    !completed?
  end

  def complete!
    return if completed?
    update!(completed_at: Time.current, is_locked: true)
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # set_year_and_week_number（Issue #A-7 で追加）
  # 【役割】
  # week_start_date から year と week_number を自動計算して設定する。
  #
  # 【ISO週番号とは？】
  # ISO 8601 規格で定義された週番号。
  # 月曜始まりで、年の最初の木曜日を含む週が第1週となる。
  # Rails の cweek メソッドが ISO 週番号を返す。
  # 例: Date.new(2026, 4, 20).cweek → 17
  #
  # 【なぜ week_start_date が nil のときスキップするのか？】
  # week_start_date が nil の場合、cweek を呼ぶと NoMethodError になる。
  # バリデーションで presence: true をチェックするため、
  # nil の場合はスキップして他のバリデーションに任せる。
  #
  # 【cwyear と cwday について】
  # Date#cwyear → ISO 週番号ベースの「年」を返す
  # 例: 2025-12-29 は ISO 週では 2026年第1週なので cwyear = 2026
  # year カラムには cwyear を使うことで year/week_number の組み合わせが
  # 正確に一意になる。
  def set_year_and_week_number
    # week_start_date が nil の場合はスキップする
    # （presence バリデーションが別途エラーを出す）
    return unless week_start_date.present?

    # cwyear: ISO 週番号ベースの年（12月末〜1月初の境界で正確）
    # cweek:  ISO 週番号（1〜53）
    self.year        = week_start_date.cwyear
    self.week_number = week_start_date.cweek
  end

  def week_end_date_must_be_six_days_after_start
    return unless week_start_date.present? && week_end_date.present?

    unless week_end_date == week_start_date + 6.days
      errors.add(:week_end_date, "は週の開始日から6日後でなければなりません")
    end
  end
end