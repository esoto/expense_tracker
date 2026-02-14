# frozen_string_literal: true

module Services::BulkOperations
  # Service for bulk deletion of expenses
  # Handles soft deletes and maintains audit trail if configured
  class DeletionService < BaseService
    protected

    def perform_operation(expenses)
      # Store expenses before deletion for undo
      expenses_to_delete = expenses.to_a
      expense_ids_to_delete = expenses_to_delete.map(&:id)

      # Perform soft deletion with undo support
      deleted_count = 0
      failures = []

      ActiveRecord::Base.transaction do
        expenses_to_delete.each do |expense|
          begin
            if expense.respond_to?(:soft_delete!)
              expense.soft_delete!(deleted_by: user&.email)
            else
              expense.destroy!
            end
            deleted_count += 1
          rescue StandardError => e
            failures << {
              id: expense.id,
              error: e.message
            }
          end
        end

        # Create undo history record if we deleted anything
        if deleted_count > 0 && defined?(UndoHistory)
          @undo_record = UndoHistory.create_for_bulk_deletion(
            expenses_to_delete.select { |e| expense_ids_to_delete.include?(e.id) },
            user: user
          )
        end
      end

      # Broadcast deletions if needed
      if options[:broadcast_updates]
        broadcast_deletions(expense_ids_to_delete)
      end

      result = {
        success_count: deleted_count,
        failures: failures
      }

      # Add undo information if available
      if @undo_record
        result[:undo_id] = @undo_record.id
        result[:undo_time_remaining] = @undo_record.time_remaining
      end

      result
    end

    def success_message(count)
      "#{count} gastos eliminados exitosamente"
    end

    def background_job_class
      BulkDeletionJob
    end

    private

    def broadcast_deletions(expense_ids)
      expense_ids.each do |expense_id|
        ActionCable.server.broadcast(
          "expenses",
          {
            action: "deleted",
            expense_id: expense_id
          }
        )
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to broadcast deletion updates: #{e.message}"
    end
  end
end
