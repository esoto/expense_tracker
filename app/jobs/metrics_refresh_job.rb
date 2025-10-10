# frozen_string_literal: true

# Job for refreshing metrics when expenses are created, updated, or deleted
# Implements smart debouncing to prevent job flooding on bulk operations
# SECURITY: Operates only on specified email_account's data for proper isolation
class MetricsRefreshJob < ApplicationJob
  queue_as :low_priority

  # Retry with exponential backoff on failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Include concurrency control
  include GoodJob::ActiveJobExtensions::Concurrency if defined?(GoodJob)

  # Prevent concurrent execution for the same email account
  # This uses a simple approach with rescue for lock acquisition
  def perform(email_account_id, affected_dates: [], force_refresh: false)
    email_account = EmailAccount.find(email_account_id)

    # Use Redis lock to prevent concurrent metric calculation for the same account
    lock_key = "metrics_refresh:#{email_account_id}"
    lock_acquired = acquire_lock(lock_key)

    unless lock_acquired
      Rails.logger.info "MetricsRefreshJob skipped - another job is already processing account #{email_account_id}"
      return
    end

    begin
      # Track performance
      start_time = Time.current

      # Determine which periods need refresh based on affected dates
      periods_to_refresh = determine_affected_periods(affected_dates)

      Rails.logger.info "Refreshing metrics for account #{email_account_id}, periods: #{periods_to_refresh.keys}"

      # Clear existing cache for affected periods
      clear_affected_cache(email_account, periods_to_refresh)

      # Recalculate metrics for affected periods
      refresh_count = 0
      periods_to_refresh.each do |period, dates|
        dates.each do |date|
          calculator = Services::MetricsCalculator.new(
            email_account: email_account,
            period: period,
            reference_date: date
          )
          calculator.calculate # This will cache the new results
          refresh_count += 1
        end
      end

      # Track completion time
      elapsed = Time.current - start_time

      # Log performance warning if exceeds target
      if elapsed > 30.seconds
        Rails.logger.warn "MetricsRefreshJob exceeded 30s target: #{elapsed.round(2)}s for account #{email_account_id}"
      else
        Rails.logger.info "MetricsRefreshJob completed in #{elapsed.round(2)}s - refreshed #{refresh_count} metric sets"
      end

      # Update job metrics for monitoring
      track_job_metrics(email_account_id, elapsed, refresh_count, :success)

    rescue StandardError => e
      Rails.logger.error "MetricsRefreshJob failed for account #{email_account_id}: #{e.message}"
      track_job_metrics(email_account_id, 0, 0, :failure)
      raise # Re-raise for retry mechanism
    ensure
      release_lock(lock_key)
    end
  end

  # Class method for smart debouncing - prevents job flooding
  def self.enqueue_debounced(email_account_id, affected_date: Date.current, delay: 5.seconds)
    # Use a unique job key based on account and time window
    job_key = "metrics_refresh_debounce:#{email_account_id}:#{(Time.current.to_i / 60)}" # 1-minute window

    # Check if a job is already scheduled for this time window
    if Rails.cache.read(job_key).present?
      Rails.logger.debug "MetricsRefreshJob debounced for account #{email_account_id}"
      return nil
    end

    # Mark this time window as having a scheduled job
    Rails.cache.write(job_key, true, expires_in: 1.minute)

    # Collect all affected dates in the cache for this account
    dates_key = "metrics_refresh_dates:#{email_account_id}"
    affected_dates = Rails.cache.fetch(dates_key, expires_in: 1.minute) { [] }
    affected_dates << affected_date unless affected_dates.include?(affected_date)
    Rails.cache.write(dates_key, affected_dates, expires_in: 1.minute)

    # Schedule the job with a small delay to collect more changes
    set(wait: delay).perform_later(email_account_id, affected_dates: affected_dates)
  end

  private

  def acquire_lock(lock_key)
    # Simple Redis-based lock with 60-second expiration
    Rails.cache.write(lock_key, Time.current.to_s, expires_in: 60.seconds, unless_exist: true)
  end

  def release_lock(lock_key)
    Rails.cache.delete(lock_key)
  end

  def determine_affected_periods(affected_dates)
    periods = {}
    current_date = Date.current

    # If no specific dates provided, refresh current periods
    if affected_dates.blank?
      Services::MetricsCalculator::SUPPORTED_PERIODS.each do |period|
        periods[period] = [ current_date ]
      end
      return periods
    end

    # For each affected date, determine which periods it impacts
    affected_dates.each do |date|
      date = date.to_date

      # Day period - just the specific day
      periods[:day] ||= []
      periods[:day] << date unless periods[:day].include?(date)

      # Week period - the week containing the date
      week_start = date.beginning_of_week
      periods[:week] ||= []
      periods[:week] << week_start unless periods[:week].include?(week_start)

      # Month period - the month containing the date
      month_start = date.beginning_of_month
      periods[:month] ||= []
      periods[:month] << month_start unless periods[:month].include?(month_start)

      # Year period - the year containing the date
      year_start = date.beginning_of_year
      periods[:year] ||= []
      periods[:year] << year_start unless periods[:year].include?(year_start)

      # Also refresh current period if the date is recent
      if date >= 7.days.ago
        periods[:day] << current_date unless periods[:day].include?(current_date)
        periods[:week] << current_date.beginning_of_week unless periods[:week].include?(current_date.beginning_of_week)
        periods[:month] << current_date.beginning_of_month unless periods[:month].include?(current_date.beginning_of_month)
      end
    end

    periods
  end

  def clear_affected_cache(email_account, periods_to_refresh)
    periods_to_refresh.each do |period, dates|
      dates.each do |date|
        cache_key = "metrics_calculator:account_#{email_account.id}:#{period}:#{date.iso8601}"
        Rails.cache.delete(cache_key)
      end
    end
  end

  def track_job_metrics(email_account_id, elapsed_time, refresh_count, status)
    # Store job metrics for monitoring dashboard
    metrics_key = "job_metrics:metrics_refresh:#{email_account_id}"

    metrics = Rails.cache.fetch(metrics_key, expires_in: 24.hours) do
      { executions: [], success_count: 0, failure_count: 0, total_time: 0.0 }
    end

    # Add current execution
    metrics[:executions] << {
      timestamp: Time.current,
      elapsed: elapsed_time,
      refresh_count: refresh_count,
      status: status
    }

    # Keep only last 100 executions
    metrics[:executions] = metrics[:executions].last(100)

    # Update counters
    if status == :success
      metrics[:success_count] += 1
      metrics[:total_time] += elapsed_time
    else
      metrics[:failure_count] += 1
    end

    # Calculate averages
    if metrics[:success_count] > 0
      metrics[:average_time] = metrics[:total_time] / metrics[:success_count]
    end

    metrics[:success_rate] = if (metrics[:success_count] + metrics[:failure_count]) > 0
      (metrics[:success_count].to_f / (metrics[:success_count] + metrics[:failure_count]) * 100).round(2)
    else
      0.0
    end

    Rails.cache.write(metrics_key, metrics, expires_in: 24.hours)
  end
end
