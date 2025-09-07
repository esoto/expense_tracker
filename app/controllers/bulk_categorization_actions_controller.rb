# frozen_string_literal: true

# Controller for bulk categorization actions and operations
class BulkCategorizationActionsController < ApplicationController
  include Authentication
  include BulkOperationMonitoring
  include RateLimiting
  before_action :set_expenses, only: [ :categorize, :suggest, :preview, :export ]
  before_action :set_bulk_operation, only: [ :undo ]

  rescue_from StandardError, with: :handle_service_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found

  def categorize
    service = build_categorization_service(
      category_id: params[:category_id],
      options: categorization_options
    )

    result = service.apply!

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/categorize" }
      format.json { render json: result }
    end
  end

  def suggest
    service = build_categorization_service(options: suggestion_options)
    suggestions = service.suggest_categories

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/suggest" }
      format.json { render json: suggestions }
    end
  end

  def preview
    service = build_categorization_service(category_id: params[:category_id])
    preview_data = service.preview

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/preview" }
      format.json { render json: preview_data }
    end
  end

  def auto_categorize
    # For auto-categorize, we need to find expenses based on filters
    expenses = find_expenses_for_auto_categorize

    service = build_categorization_service(
      expenses: expenses,
      options: {
        dry_run: params[:dry_run] == "true",
        override_existing: params[:override_existing] == "true"
      }
    )

    result = service.auto_categorize!

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/auto_categorize" }
      format.json { render json: result }
    end
  end

  def export
    service = build_categorization_service()

    respond_to do |format|
      format.csv do
        csv_data = service.export(format: :csv)
        send_data csv_data,
                  filename: "bulk_categorizations_#{Date.current.strftime('%Y%m%d')}.csv",
                  type: "text/csv",
                  disposition: "attachment"
      end
      format.json do
        render json: JSON.parse(service.export(format: :json))
      end
    end
  end

  def undo
    service = build_undo_service(bulk_operation: @bulk_operation)
    result = service.call

    respond_to do |format|
      if result.success?
        format.turbo_stream { render "bulk_categorizations/undo" }
        format.json { render json: { success: true, message: result.message, operation: result.operation } }
      else
        format.turbo_stream { render "bulk_categorizations/undo_error", status: :unprocessable_content }
        format.json { render json: { success: false, error: result.message }, status: :unprocessable_content }
      end
    end
  end

  private

  def set_expenses
    expense_ids = Array(params[:expense_ids]).reject(&:blank?).map(&:to_i)

    if expense_ids.empty?
      render json: { error: "No expenses selected" }, status: :unprocessable_content
      return
    end

    # Find expenses with eager loading for performance
    @expenses = Expense.includes(:category, :email_account)
                       .where(id: expense_ids)

    if @expenses.empty?
      # Don't reveal whether expenses exist for other users
      render json: { error: "No accessible expenses found" }, status: :not_found
      return
    end

    # Verify all requested expenses were found (prevents partial unauthorized access)
    if @expenses.count != expense_ids.count
      missing_count = expense_ids.count - @expenses.count
      Rails.logger.warn "User #{current_user.id} attempted to access #{missing_count} unauthorized expenses"
      render json: { error: "Some expenses are not accessible" }, status: :forbidden
      nil
    end
  end

  def set_bulk_operation
    # Find bulk operation by ID
    @bulk_operation = BulkOperation.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Operation not found" }, status: :not_found
  end

  def find_expenses_for_auto_categorize
    filters = auto_categorize_params
    scope = Expense.includes(:category, :email_account)

    # Apply date filters using parameterized queries
    if filters[:date_from].present?
      date_from = parse_date(filters[:date_from])
      scope = scope.where("transaction_date >= ?", date_from) if date_from
    end

    if filters[:date_to].present?
      date_to = parse_date(filters[:date_to])
      scope = scope.where("transaction_date <= ?", date_to) if date_to
    end

    # Use Arel for safe LIKE queries instead of string interpolation
    if filters[:merchant_filter].present?
      merchant_table = Expense.arel_table
      pattern = "%#{sanitize_sql_like(filters[:merchant_filter])}%"
      scope = scope.where(merchant_table[:merchant_name].matches(pattern))
    end

    # Robust amount range parsing with validation
    if filters[:amount_range].present?
      amount_range = parse_amount_range(filters[:amount_range])
      if amount_range[:error]
        Rails.logger.warn "Invalid amount_range: #{filters[:amount_range]} - #{amount_range[:error]}"
        # Return empty scope with error message
        @amount_range_error = amount_range[:error]
      elsif amount_range[:min] && amount_range[:max]
        scope = scope.where(amount: amount_range[:min]..amount_range[:max])
      end
    end

    scope = scope.where(category_id: nil) if filters[:uncategorized_only] == "true"

    # Limit with configuration
    max_bulk_size = Rails.configuration.x.bulk_operation_limit || 1000
    scope.limit(max_bulk_size)
  end

  def handle_service_error(exception)
    Rails.logger.error "BulkCategorizationActionsController Error: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")

    respond_to do |format|
      format.turbo_stream { render "shared/error", locals: { message: "An error occurred processing your request" }, status: :internal_server_error }
      format.json { render json: { error: "Internal server error", message: exception.message }, status: :internal_server_error }
    end
  end

  def handle_not_found(exception)
    respond_to do |format|
      format.turbo_stream { render "shared/not_found", status: :not_found }
      format.json { render json: { error: "Resource not found" }, status: :not_found }
    end
  end

  def categorization_options
    {
      confidence_threshold: params[:confidence_threshold]&.to_f || 0.7,
      apply_learning: params[:apply_learning] == "true",
      update_patterns: params[:update_patterns] == "true"
    }
  end

  def suggestion_options
    {
      max_suggestions: params[:max_suggestions]&.to_i || 3,
      include_confidence: params[:include_confidence] == "true"
    }
  end

  # Service builder methods to eliminate DRY violations
  def build_categorization_service(expenses: @expenses, **options)
    Categorization::BulkCategorizationService.new(
      expenses: expenses,
      user: current_user,
      **options
    )
  end

  def build_undo_service(bulk_operation:)
    BulkCategorization::UndoService.new(bulk_operation: bulk_operation)
  end

  # SQL sanitization helper to prevent injection attacks
  def sanitize_sql_like(string)
    # Remove any potential SQL keywords and special characters
    cleaned = string.to_s.gsub(/[';"\-\-\/\*\*\/]/, "")
    ActiveRecord::Base.sanitize_sql_like(cleaned)
  end

  # Parse date with validation
  def parse_date(date_string)
    Date.parse(date_string)
  rescue ArgumentError, TypeError
    nil
  end

  # Parse amount range with comprehensive validation
  def parse_amount_range(range_string)
    return { error: "Amount range cannot be blank" } if range_string.blank?

    # Support multiple formats: "100-500", "100..500", "100 to 500"
    normalized = range_string.gsub(/\s*(to|\.\.)\s*/, "-")
    parts = normalized.split("-").map(&:strip)

    return { error: "Invalid format. Use: min-max (e.g., 100-500)" } if parts.size != 2

    min_val = Float(parts[0])
    max_val = Float(parts[1])

    return { error: "Minimum cannot be negative" } if min_val < 0
    return { error: "Maximum cannot be negative" } if max_val < 0
    return { error: "Minimum must be less than maximum" } if min_val > max_val
    return { error: "Range too large (max 1,000,000)" } if max_val > 1_000_000

    { min: min_val, max: max_val }
  rescue ArgumentError, TypeError
    { error: "Invalid number format" }
  end


  def auto_categorize_params
    params.permit(:date_from, :date_to, :merchant_filter, :amount_range,
                  :uncategorized_only, :confidence_threshold, :dry_run, :override_existing)
  end
end
