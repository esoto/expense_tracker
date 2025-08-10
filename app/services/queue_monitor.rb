# frozen_string_literal: true

# Service to monitor SolidQueue background job processing
# Provides real-time metrics about queue depth, processing status, and job health
class QueueMonitor
  include ActiveSupport::NumberHelper

  # Cache duration for queue status to avoid excessive database queries
  CACHE_DURATION = 5.seconds
  # Maximum number of active jobs to display
  MAX_ACTIVE_JOBS_DISPLAY = 10
  # Time window for calculating processing rate
  PROCESSING_RATE_WINDOW = 1.hour

  class << self
    # Returns comprehensive queue status with all metrics
    def queue_status
      Rails.cache.fetch("queue_monitor:status", expires_in: CACHE_DURATION) do
        {
          pending: pending_jobs_count,
          processing: processing_jobs_count,
          completed: completed_jobs_count,
          failed: failed_jobs_count,
          paused_queues: paused_queues,
          active_jobs: format_active_jobs,
          failed_jobs: format_failed_jobs,
          queue_depth_by_name: queue_depth_by_name,
          processing_rate: processing_rate,
          estimated_completion_time: estimate_completion_time,
          worker_status: worker_status,
          health_status: calculate_health_status
        }
      end
    end

    # Count of jobs waiting to be processed
    def pending_jobs_count
      SolidQueue::ReadyExecution.count + SolidQueue::ScheduledExecution.where("solid_queue_scheduled_executions.scheduled_at <= ?", Time.current).count
    end

    # Count of jobs currently being processed
    def processing_jobs_count
      SolidQueue::ClaimedExecution.count
    end

    # Count of completed jobs in the last 24 hours
    def completed_jobs_count
      SolidQueue::Job.where.not(finished_at: nil)
                     .where(finished_at: 24.hours.ago..Time.current)
                     .count
    end

    # Count of failed jobs
    def failed_jobs_count
      SolidQueue::FailedExecution.count
    end

    # List of paused queue names
    def paused_queues
      SolidQueue::Pause.pluck(:queue_name)
    end

    # Returns pending jobs with details
    def pending_jobs
      jobs = []

      # Ready executions
      SolidQueue::ReadyExecution.joins(:job)
                                .includes(:job)
                                .order(priority: :desc, created_at: :asc)
                                .limit(MAX_ACTIVE_JOBS_DISPLAY)
                                .each do |execution|
        jobs << format_job(execution.job, "ready")
      end

      # Scheduled executions that are due
      SolidQueue::ScheduledExecution.joins(:job)
                                    .includes(:job)
                                    .where("solid_queue_scheduled_executions.scheduled_at <= ?", Time.current)
                                    .order("solid_queue_scheduled_executions.scheduled_at")
                                    .limit(MAX_ACTIVE_JOBS_DISPLAY - jobs.size)
                                    .each do |execution|
        jobs << format_job(execution.job, "scheduled")
      end

      jobs
    end

    # Returns currently processing jobs with details
    def processing_jobs
      SolidQueue::ClaimedExecution.joins(:job)
                                  .includes(:job, :process)
                                  .order(created_at: :desc)
                                  .limit(MAX_ACTIVE_JOBS_DISPLAY)
                                  .map do |execution|
        format_job(execution.job, "processing", execution.process)
      end
    end

    # Returns failed jobs with error details
    def failed_jobs
      SolidQueue::FailedExecution.joins(:job)
                                 .includes(:job)
                                 .order(created_at: :desc)
                                 .limit(MAX_ACTIVE_JOBS_DISPLAY)
                                 .map do |execution|
        format_job(execution.job, "failed", nil, execution.error)
      end
    end

    # Format job data for display
    def format_job(job, status, process = nil, error = nil)
      {
        id: job.id,
        active_job_id: job.active_job_id,
        class_name: job.class_name,
        queue_name: job.queue_name,
        priority: job.priority,
        status: status,
        created_at: job.created_at,
        scheduled_at: job.scheduled_at,
        arguments: safe_parse_arguments(job.arguments),
        process_info: process ? format_process_info(process) : nil,
        error: error,
        duration: calculate_duration(job, status)
      }
    end

    # Calculate job duration based on status
    def calculate_duration(job, status)
      case status
      when "processing"
        Time.current - job.updated_at
      when "failed", "completed"
        job.finished_at ? job.finished_at - job.created_at : nil
      else
        nil
      end
    end

    # Format process information
    def format_process_info(process)
      return nil unless process

      {
        id: process.id,
        pid: process.pid,
        hostname: process.hostname,
        kind: process.kind,
        last_heartbeat: process.last_heartbeat_at,
        healthy: process.last_heartbeat_at > 1.minute.ago
      }
    end

    # Safely parse job arguments
    def safe_parse_arguments(arguments_json)
      return {} if arguments_json.blank?

      parsed = JSON.parse(arguments_json)
      # Extract job arguments if present
      if parsed.is_a?(Hash) && parsed["arguments"]
        parsed["arguments"]
      else
        parsed
      end
    rescue JSON::ParserError
      { raw: arguments_json }
    end

    # Queue depth grouped by queue name
    def queue_depth_by_name
      depths = {}

      SolidQueue::ReadyExecution.joins(:job)
                                .group("solid_queue_jobs.queue_name")
                                .count
                                .each do |queue_name, count|
        depths[queue_name] ||= 0
        depths[queue_name] += count
      end

      SolidQueue::ScheduledExecution.joins(:job)
                                    .where("solid_queue_scheduled_executions.scheduled_at <= ?", Time.current)
                                    .group("solid_queue_jobs.queue_name")
                                    .count
                                    .each do |queue_name, count|
        depths[queue_name] ||= 0
        depths[queue_name] += count
      end

      depths
    end

    # Calculate average processing rate (jobs per minute)
    def processing_rate
      completed_recently = SolidQueue::Job.where.not(finished_at: nil)
                                          .where(finished_at: PROCESSING_RATE_WINDOW.ago..Time.current)
                                          .count

      minutes = PROCESSING_RATE_WINDOW / 1.minute
      (completed_recently.to_f / minutes).round(2)
    end

    # Estimate time to process all pending jobs
    def estimate_completion_time
      pending_count = pending_jobs_count
      rate = processing_rate

      return nil if rate.zero? || pending_count.zero?

      minutes_remaining = (pending_count / rate).ceil
      Time.current + minutes_remaining.minutes
    end

    # Get worker/process status
    def worker_status
      processes = SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago)

      {
        total: processes.count,
        workers: processes.where(kind: "Worker").count,
        dispatchers: processes.where(kind: "Dispatcher").count,
        supervisors: processes.where(kind: "Supervisor").count,
        healthy: processes.where("last_heartbeat_at > ?", 1.minute.ago).count,
        stale: processes.where("last_heartbeat_at <= ?", 1.minute.ago).count,
        processes: processes.map do |process|
          {
            id: process.id,
            name: process.name,
            kind: process.kind,
            pid: process.pid,
            hostname: process.hostname,
            last_heartbeat: process.last_heartbeat_at,
            healthy: process.last_heartbeat_at > 1.minute.ago,
            metadata: process.metadata
          }
        end
      }
    end

    # Calculate overall health status
    def calculate_health_status
      failed_count = failed_jobs_count
      pending_count = pending_jobs_count
      worker_info = worker_status

      if worker_info[:healthy].zero?
        { status: "critical", message: "No healthy workers available" }
      elsif failed_count > 100
        { status: "critical", message: "High number of failed jobs (#{failed_count})" }
      elsif pending_count > 1000
        { status: "warning", message: "Large queue backlog (#{pending_count} pending)" }
      elsif worker_info[:stale] > 0
        { status: "warning", message: "#{worker_info[:stale]} stale workers detected" }
      elsif failed_count > 50
        { status: "warning", message: "Elevated failed job count (#{failed_count})" }
      else
        { status: "healthy", message: "Queue system operating normally" }
      end
    end

    # Pause a specific queue or all queues
    def pause_queue(queue_name = nil)
      if queue_name.present?
        SolidQueue::Pause.create_or_find_by!(queue_name: queue_name)
      else
        # Pause all queues - batch insert to avoid N+1 queries
        queue_names = SolidQueue::Job.distinct.pluck(:queue_name)
        existing_pauses = SolidQueue::Pause.where(queue_name: queue_names).pluck(:queue_name)
        new_queue_names = queue_names - existing_pauses

        if new_queue_names.any?
          pause_records = new_queue_names.map { |name| { queue_name: name } }
          SolidQueue::Pause.insert_all(pause_records)
        end
      end
      clear_cache
      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to pause queue: #{e.message}"
      false
    end

    # Resume a specific queue or all queues
    def resume_queue(queue_name = nil)
      if queue_name.present?
        SolidQueue::Pause.where(queue_name: queue_name).destroy_all
      else
        # Resume all queues
        SolidQueue::Pause.destroy_all
      end
      clear_cache
      true
    rescue StandardError => e
      Rails.logger.error "Failed to resume queue: #{e.message}"
      false
    end

    # Retry a failed job
    def retry_failed_job(job_id)
      failed_execution = SolidQueue::FailedExecution.find_by(job_id: job_id)
      return false unless failed_execution

      job = failed_execution.job
      return false unless job

      # Remove from failed executions
      failed_execution.destroy

      # Re-enqueue the job by creating a ready execution
      SolidQueue::ReadyExecution.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority
      )

      clear_cache
      true
    rescue StandardError => e
      Rails.logger.error "Failed to retry job #{job_id}: #{e.message}"
      false
    end

    # Retry all failed jobs
    def retry_all_failed_jobs
      # Batch retry to avoid N+1 queries
      failed_executions = SolidQueue::FailedExecution.includes(:job).to_a
      count = 0

      SolidQueue::Job.transaction do
        failed_executions.each do |failed_execution|
          begin
            # Create ready execution for retry
            SolidQueue::ReadyExecution.create!(
              job: failed_execution.job,
              queue_name: failed_execution.job.queue_name,
              priority: failed_execution.job.priority
            )

            # Remove failed execution
            failed_execution.destroy!
            count += 1
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.warn "Failed to retry job #{failed_execution.job_id}: #{e.message}"
          end
        end
      end

      clear_cache
      count
    end

    # Clear a failed job without retrying
    def clear_failed_job(job_id)
      failed_execution = SolidQueue::FailedExecution.find_by(job_id: job_id)
      return false unless failed_execution

      job = failed_execution.job

      # Mark job as finished
      job.update!(finished_at: Time.current) if job

      # Remove from failed executions
      failed_execution.destroy

      clear_cache
      true
    rescue StandardError => e
      Rails.logger.error "Failed to clear job #{job_id}: #{e.message}"
      false
    end

    # Get detailed metrics for monitoring
    def detailed_metrics
      {
        queue_status: queue_status,
        performance: {
          processing_rate: processing_rate,
          average_wait_time: calculate_average_wait_time,
          average_processing_time: calculate_average_processing_time,
          throughput_per_hour: processing_rate * 60
        },
        queue_distribution: queue_depth_by_name,
        worker_utilization: calculate_worker_utilization,
        error_rate: calculate_error_rate
      }
    end

    private

    # Format active jobs for display
    def format_active_jobs
      processing_jobs.first(MAX_ACTIVE_JOBS_DISPLAY)
    end

    # Format failed jobs for display
    def format_failed_jobs
      failed_jobs.first(MAX_ACTIVE_JOBS_DISPLAY)
    end

    # Calculate average wait time for jobs
    def calculate_average_wait_time
      recent_jobs = SolidQueue::ClaimedExecution.joins(:job)
                                                 .where("solid_queue_claimed_executions.created_at > ?", 1.hour.ago)
                                                 .limit(100)

      return 0 if recent_jobs.empty?

      total_wait = recent_jobs.sum do |execution|
        execution.created_at - execution.job.created_at
      end

      (total_wait / recent_jobs.size).round(2)
    end

    # Calculate average processing time
    def calculate_average_processing_time
      recent_completed = SolidQueue::Job.where.not(finished_at: nil)
                                        .where(finished_at: 1.hour.ago..Time.current)
                                        .limit(100)

      return 0 if recent_completed.empty?

      total_time = recent_completed.sum do |job|
        job.finished_at - job.created_at
      end

      (total_time / recent_completed.size).round(2)
    end

    # Calculate worker utilization percentage
    def calculate_worker_utilization
      total_workers = worker_status[:workers]
      return 0 if total_workers.zero?

      busy_workers = processing_jobs_count
      utilization = (busy_workers.to_f / total_workers * 100).round(2)
      [ utilization, 100 ].min
    end

    # Calculate error rate (failed jobs / total jobs)
    def calculate_error_rate
      total_recent = SolidQueue::Job.where(created_at: 1.hour.ago..Time.current).count
      return 0 if total_recent.zero?

      failed_recent = SolidQueue::FailedExecution.joins(:job)
                                                  .where("solid_queue_jobs.created_at > ?", 1.hour.ago)
                                                  .count

      (failed_recent.to_f / total_recent * 100).round(2)
    end

    # Clear all cached data
    def clear_cache
      Rails.cache.delete("queue_monitor:status")
    end
  end
end
