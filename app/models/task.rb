# app/models/task.rb
#
# ==============================================================================
# Task（タスク）モデル（C-1: 基本CRUD実装）
# ==============================================================================
#
# 【このファイルの役割】
#   タスクの登録・管理に関するデータ構造とビジネスロジックを定義する。
#   Must/Should/Could の優先度と、todo/doing/done/archived の状態を管理する。
#
# 【テーブル構成（schema.rb より）】
#   tasks テーブルは A-1 のマイグレーションで既に作成済み。
#   主なカラム:
#     user_id        : 所有ユーザーの外部キー（必須）
#     habit_id       : 関連習慣の外部キー（任意・NULL許容）
#     title          : タスク名（必須・100文字以内）
#     priority       : 優先度（0:must / 1:should / 2:could）デフォルト 1
#     task_type      : 種別（0:通常 / 1:習慣関連 / 2:改善）デフォルト 0
#     status         : 状態（0:todo / 1:doing / 2:done / 3:archived）デフォルト 0
#     due_date       : 期限日（任意）
#     estimated_hours: 見積時間（任意・decimal）
#     scheduled_at   : 実施予定日時（任意）
#     alarm_enabled  : アラームON/OFF（デフォルト false）
#     alarm_minutes_before: 何分前に通知するか（任意）
#     completed_at   : 完了日時（任意）
#     ai_generated   : AI生成フラグ（デフォルト false）
#     deleted_at     : 論理削除日時（任意）
#
# 【enum の設計方針】
#   enum は整数値と文字列を対応させる仕組み。
#   DB には整数が保存され、アプリ内では "must" などの文字列で扱う。
#   priority のデフォルトが 1（should）なのは schema.rb で定義されている。
#
# 【scope の設計方針】
#   スコープはよく使う検索条件をメソッドとして定義したもの。
#   コントローラーで毎回 where を書く代わりに scope を使う。
# ==============================================================================

class Task < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :user
  #   tasks テーブルの user_id カラムが users テーブルの id に対応する。
  #   タスクは必ずいずれかのユーザーに属するため、null: false で必須になっている。
  belongs_to :user

  # belongs_to :habit, optional: true
  #   tasks テーブルの habit_id カラムが habits テーブルの id に対応する。
  #   optional: true を指定しないと Rails がバリデーションで
  #   "habit must exist" エラーを出す。
  #   habit_id は NULL 許容（習慣と無関係のタスクも作れる）なので optional: true が必要。
  belongs_to :habit, optional: true

  # ============================================================
  # Enum 定義
  # ============================================================

  # enum :priority（優先度）
  #   DB には整数（0/1/2）が保存される。
  #   アプリ内では "must" / "should" / "could" として扱える。
  #
  #   生成されるメソッド（Rails が自動で作ってくれる）:
  #     task.must?    → priority == 0 か判定
  #     task.should?  → priority == 1 か判定
  #     task.could?   → priority == 2 か判定
  #     task.must!    → priority を 0（must）に更新
  #     Task.must     → priority == 0 のレコードを取得するスコープ
  #
  #   なぜ 0:must / 1:should / 2:could の順にするのか:
  #     must（絶対にやる）が最も重要なので数値を小さく（0）にする。
  #     UI 上の「重要度順」と数値の大小を一致させると、
  #     ORDER BY priority ASC で重要な順に並び替えができて便利。
  enum :priority, {
    must:   0,
    should: 1,
    could:  2
  }

  # enum :task_type（タスク種別）
  #   DB には整数（0/1/2）が保存される。
  #
  #   0:normal   → 通常のタスク（ユーザーが手動で作成）
  #   1:habit    → 習慣関連タスク（habit_id と紐付く）
  #   2:improve  → 改善タスク（AI 提案から生成）
  #
  #   なぜ task_type という名前にするのか:
  #     Rails の enum は内部で "type" という名前のカラムをポリモーフィックとして
  #     特別扱いする場合がある。混乱を避けるため "task_type" という名前にしている。
  enum :task_type, {
    normal:  0,
    habit:   1,
    improve: 2
  }

  # enum :status（状態）
  #   DB には整数（0/1/2/3）が保存される。
  #
  #   0:todo     → 未着手（デフォルト）
  #   1:doing    → 進行中
  #   2:done     → 完了
  #   3:archived → アーカイブ（完了後に非表示にする）
  #
  #   なぜ archived を done と分けるのか:
  #     done にしてもタスク一覧に残ると画面が煩雑になる。
  #     archived にすることで「完了済みの履歴」として保持しつつ
  #     通常の一覧から非表示にできる。
  #     これは habits の deleted_at / archived_at の設計思想と同じ。
  enum :status, {
    todo:     0,
    doing:    1,
    done:     2,
    archived: 3
  }

  # ============================================================
  # コールバック
  # ============================================================

  # before_validation :set_default_task_type
  #   task_type が空または nil の場合に "normal" を自動設定する。
  #   フォームで種別を選ばずに送信した場合の NOT NULL 制約違反を防ぐ。
  before_validation :set_default_task_type
  
  # ============================================================
  # バリデーション
  # ============================================================

  # title の必須チェック・文字数制限
  #   タスク名は必須で、100文字以内とする。
  #   50文字に制限している習慣名（habit.name）より長くしているのは、
  #   タスクはより具体的な行動を記述するため。
  validates :title,
            presence: { message: "タスク名を入力してください" },
            length:   { maximum: 100, message: "タスク名は100文字以内で入力してください" }

  # priority の必須チェック・有効値チェック
  #   schema.rb の default: 1（should）があるので基本的に nil にはならないが、
  #   フォームから不正な値が送られた場合に備えてバリデーションを設ける。
  #
  #   inclusion: { in: priorities.keys }:
  #     enum で定義したキー（"must", "should", "could"）の配列に含まれるか確認する。
  #     priorities は Task.priorities で取得できるハッシュ。
  #     .keys で ["must", "should", "could"] の配列になる。
  validates :priority,
            presence:  true,
            inclusion: {
              in:      priorities.keys,
              message: "優先度は Must / Should / Could から選択してください"
            }

  # task_type のバリデーション
  # 【修正】presence は外したが allow_blank は付けない。
  #   空文字が来た場合は before_validation で "normal" にデフォルト設定する。
  #   DB は NOT NULL 制約があるため nil/空文字は通せない。
  validates :task_type,
            inclusion: {
              in:      task_types.keys,
              message: "が不正です"
            }

  # estimated_hours のバリデーション
  #   見積時間は任意だが、入力する場合は 0 より大きい正の数に制限する。
  #   allow_nil: true で未入力（nil）を許容する。
  #   numericality: { greater_than: 0 } で 0 以下の値を拒否する。
  validates :estimated_hours,
            numericality: {
              greater_than: 0,
              message:      "見積時間は0より大きい数値を入力してください"
            },
            allow_nil: true

  # ============================================================
  # スコープ
  # ============================================================

  # scope :active
  #   論理削除されていない（deleted_at が nil）タスクを取得する。
  #   deleted_at は「完全に削除した」タスクに日時が入る。
  #   通常の一覧表示では論理削除されたタスクは表示しない。
  #
  #   ORDER BY の設計:
  #     ① priority ASC → must(0) が先、could(2) が後の重要度順
  #     ② due_date ASC NULLS LAST → 期限が近い順、期限なしは末尾
  #     ③ created_at ASC → 作成順（最終的な並び順の安定化）
  scope :active, -> {
    where(deleted_at: nil)
      .order(Arel.sql("priority ASC, due_date ASC NULLS LAST, created_at ASC"))
  }

  # scope :not_archived
  #   アーカイブ（status=3）されていないタスクを取得する。
  #   active スコープと組み合わせて使う:
  #     current_user.tasks.active.not_archived → 通常の一覧表示
  #
  #   なぜ active に含めないのか:
  #     アーカイブ一覧（完了済みタスク履歴）を表示するときに
  #     active.archived（status=3 のみ）として使いたいから。
  #     active の中に not_archived を含めてしまうと、
  #     アーカイブ一覧が取得できなくなる。
  scope :not_archived, -> { where.not(status: Task.statuses[:archived]) }

  # scope :must / :should / :could
  #   enum が自動生成するスコープと同じだが、
  #   明示的に定義することでコードの意図が明確になる。
  #   実際には enum の自動生成スコープ（Task.must など）で十分だが、
  #   チェーンしやすいようにここで明示する。
  #
  #   使用例: current_user.tasks.active.not_archived.must
  scope :must,   -> { where(priority: priorities[:must]) }
  scope :should, -> { where(priority: priorities[:should]) }
  scope :could,  -> { where(priority: priorities[:could]) }

  # scope :today
  #   今日が期限（due_date）のタスクを取得する。
  #   ダッシュボードの「今日のタスク」セクションで使う。
  #
  #   HabitRecord.today_for_record:
  #     AM4:00 基準の「今日の日付」を返すメソッド。
  #     習慣記録と同じ基準日で「今日」を定義することで
  #     深夜のタスク管理も一貫した体験になる。
  #
  #   due_date: HabitRecord.today_for_record:
  #     due_date が今日の日付と一致するレコードのみ取得する。
  scope :today, -> { where(due_date: HabitRecord.today_for_record) }

  # scope :overdue
  #   期限が過ぎている（due_date < 今日）かつ未完了のタスクを取得する。
  #   一覧ページで期限切れの強調表示に使う。
  #
  #   where.not(status: [statuses[:done], statuses[:archived]]):
  #     完了済み・アーカイブ済みは期限切れとして扱わない。
  scope :overdue, -> {
    where(due_date: ...(HabitRecord.today_for_record))
      .where.not(status: [ statuses[:done], statuses[:archived] ])
  }

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # soft_delete
  #   論理削除（deleted_at に現在時刻を設定する）。
  #   物理削除（destroy）と異なり、データは DB に残る。
  #   削除後も「どんなタスクを作っていたか」の履歴が保持される。
  #
  #   touch(:deleted_at):
  #     deleted_at カラムに現在時刻を設定し、保存する。
  #     バリデーションをスキップする（touch は rails 内部の高速更新メソッド）。
  def soft_delete
    touch(:deleted_at)
  end

  # active?
  #   論理削除されていないか判定する。
  #   deleted_at.nil? が true → まだ削除されていない（active）。
  def active?
    deleted_at.nil?
  end

  # deleted?
  #   論理削除済みか判定する。
  def deleted?
    deleted_at.present?
  end

  # overdue?
  #   期限切れか判定する（due_date が今日より前 かつ 未完了）。
  #   ビューで期限切れを赤文字で表示するために使う。
  #
  #   due_date.present?:
  #     due_date が nil のタスクは期限なし → 期限切れにならない。
  #   due_date < HabitRecord.today_for_record:
  #     due_date が今日より前 → 期限切れ。
  #   !done? && !archived?:
  #     完了済み・アーカイブ済みは期限切れとして扱わない。
  def overdue?
    due_date.present? &&
      due_date < HabitRecord.today_for_record &&
      !done? &&
      !archived?
  end

  # due_today?
  #   今日が期限か判定する。
  #   ダッシュボードで「今日が期限」のバッジを表示するために使う。
  def due_today?
    due_date.present? && due_date == HabitRecord.today_for_record
  end

  private

  # set_default_task_type
  #   task_type が blank（nil または空文字）の場合に "normal" を設定する。
  #   blank? は nil と "" の両方を true として扱う。
  def set_default_task_type
    self.task_type = "normal" if task_type.blank?
  end
end