# frozen_string_literal: true

module Services::BulkOperations
  # Service for bulk status updates of expenses
  # Optimized to use batch updates for performance
  class StatusUpdateService < BaseService
    VALID_STATUSES = %w[pending processed failed duplicate].freeze

    attr_accessor :status

    validates :status, presence: true, inclusion: { in: VALID_STATUSES }

    def initialize(expense_ids:, status:, user: nil, options: {})
      super(expense_ids: expense_ids, user: user, options: options)
      @status = status
    end

    protected

    def perform_operation(expenses)
      # Use update_all for optimal performance
      updated_count = expenses.update_all(
        status: status,
        updated_at: Time.current
      )

      # Broadcast updates if needed
      if options[:broadcast_updates]
        broadcast_status_updates(expenses)
      end

      {
        success_count: updated_count,
        failures: []
      }
    rescue StandardError => e
      # Fall back to individual updates if batch fails
      perform_individual_updates(expenses)
    end

    def success_message(count)
      status_text = {
        "pending" => "pendiente",
        "processed" => "procesado",
        "failed" => "fallido",
        "duplicate" => "duplicado"
      }[status] || status

      "#{count} gastos marcados como #{status_text}"
    end

    def background_job_class
      BulkStatusUpdateJob
    end

    private

    def perform_individual_updates(expenses)
      success_count = 0
      failures = []

      expenses.find_each do |expense|
        if expense.update(status: status)
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

    def broadcast_status_updates(expenses)
      expenses.find_each do |expense|
        ActionCable.server.broadcast(
          "expenses_#{expense.email_account_id}",
          {
            action: "status_updated",
            expense_id: expense.id,
            status: expense.status
          }
        )
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to broadcast status updates: #{e.message}"
    end
  end
end
