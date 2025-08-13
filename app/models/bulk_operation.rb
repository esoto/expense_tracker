# frozen_string_literal: true

# Model to track bulk categorization operations for audit and undo functionality
class BulkOperation < ApplicationRecord
  # Associations
  has_many :bulk_operation_items, dependent: :destroy
  has_many :expenses, through: :bulk_operation_items
  belongs_to :target_category, class_name: "Category", optional: true

  # Enums
  enum :operation_type, {
    categorization: 0,
    recategorization: 1,
    auto_categorization: 2,
    pattern_application: 3,
    undo: 4
  }

  enum :status, {
    pending: 0,
    in_progress: 1,
    completed: 2,
    failed: 3,
    partially_completed: 4,
    undone: 5
  }, default: :pending

  # Validations
  validates :operation_type, presence: true
  validates :expense_count, presence: true, numericality: { greater_than: 0 }
  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: [ :completed, :partially_completed ]) }
  scope :undoable, -> { where(status: :completed, undone_at: nil).where("created_at > ?", 24.hours.ago) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :today, -> { where(created_at: Date.current.all_day) }
  scope :this_week, -> { where(created_at: Date.current.all_week) }
  scope :this_month, -> { where(created_at: Date.current.all_month) }

  # Callbacks
  before_validation :set_defaults

  # Instance methods
  def undoable?
    completed? && undone_at.nil? && created_at > 24.hours.ago
  end

  def undo!
    return false unless undoable?

    transaction do
      # Revert each expense to its previous state
      bulk_operation_items.each do |item|
        item.expense.update!(
          category_id: item.previous_category_id,
          auto_categorized: false,
          categorization_confidence: nil,
          categorization_method: nil
        )
        item.update!(status: "undone")
      end

      # Mark operation as undone
      update!(
        status: :undone,
        undone_at: Time.current,
        metadata: metadata.merge("undone_by" => Current.user_id || "system")
      )

      # Create undo operation record
      BulkOperation.create!(
        operation_type: :undo,
        user_id: user_id,
        expense_count: expense_count,
        total_amount: total_amount,
        metadata: {
          original_operation_id: id,
          undone_at: Time.current
        }
      )
    end

    true
  rescue StandardError => e
    Rails.logger.error "Failed to undo bulk operation #{id}: #{e.message}"
    false
  end

  def success_rate
    return 0.0 if expense_count.zero?

    successful_items = bulk_operation_items.where(status: "completed").count
    (successful_items.to_f / expense_count * 100).round(2)
  end

  def duration_seconds
    return nil unless completed_at.present?

    (completed_at - created_at).to_i
  end

  def average_confidence
    items_with_confidence = bulk_operation_items
      .joins(:expense)
      .where.not(expenses: { categorization_confidence: nil })
      .pluck("expenses.categorization_confidence")

    return nil if items_with_confidence.empty?

    (items_with_confidence.sum.to_f / items_with_confidence.count).round(3)
  end

  def affected_categories
    Category.joins(:expenses)
      .where(expenses: { id: expense_ids })
      .distinct
  end

  def expense_ids
    metadata["expense_ids"] || bulk_operation_items.pluck(:expense_id)
  end

  def summary
    {
      operation: operation_type.humanize,
      status: status.humanize,
      expenses_affected: expense_count,
      total_amount: total_amount,
      target_category: target_category&.name,
      success_rate: success_rate,
      duration: duration_seconds,
      average_confidence: average_confidence,
      created_at: created_at,
      undoable: undoable?
    }
  end

  private

  def set_defaults
    self.metadata ||= {}
    self.expense_count ||= 0
    self.total_amount ||= 0.0
  end
end
