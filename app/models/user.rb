# ファイルパス: app/models/user.rb
#
# 【このファイルの役割】
# ユーザーを表すモデル。
# Issue #24 で追加した locked? メソッドを、
# Issue #25 では「前週の振り返りが完了済みかどうか」を正確に判断できるよう整理する。
#
# 【locked? メソッドのロジック変更点】
# Issue #24 では locked? が「前週の振り返りレコードが存在しない or completed_at が nil」
# という条件でロックをかけていた。
# Issue #25 では complete! メソッドが completed_at を更新するため、
# locked? の条件はそのまま正しく動作する（変更不要）。
# ただし、コメントを充実させてロジックを明確にする。

class User < ApplicationRecord
  # ============================================================
  # 認証関連
  # ============================================================

  # has_secure_password
  #   → BCryptを使ってパスワードをハッシュ化して保存する
  #   → authenticate メソッドが自動で追加される
  #   → Gemfile に 'bcrypt' が必要
  has_secure_password

  # ============================================================
  # アソシエーション（関連付け）
  # ============================================================

  # has_many :habits
  #   → 1人のユーザーが複数の習慣を持てる
  # dependent: :destroy
  #   → ユーザーを削除したとき、その習慣もすべて削除する
  has_many :habits, dependent: :destroy

  # has_many :habit_records
  #   → 1人のユーザーが複数の習慣記録を持てる
  has_many :habit_records, dependent: :destroy

  # has_many :weekly_reflections
  #   → 1人のユーザーが複数の週次振り返りを持てる
  has_many :weekly_reflections, dependent: :destroy

  # ============================================================
  # バリデーション
  # ============================================================

  validates :name,  presence: true, length: { maximum: 50 }
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # ============================================================
  # コールバック（保存の前後に自動実行される処理）
  # ============================================================

  # before_save :downcase_email
  #   → DBに保存する直前に downcase_email メソッドを実行する
  #
  #   【なぜ小文字化が必要なのか？】
  #   DBのUNIQUE制約は大文字小文字を区別する（例: PostgreSQL の場合）。
  #   "Test@Example.com" と "test@example.com" は別々のメールアドレスとして扱われ、
  #   同じユーザーが大文字・小文字を変えて2つのアカウントを作れてしまう。
  #
  #   保存前に必ず小文字化することで、
  #   「同じメールアドレスは1アカウントのみ」という制約を確実に守れる。
  #
  #   【before_save と before_create の違い】
  #   before_create → 新規作成時のみ実行（update では実行されない）
  #   before_save   → 作成・更新どちらでも実行される
  #   メールアドレスは「更新」されることもあるので before_save を使う。
  before_save :downcase_email

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # locked?
  #   → PDCA強制ロックがかかっているかどうかを返す
  #
  #   【ロックの条件（両方を満たした場合にロック）】
  #   1. 現在が月曜日の AM4:00 以降である
  #   2. 前週の振り返りが未完了（completed_at が nil）または存在しない
  #
  #   【なぜ AM4:00 基準なのか？】
  #   深夜0時〜AM4:00 は「前の日の続き」として扱う。
  #   例えば日曜の深夜3時はまだ「土曜の夜」扱いにする。
  #
  #   【Issue #25 との関係】
  #   complete! メソッドで completed_at に時刻が入ると、
  #   locked? の条件2が false になり、ロックが解除される。
  #   つまり locked? 自体のロジックは変更不要。
  def locked?
    # Step 1: 現在が「月曜日のAM4:00以降」かどうかを確認する
    #
    # Time.current - 4.hours
    #   → 4時間前の時刻を計算することで AM4:00 を「1日の始まり」として扱う
    # .monday?
    #   → 月曜日なら true を返す（ActiveSupport::TimeWithZone のメソッド）
    # adjusted_time.monday? によって
    # 「月曜4:00〜火曜3:59」の間だけロック判定が行われる
    adjusted_time = Time.current - 4.hours
    return false unless adjusted_time.monday?

    # Step 2: 前週の振り返りが完了済みかどうかを確認する
    #
    # 前週の開始日 = 今週の開始日 - 7日
    # 今週の開始日は WeeklyReflection.current_week_start_date を使う
    last_week_start = WeeklyReflection.current_week_start_date - 7.days

    # weekly_reflections.for_week(last_week_start).completed.exists?
    #   → 前週の振り返りが「完了済み」で存在するか確認する
    #   → exists? はレコードが1件でもあれば true を返す（高速）
    last_week_completed = weekly_reflections
                            .for_week(last_week_start)
                            .completed
                            .exists?

    # 前週の振り返りが完了していなければ locked = true
    # 完了していれば locked = false（ロック解除）
    !last_week_completed
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # downcase_email
  #   → メールアドレスを小文字に変換する（before_save コールバックから呼ばれる）
  #
  #   【self.email = email.downcase の意味】
  #   self.email = ... → このユーザーオブジェクトの email カラムに代入する
  #   email.downcase   → 現在の email 文字列を全部小文字にした文字列を返す
  #   例: "Test@Example.COM".downcase → "test@example.com"
  #
  #   【なぜ self. が必要なのか？】
  #   Rubyのメソッド内では「email = ...」と書くと
  #   インスタンス変数ではなくローカル変数への代入になってしまう。
  #   「このオブジェクトの email を更新する」という意味を明示するために
  #   self.email = と書く必要がある。
  def downcase_email
    self.email = email.to_s.downcase
  end
end
