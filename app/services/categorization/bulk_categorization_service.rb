# frozen_string_literal: true

require_relative "expense_collection_adapter"

module Services
  module Categorization
    # BulkCategorizationService consolidates all bulk categorization operations
    # including preview, apply, undo, export, grouping, and suggestions.
    # This replaces 8 separate service files for better cohesion and maintainability.
    class BulkCategorizationService
      include ActiveModel::Model

      attr_accessor :expenses, :category_id, :user, :options
      attr_reader :expense_adapter

      def initialize(expenses: [], category_id: nil, user: nil, options: {})
        @expenses = expenses
        @expense_adapter = ExpenseCollectionAdapter.new(expenses)
        @category_id = category_id
        @user = user
        @options = options
      end

      # Preview categorization changes before applying
      def preview
        return { expenses: [], summary: empty_summary } if expense_adapter.empty?

        affected_expenses = filter_changeable_expenses

        {
          expenses: affected_expenses.map { |expense| preview_change(expense) },
          summary: {
            total_count: affected_expenses.count,
            total_amount: affected_expenses.sum(&:amount),
            by_current_category: group_by_current_category(affected_expenses),
            estimated_time_saved: estimate_time_saved(affected_expenses.count)
          }
        }
      end

      # Apply categorization to selected expenses
      def apply!
        return { success: false, errors: [ "No expenses selected" ] } if expense_adapter.empty?
        return { success: false, errors: [ "Category not found" ] } unless valid_category?

        ApplicationRecord.transaction do
          results = expense_adapter.map do |expense|
            apply_to_expense(expense)
          end

          success_count = results.count { |r| r[:success] }

          # Store for undo functionality
          if success_count > 0
            store_bulk_operation(results.select { |r| r[:success] })
          end

          {
            success: true,
            updated_count: success_count,
            failed_count: results.count { |r| !r[:success] },
            errors: results.reject { |r| r[:success] }.map { |r| r[:error] },
            undo_operation_id: @bulk_operation&.id
          }
        end
      rescue StandardError => e
        { success: false, errors: [ e.message ] }
      end

      # Undo a bulk categorization
      def undo!(operation_id)
        operation = BulkOperation.find_by(id: operation_id, operation_type: "categorization")

        return { success: false, errors: [ "Operation not found" ] } unless operation
        return { success: false, errors: [ "Operation already undone" ] } if operation.undone_at.present?

        ApplicationRecord.transaction do
          restored_count = 0

          operation.bulk_operation_items.each do |item|
            expense = item.expense
            expense.update!(category_id: item.previous_category_id)
            restored_count += 1
          end

          operation.update!(undone_at: Time.current, status: :undone)

          { success: true, restored_count: restored_count }
        end
      rescue StandardError => e
        { success: false, errors: [ e.message ] }
      end

      # Export categorization results
      def export(format: :csv)
        case format
        when :csv
          export_to_csv
        when :json
          export_to_json
        when :xlsx
          export_to_xlsx
        else
          raise ArgumentError, "Unsupported export format: #{format}"
        end
      end

      # Group expenses by various criteria
      def group_expenses(by: :merchant)
        case by
        when :merchant
          group_by_merchant
        when :date
          group_by_date
        when :amount_range
          group_by_amount_range
        when :category
          group_by_category
        when :similarity
          group_by_similarity
        else
          raise ArgumentError, "Unsupported grouping: #{by}"
        end
      end

      # Suggest categories based on patterns
      def suggest_categories
        suggestions = {}

        expense_adapter.each do |expense|
          next if expense.category_id.present?

          # Use pattern matching for suggestions
          suggested_category = find_best_category_match(expense)

          if suggested_category && suggested_category[:category].present?
            # Use object_id for non-persisted expenses to avoid nil keys
            key = expense.id || expense.object_id
            suggestions[key] = {
              expense: expense,
              suggested_category: suggested_category[:category],
              confidence: suggested_category[:confidence],
              reason: suggested_category[:reason]
            }
          end
        end

        suggestions
      end

      # Auto-categorize based on rules and patterns
      def auto_categorize!
        return { success: false, errors: [ "No expenses to categorize" ] } if expense_adapter.empty?

        categorized_count = 0
        failed_count = 0

        ApplicationRecord.transaction do
          expense_adapter.each do |expense|
            next if expense.category_id.present? && !options[:override_existing]

            result = auto_categorize_expense(expense)

            if result[:success]
              categorized_count += 1
            else
              failed_count += 1
            end
          end

          {
            success: true,
            categorized_count: categorized_count,
            failed_count: failed_count,
            total_processed: expense_adapter.count
          }
        end
      rescue StandardError => e
        { success: false, errors: [ e.message ] }
      end

      # Batch process expenses in chunks
      def batch_process(batch_size: 100)
        results = []

        expense_adapter.in_batches(batch_size: batch_size) do |batch|
          batch_result = process_batch(batch)
          results << batch_result

          yield batch_result if block_given?
        end

        aggregate_results(results)
      end

      # Simple categorize all method for bulk operations controller
      def categorize_all
        return { success: false, errors: [ "No expenses selected" ] } if expense_adapter.empty?
        return { success: false, errors: [ "No category provided" ] } unless @category_id || @category

        category = @category || Category.find_by(id: @category_id)
        return { success: false, errors: [ "Category not found" ] } unless category

        success_count = 0
        failures = []

        expense_adapter.each do |expense|
          if expense.update(category_id: category.id)
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

      private

      def filter_changeable_expenses
        expense_adapter.select do |expense|
          expense.category_id != category_id && !expense.locked?
        end.to_a
      end

      def preview_change(expense)
        {
          id: expense.id,
          description: expense.description,
          amount: expense.amount,
          date: expense.transaction_date,
          current_category: expense.category&.name,
          new_category: Category.find(category_id)&.name,
          will_change: expense.category_id != category_id
        }
      end

      def group_by_current_category(expenses)
        expense_adapter.group_by { |e| e.category&.name || "Uncategorized" }
                .transform_values { |group| {
                  count: group.count,
                  amount: group.sum(&:amount)
                }}
      end

      def estimate_time_saved(count)
        # Assume 3 seconds saved per manual categorization
        seconds = count * 3

        if seconds < 60
          "#{seconds} seconds"
        elsif seconds < 3600
          "#{(seconds / 60.0).round(1)} minutes"
        else
          "#{(seconds / 3600.0).round(1)} hours"
        end
      end

      def valid_category?
        Category.exists?(category_id)
      end

      def apply_to_expense(expense)
        if expense.update(category_id: category_id)
          {
            success: true,
            expense_id: expense.id,
            previous_category_id: expense.category_id_was
          }
        else
          {
            success: false,
            expense_id: expense.id,
            error: expense.errors.full_messages.join(", ")
          }
        end
      end

      def store_bulk_operation(results)
        @bulk_operation = BulkOperation.create!(
          operation_type: "categorization",
          user_id: user&.id,
          target_category_id: category_id,
          expense_count: results.count,
          total_amount: results.sum { |r| Expense.find(r[:expense_id]).amount },
          status: :completed,
          completed_at: Time.current,
          metadata: { results: results }
        )

        # Create bulk operation items for each affected expense
        results.each do |result|
          @bulk_operation.bulk_operation_items.create!(
            expense_id: result[:expense_id],
            previous_category_id: result[:previous_category_id],
            new_category_id: category_id,
            status: :completed,
            processed_at: Time.current
          )
        end
      end

      def export_to_csv
        CSV.generate(headers: true) do |csv|
          csv << [ "ID", "Date", "Description", "Amount", "Current Category", "Merchant" ]

          expense_adapter.each do |expense|
            csv << [
              expense.id,
              expense.transaction_date,
              expense.description,
              expense.amount,
              expense.category&.name,
              expense.merchant_name
            ]
          end
        end
      end

      def export_to_json
        expense_adapter.map do |expense|
          {
            id: expense.id,
            date: expense.transaction_date,
            description: expense.description,
            amount: expense.amount,
            category: expense.category&.name,
            merchant: expense.merchant_name
          }
        end.to_json
      end

      def export_to_xlsx
        # Would require additional gem like 'caxlsx'
        raise NotImplementedError, "Excel export requires additional dependencies"
      end

      def group_by_merchant
        expense_adapter.group_by(&:merchant_name)
                .transform_values { |group| {
                  expenses: group,
                  count: group.count,
                  total_amount: group.sum(&:amount),
                  date_range: [ group.min_by(&:transaction_date).transaction_date, group.max_by(&:transaction_date).transaction_date ]
                }}
                .sort_by { |_, v| -v[:count] }
                .to_h
      end

      def group_by_date
        expense_adapter.group_by { |e| e.transaction_date.beginning_of_month }
                .transform_values { |group| {
                  expenses: group,
                  count: group.count,
                  total_amount: group.sum(&:amount)
                }}
                .sort_by { |date, _| date }
                .to_h
      end

      def group_by_amount_range
        ranges = [
          { min: 0, max: 10, label: "$0-10" },
          { min: 10, max: 50, label: "$10-50" },
          { min: 50, max: 100, label: "$50-100" },
          { min: 100, max: 500, label: "$100-500" },
          { min: 500, max: Float::INFINITY, label: "$500+" }
        ]

        result = {}

        ranges.each do |range|
          matching = expense_adapter.select { |e| e.amount >= range[:min] && e.amount < range[:max] }.to_a
          next if matching.empty?

          result[range[:label]] = {
            expenses: matching,
            count: matching.count,
            total_amount: matching.sum(&:amount)
          }
        end

        result
      end

      def group_by_category
        expense_adapter.group_by { |e| e.category&.name || "Uncategorized" }
                .transform_values { |group| {
                  expenses: group,
                  count: group.count,
                  total_amount: group.sum(&:amount)
                }}
                .sort_by { |_, v| -v[:total_amount] }
                .to_h
      end

      def group_by_similarity
        groups = []
        processed = Set.new

        expense_adapter.each do |expense|
          next if processed.include?(expense.id)

          similar = find_similar_expenses(expense)
          if similar.any?
            groups << {
              anchor: expense,
              similar: similar,
              count: similar.count + 1,
              total_amount: similar.sum(&:amount) + expense.amount
            }
            processed.merge(similar.map(&:id))
            processed.add(expense.id)
          end
        end

        groups.sort_by { |g| -g[:count] }
      end

      def find_similar_expenses(expense)
        expense_adapter.select do |e|
          e.id != expense.id &&
          similar_description?(expense.description, e.description) &&
          (expense.amount - e.amount).abs < expense.amount * 0.1
        end.to_a
      end

      def similar_description?(desc1, desc2)
        return false if desc1.nil? || desc2.nil?

        # Simple similarity check - could be enhanced with fuzzy matching
        words1 = desc1.downcase.split(/\W+/)
        words2 = desc2.downcase.split(/\W+/)

        common = words1 & words2
        return false if common.empty?

        similarity = common.length.to_f / [ words1.length, words2.length ].min
        similarity > 0.6
      end

      def find_best_category_match(expense)
        # Skip if expense doesn't have required attributes
        return nil unless expense.respond_to?(:description) && expense.respond_to?(:merchant_name)

        # Try to find matching patterns for this expense
        patterns = CategorizationPattern.active.with_category rescue []

        matching_pattern = patterns.find do |pattern|
          case pattern.pattern_type
          when "merchant"
            expense.merchant_name&.downcase&.include?(pattern.pattern_value.downcase)
          when "keyword", "description"
            expense.description&.downcase&.include?(pattern.pattern_value.downcase)
          else
            false
          end
        end

        if matching_pattern
          {
            category: matching_pattern.category,
            confidence: matching_pattern.confidence_weight || 0.8,
            reason: "Pattern match: #{matching_pattern.pattern_value}"
          }
        elsif expense.respond_to?(:persisted?) && expense.persisted? && expense.description?
          # Fallback to finding similar categorized expenses - only for persisted records
          first_word = expense.description.split.first
          return nil unless first_word.present?

          # Only search for similar expenses if this expense is persisted
          similar = Expense.where.not(category_id: nil)
                           .where("description ILIKE ?", "%#{first_word}%")
                           .group(:category_id)
                           .count
                           .max_by { |_, count| count }

          if similar && similar[1] > 0  # Only if we found actual matches
            category = Category.find_by(id: similar[0])
            if category
              {
                category: category,
                confidence: 0.6,
                reason: "Similar expenses in #{category.name}"
              }
            end
          end
        end
      end

      def auto_categorize_expense(expense)
        suggestion = find_best_category_match(expense)

        if suggestion && suggestion[:confidence] >= (options[:min_confidence] || 0.7)
          expense.update(category_id: suggestion[:category].id)
          { success: true, expense_id: expense.id, category_id: suggestion[:category].id }
        else
          { success: false, expense_id: expense.id, reason: "No confident match found" }
        end
      end

      def process_batch(batch)
        {
          processed: batch.count,
          success: batch.count { |e| e.category_id.present? },
          failed: batch.count { |e| e.category_id.nil? },
          timestamp: Time.current
        }
      end

      def aggregate_results(results)
        {
          total_processed: results.sum { |r| r[:processed] },
          total_success: results.sum { |r| r[:success] },
          total_failed: results.sum { |r| r[:failed] },
          batch_count: results.count
        }
      end

      def empty_summary
        {
          total_count: 0,
          total_amount: 0,
          by_current_category: {},
          estimated_time_saved: "0 seconds"
        }
      end
    end
  end
end
