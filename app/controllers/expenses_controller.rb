class ExpensesController < ApplicationController
  before_action :set_expense, only: [ :show, :edit, :update, :destroy ]

  # GET /expenses
  def index
    @expenses = Expense.includes(:category, :email_account)
                      .order(transaction_date: :desc, created_at: :desc)
                      .limit(25)

    # Filter by category if specified
    @expenses = @expenses.joins(:category).where(categories: { name: params[:category] }) if params[:category].present?

    # Filter by date range if specified
    if params[:start_date].present? && params[:end_date].present?
      @expenses = @expenses.where(transaction_date: params[:start_date]..params[:end_date])
    end

    # Filter by bank if specified
    @expenses = @expenses.where(bank_name: params[:bank]) if params[:bank].present?

    # Summary statistics
    @total_amount = @expenses.sum(:amount)
    @expense_count = @expenses.count
    @categories_summary = @expenses.joins(:category)
                                  .group("categories.name")
                                  .sum(:amount)
                                  .sort_by { |_, amount| -amount }
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
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /expenses/1
  def update
    if @expense.update(expense_params)
      redirect_to @expense, notice: "Gasto actualizado exitosamente."
    else
      @categories = Category.all.order(:name)
      @email_accounts = EmailAccount.all.order(:email)
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /expenses/1
  def destroy
    @expense.destroy
    redirect_to expenses_url, notice: "Gasto eliminado exitosamente."
  end

  # GET /expenses/dashboard
  def dashboard
    @total_expenses = Expense.sum(:amount)
    @expense_count = Expense.count
    @current_month_total = Expense.where(transaction_date: Date.current.beginning_of_month..Date.current.end_of_month).sum(:amount)
    @last_month_total = Expense.where(transaction_date: 1.month.ago.beginning_of_month..1.month.ago.end_of_month).sum(:amount)

    # Recent expenses
    @recent_expenses = Expense.includes(:category).order(transaction_date: :desc, created_at: :desc).limit(10)

    # Category breakdown
    @category_totals = Expense.joins(:category)
                             .group("categories.name")
                             .sum(:amount)
                             .transform_values(&:to_f)
    @sorted_categories = @category_totals.sort_by { |_, amount| -amount }

    # Monthly trend (last 6 months)
    @monthly_data = Expense.where(transaction_date: 6.months.ago.beginning_of_month..Date.current.end_of_month)
                          .group_by_month(:transaction_date)
                          .sum(:amount)
                          .transform_values(&:to_f)

    # Bank breakdown
    @bank_totals = Expense.group(:bank_name).sum(:amount).sort_by { |_, amount| -amount }

    # Top merchants
    @top_merchants = Expense.group(:merchant_name)
                           .sum(:amount)
                           .sort_by { |_, amount| -amount }
                           .first(10)

    # Email accounts and sync status
    @email_accounts = EmailAccount.active.order(:bank_name, :email)
    @last_sync_info = get_last_sync_info
  end

  # POST /expenses/sync_emails
  def sync_emails
    email_account_id = params[:email_account_id]
    
    if email_account_id.present?
      # Sync specific account
      email_account = EmailAccount.find_by(id: email_account_id)
      
      if email_account.nil?
        redirect_to dashboard_expenses_path, alert: "Cuenta de correo no encontrada."
        return
      end
      
      unless email_account.active?
        redirect_to dashboard_expenses_path, alert: "La cuenta de correo está inactiva."
        return
      end
      
      ProcessEmailsJob.perform_later(email_account.id)
      redirect_to dashboard_expenses_path, notice: "Sincronización iniciada para #{email_account.email}. Los nuevos gastos aparecerán en unos momentos."
    else
      # Sync all accounts
      active_accounts = EmailAccount.active.count
      
      if active_accounts == 0
        redirect_to dashboard_expenses_path, alert: "No hay cuentas de correo activas configuradas."
        return
      end
      
      ProcessEmailsJob.perform_later
      redirect_to dashboard_expenses_path, notice: "Sincronización iniciada para #{active_accounts} cuenta#{'s' if active_accounts != 1} de correo. Los nuevos gastos aparecerán en unos momentos."
    end
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

  def get_last_sync_info
    # Get most recent expense from each email account to estimate last sync
    last_expenses = Expense.select('email_account_id, MAX(created_at) as last_created')
                          .group(:email_account_id)
                          .includes(:email_account)
    
    sync_info = {}
    last_expenses.each do |expense|
      sync_info[expense.email_account_id] = {
        last_sync: expense.last_created,
        account: expense.email_account
      }
    end
    
    # Also check for running sync jobs
    running_jobs = SolidQueue::Job.where(
      class_name: 'ProcessEmailsJob',
      finished_at: nil
    ).where('created_at > ?', 5.minutes.ago)
    
    sync_info[:has_running_jobs] = running_jobs.exists?
    sync_info[:running_job_count] = running_jobs.count
    
    sync_info
  end
end
