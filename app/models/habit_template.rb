# app/models/habit_template.rb
#
# ==============================================================================
# HabitTemplate モデル
# ==============================================================================
#
# 【このモデルの役割】
# オンボーディング（初回ログイン時のガイド）で表示する
# 「習慣のテンプレート（雛形）」を管理するモデルです。
#
# ユーザーが習慣を一から考えなくても、
# カテゴリ別のテンプレートから選択できるようにするためのマスタデータです。
#
# 【テーブル名】
# habit_templates（#A-1 のマイグレーションで作成済み）
#
# 【カラム一覧】
# name                 : 習慣名（例: "筋トレ"）
# measurement_type     : 測定タイプ（0: チェック型 / 1: 数値型）
# default_unit         : 数値型の単位（例: "分", "冊"）チェック型は nil
# default_weekly_target: 週の目標回数（例: 5 → 週5回）
# category             : カテゴリ（0:健康 1:フィットネス 2:学習 3:マインド 4:その他）
# description          : テンプレートの説明文
# sort_order           : 一覧表示の並び順（数値が小さいほど先に表示）
# is_active            : 公開フラグ（true: 表示する / false: 非表示）
# ==============================================================================

class HabitTemplate < ApplicationRecord
  # ============================================================================
  # 定数定義
  # ============================================================================

  # measurement_type の enum 定義
  #
  # 【enum とは】
  # 整数カラムに「名前」を付ける Rails の機能です。
  # DBには 0, 1 という数値で保存されますが、
  # コード上では :check_type, :numeric_type という名前で扱えます。
  #
  # 例:
  #   template.check_type?    # => true / false
  #   template.measurement_type  # => "check_type"
  #   HabitTemplate.check_type   # => チェック型のレコード一覧
  enum :measurement_type, {
    check_type:   0,  # チェック型: やった/やらないで記録（読書・瞑想など）
    numeric_type: 1   # 数値型: 回数・時間・距離などで記録（ジョギング・水分補給など）
  }

  # category の enum 定義
  #
  # 【なぜ integer で管理するのか】
  # カテゴリ名を文字列で保存すると、タイポ（typo）や
  # 表記ゆれ（"health" / "Health"）が発生するリスクがあります。
  # integer + enum にすることで、使える値を限定できます。
  enum :category, {
    health:    0,  # 健康カテゴリ（読書・瞑想・睡眠など）
    fitness:   1,  # フィットネスカテゴリ（筋トレ・ジョギングなど）
    study:     2,  # 学習カテゴリ（英語学習・プログラミングなど）
    mind:      3,  # マインドカテゴリ（日記・感謝リスト・呼吸法など）
    other:     4   # その他カテゴリ（どのカテゴリにも属さないもの）
  }

  # ============================================================================
  # バリデーション（入力値の検証ルール）
  # ============================================================================
  #
  # 【バリデーションとは】
  # DB に保存する前に「このデータは正しいか？」をチェックする仕組みです。
  # ルールに違反しているデータは保存されず、エラーメッセージが返ります。

  # name（習慣名）は必須・100文字以内
  validates :name,
            presence:   true,                          # 空文字・nil を禁止
            length:     { maximum: 100 }               # 100文字以内

  # measurement_type（測定タイプ）は必須
  # enum で定義した値以外は自動的にエラーになるため、presence のみで十分
  validates :measurement_type, presence: true

  # default_weekly_target（週次目標回数）は必須・1〜7の整数
  validates :default_weekly_target,
            presence:     true,
            numericality: {
              only_integer:             true,  # 小数を禁止（整数のみ許可）
              greater_than_or_equal_to: 1,     # 1回以上
              less_than_or_equal_to:    7      # 7回以下（1週間は7日なので上限は7）
            }

  # category（カテゴリ）は必須
  validates :category, presence: true

  # ============================================================================
  # スコープ（よく使う検索条件に名前をつけたもの）
  # ============================================================================
  #
  # 【スコープとは】
  # よく使う WHERE 条件に名前をつける機能です。
  # HabitTemplate.active のように簡潔に書けるようになります。

  # active: is_active = true のテンプレートのみ取得（公開中のもの）
  # ordered: sort_order の昇順で並び替え（数値が小さいほど先に表示）
  scope :active,   -> { where(is_active: true) }
  scope :ordered,  -> { order(:sort_order) }

  # active_ordered: 公開中かつ並び順でよく使う組み合わせ
  scope :active_ordered, -> { active.ordered }
end