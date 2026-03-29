# app/models/habit.rb
#
# ==============================================================================
# Habit（習慣）モデル（B-4: アーカイブ機能追加）
# ==============================================================================
#
# 【B-4 での変更内容】
#
#   ① scope :active を修正
#      修正前: deleted_at が nil のものだけを返していた
#      修正後: deleted_at が nil かつ archived_at も nil のものを返す
#      理由: アーカイブした習慣（archived_at が設定されている）は
#            「アクティブ一覧」に表示したくないため。
#            削除（deleted_at）と卒業（archived_at）を明確に区別する。
#
#   ② scope :archived を新規追加
#      deleted_at が nil かつ archived_at が設定されているものを返す。
#      理由: 「アーカイブ済み一覧」を取得するための専用スコープ。
#            deleted_at が nil の条件を AND にする理由は、
#            「アーカイブした後に削除した習慣」は
#            アーカイブ一覧にも表示しないようにするため。
#
#   ③ archive! メソッドを新規追加
#      archived_at に現在時刻をセットして保存する。
#      理由: コントローラーで直接 update を書くより、
#            モデルにメソッドとして持たせることで
#            「アーカイブとは何か」をモデルが責任を持って定義できる（単一責任の原則）。
#
#   ④ unarchive! メソッドを新規追加
#      archived_at を nil に戻して保存する。
#      理由: 復元（アーカイブ解除）の処理をモデルに集約するため。
#
#   ⑤ archived? メソッドを新規追加
#      archived_at が nil でないかを返すヘルパーメソッド。
#      理由: ビューやコントローラーで条件分岐するときに
#            habit.archived_at.present? と書くより
#            habit.archived? と書くほうが意図が明確になる（可読性向上）。
#
# ==============================================================================

class Habit < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================
  # belongs_to :user
  #   「この習慣はどのユーザーのものか」を示す関連。
  #   Habit テーブルの user_id カラムで User テーブルと紐付ける。
  #   belongs_to は「1対多」の「多」側に書く。

  belongs_to :user

  # has_many :habit_records, dependent: :destroy
  #   「この習慣に紐付く記録は複数ある」という関連。
  #   dependent: :destroy は「習慣を削除したとき、関連する記録も一緒に削除する」という設定。

  has_many :habit_records, dependent: :destroy

  # has_many :weekly_reflection_habit_summaries, dependent: :nullify
  #   週次振り返りのスナップショットとの関連。
  #   dependent: :nullify は「習慣を削除しても、スナップショットは削除せず
  #   habit_id を NULL にする」という設定。
  #   B-4 のタスク要件「アーカイブ済み習慣は週次振り返りスナップショットから除外しない」
  #   に対応している（アーカイブしても nullify されないため、スナップショットは保持される）。

  has_many :weekly_reflection_habit_summaries, dependent: :nullify
  has_many :habit_excluded_days, dependent: :destroy

  # ============================================================
  # Enum 定義
  # ============================================================
  # enum :measurement_type, { check_type: 0, numeric_type: 1 }
  #   習慣の記録タイプを整数で管理する。
  #   DB には 0 か 1 を保存し、Rails 上では check_type / numeric_type という
  #   名前でアクセスできる。
  #   例: habit.check_type? → true / false
  #       habit.numeric_type? → true / false

  enum :measurement_type, {
    check_type:   0,
    numeric_type: 1
  }

  # ============================================================
  # バリデーション
  # ============================================================

  validates :name, presence: true, length: { maximum: 50 }

  validates :weekly_target,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              message: "は1以上の整数を入力してください"
            }

  validates :weekly_target,
            numericality: {
              less_than_or_equal_to: 7,
              message: "は7以下で設定してください（チェック型は週7日が最大）"
            },
            if: -> { check_type? }

  validates :measurement_type, presence: true,
                                inclusion: {
                                  in: measurement_types.keys,
                                  message: "は有効な値を選択してください"
                                }

  validates :unit,
            presence: {
              message: "は数値型習慣では入力が必要です"
            },
            length: { maximum: 10 },
            if: -> { numeric_type? }

  # ============================================================
  # スコープ（B-4: active を修正、archived を新規追加）
  # ============================================================

  # scope :active（B-4 修正）
  # 【修正前】where(deleted_at: nil)
  #   → deleted_at が nil のもの = 削除されていない習慣をすべて返していた。
  #     アーカイブ済み（archived_at が設定されている）習慣も含まれてしまっていた。
  #
  # 【修正後】where(deleted_at: nil, archived_at: nil)
  #   → deleted_at が nil かつ archived_at も nil のものだけを返す。
  #   → 削除もアーカイブもされていない「アクティブな習慣」だけが対象になる。
  #
  # なぜ 2 つの条件を AND にするのか:
  #   habits テーブルには 3 つの状態がある。
  #   1. アクティブ:    deleted_at = nil AND archived_at = nil
  #   2. アーカイブ済み: deleted_at = nil AND archived_at = 設定済み
  #   3. 削除済み:      deleted_at = 設定済み（archived_at は問わない）
  #   scope :active はこの「1. アクティブ」だけを返したいため。

  scope :active,   -> { where(deleted_at: nil, archived_at: nil) }

  # scope :archived（B-4 新規追加）
  # deleted_at が nil かつ archived_at が NOT NULL のものを返す。
  #
  # where.not(archived_at: nil) とは:
  #   archived_at が NULL でないレコードを条件にする SQL の書き方。
  #   SQL では WHERE archived_at IS NOT NULL に変換される。
  #
  # なぜ deleted_at: nil の条件も加えるのか:
  #   「アーカイブした後にさらに削除した習慣」は
  #   アーカイブ一覧にも表示したくないため。
  #   deleted_at が設定されている = 削除済み なので、アーカイブ一覧から除外する。

  scope :archived, -> { where(deleted_at: nil).where.not(archived_at: nil) }

  # scope :deleted（既存）
  # deleted_at が設定されているもの = 削除済み習慣を返す。

  scope :deleted,  -> { where.not(deleted_at: nil) }

  # ============================================================
  # インスタンスメソッド（既存）
  # ============================================================

  # soft_delete
  # deleted_at に現在時刻をセットして「論理削除」する。
  # 物理削除（レコードを DB から消す）ではなく、
  # deleted_at に日時を入れることで「削除済み」として扱う。

  def soft_delete
    touch(:deleted_at)
  end

  # active?
  # deleted_at が nil かつ archived_at も nil なら true を返す。
  # B-4 修正: アーカイブ済みの習慣は active? = false とする。

  def active?
    deleted_at.nil? && archived_at.nil?
  end

  # deleted?
  # deleted_at が設定されていれば true を返す。

  def deleted?
    deleted_at.present?
  end

  # ============================================================
  # B-4 新規追加: アーカイブ関連メソッド
  # ============================================================

  # archived?
  # 【役割】
  #   この習慣がアーカイブ済みかどうかを返すヘルパーメソッド。
  #
  # 【実装方法】
  #   archived_at.present? を使う。
  #   present? は nil と空文字を false として扱う Active Support のメソッド。
  #   archived_at が nil → present? = false → archived? = false（アーカイブされていない）
  #   archived_at が日時 → present? = true  → archived? = true（アーカイブ済み）
  #
  # 【なぜメソッドにするのか】
  #   ビューやコントローラーで habit.archived_at.present? と書くより
  #   habit.archived? と書くほうが意図が明確で読みやすい（可読性向上）。
  #   また、将来的にアーカイブの判定ロジックが変わっても
  #   このメソッドだけ修正すれば済む（変更容易性）。

  def archived?
    archived_at.present?
  end

  # archive!
  # 【役割】
  #   この習慣を「卒業アーカイブ」状態にする。
  #   archived_at に現在時刻をセットして DB に保存する。
  #
  # 【! （バン）を付ける理由】
  #   Rails の慣例として、! を付けたメソッドは
  #   「失敗したときに例外（エラー）を発生させる」という意味を持つ。
  #   update! は保存に失敗すると ActiveRecord::RecordInvalid 例外を投げる。
  #   コントローラー側で rescue して適切なエラーハンドリングができる。
  #
  # 【状態ガードを入れる理由】
  #   すでにアーカイブ済みの習慣に再度 archive! を呼ぶと、
  #   archived_at が上書きされてアーカイブ日が変わってしまう。
  #   削除済みの習慣をアーカイブすると、
  #   scope :archived に含まれない状態（deleted_at が設定済み）で
  #   archived_at だけがセットされた不整合なレコードになる。
  #   これらの異常状態を早期に検知して RuntimeError で知らせることで、
  #   コントローラー側で適切にハンドリングできる。
  #
  # 【StandardError ではなく RuntimeError を使う理由】
  #   StandardError は rescue => e でキャッチできる汎用エラー。
  #   今回は「プログラムの想定外の使い方をした」ことを示すため
  #   RuntimeError（StandardError のサブクラス）を使う。
  #   これにより rescue => e でコントローラー側でまとめて捕捉できる。

  def archive!
    # 状態ガード①: すでにアーカイブ済みの場合はエラー
    # 【理由】
    #   二重アーカイブすると archived_at の日時が上書きされ、
    #   「本当にアーカイブした日」が失われてしまう。
    raise RuntimeError, "すでにアーカイブ済みです" if archived?

    # 状態ガード②: 削除済みの場合はエラー
    # 【理由】
    #   deleted_at が設定されている習慣は scope :archived の対象外
    #   （scope :archived は deleted_at: nil の条件がある）。
    #   削除済み習慣に archive! を実行しても
    #   アーカイブ一覧に表示されない不整合なレコードになる。
    raise RuntimeError, "削除済みのため操作できません" if deleted?

    update!(archived_at: Time.current)
  end

  # unarchive!
  # 【役割】
  #   アーカイブを解除してアクティブ状態に戻す（復元）。
  #   archived_at を nil にして DB に保存する。
  #
  # 【状態ガードを入れる理由】
  #   アーカイブされていない習慣に unarchive! を呼ぶのは
  #   プログラムの誤りを示す。早期にエラーを出して問題の発見を容易にする。

  def unarchive!
    # 状態ガード: アーカイブされていない習慣への unarchive! はエラー
    # 【理由】
    #   アクティブな習慣や削除済み習慣に unarchive! を呼んでも
    #   意味のある操作ではないため、明示的にエラーにする。
    raise RuntimeError, "アーカイブされていません" unless archived?

    update!(archived_at: nil)
  end

  # ============================================================
  # 既存インスタンスメソッド（変更なし）
  # ============================================================

  def excluded_day_numbers
    habit_excluded_days.pluck(:day_of_week).sort
  end

  def effective_weekly_target
    excluded_count = habit_excluded_days.size
    available_days = 7 - excluded_count
    [ weekly_target, available_days ].min
  end

  # ============================================================
  # B-3 追加: ストリーク関連メソッド（変更なし）
  # ============================================================

  def on_rest_mode?
    user.user_setting&.rest_mode_active?
  end

  def rest_mode_on_date?(date)
    return false unless allow_rest_mode

    setting = user.user_setting
    return false unless setting
    return false unless setting.rest_mode_until.present?

    setting.rest_mode_until.to_date >= date
  end

  def calculate_streak!(reference_date = HabitRecord.today_for_record)
    start_date  = reference_date - 90.days
    records_map = habit_records
                    .where(record_date: start_date..reference_date, deleted_at: nil)
                    .pluck(:record_date, :completed, :numeric_value)
                    .each_with_object({}) do |(date, completed, numeric_value), hash|
                      hash[date] = if check_type?
                                     completed
                                   else
                                     numeric_value.present? && numeric_value > 0
                                   end
                    end

    excluded_days_set = Set.new(excluded_day_numbers)

    streak = 0

    (0..90).each do |days_ago|
      date        = reference_date - days_ago
      day_of_week = date.wday

      next if excluded_days_set.include?(day_of_week)

      achieved = records_map[date]

      if achieved
        streak += 1
      else
        if rest_mode_on_date?(date)
          next
        end
        break
      end
    end

    new_longest = [ longest_streak, streak ].max

    update_columns(
      current_streak:            streak,
      longest_streak:            new_longest,
      last_streak_calculated_at: Time.current
    )

    streak
  end

  # ============================================================
  # 進捗統計メソッド（既存・変更なし）
  # ============================================================

  def weekly_progress_stats(user)
    range = current_week_range

    if check_type?
      target = effective_weekly_target
      return { rate: 0, completed_count: 0, numeric_sum: nil, effective_target: target } if target.zero?

      completed_count = habit_records
                          .where(user: user, record_date: range, completed: true)
                          .count
      rate = ((completed_count.to_f / target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: completed_count, numeric_sum: nil, effective_target: target }
    else
      return { rate: 0, completed_count: nil, numeric_sum: 0.0, effective_target: weekly_target } if weekly_target.zero?

      numeric_sum   = habit_records
                        .where(user: user, record_date: range, deleted_at: nil)
                        .sum(:numeric_value)
      numeric_sum_f = numeric_sum.to_f
      rate          = ((numeric_sum_f / weekly_target) * 100).clamp(0, 100).floor
      { rate: rate, completed_count: nil, numeric_sum: numeric_sum_f, effective_target: weekly_target }
    end
  end

  # ============================================================
  # private
  # ============================================================
  private

  def current_week_range
    today      = HabitRecord.today_for_record
    week_start = today.beginning_of_week(:monday)
    week_start..today
  end
end