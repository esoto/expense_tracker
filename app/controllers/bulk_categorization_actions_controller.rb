# frozen_string_literal: true

# Controller for bulk categorization actions and operations
class BulkCategorizationActionsController < ApplicationController
  before_action :authenticate_user!

  def categorize
    # FIXME: This action uses non-existent Services::Categorization::BulkProcessor
    # Should use Services::Categorization::BulkCategorizationService instead
    result = Services::Categorization::BulkProcessor.new.categorize(
      expense_ids: params[:expense_ids],
      category_id: params[:category_id],
      options: categorization_options
    )

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/categorize" }
      format.json { render json: result }
    end
  end

  def suggest
    expenses = Expense.find(params[:expense_ids])
    service = Categorization::BulkCategorizationService.new(
      expenses: expenses,
      user: current_user,
      options: suggestion_options
    )
    suggestions = service.suggest_categories

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/suggest" }
      format.json { render json: suggestions }
    end
  end

  def preview
    # FIXME: This action uses non-existent Services::Categorization::BulkProcessor
    # Should use Services::Categorization::BulkCategorizationService#preview instead
    preview_data = Services::Categorization::BulkProcessor.new.preview(
      expense_ids: params[:expense_ids],
      category_id: params[:category_id]
    )

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/preview" }
      format.json { render json: preview_data }
    end
  end

  def auto_categorize
    # FIXME: This action uses non-existent Services::Categorization::BulkProcessor
    # Should use Services::Categorization::BulkCategorizationService instead
    result = Services::Categorization::BulkProcessor.new.auto_categorize(
      filter_params: auto_categorize_params,
      options: { dry_run: params[:dry_run] }
    )

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/auto_categorize" }
      format.json { render json: result }
    end
  end

  def export
    respond_to do |format|
      format.csv do
        csv_data = Services::Categorization::BulkExporter.new.export(
          expense_ids: params[:expense_ids]
        )
        send_data csv_data,
                  filename: "bulk_categorizations_#{Date.current.strftime('%Y%m%d')}.csv",
                  type: "text/csv"
      end
    end
  end

  def undo
    # FIXME: This action uses non-existent Services::Categorization::BulkProcessor
    # Should use BulkCategorization::UndoService instead
    operation = BulkCategorizationOperation.find(params[:id])
    result = Services::Categorization::BulkProcessor.new.undo(operation)

    respond_to do |format|
      format.turbo_stream { render "bulk_categorizations/undo" }
      format.json { render json: result }
    end
  end

  private

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

  def auto_categorize_params
    params.permit(:date_from, :date_to, :merchant_filter, :amount_range,
                  :uncategorized_only, :confidence_threshold)
  end
end
