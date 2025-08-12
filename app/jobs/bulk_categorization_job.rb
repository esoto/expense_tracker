# frozen_string_literal: true

# Background job for processing bulk categorization operations
# Uses Solid Queue for reliable background processing
class BulkCategorizationJob < ApplicationJob
  queue_as :bulk_operations

  # Retry configuration
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::RecordNotFound, wait: 2.seconds, attempts: 2

  # Performance limits
  MAX_EXPENSES_PER_JOB = 100
  BATCH_SIZE = 20

  def perform(expense_ids, category_id, user_id, options = {})
    Rails.logger.info "Processing bulk categorization: #{expense_ids.count} expenses"

    # Process in batches to avoid memory issues
    expense_ids.each_slice(BATCH_SIZE) do |batch_ids|
      process_batch(batch_ids, category_id, user_id, options)
    end

    # Send completion notification
    notify_completion(expense_ids.count, category_id, user_id)
  rescue StandardError => e
    handle_job_error(e, expense_ids, category_id, user_id)
    raise # Re-raise for job retry mechanism
  end

  private

  def process_batch(batch_ids, category_id, user_id, options)
    result = BulkCategorization::ApplyService.new(
      expense_ids: batch_ids,
      category_id: category_id,
      user_id: user_id,
      options: options.merge(send_notifications: false) # Avoid duplicate notifications
    ).call

    unless result.success?
      Rails.logger.error "Batch processing failed: #{result.message}"
      track_failed_batch(batch_ids, result)
    end
  end

  def notify_completion(expense_count, category_id, user_id)
    category = Category.find(category_id)

    # Broadcast completion via Turbo Streams
    Turbo::StreamsChannel.broadcast_append_to(
      "user_#{user_id}_notifications",
      target: "notifications",
      partial: "shared/notification",
      locals: {
        message: "Bulk categorization completed: #{expense_count} expenses categorized as #{category.name}",
        type: :success,
        timestamp: Time.current
      }
    )

    # Log completion
    Rails.logger.info(
      {
        event: "bulk_categorization_completed",
        user_id: user_id,
        expense_count: expense_count,
        category_id: category_id,
        timestamp: Time.current.iso8601
      }.to_json
    )
  end

  def handle_job_error(error, expense_ids, category_id, user_id)
    Rails.logger.error(
      {
        event: "bulk_categorization_failed",
        error: error.message,
        error_class: error.class.name,
        user_id: user_id,
        expense_count: expense_ids.count,
        category_id: category_id,
        backtrace: error.backtrace&.first(5),
        timestamp: Time.current.iso8601
      }.to_json
    )

    # Notify user of failure
    Turbo::StreamsChannel.broadcast_append_to(
      "user_#{user_id}_notifications",
      target: "notifications",
      partial: "shared/notification",
      locals: {
        message: "Bulk categorization failed. Please try again or contact support if the problem persists.",
        type: :error,
        timestamp: Time.current
      }
    )
  end

  def track_failed_batch(batch_ids, result)
    # Store failed batch for retry or manual intervention
    Rails.cache.write(
      "failed_bulk_categorization_#{SecureRandom.uuid}",
      {
        expense_ids: batch_ids,
        errors: result.errors,
        timestamp: Time.current
      },
      expires_in: 7.days
    )
  end
end
