# frozen_string_literal: true

module Services::BulkCategorization
  # Custom error for already categorized expenses
  class AlreadyCategorizedError < StandardError; end


  # Service to apply categorization to multiple expenses at once
  # Handles validation, database updates, pattern learning, and audit logging
  class ApplyService
    include ActiveModel::Model

    attr_accessor :expense_ids, :category_id, :user_id, :options

    validates :expense_ids, presence: true
    validates :category_id, presence: true

    def initialize(expense_ids:, category_id:, user_id: nil, options: {})
      @expense_ids = Array(expense_ids)
      @category_id = category_id
      @user_id = user_id
      @options = default_options.merge(options)
      @results = []
      @processing_errors = []
    end

    def call
      return failure_result(errors.full_messages.join(", ")) unless valid?

      ActiveRecord::Base.transaction do
        load_resources
        validate_expenses!
        create_bulk_operation
        apply_categorization
        learn_from_categorization if options[:learn_patterns]
        notify_completion if options[:send_notifications]

        success_result
      end
    rescue AlreadyCategorizedError => e
      # Don't track this as an error since it's a validation failure
      failure_result(e.message)
    rescue ActiveRecord::RecordInvalid => e
      ErrorTrackingService.track_bulk_operation_error("categorization", e, {
        expense_count: expense_ids.count,
        category_id: category_id,
        user_id: user_id
      })
      failure_result(e.message)
    rescue StandardError => e
      ErrorTrackingService.track_bulk_operation_error("categorization", e, {
        expense_count: expense_ids.count,
        category_id: category_id,
        user_id: user_id,
        options: options
      })
      Rails.logger.error "BulkCategorization::ApplyService error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      failure_result("An error occurred while categorizing expenses")
    end

    private

    def default_options
      {
        learn_patterns: true,
        send_notifications: true,
        track_operation: true,
        update_confidence: true,
        create_patterns: true
      }
    end

    def load_resources
      # Use pessimistic locking to prevent concurrent modifications
      @expenses = Expense.where(id: expense_ids)
                        .includes(:category, :email_account)
                        .lock("FOR UPDATE") # Pessimistic locking
      @category = Category.find(category_id)

      if @expenses.count != expense_ids.count
        missing_ids = expense_ids - @expenses.pluck(:id)
        raise ActiveRecord::RecordNotFound, "Expenses not found: #{missing_ids.join(', ')}"
      end
    end

    def validate_expenses!
      already_categorized = @expenses.select { |e| e.category.present? }

      if already_categorized.any? && !options[:allow_recategorization]
        expense_list = already_categorized.map(&:display_description).join(", ")
        # Raise a custom error with the categorization message
        raise AlreadyCategorizedError, "Some expenses are already categorized: #{expense_list}"
      end
    end

    def create_bulk_operation
      return unless options[:track_operation]

      @bulk_operation = BulkOperation.create!(
        operation_type: "categorization",
        user_id: user_id,
        target_category_id: category_id,
        expense_count: @expenses.count,
        total_amount: @expenses.sum(:amount),
        metadata: {
          expense_ids: expense_ids,
          previous_categories: @expenses.pluck(:id, :category_id).to_h,
          applied_at: Time.current
        }
      )
    end

    def apply_categorization
      @expenses.each do |expense|
        result = categorize_expense(expense)
        @results << result

        if result[:success]
          track_success(expense, result)
        else
          @processing_errors << result[:error]
        end
      end

      if @processing_errors.any?
        Rails.logger.warn "BulkCategorization: #{@processing_errors.count} errors during categorization"
      end
    end

    def categorize_expense(expense)
      previous_category = expense.category

      expense.update!(
        category: @category,
        auto_categorized: false, # Manual bulk categorization
        categorization_confidence: calculate_confidence(expense),
        categorization_method: "bulk_manual",
        categorized_at: Time.current,
        categorized_by: user_id
      )

      {
        success: true,
        expense_id: expense.id,
        previous_category_id: previous_category&.id,
        new_category_id: @category.id
      }
    rescue StandardError => e
      {
        success: false,
        expense_id: expense.id,
        error: e.message
      }
    end

    def calculate_confidence(expense)
      return 1.0 unless options[:update_confidence]

      # Use categorization engine to calculate confidence
      engine = Services::Categorization::EngineFactory.default
      result = engine.categorize(expense, auto_update: false)

      if result.successful? && result.category == @category
        result.confidence
      else
        0.9 # High confidence for manual categorization
      end
    end

    def learn_from_categorization
      return unless options[:learn_patterns]

      learner = Categorization::PatternLearner.new

      @expenses.each do |expense|
        # Learn from this manual categorization
        learner.learn_from_correction(expense, @category, nil)

        # Create new patterns if applicable
        create_pattern_from_expense(expense) if options[:create_patterns]
      end
    end

    def create_pattern_from_expense(expense)
      return unless expense.merchant_name?

      # Check if pattern already exists
      existing = CategorizationPattern.find_by(
        category: @category,
        pattern_type: "merchant",
        pattern_value: expense.merchant_normalized || expense.merchant_name
      )

      return if existing

      # Create new pattern from this categorization
      CategorizationPattern.create!(
        category: @category,
        pattern_type: "merchant",
        pattern_value: expense.merchant_normalized || expense.merchant_name,
        confidence_weight: 0.8,
        user_created: true,
        metadata: {
          source: "bulk_categorization",
          created_by: user_id,
          expense_count: @expenses.count { |e| e.merchant_normalized == expense.merchant_normalized }
        }
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "Failed to create pattern: #{e.message}"
    end

    def track_success(expense, result)
      return unless @bulk_operation

      BulkOperationItem.create!(
        bulk_operation: @bulk_operation,
        expense: expense,
        previous_category_id: result[:previous_category_id],
        new_category_id: result[:new_category_id],
        status: "completed"
      )
    end

    def notify_completion
      # Broadcast Turbo Stream update
      Turbo::StreamsChannel.broadcast_replace_to(
        "bulk_categorization_updates",
        target: "categorization_progress",
        partial: "bulk_categorizations/progress",
        locals: {
          completed: @results.count { |r| r[:success] },
          total: @expenses.count,
          errors: @processing_errors.count
        }
      )
    end

    def success_result
      completed_count = @results.count { |r| r[:success] }

      OpenStruct.new(
        success?: true,
        message: "Successfully categorized #{completed_count} expense#{'s' if completed_count != 1}",
        bulk_operation: @bulk_operation,
        results: @results,
        errors: @processing_errors,
        expense_count: completed_count,
        updated_group: nil, # Will be set by controller if needed
        remaining_groups: [] # Will be set by controller if needed
      )
    end

    def failure_result(message)
      OpenStruct.new(
        success?: false,
        message: message,
        bulk_operation: nil,
        results: @results,
        errors: @processing_errors + [ message ],
        expense_count: 0
      )
    end
  end
end
