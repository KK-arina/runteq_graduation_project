# app/models/user_purpose.rb
#
# ==============================================================================
# UserPurpose（PMVV目標）モデル（E-1修正: 5フィールドを必須化）
# ==============================================================================
# 【E-1修正での変更内容】
#   ユーザーフィードバックにより以下5フィールドを必須化する:
#   ① purpose           - Purpose: 人生で一番大切にしていることは？
#   ② vision            - Vision: 1年後どんな自分になっていたいか？
#   ③ mission           - Mission: 今の自分に最も必要なことは？
#   ④ value             - Value: 絶対に譲れないことは？
#   ⑤ current_situation - Current: 今の自分の現状
#
# 【重要: CrisisDetector は削除しない】
#   既存の実装で include CrisisDetector されており、
#   crisis_word_detected? メソッドが OnboardingsController / CrisisDetectorTest で使われる。
#   E-1修正で誤って削除していたため復元する。
# ==============================================================================

class UserPurpose < ApplicationRecord
  # ── CrisisDetector モジュールをインクルードする ───────────────────────────
  #
  # 【インクルードの理由】
  #   PMVV 入力フォームの各テキストフィールドに「死にたい」「消えたい」などの
  #   危機ワードが含まれていないかを before_validation で自動検出する。
  #   検出された場合は crisis_word_detected フラグが true になる。
  #   OnboardingsController#complete がこのフラグを確認して
  #   危機介入モーダルを表示するかどうかを判断する。
  include CrisisDetector
  # ────────────────────────────────────────────────────────────────────────────

  # ============================================================
  # アソシエーション
  # ============================================================
  belongs_to :user

  # ============================================================
  # Enum 定義
  # ============================================================
  # analysis_state: AI分析の進捗状態を管理する
  #   pending:   分析待ち（ジョブがエンキューされていない状態）
  #   analyzing: 分析中（GoodJobがジョブを実行中の状態）
  #   completed: 分析完了（AI分析が正常に終わった状態）
  #   failed:    分析失敗（エラーが発生した状態）
  enum :analysis_state, {
    pending:   0,
    analyzing: 1,
    completed: 2,
    failed:    3
  }

  # ============================================================
  # バリデーション
  # ============================================================

  # version: 必須・1以上の整数
  validates :version,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  # ── E-1修正: purpose を必須化 ─────────────────────────────────────────────
  #
  # 【変更前】length: { maximum: 500 }, allow_blank: true（任意）
  # 【変更後】presence: true を追加（必須）
  #
  # 【i18n との連携】
  #   ja.yml の activerecord.attributes.user_purpose.purpose
  #   に "Purpose（人生で大切にしていること）" と定義してあるため、
  #   エラーメッセージは「Purpose（人生で大切にしていること）を入力してください」になる。
  validates :purpose,
            presence: { message: "を入力してください" },
            length: { maximum: 500 }

  # ── E-1修正: mission を必須化 ─────────────────────────────────────────────
  #
  # 【i18n との連携】
  #   ja.yml: mission = "Mission（今最も必要なこと）"
  #   エラー: 「Mission（今最も必要なこと）を入力してください」
  validates :mission,
            presence: { message: "を入力してください" },
            length: { maximum: 500 }

  # ── E-1修正: vision を必須化 ──────────────────────────────────────────────
  #
  # 【i18n との連携】
  #   ja.yml: vision = "Vision（1年後の理想の自分）"
  #   エラー: 「Vision（1年後の理想の自分）を入力してください」
  validates :vision,
            presence: { message: "を入力してください" },
            length: { maximum: 500 }

  # ── E-1修正: value を必須化 ───────────────────────────────────────────────
  #
  # 【i18n との連携】
  #   ja.yml: value = "Value（絶対に譲れないこと）"
  #   エラー: 「Value（絶対に譲れないこと）を入力してください」
  validates :value,
            presence: { message: "を入力してください" },
            length: { maximum: 500 }

  # ── E-1修正: current_situation を必須化 ───────────────────────────────────
  #
  # 【i18n との連携】
  #   ja.yml: current_situation = "Current（今の自分の現状）"
  #   エラー: 「Current（今の自分の現状）を入力してください」
  validates :current_situation,
            presence: { message: "を入力してください" },
            length: { maximum: 500 }

  # ============================================================
  # スコープ
  # ============================================================

  # active_for: 指定ユーザーの有効な UserPurpose を返す
  scope :active_for, ->(user) { where(user: user, is_active: true).order(version: :desc) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # current_for: ユーザーの現在有効な UserPurpose を1件返す
  def self.current_for(user)
    active_for(user).first
  end

  # ============================================================
  # インスタンスメソッド（analysis_state 関連）
  # ============================================================

  # pending?: 分析待ち状態か
  def pending?
    analysis_state == "pending"
  end

  # analyzing?: 分析中か
  def analyzing?
    analysis_state == "analyzing"
  end

  # completed?: 分析完了か
  def completed?
    analysis_state == "completed"
  end

  # failed?: 分析失敗か
  def failed?
    analysis_state == "failed"
  end

  # ============================================================
  # プライベートメソッド
  # ============================================================
  private

  # ── crisis_text_fields: CrisisDetector が検索対象とするフィールドを返す ───
  #
  # 【役割】
  #   CrisisDetector モジュールの check_crisis_keywords メソッドが
  #   危機ワードを検索する対象フィールドの値を配列で返す。
  #   UserPurpose の全テキストフィールドを対象にする。
  #
  # 【なぜ private か】
  #   このメソッドは CrisisDetector から内部的に呼ばれるため、
  #   外部から直接呼ばれる必要はない。
  def crisis_text_fields
    [
      purpose,
      mission,
      vision,
      value,
      current_situation
    ]
  end
  # ────────────────────────────────────────────────────────────────────────────
end
