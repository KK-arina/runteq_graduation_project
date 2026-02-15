# 習慣を管理するモデル
# ユーザーの習慣（チェック型のみ、MVP範囲）を表現する
class Habit < ApplicationRecord
  # ===== アソシエーション =====
  # belongs_to: この習慣は1人のユーザーに所属する（N:1の関係）
  # user: User モデルとの関連付け
  # 必須の関連付けなので、user_id が nil の場合は保存できない
  belongs_to :user

  # ===== バリデーション =====
  # name: 習慣名のバリデーション
  # presence: true => 必須項目（空欄不可）
  # length: { maximum: 50 } => 最大50文字まで
  # エラーメッセージ例: "Name can't be blank", "Name is too long (maximum is 50 characters)"
  validates :name, presence: true, length: { maximum: 50 }

  # weekly_target: 週次目標値のバリデーション
  # presence: true => 必須項目（空欄不可）
  # numericality: 数値のバリデーション
  #   only_integer: true => 整数のみ許可（小数点不可）
  #   greater_than_or_equal_to: 1 => 1以上
  #   less_than_or_equal_to: 7 => 7以下（週7日なので上限7）
  # エラーメッセージ例: "Weekly target must be greater than or equal to 1"
  validates :weekly_target, presence: true,
                            numericality: {
                              only_integer: true,
                              greater_than_or_equal_to: 1,
                              less_than_or_equal_to: 7
                            }

  # ===== スコープ =====
  # scope: よく使う検索条件を名前付きで定義する機能
  # active: 有効な習慣のみを取得するスコープ
  # deleted_at が NULL のレコードのみを返す（論理削除されていない習慣）
  # 使用例: Habit.active => 有効な習慣のみ取得
  scope :active, -> { where(deleted_at: nil) }

  # deleted: 削除済みの習慣のみを取得するスコープ
  # deleted_at が NOT NULL のレコードのみを返す（論理削除された習慣）
  # 使用例: Habit.deleted => 削除済み習慣のみ取得
  scope :deleted, -> { where.not(deleted_at: nil) }

  # ===== インスタンスメソッド =====
  # 論理削除を実行するメソッド
  # deleted_at カラムに現在時刻を設定することで「削除済み」とマークする
  # 物理削除（destroy）ではなく論理削除を使う理由:
  #   - 過去の振り返りデータとの整合性を保つため
  #   - weekly_reflection_habit_summaries でスナップショットとして参照されるため
  def soft_delete
    # touch: 指定したカラムに現在時刻を設定するメソッド
    # touch(:deleted_at) => deleted_at = Time.current
    # updated_at も自動的に更新される
    touch(:deleted_at)
  end

  # 有効な習慣かどうかを判定するメソッド
  # 戻り値: deleted_at が nil なら true、それ以外は false
  # 使用例: habit.active? => true（有効） / false（削除済み）
  def active?
    deleted_at.nil?
  end

  # 削除済みかどうかを判定するメソッド
  # 戻り値: active? の逆（削除済みなら true、有効なら false）
  # 使用例: habit.deleted? => true（削除済み） / false（有効）
  def deleted?
    !active?
  end
end
