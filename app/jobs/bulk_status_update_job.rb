# frozen_string_literal: true

# Job for processing bulk status updates in background
class BulkStatusUpdateJob < BulkOperations::BaseJob
  def perform(expense_ids:, status:, user_id: nil, options: {})
    @status = status
    super(expense_ids: expense_ids, user_id: user_id, options: options)
  end

  protected

  def execute_operation
    service = BulkOperations::StatusUpdateService.new(
      expense_ids: @expense_ids,
      status: @status,
      user: @user,
      options: @options.merge(force_synchronous: true)
    )

    # Track progress during operation
    total = @expense_ids.size
    processed = 0

    # Process in batches with progress updates
    @expense_ids.each_slice(50) do |batch_ids|
      batch_service = BulkOperations::StatusUpdateService.new(
        expense_ids: batch_ids,
        status: @status,
        user: @user,
        options: @options.merge(force_synchronous: true)
      )

      batch_result = batch_service.call
      processed += batch_ids.size

      percentage = (processed.to_f / total * 100).round
      track_progress(percentage, "Updated status for #{processed} of #{total} expenses...")

      # Short sleep to prevent overwhelming the system
      sleep 0.1 if total > 100
    end

    service.call
  end

  def service_class
    BulkOperations::StatusUpdateService
  end
end
