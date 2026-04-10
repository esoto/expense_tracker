# frozen_string_literal: true

# Job for processing bulk status updates in background
class BulkStatusUpdateJob < BulkOperations::BaseJob
  def perform(expense_ids:, status:, user_id: nil, options: {})
    @status = status
    super(expense_ids: expense_ids, user_id: user_id, options: options)
  end

  protected

  def execute_operation
    return { success: true, message: "No expenses to update", affected_count: 0 } if @expense_ids.empty?

    total = @expense_ids.size
    processed = 0
    last_result = nil

    @expense_ids.each_slice(50) do |batch_ids|
      batch_service = Services::BulkOperations::StatusUpdateService.new(
        expense_ids: batch_ids,
        status: @status,
        user: @user,
        options: @options.merge(force_synchronous: true)
      )

      last_result = batch_service.call
      processed += batch_ids.size

      percentage = (processed.to_f / total * 100).round
      track_progress(percentage, "Updated status for #{processed} of #{total} expenses...")
    end

    last_result
  end

  def service_class
    Services::BulkOperations::StatusUpdateService
  end
end
