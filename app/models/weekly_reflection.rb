# ファイルパス: app/models/weekly_reflection.rb
#
# 【このファイルの役割】
# 週次振り返りを表すモデル。
# Issue #25では「振り返り完了」を明示的に行う complete! メソッドを追加する。
# completed_at カラムに現在時刻を保存することで「完了済み」と判断できるようにする。

class WeeklyReflection < ApplicationRecord
  # ============================================================
  # アソシエーション（関連付け）
  # ============================================================

  # belongs_to :user
  #   → WeeklyReflection は必ず1人の User に属する（外部キー: user_id）
  belongs_to :user

  # has_many :habit_summaries
  #   → 1つの振り返りに複数の習慣スナップショットが紐づく
  # dependent: :destroy
  #   → 振り返りを削除したとき、紐づくスナップショットも一緒に削除する
  has_many :habit_summaries,
           class_name: "WeeklyReflectionHabitSummary",
           dependent: :destroy

  # ============================================================
  # バリデーション（入力値の検証）
  # ============================================================

  # presence: true
  #   → nil や空文字は許可しない（必須項目）
  validates :week_start_date, presence: true
  validates :week_end_date,   presence: true

  # length: { maximum: 1000 }
  #   → 振り返りコメントは1000文字まで
  validates :reflection_comment, length: { maximum: 1000 }

  # カスタムバリデーション: week_end_date は week_start_date + 6日 でなければならない
  validate :week_end_date_must_be_six_days_after_start

  # ============================================================
  # スコープ（よく使うクエリをメソッドとして定義）
  # ============================================================

  # completed
  #   → completed_at が NULL でないレコード（振り返り完了済み）
  #   使用例: current_user.weekly_reflections.completed
  scope :completed, -> { where.not(completed_at: nil) }

  # pending
  #   → completed_at が NULL のレコード（振り返り未完了）
  scope :pending, -> { where(completed_at: nil) }

  # recent
  #   → week_start_date の新しい順に並べる
  scope :recent, -> { order(week_start_date: :desc) }

  # for_week(date)
  #   → 指定した日付が属する週の振り返りを取得する
  scope :for_week, ->(date) { where(week_start_date: date) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # current_week_start_date
  #   → AM4:00基準で「今週の月曜日」を返すクラスメソッド
  #
  #   【AM4:00基準とは？】
  #   深夜4時より前（例: 月曜AM3:59）は、まだ「前週の日曜」として扱う。
  #   深夜4時以降（例: 月曜AM4:01）になって初めて「今週の月曜」として扱う。
  #
  #   【計算方法】
  #   1. Time.current から4時間引いて「実質的な現在時刻」を得る
  #   2. beginning_of_week(:monday) で月曜日の始まりを得る
  #   3. to_date で Date 型に変換する
  def self.current_week_start_date
    # Time.current - 4.hours
    #   → Rails の Time.current は常にタイムゾーン対応の現在時刻を返す
    #   → 4時間引くことで AM4:00 を「1日の始まり」として扱える
    (Time.current - 4.hours).beginning_of_week(:monday).to_date
  end

  # find_or_build_for_current_week(user)
  #   → 今週の振り返りが存在すれば取得、なければ新しいインスタンスを作る
  #
  #   【なぜ find_or_build を使うのか？】
  #   コントローラーで「今週の振り返りを取得 or 新規作成」という処理を
  #   1行で書けるため、コントローラーが肥大化しない。
  #
  #   【build と create の違い】
  #   build  → DBに保存しない（メモリ上のオブジェクトを作るだけ）
  #   create → DBに保存する
  #   ここでは「フォームに渡して表示するだけ」なので build を使う。
  def self.find_or_build_for_current_week(user)
    start_date = current_week_start_date

    # find_or_initialize_by
    #   → 条件に合うレコードが存在すればそれを返し、
    #     存在しなければ新しいインスタンスを作って返す（DBには保存しない）
    user.weekly_reflections.find_or_initialize_by(
      week_start_date: start_date
    ) do |reflection|
      # ブロックは「新規作成時のみ」実行される
      # week_end_date を week_start_date + 6日 に自動設定する
      reflection.week_end_date = start_date + 6.days
    end
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # completed?
  #   → 振り返りが完了済みかどうかを返す
  #   completed_at が nil でなければ完了済みと判断する
  #
  #   【使用例】
  #   reflection.completed? #=> true or false
  def completed?
    # present? は nil でも空文字でもなければ true を返す
    completed_at.present?
  end

  # week_label
  #   → 振り返り対象週を「YYYY/MM/DD - MM/DD」形式の文字列で返す
  #   → new.html.erb の「対象期間:」表示で使用する
  def week_label
    "#{week_start_date.strftime('%Y/%m/%d')} - #{week_end_date.strftime('%m/%d')}"
  end

  # pending?
  #   → 振り返りが未完了かどうかを返す（completed? の逆）
  #
  #   【なぜ pending? が必要なのか？】
  #   application_controller.rb の locked? メソッドが
  #   last_week_reflection.pending? を呼び出している。
  #   pending? がないと NoMethodError が発生するため、ここで定義する。
  #
  #   【completed? との使い分け】
  #   completed? → 「完了した？」という確認に使う（ポジティブな確認）
  #   pending?   → 「まだ終わっていない？」という確認に使う（ロック判定など）
  #   どちらも同じ情報を表すが、読む文脈に合わせて使い分けると英語として自然になる。
  #
  #   例: "振り返りはまだ終わっていないか？" → reflection.pending?
  #       "振り返りは完了済みか？"           → reflection.completed?
  def pending?
    !completed?
  end

  # complete!
  #   → 振り返りを「完了状態」にするメソッド（Issue #25 で追加）
  #
  #   【完了の記録方法】
  #   - completed_at: 「いつ完了したか」という時刻の記録
  #     → pending? / completed? の判定に使用
  #     → application_controller の locked? がこれを参照する
  #   - is_locked: true にも同時に設定する
  #     → new / create アクションの「既に完了済みか」チェックに使用
  #     → index の .completed スコープが is_locked: true を参照している
  #
  #   【なぜ両方を更新するのか】
  #   既存コードの is_locked カラムと新しい completed_at カラムを
  #   両方一致させておくことで、どちらの方式でも正しく動作する。
  #   将来 is_locked カラムを廃止する際は complete! のみ修正すればよい。
  def complete!
    return if completed?

    update!(completed_at: Time.current, is_locked: true)
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # week_end_date_must_be_six_days_after_start
  #   → week_end_date が week_start_date + 6日 になっているか検証する
  #
  #   【なぜ 6日後なのか？】
  #   月曜始まりで日曜終わりの1週間 = 7日間
  #   month_start + 0日（月曜）〜 + 6日（日曜）= 7日間
  def week_end_date_must_be_six_days_after_start
    # week_start_date が存在しない場合は他のバリデーションに任せる
    return unless week_start_date.present? && week_end_date.present?

    unless week_end_date == week_start_date + 6.days
      # errors.add でバリデーションエラーを追加する
      # :week_end_date → エラーが起きたカラム名
      # "は週の開始日から6日後でなければなりません" → エラーメッセージ
      errors.add(:week_end_date, "は週の開始日から6日後でなければなりません")
    end
  end
end
