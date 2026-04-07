# app/models/task.rb
#
# ==============================================================================
# Task（タスク）モデル（C-2: 完了チェック・ステータス管理を追加）
# ==============================================================================
#
# 【C-2 での変更点】
#   インスタンスメソッドに以下を追加:
#     toggle_complete! → 完了↔未完了を切り替える（completed_at も同時更新）
#     archive!         → status を archived に変更する
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

  validates :title,
            presence: { message: "タスク名を入力してください" },
            length:   { maximum: 100, message: "タスク名は100文字以内で入力してください" }

  validates :priority,
            presence:  true,
            inclusion: {
              in:      priorities.keys,
              message: "優先度は Must / Should / Could から選択してください"
            }

  validates :task_type,
            inclusion: {
              in:      task_types.keys,
              message: "が不正です"
            }

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
  scope :active, -> {
    where(deleted_at: nil)
      .order(Arel.sql("priority ASC, due_date ASC NULLS LAST, created_at ASC"))
  }

  # scope :not_archived
  #   アーカイブ（status=3）されていないタスクを取得する。
  scope :not_archived, -> { where.not(status: Task.statuses[:archived]) }

  # scope :must / :should / :could
  scope :must,   -> { where(priority: priorities[:must]) }
  scope :should, -> { where(priority: priorities[:should]) }
  scope :could,  -> { where(priority: priorities[:could]) }

  # scope :today
  #   今日が期限（due_date）のタスクを取得する。
  scope :today, -> { where(due_date: HabitRecord.today_for_record) }

  # scope :overdue
  #   期限が過ぎている（due_date < 今日）かつ未完了のタスクを取得する。
  scope :overdue, -> {
    where(due_date: ...(HabitRecord.today_for_record))
      .where.not(status: [ statuses[:done], statuses[:archived] ])
  }

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # soft_delete
  #   論理削除（deleted_at に現在時刻を設定する）。
  def soft_delete
    touch(:deleted_at)
  end

  # active?
  #   論理削除されていないか判定する。
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
  def overdue?
    due_date.present? &&
      due_date < HabitRecord.today_for_record &&
      !done? &&
      !archived?
  end

  # due_today?
  #   今日が期限か判定する。
  def due_today?
    due_date.present? && due_date == HabitRecord.today_for_record
  end

  # ----------------------------------------------------------
  # C-2 追加: toggle_complete!
  # ----------------------------------------------------------
  # 完了↔未完了を切り替えるメソッド。
  #
  # 【なぜモデルにロジックを書くのか】
  #   コントローラーに書くと「どんな操作をしているか」がわかりにくくなる。
  #   モデルにメソッドとして定義することで、
  #   「タスクの完了切り替え」という意図が明確になり、
  #   テストも書きやすくなる（Fat Controller を避ける設計原則）。
  #
  # 【動作の流れ】
  #   現在の status が done → todo に戻す（completed_at も nil に）
  #   現在の status が todo / doing → done にする（completed_at に現在時刻を設定）
  #
  # 【update! を使う理由】
  #   update! はバリデーションを通過した場合のみ保存する。
  #   保存失敗時は ActiveRecord::RecordInvalid 例外を発生させるため、
  #   コントローラー側で rescue して適切なエラー処理ができる。
  #   （save は失敗時に false を返すだけで例外を投げない）
  #
  # 【archived? のガード】
  #   アーカイブ済みのタスクはチェックボックスで操作しない設計にする。
  #   誤ってアーカイブ済みが toggle されるのを防ぐ。
  def toggle_complete!
    # アーカイブ済みは操作しない
    return if archived?

    if done?
      # 完了済み → 未完了（todo）に戻す
      # completed_at も nil にリセットする
      update!(status: :todo, completed_at: nil)
    else
      # 未完了（todo / doing）→ 完了（done）にする
      # completed_at に現在時刻を設定する
      # Time.current: Rails のタイムゾーン設定（config.time_zone）を考慮した現在時刻
      #   Time.now だとサーバーのローカル時刻になるため、
      #   必ず Time.current を使うこと（JST が正しく記録される）
      update!(status: :done, completed_at: Time.current)
    end
  end

  # ============================================================
  # C-2 修正: archive!
  # ============================================================
  # 【修正内容】
  #   done? のガードを追加する。
  #   done 以外のタスク（todo / doing / archived）は archive! できない。
  #
  # 【なぜ done? ガードが必要か】
  #   UI 側では「アーカイブ」ボタンを done タスクにのみ表示しているが、
  #   直接 PATCH リクエストを送れば todo タスクをアーカイブできてしまう。
  #   サーバー側でもガードすることで「done のみアーカイブ可能」を保証する。
  def archive!
    return if archived?   # 二重アーカイブ防止
    return unless done?   # done 以外は操作しない（C-2 修正追加）

    update!(status: :archived)
  end

  private

  # set_default_task_type
  #   task_type が blank（nil または空文字）の場合に "normal" を設定する。
  def set_default_task_type
    self.task_type = "normal" if task_type.blank?
  end
end