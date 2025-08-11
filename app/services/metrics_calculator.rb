# frozen_string_literal: true

require 'benchmark'

# Service for calculating expense metrics with caching and trend analysis
# Supports multiple time periods and category breakdowns
# Performance target: < 100ms for calculations
# SECURITY: All metrics are scoped to a specific email_account for data isolation
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
        {
          period: period,
          reference_date: reference_date,
          date_range: date_range,
          metrics: calculate_metrics,
          trends: calculate_trends,
          category_breakdown: calculate_category_breakdown,
          daily_breakdown: calculate_daily_breakdown,
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
    
    {
      total_amount: expenses.sum(:amount).to_f,
      transaction_count: expenses.count,
      average_amount: calculate_average(expenses),
      median_amount: calculate_median(expenses),
      min_amount: expenses.minimum(:amount)&.to_f || 0.0,
      max_amount: expenses.maximum(:amount)&.to_f || 0.0,
      unique_merchants: expenses.distinct.count(:merchant_name),
      unique_categories: expenses.joins(:category).distinct.count("categories.id"),
      uncategorized_count: expenses.uncategorized.count,
      by_status: calculate_status_breakdown(expenses),
      by_currency: calculate_currency_breakdown(expenses)
    }
  end

  def calculate_trends
    current_metrics = calculate_metrics
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
    expenses_in_period
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
      .map do |name, total, count, avg, min, max|
        {
          category: name,
          total_amount: total.to_f,
          transaction_count: count,
          average_amount: avg.to_f.round(2),
          min_amount: min.to_f,
          max_amount: max.to_f,
          percentage_of_total: calculate_percentage_of_total(total.to_f)
        }
      end
      .sort_by { |item| -item[:total_amount] }
  end

  def calculate_daily_breakdown
    return {} unless [:week, :month].include?(period)
    
    expenses_in_period
      .group_by_day(:transaction_date, range: date_range)
      .sum(:amount)
      .transform_values(&:to_f)
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
end