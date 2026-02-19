# app/models/habit.rb
#
# 【このファイルの役割】
# Habit（習慣）モデル。
# ユーザーが登録した習慣データを管理し、週次の進捗率計算ロジックもここに集約する。
# 「モデルに責務を集約する」設計方針（Fat Model）に従い、
# コントローラーやビューから計算ロジックを切り離す。

class Habit < ApplicationRecord
  # ============================================================
  # アソシエーション（他のモデルとの関連付け）
  # ============================================================

  # 【belongs_to :user】
  # 「この習慣はどのユーザーのものか」を定義する。
  # habits テーブルの user_id カラムで users テーブルと紐付ける。
  belongs_to :user

  # 【has_many :habit_records】
  # 「この習慣には複数の日次記録がある」を定義する。
  # dependent: :destroy は「習慣を削除したとき、紐づく記録も一緒に削除する」設定。
  # ただし今回は論理削除なので、物理削除されるケースは限定的。
  has_many :habit_records, dependent: :destroy

  # ============================================================
  # バリデーション（入力値の検証ルール）
  # ============================================================

  # 【presence: true】  → 空欄（nil / 空文字）を禁止する
  # 【length: { maximum: 50 }】 → 50文字を超えるとエラーにする
  validates :name, presence: true, length: { maximum: 50 }

  # 【presence: true】       → 入力必須
  # 【numericality: { ... }】 → 数値バリデーション
  #   only_integer: true        → 整数のみ許可（1.5 などは不可）
  #   greater_than_or_equal_to: 1 → 1以上
  #   less_than_or_equal_to: 7    → 7以下（週7日が最大）
  validates :weekly_target,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1,
              less_than_or_equal_to: 7
            }

  # ============================================================
  # スコープ（よく使う検索条件をメソッドのように呼び出せる定義）
  # ============================================================

  # 【scope :active】
  # 論理削除されていない（deleted_at が nil = NULL）習慣だけを返す。
  # 例: current_user.habits.active → 有効な習慣一覧
  scope :active, -> { where(deleted_at: nil) }

  # 【scope :deleted】
  # 論理削除済み（deleted_at に日時が入っている）習慣だけを返す。
  scope :deleted, -> { where.not(deleted_at: nil) }

  # ============================================================
  # インスタンスメソッド（個々の習慣オブジェクトに対して呼べるメソッド）
  # ============================================================

  # 【soft_delete】
  # 習慣を「論理削除」するメソッド。
  # 物理削除（destroy）ではなく deleted_at カラムに現在時刻を記録するだけ。
  # こうすることで、過去の振り返りデータとの整合性が保たれる。
  # touch(:deleted_at) は「deleted_at = Time.current を保存する」Rails組み込みメソッド。
  def soft_delete
    touch(:deleted_at)
  end

  # 【active?】
  # この習慣が有効（削除されていない）かどうかを真偽値で返す。
  # deleted_at が nil = 削除されていない = true
  def active?
    deleted_at.nil?
  end

  # 【deleted?】
  # この習慣が論理削除済みかどうかを真偽値で返す。
  # active? の逆。
  def deleted?
    !active?
  end

  # ============================================================
  # 進捗統計メソッド（Issue #16 で追加）
  # ============================================================

  # 【weekly_progress_stats】
  # 「今週の進捗率（%）」と「今週の完了日数」を同時に返すメソッド。
  #
  # ■ なぜ「rate（%）」と「completed_count（日数）」を一緒に返すのか？
  #   ビューで「50%」という数値と「3 / 7 日達成」という文字を
  #   両方表示したいため。
  #   もし別々のメソッドにすると、DBへの問い合わせが2回になってしまう。
  #   まとめて1回のDBアクセスで両方取得することで効率化している。
  #
  # 計算式: 今週の完了日数 ÷ weekly_target × 100
  #
  # 例: weekly_target = 7, 完了 = 3日 → (3 / 7.0 * 100).floor = 42
  #
  # 引数:
  #   user - 計算対象のユーザー（他ユーザーの記録を混入させないため）
  #
  # 戻り値: Hash
  #   {
  #     rate:            Integer (0〜100) ← 進捗率（%）
  #     completed_count: Integer          ← 今週の完了日数
  #   }
  def weekly_progress_stats(user)
    # 今週の月曜日〜今日（AM4:00基準）の日付範囲を計算する
    range = current_week_range

    # 今週の完了済み記録を1回のSQLで数える
    # .count は SQLの COUNT(*) を発行するため、データを全件取得するより高速
    completed_count = habit_records
                        .where(user: user)         # このユーザーの記録だけ
                        .where(record_date: range) # 今週の範囲内
                        .where(completed: true)    # 完了済み（チェックが入っている）
                        .count                     # 件数をSQLで数える

    # 【ゼロ除算ガード】
    # weekly_target は必ず1以上なのでゼロになるはずがないが、
    # 万が一の場合に備えた安全策（ガード節）。
    # 0で割ると ZeroDivisionError が発生するため、先に弾いておく。
    if weekly_target.zero?
      return { rate: 0, completed_count: completed_count }
    end

    # 【進捗率の計算】
    # .to_f → 整数同士の割り算は小数が出ないため（例: 3/7 = 0）、
    #         浮動小数点数（小数）に変換してから割り算する（3/7.0 = 0.428...）
    # .clamp(0, 100) → 結果を必ず 0〜100 の範囲に収める（目標超過時の安全装置）
    # .floor → 小数点以下を切り捨てて整数にする（例: 42.8 → 42）
    rate = ((completed_count.to_f / weekly_target) * 100)
             .clamp(0, 100)
             .floor

    # 進捗率と完了日数を一緒に返す（Rubyのハッシュ形式）
    {
      rate: rate,
      completed_count: completed_count
    }
  end

  # ============================================================
  # private（外部から直接呼び出されるべきでないメソッド）
  # ============================================================
  private

  # 【current_week_range】
  # AM4:00基準で「今週の月曜日〜今日」の Date の Range を返す。
  #
  # ■ AM4:00 基準とは？
  #   深夜（例: 0:00〜3:59）に作業した場合、それは「前日の記録」として扱う設計。
  #   HabitRecord.today_for_record と同じロジックを使う。
  #
  # ■ beginning_of_week とは？
  #   Rails の Date / ActiveSupport に組み込まれたメソッド。
  #   デフォルトは月曜日始まり（:monday）。
  #   例: Date.new(2026, 2, 19).beginning_of_week → 2026-02-16（月曜日）
  #
  # 戻り値: Range<Date>  例: 2026-02-16..2026-02-19
  def current_week_range
    # AM4:00 基準で「今日」を取得する
    # HabitRecord.today_for_record はモデルに定義済みのクラスメソッド
    today = HabitRecord.today_for_record

    # 今週の月曜日を取得する
    week_start = today.beginning_of_week(:monday)

    # 月曜日〜今日の Date の Range を返す
    week_start..today
  end
end