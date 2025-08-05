class ExpensesController < ApplicationController
  before_action :set_expense, only: [ :show, :edit, :update, :destroy ]

  # GET /expenses
  def index
    # Base query with includes
    @expenses = Expense.includes(:category, :email_account)

    # Apply filters efficiently
    @expenses = apply_filters(@expenses)

    # Order and limit
    @expenses = @expenses.order(transaction_date: :desc, created_at: :desc)
                        .limit(25)

    # Calculate summary with separate optimized query
    calculate_summary_statistics
  end

  # GET /expenses/1
  def show
  end

  # GET /expenses/new
  def new
    @expense = Expense.new
    @categories = Category.all.order(:name)
    @email_accounts = EmailAccount.all.order(:email)
  end

  # GET /expenses/1/edit
  def edit
    @categories = Category.all.order(:name)
    @email_accounts = EmailAccount.all.order(:email)
  end

  # POST /expenses
  def create
    @expense = Expense.new(expense_params)
    @expense.bank_name = "Manual Entry"
    @expense.status = "processed"
    @expense.crc! if @expense.currency.blank? # Default to CRC if no currency specified

    if @expense.save
      redirect_to @expense, notice: "Gasto creado exitosamente."
    else
      @categories = Category.all.order(:name)
      @email_accounts = EmailAccount.all.order(:email)
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /expenses/1
  def update
    if @expense.update(expense_params)
      redirect_to @expense, notice: "Gasto actualizado exitosamente."
    else
      @categories = Category.all.order(:name)
      @email_accounts = EmailAccount.all.order(:email)
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /expenses/1
  def destroy
    @expense.destroy
    redirect_to expenses_url, notice: "Gasto eliminado exitosamente."
  end

  # GET /expenses/dashboard
  def dashboard
    dashboard_data = DashboardService.new.analytics

    # Extract data for view variables
    totals = dashboard_data[:totals]
    @total_expenses = totals[:total_expenses]
    @expense_count = totals[:expense_count]
    @current_month_total = totals[:current_month_total]
    @last_month_total = totals[:last_month_total]

    @recent_expenses = dashboard_data[:recent_expenses]

    category_data = dashboard_data[:category_breakdown]
    @category_totals = category_data[:totals]
    @sorted_categories = category_data[:sorted]

    @monthly_data = dashboard_data[:monthly_trend]
    @bank_totals = dashboard_data[:bank_breakdown]
    @top_merchants = dashboard_data[:top_merchants]
    @email_accounts = dashboard_data[:email_accounts]
    @last_sync_info = dashboard_data[:sync_info]
  end

  # POST /expenses/sync_emails
  def sync_emails
    sync_result = SyncService.new.sync_emails(email_account_id: params[:email_account_id])
    redirect_to dashboard_expenses_path, notice: sync_result[:message]
  rescue SyncService::SyncError => e
    redirect_to dashboard_expenses_path, alert: e.message
  rescue StandardError => e
    Rails.logger.error "Error starting email sync: #{e.message}"
    redirect_to dashboard_expenses_path, alert: "Error al iniciar la sincronización. Por favor, inténtalo de nuevo."
  end

  private

  def set_expense
    @expense = Expense.find(params[:id])
  end

  def expense_params
    params.require(:expense).permit(:amount, :currency, :transaction_date, :merchant_name, :description, :category_id, :email_account_id, :notes)
  end

  def apply_filters(scope)
    # Use left_joins instead of joins to maintain includes
    scope = scope.left_joins(:category).where(categories: { name: params[:category] }) if params[:category].present?
    scope = scope.where(transaction_date: params[:start_date]..params[:end_date]) if date_range_present?
    scope = scope.where(bank_name: params[:bank]) if params[:bank].present?
    scope
  end

  def date_range_present?
    params[:start_date].present? && params[:end_date].present?
  end

  def calculate_summary_statistics
    # Build a separate query for aggregations
    summary_scope = Expense.all
    summary_scope = apply_filters(summary_scope)

    # Single query for both sum and count
    result = summary_scope.pick(Arel.sql("SUM(amount)"), Arel.sql("COUNT(*)"))
    @total_amount = result[0] || 0
    @expense_count = result[1] || 0

    # Category summary with single query
    @categories_summary = summary_scope
      .joins(:category)
      .group("categories.name")
      .sum(:amount)
      .sort_by { |_, amount| -amount }
  end
end
