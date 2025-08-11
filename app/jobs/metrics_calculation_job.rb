# frozen_string_literal: true

# Background job for pre-calculating expense metrics
# Runs periodically to ensure metrics are always cached and fast
# SECURITY: Operates only on specified email_account's data for proper isolation
class MetricsCalculationJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff on failures
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Job can be called with specific email_account_id and optionally period and date
  # email_account_id is REQUIRED for data isolation
  def perform(email_account_id: nil, period: nil, reference_date: nil)
    # Support both email_account_id and direct email_account object
    email_account = if email_account_id.is_a?(EmailAccount)
                      email_account_id
                    elsif email_account_id
                      EmailAccount.find(email_account_id)
                    else
                      raise ArgumentError, "email_account_id is required for MetricsCalculationJob"
                    end
    
    reference_date ||= Date.current
    
    if period.present?
      # Calculate specific period for the email account
      Rails.logger.info "Calculating metrics for account #{email_account.id}, period: #{period}, date: #{reference_date}"
      calculator = MetricsCalculator.new(email_account: email_account, period: period, reference_date: reference_date)
      result = calculator.calculate
      
      log_calculation_result(email_account, period, reference_date, result)
    else
      # Calculate all periods for current date and next/previous periods for the email account
      calculate_all_periods(email_account, reference_date)
    end
    
    # Also update dashboard cache to keep it fresh
    # Note: DashboardService doesn't currently support email_account scoping
    if defined?(DashboardService)
      begin
        DashboardService.new.analytics
      rescue ArgumentError
        # DashboardService might not be configured yet
        Rails.logger.debug "DashboardService not available or configured"
      end
    end
    
    Rails.logger.info "MetricsCalculationJob completed successfully for account #{email_account.id}"
  rescue StandardError => e
    Rails.logger.error "MetricsCalculationJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise for retry mechanism
  end

  private

  def calculate_all_periods(email_account, reference_date)
    periods_and_dates = generate_periods_and_dates(reference_date)
    
    Rails.logger.info "Pre-calculating #{periods_and_dates.size} metric combinations for account #{email_account.id}"
    
    periods_and_dates.each do |period, date|
      Rails.logger.debug "Calculating metrics for account #{email_account.id}, #{period} period on #{date}"
      
      calculator = MetricsCalculator.new(email_account: email_account, period: period, reference_date: date)
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
          periods_and_dates << [period, reference_date + days_ago.days]
        end
      when :week
        # Current week and past 4 weeks
        (-4..0).each do |weeks_ago|
          periods_and_dates << [period, reference_date + weeks_ago.weeks]
        end
      when :month
        # Current month and past 3 months
        (-3..0).each do |months_ago|
          periods_and_dates << [period, reference_date + months_ago.months]
        end
      when :year
        # Current year and previous year
        [0, -1].each do |years_ago|
          periods_and_dates << [period, reference_date + years_ago.years]
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
end