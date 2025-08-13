# frozen_string_literal: true

# Model to track individual items within a bulk operation
class BulkOperationItem < ApplicationRecord
  # Associations
  belongs_to :bulk_operation
  belongs_to :expense
  belongs_to :previous_category, class_name: "Category", optional: true
  belongs_to :new_category, class_name: "Category", optional: true

  # Enums
  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2,
    skipped: 3,
    undone: 4
  }, default: :pending

  # Validations
  validates :expense_id, uniqueness: { scope: :bulk_operation_id }

  # Scopes
  scope :successful, -> { where(status: :completed) }
  scope :failed, -> { where(status: :failed) }
  scope :with_category_change, -> { where.not(previous_category_id: nil) }

  # Instance methods
  def category_changed?
    previous_category_id != new_category_id
  end

  def confidence_delta
    return nil unless expense.categorization_confidence.present? && previous_confidence.present?

    expense.categorization_confidence - previous_confidence
  end

  def processing_time_ms
    return nil unless processed_at.present? && created_at.present?

    ((processed_at - created_at) * 1000).round(2)
  end
end
