# frozen_string_literal: true

# Background job for pre-calculating expense metrics
# Runs periodically to ensure metrics are always cached and fast
# Performance target: Complete in < 30 seconds
# SECURITY: Operates only on specified email_account's data for proper isolation
class MetricsCalculationJob < ApplicationJob
  queue_as :default

  # Performance monitoring
  MAX_EXECUTION_TIME = 30.seconds
  CACHE_EXPIRY_HOURS = 4 # Longer cache for background-calculated metrics

  # Retry with exponential backoff on failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Job can be called with specific email_account_id and optionally period and date
  # If called without email_account_id, it will enqueue jobs for all active accounts
  def perform(email_account_id: nil, period: nil, reference_date: nil, force_refresh: false)
    # If no email_account_id provided, enqueue jobs for all active accounts
    if email_account_id.nil?
      Rails.logger.info "MetricsCalculationJob called without email_account_id - enqueuing for all active accounts"
      self.class.enqueue_for_all_accounts
      return
    end

    # Track start time for performance monitoring
    start_time = Time.current

    # Support both email_account_id and direct email_account object
    email_account = if email_account_id.is_a?(EmailAccount)
                      email_account_id
    elsif email_account_id
                      EmailAccount.find(email_account_id)
    else
                      raise ArgumentError, "email_account_id is required for MetricsCalculationJob"
    end

    # Acquire lock to prevent concurrent calculation for the same account
    lock_key = "metrics_calculation:#{email_account.id}"
    lock_acquired = acquire_lock(lock_key)

    unless lock_acquired
      Rails.logger.info "MetricsCalculationJob skipped - another job is already processing account #{email_account.id}"
      return
    end

    begin
      reference_date ||= Date.current

      # Clear cache if forced refresh
      if force_refresh
        MetricsCalculator.clear_cache(email_account: email_account)
      end

      if period.present?
        # Calculate specific period for the email account
        Rails.logger.info "Calculating metrics for account #{email_account.id}, period: #{period}, date: #{reference_date}"

        # Use longer cache expiration for background-calculated metrics
        calculator = ExtendedCacheMetricsCalculator.new(
          email_account: email_account,
          period: period,
          reference_date: reference_date,
          cache_hours: CACHE_EXPIRY_HOURS
        )
        result = calculator.calculate

        log_calculation_result(email_account, period, reference_date, result)
      else
        # Calculate all periods for current date and next/previous periods for the email account
        calculate_all_periods(email_account, reference_date)
      end

      # Track execution time
      elapsed_time = Time.current - start_time

      # Log performance warning if exceeds target
      if elapsed_time > MAX_EXECUTION_TIME
        Rails.logger.warn "MetricsCalculationJob exceeded #{MAX_EXECUTION_TIME}s target: #{elapsed_time.round(2)}s for account #{email_account.id}"
        track_slow_job(email_account, elapsed_time)
      else
        Rails.logger.info "MetricsCalculationJob completed in #{elapsed_time.round(2)}s for account #{email_account.id}"
      end

      # Track job metrics for monitoring
      track_job_metrics(email_account.id, elapsed_time, :success)

    rescue StandardError => e
      Rails.logger.error "MetricsCalculationJob failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      track_job_metrics(email_account.id, 0, :failure)
      raise # Re-raise for retry mechanism
    ensure
      release_lock(lock_key)
    end
  end

  # Enqueue calculation for all active email accounts
  def self.enqueue_for_all_accounts
    EmailAccount.active.find_each do |email_account|
      perform_later(email_account_id: email_account.id)
    end
  end

  private

  def calculate_all_periods(email_account, reference_date)
    periods_and_dates = generate_periods_and_dates(reference_date)

    Rails.logger.info "Pre-calculating #{periods_and_dates.size} metric combinations for account #{email_account.id}"

    periods_and_dates.each do |period, date|
      Rails.logger.debug "Calculating metrics for account #{email_account.id}, #{period} period on #{date}"

      # Use extended cache for background calculations
      calculator = ExtendedCacheMetricsCalculator.new(
        email_account: email_account,
        period: period,
        reference_date: date,
        cache_hours: CACHE_EXPIRY_HOURS
      )
      result = calculator.calculate

      log_calculation_result(email_account, period, date, result)
    end
  end

  def generate_periods_and_dates(reference_date)
    periods_and_dates = []

    # For each period type, calculate current, previous, and next
    MetricsCalculator::SUPPORTED_PERIODS.each do |period|
      case period
      when :day
        # Current day and past 7 days
        (-7..0).each do |days_ago|
          periods_and_dates << [ period, reference_date + days_ago.days ]
        end
      when :week
        # Current week and past 4 weeks
        (-4..0).each do |weeks_ago|
          periods_and_dates << [ period, reference_date + weeks_ago.weeks ]
        end
      when :month
        # Current month and past 3 months
        (-3..0).each do |months_ago|
          periods_and_dates << [ period, reference_date + months_ago.months ]
        end
      when :year
        # Current year and previous year
        [ 0, -1 ].each do |years_ago|
          periods_and_dates << [ period, reference_date + years_ago.years ]
        end
      end
    end

    periods_and_dates
  end

  def log_calculation_result(email_account, period, reference_date, result)
    if result[:error].present?
      Rails.logger.error "Metrics calculation failed for account #{email_account.id}, #{period} on #{reference_date}: #{result[:error]}"
    else
      metrics = result[:metrics]
      Rails.logger.info "Metrics calculated for account #{email_account.id}, #{period} on #{reference_date}: " \
                       "#{metrics[:transaction_count]} transactions, " \
                       "total: #{format_amount(metrics[:total_amount])}"
    end
  end

  def format_amount(amount)
    "$#{'%.2f' % amount}"
  end

  def acquire_lock(lock_key)
    # Use Redis/cache-based lock with 5-minute expiration
    # Returns true if lock acquired, false if already locked
    Rails.cache.write(lock_key, Time.current.to_s, expires_in: 5.minutes, unless_exist: true)
  end

  def release_lock(lock_key)
    Rails.cache.delete(lock_key)
  end

  def track_job_metrics(email_account_id, elapsed_time, status)
    # Store job metrics for monitoring dashboard
    metrics_key = "job_metrics:metrics_calculation:#{email_account_id}"

    metrics = Rails.cache.fetch(metrics_key, expires_in: 24.hours) do
      { executions: [], success_count: 0, failure_count: 0, total_time: 0.0 }
    end

    # Add current execution
    metrics[:executions] << {
      timestamp: Time.current,
      elapsed: elapsed_time,
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

  def track_slow_job(email_account, elapsed_time)
    # Track slow jobs for analysis
    slow_jobs_key = "slow_jobs:metrics_calculation"

    slow_jobs = Rails.cache.fetch(slow_jobs_key, expires_in: 7.days) { [] }

    slow_jobs << {
      email_account_id: email_account.id,
      timestamp: Time.current,
      elapsed_time: elapsed_time,
      expense_count: email_account.expenses.count
    }

    # Keep only last 50 slow job records
    slow_jobs = slow_jobs.last(50)

    Rails.cache.write(slow_jobs_key, slow_jobs, expires_in: 7.days)
  end
end
