# frozen_string_literal: true

module Services::Infrastructure
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

        def cache_metrics
          CacheMonitor.metrics
        end

        # Convenience method for recording metrics (delegates to PerformanceTracker)
        def record_metric(metric_name, data, tags: {})
          PerformanceTracker.record_custom_metric(metric_name, data, tags)
        end

        # Convenience method for recording errors (delegates to ErrorTracker)
        def record_error(error_name, details, tags: {})
          error = StandardError.new("#{error_name}: #{details.inspect}")
          ErrorTracker.report(error, tags)
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

          def record_custom_metric(metric_name, value, tags = {})
            key = "#{CACHE_PREFIX}:custom_metrics:#{metric_name}:#{Date.current}"

            data = Rails.cache.fetch(key, expires_in: 24.hours) { { values: [], tags: {} } }

            data[:values] << { value: value, timestamp: Time.current }
            data[:tags].merge!(tags)

            # Keep only last 1000 values to prevent memory bloat
            data[:values] = data[:values].last(1000)

            Rails.cache.write(key, data, expires_in: 24.hours)
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
            Infrastructure::CacheAdapter.matching_keys(pattern)
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

          def report_custom_error(error_name, details, tags = {})
            key = "custom_errors:#{error_name}:#{Time.current.to_i}"

            data = {
              error_name: error_name,
              details: details,
              tags: tags,
              timestamp: Time.current
            }

            Rails.cache.write(key, data, expires_in: 24.hours)

            # Also log the error
            Rails.logger.error "[CustomError] #{error_name}: #{details.inspect} (tags: #{tags.inspect})"
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

      # Cache monitoring module
      module CacheMonitor
        extend ActiveSupport::Concern

        class << self
          def metrics
            {
              pattern_cache: pattern_cache_metrics,
              rails_cache: rails_cache_metrics,
              performance: cache_performance_metrics,
              health: cache_health_status
            }
          end

          def pattern_cache_metrics
            return {} unless defined?(Categorization::PatternCache)

            cache = Services::Categorization::PatternCache.instance
            cache_metrics = cache.metrics

            {
              hit_rate: cache_metrics[:hit_rate],
              total_hits: cache_metrics[:hits],
              total_misses: cache_metrics[:misses],
              memory_entries: cache_metrics[:memory_cache_entries],
              redis_available: cache_metrics[:redis_available],
              average_lookup_time_ms: cache_metrics[:average_lookup_time_ms] || 0,
              warmup_status: warmup_status
            }
          rescue => e
            Rails.logger.error "Failed to get pattern cache metrics: #{e.message}"
            { error: e.message }
          end

          def rails_cache_metrics
            if Rails.cache.respond_to?(:stats)
              Rails.cache.stats
            else
              {
                type: Rails.cache.class.name,
                available: test_cache_availability
              }
            end
          end

          def cache_performance_metrics
            key_prefix = "performance_metrics:pattern_cache"

            # Fetch recent performance data
            recent_data = []
            10.times do |i|
              key = "#{key_prefix}:warming:#{(Date.current - i.days)}"
              if data = Rails.cache.read(key)
                recent_data << data
              end
            end

            return {} if recent_data.empty?

            durations = recent_data.map { |d| d[:duration] || 0 }.compact
            patterns_cached = recent_data.map { |d| d[:patterns] || 0 }.compact

            {
              average_warming_duration_seconds: durations.empty? ? 0 : (durations.sum / durations.size.to_f).round(3),
              average_patterns_warmed: patterns_cached.empty? ? 0 : (patterns_cached.sum / patterns_cached.size.to_f).round,
              last_warming_at: recent_data.first[:timestamp] || nil,
              warming_success_rate: calculate_warming_success_rate(recent_data)
            }
          end

          def cache_health_status
            pattern_cache_health = check_pattern_cache_health
            rails_cache_health = check_rails_cache_health

            overall_status = if pattern_cache_health[:status] == "healthy" && rails_cache_health[:status] == "healthy"
                                "healthy"
            elsif pattern_cache_health[:status] == "critical" || rails_cache_health[:status] == "critical"
                                "critical"
            else
                                "degraded"
            end

            {
              overall: overall_status,
              pattern_cache: pattern_cache_health,
              rails_cache: rails_cache_health,
              recommendations: generate_cache_recommendations(pattern_cache_health, rails_cache_health)
            }
          end

          private

          def warmup_status
            last_warmup_key = "pattern_cache:last_warmup"
            last_warmup = Rails.cache.read(last_warmup_key)

            return { status: "never_run" } unless last_warmup

            time_since = Time.current - last_warmup[:timestamp]

            status = if time_since < 20.minutes
                       "recent"
            elsif time_since < 1.hour
                       "stale"
            else
                       "outdated"
            end

            {
              status: status,
              last_run: last_warmup[:timestamp],
              minutes_ago: (time_since / 60).round
            }
          end

          def test_cache_availability
            Rails.cache.write("health_check_#{Time.current.to_i}", "test", expires_in: 1.second)
            true
          rescue
            false
          end

          def check_pattern_cache_health
            return { status: "not_configured" } unless defined?(Categorization::PatternCache)

            metrics = pattern_cache_metrics

            status = if metrics[:error]
                       "critical"
            elsif metrics[:hit_rate].to_f < 50
                       "degraded"
            elsif metrics[:hit_rate].to_f < 80
                       "warning"
            else
                       "healthy"
            end

            {
              status: status,
              hit_rate: metrics[:hit_rate],
              memory_usage: metrics[:memory_entries],
              issues: identify_pattern_cache_issues(metrics)
            }
          end

          def check_rails_cache_health
            available = test_cache_availability

            {
              status: available ? "healthy" : "critical",
              available: available
            }
          end

          def identify_pattern_cache_issues(metrics)
            issues = []

            issues << "Low hit rate (#{metrics[:hit_rate]}%)" if metrics[:hit_rate].to_f < 80
            issues << "High memory usage (#{metrics[:memory_entries]} entries)" if metrics[:memory_entries].to_i > 10_000
            issues << "Redis unavailable" unless metrics[:redis_available]
            issues << "Slow lookups (#{metrics[:average_lookup_time_ms]}ms)" if metrics[:average_lookup_time_ms].to_f > 5

            issues
          end

          def generate_cache_recommendations(pattern_cache_health, rails_cache_health)
            recommendations = []

            if pattern_cache_health[:hit_rate].to_f < 80
              recommendations << "Consider increasing cache warming frequency"
              recommendations << "Review pattern matching logic for optimization"
            end

            if pattern_cache_health[:memory_usage].to_i > 10_000
              recommendations << "Consider implementing cache eviction for old patterns"
            end

            unless rails_cache_health[:available]
              recommendations << "Critical: Rails cache is unavailable - check Redis/Solid Cache configuration"
            end

            recommendations
          end

          def calculate_warming_success_rate(recent_data)
            return 0 if recent_data.empty?

            successful = recent_data.count { |d| !d[:error] }
            ((successful.to_f / recent_data.size) * 100).round(2)
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
              emails_processed: sessions.sum(:processed_emails),
              average_duration: calculate_average_duration(sessions)
            }
          end

          def email_processing_metrics(time_window)
            {
              emails_fetched: ProcessedEmail.where(created_at: time_window.ago..Time.current).count,
              expenses_created: Expense.where(created_at: time_window.ago..Time.current)
                                       .where.not(raw_email_content: nil).count
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
              operation_type: :categorization
            )

            {
              total_operations: operations.count,
              expenses_affected: operations.sum(:expense_count),
              operations_undone: operations.undone.count
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
