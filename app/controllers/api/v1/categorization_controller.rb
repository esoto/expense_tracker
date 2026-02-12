# frozen_string_literal: true

module Api
  module V1
    # API controller for categorization suggestions and feedback
    class CategorizationController < BaseController
      before_action :initialize_categorization_service

      # POST /api/v1/categorization/suggest
      def suggest
        validate_suggest_params!

        # Build expense-like object for categorization
        expense_data = build_expense_data(suggest_params)

        # Get category suggestions
        suggestions = @categorization_service.suggest_categories(
          expense_data,
          suggest_params[:max_suggestions] || 3
        )

        # Format and return suggestions
        render_success({
          suggestions: format_suggestions(suggestions),
          expense_data: {
            merchant_name: expense_data.merchant_name,
            description: expense_data.description,
            amount: expense_data.amount,
            transaction_date: expense_data.transaction_date&.iso8601
          }
        })
      end

      # POST /api/v1/categorization/feedback
      def feedback
        validate_feedback_params!

        expense = Expense.find(feedback_params[:expense_id])
        category = Category.find(feedback_params[:category_id])

        # Find the pattern that was used (if any)
        pattern = if feedback_params[:pattern_id].present?
                    CategorizationPattern.find_by(id: feedback_params[:pattern_id])
        end

        # Record the feedback
        feedback_record = PatternFeedback.record_feedback(
          expense: expense,
          correct_category: category,
          pattern: pattern,
          was_correct: feedback_params[:was_correct],
          confidence: feedback_params[:confidence],
          type: determine_feedback_type(feedback_params)
        )

        # Let the categorization service learn from this feedback
        @categorization_service.learn_from_feedback(
          expense,
          category,
          feedback_params[:was_correct]
        )

        render_success({
          feedback: serialize_feedback(feedback_record),
          improvement_suggestion: feedback_record.improvement_suggestion
        })
      end

      # POST /api/v1/categorization/batch_suggest
      def batch_suggest
        return unless validate_batch_suggest_params!

        expenses_data = batch_suggest_params[:expenses].map do |expense_params|
          build_expense_data(expense_params)
        end

        results = @categorization_service.categorize_batch(expenses_data)

        render_success({
          results: format_batch_results(results)
        })
      end

      # GET /api/v1/categorization/statistics
      def statistics
        stats = {
          total_patterns: CategorizationPattern.count,
          active_patterns: CategorizationPattern.active.count,
          user_created_patterns: CategorizationPattern.user_created.count,
          high_confidence_patterns: CategorizationPattern.high_confidence.count,
          successful_patterns: CategorizationPattern.successful.count,
          frequently_used_patterns: CategorizationPattern.frequently_used.count,
          recent_feedback_count: PatternFeedback.where(created_at: 7.days.ago..).count,
          feedback_by_type: PatternFeedback.group(:feedback_type).count,
          average_success_rate: CategorizationPattern.active.average(:success_rate)&.round(3) || 0,
          patterns_by_type: CategorizationPattern.group(:pattern_type).count,
          top_categories: top_categorized_categories
        }

        render_success({ statistics: stats })
      end

      private

      def initialize_categorization_service
        @categorization_service = Services::Categorization::EnhancedCategorizationService.new
      end

      def suggest_params
        params.permit(
          :merchant_name,
          :description,
          :amount,
          :transaction_date,
          :max_suggestions
        )
      end

      def feedback_params
        params.require(:feedback).permit(
          :expense_id,
          :category_id,
          :pattern_id,
          :was_correct,
          :confidence,
          :feedback_type
        )
      end

      def batch_suggest_params
        params.permit(
          expenses: [
            :merchant_name,
            :description,
            :amount,
            :transaction_date
          ]
        )
      end

      def validate_suggest_params!
        if suggest_params[:merchant_name].blank? && suggest_params[:description].blank?
          raise ActionController::ParameterMissing, "Either merchant_name or description is required"
        end
      end

      def validate_feedback_params!
        raise ActionController::ParameterMissing, "expense_id is required" if feedback_params[:expense_id].blank?
        raise ActionController::ParameterMissing, "category_id is required" if feedback_params[:category_id].blank?
      end

      def validate_batch_suggest_params!
        if batch_suggest_params[:expenses].blank? || !batch_suggest_params[:expenses].is_a?(Array)
          raise ActionController::ParameterMissing, "expenses array is required"
        end

        if batch_suggest_params[:expenses].size > 100
          render json: {
            error: "Maximum 100 expenses per batch",
            status: 400
          }, status: :bad_request
          return false
        end

        true
      end

      def build_expense_data(params)
        # Create a struct that behaves like an Expense model
        expense_struct = Struct.new(
          :merchant_name,
          :description,
          :amount,
          :transaction_date,
          keyword_init: true
        ) do
          def merchant_name?
            merchant_name.present?
          end

          def description?
            description.present?
          end
        end

        expense_struct.new(
          merchant_name: params[:merchant_name],
          description: params[:description],
          amount: params[:amount]&.to_d,
          transaction_date: parse_date(params[:transaction_date])
        )
      end

      def parse_date(date_string)
        return nil if date_string.blank?
        Date.parse(date_string)
      rescue ArgumentError
        nil
      end

      def determine_feedback_type(params)
        return params[:feedback_type] if params[:feedback_type].present?

        if params[:was_correct] == true
          "accepted"
        elsif params[:was_correct] == false
          "rejected"
        else
          "correction"
        end
      end

      def format_suggestions(suggestions)
        CategorizationSerializer.collection(suggestions)
      end

      def format_batch_results(results)
        results.map do |result|
          {
            expense: {
              merchant_name: result[:expense].merchant_name,
              description: result[:expense].description,
              amount: result[:expense].amount
            },
            category_id: result[:category]&.id,
            category_name: result[:category]&.name,
            confidence: result[:confidence]&.round(3)
          }
        end
      end

      def serialize_feedback(feedback)
        CategorizationSerializer.feedback(feedback)
      end

      def top_categorized_categories(limit = 5)
        Category
          .joins("LEFT JOIN categorization_patterns ON categorization_patterns.category_id = categories.id")
          .group("categories.id", "categories.name")
          .order("COUNT(categorization_patterns.id) DESC")
          .limit(limit)
          .pluck("categories.name", "COUNT(categorization_patterns.id)")
          .map { |name, count| { name: name, pattern_count: count } }
      end
    end
  end
end
