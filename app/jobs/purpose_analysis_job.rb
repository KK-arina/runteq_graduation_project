# app/jobs/purpose_analysis_job.rb
#
# ==============================================================================
# PurposeAnalysisJob（PMVV AI分析ジョブ）
# ==============================================================================
#
# 【このファイルの役割】
#   UserPurpose が保存された後に GoodJob によって非同期実行される。
#   PMVV データを AI（Gemini API）に送信して分析結果を取得し、
#   ai_analyses テーブルに保存する。
#
# 【D-1 時点での実装状態】
#   D-1 ではジョブのスケルトン（骨格）のみ作成する。
#   perform メソッドの中身は D-2（PMVV AI分析ジョブ実装）で実装する。
#   D-1 では「analysis_state を pending → analyzing に変更する」のみ実装し、
#   実際の AI API 呼び出しは D-2 で追加する。
#
# 【GoodJob との連携】
#   UserPurposesController#create / #update で
#   PurposeAnalysisJob.perform_later(user_purpose.id)
#   を呼び出すことで GoodJob キューに追加される。
#   GoodJob は good_jobs テーブルを監視してジョブを取り出し実行する。
#
# 【引数に id（整数）を渡す理由】
#   GoodJob はジョブの引数を JSON 形式で good_jobs.serialized_params に保存する。
#   ActiveRecord のインスタンスは JSON シリアライズできないため、
#   id のみを渡して perform 内で find して再取得する。
#   discard_on ActiveRecord::RecordNotFound と組み合わせることで、
#   ユーザーが目標を削除した後に残ったジョブを自動破棄できる。
#
# ==============================================================================

class PurposeAnalysisJob < ApplicationJob
  # queue_as :default
  # 【理由】
  #   GoodJob のデフォルトキューに追加する。
  #   AI 分析は重い処理のため、将来的に専用キュー（:ai_analysis 等）に
  #   分けることも検討できるが、D-1 時点では default で十分。
  queue_as :default

  # perform(user_purpose_id)
  # 【引数】
  #   user_purpose_id: UserPurpose の id（整数）
  #
  # 【D-1 での実装内容】
  #   1. UserPurpose を id で取得する
  #      → 存在しない場合は discard_on により自動破棄される
  #   2. analysis_state を pending → analyzing に変更する
  #      → D-2 では analyzing → AI 呼び出し → completed/failed の流れを実装する
  #
  # 【D-2 で追加予定の処理】
  #   - AiClient を使って Gemini API に PMVV データを送信する
  #   - レスポンスをパースして ai_analyses テーブルに保存する
  #   - analysis_state を completed または failed に更新する
  #   - Turbo Stream で 16番ページ（PMVV目標管理）をリアルタイム更新する
  def perform(user_purpose_id)
    # find: id で UserPurpose を取得する
    # 存在しない場合は ActiveRecord::RecordNotFound が発生し、
    # ApplicationJob の discard_on により静かに破棄される
    user_purpose = UserPurpose.find(user_purpose_id)

    # D-1: analysis_state を analyzing に更新する
    # update_columns を使う理由:
    #   - バリデーションをスキップして直接 DB を更新する（高速）
    #   - updated_at を更新しない（ジョブによる状態更新と区別できる）
    #   - before_save の deactivate_previous_versions を再実行しない
    user_purpose.update_columns(analysis_state: UserPurpose.analysis_states[:analyzing])

    # ================================================================
    # D-2 で以下の処理を追加する:
    # ================================================================
    # result = AiClient.new.analyze(build_prompt(user_purpose))
    # if result
    #   AiAnalysis.create!(
    #     user_purpose: user_purpose,
    #     analysis_type: :purpose_breakdown,
    #     analysis_comment: result[:comment],
    #     ...
    #   )
    #   user_purpose.update_columns(analysis_state: UserPurpose.analysis_states[:completed])
    # else
    #   user_purpose.update_columns(
    #     analysis_state: UserPurpose.analysis_states[:failed],
    #     last_error_message: "AI分析に失敗しました"
    #   )
    # end
    # ================================================================

    Rails.logger.info "[PurposeAnalysisJob] D-1 スタブ実行完了: user_purpose_id=#{user_purpose_id}"
  end
end