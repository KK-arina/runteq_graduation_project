# app/models/application_record.rb
#
# ============================================================
# 【このファイルの役割】
# 全てのモデルの親クラス。共通のトランザクションメソッドを定義する。
#
# 【Issue #A-7 最終修正版】
#
# 【設計方針の変更】
# with_transaction は「例外をキャッチしない」シンプルなラッパーにする。
# 例外のハンドリング（rescue）はサービスクラス側で行う。
#
# 【なぜ with_transaction 内で rescue しないのか】
#
#   問題のあった設計:
#     def with_transaction
#       transaction { yield }
#       { success: true }
#     rescue => e
#       { success: false }   ← ここで例外を握りつぶす
#     end
#
#   ネスト時に何が起きるか:
#     外側 transaction do
#       習慣1を作成
#       内側 with_transaction do     ← 内側の with_transaction を呼ぶ
#         習慣2を作成
#         例外発生
#       end                          ← 内側の rescue が例外をキャッチ → Hash 返す
#     end                            ← 外側は例外を知らない → COMMIT される
#
#   → 習慣1も習慣2もDBに保存されてしまう（ロールバックなし）
#
# 【正しい設計】
# with_transaction は transaction ブロックを提供するだけ。
# 例外はそのまま外に伝播させ、サービスクラス側の rescue で処理する。
#
#   サービスクラス:
#     def call
#       ApplicationRecord.with_transaction do
#         ...  ← ここで例外が発生すると
#       end    ← transaction を抜ける前に Rails がロールバック
#       { success: true }
#     rescue ActiveRecord::RecordInvalid => e
#       { success: false, error: e.message }  ← ロールバック後にここに来る
#     end
#
# 【with_transaction のネスト使用は禁止】
# with_transaction の中で with_transaction を呼ばないこと。
# WeeklyReflectionHabitSummary.create_all_for_reflection! の内部 transaction は
# 外側の with_transaction の transaction ブロックに「合流」するため問題ない。
# これは with_transaction のネストとは異なる。
# ============================================================

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  class << self
    # ==========================================================
    # with_transaction（Issue #A-7 最終版）
    # ==========================================================
    # 【役割】
    # ActiveRecord::Base.transaction のシンプルなラッパー。
    # 例外はキャッチせずそのまま外に伝播させる。
    #
    # 【重要: このメソッドはネストして使わないこと】
    # with_transaction の中で with_transaction を呼ぶと、
    # 内側の例外が外側に伝播しない問題が起きる。
    # rescue はサービスクラス側でのみ書く。
    #
    # 【使い方（サービスクラス内）】
    #   def call
    #     ApplicationRecord.with_transaction do
    #       record1.save!    ← 失敗すると例外が外に出る
    #       record2.save!    ← record1 の保存もロールバックされる
    #     end
    #     { success: true, error: nil }
    #   rescue ActiveRecord::RecordInvalid => e
    #     { success: false, error: e.message }
    #   rescue StandardError => e
    #     { success: false, error: "予期しないエラーが発生しました" }
    #   end
    #
    # 【なぜ yield だけなのか】
    # Rails の ActiveRecord::Base.transaction は、ブロック内で例外が発生すると
    # 自動的にロールバックして例外を再 raise する。
    # with_transaction はこの動作を「そのまま活かす」だけのラッパー。
    # rescue を書かないことで、呼び出し元（サービスクラス）に
    # 「何が起きたか」を正確に伝えることができる。
    def with_transaction(&block)
      # ActiveRecord::Base.transaction
      # → ブロック内の全 DB 操作を1つのトランザクションとして実行する。
      # → ブロック内で例外が発生した場合:
      #   1. Rails がロールバックを実行する
      #   2. 例外をそのまま再 raise する（外に伝播させる）
      # → ブロックが正常終了した場合: COMMIT する
      #
      # &block
      # → yield と同じ意味だが、ブロックを明示的に受け取って transaction に渡す。
      # → ActiveRecord::Base.transaction(&block) と書くことで
      #   ブロックを直接 transaction に渡せる（最も明確な書き方）。
      ActiveRecord::Base.transaction(&block)
    end
  end
end