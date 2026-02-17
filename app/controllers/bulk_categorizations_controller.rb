# frozen_string_literal: true

# Controller for bulk categorization operations
# Provides interface for users to categorize multiple uncategorized expenses at once
class BulkCategorizationsController < ApplicationController
  include Authentication

  before_action :load_uncategorized_expenses, only: [ :index ]
  before_action :load_bulk_operation, only: [ :show ]

  # GET /bulk_categorizations
  # Main interface showing grouped uncategorized expenses
  def index
    begin
      @grouped_expenses = group_similar_expenses(@uncategorized_expenses)
      @categories = Category.includes(:parent).order(:name)
      @statistics = calculate_statistics(@grouped_expenses)

      respond_to do |format|
        format.html
        format.json { render json: @grouped_expenses }
      end
    rescue StandardError => e
      Rails.logger.error("Bulk categorizations index failed: #{e.message}")
      @grouped_expenses = []
      @statistics = default_statistics
      flash.now[:alert] = "Unable to group expenses. Showing ungrouped list."
      respond_to do |format|
        format.html { render :index }
        format.json { render json: { error: "Unable to process expenses" }, status: :unprocessable_content }
      end
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


  private

  def load_uncategorized_expenses
    # Fix N+1 queries by including all necessary associations
    scope = Expense
      .uncategorized
      .includes(:email_account, :category, :bulk_operation_items)
      .order(transaction_date: :desc)

    # Use offset pagination when requested, otherwise apply performance limit
    @uncategorized_expenses = if params[:page].present?
      page = [ params[:page].to_i, 1 ].max
      scope.limit(100).offset((page - 1) * 100)
    else
      scope.limit(500) # Only apply limit when not paginating
    end
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

  def default_statistics
    {
      total_groups: 0,
      total_expenses: 0,
      high_confidence_groups: 0,
      total_amount: 0
    }
  end
end
