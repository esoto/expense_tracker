# frozen_string_literal: true

# Controller for managing budgets and spending goals
# SECURITY: All budgets are scoped to scoping_user for data isolation (PR 6).
class BudgetsController < ApplicationController
  before_action :set_budget, only: [ :show, :edit, :update, :destroy ]

  # GET /budgets
  def index
    @budgets = Budget.for_user(scoping_user)
      .includes(:category)
      .order(active: :desc, period: :asc, created_at: :desc)

    # Group budgets by period for better display
    @budgets_by_period = @budgets.group_by(&:period)

    # Calculate overall budget health
    @overall_health = calculate_overall_budget_health

    # Precompute category options for unmapped external budgets to avoid N+1 queries
    @category_options = Category.all.distinct.to_a

    # Whether an active external budget source (e.g., salary_calculator) is linked.
    # Drives the empty-state CTA and sync-in-progress messaging.
    email_account = scoping_user.email_accounts.first
    @has_external_source = email_account&.external_budget_source&.active? || false
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
    email_account = scoping_user.email_accounts.first
    @budget = Budget.new(
      user: scoping_user,
      email_account: email_account,
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
    @budget = Budget.new(budget_params)
    @budget.user = scoping_user

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
    original = Budget.for_user(scoping_user).find(params[:id])
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
    budget = Budget.for_user(scoping_user).find(params[:id])
    budget.deactivate!

    redirect_to budgets_path,
      notice: "Presupuesto desactivado exitosamente."
  end

  # GET /budgets/quick_set
  # Quick budget setting from dashboard
  def quick_set
    @period = params[:period] || "monthly"
    email_account = scoping_user.email_accounts.first
    @suggested_amount = calculate_suggested_budget_amount(@period, email_account)

    @budget = Budget.new(
      user: scoping_user,
      email_account: email_account,
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

  def set_budget
    @budget = Budget.for_user(scoping_user).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to budgets_path, alert: "Presupuesto no encontrado."
  end

  def budget_params
    permitted = params.require(:budget).permit(
      :name, :description, :category_id, :period, :amount, :currency,
      :start_date, :end_date, :warning_threshold, :critical_threshold,
      :notify_on_warning, :notify_on_critical, :notify_on_exceeded,
      :rollover_enabled, :active, :email_account_id
    )
    # Drop user_id if someone tries to forge it via params.
    permitted.delete(:user_id) if permitted.key?(:user_id)
    # Validate email_account_id belongs to scoping_user; nullify if forged.
    if permitted[:email_account_id].present? &&
       !scoping_user.email_accounts.exists?(id: permitted[:email_account_id])
      permitted[:email_account_id] = nil
    end
    permitted
  end

  def calculate_overall_budget_health
    active_budgets = Budget.for_user(scoping_user).active.current
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

  def calculate_suggested_budget_amount(period, email_account)
    return 0 unless email_account

    # Calculate average spending for the last 3 periods
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
    average_spend = email_account.expenses
      .where(transaction_date: start_date.beginning_of_day..Date.current.end_of_day)
      .average(:amount) || 0

    # Suggest 10% more than average to provide some buffer
    (average_spend * 1.1).round(-3) # Round to nearest thousand
  end

  def scoping_user
    @scoping_user ||= begin
      user = try(:current_app_user)
      if user.nil?
        user = User.admin.first
        Rails.logger.warn(
          "[scoping_user] current_app_user is nil; falling back to User.admin.first " \
          "(controller=#{self.class.name}, path=#{request.fullpath}). " \
          "This path disappears in PR 12 when UserAuthentication gates all controllers."
        ) if user
      end
      user || raise("No authenticated user and no admin User found")
    end
  end
end
