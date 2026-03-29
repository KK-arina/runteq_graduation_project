# app/models/user_setting.rb
#
# ==============================================================================
# UserSetting（ユーザー設定）モデル
# ==============================================================================
# 【このモデルの役割】
#   ユーザーごとの各種設定（通知設定・お休みモード・AIコスト管理）を管理する。
#   user_settings テーブルに対応しており、1ユーザーに1レコード（has_one）。
#
# 【B-3 での利用箇所】
#   Habit#on_rest_mode? メソッド内で
#   user.user_setting&.rest_mode_until を参照し、
#   「現在お休みモード中かどうか」を判定するために使用する。
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
# ==============================================================================

class UserSetting < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :user
  # 【理由】
  #   user_settings テーブルには user_id カラムがあり、
  #   1つの設定レコードは必ず1人のユーザーに属する。
  #   dependent はなし（User 側の has_one で管理する）。
  belongs_to :user

  # ============================================================
  # バリデーション
  # ============================================================

  # time_zone は必須
  validates :time_zone, presence: true

  # daily_notification_limit は 0 以上の整数
  validates :daily_notification_limit,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }

  # ai_analysis_monthly_limit は 1 以上の整数
  validates :ai_analysis_monthly_limit,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 1
            }

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # rest_mode_active?
  # 【役割】
  #   「現在お休みモード中かどうか」を返す便利メソッド。
  #   rest_mode_until が設定されており、かつ現在時刻より未来であれば true。
  #
  # 【present? とは】
  #   nil でも空文字でもなければ true を返す ActiveSupport のメソッド。
  #   rest_mode_until が nil の場合（お休みモード未設定）は false になる。
  def rest_mode_active?
    rest_mode_until.present? && rest_mode_until > Time.current
  end
end