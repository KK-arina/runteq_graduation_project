# app/models/ai_analysis.rb（model_name → ai_model_name に修正）

class AiAnalysis < ApplicationRecord
  belongs_to :user_purpose,    optional: true
  belongs_to :weekly_reflection, optional: true

  enum :analysis_type, {
    weekly_reflection: 0,
    purpose_breakdown: 1,
    monthly_review:    2
  }

  validates :analysis_type, presence: true
  validate  :at_least_one_parent_present

  before_create :deactivate_previous_analyses

  scope :latest,      -> { where(is_latest: true) }
  scope :for_purpose, ->(user_purpose) { where(user_purpose: user_purpose) }

  private

  def at_least_one_parent_present
    if weekly_reflection_id.blank? && user_purpose_id.blank?
      errors.add(:base, "weekly_reflection_id または user_purpose_id のどちらかは必須です")
    end
  end

  def deactivate_previous_analyses
    if user_purpose_id.present?
      AiAnalysis.where(
        user_purpose_id: user_purpose_id,
        analysis_type:   analysis_type,
        is_latest:       true
      ).update_all(is_latest: false)
    end

    if weekly_reflection_id.present?
      AiAnalysis.where(
        weekly_reflection_id: weekly_reflection_id,
        is_latest:            true
      ).update_all(is_latest: false)
    end
  end
end