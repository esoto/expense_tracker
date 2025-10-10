# frozen_string_literal: true

# Service for monitoring metrics calculation job performance
# Tracks execution times, success rates, and ensures performance targets are met
module Services
  class MetricsJobMonitor
  # Performance targets
  TARGET_EXECUTION_TIME = 30.seconds
  WARNING_EXECUTION_TIME = 20.seconds
  CRITICAL_FAILURE_RATE = 10.0 # percentage
  WARNING_FAILURE_RATE = 5.0 # percentage

  class << self
    # Get comprehensive status of metrics jobs
    def status
      {
        calculation_jobs: calculation_job_status,
        refresh_jobs: refresh_job_status,
        performance: performance_metrics,
        health: health_check,
        slow_jobs: recent_slow_jobs,
        recommendations: generate_recommendations
      }
    end

    # Status of MetricsCalculationJob executions
    def calculation_job_status
      metrics = aggregate_job_metrics("metrics_calculation")

      {
        total_executions: metrics[:total_executions],
        success_rate: metrics[:success_rate],
        average_execution_time: metrics[:average_time],
        last_execution: metrics[:last_execution],
        accounts_processed: metrics[:accounts].size,
        status: determine_job_status(metrics)
      }
    end

    # Status of MetricsRefreshJob executions
    def refresh_job_status
      metrics = aggregate_job_metrics("metrics_refresh")

      {
        total_executions: metrics[:total_executions],
        success_rate: metrics[:success_rate],
        average_execution_time: metrics[:average_time],
        last_execution: metrics[:last_execution],
        accounts_processed: metrics[:accounts].size,
        debounced_count: count_debounced_jobs,
        status: determine_job_status(metrics)
      }
    end

    # Overall performance metrics
    def performance_metrics
      calc_metrics = aggregate_job_metrics("metrics_calculation")
      refresh_metrics = aggregate_job_metrics("metrics_refresh")

      {
        total_metric_calculations: calc_metrics[:total_executions] + refresh_metrics[:total_executions],
        average_execution_time: calculate_weighted_average_time(calc_metrics, refresh_metrics),
        jobs_exceeding_target: count_slow_executions(TARGET_EXECUTION_TIME),
        jobs_exceeding_warning: count_slow_executions(WARNING_EXECUTION_TIME),
        cache_hit_rate: calculate_cache_hit_rate,
        peak_execution_hour: find_peak_execution_hour
      }
    end

    # Health check for metrics job system
    def health_check
      calc_metrics = aggregate_job_metrics("metrics_calculation")
      refresh_metrics = aggregate_job_metrics("metrics_refresh")
      slow_job_count = recent_slow_jobs.size

      # Determine overall health
      if calc_metrics[:success_rate] < (100 - CRITICAL_FAILURE_RATE) ||
         refresh_metrics[:success_rate] < (100 - CRITICAL_FAILURE_RATE)
        status = :critical
        message = "High failure rate detected"
      elsif calc_metrics[:average_time] > TARGET_EXECUTION_TIME ||
            refresh_metrics[:average_time] > TARGET_EXECUTION_TIME
        status = :warning
        message = "Jobs exceeding performance target"
      elsif slow_job_count > 10
        status = :warning
        message = "Multiple slow job executions detected"
      elsif calc_metrics[:success_rate] < (100 - WARNING_FAILURE_RATE) ||
            refresh_metrics[:success_rate] < (100 - WARNING_FAILURE_RATE)
        status = :warning
        message = "Elevated failure rate"
      else
        status = :healthy
        message = "All metrics jobs operating normally"
      end

      {
        status: status,
        message: message,
        checks: {
          calculation_job_healthy: calc_metrics[:success_rate] >= (100 - WARNING_FAILURE_RATE),
          refresh_job_healthy: refresh_metrics[:success_rate] >= (100 - WARNING_FAILURE_RATE),
          performance_target_met: calc_metrics[:average_time] <= TARGET_EXECUTION_TIME &&
                                 refresh_metrics[:average_time] <= TARGET_EXECUTION_TIME,
          no_stale_locks: !stale_locks_exist?
        }
      }
    end

    # Get recent slow job executions
    def recent_slow_jobs(limit: 10)
      slow_jobs = Rails.cache.fetch("slow_jobs:metrics_calculation", expires_in: 7.days) { [] }
      slow_jobs.last(limit).reverse.map do |job|
        {
          email_account_id: job[:email_account_id],
          timestamp: job[:timestamp],
          elapsed_time: job[:elapsed_time],
          expense_count: job[:expense_count],
          exceeded_by: (job[:elapsed_time] - TARGET_EXECUTION_TIME).round(2)
        }
      end
    end

    # Clear stale locks that might be blocking jobs
    def clear_stale_locks
      cleared = 0

      # Clear metrics calculation locks older than 10 minutes
      EmailAccount.find_each do |account|
        lock_key = "metrics_calculation:#{account.id}"
        lock_value = Rails.cache.read(lock_key)

        if lock_value.present?
          lock_time = Time.parse(lock_value) rescue nil
          if lock_time && lock_time < 10.minutes.ago
            Rails.cache.delete(lock_key)
            cleared += 1
            Rails.logger.info "Cleared stale lock for account #{account.id}"
          end
        end

        # Also check refresh locks
        refresh_lock_key = "metrics_refresh:#{account.id}"
        refresh_lock_value = Rails.cache.read(refresh_lock_key)

        if refresh_lock_value.present?
          lock_time = Time.parse(refresh_lock_value) rescue nil
          if lock_time && lock_time < 10.minutes.ago
            Rails.cache.delete(refresh_lock_key)
            cleared += 1
            Rails.logger.info "Cleared stale refresh lock for account #{account.id}"
          end
        end
      end

      cleared
    end

    # Force recalculation of all metrics
    def force_recalculate_all
      EmailAccount.active.find_each do |account|
        MetricsCalculationJob.perform_later(
          email_account_id: account.id,
          force_refresh: true
        )
      end
    end

    private

    def aggregate_job_metrics(job_type)
      all_metrics = {
        total_executions: 0,
        success_count: 0,
        failure_count: 0,
        total_time: 0.0,
        executions: [],
        accounts: Set.new
      }

      # Aggregate metrics across all email accounts
      EmailAccount.find_each do |account|
        metrics_key = "job_metrics:#{job_type}:#{account.id}"
        account_metrics = Rails.cache.read(metrics_key)

        next unless account_metrics

        all_metrics[:success_count] += account_metrics[:success_count] || 0
        all_metrics[:failure_count] += account_metrics[:failure_count] || 0
        all_metrics[:total_time] += account_metrics[:total_time] || 0.0
        all_metrics[:executions] += account_metrics[:executions] || []
        all_metrics[:accounts] << account.id
      end

      all_metrics[:total_executions] = all_metrics[:success_count] + all_metrics[:failure_count]

      # Calculate averages
      if all_metrics[:success_count] > 0
        all_metrics[:average_time] = all_metrics[:total_time] / all_metrics[:success_count]
      else
        all_metrics[:average_time] = 0.0
      end

      all_metrics[:success_rate] = if all_metrics[:total_executions] > 0
        (all_metrics[:success_count].to_f / all_metrics[:total_executions] * 100).round(2)
      else
        0.0
      end

      # Find last execution
      all_metrics[:last_execution] = all_metrics[:executions]
        .select { |e| e[:status] == :success }
        .max_by { |e| e[:timestamp] }

      all_metrics
    end

    def determine_job_status(metrics)
      if metrics[:success_rate] < (100 - CRITICAL_FAILURE_RATE)
        :critical
      elsif metrics[:success_rate] < (100 - WARNING_FAILURE_RATE)
        :warning
      elsif metrics[:average_time] > TARGET_EXECUTION_TIME
        :slow
      elsif metrics[:average_time] > WARNING_EXECUTION_TIME
        :warning
      else
        :healthy
      end
    end

    def calculate_weighted_average_time(calc_metrics, refresh_metrics)
      total_success = calc_metrics[:success_count] + refresh_metrics[:success_count]
      return 0.0 if total_success.zero?

      total_time = calc_metrics[:total_time] + refresh_metrics[:total_time]
      (total_time / total_success).round(2)
    end

    def count_slow_executions(threshold)
      count = 0

      EmailAccount.find_each do |account|
        [ "metrics_calculation", "metrics_refresh" ].each do |job_type|
          metrics_key = "job_metrics:#{job_type}:#{account.id}"
          account_metrics = Rails.cache.read(metrics_key)

          next unless account_metrics && account_metrics[:executions]

          count += account_metrics[:executions].count do |execution|
            execution[:status] == :success && execution[:elapsed] > threshold
          end
        end
      end

      count
    end

    def calculate_cache_hit_rate
      # Estimate based on job execution patterns
      # In reality, this would need more sophisticated tracking
      total_requests = Rails.cache.read("metrics_calculator:requests") || 0
      cache_hits = Rails.cache.read("metrics_calculator:cache_hits") || 0

      return 100.0 if total_requests.zero?

      ((cache_hits.to_f / total_requests) * 100).round(2)
    end

    def find_peak_execution_hour
      hour_counts = Hash.new(0)

      EmailAccount.find_each do |account|
        [ "metrics_calculation", "metrics_refresh" ].each do |job_type|
          metrics_key = "job_metrics:#{job_type}:#{account.id}"
          account_metrics = Rails.cache.read(metrics_key)

          next unless account_metrics && account_metrics[:executions]

          account_metrics[:executions].each do |execution|
            hour = execution[:timestamp].hour
            hour_counts[hour] += 1
          end
        end
      end

      peak_hour = hour_counts.max_by { |_hour, count| count }
      peak_hour ? peak_hour[0] : nil
    end

    def count_debounced_jobs
      # Count how many jobs were debounced (prevented from running)
      debounced_count = 0

      EmailAccount.find_each do |account|
        job_key = "metrics_refresh_debounce:#{account.id}:#{(Time.current.to_i / 60)}"
        debounced_count += 1 if Rails.cache.read(job_key).present?
      end

      debounced_count
    end

    def stale_locks_exist?
      EmailAccount.find_each do |account|
        [ "metrics_calculation:#{account.id}", "metrics_refresh:#{account.id}" ].each do |lock_key|
          lock_value = Rails.cache.read(lock_key)
          if lock_value.present?
            lock_time = Time.parse(lock_value) rescue nil
            return true if lock_time && lock_time < 10.minutes.ago
          end
        end
      end

      false
    end

    def generate_recommendations
      recommendations = []

      calc_metrics = aggregate_job_metrics("metrics_calculation")
      refresh_metrics = aggregate_job_metrics("metrics_refresh")
      slow_jobs = recent_slow_jobs

      # Performance recommendations
      if calc_metrics[:average_time] > TARGET_EXECUTION_TIME
        recommendations << {
          type: :performance,
          priority: :high,
          message: "Metrics calculation jobs are exceeding the 30-second target. Consider optimizing queries or increasing cache duration."
        }
      end

      # Failure rate recommendations
      if calc_metrics[:success_rate] < (100 - WARNING_FAILURE_RATE)
        recommendations << {
          type: :reliability,
          priority: :high,
          message: "Metrics calculation job failure rate is #{(100 - calc_metrics[:success_rate]).round(2)}%. Investigate error logs."
        }
      end

      # Slow job pattern detection
      if slow_jobs.size > 5
        avg_expense_count = slow_jobs.sum { |j| j[:expense_count] } / slow_jobs.size.to_f
        if avg_expense_count > 10000
          recommendations << {
            type: :scaling,
            priority: :medium,
            message: "Slow jobs correlate with high expense counts (avg: #{avg_expense_count.round}). Consider data archival or query optimization."
          }
        end
      end

      # Stale lock detection
      if stale_locks_exist?
        recommendations << {
          type: :maintenance,
          priority: :high,
          message: "Stale locks detected. Run MetricsJobMonitor.clear_stale_locks to resolve."
        }
      end

      # Cache optimization
      if refresh_metrics[:total_executions] > calc_metrics[:total_executions] * 10
        recommendations << {
          type: :optimization,
          priority: :medium,
          message: "High refresh-to-calculation ratio. Consider increasing cache duration or optimizing change triggers."
        }
      end

      recommendations
    end
  end
  end
end
