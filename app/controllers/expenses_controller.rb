class ExpensesController < ApplicationController
  before_action :authenticate_user!, except: [ :dashboard ] # Allow dashboard without auth for now
  before_action :set_expense, only: [ :show, :edit, :update, :destroy, :correct_category, :accept_suggestion, :reject_suggestion ]
  before_action :authorize_expense!, only: [ :edit, :update, :destroy, :correct_category, :accept_suggestion, :reject_suggestion ]

  # GET /expenses
  def index
    # Handle dashboard navigation context
    setup_navigation_context

    # Base query with includes - now includes ml_suggested_category to prevent N+1
    @expenses = current_user_expenses.includes(:category, :email_account, :ml_suggested_category)

    # Apply filters efficiently
    @expenses = apply_filters(@expenses)

    # Order and limit
    @expenses = @expenses.order(transaction_date: :desc, created_at: :desc)
                        .limit(25)

    # Calculate summary with separate optimized query
    calculate_summary_statistics

    # Set up scroll target if specified
    @scroll_to = params[:scroll_to] if params[:scroll_to].present?

    # Add filter description for UI
    @filter_description = build_filter_description
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
    # Use primary email account or first active one for metrics
    # This ensures proper data isolation per email account
    primary_email_account = EmailAccount.active.first

    # Calculate metrics for different periods using MetricsCalculator
    if primary_email_account
      # Batch calculate all metrics for better performance
      # This optimization reduces object instantiation and improves efficiency
      batch_results = MetricsCalculator.batch_calculate(
        email_account: primary_email_account,
        periods: [ :year, :month, :week, :day ],
        reference_date: Date.current
      )
      # Assign results to instance variables for view compatibility
      @total_metrics = batch_results[:year]   # Using year for total metrics
      @month_metrics = batch_results[:month]
      @week_metrics = batch_results[:week]
      @day_metrics = batch_results[:day]
    else
      # Default empty metrics if no email account
      @total_metrics = default_empty_metrics
      @month_metrics = default_empty_metrics
      @week_metrics = default_empty_metrics
      @day_metrics = default_empty_metrics
    end

    # Get dashboard data from DashboardService for other components
    dashboard_data = DashboardService.new.analytics

    # Legacy variables for compatibility with existing views
    totals = dashboard_data[:totals]
    @total_expenses = @total_metrics[:metrics][:total_amount] || totals[:total_expenses]
    @expense_count = @total_metrics[:metrics][:transaction_count] || totals[:expense_count]
    @current_month_total = @month_metrics[:metrics][:total_amount] || totals[:current_month_total]
    @last_month_total = @month_metrics[:trends][:previous_period_total] || totals[:last_month_total]

    @recent_expenses = dashboard_data[:recent_expenses]

    category_data = dashboard_data[:category_breakdown]
    @category_totals = category_data[:totals]
    @sorted_categories = category_data[:sorted]

    @monthly_data = dashboard_data[:monthly_trend]
    @bank_totals = dashboard_data[:bank_breakdown]
    @top_merchants = dashboard_data[:top_merchants]
    @email_accounts = dashboard_data[:email_accounts]
    @last_sync_info = dashboard_data[:sync_info]
    # Add sync session data for the widget
    sync_sessions = dashboard_data[:sync_sessions] || {}
    @active_sync_session = sync_sessions[:active_session]
    @last_completed_sync = sync_sessions[:last_completed]

    # Primary email account for display
    @primary_email_account = primary_email_account
  end

  # POST /expenses/sync_emails
  def sync_emails
    sync_result = Services::Email::SyncService.new.sync_emails(email_account_id: params[:email_account_id])
    redirect_to dashboard_expenses_path, notice: sync_result[:message]
  rescue Services::Email::SyncService::SyncError => e
    redirect_to dashboard_expenses_path, alert: e.message
  rescue StandardError => e
    Rails.logger.error "Error starting email sync: #{e.message}"
    redirect_to dashboard_expenses_path, alert: "Error al iniciar la sincronización. Por favor, inténtalo de nuevo."
  end

  # POST /expenses/:id/correct_category
  def correct_category
    new_category_id = params[:category_id]

    # Validate category_id
    if new_category_id.present?
      # Ensure the category exists
      unless Category.exists?(new_category_id)
        respond_to do |format|
          format.html { redirect_back(fallback_location: @expense, alert: "Categoría inválida") }
          format.json { render json: { success: false, error: "Invalid category ID" }, status: :unprocessable_content }
        end
        return
      end

      @expense.reject_ml_suggestion!(new_category_id)

      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, notice: "Categoría actualizada correctamente") }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("expense_#{@expense.id}_category", partial: "expenses/category_with_confidence", locals: { expense: @expense }) }
        format.json { render json: { success: true, expense: expense_json(@expense) } }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, alert: "Por favor selecciona una categoría") }
        format.json { render json: { success: false, error: "Category ID required" }, status: :unprocessable_content }
      end
    end
  rescue StandardError => e
    Rails.logger.error "Error correcting category: #{e.message}"
    respond_to do |format|
      format.html { redirect_back(fallback_location: @expense, alert: "Error al actualizar la categoría") }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  # POST /expenses/:id/accept_suggestion
  def accept_suggestion
    if @expense.accept_ml_suggestion!
      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, notice: "Sugerencia aceptada") }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("expense_#{@expense.id}_category", partial: "expenses/category_with_confidence", locals: { expense: @expense }) }
        format.json { render json: { success: true, expense: expense_json(@expense) } }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, alert: "No hay sugerencia disponible") }
        format.json { render json: { success: false, error: "No suggestion available" }, status: :unprocessable_content }
      end
    end
  rescue StandardError => e
    Rails.logger.error "Error accepting suggestion: #{e.message}"
    respond_to do |format|
      format.html { redirect_back(fallback_location: @expense, alert: "Error al aceptar la sugerencia") }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  # POST /expenses/:id/reject_suggestion
  def reject_suggestion
    @expense.update!(ml_suggested_category_id: nil)

    respond_to do |format|
      format.html { redirect_back(fallback_location: @expense, notice: "Sugerencia rechazada") }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("expense_#{@expense.id}_category", partial: "expenses/category_with_confidence", locals: { expense: @expense }) }
      format.json { render json: { success: true, expense: expense_json(@expense) } }
    end
  rescue StandardError => e
    Rails.logger.error "Error rejecting suggestion: #{e.message}"
    respond_to do |format|
      format.html { redirect_back(fallback_location: @expense, alert: "Error al rechazar la sugerencia") }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  private

  def set_expense
    @expense = current_user_expenses.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to expenses_path, alert: "Gasto no encontrado o no tienes permiso para verlo."
  end

  def authorize_expense!
    unless can_modify_expense?(@expense)
      redirect_to expenses_path, alert: "No tienes permiso para modificar este gasto."
    end
  end

  def can_modify_expense?(expense)
    # Check if the expense belongs to the current user's email accounts
    return false unless expense.present?

    # Allow modification if expense belongs to user's email accounts
    current_user_email_accounts.include?(expense.email_account)
  end

  def current_user_expenses
    # Get expenses that belong to the current user's email accounts
    Expense.joins(:email_account)
           .where(email_account: current_user_email_accounts)
  end

  def current_user_email_accounts
    # Cache this in instance variable to avoid multiple queries
    @current_user_email_accounts ||= if defined?(current_user) && current_user.present?
      # If using Devise or similar authentication
      EmailAccount.where(user_id: current_user.id)
    else
      # Fallback for systems without user authentication
      # In production, this should be properly configured
      EmailAccount.all
    end
  end

  def authenticate_user!
    # This would normally be provided by Devise or your auth system
    # For now, we'll make it a no-op if not defined
    super if defined?(super)
  end

  def expense_params
    params.require(:expense).permit(:amount, :currency, :transaction_date, :merchant_name, :description, :category_id, :email_account_id, :notes)
  end

  def expense_json(expense)
    {
      id: expense.id,
      amount: expense.amount,
      description: expense.description,
      merchant_name: expense.merchant_name,
      category: expense.category ? {
        id: expense.category.id,
        name: expense.category.name,
        color: expense.category.color
      } : nil,
      ml_confidence: expense.ml_confidence,
      confidence_level: expense.confidence_level,
      confidence_percentage: expense.confidence_percentage,
      ml_suggested_category: expense.ml_suggested_category ? {
        id: expense.ml_suggested_category.id,
        name: expense.ml_suggested_category.name,
        color: expense.ml_suggested_category.color
      } : nil
    }
  end

  def apply_filters(scope)
    # Handle period-based filtering from dashboard cards
    if params[:period].present?
      date_range = calculate_period_range(params[:period])
      scope = scope.where(transaction_date: date_range) if date_range
    elsif params[:date_from].present? && params[:date_to].present?
      # Handle explicit date range from dashboard
      scope = scope.where(transaction_date: params[:date_from]..params[:date_to])
    elsif date_range_present?
      # Handle traditional date range filters
      scope = scope.where(transaction_date: params[:start_date]..params[:end_date])
    end

    # Use left_joins instead of joins to maintain includes
    scope = scope.left_joins(:category).where(categories: { name: params[:category] }) if params[:category].present?
    scope = scope.where(bank_name: params[:bank]) if params[:bank].present?
    scope
  end

  def date_range_present?
    params[:start_date].present? && params[:end_date].present?
  end

  def calculate_period_range(period)
    today = Date.current
    case period
    when "day"
      today..today
    when "week"
      today.beginning_of_week..today.end_of_week
    when "month"
      today.beginning_of_month..today.end_of_month
    when "year"
      today.beginning_of_year..today.end_of_year
    else
      nil
    end
  end

  def setup_navigation_context
    # Detect if navigation is from dashboard
    @from_dashboard = params[:filter_type] == "dashboard_metric"

    # Store period for display
    @active_period = params[:period] if params[:period].present?

    # Store date range for display
    if params[:date_from].present? && params[:date_to].present?
      begin
        @date_from = Date.parse(params[:date_from])
      rescue ArgumentError => e
        Rails.logger.warn "Invalid date_from parameter: #{params[:date_from]} - #{e.message}"
        @date_from = nil
      end

      begin
        @date_to = Date.parse(params[:date_to])
      rescue ArgumentError => e
        Rails.logger.warn "Invalid date_to parameter: #{params[:date_to]} - #{e.message}"
        @date_to = nil
      end
    elsif params[:period].present?
      date_range = calculate_period_range(params[:period])
      if date_range
        @date_from = date_range.first
        @date_to = date_range.last
      end
    end
  end

  def build_filter_description
    descriptions = []

    # Add period description
    if @active_period
      period_descriptions = {
        "day" => "Gastos de hoy",
        "week" => "Gastos de esta semana",
        "month" => "Gastos de este mes",
        "year" => "Gastos del año"
      }
      descriptions << period_descriptions[@active_period]
    elsif @date_from && @date_to
      if @date_from == @date_to
        descriptions << "Gastos del #{@date_from.strftime('%d/%m/%Y')}"
      else
        descriptions << "Gastos del #{@date_from.strftime('%d/%m/%Y')} al #{@date_to.strftime('%d/%m/%Y')}"
      end
    elsif params[:start_date].present? && params[:end_date].present?
      descriptions << "Gastos del #{params[:start_date]} al #{params[:end_date]}"
    end

    # Add category filter
    descriptions << "Categoría: #{params[:category]}" if params[:category].present?

    # Add bank filter
    descriptions << "Banco: #{params[:bank]}" if params[:bank].present?

    descriptions.empty? ? nil : descriptions.join(" • ")
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

  def default_empty_metrics
    {
      period: :month,
      reference_date: Date.current,
      date_range: Date.current.beginning_of_month..Date.current.end_of_month,
      metrics: {
        total_amount: 0.0,
        transaction_count: 0,
        average_amount: 0.0,
        median_amount: 0.0,
        min_amount: 0.0,
        max_amount: 0.0,
        unique_merchants: 0,
        unique_categories: 0,
        uncategorized_count: 0,
        by_status: {},
        by_currency: {}
      },
      trends: {
        amount_change: 0.0,
        count_change: 0.0,
        average_change: 0.0,
        absolute_amount_change: 0.0,
        absolute_count_change: 0,
        is_increase: false,
        previous_period_total: 0.0,
        previous_period_count: 0
      },
      category_breakdown: [],
      daily_breakdown: {},
      trend_data: {
        daily_amounts: [],
        min: 0.0,
        max: 0.0,
        average: 0.0,
        total: 0.0,
        start_date: Date.current - 6.days,
        end_date: Date.current
      },
      calculated_at: Time.current
    }
  end
end
