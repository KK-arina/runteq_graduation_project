# app/jobs/update_ai_profile_job.rb
class UpdateAiProfileJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id = nil)
    if user_id.present?
      update_single_user(user_id)
    else
      update_all_users
    end
  end

  private

  def update_single_user(user_id)
    user = User.active.find(user_id)
    Rails.logger.info "[UpdateAiProfileJob] 単一ユーザー更新開始: user_id=#{user_id}"
    result = UserContextBuilderService.new(user: user).call
    if result[:success]
      Rails.logger.info "[UpdateAiProfileJob] 単一ユーザー更新完了: user_id=#{user_id}"
    else
      Rails.logger.error "[UpdateAiProfileJob] 単一ユーザー更新失敗: user_id=#{user_id}, error=#{result[:error]}"
    end
  end

  def update_all_users
    Rails.logger.info "[UpdateAiProfileJob] 全ユーザー週次更新開始"
    success_count = 0
    failure_count = 0

    # includes を付ける理由:
    #   UserContextBuilderService 内で habits / weekly_reflections / tasks を
    #   参照するため、find_each のバッチごとに一緒に読み込んでおく。
    #   ただし has_many の includes は find_each と組み合わせると
    #   バッチ境界でアソシエーションがリセットされるため、
    #   実効性は限定的。H-9 で改めて bullet gem で確認する。
    # 【TODO: H-9】find_each + includes の組み合わせの効果を bullet で測定する
    User.active.find_each do |user|
      result = UserContextBuilderService.new(user: user).call
      if result[:success]
        success_count += 1
      else
        failure_count += 1
        Rails.logger.error "[UpdateAiProfileJob] ユーザー更新失敗: user_id=#{user.id}, error=#{result[:error]}"
      end
    rescue => e
      failure_count += 1
      Rails.logger.error "[UpdateAiProfileJob] 予期しないエラー: user_id=#{user.id}, error=#{e.message}"
    end

    Rails.logger.info "[UpdateAiProfileJob] 全ユーザー週次更新完了: success=#{success_count}, failure=#{failure_count}"
  end
end