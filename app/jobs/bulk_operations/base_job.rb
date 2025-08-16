# frozen_string_literal: true

module BulkOperations
  # Base job for bulk operations
  # Provides common functionality for progress tracking and error handling
  class BaseJob < ApplicationJob
    queue_as :bulk_operations

    # Retry failed jobs with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(expense_ids:, user_id: nil, options: {})
      @expense_ids = expense_ids
      @user = user_id ? User.find_by(id: user_id) : nil
      @options = options
      @job_id = job_id

      # Track job start
      track_progress(0, "Starting bulk operation...")

      # Execute the operation
      result = execute_operation

      # Track completion
      if result[:success]
        track_progress(100, result[:message])
        broadcast_completion(result)
      else
        track_progress(100, "Operation failed: #{result[:message]}", error: true)
        broadcast_failure(result)
      end

      result
    rescue StandardError => e
      handle_job_error(e)
      raise # Re-raise to trigger retry
    end

    protected

    # Override in subclasses to implement specific operation
    def execute_operation
      raise NotImplementedError, "Subclasses must implement execute_operation"
    end

    # Override in subclasses to get service class
    def service_class
      raise NotImplementedError, "Subclasses must implement service_class"
    end

    private

    def track_progress(percentage, message, error: false)
      # Store progress in cache for polling
      Rails.cache.write(
        progress_cache_key,
        {
          percentage: percentage,
          message: message,
          error: error,
          updated_at: Time.current
        },
        expires_in: 1.hour
      )

      # Broadcast progress via ActionCable
      ActionCable.server.broadcast(
        progress_channel,
        {
          job_id: @job_id,
          percentage: percentage,
          message: message,
          error: error
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to track progress: #{e.message}"
    end

    def broadcast_completion(result)
      ActionCable.server.broadcast(
        completion_channel,
        {
          job_id: @job_id,
          success: true,
          affected_count: result[:affected_count],
          message: result[:message]
        }
      )
    end

    def broadcast_failure(result)
      ActionCable.server.broadcast(
        completion_channel,
        {
          job_id: @job_id,
          success: false,
          errors: result[:errors],
          message: result[:message]
        }
      )
    end

    def handle_job_error(error)
      Rails.logger.error "Bulk operation job error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      track_progress(100, "Operation failed: #{error.message}", error: true)
    end

    def progress_cache_key
      "bulk_operation_progress:#{@job_id}"
    end

    def progress_channel
      @user ? "bulk_operations_#{@user.id}" : "bulk_operations"
    end

    def completion_channel
      @user ? "bulk_operations_completion_#{@user.id}" : "bulk_operations_completion"
    end
  end
end