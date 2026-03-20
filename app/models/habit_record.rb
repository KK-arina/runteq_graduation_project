# ==============================================================================
# HabitRecord モデル（Issue #15 修正版）
# ==============================================================================
# 【修正内容】
#   update_completed! メソッドを追加。
#   「Controller から直接カラムを触らない」設計にすることで、
#   ビジネスロジックをモデルに集約し、責務を明確に分ける。
#
# 【設計の考え方】
#   Controller の役割: 「何をするか」の流れを制御する
#   Model の役割:      「どのように変更するか」のロジックを持つ
#
#   NG: Controller が update!(completed: true) を直接呼ぶ
#         → Controller がカラム名（completed）を知っている状態 = 密結合
#   OK: Controller が update_completed!(true) を呼ぶ
#         → Controller は「完了状態を更新する」という意図だけを伝える = 疎結合
#         → 将来カラム名が変わっても Controller を修正しなくてよい
# ==============================================================================
class HabitRecord < ApplicationRecord
  # ---------------------------------------------------------------------------
  # アソシエーション
  # ---------------------------------------------------------------------------
  belongs_to :user
  belongs_to :habit

  # ---------------------------------------------------------------------------
  # バリデーション
  # ---------------------------------------------------------------------------
  validates :record_date, presence: true

  # Rails デフォルトメッセージを使う（カスタムメッセージなし）
  # テストの期待値: errors[:record_date] に "has already been taken" が入る
  validates :record_date,
            uniqueness: {
              scope: [ :user_id, :habit_id ]
            }

  # Rails デフォルトメッセージを使う（カスタムメッセージなし）
  # テストの期待値: errors[:completed] に "is not included in the list" が入る
  validates :completed, inclusion: { in: [ true, false ] }

  # ---------------------------------------------------------------------------
  # スコープ
  # ---------------------------------------------------------------------------
  scope :for_date,           ->(date) { where(record_date: date) }
  scope :for_user,           ->(user) { where(user: user) }
  scope :completed_records,  ->       { where(completed: true) }

  # ---------------------------------------------------------------------------
  # クラスメソッド
  # ---------------------------------------------------------------------------

  # today_for_record
  # 【役割】AM 4:00 基準の「今日」の日付を返す。
  # 【Time.current について】
  #   Rails の Time.current はアプリのタイムゾーン設定を考慮する。
  #   Time.now は OS のタイムゾーンを使うためサーバー環境によって差が出る。
  #   → 常に Time.current を使うこと（Railsの規約）。
  def self.today_for_record
    now      = Time.current
    boundary = now.change(hour: 4, min: 0, sec: 0)
    now < boundary ? now.to_date - 1.day : now.to_date
  end

  # find_or_create_for
  # 【役割】
  #   指定したユーザー・習慣の「今日」のレコードを探して返す。
  #   なければ新規作成する。
  # 【なぜモデルメソッドにするか】
  #   Controller が find_or_create_by! を直接呼ぶと、
  #   「どの条件で作成するか」というロジックが Controller に漏れてしまう。
  #   モデルメソッドに集約することで、呼び出し側はシンプルになる。
  # 【! がつく理由】
  #   内部で find_or_create_by! を使っているため、バリデーション失敗時は
  #   ActiveRecord::RecordInvalid 例外を発生させる。
  def self.find_or_create_for(user, habit, date = today_for_record)
    find_or_create_by!(
      user:        user,
      habit:       habit,
      record_date: date
    )
  end

  # ---------------------------------------------------------------------------
  # インスタンスメソッド
  # ---------------------------------------------------------------------------

  # update_completed!
  # 【役割】completed（完了状態）を指定した値で更新して保存する。
  # 【なぜ toggle_completed! ではなく update_completed! にするか】
  #   toggle_completed! は「現在の値を反転させる」動作。
  #   しかしこのアプリでは、クライアント（ブラウザ）が明示的に
  #   「true にしてほしい」「false にしてほしい」という値を送ってくる。
  #   → toggle だと「送信中にダブルクリックされた場合」に意図しない値になる危険がある。
  #   → 明示的に値を指定する update_completed! の方が安全で意図が明確。
  # 【引数 value について】
  #   true または false の Boolean 値を受け取る。
  #   Controller から params を直接渡さず、変換済みの Boolean を渡す設計。
  def update_completed!(value)
    update!(completed: value)
  end

  # toggle_completed!
  # 【役割】completed を true ↔ false に反転させる。
  # 【用途】
  #   「現在の状態に関わらず切り替えたい」場合に使う。
  #   現在は update_completed! を主に使っているが、
  #   将来のユースケースのために残しておく。
  def toggle_completed!
    toggle!(:completed)
  end
end
