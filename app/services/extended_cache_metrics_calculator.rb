# frozen_string_literal: true

# Extended metrics calculator with configurable cache expiration
# Used by background jobs to set longer cache times for pre-calculated metrics
class ExtendedCacheMetricsCalculator < MetricsCalculator
  attr_reader :cache_hours

  def initialize(email_account:, period: :month, reference_date: Date.current, cache_hours: 4)
    Rails.logger.debug "ExtendedCacheMetricsCalculator.initialize called with cache_hours: #{cache_hours}"
    @cache_hours = cache_hours
    # Only pass parameters that the parent class accepts
    super(email_account: email_account, period: period, reference_date: reference_date)
  end

  def calculate
    # Use longer cache expiration for background-calculated metrics
    Rails.cache.fetch(cache_key, expires_in: cache_hours.hours) do
      benchmark_calculation do
        {
          period: period,
          reference_date: reference_date,
          date_range: date_range,
          metrics: calculate_metrics,
          trends: calculate_trends,
          category_breakdown: calculate_category_breakdown,
          daily_breakdown: calculate_daily_breakdown,
          trend_data: calculate_trend_data,
          budgets: calculate_budget_data,
          calculated_at: Time.current,
          background_calculated: true # Mark as background-calculated
        }
      end
    end
  rescue StandardError => e
    handle_calculation_error(e)
  end
end
