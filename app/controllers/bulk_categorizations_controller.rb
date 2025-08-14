# frozen_string_literal: true

# Controller for bulk categorization operations
# Provides interface for users to categorize multiple uncategorized expenses at once
class BulkCategorizationsController < ApplicationController
  include Authentication
  include RateLimiting

  # Rate limiting for bulk operations
  rate_limit :categorize, limit: 10, period: 1.minute, by: :user
  rate_limit :auto_categorize, limit: 5, period: 5.minutes, by: :user
  rate_limit :export, limit: 20, period: 1.hour, by: :user

  before_action :load_uncategorized_expenses, only: [ :index ]
  before_action :load_bulk_operation, only: [ :show, :undo ]

  # GET /bulk_categorizations
  # Main interface showing grouped uncategorized expenses
  def index
    @grouped_expenses = group_similar_expenses(@uncategorized_expenses)
    @categories = Category.includes(:parent).order(:name)
    @statistics = calculate_statistics(@grouped_expenses)

    respond_to do |format|
      format.html
      format.json { render json: @grouped_expenses }
    end
  end

  # GET /bulk_categorizations/:id
  # Show details of a specific bulk operation
  def show
    @affected_expenses = @bulk_operation.expenses
    respond_to do |format|
      format.html
      format.json { render json: @bulk_operation }
    end
  end

  # POST /bulk_categorizations/categorize
  # Apply categorization to a group of expenses
  def categorize
    expense_ids = Array(params[:expense_ids])

    # Use background job for large operations
    if expense_ids.count > 50
      job = BulkCategorizationJob.perform_later(
        expense_ids,
        params[:category_id],
        current_user_id,
        { allow_recategorization: params[:allow_recategorization] }
      )

      respond_to do |format|
        format.html { redirect_to bulk_categorizations_path, notice: "Processing #{expense_ids.count} expenses in background. You'll be notified when complete." }
        format.turbo_stream { render_background_job_stream(job.job_id, expense_ids.count) }
        format.json { render json: { job_id: job.job_id, status: "processing" }, status: :accepted }
      end
    else
      # Process small batches synchronously
      result = Services::BulkCategorization::ApplyService.new(
        expense_ids: expense_ids,
        category_id: params[:category_id],
        user_id: current_user_id
      ).call

      if result.success?
        log_user_action("bulk_categorization", { expense_count: expense_ids.count, category_id: params[:category_id] })

        respond_to do |format|
          format.html { redirect_to bulk_categorizations_path, notice: result.message }
          format.turbo_stream { render_categorization_update(result) }
          format.json { render json: result, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to bulk_categorizations_path, alert: result.message }
          format.turbo_stream { render_error_stream(result.message) }
          format.json { render json: { error: result.message }, status: :unprocessable_content }
        end
      end
    end
  end

  # POST /bulk_categorizations/suggest
  # Get AI-powered suggestions for a group of expenses
  def suggest
    service = Services::BulkCategorization::SuggestionService.new(
      expenses: Expense.where(id: params[:expense_ids])
    )

    suggestions = service.generate_suggestions

    respond_to do |format|
      format.turbo_stream { render_suggestions_stream(suggestions) }
      format.json { render json: suggestions }
    end
  end

  # POST /bulk_categorizations/preview
  # Preview categorization before applying
  def preview
    expenses = Expense.where(id: params[:expense_ids])
    category = Category.find(params[:category_id])

    preview_data = Services::BulkCategorization::PreviewService.new(
      expenses: expenses,
      category: category
    ).generate

    respond_to do |format|
      format.turbo_stream { render_preview_stream(preview_data) }
      format.json { render json: preview_data }
    end
  end

  # POST /bulk_categorizations/:id/undo
  # Undo a bulk categorization operation
  def undo
    result = Services::BulkCategorization::UndoService.new(
      bulk_operation: @bulk_operation
    ).call

    if result.success?
      respond_to do |format|
        format.html { redirect_to bulk_categorizations_path, notice: "Operation undone successfully" }
        format.turbo_stream { render_undo_stream(result) }
        format.json { render json: result, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to bulk_categorizations_path, alert: result.message }
        format.json { render json: { error: result.message }, status: :unprocessable_content }
      end
    end
  end

  # GET /bulk_categorizations/export
  # Export categorization report
  def export
    exporter = Services::BulkCategorization::ExportService.new(
      start_date: params[:start_date],
      end_date: params[:end_date],
      format: params[:format_type] || "csv"
    )

    respond_to do |format|
      format.csv { send_data exporter.to_csv, filename: export_filename("csv") }
      format.xlsx { send_data exporter.to_xlsx, filename: export_filename("xlsx") }
      format.json { render json: exporter.to_json }
    end
  end

  # POST /bulk_categorizations/auto_categorize
  # Automatically categorize high-confidence matches
  def auto_categorize
    service = Services::BulkCategorization::AutoCategorizationService.new(
      confidence_threshold: params[:confidence_threshold] || 0.8
    )

    result = service.categorize_all

    respond_to do |format|
      format.html { redirect_to bulk_categorizations_path, notice: result.message }
      format.turbo_stream { render_auto_categorize_stream(result) }
      format.json { render json: result }
    end
  end

  private

  def load_uncategorized_expenses
    # Fix N+1 queries by including all necessary associations
    # Use batch loading for better memory management
    @uncategorized_expenses = Expense
      .uncategorized
      .includes(:email_account, :category, :bulk_operation_items)
      .order(transaction_date: :desc)
      .limit(500) # Limit for performance

    # For very large datasets, consider pagination
    @uncategorized_expenses = @uncategorized_expenses.page(params[:page]).per(100) if params[:page].present?
  end

  def load_bulk_operation
    # Fix N+1 queries for bulk operation
    @bulk_operation = BulkOperation
      .includes(:bulk_operation_items, expenses: [ :category, :email_account ])
      .find(params[:id])
  end

  def group_similar_expenses(expenses)
    Services::BulkCategorization::GroupingService.new(expenses).group_by_similarity
  end

  def calculate_statistics(grouped_expenses)
    {
      total_groups: grouped_expenses.count,
      total_expenses: grouped_expenses.sum { |g| g[:expenses].count },
      high_confidence_groups: grouped_expenses.count { |g| g[:confidence] > 0.8 },
      total_amount: grouped_expenses.sum { |g| g[:total_amount] }
    }
  end


  def render_categorization_update(result)
    render turbo_stream: [
      turbo_stream.replace("expense_group_#{params[:group_id]}",
        partial: "bulk_categorizations/expense_group",
        locals: { group: result.updated_group }),
      turbo_stream.replace("statistics",
        partial: "bulk_categorizations/statistics",
        locals: { statistics: calculate_statistics(result.remaining_groups) }),
      turbo_stream.prepend("notifications",
        partial: "shared/notification",
        locals: { message: result.message, type: :success })
    ]
  end

  def render_error_stream(message)
    render turbo_stream: turbo_stream.prepend("notifications",
      partial: "shared/notification",
      locals: { message: message, type: :error })
  end

  def render_suggestions_stream(suggestions)
    render turbo_stream: turbo_stream.replace("suggestions_#{params[:group_id]}",
      partial: "bulk_categorizations/suggestions",
      locals: { suggestions: suggestions })
  end

  def render_preview_stream(preview_data)
    render turbo_stream: turbo_stream.replace("preview_modal",
      partial: "bulk_categorizations/preview_modal",
      locals: { preview: preview_data })
  end

  def render_undo_stream(result)
    render turbo_stream: [
      turbo_stream.replace("bulk_operation_#{params[:id]}",
        partial: "bulk_categorizations/bulk_operation",
        locals: { operation: result.operation }),
      turbo_stream.prepend("notifications",
        partial: "shared/notification",
        locals: { message: "Operation undone successfully", type: :success })
    ]
  end

  def render_auto_categorize_stream(result)
    render turbo_stream: [
      turbo_stream.replace("uncategorized_expenses",
        partial: "bulk_categorizations/expense_groups",
        locals: { grouped_expenses: group_similar_expenses(result.remaining_expenses) }),
      turbo_stream.replace("statistics",
        partial: "bulk_categorizations/statistics",
        locals: { statistics: calculate_statistics(result.remaining_groups) }),
      turbo_stream.prepend("notifications",
        partial: "shared/notification",
        locals: { message: result.message, type: :success })
    ]
  end

  def render_background_job_stream(job_id, expense_count)
    render turbo_stream: [
      turbo_stream.prepend("notifications",
        partial: "shared/notification",
        locals: {
          message: "Processing #{expense_count} expenses in background. Job ID: #{job_id}",
          type: :info
        }),
      turbo_stream.replace("bulk_operation_status",
        partial: "bulk_categorizations/job_status",
        locals: { job_id: job_id, status: "processing" })
    ]
  end

  def export_filename(extension)
    "categorization_report_#{Date.current.strftime('%Y%m%d')}.#{extension}"
  end
end
