# frozen_string_literal: true

# Background job for processing bulk categorization operations
# Extends BulkOperations::BaseJob for progress tracking and standardized error handling
class BulkCategorizationJob < BulkOperations::BaseJob
  # Additional retry for categorization-specific errors
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Performance limits
  MAX_EXPENSES_PER_JOB = 100
  BATCH_SIZE = 20

  protected

  def execute_operation
    category_id = @options[:category_id]
    total = @expense_ids.size

    Rails.logger.info "Processing bulk categorization: #{total} expenses"

    processed = 0
    failures = []

    @expense_ids.each_slice(BATCH_SIZE) do |batch_ids|
      result = process_batch(batch_ids, category_id)

      if result.success?
        processed += batch_ids.size
      else
        failures << { batch_ids: batch_ids, error: result.message }
        Rails.logger.error "Batch processing failed: #{result.message}"
        track_failed_batch(batch_ids, result)
      end

      percentage = total > 0 ? ((processed.to_f / total) * 100).round : 100
      track_progress(percentage, "Processed #{processed}/#{total} expenses")
    end

    category = Category.find_by(id: category_id)
    category_name = category&.name || "category"

    {
      success: failures.empty?,
      affected_count: processed,
      message: "Bulk categorization completed: #{processed} expenses categorized as #{category_name}",
      failures: failures
    }
  end

  private

  def process_batch(batch_ids, category_id)
    Services::BulkCategorization::ApplyService.new(
      expense_ids: batch_ids,
      category_id: category_id,
      user_id: @user&.id,
      options: @options.except(:category_id).merge(send_notifications: false)
    ).call
  end

  def track_failed_batch(batch_ids, result)
    Rails.cache.write(
      "failed_bulk_categorization_#{SecureRandom.uuid}",
      {
        expense_ids: batch_ids,
        errors: result.respond_to?(:errors) ? result.errors : [],
        timestamp: Time.current
      },
      expires_in: 7.days
    )
  end
end
