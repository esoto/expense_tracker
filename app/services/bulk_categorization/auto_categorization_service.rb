# frozen_string_literal: true

module BulkCategorization
  # Service to automatically categorize expenses with high confidence
  class AutoCategorizationService
    attr_reader :confidence_threshold, :options

    def initialize(confidence_threshold: 0.8, options: {})
      @confidence_threshold = confidence_threshold
      @options = default_options.merge(options)
      # Use dependency injection - engine must be provided
      @categorization_engine = options[:engine] || Categorization::Engine.create
      @results = []
      @errors = []
    end

    def categorize_all
      Rails.logger.info "Auto-categorizing expenses"
      ActiveRecord::Base.transaction do
        expenses = load_uncategorized_expenses

        return no_expenses_result if expenses.empty?

        create_bulk_operation(expenses)
        process_expenses(expenses)
        finalize_operation

        success_result(expenses)
      end
    rescue StandardError => e
      Rails.logger.error "AutoCategorizationService error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      failure_result(e.message)
    end

    private

    def default_options
      {
        batch_size: 100,
        max_expenses: 500,
        learn_patterns: true,
        track_operation: true,
        dry_run: false
      }
    end

    def load_uncategorized_expenses
      Expense
        .uncategorized
        .includes(:email_account)
        .order(amount: :desc) # Process higher amounts first
        .limit(options[:max_expenses])
    end

    def create_bulk_operation(expenses)
      return unless options[:track_operation] && !options[:dry_run]

      @bulk_operation = BulkOperation.create!(
        operation_type: :auto_categorization,
        user_id: "system",
        expense_count: expenses.count,
        total_amount: expenses.sum(:amount),
        status: :in_progress,
        metadata: {
          confidence_threshold: confidence_threshold,
          started_at: Time.current
        }
      )
    end

    def process_expenses(expenses)
      expenses.find_in_batches(batch_size: options[:batch_size]) do |batch|
        # Use batch categorization for efficiency
        results = @categorization_engine.batch_categorize(batch, auto_update: false)

        batch.zip(results).each do |expense, result|
          process_single_expense(expense, result)
        end
      end
    end

    def process_single_expense(expense, categorization_result)
      if should_categorize?(categorization_result)
        if options[:dry_run]
          record_dry_run_result(expense, categorization_result)
        else
          apply_categorization(expense, categorization_result)
        end
      else
        record_skipped(expense, categorization_result)
      end
    rescue StandardError => e
      record_error(expense, e)
    end

    def should_categorize?(result)
      result.successful? && result.confidence >= confidence_threshold
    end

    def apply_categorization(expense, result)
      expense.update!(
        category: result.category,
        auto_categorized: true,
        categorization_confidence: result.confidence,
        categorization_method: "auto_bulk_#{result.method}",
        categorized_at: Time.current,
        categorized_by: "system"
      )

      # Track in bulk operation
      if @bulk_operation
        BulkOperationItem.create!(
          bulk_operation: @bulk_operation,
          expense: expense,
          new_category_id: result.category.id,
          status: :completed,
          processed_at: Time.current
        )
      end

      # Learn from successful categorization
      learn_from_categorization(expense, result) if options[:learn_patterns]

      @results << {
        expense_id: expense.id,
        category_id: result.category.id,
        confidence: result.confidence,
        status: :categorized
      }
    end

    def record_dry_run_result(expense, result)
      @results << {
        expense_id: expense.id,
        category_id: result.category.id,
        confidence: result.confidence,
        status: :would_categorize,
        dry_run: true
      }
    end

    def record_skipped(expense, result)
      reason = if result.failed?
        "categorization_failed"
      elsif result.confidence < confidence_threshold
        "low_confidence"
      else
        "unknown"
      end

      @results << {
        expense_id: expense.id,
        confidence: result.confidence,
        status: :skipped,
        reason: reason
      }
    end

    def record_error(expense, error)
      @errors << {
        expense_id: expense.id,
        error: error.message
      }

      Rails.logger.error "Failed to auto-categorize expense #{expense.id}: #{error.message}"
    end

    def learn_from_categorization(expense, result)
      return unless result.successful? && result.confidence >= 0.9

      # Only learn from very high confidence categorizations
      Categorization::PatternLearner.new.learn_from_correction(
        expense,
        result.category,
        nil,
        confidence_boost: result.confidence
      )
    rescue StandardError => e
      Rails.logger.warn "Failed to learn from auto-categorization: #{e.message}"
    end

    def finalize_operation
      return unless @bulk_operation && !options[:dry_run]

      categorized_count = @results.count { |r| r[:status] == :categorized }

      @bulk_operation.update!(
        status: categorized_count > 0 ? :completed : :failed,
        completed_at: Time.current,
        metadata: @bulk_operation.metadata.merge(
          categorized_count: categorized_count,
          skipped_count: @results.count { |r| r[:status] == :skipped },
          error_count: @errors.count,
          completed_at: Time.current
        )
      )
    end

    def no_expenses_result
      OpenStruct.new(
        success?: true,
        message: "No uncategorized expenses found",
        categorized_count: 0,
        remaining_expenses: [],
        remaining_groups: []
      )
    end

    def success_result(all_expenses)
      categorized_count = @results.count { |r| r[:status] == :categorized }
      remaining_ids = @results
        .select { |r| r[:status] == :skipped }
        .map { |r| r[:expense_id] }

      remaining_expenses = all_expenses.select { |e| remaining_ids.include?(e.id) }

      message = if options[:dry_run]
        "Dry run: Would categorize #{categorized_count} expenses"
      else
        "Successfully auto-categorized #{categorized_count} expense#{'s' if categorized_count != 1}"
      end

      OpenStruct.new(
        success?: true,
        message: message,
        categorized_count: categorized_count,
        skipped_count: @results.count { |r| r[:status] == :skipped },
        error_count: @errors.count,
        results: @results,
        errors: @errors,
        remaining_expenses: remaining_expenses,
        remaining_groups: [], # Will be populated by controller
        bulk_operation: @bulk_operation
      )
    end

    def failure_result(message)
      OpenStruct.new(
        success?: false,
        message: "Auto-categorization failed: #{message}",
        categorized_count: 0,
        results: @results,
        errors: @errors,
        remaining_expenses: [],
        remaining_groups: []
      )
    end
  end
end
