# frozen_string_literal: true

module Api
  # API controller for queue monitoring and management
  # Provides endpoints for real-time queue status, control operations, and job management
  class QueueController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :verify_authenticity_token
    before_action :authenticate_queue_access!
    before_action :set_job, only: [ :retry_job, :clear_job ]

    # GET /api/queue/status.json
    # Returns comprehensive queue status including metrics and health information
    def status
      status_data = Services::QueueMonitor.queue_status

      render json: {
        success: true,
        data: {
          summary: {
            pending: status_data[:pending],
            processing: status_data[:processing],
            completed: status_data[:completed],
            failed: status_data[:failed],
            health: status_data[:health_status]
          },
          queues: {
            depth: status_data[:queue_depth_by_name],
            paused: status_data[:paused_queues]
          },
          jobs: {
            active: status_data[:active_jobs],
            failed: status_data[:failed_jobs]
          },
          performance: {
            processing_rate: status_data[:processing_rate],
            estimated_completion: status_data[:estimated_completion_time]&.iso8601,
            estimated_minutes: calculate_minutes_remaining(status_data)
          },
          workers: status_data[:worker_status]
        },
        timestamp: Time.current.iso8601
      }
    end

    # POST /api/queue/pause
    # Pauses job processing for specified queue or all queues
    def pause
      queue_name = params[:queue_name]

      if Services::QueueMonitor.pause_queue(queue_name)
        broadcast_queue_update("paused", queue_name)

        render json: {
          success: true,
          message: queue_name.present? ?
            "Queue '#{queue_name}' has been paused" :
            "All queues have been paused",
          paused_queues: Services::QueueMonitor.paused_queues
        }
      else
        render json: {
          success: false,
          error: "Failed to pause queue(s)"
        }, status: :unprocessable_content
      end
    end

    # POST /api/queue/resume
    # Resumes job processing for specified queue or all queues
    def resume
      queue_name = params[:queue_name]

      if Services::QueueMonitor.resume_queue(queue_name)
        broadcast_queue_update("resumed", queue_name)

        render json: {
          success: true,
          message: queue_name.present? ?
            "Queue '#{queue_name}' has been resumed" :
            "All queues have been resumed",
          paused_queues: Services::QueueMonitor.paused_queues
        }
      else
        render json: {
          success: false,
          error: "Failed to resume queue(s)"
        }, status: :unprocessable_content
      end
    end

    # POST /api/queue/jobs/:id/retry
    # Retries a specific failed job
    def retry_job
      if Services::QueueMonitor.retry_failed_job(params[:id])
        broadcast_job_update("retried", params[:id])

        render json: {
          success: true,
          message: "Job #{params[:id]} has been queued for retry",
          job_id: params[:id]
        }
      else
        render json: {
          success: false,
          error: "Failed to retry job #{params[:id]}"
        }, status: :unprocessable_content
      end
    end

    # POST /api/queue/jobs/:id/clear
    # Clears a failed job without retrying
    def clear_job
      if Services::QueueMonitor.clear_failed_job(params[:id])
        broadcast_job_update("cleared", params[:id])

        render json: {
          success: true,
          message: "Job #{params[:id]} has been cleared",
          job_id: params[:id]
        }
      else
        render json: {
          success: false,
          error: "Failed to clear job #{params[:id]}"
        }, status: :unprocessable_content
      end
    end

    # POST /api/queue/retry_all_failed
    # Retries all failed jobs
    def retry_all_failed
      count = Services::QueueMonitor.retry_all_failed_jobs

      if count > 0
        broadcast_queue_update("retry_all", nil)

        render json: {
          success: true,
          message: "#{count} failed jobs have been queued for retry",
          count: count
        }
      else
        render json: {
          success: false,
          error: "No failed jobs to retry or retry operation failed"
        }, status: :unprocessable_content
      end
    end

    # GET /api/queue/metrics
    # Returns detailed performance metrics for monitoring
    def metrics
      metrics_data = Services::QueueMonitor.detailed_metrics

      render json: {
        success: true,
        data: metrics_data,
        timestamp: Time.current.iso8601
      }
    end

    # GET /api/queue/health
    # Simple health check endpoint for monitoring systems
    def health
      health_status = Services::QueueMonitor.calculate_health_status
      status_code = case health_status[:status]
      when "critical" then :service_unavailable
      when "warning" then :ok
      else :ok
      end

      render json: {
        status: health_status[:status],
        message: health_status[:message],
        metrics: {
          pending: Services::QueueMonitor.pending_jobs_count,
          processing: Services::QueueMonitor.processing_jobs_count,
          failed: Services::QueueMonitor.failed_jobs_count,
          workers: Services::QueueMonitor.worker_status[:healthy]
        },
        timestamp: Time.current.iso8601
      }, status: status_code
    end

    private

    def set_job
      @job = SolidQueue::Job.find_by(id: params[:id])

      unless @job
        render json: {
          success: false,
          error: "Job not found"
        }, status: :not_found
      end
    end

    def calculate_minutes_remaining(status_data)
      return nil unless status_data[:estimated_completion_time]

      minutes = ((status_data[:estimated_completion_time] - Time.current) / 60).ceil
      minutes.positive? ? minutes : nil
    end

    # Extract the session ID from the current request for session-scoped broadcasting.
    # Falls back to the Rails session ID when the encrypted cookie does not contain a "session_id" key.
    def current_request_session_id
      session_data = cookies.encrypted[:_expense_tracker_session]
      session_id = session_data&.dig("session_id") || session_data&.dig(:session_id)
      session_id.presence || request.session.id.to_s.presence
    end

    # Build the session-scoped stream name for broadcasting via ActionCable.
    def scoped_stream_name
      QueueChannel.stream_name_for(current_request_session_id)
    end

    # Broadcast queue status updates via ActionCable, scoped to the requesting user's session
    def broadcast_queue_update(action, queue_name)
      stream = scoped_stream_name
      unless stream
        Rails.logger.warn "[QueueController] Skipping queue update broadcast: no valid session ID"
        return
      end

      ActionCable.server.broadcast(
        stream,
        {
          action: action,
          queue_name: queue_name,
          timestamp: Time.current.iso8601,
          current_status: {
            paused_queues: Services::QueueMonitor.paused_queues,
            pending: Services::QueueMonitor.pending_jobs_count,
            processing: Services::QueueMonitor.processing_jobs_count
          }
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to broadcast queue update: #{e.message}"
    end

    # Broadcast job-specific updates via ActionCable, scoped to the requesting user's session
    def broadcast_job_update(action, job_id)
      stream = scoped_stream_name
      unless stream
        Rails.logger.warn "[QueueController] Skipping job update broadcast: no valid session ID"
        return
      end

      ActionCable.server.broadcast(
        stream,
        {
          action: "job_#{action}",
          job_id: job_id,
          timestamp: Time.current.iso8601,
          failed_count: Services::QueueMonitor.failed_jobs_count
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to broadcast job update: #{e.message}"
    end

    # Authentication for queue access - supports both API token and admin session
    def authenticate_queue_access!
      # Option 1: API token authentication (for automated systems)
      token = request.headers["Authorization"]&.remove("Bearer ")
      if token.present?
        api_token = ApiToken.authenticate(token)
        if api_token&.valid_token?
          api_token.touch_last_used!
          return true
        end
      end

      # Option 2: Admin session authentication (for web interface)
      # Check for admin access via environment variable or session
      admin_key = Rails.application.credentials.dig(:admin_key) || ENV["ADMIN_KEY"]

      if admin_key.present?
        # Allow access if admin key matches
        provided_key = params[:admin_key] || request.headers["X-Admin-Key"]
        return true if provided_key == admin_key
      end

      # Option 3: Development/test environment bypass
      return true if Rails.env.development? || Rails.env.test?

      # Log unauthorized access attempt
      Rails.logger.warn "[SECURITY] Unauthorized queue access attempt from IP: #{request.remote_ip}, User-Agent: #{request.headers['User-Agent']}"

      # Return error response
      render json: {
        success: false,
        error: "Unauthorized access. Queue management requires admin privileges."
      }, status: :unauthorized

      false
    end
  end
end
