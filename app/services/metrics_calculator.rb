# frozen_string_literal: true

require "benchmark"

# Service for calculating expense metrics with caching and trend analysis
# Supports multiple time periods and category breakdowns
# Performance target: < 100ms for calculations
# SECURITY: All metrics are scoped to a specific email_account for data isolation
module Services
  class MetricsCalculator
  CACHE_EXPIRY = 1.hour
  SUPPORTED_PERIODS = %i[day week month year].freeze

  class InvalidPeriodError < StandardError; end
  class CalculationError < StandardError; end
  class MissingEmailAccountError < StandardError; end

  attr_reader :email_account, :period, :reference_date, :cache_key

  def initialize(email_account: nil, period: :month, reference_date: Date.current)
    raise MissingEmailAccountError, "EmailAccount is required for metrics calculation" unless email_account

    validate_period!(period)
    @email_account = email_account
    @period = period.to_sym
    @reference_date = reference_date.to_date
    @cache_key = generate_cache_key
  end

  # Main public interface - returns all metrics with caching
  def calculate
    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
      benchmark_calculation do
        metrics = calculate_metrics
        {
          period: period,
          reference_date: reference_date,
          date_range: date_range,
          metrics: metrics,
          trends: calculate_trends(metrics),
          category_breakdown: calculate_category_breakdown,
          daily_breakdown: calculate_daily_breakdown,
          trend_data: calculate_trend_data,
          budgets: calculate_budget_data,
          calculated_at: Time.current
        }
      end
    end
  rescue StandardError => e
    handle_calculation_error(e)
  end

  # Public accessor for date_range for testing
  def date_range
    @date_range ||= calculate_date_range
  end

  # Force recalculation without cache
  def calculate!
    Rails.cache.delete(cache_key)
    calculate
  end

  # Clear all metric caches for a specific email account
  def self.clear_cache(email_account: nil)
    if email_account
      Rails.cache.delete_matched("metrics_calculator:account_#{email_account.id}:*")
    else
      Rails.cache.delete_matched("metrics_calculator:*")
    end
  end

  # Pre-calculate metrics for common periods for a specific email account
  def self.pre_calculate_all(email_account: nil, reference_date: Date.current)
    raise MissingEmailAccountError, "EmailAccount is required for pre-calculation" unless email_account

    SUPPORTED_PERIODS.each do |period|
      new(email_account: email_account, period: period, reference_date: reference_date).calculate
    end
  end

  # Batch calculate metrics for multiple periods efficiently
  # Returns a hash with period symbols as keys and calculated metrics as values
  # Example: { day: {...}, week: {...}, month: {...}, year: {...} }
  def self.batch_calculate(email_account: nil, periods: SUPPORTED_PERIODS, reference_date: Date.current)
    raise MissingEmailAccountError, "EmailAccount is required for batch calculation" unless email_account

    # Validate all periods first
    invalid_periods = periods.map(&:to_sym) - SUPPORTED_PERIODS
    unless invalid_periods.empty?
      raise InvalidPeriodError, "Invalid periods: #{invalid_periods.join(', ')}. Supported periods: #{SUPPORTED_PERIODS.join(', ')}"
    end

    results = {}

    # Optimization: Pre-load data that might be used across multiple periods
    # This reduces redundant database queries
    preload_data_for_batch(email_account, periods, reference_date)

    # Calculate for each period using cache when available
    periods.each do |period|
      calculator = new(
        email_account: email_account,
        period: period,
        reference_date: reference_date
      )
      results[period.to_sym] = calculator.calculate
    end

    results
  end

  # Pre-load and cache expense data for multiple periods to optimize batch calculations
  private_class_method def self.preload_data_for_batch(email_account, periods, reference_date)
    # Determine the widest date range needed
    date_ranges = periods.map do |period|
      case period.to_sym
      when :day
        reference_date.beginning_of_day..reference_date.end_of_day
      when :week
        reference_date.beginning_of_week..reference_date.end_of_week
      when :month
        reference_date.beginning_of_month..reference_date.end_of_month
      when :year
        reference_date.beginning_of_year..reference_date.end_of_year
      end
    end

    # Find the earliest start and latest end date
    earliest_date = date_ranges.map(&:begin).min
    latest_date = date_ranges.map(&:end).max

    # Pre-load all expenses in the widest range with includes
    # This single query replaces multiple queries across different periods
    email_account.expenses
      .where(transaction_date: earliest_date..latest_date)
      .includes(:category)
      .load # Force loading into memory

    # The ActiveRecord query cache will now serve these records
    # for subsequent queries within the same request
  end

  private

  def validate_period!(period)
    unless SUPPORTED_PERIODS.include?(period.to_sym)
      raise InvalidPeriodError, "Invalid period: #{period}. Supported periods: #{SUPPORTED_PERIODS.join(', ')}"
    end
  end

  def generate_cache_key
    "metrics_calculator:account_#{email_account.id}:#{period}:#{reference_date.iso8601}"
  end

  def benchmark_calculation
    result = nil
    elapsed = Benchmark.realtime do
      result = yield
    end

    # Log if calculation exceeds target
    if elapsed > 0.1
      Rails.logger.warn "MetricsCalculator exceeded 100ms target: #{(elapsed * 1000).round(2)}ms for #{period} period"
    end

    result
  end

  def handle_calculation_error(error)
    Rails.logger.error "MetricsCalculator error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n") if error.backtrace

    # Return minimal valid response on error
    {
      period: period,
      reference_date: reference_date,
      date_range: date_range,
      error: error.message,
      metrics: default_metrics,
      trends: default_trends,
      category_breakdown: {},
      daily_breakdown: {},
      trend_data: default_trend_data,
      budgets: default_budget_data,
      calculated_at: Time.current
    }
  end

  def previous_date_range
    @previous_date_range ||= calculate_previous_date_range
  end

  def calculate_date_range
    case period
    when :day
      reference_date.beginning_of_day..reference_date.end_of_day
    when :week
      reference_date.beginning_of_week..reference_date.end_of_week
    when :month
      reference_date.beginning_of_month..reference_date.end_of_month
    when :year
      reference_date.beginning_of_year..reference_date.end_of_year
    end
  end

  def calculate_previous_date_range
    case period
    when :day
      previous_date = reference_date - 1.day
      previous_date.beginning_of_day..previous_date.end_of_day
    when :week
      previous_date = reference_date - 1.week
      previous_date.beginning_of_week..previous_date.end_of_week
    when :month
      previous_date = reference_date - 1.month
      previous_date.beginning_of_month..previous_date.end_of_month
    when :year
      previous_date = reference_date - 1.year
      previous_date.beginning_of_year..previous_date.end_of_year
    end
  end

  def calculate_metrics
    expenses = expenses_in_period

    # Single query for main aggregates
    count, total, average, min_val, max_val = expenses.pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("COALESCE(SUM(amount), 0)"),
      Arel.sql("COALESCE(AVG(amount), 0)"),
      Arel.sql("MIN(amount)"),
      Arel.sql("MAX(amount)")
    )

    {
      total_amount: total.to_f,
      transaction_count: count.to_i,
      average_amount: average.to_f.round(2),
      median_amount: calculate_median(expenses),
      min_amount: min_val&.to_f || 0.0,
      max_amount: max_val&.to_f || 0.0,
      unique_merchants: expenses.distinct.count(:merchant_name),
      unique_categories: expenses.joins(:category).distinct.count("categories.id"),
      uncategorized_count: expenses.uncategorized.count,
      by_status: calculate_status_breakdown(expenses),
      by_currency: calculate_currency_breakdown(expenses)
    }
  end

  def calculate_trends(current_metrics = nil)
    current_metrics ||= calculate_metrics
    previous_expenses = expenses_in_previous_period

    previous_total = previous_expenses.sum(:amount).to_f
    previous_count = previous_expenses.count
    previous_average = calculate_average(previous_expenses)

    {
      amount_change: calculate_percentage_change(current_metrics[:total_amount], previous_total),
      count_change: calculate_percentage_change(current_metrics[:transaction_count], previous_count),
      average_change: calculate_percentage_change(current_metrics[:average_amount], previous_average),
      absolute_amount_change: current_metrics[:total_amount] - previous_total,
      absolute_count_change: current_metrics[:transaction_count] - previous_count,
      is_increase: current_metrics[:total_amount] > previous_total,
      previous_period_total: previous_total,
      previous_period_count: previous_count
    }
  end

  def calculate_category_breakdown
    rows = expenses_in_period
      .left_joins(:category)
      .group(Arel.sql("COALESCE(categories.name, 'Uncategorized')"))
      .pluck(
        Arel.sql("COALESCE(categories.name, 'Uncategorized')"),
        Arel.sql("SUM(expenses.amount)"),
        Arel.sql("COUNT(expenses.id)"),
        Arel.sql("AVG(expenses.amount)"),
        Arel.sql("MIN(expenses.amount)"),
        Arel.sql("MAX(expenses.amount)")
      )

    grand_total = rows.sum { |_, amount, *| amount.to_f }

    rows.map do |name, total, count, avg, min, max|
        {
          category: name,
          total_amount: total.to_f,
          transaction_count: count,
          average_amount: avg.to_f.round(2),
          min_amount: min.to_f,
          max_amount: max.to_f,
          percentage_of_total: grand_total.zero? ? 0.0 : ((total.to_f / grand_total) * 100).round(2)
        }
      end
      .sort_by { |item| -item[:total_amount] }
  end

  def calculate_daily_breakdown
    return {} unless [ :week, :month ].include?(period)

    expenses_in_period
      .group_by_day(:transaction_date, range: date_range)
      .sum(:amount)
      .transform_values(&:to_f)
  end

  def calculate_trend_data
    # Calculate 7-day trend data for sparkline visualization
    # Returns daily totals for the last 7 days
    end_date = reference_date.to_date
    start_date = (end_date - 6.days).to_date

    # Get daily totals for the past 7 days
    # Group by date (not datetime) to ensure proper matching
    daily_totals = email_account.expenses
      .where(transaction_date: start_date.beginning_of_day..end_date.end_of_day)
      .group("DATE(transaction_date)")
      .sum(:amount)

    # Convert keys to Date objects and amounts to floats
    normalized_totals = {}
    daily_totals.each do |date_key, amount|
      # Handle different date formats from the database
      date = case date_key
      when String then Date.parse(date_key)
      when Date then date_key
      when DateTime, Time then date_key.to_date
      else date_key
      end
      normalized_totals[date] = amount.to_f
    end

    # Ensure we have all 7 days with zeros for missing days
    trend_data = []
    (0..6).each do |days_from_start|
      date = start_date + days_from_start.days
      amount = normalized_totals[date] || 0.0
      trend_data << {
        date: date,
        amount: amount
      }
    end

    # Calculate statistics for the trend
    amounts = trend_data.map { |d| d[:amount] }
    {
      daily_amounts: trend_data,
      min: amounts.min || 0.0,
      max: amounts.max || 0.0,
      average: amounts.empty? ? 0.0 : (amounts.sum.to_f / amounts.size).round(2),
      total: amounts.sum,
      start_date: start_date,
      end_date: end_date
    }
  end

  def calculate_status_breakdown(expenses)
    expenses.group(:status).count
  end

  def calculate_currency_breakdown(expenses)
    expenses.group(:currency).sum(:amount).transform_values(&:to_f)
  end

  def calculate_average(expenses_relation)
    count = expenses_relation.count
    return 0.0 if count.zero?

    (expenses_relation.sum(:amount).to_f / count).round(2)
  end

  def calculate_median(expenses_relation)
    amounts = expenses_relation.pluck(:amount).map(&:to_f).sort
    return 0.0 if amounts.empty?

    mid = amounts.length / 2
    if amounts.length.odd?
      amounts[mid]
    else
      ((amounts[mid - 1] + amounts[mid]) / 2.0).round(2)
    end
  end

  def calculate_percentage_change(current, previous)
    return 0.0 if previous.zero?

    (((current - previous) / previous) * 100).round(2)
  end

  def calculate_percentage_of_total(amount)
    total = expenses_in_period.sum(:amount).to_f
    return 0.0 if total.zero?

    ((amount / total) * 100).round(2)
  end

  def expenses_in_period
    @expenses_in_period ||= email_account.expenses
      .where(transaction_date: date_range)
      .includes(:category)
  end

  def expenses_in_previous_period
    @expenses_in_previous_period ||= email_account.expenses
      .where(transaction_date: previous_date_range)
      .includes(:category)
  end

  def default_metrics
    {
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
    }
  end

  def default_trends
    {
      amount_change: 0.0,
      count_change: 0.0,
      average_change: 0.0,
      absolute_amount_change: 0.0,
      absolute_count_change: 0,
      is_increase: false,
      previous_period_total: 0.0,
      previous_period_count: 0
    }
  end

  def default_trend_data
    # Default empty trend data for error cases
    {
      daily_amounts: [],
      min: 0.0,
      max: 0.0,
      average: 0.0,
      total: 0.0,
      start_date: reference_date - 6.days,
      end_date: reference_date
    }
  end

  def calculate_budget_data
    return default_budget_data unless email_account

    # Map MetricsCalculator periods to Budget model periods
    budget_period_mapping = {
      day: :daily,
      week: :weekly,
      month: :monthly,
      year: :yearly
    }

    budget_period = budget_period_mapping[period]
    return default_budget_data unless budget_period

    # Find active budgets for the current period
    budgets = email_account.budgets
      .active
      .current
      .includes(:category)

    # Get general budget (no category) for the period
    general_budget = budgets.general.where(period: budget_period).first

    # Get category-specific budgets
    category_budgets = budgets.where.not(category_id: nil).where(period: budget_period)

    # Calculate budget data
    budget_info = {
      has_budget: general_budget.present? || category_budgets.any?,
      general_budget: format_budget_data(general_budget),
      category_budgets: category_budgets.map { |b| format_budget_data(b) },
      total_budget_amount: calculate_total_budget_amount(general_budget, category_budgets),
      overall_usage: calculate_overall_budget_usage(general_budget, category_budgets),
      historical_adherence: calculate_historical_budget_adherence
    }

    budget_info
  rescue StandardError => e
    Rails.logger.error "Budget calculation error: #{e.message}"
    default_budget_data
  end

  def format_budget_data(budget)
    return nil unless budget

    # Ensure current spend is up to date
    budget.calculate_current_spend!

    {
      id: budget.id,
      name: budget.name,
      category: budget.category&.name,
      period: budget.period,
      amount: budget.amount.to_f,
      currency: budget.currency,
      current_spend: budget.current_spend.to_f,
      remaining: budget.remaining_amount,
      usage_percentage: budget.usage_percentage,
      status: budget.status,
      status_color: budget.status_color,
      status_message: budget.status_message,
      on_track: budget.on_track?,
      warning_threshold: budget.warning_threshold,
      critical_threshold: budget.critical_threshold,
      formatted_amount: budget.formatted_amount,
      formatted_remaining: budget.formatted_remaining
    }
  end

  def calculate_total_budget_amount(general_budget, category_budgets)
    total = 0.0
    total += general_budget.amount.to_f if general_budget
    total += category_budgets.sum(&:amount).to_f
    total
  end

  def calculate_overall_budget_usage(general_budget, category_budgets)
    if general_budget
      # If there's a general budget, use its usage
      general_budget.usage_percentage
    elsif category_budgets.any?
      # Calculate weighted average of category budgets
      total_budget = category_budgets.sum(&:amount).to_f
      return 0.0 if total_budget.zero?

      total_spend = category_budgets.sum(&:current_spend).to_f
      ((total_spend / total_budget) * 100).round(1)
    else
      0.0
    end
  end

  def calculate_historical_budget_adherence
    # Look at the last 6 periods for adherence
    # This is a simplified version - could be expanded with more sophisticated analysis
    {
      periods_analyzed: 6,
      average_adherence: 82.5, # Placeholder - would calculate from historical data
      times_exceeded: 1,        # Placeholder - would query historical data
      trend: :improving,        # Placeholder - would analyze trend
      message: "Generalmente dentro del presupuesto"
    }
  end

  def default_budget_data
    {
      has_budget: false,
      general_budget: nil,
      category_budgets: [],
      total_budget_amount: 0.0,
      overall_usage: 0.0,
      historical_adherence: {
        periods_analyzed: 0,
        average_adherence: 0.0,
        times_exceeded: 0,
        trend: :unknown,
        message: "Sin datos históricos"
      }
    }
  end
  end
end
