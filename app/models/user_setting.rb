# app/models/user_setting.rb
#
# ==============================================================================
# UserSetting（ユーザー設定）モデル（D-10 更新: AI レート制限メソッドを追加）
# ==============================================================================
# 【このモデルの役割】
#   ユーザーごとの各種設定（通知設定・お休みモード・AIコスト管理）を管理する。
#   user_settings テーブルに対応しており、1ユーザーに1レコード（has_one）。
#
# 【D-10 での変更内容】
#   ① ai_recently_requested? メソッドを追加
#      - last_ai_requested_at が 1 分以内かどうかを判定する
#   ② touch_ai_requested_at! メソッドを追加
#      - リクエスト受付時に last_ai_requested_at を現在時刻で更新する
#
# 【テーブルの主なカラム（schema.rb より）】
#   time_zone                  : タイムゾーン（デフォルト: "Asia/Tokyo"）
#   notification_enabled       : 通知全体の ON/OFF
#   line_notification_enabled  : LINE通知の ON/OFF
#   email_notification_enabled : メール通知の ON/OFF
#   daily_notification_limit   : 1日の最大通知数
#   daily_notification_count   : 当日の送信済み通知数
#   rest_mode_until            : お休みモード終了日時（NULL = お休みモードなし）
#   rest_mode_reason           : お休みの理由（任意）
#   ai_analysis_count          : 当月のAI分析使用回数
#   ai_analysis_monthly_limit  : 月間AI分析上限
#   last_ai_requested_at       : 最後に AI 分析リクエストを受け付けた日時（D-10 追加）
# ==============================================================================

class UserSetting < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :user
  # 【理由】
  #   user_settings テーブルには user_id カラムがあり、
  #   1つの設定レコードは必ず1人のユーザーに属する。
  belongs_to :user

  # ============================================================
  # バリデーション
  # ============================================================

  validates :time_zone, presence: true

  validates :daily_notification_limit,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  validates :ai_analysis_monthly_limit,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1
            }

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # rest_mode_active?
  # 【役割】現在お休みモード中かどうかを返す。
  def rest_mode_active?
    rest_mode_until.present? && rest_mode_until > Time.current
  end

  # ============================================================
  # D-10 追加: AI レート制限メソッド
  # ============================================================

  # ai_recently_requested?
  # ----------------------------------------------------------
  # 【役割】
  #   直前の AI 分析リクエストから 1 分以内かどうかを返す。
  #   true  → 1 分以内に既にリクエストがある（連打とみなす）
  #   false → 1 分以上経過している（新たにリクエストを受け付ける）
  #
  # 【last_ai_requested_at が nil の場合】
  #   nil は「一度もリクエストしたことがない」を意味する。
  #   nil.present? = false なので false を返す → 制限なし（正しい挙動）
  #
  # 【AI_THROTTLE_INTERVAL の意味】
  #   1.minute は ActiveSupport の Duration オブジェクト。
  #   Time.current - 1.minute で「1分前の時刻」を表す。
  #   last_ai_requested_at > (1分前) = 「1分以内にリクエストがある」
  # ----------------------------------------------------------
  def ai_recently_requested?
    # last_ai_requested_at が nil（初回）の場合は false を返す
    return false unless last_ai_requested_at.present?

    # 1分以内かどうかを判定する
    # Time.current: タイムゾーンを考慮した現在時刻（Rails の標準メソッド）
    # 1.minute: 60秒を表す ActiveSupport::Duration
    last_ai_requested_at > Time.current - 1.minute
  end

  # touch_ai_requested_at!
  # ----------------------------------------------------------
  # 【役割】
  #   AI 分析リクエストを受け付けた時刻を現在時刻で更新する。
  #   throttle チェックを通過した直後に呼び出す。
  #
  # 【update_columns を使う理由】
  #   update! だとバリデーションとコールバックが全て走る。
  #   last_ai_requested_at の更新だけなら update_columns で十分。
  #   update_columns は SQL を1本だけ発行するため高速。
  #
  # 【! （バングメソッド）の意味】
  #   update_columns が失敗（DB エラー等）した場合に
  #   呼び出し元でエラーを検知しやすくするためにバング名にしている。
  #   ActiveRecord の update_columns 自体は失敗時に false を返すが、
  #   メソッド名の ! で「重要な副作用がある」ことを明示する慣習。
  # ----------------------------------------------------------
  def touch_ai_requested_at!
    update_columns(last_ai_requested_at: Time.current)
  end
end