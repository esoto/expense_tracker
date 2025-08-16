# frozen_string_literal: true

module BulkOperations
  # Base service for all bulk operations on expenses
  # Provides common functionality like batch processing, progress tracking, and error handling
  class BaseService
    include ActiveModel::Model

    attr_accessor :expense_ids, :user, :options
    attr_reader :results

    validates :expense_ids, presence: true
    validate :expense_ids_must_be_array

    BATCH_SIZE = 100
    BACKGROUND_THRESHOLD = 100

    def initialize(expense_ids:, user: nil, options: {})
      @expense_ids = expense_ids
      @user = user
      @options = options
      @results = {
        success: false,
        affected_count: 0,
        failures: [],
        errors: [],
        message: nil
      }
    end

    def call
      return results.merge(success: false, errors: errors.full_messages) unless valid?
      return results.merge(success: false, errors: ["No expenses found"]) if expense_ids.empty?

      # Decide whether to process synchronously or asynchronously
      if should_process_in_background?
        enqueue_background_job
      else
        process_synchronously
      end
    end

    protected

    # Override in subclasses to implement specific bulk operation
    def perform_operation(expenses)
      raise NotImplementedError, "Subclasses must implement perform_operation"
    end

    # Override in subclasses to provide operation-specific success message
    def success_message(count)
      "#{count} expenses processed successfully"
    end

    # Override in subclasses to provide the background job class
    def background_job_class
      raise NotImplementedError, "Subclasses must implement background_job_class"
    end

    private

    def expense_ids_must_be_array
      errors.add(:expense_ids, "must be an array") unless expense_ids.is_a?(Array)
    end

    def should_process_in_background?
      expense_ids.size >= BACKGROUND_THRESHOLD && !options[:force_synchronous]
    end

    def process_synchronously
      expenses = find_authorized_expenses

      if expenses.count != expense_ids.size
        handle_missing_expenses(expenses.count)
        return results
      end

      ActiveRecord::Base.transaction do
        result = perform_operation(expenses)
        process_operation_result(result)
      end

      results
    rescue StandardError => e
      handle_error(e)
      results
    end

    def enqueue_background_job
      job = background_job_class.perform_later(
        expense_ids: expense_ids,
        user_id: user&.id,
        options: options
      )

      results.merge(
        success: true,
        message: "Processing #{expense_ids.size} expenses in background",
        job_id: job.job_id,
        background: true
      )
    rescue StandardError => e
      handle_error(e)
      results
    end

    def find_authorized_expenses
      scope = Expense.where(id: expense_ids)
      
      # Apply user authorization if user is provided
      if user.present?
        email_account_ids = EmailAccount.where(user_id: user.id).pluck(:id)
        scope = scope.where(email_account_id: email_account_ids)
      end

      scope
    end

    def handle_missing_expenses(found_count)
      missing_count = expense_ids.size - found_count
      @results = results.merge(
        success: false,
        message: "#{missing_count} expenses not found or unauthorized",
        errors: ["Some expenses were not found or you don't have permission to modify them"]
      )
    end

    def process_operation_result(result)
      if result.is_a?(Hash)
        @results = results.merge(
          success: true,
          affected_count: result[:success_count] || 0,
          failures: result[:failures] || [],
          message: success_message(result[:success_count] || 0)
        )
      else
        @results = results.merge(
          success: true,
          affected_count: expense_ids.size,
          message: success_message(expense_ids.size)
        )
      end
    end

    def handle_error(error)
      Rails.logger.error "Bulk operation error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      @results = results.merge(
        success: false,
        message: "Error processing operation",
        errors: [error.message]
      )
    end
  end
end