# frozen_string_literal: true

class PatternFeedback < ApplicationRecord
  belongs_to :categorization_pattern, optional: true
  belongs_to :expense
  belongs_to :category # The correct category from the migration schema
  
  validates :feedback_type, presence: true, inclusion: { in: %w[accepted rejected corrected correction] }
  
  before_validation :set_default_feedback_type
  
  scope :accepted, -> { where(feedback_type: "accepted") }
  scope :rejected, -> { where(feedback_type: "rejected") }
  scope :corrected, -> { where(feedback_type: "corrected") }
  scope :correction, -> { where(feedback_type: "correction") }
  scope :recent, -> { order(created_at: :desc) }
  
  after_create :update_pattern_performance
  after_create :create_pattern_from_correction, if: :correction_feedback?
  
  # Class method to create feedback records
  def self.record_feedback(expense:, correct_category:, pattern: nil, was_correct:, confidence: nil, type: "confirmation")
    create!(
      expense: expense,
      category: correct_category,
      categorization_pattern: pattern,
      was_correct: was_correct,
      confidence_score: confidence,
      feedback_type: %w[accepted rejected corrected correction].include?(type) ? type : "accepted"
    )
  end
  
  # Check if this feedback indicates success
  def successful?
    was_correct == true
  end
  
  # Generate improvement suggestion based on feedback
  def improvement_suggestion
    return nil unless feedback_type.in?(%w[rejected corrected correction])
    
    # Determine suggested pattern type based on expense data
    suggested_pattern_type = if expense&.merchant_name.present?
                               "merchant"
                             elsif expense&.description.present?
                               "description"
                             else
                               "keyword"
                             end
    
    {
      suggested_action: feedback_type == "correction" ? "create_new_pattern" : "adjust_pattern",
      category_id: category&.id,
      pattern_type: suggested_pattern_type,
      pattern_value: expense&.merchant_name || expense&.description,
      confidence_adjustment: feedback_type == "correction" ? 0.2 : -0.1,
      context: {
        expense_merchant: expense&.merchant_name,
        expense_amount: expense&.amount,
        expense_date: expense&.transaction_date,
        original_pattern_type: categorization_pattern&.pattern_type,
        original_pattern_value: categorization_pattern&.pattern_value
      }
    }
  end
  
  private
  
  def set_default_feedback_type
    self.feedback_type ||= was_correct ? "accepted" : "rejected"
  end
  
  def correction_feedback?
    feedback_type == "correction"
  end
  
  def create_pattern_from_correction
    suggestion = improvement_suggestion
    return unless suggestion && suggestion[:pattern_type] && suggestion[:pattern_value]
    
    # Check if pattern already exists for this category and value
    existing_pattern = CategorizationPattern.find_by(
      category: category,
      pattern_type: suggestion[:pattern_type],
      pattern_value: suggestion[:pattern_value]
    )
    
    return if existing_pattern
    
    # Create new pattern from the correction
    CategorizationPattern.create!(
      category: category,
      pattern_type: suggestion[:pattern_type],
      pattern_value: suggestion[:pattern_value],
      confidence_weight: 1.2, # Slightly higher confidence for user corrections
      user_created: true,
      metadata: {
        created_from_feedback: true,
        feedback_id: id,
        expense_id: expense_id
      }
    )
  end
  
  def update_pattern_performance
    return unless categorization_pattern
    
    case feedback_type
    when "accepted"
      categorization_pattern.record_usage(true)
    when "rejected", "corrected", "correction"
      categorization_pattern.record_usage(false)
    end
  end
end