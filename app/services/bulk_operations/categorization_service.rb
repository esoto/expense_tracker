# frozen_string_literal: true

module Services::BulkOperations
  # Service for bulk categorization of expenses
  # Optimized to use batch updates for performance
  class CategorizationService < BaseService
    attr_accessor :category_id

    validates :category_id, presence: true
    validate :category_must_exist

    def initialize(expense_ids:, category_id:, user: nil, options: {})
      super(expense_ids: expense_ids, user: user, options: options)
      @category_id = category_id
    end

    protected

    def perform_operation(expenses)
      # Use update_all for optimal performance
      # This avoids N+1 queries and callbacks
      updated_count = expenses.update_all(
        category_id: category_id,
        updated_at: Time.current
      )

      # Track ML corrections if applicable
      if options[:track_ml_corrections]
        track_ml_corrections(expenses)
      end

      # Broadcast updates if needed
      if options[:broadcast_updates]
        broadcast_categorization_updates(expenses)
      end

      {
        success_count: updated_count,
        failures: []
      }
    rescue StandardError => e
      # If batch update fails, fall back to individual updates
      # This helps identify which specific expenses have issues
      perform_individual_updates(expenses)
    end

    def success_message(count)
      category = Category.find_by(id: category_id)
      category_name = category&.name || "category"
      "#{count} gastos categorizados como #{category_name} exitosamente"
    end

    def background_job_class
      BulkCategorizationJob
    end

    private

    def category_must_exist
      return if category_id.blank?
      errors.add(:category_id, "does not exist") unless Category.exists?(category_id)
    end

    def perform_individual_updates(expenses)
      success_count = 0
      failures = []

      expenses.find_each do |expense|
        if expense.update(category_id: category_id)
          success_count += 1
        else
          failures << {
            id: expense.id,
            error: expense.errors.full_messages.join(", ")
          }
        end
      end

      {
        success_count: success_count,
        failures: failures
      }
    end

    def track_ml_corrections(expenses)
      # Update ML correction tracking for categorized expenses
      expenses.where.not(ml_suggested_category_id: nil)
              .where.not(ml_suggested_category_id: category_id)
              .update_all(
                ml_correction_count: Arel.sql("ml_correction_count + 1"),
                ml_last_corrected_at: Time.current
              )
    end

    def broadcast_categorization_updates(expenses)
      # Broadcast updates via ActionCable for real-time UI updates
      expenses.includes(:category).find_each do |expense|
        ActionCable.server.broadcast(
          "expenses_#{expense.email_account_id}",
          {
            action: "categorized",
            expense_id: expense.id,
            category_id: expense.category_id,
            category_name: expense.category&.name
          }
        )
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to broadcast categorization updates: #{e.message}"
    end
  end
end
