# app/models/user_purpose.rb
#
# ==============================================================================
# UserPurpose（PMVV目標）モデル
# ==============================================================================
#
# 【このファイルの役割】
#   ユーザーの PMVV（Purpose / Mission / Vision / Value / Current）を
#   バージョン管理する。
#   1人のユーザーが何度でも目標を更新でき、履歴として保存される。
#   現在有効な目標は is_active=true で識別する。
#
# 【テーブル設計（schema.rbより）】
#   user_purposes テーブルの主要カラム:
#     purpose          : text  - 人生で一番大切にしていること
#     mission          : text  - 今の自分に最も必要なこと
#     vision           : text  - 1年後どんな自分になっていたいか
#     value            : text  - 絶対に譲れないこと
#     current_situation: text  - 今の自分の現状
#     version          : integer(default: 1) - バージョン番号
#     is_active        : boolean(default: true) - 現在有効か
#     analysis_state   : integer(default: 0) - AI分析の状態
#     last_error_message: text - 分析失敗時のエラー内容
#
# 【バージョン管理の仕組み】
#   ユーザーが目標を更新するたびに新しいレコードを作成し、
#   古いレコードの is_active を false にする。
#   これにより過去の目標履歴をすべて保持できる。
#
# 【analysis_state の遷移】
#   pending(0) → analyzing(1) → completed(2)
#                             ↘ failed(3)
#   保存直後は pending に設定され、GoodJob で非同期に分析される。
#
# ==============================================================================

class UserPurpose < ApplicationRecord
  # ============================================================
  # アソシエーション
  # ============================================================

  # belongs_to :user
  # 【理由】
  #   1つの目標レコードは必ず1人のユーザーに属する（多対1の関係）。
  #   schema.rb の add_foreign_key "user_purposes", "users" に対応する。
  belongs_to :user

  # ============================================================
  # enum 定義
  # ============================================================

  # analysis_state: AI分析ジョブの状態を整数で管理する
  # 【なぜ enum を使うのか】
  #   DB には整数（0/1/2/3）で保存するが、コードでは
  #   user_purpose.pending? や user_purpose.analysis_state = :analyzing
  #   のように意味のある名前で扱える。可読性が高くバグを減らせる。
  #
  # 【各状態の意味】
  #   pending(0)   : 保存直後。AI分析ジョブのエンキュー待ち
  #   analyzing(1) : GoodJob がジョブを取り出し分析中
  #   completed(2) : AI分析が正常に完了した
  #   failed(3)    : AI分析が失敗した（last_error_message に詳細を記録）
  #
  # 【prefix: :analysis_state について】
  #   prefix を使わないと pending?/completed? などのメソッドが生成される。
  #   他のモデルでも pending? を使う可能性があるため、
  #   analysis_state_pending? のようにプレフィックスを付けることで
  #   メソッド名の衝突を防ぐ。
  #   ただし D-2 以降での実装を考慮し、今回はシンプルに prefix なしで定義する。
  enum :analysis_state, {
    pending:   0,
    analyzing: 1,
    completed: 2,
    failed:    3
  }

  # ============================================================
  # バリデーション
  # ============================================================

  # validates :user, presence: true
  # 【理由】
  #   belongs_to は Rails 5 以降でデフォルトで presence バリデーションが
  #   自動的に追加されるため、明示的な記述は不要。
  #   しかし意図を明確にするため、以下では他のバリデーションを定義する。

  # version のバリデーション
  # 【理由】
  #   バージョン番号は必ず1以上の整数であることを保証する。
  #   before_save コールバックで自動的に設定されるが、
  #   直接保存される場合のための安全網として定義する。
  validates :version,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  # 各フィールドの文字数制限
  # 【理由】
  #   text 型は DB レベルでは制限なしだが、
  #   AIへのプロンプトに組み込む際のトークン数を抑えるため
  #   アプリ側で1000文字の上限を設ける。
  #   allow_blank: true で任意入力（空欄可）にする。
  validates :purpose,           length: { maximum: 1000 }, allow_blank: true
  validates :mission,           length: { maximum: 1000 }, allow_blank: true
  validates :vision,            length: { maximum: 1000 }, allow_blank: true
  validates :value,             length: { maximum: 500  }, allow_blank: true
  validates :current_situation, length: { maximum: 1000 }, allow_blank: true

  # 【バリデーション: 少なくとも1フィールドは入力必須】
  # 全フィールドが空白のままでは PMVV として意味がないため
  # カスタムバリデーションで1つ以上の入力を要求する。
  validate :at_least_one_field_present

  # ============================================================
  # スコープ
  # ============================================================

  # scope :active → is_active=true のレコードのみ取得
  # 【使用場面】
  #   UserPurpose.active.find_by(user: current_user)
  #   のように現在有効な目標だけを取得したいときに使う。
  scope :active, -> { where(is_active: true) }

  # scope :by_version → バージョン番号の降順で取得
  # 【使用場面】
  #   ユーザーの目標履歴を新しい順に表示するとき。
  scope :by_version, -> { order(version: :desc) }

  # ============================================================
  # コールバック
  # ============================================================

  # before_validation :set_version
  # 【なぜ before_validation か】
  #   validates :version, presence: true があるため、
  #   バリデーション実行前に version を設定しておく必要がある。
  #   before_save だとバリデーション後なので validation エラーが出てしまう。
  before_validation :set_version, on: :create

  # before_save :deactivate_previous_versions
  # 【役割】
  #   新しいレコードを保存する直前に、同じユーザーの既存の
  #   is_active=true のレコードを全て is_active=false に更新する。
  #   これにより「常に1つの is_active=true しか存在しない」状態を保つ。
  #
  # 【なぜ before_save か】
  #   create と update の両方で実行したいため before_save を使う。
  #   on: :create だと update 時（将来の実装）に走らないため除外する。
  #
  # 【注意: before_save は self がまだ DB に保存される前に実行される】
  #   そのため self を除外する条件（id が nil の場合 or self.id != id）は
  #   新規作成時には考慮不要。update の場合は別途対応する。
  before_save :deactivate_previous_versions

  # ============================================================
  # クラスメソッド
  # ============================================================

  # UserPurpose.current_for(user)
  # 【役割】
  #   指定ユーザーの現在有効な PMVV を1件返す。
  #   存在しなければ nil を返す。
  # 【使用場面】
  #   UserPurposesController の show / edit で使う。
  def self.current_for(user)
    where(user: user, is_active: true).order(version: :desc).first
  end

  # ============================================================
  # Private メソッド
  # ============================================================
  private

  # set_version
  # 【役割】
  #   新規作成時（on: :create）に version 番号を自動設定する。
  #   既存の最大バージョン + 1 を設定することで連番が保証される。
  #   レコードが1件もない場合は 1 を設定する。
  def set_version
    # maximum(:version) → 同一ユーザーの最大バージョン番号を取得する
    # .to_i → nil の場合（初回）に 0 を返す（nil.to_i = 0）
    # + 1 → 現在の最大に1加算して新しいバージョン番号にする
    max_version = user.user_purposes.maximum(:version).to_i
    self.version = max_version + 1
  end

  # deactivate_previous_versions
  # 【役割】
  #   このレコードを保存する前に、同一ユーザーの既存の
  #   is_active=true のレコードを全て is_active=false に更新する。
  #
  # 【update_all を使う理由】
  #   update_all は SQL の UPDATE 文を1回だけ発行するため高速。
  #   each { |r| r.update! } だと N+1 回の UPDATE が発生する。
  #   コールバックやバリデーションをスキップするが、
  #   is_active フラグの変更のみなので問題ない。
  #
  # 【where.not(id: id_was || id) の意味】
  #   新規作成時: id はまだ nil なので「全件を対象」にする。
  #   更新時: 自分自身を除外する（将来の実装での安全網）。
  #   id_was は変更前の id を返す（変更されていれば nil を返す）。
  def deactivate_previous_versions
    scope = user.user_purposes.where(is_active: true)
    # 更新時は自分自身を除外する
    scope = scope.where.not(id: id) if persisted?
    scope.update_all(is_active: false)
  end

  # at_least_one_field_present
  # 【役割】
  #   5つの PMVV フィールドのうち少なくとも1つは入力されていることを検証する。
  #   全て空白の場合はエラーメッセージを追加する。
  def at_least_one_field_present
    fields = [purpose, mission, vision, value, current_situation]
    # all? { |f| f.blank? } → 全フィールドが空白かどうか
    if fields.all?(&:blank?)
      errors.add(:base, "Purpose / Mission / Vision / Value / Current のうち少なくとも1つを入力してください")
    end
  end
end