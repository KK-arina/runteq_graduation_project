# ============================================================
# Habit（習慣）モデル：ユーザーが継続したい行動を管理します
# ============================================================
class Habit < ApplicationRecord
  # ===================================================================
  # アソシエーション（関連付け）
  # ===================================================================
  
  # ユーザーへの所属関係を定義
  # 習慣は1つのユーザーに属する（1対多の「多」側）
  belongs_to :user

  # ===================================================================
  # バリデーション（データの妥当性チェック）
  # ===================================================================
  
  # 習慣名の必須チェックと文字数制限
  # presence: true → 空文字・nil・空白のみの文字列を許可しない
  # length: { maximum: 50 } → 50文字以内に制限（DB側の制約と一致させる）
  validates :name, presence: true, length: { maximum: 50 }
  
  # 週次目標値の必須チェックと数値範囲チェック
  # presence: true → 空・nilを許可しない
  # numericality: → 数値であることを検証
  #   only_integer: true → 整数のみ許可（小数は不可）
  #   greater_than: 0 → 0より大きい値のみ許可（1以上）
  #   less_than_or_equal_to: 7 → 7以下の値のみ許可（週7日まで）
  # チェック型の場合、週7日で何回実施するかなので1〜7の範囲
  validates :weekly_target, presence: true, numericality: {
    only_integer: true,
    greater_than: 0,
    less_than_or_equal_to: 7
  }

  # ===================================================================
  # スコープ（よく使う検索条件を名前付きで定義）
  # ===================================================================
  
  # 有効な習慣のみを取得するスコープ（論理削除されていないもの）
  # WHERE deleted_at IS NULL という条件を active という名前で定義
  # 使用例: Habit.active → 削除されていない習慣のみ取得
  # 使用例: current_user.habits.active → ログインユーザーの有効な習慣のみ
  scope :active, -> { where(deleted_at: nil) }
  
  # 削除済みの習慣のみを取得するスコープ
  # WHERE deleted_at IS NOT NULL という条件を deleted という名前で定義
  # 使用例: Habit.deleted → 論理削除された習慣のみ取得
  scope :deleted, -> { where.not(deleted_at: nil) }

  # ===================================================================
  # インスタンスメソッド（個々のHabitオブジェクトに対する操作）
  # ===================================================================
  
  # 論理削除を実行するメソッド
  # 物理削除（destroy）ではなく、deleted_atに現在時刻を設定
  # 例: habit.soft_delete → deleted_atに現在時刻が入り、論理削除される
  def soft_delete
    # touch(:deleted_at): 指定したカラムを現在時刻で更新する
    # update(deleted_at: Time.current) でも同じ動作だが、
    # touch の方が「タイムスタンプ更新」という意図が明確で推奨される
    touch(:deleted_at)
  end
  
  # 有効な習慣かどうかを判定するメソッド
  # 例: habit.active? → true（有効）または false（削除済み）
  def active?
    # deleted_at.nil? → deleted_atがnilならtrue（有効）
    deleted_at.nil?
  end
  
  # 論理削除済みかどうかを判定するメソッド
  # 例: habit.deleted? → true（削除済み）または false（有効）
  def deleted?
    # !active? → active?の結果を反転（! は「NOT」の意味）
    !active?
  end
end
