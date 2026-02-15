class ExpensesController < ApplicationController
  include Authentication
  before_action :set_expense, only: [ :show, :edit, :update, :destroy, :correct_category, :accept_suggestion, :reject_suggestion, :update_status, :duplicate ]
  before_action :authorize_expense!, only: [ :edit, :update, :destroy, :correct_category, :accept_suggestion, :reject_suggestion, :update_status, :duplicate ]

  # GET /expenses
  def index
    # Handle dashboard navigation context
    setup_navigation_context

    # Use the optimized Services::ExpenseFilterService for performance
    filter_service = Services::ExpenseFilterService.new(
      filter_params.merge(
        account_ids: current_user_email_accounts.pluck(:id)
      )
    )

    @result = filter_service.call
    @categories = Category.all.order(:name)

    if @result.success?
      @expenses = @result.expenses
      @total_count = @result.total_count
      @performance_metrics = @result.performance_metrics

      # Extract metadata for UI
      @filters_applied = @result.metadata[:filters_applied]
      @current_page = @result.metadata[:page]
      @per_page = @result.metadata[:per_page]

      # Calculate summary statistics from the result
      calculate_summary_from_result(@result)
    else
      # Fallback to empty result on error
      @expenses = []
      @total_count = 0
      @performance_metrics = { error: true }
      flash.now[:alert] = "Error loading expenses. Please try again."
    end

    # Set up scroll target if specified
    @scroll_to = params[:scroll_to] if params[:scroll_to].present?

    # Add filter description for UI
    @filter_description = build_filter_description

    respond_to do |format|
      format.html
      format.json { render json: @result }
      format.turbo_stream
    end
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

    respond_to do |format|
      format.html { redirect_to expenses_url, notice: "Gasto eliminado exitosamente." }
      format.turbo_stream do
        # Return an empty turbo stream since the JS controller handles the row removal
        render turbo_stream: turbo_stream.append("toast-container",
          "<div data-controller='toast' data-toast-remove-delay-value='5000' class='hidden'>Gasto eliminado exitosamente</div>")
      end
      format.json { render json: { success: true, message: "Gasto eliminado exitosamente" } }
    end
  end

  # GET /expenses/dashboard
  def dashboard
    # Use primary email account or first active one for metrics
    # This ensures proper data isolation per email account
    primary_email_account = EmailAccount.active.first

    # Calculate metrics for different periods using Services::MetricsCalculator
    if primary_email_account
      # Batch calculate all metrics for better performance
      # This optimization reduces object instantiation and improves efficiency
      batch_results = Services::MetricsCalculator.batch_calculate(
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

    # Get dashboard data from Services::DashboardService for other components
    dashboard_data = Services::DashboardService.new.analytics

    # Legacy variables for compatibility with existing views
    totals = dashboard_data[:totals]
    @total_expenses = @total_metrics[:metrics][:total_amount] || totals[:total_expenses]
    @expense_count = @total_metrics[:metrics][:transaction_count] || totals[:expense_count]
    @current_month_total = @month_metrics[:metrics][:total_amount] || totals[:current_month_total]
    @last_month_total = @month_metrics[:trends][:previous_period_total] || totals[:last_month_total]

    # Use optimized Services::DashboardExpenseFilterService for Recent Expenses widget
    # This provides filtered, paginated results with performance optimization
    # Always fetch 15 expenses to support both compact and expanded views
    view_mode = params[:view_mode] || "compact"

    dashboard_filter_params = params.permit(
      :page, :per_page, :view_mode,
      :search_query, :status, :period,
      :min_amount, :max_amount,
      :sort_by, :sort_direction,
      category_ids: [], banks: []
    ).to_h.merge(
      account_ids: current_user_email_accounts.pluck(:id),
      per_page: params[:per_page] || 15,  # Always fetch 15 for view toggle support
      include_summary: true,
      include_quick_filters: true
    )

    dashboard_filter_service = Services::DashboardExpenseFilterService.new(dashboard_filter_params)
    @expense_filter_result = dashboard_filter_service.call

    if @expense_filter_result.success?
      @recent_expenses = @expense_filter_result.expenses
      @expense_summary_stats = @expense_filter_result.summary_stats
      @expense_quick_filters = @expense_filter_result.quick_filters
      @expense_view_mode = view_mode  # Use the normalized view_mode
      @expense_filter_performance = @expense_filter_result.performance_metrics

      # Log metadata for debugging
      Rails.logger.debug "Dashboard loaded - Filters applied: #{@expense_filter_result.metadata[:filters_applied]}, Total expenses: #{@expense_filter_result.total_count}"
    else
      # Fallback to basic recent expenses if filter service fails
      @recent_expenses = dashboard_data[:recent_expenses]
      @expense_view_mode = "compact"
      Rails.logger.error "Dashboard filter service failed with metadata: #{@expense_filter_result.metadata.inspect}, using fallback"
    end

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

    # Load categories once for expense row partials (avoids N+1 queries)
    @categories = Category.all.order(:name)

    # Handle AJAX requests for partial updates (Task 3.6)
    if request.xhr? && params[:partial] == "expenses_list"
      render partial: "expenses/dashboard_expense_list", locals: {
        recent_expenses: @recent_expenses,
        expense_view_mode: @expense_view_mode,
        expense_filter_result: @expense_filter_result,
        categories: @categories
      }
    end
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
      # Ensure the category exists (using id: to be explicit for Brakeman)
      unless Category.exists?(id: new_category_id)
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
        format.json {
          render json: {
            success: true,
            expense: expense_json(@expense),
            color: @expense.category&.color
          }
        }
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

  # PATCH /expenses/:id/update_status
  def update_status
    new_status = params[:status]

    # Validate status parameter
    unless %w[pending processed failed duplicate].include?(new_status)
      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, alert: "Estado inválido") }
        format.json { render json: { success: false, error: "Invalid status" }, status: :unprocessable_content }
      end
      return
    end

    if @expense.update(status: new_status)
      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, notice: "Estado actualizado exitosamente") }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("expense_#{@expense.id}_status", partial: "expenses/status_badge", locals: { expense: @expense }),
            turbo_stream.replace("expense_#{@expense.id}_actions", partial: "expenses/inline_actions", locals: { expense: @expense })
          ]
        end
        format.json { render json: { success: true, expense: expense_json(@expense) } }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, alert: "Error al actualizar el estado") }
        format.json { render json: { success: false, errors: @expense.errors.full_messages }, status: :unprocessable_content }
      end
    end
  rescue StandardError => e
    Rails.logger.error "Error updating expense status: #{e.message}"
    respond_to do |format|
      format.html { redirect_back(fallback_location: @expense, alert: "Error al actualizar el estado") }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  # GET /expenses/virtual_scroll
  # Endpoint for Task 3.7: Virtual Scrolling with cursor-based pagination
  def virtual_scroll
    # Use cursor-based pagination for efficient virtual scrolling
    filter_params_with_cursor = params.permit(
      :cursor, :per_page, :view_mode,
      :search_query, :status, :period,
      :min_amount, :max_amount,
      :sort_by, :sort_direction,
      category_ids: [], banks: []
    ).to_h.merge(
      account_ids: current_user_email_accounts.pluck(:id),
      use_cursor: true,
      per_page: params[:per_page] || 30,  # Default 30 items per request
      include_summary: false,  # No summary needed for virtual scroll
      include_quick_filters: false  # No filters needed for virtual scroll
    )

    # Use Services::DashboardExpenseFilterService with cursor pagination
    filter_service = Services::DashboardExpenseFilterService.new(filter_params_with_cursor)
    result = filter_service.call

    if result.success?
      # Format response for virtual scrolling
      render json: {
        expenses: result.expenses.map { |e| expense_json_for_virtual_scroll(e) },
        total_count: result.total_count,
        has_more: result.metadata[:has_more],
        next_cursor: result.metadata[:next_cursor],
        performance: {
          query_time_ms: result.performance_metrics[:query_time_ms],
          index_used: result.performance_metrics[:index_used]
        }
      }
    else
      render json: {
        error: "Error loading expenses",
        message: result.metadata[:error]
      }, status: :internal_server_error
    end
  end

  # POST /expenses/:id/duplicate
  def duplicate
    # Create a duplicate of the expense
    duplicated_expense = @expense.dup

    # Reset certain attributes for the duplicate
    duplicated_expense.transaction_date = Date.current
    duplicated_expense.status = :pending
    duplicated_expense.ml_confidence = nil
    duplicated_expense.ml_suggested_category_id = nil
    duplicated_expense.ml_confidence_explanation = nil
    duplicated_expense.ml_correction_count = 0
    duplicated_expense.ml_last_corrected_at = nil

    if duplicated_expense.save
      @categories = Category.all.order(:name)
      respond_to do |format|
        format.html { redirect_to duplicated_expense, notice: "Gasto duplicado exitosamente" }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend("expenses_table_body", partial: "expenses/expense_row", locals: { expense: duplicated_expense, categories: @categories }),
            turbo_stream.update("flash_messages", partial: "shared/flash", locals: { notice: "Gasto duplicado exitosamente" })
          ]
        end
        format.json { render json: { success: true, expense: expense_json(duplicated_expense) } }
      end
    else
      respond_to do |format|
        format.html { redirect_back(fallback_location: @expense, alert: "Error al duplicar el gasto") }
        format.json { render json: { success: false, errors: duplicated_expense.errors.full_messages }, status: :unprocessable_content }
      end
    end
  rescue StandardError => e
    Rails.logger.error "Error duplicating expense: #{e.message}"
    respond_to do |format|
      format.html { redirect_back(fallback_location: @expense, alert: "Error al duplicar el gasto") }
      format.json { render json: { success: false, error: e.message }, status: :internal_server_error }
    end
  end

  # POST /expenses/bulk_categorize
  def bulk_categorize
    return unless authorize_bulk_operation!

    # Use strong parameters
    permitted = bulk_categorize_params

    # Use the new service object for better performance and organization
    service = Services::BulkOperations::CategorizationService.new(
      expense_ids: permitted[:expense_ids],
      category_id: permitted[:category_id],
      user: current_user_for_bulk_operations,
      options: {
        broadcast_updates: true,
        track_ml_corrections: true
      }
    )

    result = service.call

    if result[:success]
      render json: {
        success: true,
        message: result[:message],
        affected_count: result[:affected_count],
        failures: result[:failures],
        background: result[:background],
        job_id: result[:job_id]
      }
    else
      render json: {
        success: false,
        message: result[:message] || "Error al categorizar gastos",
        errors: result[:errors]
      }, status: :unprocessable_content
    end
  end

  # POST /expenses/bulk_update_status
  def bulk_update_status
    return unless authorize_bulk_operation!

    # Use strong parameters
    permitted = bulk_status_params

    # Use the new service object for better performance
    service = Services::BulkOperations::StatusUpdateService.new(
      expense_ids: permitted[:expense_ids],
      status: permitted[:status],
      user: current_user_for_bulk_operations,
      options: {
        broadcast_updates: true
      }
    )

    result = service.call

    if result[:success]
      render json: {
        success: true,
        message: result[:message],
        affected_count: result[:affected_count],
        failures: result[:failures],
        background: result[:background],
        job_id: result[:job_id]
      }
    else
      render json: {
        success: false,
        message: result[:message] || "Error al actualizar estado",
        errors: result[:errors]
      }, status: :unprocessable_content
    end
  end

  # DELETE /expenses/bulk_destroy
  def bulk_destroy
    return unless authorize_bulk_operation!

    # Use strong parameters
    permitted = bulk_destroy_params

    # Use the new service object for better performance
    service = Services::BulkOperations::DeletionService.new(
      expense_ids: permitted[:expense_ids],
      user: current_user_for_bulk_operations,
      options: {
        broadcast_updates: true,
        skip_callbacks: false # Ensure callbacks run for audit trail
      }
    )

    result = service.call

    if result[:success]
      render json: {
        success: true,
        message: result[:message],
        affected_count: result[:affected_count],
        failures: result[:failures],
        reload: false, # Don't reload to preserve undo notification
        background: result[:background],
        job_id: result[:job_id],
        undo_id: result[:undo_id],
        undo_time_remaining: result[:undo_time_remaining]
      }
    else
      render json: {
        success: false,
        message: result[:message] || "Error al eliminar gastos",
        errors: result[:errors]
      }, status: :unprocessable_content
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
    # Admin users see all email accounts (no User model for per-user scoping yet).
    # When user-level data isolation is added, scope to current_user's accounts.
    @current_user_email_accounts ||= EmailAccount.all
  end

  def expense_params
    params.require(:expense).permit(:amount, :currency, :transaction_date, :merchant_name, :description, :category_id, :email_account_id, :notes)
  end

  # Strong parameters for bulk operations
  def bulk_categorize_params
    params.permit(:category_id, expense_ids: [])
  end

  def bulk_status_params
    params.permit(:status, expense_ids: [])
  end

  def bulk_destroy_params
    params.permit(expense_ids: [])
  end

  def current_user_for_bulk_operations
    current_user
  end

  def filter_params
    params.permit(
      :date_range, :start_date, :end_date, :date_from, :date_to,
      :search_query, :status, :period,
      :min_amount, :max_amount,
      :sort_by, :sort_direction,
      :page, :per_page, :cursor, :use_cursor,
      :category, :bank, # Single value filters
      category_ids: [], banks: [] # Array filters
    ).tap do |p|
      # Convert single value filters to arrays if needed
      if params[:category].present? && !p[:category_ids].present?
        # Convert category name to ID
        category = Category.find_by(name: params[:category])
        p[:category_ids] = category ? [ category.id ] : []
      end
      p[:banks] = [ params[:bank] ] if params[:bank].present? && !p[:banks].present?
    end
  end

  def expense_json(expense)
    {
      id: expense.id,
      amount: expense.amount.to_f.to_s,
      description: expense.description,
      merchant_name: expense.merchant_name,
      status: expense.status,
      transaction_date: expense.transaction_date,
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

  def expense_json_for_virtual_scroll(expense)
    # Optimized JSON for virtual scrolling with minimal data
    {
      id: expense.id,
      merchant_name: expense.merchant_name,
      amount: expense.amount.to_f,
      currency: expense.currency,
      transaction_date: expense.transaction_date.to_s,
      status: expense.status,
      bank_name: expense.bank_name,
      description: expense.description&.truncate(100),  # Truncate for performance
      created_at: expense.created_at.to_s,
      category: expense.category ? {
        id: expense.category.id,
        name: expense.category.name,
        color: expense.category.color
      } : nil,
      ml_confidence: expense.ml_confidence
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

  def calculate_summary_from_result(result)
    # Extract summary statistics from the filtered result
    if result.expenses.any?
      @total_amount = result.expenses.sum(&:amount)
      @expense_count = result.total_count || result.expenses.count

      # Group by category for summary
      @categories_summary = result.expenses
        .group_by { |e| e.category&.name || "Uncategorized" }
        .transform_values { |expenses| expenses.sum(&:amount) }
        .sort_by { |_, amount| -amount }
    else
      @total_amount = 0
      @expense_count = 0
      @categories_summary = []
    end
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

  def authorize_bulk_operation!
    unless user_signed_in?
      respond_to do |format|
        format.json { render json: { success: false, message: "No autorizado" }, status: :unauthorized }
        format.html { redirect_to root_path, alert: "No autorizado" }
      end
      return false
    end
    true
  end

  def execute_bulk_operation(expense_ids)
    # Find expenses that belong to the user
    expenses = current_user_expenses.where(id: expense_ids)

    # Check if all requested expenses were found
    if expenses.count != expense_ids.length
      missing_count = expense_ids.length - expenses.count
      return {
        success: false,
        message: "#{missing_count} gastos no encontrados o no autorizados",
        errors: [ "Algunos gastos no fueron encontrados o no tienes permiso para modificarlos" ]
      }
    end

    # Execute operation in transaction for data consistency
    result = nil
    ActiveRecord::Base.transaction do
      result = yield(expenses)
    end

    # Process result
    if result.is_a?(Hash) && result[:success_count]
      {
        success: true,
        affected_count: result[:success_count],
        failures: result[:failures] || []
      }
    elsif result.is_a?(Hash) && result[:success]
      result
    else
      {
        success: true,
        affected_count: expenses.count,
        failures: []
      }
    end
  rescue => e
    Rails.logger.error "Bulk operation error: #{e.message}"
    {
      success: false,
      message: "Error al procesar la operación",
      errors: [ e.message ]
    }
  end
end
