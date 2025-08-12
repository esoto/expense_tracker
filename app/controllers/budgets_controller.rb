# frozen_string_literal: true

# Controller for managing budgets and spending goals
# SECURITY: All budgets are scoped to email_accounts for data isolation
class BudgetsController < ApplicationController
  before_action :set_email_account
  before_action :set_budget, only: [ :show, :edit, :update, :destroy ]

  # GET /budgets
  def index
    @budgets = @email_account.budgets
      .includes(:category)
      .order(active: :desc, period: :asc, created_at: :desc)

    # Group budgets by period for better display
    @budgets_by_period = @budgets.group_by(&:period)

    # Calculate overall budget health
    @overall_health = calculate_overall_budget_health
  end

  # GET /budgets/1
  def show
    # Calculate detailed statistics for this budget
    @budget_stats = {
      current_spend: @budget.current_spend_amount,
      usage_percentage: @budget.usage_percentage,
      remaining: @budget.remaining_amount,
      days_remaining: days_remaining_in_period(@budget),
      daily_average_needed: calculate_daily_average_needed(@budget),
      historical_data: @budget.historical_adherence(6)
    }
  end

  # GET /budgets/new
  def new
    @budget = @email_account.budgets.build(
      start_date: Date.current,
      period: "monthly",
      currency: "CRC",
      warning_threshold: 70,
      critical_threshold: 90
    )
    @categories = Category.all.order(:name)
  end

  # GET /budgets/1/edit
  def edit
    @categories = Category.all.order(:name)
  end

  # POST /budgets
  def create
    @budget = @email_account.budgets.build(budget_params)

    if @budget.save
      # Calculate initial spend
      @budget.calculate_current_spend!

      redirect_to dashboard_expenses_path,
        notice: "Presupuesto creado exitosamente."
    else
      @categories = Category.all.order(:name)
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /budgets/1
  def update
    if @budget.update(budget_params)
      # Recalculate spend after update
      @budget.calculate_current_spend!

      redirect_to dashboard_expenses_path,
        notice: "Presupuesto actualizado exitosamente."
    else
      @categories = Category.all.order(:name)
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /budgets/1
  def destroy
    @budget.destroy
    redirect_to budgets_path,
      notice: "Presupuesto eliminado exitosamente."
  end

  # POST /budgets/1/duplicate
  def duplicate
    original = @email_account.budgets.find(params[:id])
    new_budget = original.duplicate_for_next_period

    if new_budget.persisted?
      redirect_to edit_budget_path(new_budget),
        notice: "Presupuesto duplicado exitosamente. Puedes ajustar los valores según necesites."
    else
      redirect_to budgets_path,
        alert: "No se pudo duplicar el presupuesto."
    end
  end

  # POST /budgets/1/deactivate
  def deactivate
    budget = @email_account.budgets.find(params[:id])
    budget.deactivate!

    redirect_to budgets_path,
      notice: "Presupuesto desactivado exitosamente."
  end

  # GET /budgets/quick_set
  # Quick budget setting from dashboard
  def quick_set
    @period = params[:period] || "monthly"
    @suggested_amount = calculate_suggested_budget_amount(@period)

    @budget = @email_account.budgets.build(
      period: @period,
      amount: @suggested_amount,
      currency: "CRC",
      start_date: Date.current,
      name: "Presupuesto #{I18n.t("budgets.periods.#{@period}")}",
      warning_threshold: 70,
      critical_threshold: 90
    )

    respond_to do |format|
      format.html { render partial: "quick_set_form" }
      format.turbo_stream
    end
  end

  private

  def set_email_account
    # Use the first active email account for now
    # In a multi-user system, this would be scoped to current_user
    @email_account = EmailAccount.active.first

    unless @email_account
      redirect_to root_path,
        alert: "Debes configurar una cuenta de correo primero."
    end
  end

  def set_budget
    @budget = @email_account.budgets.find(params[:id])
  end

  def budget_params
    params.require(:budget).permit(
      :name, :description, :category_id, :period, :amount, :currency,
      :start_date, :end_date, :warning_threshold, :critical_threshold,
      :notify_on_warning, :notify_on_critical, :notify_on_exceeded,
      :rollover_enabled, :active
    )
  end

  def calculate_overall_budget_health
    active_budgets = @email_account.budgets.active.current
    return { status: :no_budgets, message: "Sin presupuestos activos" } if active_budgets.empty?

    total_budget = active_budgets.sum(:amount)
    total_spend = active_budgets.sum(:current_spend)

    usage_percentage = total_budget.zero? ? 0 : ((total_spend / total_budget) * 100).round(1)

    status = if usage_percentage >= 100
      :exceeded
    elsif usage_percentage >= 90
      :critical
    elsif usage_percentage >= 70
      :warning
    else
      :good
    end

    {
      status: status,
      usage_percentage: usage_percentage,
      total_budget: total_budget,
      total_spend: total_spend,
      message: status_message_for_health(status, usage_percentage)
    }
  end

  def status_message_for_health(status, percentage)
    case status
    when :exceeded
      "Has excedido tu presupuesto (#{percentage}%)"
    when :critical
      "Estás muy cerca del límite (#{percentage}%)"
    when :warning
      "Atención: #{percentage}% del presupuesto usado"
    when :good
      "Vas bien: #{percentage}% del presupuesto usado"
    else
      "Sin presupuestos activos"
    end
  end

  def days_remaining_in_period(budget)
    range = budget.current_period_range
    (range.end.to_date - Date.current).to_i
  end

  def calculate_daily_average_needed(budget)
    days_left = days_remaining_in_period(budget)
    return 0 if days_left <= 0

    remaining = budget.remaining_amount
    return 0 if remaining <= 0

    (remaining / days_left).round(2)
  end

  def calculate_suggested_budget_amount(period)
    # Calculate average spending for the last 3 periods
    # This provides a data-driven suggestion for the budget amount

    case period.to_sym
    when :daily
      lookback_days = 7
    when :weekly
      lookback_days = 21
    when :monthly
      lookback_days = 90
    when :yearly
      lookback_days = 365
    else
      lookback_days = 30
    end

    start_date = Date.current - lookback_days.days
    average_spend = @email_account.expenses
      .where(transaction_date: start_date..Date.current)
      .average(:amount) || 0

    # Suggest 10% more than average to provide some buffer
    (average_spend * 1.1).round(-3) # Round to nearest thousand
  end
end
