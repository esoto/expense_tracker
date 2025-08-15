# frozen_string_literal: true

module Infrastructure
    # MonitoringService consolidates all monitoring, metrics, and analytics functionality
    # including queue monitoring, job monitoring, performance tracking, and error tracking.
    # This replaces multiple separate monitoring services for better cohesion.
    module MonitoringService
      extend ActiveSupport::Concern

      # Main interface for accessing different monitoring modules
      class << self
        def queue_metrics
          QueueMonitor.metrics
        end

        def job_metrics
          JobMonitor.metrics
        end

        def performance_metrics(component = nil)
          PerformanceTracker.metrics(component)
        end

        def error_summary(time_window: 1.hour)
          ErrorTracker.summary(time_window: time_window)
        end

        def system_health
          SystemHealth.check
        end

        def analytics(service: nil, time_window: 1.hour)
          Analytics.get_metrics(service: service, time_window: time_window)
        end
      end

      # Queue monitoring module
      module QueueMonitor
        extend ActiveSupport::Concern

        class << self
          def metrics
            {
              queue_sizes: queue_sizes,
              processing_times: processing_times,
              failed_jobs: failed_jobs_count,
              scheduled_jobs: scheduled_jobs_count,
              workers: worker_status
            }
          end

          def queue_sizes
            queues = {}

            # Get Solid Queue metrics
            SolidQueue::Job.pending.group(:queue_name).count.each do |queue, count|
              queues[queue] = count
            end

            queues
          end

          def processing_times
            # Average processing time per queue in last hour
            SolidQueue::Job.finished
                           .where(finished_at: 1.hour.ago..Time.current)
                           .group(:queue_name)
                           .average("EXTRACT(EPOCH FROM (finished_at - created_at))")
                           .transform_values { |v| v.to_f.round(2) }
          end

          def failed_jobs_count
            SolidQueue::FailedExecution.where(created_at: 1.hour.ago..Time.current).count
          end

          def scheduled_jobs_count
            SolidQueue::ScheduledExecution.where(scheduled_at: Time.current..1.hour.from_now).count
          end

          def worker_status
            {
              active: SolidQueue::Process.where(kind: "Worker").count,
              dispatchers: SolidQueue::Process.where(kind: "Dispatcher").count,
              supervisors: SolidQueue::Process.where(kind: "Supervisor").count
            }
          end
        end
      end

      # Job monitoring module
      module JobMonitor
        extend ActiveSupport::Concern

        class << self
          def metrics
            {
              total_jobs: total_jobs_count,
              jobs_by_status: jobs_by_status,
              jobs_by_class: jobs_by_class,
              average_wait_time: average_wait_time,
              average_execution_time: average_execution_time,
              failure_rate: calculate_failure_rate
            }
          end

          def total_jobs_count
            SolidQueue::Job.where(created_at: 1.hour.ago..Time.current).count
          end

          def jobs_by_status
            {
              pending: SolidQueue::Job.pending.count,
              processing: SolidQueue::Job.where(finished_at: nil).where.not(claimed_at: nil).count,
              finished: SolidQueue::Job.finished.count,
              failed: SolidQueue::FailedExecution.count
            }
          end

          def jobs_by_class
            SolidQueue::Job.where(created_at: 1.hour.ago..Time.current)
                           .group(:class_name)
                           .count
                           .sort_by { |_, count| -count }
                           .to_h
          end

          def average_wait_time
            jobs = SolidQueue::Job.finished
                                  .where(finished_at: 1.hour.ago..Time.current)
                                  .where.not(claimed_at: nil)

            return 0 if jobs.empty?

            wait_times = jobs.pluck(:created_at, :claimed_at).map do |created, claimed|
              (claimed - created).to_f
            end

            (wait_times.sum / wait_times.count).round(2)
          end

          def average_execution_time
            jobs = SolidQueue::Job.finished
                                  .where(finished_at: 1.hour.ago..Time.current)

            return 0 if jobs.empty?

            execution_times = jobs.pluck(:claimed_at, :finished_at).map do |claimed, finished|
              next unless claimed && finished
              (finished - claimed).to_f
            end.compact

            return 0 if execution_times.empty?

            (execution_times.sum / execution_times.count).round(2)
          end

          def calculate_failure_rate
            total = SolidQueue::Job.where(created_at: 1.hour.ago..Time.current).count
            failed = SolidQueue::FailedExecution.where(created_at: 1.hour.ago..Time.current).count

            return 0 if total == 0

            ((failed.to_f / total) * 100).round(2)
          end
        end
      end

      # Performance tracking module
      module PerformanceTracker
        extend ActiveSupport::Concern

        CACHE_PREFIX = "performance_metrics"

        class << self
          def metrics(component = nil)
            if component
              component_metrics(component)
            else
              all_metrics
            end
          end

          def track(component, operation, duration, metadata = {})
            key = "#{CACHE_PREFIX}:#{component}:#{operation}:#{Date.current}"

            data = Rails.cache.fetch(key, expires_in: 24.hours) { default_metrics }

            data[:count] += 1
            data[:total_duration] += duration
            data[:min_duration] = [ data[:min_duration], duration ].min
            data[:max_duration] = [ data[:max_duration], duration ].max
            data[:metadata] ||= {}

            metadata.each do |k, v|
              data[:metadata][k] ||= []
              data[:metadata][k] << v
            end

            Rails.cache.write(key, data, expires_in: 24.hours)
          end

          def component_metrics(component)
            pattern = "#{CACHE_PREFIX}:#{component}:*:#{Date.current}"

            metrics = {}

            Rails.cache.fetch_multi(*matching_keys(pattern)) do |key, data|
              operation = key.split(":")[2]

              metrics[operation] = {
                count: data[:count],
                average_duration: data[:count] > 0 ? (data[:total_duration] / data[:count]).round(3) : 0,
                min_duration: data[:min_duration],
                max_duration: data[:max_duration]
              }
            end

            metrics
          end

          def all_metrics
            components = {}

            pattern = "#{CACHE_PREFIX}:*:*:#{Date.current}"

            Rails.cache.fetch_multi(*matching_keys(pattern)) do |key, data|
              parts = key.split(":")
              component = parts[1]
              operation = parts[2]

              components[component] ||= {}
              components[component][operation] = {
                count: data[:count],
                average_duration: data[:count] > 0 ? (data[:total_duration] / data[:count]).round(3) : 0
              }
            end

            components
          end

          private

          def default_metrics
            {
              count: 0,
              total_duration: 0,
              min_duration: Float::INFINITY,
              max_duration: 0
            }
          end

          def matching_keys(pattern)
            # This would need to be adjusted based on cache store
            # For simplicity, returning empty array
            []
          end
        end
      end

      # Error tracking module
      module ErrorTracker
        extend ActiveSupport::Concern

        class << self
          def report(error, context = {})
            # Log the error
            Rails.logger.error "#{error.class}: #{error.message}"
            Rails.logger.error error.backtrace.join("\n") if error.backtrace

            # Store in database or cache for analytics
            store_error(error, context)

            # Send to external service if configured (Sentry, Rollbar, etc.)
            send_to_external_service(error, context) if external_service_configured?
          end

          def summary(time_window: 1.hour)
            errors = recent_errors(time_window)

            {
              total_errors: errors.count,
              errors_by_class: group_by_class(errors),
              errors_by_context: group_by_context(errors),
              top_errors: top_errors(errors),
              error_rate: calculate_error_rate(time_window)
            }
          end

          private

          def store_error(error, context)
            key = "errors:#{Time.current.to_i}"

            data = {
              class: error.class.name,
              message: error.message,
              backtrace: error.backtrace&.first(10),
              context: context,
              timestamp: Time.current
            }

            Rails.cache.write(key, data, expires_in: 24.hours)
          end

          def recent_errors(time_window)
            # Fetch errors from cache or database
            # Simplified implementation
            []
          end

          def group_by_class(errors)
            errors.group_by { |e| e[:class] }
                  .transform_values(&:count)
                  .sort_by { |_, count| -count }
                  .to_h
          end

          def group_by_context(errors)
            errors.group_by { |e| e[:context][:service] }
                  .transform_values(&:count)
                  .sort_by { |_, count| -count }
                  .to_h
          end

          def top_errors(errors, limit = 5)
            errors.group_by { |e| "#{e[:class]}: #{e[:message]}" }
                  .transform_values(&:count)
                  .sort_by { |_, count| -count }
                  .first(limit)
                  .to_h
          end

          def calculate_error_rate(time_window)
            # Calculate errors per minute
            total_errors = recent_errors(time_window).count
            minutes = (time_window / 60.0)

            (total_errors / minutes).round(2)
          end

          def external_service_configured?
            ENV["SENTRY_DSN"].present? || ENV["ROLLBAR_ACCESS_TOKEN"].present?
          end

          def send_to_external_service(error, context)
            # Integration with external error tracking services
            # Would be implemented based on specific service
          end
        end
      end

      # System health monitoring
      module SystemHealth
        extend ActiveSupport::Concern

        class << self
          def check
            {
              database: check_database,
              redis: check_redis,
              disk_space: check_disk_space,
              memory: check_memory,
              services: check_services,
              overall: calculate_overall_health
            }
          end

          private

          def check_database
            ActiveRecord::Base.connection.active?
            { status: "healthy", response_time: measure_db_response_time }
          rescue StandardError => e
            { status: "unhealthy", error: e.message }
          end

          def check_redis
            Rails.cache.redis.ping == "PONG"
            { status: "healthy", response_time: measure_redis_response_time }
          rescue StandardError => e
            { status: "unhealthy", error: e.message }
          end

          def check_disk_space
            # Check available disk space
            stats = Sys::Filesystem.stat("/")
            percent_used = ((stats.blocks - stats.blocks_available) * 100.0 / stats.blocks).round(2)

            status = if percent_used > 90
                       "critical"
            elsif percent_used > 80
                       "warning"
            else
                       "healthy"
            end

            { status: status, percent_used: percent_used }
          rescue StandardError
            { status: "unknown" }
          end

          def check_memory
            # Check memory usage
            memory_info = `free -m`.split("\n")[1].split
            total = memory_info[1].to_f
            used = memory_info[2].to_f
            percent_used = (used / total * 100).round(2)

            status = if percent_used > 90
                       "critical"
            elsif percent_used > 80
                       "warning"
            else
                       "healthy"
            end

            { status: status, percent_used: percent_used }
          rescue StandardError
            { status: "unknown" }
          end

          def check_services
            services = {}

            # Check critical services
            services[:solid_queue] = SolidQueue::Process.any? ? "running" : "stopped"
            services[:action_cable] = ActionCable.server.pubsub.redis_connection_for_subscriptions.ping rescue "unknown"

            services
          end

          def calculate_overall_health
            # Simple health calculation
            checks = [
              check_database[:status],
              check_redis[:status],
              check_disk_space[:status],
              check_memory[:status]
            ]

            if checks.any? { |c| c == "critical" || c == "unhealthy" }
              "unhealthy"
            elsif checks.any? { |c| c == "warning" }
              "degraded"
            else
              "healthy"
            end
          end

          def measure_db_response_time
            start = Time.current
            ActiveRecord::Base.connection.execute("SELECT 1")
            ((Time.current - start) * 1000).round(2)
          end

          def measure_redis_response_time
            start = Time.current
            Rails.cache.redis.ping
            ((Time.current - start) * 1000).round(2)
          end
        end
      end

      # Analytics module
      module Analytics
        extend ActiveSupport::Concern

        class << self
          def get_metrics(service: nil, time_window: 1.hour)
            base_metrics = {
              time_window: time_window,
              timestamp: Time.current,
              services: {}
            }

            if service
              base_metrics[:services][service] = service_metrics(service, time_window)
            else
              # Get metrics for all services
              %w[sync email_processing categorization bulk_categorization].each do |svc|
                base_metrics[:services][svc] = service_metrics(svc, time_window)
              end
            end

            base_metrics[:summary] = calculate_summary(base_metrics[:services])
            base_metrics
          end

          private

          def service_metrics(service, time_window)
            case service
            when "sync"
              sync_metrics(time_window)
            when "email_processing"
              email_processing_metrics(time_window)
            when "categorization"
              categorization_metrics(time_window)
            when "bulk_categorization"
              bulk_categorization_metrics(time_window)
            else
              {}
            end
          end

          def sync_metrics(time_window)
            sessions = SyncSession.where(created_at: time_window.ago..Time.current)

            {
              total_sessions: sessions.count,
              successful_sessions: sessions.completed.count,
              failed_sessions: sessions.failed.count,
              emails_processed: sessions.sum(:processed_emails_count),
              average_duration: calculate_average_duration(sessions)
            }
          end

          def email_processing_metrics(time_window)
            {
              emails_fetched: ProcessedEmail.where(created_at: time_window.ago..Time.current).count,
              expenses_created: Expense.where(created_at: time_window.ago..Time.current, source: "email").count
            }
          end

          def categorization_metrics(time_window)
            expenses = Expense.where(updated_at: time_window.ago..Time.current)
                              .where.not(category_id: nil)

            {
              total_categorized: expenses.count,
              auto_categorized: expenses.where(auto_categorized: true).count,
              manual_categorized: expenses.where(auto_categorized: false).count
            }
          end

          def bulk_categorization_metrics(time_window)
            operations = BulkOperation.where(
              created_at: time_window.ago..Time.current,
              operation_type: "categorization"
            )

            {
              total_operations: operations.count,
              expenses_affected: operations.sum(:affected_count),
              operations_undone: operations.where(undone: true).count
            }
          end

          def calculate_average_duration(sessions)
            completed = sessions.completed.where.not(completed_at: nil)

            return 0 if completed.empty?

            durations = completed.map do |s|
              (s.completed_at - s.started_at).to_f
            end

            (durations.sum / durations.count).round(2)
          end

          def calculate_summary(services)
            {
              total_operations: services.values.sum { |s| s[:total_sessions] || s[:total_operations] || 0 },
              success_rate: calculate_overall_success_rate(services),
              busiest_service: services.max_by { |_, metrics| metrics.values.select { |v| v.is_a?(Numeric) }.sum }[0]
            }
          end

          def calculate_overall_success_rate(services)
            total = 0
            successful = 0

            services.each do |_, metrics|
              if metrics[:total_sessions]
                total += metrics[:total_sessions]
                successful += metrics[:successful_sessions] || 0
              end
            end

            return 0 if total == 0

            ((successful.to_f / total) * 100).round(2)
          end
        end
      end
    end
  end
