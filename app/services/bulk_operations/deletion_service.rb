# frozen_string_literal: true

module BulkOperations
  # Service for bulk deletion of expenses
  # Handles soft deletes and maintains audit trail if configured
  class DeletionService < BaseService
    protected

    def perform_operation(expenses)
      # Store IDs before deletion for broadcasting
      expense_ids_to_delete = expenses.pluck(:id)

      # Use destroy_all to trigger callbacks if needed
      # Use delete_all for better performance if callbacks aren't needed
      if options[:skip_callbacks]
        deleted_count = expenses.delete_all
      else
        deleted_count = 0
        failures = []

        expenses.find_each do |expense|
          begin
            expense.destroy!
            deleted_count += 1
          rescue StandardError => e
            failures << {
              id: expense.id,
              error: e.message
            }
          end
        end

        return { success_count: deleted_count, failures: failures }
      end

      # Broadcast deletions if needed
      if options[:broadcast_updates]
        broadcast_deletions(expense_ids_to_delete)
      end

      {
        success_count: deleted_count,
        failures: []
      }
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
