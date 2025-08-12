# frozen_string_literal: true

# Budget model for tracking spending limits and goals
# Supports multiple periods and category-specific budgets
# SECURITY: All budgets are scoped to email_accounts for data isolation
class Budget < ApplicationRecord
  # Enums
  enum :period, {
    daily: 0,
    weekly: 1,
    monthly: 2,
    yearly: 3
  }, prefix: true

  # Associations
  belongs_to :email_account
  belongs_to :category, optional: true

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :period, presence: true
  validates :start_date, presence: true, on: :update
  validates :currency, presence: true, inclusion: { in: %w[CRC USD EUR] }, on: :update
  validates :warning_threshold, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :critical_threshold, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validate :thresholds_order
  validate :end_date_after_start_date
  validate :unique_active_budget_per_scope

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :current, -> { active.where("start_date <= ? AND (end_date IS NULL OR end_date >= ?)", Date.current, Date.current) }
  scope :for_category, ->(category_id) { where(category_id: category_id) }
  scope :general, -> { where(category_id: nil) }
  # Optimized scopes that use precomputed values instead of divisions in WHERE clause
  scope :exceeded, -> { where("current_spend > amount") }
  scope :warning, -> { where("current_spend >= (amount * warning_threshold / 100.0)") }
  scope :critical, -> { where("current_spend >= (amount * critical_threshold / 100.0)") }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_create :calculate_current_spend_after_save
  after_update :recalculate_if_needed

  # Class methods
  def self.for_period_containing(date, period_type)
    case period_type.to_sym
    when :daily
      where("start_date <= ? AND (end_date IS NULL OR end_date >= ?)", date, date)
    when :weekly
      week_start = date.beginning_of_week
      week_end = date.end_of_week
      where("start_date <= ? AND (end_date IS NULL OR end_date >= ?)", week_end, week_start)
    when :monthly
      month_start = date.beginning_of_month
      month_end = date.end_of_month
      where("start_date <= ? AND (end_date IS NULL OR end_date >= ?)", month_end, month_start)
    when :yearly
      year_start = date.beginning_of_year
      year_end = date.end_of_year
      where("start_date <= ? AND (end_date IS NULL OR end_date >= ?)", year_end, year_start)
    else
      none
    end
  end

  # Instance methods

  # Calculate the current period's date range based on budget period type
  def current_period_range
    reference_date = Date.current

    case period.to_sym
    when :daily
      reference_date.beginning_of_day..reference_date.end_of_day
    when :weekly
      reference_date.beginning_of_week..reference_date.end_of_week
    when :monthly
      reference_date.beginning_of_month..reference_date.end_of_month
    when :yearly
      reference_date.beginning_of_year..reference_date.end_of_year
    else
      raise "Invalid period: #{period}"
    end
  end

  # Calculate actual spending for the current period
  def calculate_current_spend!
    return 0.0 unless active?

    date_range = current_period_range

    # Base query for expenses in the period with eager loading
    expenses_query = email_account.expenses
      .includes(:category)
      .where(transaction_date: date_range)
      .where(currency: currency_to_expense_currency)

    # Filter by category if this is a category-specific budget
    expenses_query = expenses_query.where(category_id: category_id) if category_id.present?

    # Calculate and cache the spend
    spend = expenses_query.sum(:amount).to_f

    # Update the budget record with cached values
    update_columns(
      current_spend: spend,
      current_spend_updated_at: Time.current
    )

    # Track if budget was exceeded
    check_and_track_exceeded(spend)

    spend
  end

  # Get current spend (use cached value if recent, otherwise recalculate)
  def current_spend_amount
    # Recalculate if cache is older than 1 hour or never calculated
    if current_spend_updated_at.nil? || current_spend_updated_at < 1.hour.ago
      calculate_current_spend!
    else
      current_spend
    end
  end

  # Calculate the percentage of budget used
  def usage_percentage
    return 0.0 if amount.zero?
    ((current_spend_amount / amount) * 100).round(1)
  end

  # Calculate remaining budget
  def remaining_amount
    amount - current_spend_amount
  end

  # Check budget status and return appropriate color/status
  def status
    percentage = usage_percentage

    if percentage >= 100
      :exceeded
    elsif percentage >= critical_threshold
      :critical
    elsif percentage >= warning_threshold
      :warning
    else
      :good
    end
  end

  # Get the status color based on current usage
  def status_color
    case status
    when :exceeded
      "rose-600"    # Red for exceeded
    when :critical
      "rose-500"    # Light red for critical
    when :warning
      "amber-600"   # Yellow for warning
    else
      "emerald-600" # Green for good
    end
  end

  # Get status message in Spanish
  def status_message
    case status
    when :exceeded
      "Presupuesto excedido"
    when :critical
      "Cerca del límite"
    when :warning
      "Atención requerida"
    else
      "Dentro del presupuesto"
    end
  end

  # Check if budget is on track for the period
  def on_track?
    return true if usage_percentage < 50 # Simple rule: less than 50% used is on track

    # More sophisticated tracking based on time elapsed in period
    elapsed_percentage = period_elapsed_percentage
    usage_percentage <= (elapsed_percentage + 10) # Allow 10% buffer
  end

  # Calculate how much of the current period has elapsed
  def period_elapsed_percentage
    range = current_period_range
    total_days = (range.end.to_date - range.begin.to_date).to_i + 1
    elapsed_days = (Date.current - range.begin.to_date).to_i + 1

    return 100.0 if elapsed_days >= total_days
    ((elapsed_days.to_f / total_days) * 100).round(1)
  end

  # Get historical adherence for the last N periods
  def historical_adherence(periods_count = 6)
    # This would query historical expense data
    # For now, return a simple structure
    {
      periods_analyzed: periods_count,
      times_exceeded: times_exceeded,
      average_usage: 85.0, # Placeholder - would calculate from historical data
      trend: :improving    # Placeholder - would analyze trend
    }
  end

  # Format amount for display
  def formatted_amount
    ActionController::Base.helpers.number_to_currency(
      amount,
      unit: currency_symbol,
      separator: ",",
      delimiter: ".",
      precision: 0
    )
  end

  # Format remaining amount for display
  def formatted_remaining
    ActionController::Base.helpers.number_to_currency(
      remaining_amount.abs,
      unit: currency_symbol,
      separator: ",",
      delimiter: ".",
      precision: 0
    )
  end

  # Get the appropriate currency symbol
  def currency_symbol
    case currency
    when "CRC"
      "₡"
    when "USD"
      "$"
    when "EUR"
      "€"
    else
      currency
    end
  end

  # Deactivate this budget
  def deactivate!
    update!(active: false)
  end

  # Duplicate budget for next period
  def duplicate_for_next_period
    next_start = calculate_next_period_start

    self.class.create!(
      email_account: email_account,
      category: category,
      name: name,
      description: description,
      period: period,
      amount: amount,
      currency: currency,
      start_date: next_start,
      end_date: end_date ? next_start + (end_date - start_date) : nil,
      warning_threshold: warning_threshold,
      critical_threshold: critical_threshold,
      notify_on_warning: notify_on_warning,
      notify_on_critical: notify_on_critical,
      notify_on_exceeded: notify_on_exceeded,
      rollover_enabled: rollover_enabled,
      active: true
    )
  end

  private

  def set_defaults
    self.start_date ||= Date.current
    self.currency ||= "CRC"
    self.warning_threshold ||= 70
    self.critical_threshold ||= 90
  end

  def thresholds_order
    return unless warning_threshold && critical_threshold

    if warning_threshold >= critical_threshold
      errors.add(:warning_threshold, "debe ser menor que el umbral crítico")
    end
  end

  def end_date_after_start_date
    return unless start_date && end_date

    if end_date < start_date
      errors.add(:end_date, "debe ser posterior a la fecha de inicio")
    end
  end

  def unique_active_budget_per_scope
    return unless active?

    existing = self.class
      .active
      .where(email_account_id: email_account_id)
      .where(period: period)
      .where(category_id: category_id)

    existing = existing.where.not(id: id) if persisted?

    if existing.exists?
      errors.add(:base, "Ya existe un presupuesto activo para este período y categoría")
    end
  end

  def currency_to_expense_currency
    # Map budget currency to expense currency enum value using Expense enum
    case currency
    when "CRC"
      Expense.currencies[:crc]
    when "USD"
      Expense.currencies[:usd]
    when "EUR"
      Expense.currencies[:eur]
    else
      Expense.currencies[:crc] # Default to CRC
    end
  end

  def check_and_track_exceeded(spend)
    if spend > amount && last_exceeded_at.nil?
      update_columns(
        times_exceeded: times_exceeded + 1,
        last_exceeded_at: Time.current
      )
    elsif spend <= amount && last_exceeded_at.present?
      # Reset if back under budget
      update_columns(last_exceeded_at: nil)
    end
  end

  def calculate_next_period_start
    case period.to_sym
    when :daily
      start_date + 1.day
    when :weekly
      start_date + 1.week
    when :monthly
      start_date + 1.month
    when :yearly
      start_date + 1.year
    else
      start_date
    end
  end

  def calculate_current_spend_after_save
    # Guard against infinite recursion with flag
    return if @calculating_spend

    @calculating_spend = true
    calculate_current_spend!
  ensure
    @calculating_spend = false
  end

  def recalculate_if_needed
    # Guard against infinite recursion and only recalculate on significant changes
    return if @calculating_spend

    if saved_change_to_active? || saved_change_to_category_id? || saved_change_to_period?
      begin
        @calculating_spend = true
        calculate_current_spend!
      ensure
        @calculating_spend = false
      end
    end
  end
end
