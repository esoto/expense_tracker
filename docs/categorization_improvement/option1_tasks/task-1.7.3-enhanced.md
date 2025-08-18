### Task 1.7.3: Production Readiness and Monitoring (Enhanced)
**Priority**: HIGH  
**Estimated Hours**: 8-10
**Dependencies**: Task 1.7.2  
**Completion Status**: 60%

#### Executive Summary
Implement comprehensive monitoring, observability, and configuration management for production deployment with integration to existing Infrastructure::MonitoringService, proper metrics collection, alerting, and operational dashboards.

#### Current Issues
- Monitoring code exists but not wired to production metrics systems (Datadog/Prometheus)
- Missing correlation between service metrics and business outcomes
- No automated alerting for degraded performance
- Insufficient granularity in error tracking
- Health checks don't cover all critical paths

#### Technical Architecture

##### 1. Enhanced Metrics Collection with StatsD/Datadog Integration
```ruby
# app/services/categorization/monitoring/metrics_collector.rb
module Categorization
  module Monitoring
    class MetricsCollector
      include Singleton
      
      METRIC_PREFIX = 'categorization'
      
      def initialize
        @statsd = initialize_statsd_client
        @registry = Prometheus::Client.registry
        @metrics = initialize_prometheus_metrics
        @buffer = MetricsBuffer.new
      end
      
      # Track categorization attempt with detailed metrics
      def track_categorization(expense_id, result, duration_ms, context = {})
        correlation_id = context[:correlation_id] || SecureRandom.uuid
        
        # StatsD metrics for real-time monitoring
        tags = build_tags(result, context)
        
        @statsd.increment("#{METRIC_PREFIX}.attempts", tags: tags)
        @statsd.histogram("#{METRIC_PREFIX}.duration", duration_ms, tags: tags)
        @statsd.gauge("#{METRIC_PREFIX}.confidence", result.confidence, tags: tags)
        
        if result.successful?
          @statsd.increment("#{METRIC_PREFIX}.success", tags: tags)
          track_success_metrics(result, tags)
        else
          @statsd.increment("#{METRIC_PREFIX}.failure", tags: tags + ["error:#{result.error}"])
          track_failure_metrics(result, tags)
        end
        
        # Prometheus metrics for long-term trends
        @metrics[:categorization_total].increment(labels: prometheus_labels(result))
        @metrics[:categorization_duration].observe(duration_ms, labels: prometheus_labels(result))
        
        # Buffer for batch processing
        @buffer.add({
          expense_id: expense_id,
          result: result.to_h,
          duration_ms: duration_ms,
          correlation_id: correlation_id,
          timestamp: Time.current
        })
        
        # Send to monitoring service
        Infrastructure::MonitoringService::PerformanceTracker.track(
          'categorization',
          'process',
          duration_ms,
          {
            expense_id: expense_id,
            success: result.successful?,
            confidence: result.confidence,
            category_id: result.category&.id
          }
        )
      end
      
      # Track cache performance
      def track_cache_performance(operation, hit, duration_ms, cache_type = :pattern)
        tags = ["operation:#{operation}", "hit:#{hit}", "cache_type:#{cache_type}"]
        
        @statsd.increment("#{METRIC_PREFIX}.cache.#{operation}", tags: tags)
        @statsd.histogram("#{METRIC_PREFIX}.cache.duration", duration_ms, tags: tags)
        
        if hit
          @statsd.increment("#{METRIC_PREFIX}.cache.hits", tags: ["cache_type:#{cache_type}"])
        else
          @statsd.increment("#{METRIC_PREFIX}.cache.misses", tags: ["cache_type:#{cache_type}"])
        end
        
        update_cache_hit_rate(cache_type)
      end
      
      # Track pattern learning
      def track_pattern_learning(action, pattern_type, context = {})
        tags = [
          "action:#{action}",
          "pattern_type:#{pattern_type}",
          "source:#{context[:source] || 'manual'}"
        ]
        
        @statsd.increment("#{METRIC_PREFIX}.learning.events", tags: tags)
        
        case action
        when :created
          @statsd.increment("#{METRIC_PREFIX}.patterns.created", tags: tags)
        when :updated
          @statsd.increment("#{METRIC_PREFIX}.patterns.updated", tags: tags)
        when :merged
          @statsd.increment("#{METRIC_PREFIX}.patterns.merged", tags: tags)
        when :deactivated
          @statsd.increment("#{METRIC_PREFIX}.patterns.deactivated", tags: tags)
        end
        
        # Track learning effectiveness
        if context[:correction]
          track_learning_effectiveness(context[:correction])
        end
      end
      
      # Track service health
      def track_service_health(service_name, status, response_time_ms = nil)
        tags = ["service:#{service_name}", "status:#{status}"]
        
        @statsd.gauge("#{METRIC_PREFIX}.service.health", status == 'healthy' ? 1 : 0, tags: tags)
        
        if response_time_ms
          @statsd.histogram("#{METRIC_PREFIX}.service.response_time", response_time_ms, tags: tags)
        end
      end
      
      # Business metrics tracking
      def track_business_metrics
        # Track categorization coverage
        total_expenses = Expense.count
        categorized = Expense.where.not(category_id: nil).count
        coverage = total_expenses > 0 ? (categorized.to_f / total_expenses * 100) : 0
        
        @statsd.gauge("#{METRIC_PREFIX}.business.coverage", coverage)
        
        # Track accuracy (based on user corrections)
        corrections_today = PatternFeedback.where(
          created_at: Date.current.beginning_of_day..Date.current.end_of_day,
          feedback_type: 'correction'
        ).count
        
        total_categorizations_today = CategorizationMetric.where(
          created_at: Date.current.beginning_of_day..Date.current.end_of_day
        ).count
        
        accuracy = total_categorizations_today > 0 ? 
          ((total_categorizations_today - corrections_today).to_f / total_categorizations_today * 100) : 100
        
        @statsd.gauge("#{METRIC_PREFIX}.business.accuracy", accuracy)
        
        # Track value metrics
        auto_categorized_value = Expense.where(auto_categorized: true)
                                       .where(created_at: 1.day.ago..Time.current)
                                       .sum(:amount)
        
        @statsd.gauge("#{METRIC_PREFIX}.business.auto_categorized_value", auto_categorized_value)
      end
      
      # Flush buffered metrics
      def flush
        return if @buffer.empty?
        
        batch = @buffer.flush
        
        # Send to data warehouse for analysis
        CategorizationMetricsBatchJob.perform_later(batch) if batch.size > 100
        
        # Update aggregated metrics
        update_aggregated_metrics(batch)
      end
      
      private
      
      def initialize_statsd_client
        if Rails.env.production?
          Datadog::Statsd.new(
            ENV['STATSD_HOST'] || 'localhost',
            ENV['STATSD_PORT'] || 8125,
            namespace: 'expense_tracker',
            tags: ["env:#{Rails.env}", "app:categorization"]
          )
        else
          # Mock client for development/test
          MockStatsd.new
        end
      end
      
      def initialize_prometheus_metrics
        {
          categorization_total: @registry.counter(
            :categorization_total,
            docstring: 'Total number of categorization attempts',
            labels: [:status, :confidence_level, :category]
          ),
          categorization_duration: @registry.histogram(
            :categorization_duration_milliseconds,
            docstring: 'Categorization duration in milliseconds',
            labels: [:status],
            buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000]
          )
        }
      end
      
      def build_tags(result, context)
        tags = [
          "success:#{result.successful?}",
          "confidence_level:#{confidence_bucket(result.confidence)}",
          "has_error:#{result.error.present?}"
        ]
        
        tags << "category:#{result.category.name.parameterize}" if result.category
        tags << "source:#{context[:source]}" if context[:source]
        tags << "batch:true" if context[:batch]
        
        tags
      end
      
      def prometheus_labels(result)
        {
          status: result.successful? ? 'success' : 'failure',
          confidence_level: confidence_bucket(result.confidence),
          category: result.category&.name || 'uncategorized'
        }
      end
      
      def confidence_bucket(confidence)
        case confidence
        when 0.9..1.0 then 'very_high'
        when 0.7...0.9 then 'high'
        when 0.5...0.7 then 'medium'
        when 0.3...0.5 then 'low'
        else 'very_low'
        end
      end
      
      def track_success_metrics(result, tags)
        # Track pattern effectiveness
        result.patterns_used.each do |pattern|
          @statsd.increment("#{METRIC_PREFIX}.pattern.usage", 
            tags: ["pattern_id:#{pattern.id}", "pattern_type:#{pattern.pattern_type}"]
          )
        end
        
        # Track confidence distribution
        @statsd.histogram("#{METRIC_PREFIX}.confidence.distribution", 
          result.confidence * 100, tags: tags
        )
      end
      
      def track_failure_metrics(result, tags)
        # Track failure reasons
        failure_reason = determine_failure_reason(result)
        @statsd.increment("#{METRIC_PREFIX}.failure.reason", 
          tags: tags + ["reason:#{failure_reason}"]
        )
      end
      
      def determine_failure_reason(result)
        return 'error' if result.error.present?
        return 'no_patterns' if result.patterns_used.empty?
        return 'low_confidence' if result.confidence < 0.5
        'unknown'
      end
      
      def update_cache_hit_rate(cache_type)
        key = "cache_hit_rate:#{cache_type}:#{Time.current.strftime('%Y%m%d%H')}"
        
        Rails.cache.increment("#{key}:hits") if hit
        Rails.cache.increment("#{key}:total")
        
        # Calculate and report hourly hit rate
        if Time.current.min == 0 # On the hour
          calculate_and_report_hit_rate(cache_type)
        end
      end
      
      def track_learning_effectiveness(correction)
        # Track how quickly the system learns from corrections
        similar_expenses = Expense.where(
          merchant_name: correction.expense.merchant_name
        ).where(
          'created_at > ?', correction.created_at
        ).limit(10)
        
        correct_categorizations = similar_expenses.select { |e| 
          e.category_id == correction.correct_category_id 
        }.count
        
        effectiveness = similar_expenses.any? ? 
          (correct_categorizations.to_f / similar_expenses.count * 100) : 0
        
        @statsd.gauge("#{METRIC_PREFIX}.learning.effectiveness", effectiveness)
      end
      
      def update_aggregated_metrics(batch)
        # Update hourly aggregates
        hour_key = Time.current.strftime('%Y%m%d%H')
        
        Rails.cache.write(
          "#{METRIC_PREFIX}:aggregates:#{hour_key}",
          calculate_aggregates(batch),
          expires_in: 25.hours
        )
      end
    end
    
    # Metrics buffer for batch processing
    class MetricsBuffer
      def initialize(max_size: 1000, flush_interval: 60.seconds)
        @buffer = []
        @max_size = max_size
        @flush_interval = flush_interval
        @last_flush = Time.current
        @mutex = Mutex.new
      end
      
      def add(metric)
        @mutex.synchronize do
          @buffer << metric
          flush if should_flush?
        end
      end
      
      def flush
        @mutex.synchronize do
          return [] if @buffer.empty?
          
          batch = @buffer.dup
          @buffer.clear
          @last_flush = Time.current
          
          batch
        end
      end
      
      def empty?
        @buffer.empty?
      end
      
      private
      
      def should_flush?
        @buffer.size >= @max_size || 
        (Time.current - @last_flush) > @flush_interval
      end
    end
  end
end
```

##### 2. Structured Logging with Correlation
```ruby
# app/services/categorization/monitoring/structured_logger.rb
module Categorization
  module Monitoring
    class StructuredLogger
      class << self
        def log_categorization(expense, result, context = {})
          log_entry = build_categorization_log(expense, result, context)
          
          if result.successful?
            Rails.logger.info(log_entry.to_json)
          else
            Rails.logger.warn(log_entry.to_json)
          end
          
          # Send to centralized logging
          send_to_centralized_logging(log_entry) if Rails.env.production?
        end
        
        def log_batch_operation(expenses, results, context = {})
          log_entry = {
            event: 'batch_categorization',
            correlation_id: context[:correlation_id] || SecureRandom.uuid,
            batch_size: expenses.size,
            successful: results.count(&:successful?),
            failed: results.count { |r| !r.successful? },
            average_confidence: calculate_average_confidence(results),
            duration_ms: context[:duration_ms],
            timestamp: Time.current.iso8601
          }
          
          Rails.logger.info(log_entry.to_json)
        end
        
        def log_learning(expense, category, pattern, context = {})
          log_entry = {
            event: 'pattern_learning',
            correlation_id: context[:correlation_id] || SecureRandom.uuid,
            expense_id: expense.id,
            category_id: category.id,
            category_name: category.name,
            pattern_id: pattern&.id,
            pattern_type: pattern&.pattern_type,
            pattern_value: pattern&.pattern_value,
            action: context[:action],
            confidence_change: context[:confidence_change],
            timestamp: Time.current.iso8601
          }
          
          Rails.logger.info(log_entry.to_json)
        end
        
        def log_cache_operation(operation, cache_type, context = {})
          log_entry = {
            event: 'cache_operation',
            operation: operation,
            cache_type: cache_type,
            hit: context[:hit],
            entries: context[:entries],
            duration_ms: context[:duration_ms],
            correlation_id: context[:correlation_id],
            timestamp: Time.current.iso8601
          }
          
          Rails.logger.debug(log_entry.to_json)
        end
        
        def log_error(error, context = {})
          log_entry = {
            event: 'categorization_error',
            error_class: error.class.name,
            error_message: error.message,
            backtrace: error.backtrace&.first(10),
            correlation_id: context[:correlation_id] || SecureRandom.uuid,
            expense_id: context[:expense_id],
            service: context[:service] || 'categorization',
            severity: determine_severity(error),
            timestamp: Time.current.iso8601
          }
          
          Rails.logger.error(log_entry.to_json)
          
          # Report to error tracking
          Infrastructure::MonitoringService::ErrorTracker.report(error, context)
        end
        
        def log_performance_warning(component, metric, value, threshold, context = {})
          log_entry = {
            event: 'performance_warning',
            component: component,
            metric: metric,
            value: value,
            threshold: threshold,
            exceeded_by: value - threshold,
            correlation_id: context[:correlation_id],
            timestamp: Time.current.iso8601
          }
          
          Rails.logger.warn(log_entry.to_json)
        end
        
        private
        
        def build_categorization_log(expense, result, context)
          {
            event: 'categorization',
            correlation_id: result.correlation_id || context[:correlation_id],
            expense: {
              id: expense.id,
              merchant: expense.merchant_name,
              description: expense.description&.first(100),
              amount: expense.amount,
              created_at: expense.created_at
            },
            result: {
              successful: result.successful?,
              category_id: result.category&.id,
              category_name: result.category&.name,
              confidence: result.confidence,
              confidence_level: result.confidence_level,
              patterns_used: result.patterns_used.map { |p| 
                { id: p.id, type: p.pattern_type, value: p.pattern_value }
              },
              explanation: result.explanation,
              error: result.error
            },
            performance: {
              duration_ms: context[:duration_ms],
              cache_hits: context[:cache_hits],
              patterns_evaluated: context[:patterns_evaluated]
            },
            metadata: {
              source: context[:source] || 'manual',
              batch: context[:batch] || false,
              retry_count: context[:retry_count] || 0
            },
            timestamp: Time.current.iso8601
          }
        end
        
        def calculate_average_confidence(results)
          successful = results.select(&:successful?)
          return 0 if successful.empty?
          
          (successful.sum(&:confidence) / successful.size).round(3)
        end
        
        def determine_severity(error)
          case error
          when ActiveRecord::RecordNotFound
            'low'
          when Redis::CannotConnectError, PG::ConnectionBad
            'critical'
          when StandardError
            'medium'
          else
            'high'
          end
        end
        
        def send_to_centralized_logging(log_entry)
          # Send to ELK stack or similar
          LogstashClient.send(log_entry) if defined?(LogstashClient)
        rescue => e
          Rails.logger.error "Failed to send to centralized logging: #{e.message}"
        end
      end
    end
  end
end
```

##### 3. Health Check System
```ruby
# app/services/categorization/monitoring/health_check.rb
module Categorization
  module Monitoring
    class HealthCheck
      HEALTH_CHECK_CACHE_KEY = 'categorization:health:status'
      CACHE_TTL = 30.seconds
      
      class << self
        def status(detailed: false)
          Rails.cache.fetch(HEALTH_CHECK_CACHE_KEY, expires_in: CACHE_TTL) do
            perform_health_check(detailed)
          end
        end
        
        def live?
          # Kubernetes liveness probe - basic check
          ActiveRecord::Base.connection.active? && 
          Redis.current.ping == 'PONG'
        rescue
          false
        end
        
        def ready?
          # Kubernetes readiness probe - full service check
          status[:overall_status] == 'healthy'
        rescue
          false
        end
        
        private
        
        def perform_health_check(detailed)
          checks = {
            database: check_database,
            redis: check_redis,
            pattern_cache: check_pattern_cache,
            services: check_services,
            background_jobs: check_background_jobs,
            data_quality: check_data_quality
          }
          
          overall_status = calculate_overall_status(checks)
          
          health_report = {
            status: overall_status,
            timestamp: Time.current.iso8601,
            checks: checks,
            metrics: collect_health_metrics,
            recommendations: generate_recommendations(checks)
          }
          
          health_report[:details] = collect_detailed_info(checks) if detailed
          
          # Track health status
          MetricsCollector.instance.track_service_health(
            'categorization_engine',
            overall_status
          )
          
          health_report
        end
        
        def check_database
          start = Time.current
          
          # Check connection
          ActiveRecord::Base.connection.execute('SELECT 1')
          
          # Check critical tables
          pattern_count = CategorizationPattern.count
          category_count = Category.count
          
          response_time = (Time.current - start) * 1000
          
          status = if response_time > 100
                    'degraded'
                  elsif pattern_count == 0 || category_count == 0
                    'unhealthy'
                  else
                    'healthy'
                  end
          
          {
            status: status,
            response_time_ms: response_time.round(2),
            pattern_count: pattern_count,
            category_count: category_count
          }
        rescue => e
          { status: 'unhealthy', error: e.message }
        end
        
        def check_redis
          start = Time.current
          
          # Check connection
          Redis.current.ping
          
          # Check memory usage
          info = Redis.current.info('memory')
          used_memory_mb = info['used_memory'].to_f / 1.megabyte
          max_memory_mb = info['maxmemory'].to_f / 1.megabyte
          
          response_time = (Time.current - start) * 1000
          
          status = if response_time > 20
                    'degraded'
                  elsif max_memory_mb > 0 && (used_memory_mb / max_memory_mb) > 0.9
                    'warning'
                  else
                    'healthy'
                  end
          
          {
            status: status,
            response_time_ms: response_time.round(2),
            memory_used_mb: used_memory_mb.round(2),
            memory_max_mb: max_memory_mb.round(2)
          }
        rescue => e
          { status: 'unhealthy', error: e.message }
        end
        
        def check_pattern_cache
          return { status: 'not_initialized' } unless defined?(PatternCache)
          
          cache = PatternCache.instance
          metrics = cache.metrics
          
          status = if metrics[:hit_rate] < 50
                    'unhealthy'
                  elsif metrics[:hit_rate] < 80
                    'degraded'
                  else
                    'healthy'
                  end
          
          {
            status: status,
            hit_rate: metrics[:hit_rate],
            entries: metrics[:memory_cache_entries],
            memory_used_mb: (metrics[:memory_used] / 1.megabyte).round(2),
            last_warmup: metrics[:last_warmup],
            redis_available: metrics[:redis_available]
          }
        rescue => e
          { status: 'unhealthy', error: e.message }
        end
        
        def check_services
          registry = ServiceRegistry.instance
          service_status = registry.health_status
          
          unhealthy_services = service_status.select { |_, status| 
            status[:status] != 'healthy' 
          }
          
          overall = if unhealthy_services.any?
                     'degraded'
                   else
                     'healthy'
                   end
          
          {
            status: overall,
            services: service_status,
            unhealthy_count: unhealthy_services.size
          }
        rescue => e
          { status: 'unhealthy', error: e.message }
        end
        
        def check_background_jobs
          # Check Solid Queue health
          failed_jobs = SolidQueue::FailedExecution.where(
            created_at: 1.hour.ago..Time.current
          ).count
          
          pending_jobs = SolidQueue::Job.pending.count
          
          status = if failed_jobs > 100
                    'unhealthy'
                  elsif failed_jobs > 50 || pending_jobs > 1000
                    'degraded'
                  else
                    'healthy'
                  end
          
          {
            status: status,
            failed_jobs_1h: failed_jobs,
            pending_jobs: pending_jobs,
            workers_active: SolidQueue::Process.where(kind: 'Worker').count
          }
        rescue => e
          { status: 'unhealthy', error: e.message }
        end
        
        def check_data_quality
          # Check pattern quality
          low_success_patterns = CategorizationPattern.active
                                                      .where('usage_count > 10')
                                                      .where('success_rate < 0.5')
                                                      .count
          
          # Check categorization coverage
          total_expenses = Expense.count
          categorized = Expense.where.not(category_id: nil).count
          coverage = total_expenses > 0 ? (categorized.to_f / total_expenses * 100) : 0
          
          status = if low_success_patterns > 20 || coverage < 50
                    'unhealthy'
                  elsif low_success_patterns > 10 || coverage < 70
                    'degraded'
                  else
                    'healthy'
                  end
          
          {
            status: status,
            low_success_patterns: low_success_patterns,
            categorization_coverage: coverage.round(2),
            total_patterns: CategorizationPattern.active.count
          }
        rescue => e
          { status: 'unhealthy', error: e.message }
        end
        
        def calculate_overall_status(checks)
          statuses = checks.values.map { |c| c[:status] }
          
          if statuses.any? { |s| s == 'unhealthy' }
            'unhealthy'
          elsif statuses.any? { |s| s == 'degraded' }
            'degraded'
          elsif statuses.any? { |s| s == 'warning' }
            'warning'
          else
            'healthy'
          end
        end
        
        def collect_health_metrics
          {
            patterns_total: CategorizationPattern.count,
            patterns_active: CategorizationPattern.active.count,
            categories_total: Category.count,
            avg_pattern_success_rate: CategorizationPattern.active.average(:success_rate)&.round(3),
            recent_categorizations: CategorizationMetric.where(
              created_at: 1.hour.ago..Time.current
            ).count,
            recent_success_rate: calculate_recent_success_rate
          }
        end
        
        def calculate_recent_success_rate
          recent = CategorizationMetric.where(created_at: 1.hour.ago..Time.current)
          return 0 if recent.empty?
          
          (recent.where(successful: true).count.to_f / recent.count * 100).round(2)
        end
        
        def generate_recommendations(checks)
          recommendations = []
          
          # Database recommendations
          if checks[:database][:status] != 'healthy'
            if checks[:database][:response_time_ms] > 100
              recommendations << 'Database queries are slow - consider adding indexes'
            end
            if checks[:database][:pattern_count] == 0
              recommendations << 'No categorization patterns found - run seed data'
            end
          end
          
          # Cache recommendations
          if checks[:pattern_cache][:status] != 'healthy'
            if checks[:pattern_cache][:hit_rate] < 80
              recommendations << 'Low cache hit rate - increase cache warmup frequency'
            end
          end
          
          # Background job recommendations
          if checks[:background_jobs][:failed_jobs_1h] > 50
            recommendations << 'High job failure rate - check job logs for errors'
          end
          
          # Data quality recommendations
          if checks[:data_quality][:low_success_patterns] > 10
            recommendations << 'Many patterns have low success rates - review and update patterns'
          end
          
          recommendations
        end
        
        def collect_detailed_info(checks)
          {
            top_patterns: CategorizationPattern.active
                                              .order(usage_count: :desc)
                                              .limit(10)
                                              .pluck(:pattern_value, :usage_count, :success_rate),
            recent_errors: fetch_recent_errors,
            performance_stats: fetch_performance_stats
          }
        end
        
        def fetch_recent_errors
          # Fetch from error tracking service
          []
        end
        
        def fetch_performance_stats
          {
            p50: calculate_percentile(50),
            p95: calculate_percentile(95),
            p99: calculate_percentile(99)
          }
        end
        
        def calculate_percentile(percentile)
          # Calculate from recent metrics
          0
        end
      end
    end
  end
end
```

##### 4. Production Configuration
```yaml
# config/categorization.yml
default: &default
  monitoring:
    enabled: false
    statsd:
      host: localhost
      port: 8125
      namespace: expense_tracker
    prometheus:
      enabled: false
      port: 9090
    logging:
      level: info
      structured: true
  
  cache:
    memory:
      size_mb: 50
      ttl_minutes: 5
    redis:
      ttl_hours: 24
      max_connections: 10
  
  performance:
    max_response_time_ms: 10
    batch_size: 100
    parallel_workers: 4
  
  circuit_breaker:
    failure_threshold: 5
    timeout_seconds: 30
    half_open_requests: 1

development:
  <<: *default
  monitoring:
    enabled: false
    logging:
      level: debug

test:
  <<: *default
  cache:
    memory:
      size_mb: 10
      ttl_minutes: 1

staging:
  <<: *default
  monitoring:
    enabled: true
    statsd:
      host: <%= ENV['STATSD_HOST'] %>
      port: <%= ENV['STATSD_PORT'] %>
    prometheus:
      enabled: true
      port: <%= ENV['PROMETHEUS_PORT'] || 9090 %>
    logging:
      level: info
      structured: true

production:
  <<: *default
  monitoring:
    enabled: true
    statsd:
      host: <%= ENV['STATSD_HOST'] %>
      port: <%= ENV['STATSD_PORT'] %>
      namespace: expense_tracker_prod
    prometheus:
      enabled: true
      port: <%= ENV['PROMETHEUS_PORT'] || 9090 %>
    datadog:
      enabled: <%= ENV['DATADOG_ENABLED'] == 'true' %>
      api_key: <%= ENV['DATADOG_API_KEY'] %>
      app_key: <%= ENV['DATADOG_APP_KEY'] %>
    sentry:
      enabled: <%= ENV['SENTRY_DSN'].present? %>
      dsn: <%= ENV['SENTRY_DSN'] %>
      environment: production
    logging:
      level: warn
      structured: true
      centralized: true
      logstash:
        host: <%= ENV['LOGSTASH_HOST'] %>
        port: <%= ENV['LOGSTASH_PORT'] || 5000 %>
  
  cache:
    memory:
      size_mb: 500
      ttl_minutes: 15
    redis:
      ttl_hours: 48
      max_connections: 50
      connection_pool_size: 25
  
  performance:
    max_response_time_ms: 10
    batch_size: 500
    parallel_workers: 8
  
  alerts:
    low_success_rate: 85
    high_error_rate: 5
    slow_response_ms: 15
    low_cache_hit_rate: 80
    high_memory_usage_mb: 1000
```

##### 5. Alert Configuration
```ruby
# app/services/categorization/monitoring/alerting.rb
module Categorization
  module Monitoring
    class Alerting
      ALERT_COOLDOWN = 5.minutes
      
      class << self
        def check_and_alert
          alerts = []
          
          # Check success rate
          if (alert = check_success_rate)
            alerts << alert
          end
          
          # Check response time
          if (alert = check_response_time)
            alerts << alert
          end
          
          # Check error rate
          if (alert = check_error_rate)
            alerts << alert
          end
          
          # Check cache performance
          if (alert = check_cache_performance)
            alerts << alert
          end
          
          # Send alerts
          alerts.each { |alert| send_alert(alert) }
          
          alerts
        end
        
        private
        
        def check_success_rate
          recent_metrics = CategorizationMetric.where(
            created_at: 15.minutes.ago..Time.current
          )
          
          return nil if recent_metrics.count < 100
          
          success_rate = (recent_metrics.where(successful: true).count.to_f / 
                         recent_metrics.count * 100)
          
          threshold = Rails.configuration.categorization[:alerts][:low_success_rate]
          
          if success_rate < threshold && !recently_alerted?('low_success_rate')
            {
              type: 'low_success_rate',
              severity: 'high',
              message: "Categorization success rate dropped to #{success_rate.round(2)}%",
              value: success_rate,
              threshold: threshold
            }
          end
        end
        
        def check_response_time
          recent_metrics = CategorizationMetric.where(
            created_at: 5.minutes.ago..Time.current
          ).where.not(duration_ms: nil)
          
          return nil if recent_metrics.empty?
          
          avg_response_time = recent_metrics.average(:duration_ms)
          p95_response_time = calculate_percentile(recent_metrics.pluck(:duration_ms), 95)
          
          threshold = Rails.configuration.categorization[:alerts][:slow_response_ms]
          
          if p95_response_time > threshold && !recently_alerted?('slow_response')
            {
              type: 'slow_response',
              severity: 'medium',
              message: "P95 response time is #{p95_response_time.round(2)}ms",
              value: p95_response_time,
              threshold: threshold,
              avg_response_time: avg_response_time
            }
          end
        end
        
        def check_error_rate
          total_attempts = CategorizationMetric.where(
            created_at: 10.minutes.ago..Time.current
          ).count
          
          return nil if total_attempts < 100
          
          errors = CategorizationMetric.where(
            created_at: 10.minutes.ago..Time.current
          ).where.not(error_message: nil).count
          
          error_rate = (errors.to_f / total_attempts * 100)
          threshold = Rails.configuration.categorization[:alerts][:high_error_rate]
          
          if error_rate > threshold && !recently_alerted?('high_error_rate')
            {
              type: 'high_error_rate',
              severity: 'critical',
              message: "Error rate increased to #{error_rate.round(2)}%",
              value: error_rate,
              threshold: threshold
            }
          end
        end
        
        def check_cache_performance
          cache_metrics = PatternCache.instance.metrics
          hit_rate = cache_metrics[:hit_rate]
          
          threshold = Rails.configuration.categorization[:alerts][:low_cache_hit_rate]
          
          if hit_rate < threshold && !recently_alerted?('low_cache_hit_rate')
            {
              type: 'low_cache_hit_rate',
              severity: 'medium',
              message: "Cache hit rate dropped to #{hit_rate.round(2)}%",
              value: hit_rate,
              threshold: threshold
            }
          end
        end
        
        def recently_alerted?(alert_type)
          last_alert_key = "alerts:last_sent:#{alert_type}"
          last_alert_time = Rails.cache.read(last_alert_key)
          
          last_alert_time && (Time.current - last_alert_time) < ALERT_COOLDOWN
        end
        
        def send_alert(alert)
          # Send to multiple channels based on severity
          case alert[:severity]
          when 'critical'
            send_pagerduty_alert(alert)
            send_slack_alert(alert, channel: '#critical-alerts')
            send_email_alert(alert)
          when 'high'
            send_slack_alert(alert, channel: '#alerts')
            send_email_alert(alert)
          when 'medium'
            send_slack_alert(alert, channel: '#monitoring')
          end
          
          # Mark alert as sent
          Rails.cache.write("alerts:last_sent:#{alert[:type]}", Time.current)
          
          # Log alert
          Rails.logger.warn({
            event: 'alert_sent',
            alert: alert,
            timestamp: Time.current.iso8601
          }.to_json)
        end
        
        def send_pagerduty_alert(alert)
          # PagerDuty integration
        end
        
        def send_slack_alert(alert, channel:)
          # Slack integration
        end
        
        def send_email_alert(alert)
          # Email integration
        end
        
        def calculate_percentile(values, percentile)
          sorted = values.sort
          index = (percentile / 100.0 * sorted.length).ceil - 1
          sorted[index]
        end
      end
    end
  end
end
```

#### Health Check Controller
```ruby
# app/controllers/api/v1/health_controller.rb
module Api
  module V1
    class HealthController < ApplicationController
      skip_before_action :authenticate_user!
      
      def show
        health_status = Categorization::Monitoring::HealthCheck.status(
          detailed: params[:detailed] == 'true'
        )
        
        http_status = case health_status[:status]
                     when 'healthy' then :ok
                     when 'degraded', 'warning' then :ok
                     else :service_unavailable
                     end
        
        render json: health_status, status: http_status
      end
      
      def live
        if Categorization::Monitoring::HealthCheck.live?
          head :ok
        else
          head :service_unavailable
        end
      end
      
      def ready
        if Categorization::Monitoring::HealthCheck.ready?
          head :ok
        else
          head :service_unavailable
        end
      end
      
      def metrics
        # Prometheus endpoint
        render plain: Prometheus::Client::Formats::Text.marshal(
          Prometheus::Client.registry
        )
      end
    end
  end
end

# config/routes.rb
namespace :api do
  namespace :v1 do
    get 'health', to: 'health#show'
    get 'health/live', to: 'health#live'
    get 'health/ready', to: 'health#ready'
    get 'metrics', to: 'health#metrics'
  end
end
```

#### Kubernetes Configuration
```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: expense-tracker-categorization
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: expense-tracker:latest
        ports:
        - containerPort: 3000
        - containerPort: 9090  # Prometheus metrics
        env:
        - name: STATSD_HOST
          value: "datadog-agent.monitoring.svc.cluster.local"
        - name: STATSD_PORT
          value: "8125"
        livenessProbe:
          httpGet:
            path: /api/v1/health/live
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/v1/health/ready
            port: 3000
          initialDelaySeconds: 20
          periodSeconds: 5
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"

---
apiVersion: v1
kind: Service
metadata:
  name: expense-tracker-metrics
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
spec:
  ports:
  - name: metrics
    port: 9090
    targetPort: 9090
```

#### Operations Runbook

```markdown
# Categorization Service Operations Runbook

## Service Overview
The categorization service uses pattern matching and machine learning to automatically categorize expenses.

## Architecture
- **Engine**: Main orchestration service
- **Pattern Cache**: In-memory and Redis-backed pattern storage
- **Fuzzy Matcher**: Text similarity matching
- **Confidence Calculator**: Scoring algorithm
- **Pattern Learner**: ML feedback loop

## Key Metrics Dashboard

### Business Metrics
- **Categorization Coverage**: Target >95%
- **Accuracy Rate**: Target >90%
- **Auto-categorized Value**: $ processed automatically

### Performance Metrics
- **Response Time P50**: Target <5ms
- **Response Time P95**: Target <10ms
- **Response Time P99**: Target <15ms
- **Throughput**: Categorizations per second

### System Metrics
- **Cache Hit Rate**: Target >90%
- **Error Rate**: Target <1%
- **Memory Usage**: Target <500MB
- **CPU Usage**: Target <50%

## Common Issues and Solutions

### Issue: High Response Times
**Symptoms**:
- P95 response time >15ms
- User complaints about slow categorization

**Diagnosis**:
1. Check cache hit rate: `curl /api/v1/health?detailed=true | jq '.checks.pattern_cache'`
2. Check database query performance
3. Review pattern count and complexity

**Solutions**:
1. Warm cache: `rails runner 'PatternCacheWarmupJob.perform_now'`
2. Optimize patterns: Remove low-performing patterns
3. Scale horizontally: Increase pod replicas

### Issue: Low Success Rate
**Symptoms**:
- Success rate <85%
- Many uncategorized expenses

**Diagnosis**:
1. Check pattern quality: Review low success patterns
2. Check data quality: Verify expense data completeness
3. Review recent pattern changes

**Solutions**:
1. Update patterns based on feedback
2. Retrain with recent data
3. Lower confidence threshold temporarily

### Issue: Memory Leak
**Symptoms**:
- Steadily increasing memory usage
- OOM kills

**Diagnosis**:
1. Check cache size: Pattern cache entries
2. Review buffered metrics
3. Check for circular references

**Solutions**:
1. Clear cache: `rails runner 'Categorization::PatternCache.instance.clear!'`
2. Restart pods: `kubectl rollout restart deployment expense-tracker`
3. Reduce cache TTL

## Maintenance Tasks

### Daily
- Review alert dashboard
- Check success rate metrics
- Monitor error logs

### Weekly
- Analyze pattern performance
- Review and merge similar patterns
- Update confidence thresholds

### Monthly
- Full pattern audit
- Performance baseline review
- Capacity planning

## Emergency Procedures

### Complete Service Failure
1. Check health endpoint: `curl /api/v1/health`
2. Review pod status: `kubectl get pods`
3. Check logs: `kubectl logs -l app=expense-tracker --tail=100`
4. Failover to manual categorization if needed

### Database Connection Issues
1. Verify database connectivity
2. Check connection pool usage
3. Restart connection pool if needed
4. Scale down workers if database is overloaded

### Redis Failure
1. Service automatically falls back to database
2. Performance will be degraded but functional
3. Monitor memory usage closely
4. Restore Redis ASAP

## Performance Tuning

### Cache Optimization
```ruby
# Adjust cache size
Rails.application.config.categorization[:cache][:memory][:size_mb] = 1000

# Increase TTL
Rails.application.config.categorization[:cache][:redis][:ttl_hours] = 72
```

### Pattern Optimization
```sql
-- Find low-performing patterns
SELECT pattern_value, success_rate, usage_count 
FROM categorization_patterns 
WHERE usage_count > 100 AND success_rate < 0.5
ORDER BY usage_count DESC;

-- Deactivate bad patterns
UPDATE categorization_patterns 
SET active = false 
WHERE success_rate < 0.3 AND usage_count > 50;
```

## Monitoring Queries

### Datadog
```
# Success rate
avg:categorization.success.rate{env:production} by {category}

# Response time
avg:categorization.duration{env:production}.rollup(avg, 300)

# Error rate
sum:categorization.failure{env:production}.as_rate()
```

### Prometheus
```
# Success rate
rate(categorization_total{status="success"}[5m]) / rate(categorization_total[5m])

# P95 response time
histogram_quantile(0.95, rate(categorization_duration_milliseconds_bucket[5m]))
```

## Contact Information
- On-call: #oncall-categorization
- Slack: #team-categorization
- PagerDuty: categorization-service
```

#### Testing Requirements
```ruby
# spec/services/categorization/monitoring/metrics_collector_spec.rb
RSpec.describe Categorization::Monitoring::MetricsCollector do
  let(:collector) { described_class.instance }
  let(:result) { build(:categorization_result, successful: true, confidence: 0.85) }
  
  describe '#track_categorization' do
    it 'sends metrics to StatsD' do
      expect(collector.statsd).to receive(:increment).with('categorization.attempts', anything)
      expect(collector.statsd).to receive(:histogram).with('categorization.duration', anything, anything)
      
      collector.track_categorization(1, result, 10.5)
    end
    
    it 'tracks success metrics' do
      expect(collector.statsd).to receive(:increment).with('categorization.success', anything)
      
      collector.track_categorization(1, result, 10.5)
    end
  end
  
  describe '#track_business_metrics' do
    before do
      create_list(:expense, 10, category: create(:category))
      create_list(:expense, 5, category: nil)
    end
    
    it 'tracks categorization coverage' do
      expect(collector.statsd).to receive(:gauge).with('categorization.business.coverage', 66.67)
      
      collector.track_business_metrics
    end
  end
end

# spec/services/categorization/monitoring/health_check_spec.rb
RSpec.describe Categorization::Monitoring::HealthCheck do
  describe '.status' do
    it 'returns comprehensive health status' do
      status = described_class.status
      
      expect(status).to include(:status, :timestamp, :checks, :metrics, :recommendations)
      expect(status[:checks]).to include(:database, :redis, :pattern_cache, :services)
    end
    
    it 'identifies unhealthy components' do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(false)
      
      status = described_class.status
      
      expect(status[:status]).to eq('unhealthy')
      expect(status[:checks][:database][:status]).to eq('unhealthy')
    end
  end
  
  describe '.ready?' do
    it 'returns true when healthy' do
      allow(described_class).to receive(:status).and_return({ overall_status: 'healthy' })
      
      expect(described_class.ready?).to be true
    end
    
    it 'returns false when unhealthy' do
      allow(described_class).to receive(:status).and_return({ overall_status: 'unhealthy' })
      
      expect(described_class.ready?).to be false
    end
  end
end
```

#### Rollout Plan
1. **Phase 1**: Deploy monitoring infrastructure (StatsD, Prometheus)
2. **Phase 2**: Enable structured logging in staging
3. **Phase 3**: Configure alerts with low thresholds
4. **Phase 4**: Production deployment with gradual rollout
5. **Phase 5**: Tune thresholds based on baseline data

#### Success Metrics
- Health check response time: <100ms
- Alert accuracy: >95% (not false positives)
- Mean time to detection (MTTD): <2 minutes
- Mean time to resolution (MTTR): <15 minutes
- Observability coverage: 100% of critical paths

## UX Specifications for Production Monitoring Dashboard

### Overview
The Production Monitoring Dashboard provides comprehensive real-time observability into the categorization system's operational health, performance metrics, and business KPIs. This interface serves DevOps teams, system administrators, and business stakeholders with tailored views and actionable insights.

### Information Architecture

#### Multi-Persona Navigation Structure
```
Operations Dashboard (Root)
├── Executive Summary (Business View)
│   ├── Business KPIs
│   ├── Cost Analysis
│   └── ROI Metrics
├── Operations Center (DevOps View)
│   ├── System Health
│   ├── Performance Metrics
│   ├── Alert Management
│   └── Incident Response
├── Analytics Hub (Data View)
│   ├── Categorization Analytics
│   ├── Pattern Performance
│   └── Learning Effectiveness
└── Configuration Center
    ├── Alert Rules
    ├── Thresholds
    └── Notification Channels
```

### UI Components and Design Specifications

#### 1. Operations Center Main Dashboard

##### Layout and Structure
```erb
<!-- app/views/admin/categorization/operations/index.html.erb -->
<div class="min-h-screen bg-slate-50" data-controller="operations-dashboard" 
     data-operations-dashboard-auto-refresh-value="true"
     data-operations-dashboard-refresh-interval-value="10000">
  
  <!-- Fixed Header with Global Status -->
  <div class="bg-white border-b border-slate-200 sticky top-0 z-50 shadow-sm">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex justify-between items-center py-3">
        <!-- Logo and Title -->
        <div class="flex items-center space-x-4">
          <h1 class="text-xl font-bold text-slate-900">Operations Center</h1>
          
          <!-- Environment Badge -->
          <span class="px-2 py-1 text-xs font-medium rounded-full 
                       <%= Rails.env.production? ? 'bg-rose-100 text-rose-700' : 'bg-amber-100 text-amber-700' %>">
            <%= Rails.env.upcase %>
          </span>
          
          <!-- Last Update Time -->
          <span class="text-xs text-slate-500" data-operations-dashboard-target="lastUpdate">
            Updated: <time data-operations-dashboard-target="updateTime">--</time>
          </span>
        </div>
        
        <!-- Quick Actions Bar -->
        <div class="flex items-center space-x-3">
          <!-- Alert Summary -->
          <div class="flex items-center space-x-2 px-3 py-1 bg-slate-100 rounded-lg">
            <span class="relative flex h-3 w-3">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"
                    data-operations-dashboard-target="alertPulse"></span>
              <span class="relative inline-flex rounded-full h-3 w-3 bg-rose-500"
                    data-operations-dashboard-target="alertIndicator"></span>
            </span>
            <span class="text-sm font-medium text-slate-700">
              <span data-operations-dashboard-target="activeAlerts">0</span> Active Alerts
            </span>
          </div>
          
          <!-- View Switcher -->
          <div class="flex bg-slate-100 rounded-lg p-1" role="tablist">
            <button class="px-3 py-1 text-sm font-medium rounded-md bg-white text-slate-900"
                    role="tab" aria-selected="true"
                    data-action="click->operations-dashboard#switchView"
                    data-view="operations">
              Operations
            </button>
            <button class="px-3 py-1 text-sm font-medium text-slate-600 hover:text-slate-900"
                    role="tab" aria-selected="false"
                    data-action="click->operations-dashboard#switchView"
                    data-view="business">
              Business
            </button>
            <button class="px-3 py-1 text-sm font-medium text-slate-600 hover:text-slate-900"
                    role="tab" aria-selected="false"
                    data-action="click->operations-dashboard#switchView"
                    data-view="analytics">
              Analytics
            </button>
          </div>
          
          <!-- Settings Menu -->
          <button data-action="click->operations-dashboard#toggleSettings"
                  class="p-2 text-slate-600 hover:text-slate-900 rounded-lg hover:bg-slate-100">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                    d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
            </svg>
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Main Content Area -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <!-- Critical Metrics Overview -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
      <!-- Uptime Card -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm font-medium text-slate-600">System Uptime</span>
          <svg class="w-5 h-5 text-emerald-500" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
          </svg>
        </div>
        <div class="flex items-baseline space-x-2">
          <span class="text-3xl font-bold text-slate-900" data-operations-dashboard-target="uptime">99.99</span>
          <span class="text-lg text-slate-500">%</span>
        </div>
        <div class="mt-2 text-xs text-slate-500">
          Last incident: <span data-operations-dashboard-target="lastIncident">3 days ago</span>
        </div>
      </div>

      <!-- Error Rate Card -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm font-medium text-slate-600">Error Rate</span>
          <div data-operations-dashboard-target="errorTrend">
            <!-- Trend indicator will be inserted here -->
          </div>
        </div>
        <div class="flex items-baseline space-x-2">
          <span class="text-3xl font-bold" 
                data-operations-dashboard-target="errorRate"
                data-operations-dashboard-error-threshold="1">0.05</span>
          <span class="text-lg text-slate-500">%</span>
        </div>
        <div class="mt-2">
          <div class="flex items-center text-xs text-slate-500">
            <span data-operations-dashboard-target="errorCount">12</span> errors in last hour
          </div>
        </div>
      </div>

      <!-- Response Time Card -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm font-medium text-slate-600">Avg Response Time</span>
          <button data-action="click->operations-dashboard#showResponseTimeDetails"
                  class="text-teal-700 hover:text-teal-800">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6"/>
            </svg>
          </button>
        </div>
        <div class="flex items-baseline space-x-2">
          <span class="text-3xl font-bold text-slate-900" data-operations-dashboard-target="avgResponseTime">7.2</span>
          <span class="text-lg text-slate-500">ms</span>
        </div>
        <div class="mt-2 grid grid-cols-3 gap-1 text-xs">
          <div>
            <span class="text-slate-500">P50:</span>
            <span class="font-medium" data-operations-dashboard-target="p50">5ms</span>
          </div>
          <div>
            <span class="text-slate-500">P95:</span>
            <span class="font-medium" data-operations-dashboard-target="p95">12ms</span>
          </div>
          <div>
            <span class="text-slate-500">P99:</span>
            <span class="font-medium" data-operations-dashboard-target="p99">18ms</span>
          </div>
        </div>
      </div>

      <!-- Throughput Card -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm font-medium text-slate-600">Throughput</span>
          <div class="h-8 w-16" data-operations-dashboard-target="throughputSparkline">
            <!-- Mini sparkline chart -->
          </div>
        </div>
        <div class="flex items-baseline space-x-2">
          <span class="text-3xl font-bold text-slate-900" data-operations-dashboard-target="throughput">1.2k</span>
          <span class="text-lg text-slate-500">req/s</span>
        </div>
        <div class="mt-2 text-xs text-slate-500">
          Peak: <span data-operations-dashboard-target="peakThroughput">2.1k req/s</span> today
        </div>
      </div>
    </div>

    <!-- Alert Management Section -->
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 mb-6">
      <div class="px-6 py-4 border-b border-slate-200">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold text-slate-900">Active Alerts</h2>
          <div class="flex items-center space-x-2">
            <!-- Alert Filters -->
            <select data-action="change->operations-dashboard#filterAlerts"
                    class="text-sm bg-white border border-slate-300 rounded-lg px-3 py-1">
              <option value="all">All Severities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>
            
            <!-- Mute/Unmute All -->
            <button data-action="click->operations-dashboard#toggleMuteAll"
                    class="p-1 text-slate-600 hover:text-slate-900">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                      d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" clip-path="evenodd"/>
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2"/>
              </svg>
            </button>
          </div>
        </div>
      </div>
      
      <div class="divide-y divide-slate-200" data-operations-dashboard-target="alertList">
        <!-- Alert Items -->
        <div class="px-6 py-4 hover:bg-slate-50 transition-colors" data-alert-id="1">
          <div class="flex items-start justify-between">
            <div class="flex items-start space-x-3">
              <!-- Severity Indicator -->
              <span class="flex-shrink-0 w-2 h-2 mt-1.5 rounded-full bg-rose-500"></span>
              
              <!-- Alert Content -->
              <div class="flex-1">
                <div class="flex items-center space-x-2">
                  <h3 class="text-sm font-medium text-slate-900">High Error Rate Detected</h3>
                  <span class="px-2 py-0.5 text-xs font-medium bg-rose-100 text-rose-700 rounded-full">Critical</span>
                  <span class="text-xs text-slate-500">2 min ago</span>
                </div>
                <p class="mt-1 text-sm text-slate-600">
                  Error rate has exceeded 5% threshold (current: 5.8%)
                </p>
                <div class="mt-2 flex items-center space-x-4 text-xs">
                  <button class="text-teal-700 hover:text-teal-800 font-medium"
                          data-action="click->operations-dashboard#investigateAlert">
                    Investigate
                  </button>
                  <button class="text-slate-600 hover:text-slate-900"
                          data-action="click->operations-dashboard#acknowledgeAlert">
                    Acknowledge
                  </button>
                  <button class="text-slate-600 hover:text-slate-900"
                          data-action="click->operations-dashboard#muteAlert">
                    Mute for 1h
                  </button>
                </div>
              </div>
            </div>
            
            <!-- Alert Actions -->
            <div class="flex items-center space-x-2">
              <button class="p-1 text-slate-400 hover:text-slate-600">
                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M10 12a2 2 0 100-4 2 2 0 000 4z"/>
                  <path fill-rule="evenodd" d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z" clip-rule="evenodd"/>
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Performance Visualization Grid -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
      <!-- Real-time Metrics Chart -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-slate-900">Real-time Performance</h3>
          <div class="flex items-center space-x-2">
            <!-- Metric Selector -->
            <div class="flex bg-slate-100 rounded-lg p-0.5" role="tablist">
              <button class="px-2 py-1 text-xs font-medium rounded-md bg-white text-slate-900"
                      data-metric="response_time">Response Time</button>
              <button class="px-2 py-1 text-xs font-medium text-slate-600"
                      data-metric="throughput">Throughput</button>
              <button class="px-2 py-1 text-xs font-medium text-slate-600"
                      data-metric="error_rate">Error Rate</button>
            </div>
          </div>
        </div>
        
        <!-- Chart Container with Real-time Updates -->
        <div class="relative h-64">
          <canvas data-operations-dashboard-target="realtimeChart"></canvas>
          
          <!-- Live Indicator -->
          <div class="absolute top-2 right-2 flex items-center space-x-1">
            <span class="flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
            </span>
            <span class="text-xs text-slate-600">Live</span>
          </div>
        </div>
      </div>

      <!-- Heatmap Visualization -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-slate-900">Service Health Heatmap</h3>
          <button data-action="click->operations-dashboard#toggleHeatmapView"
                  class="text-sm text-teal-700 hover:text-teal-800">
            <svg class="w-4 h-4 inline mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/>
            </svg>
            Toggle View
          </button>
        </div>
        
        <!-- Heatmap Grid -->
        <div class="grid grid-cols-24 gap-0.5" data-operations-dashboard-target="heatmap">
          <!-- Dynamically generated heatmap cells -->
        </div>
        
        <!-- Legend -->
        <div class="mt-4 flex items-center justify-between text-xs text-slate-600">
          <span>24 hours ago</span>
          <div class="flex items-center space-x-2">
            <span>Healthy</span>
            <div class="flex space-x-0.5">
              <div class="w-3 h-3 bg-emerald-500"></div>
              <div class="w-3 h-3 bg-amber-500"></div>
              <div class="w-3 h-3 bg-rose-500"></div>
            </div>
            <span>Critical</span>
          </div>
          <span>Now</span>
        </div>
      </div>
    </div>

    <!-- Business Metrics Section -->
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-slate-900">Business Impact Metrics</h3>
        <button data-action="click->operations-dashboard#exportBusinessMetrics"
                class="text-sm text-teal-700 hover:text-teal-800 font-medium">
          Export Report
        </button>
      </div>
      
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <!-- Categorization Success -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm text-slate-600">Auto-Categorization Rate</span>
            <span class="text-xs text-emerald-600">+2.3%</span>
          </div>
          <div class="flex items-baseline space-x-2 mb-2">
            <span class="text-2xl font-bold text-slate-900">87.5%</span>
            <span class="text-sm text-slate-500">of expenses</span>
          </div>
          <div class="w-full bg-slate-200 rounded-full h-2">
            <div class="bg-teal-700 h-2 rounded-full" style="width: 87.5%"></div>
          </div>
        </div>
        
        <!-- Time Saved -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm text-slate-600">Time Saved This Month</span>
            <span class="text-xs text-emerald-600">+18h</span>
          </div>
          <div class="flex items-baseline space-x-2 mb-2">
            <span class="text-2xl font-bold text-slate-900">142</span>
            <span class="text-sm text-slate-500">hours</span>
          </div>
          <div class="text-xs text-slate-500">
            Equivalent to $<span data-operations-dashboard-target="costSaved">5,680</span> saved
          </div>
        </div>
        
        <!-- Accuracy Trend -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm text-slate-600">Categorization Accuracy</span>
            <span class="text-xs text-amber-600">-0.5%</span>
          </div>
          <div class="flex items-baseline space-x-2 mb-2">
            <span class="text-2xl font-bold text-slate-900">92.1%</span>
            <span class="text-sm text-slate-500">correct</span>
          </div>
          <div class="h-12" data-operations-dashboard-target="accuracyTrendChart">
            <!-- Mini trend chart -->
          </div>
        </div>
      </div>
    </div>

    <!-- System Logs and Events -->
    <div class="bg-white rounded-xl shadow-sm border border-slate-200">
      <div class="px-6 py-4 border-b border-slate-200">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">System Events</h3>
          <div class="flex items-center space-x-2">
            <!-- Log Level Filter -->
            <select data-action="change->operations-dashboard#filterLogs"
                    class="text-sm bg-white border border-slate-300 rounded-lg px-3 py-1">
              <option value="all">All Levels</option>
              <option value="error">Errors</option>
              <option value="warning">Warnings</option>
              <option value="info">Info</option>
              <option value="debug">Debug</option>
            </select>
            
            <!-- Search -->
            <div class="relative">
              <input type="text" 
                     placeholder="Search logs..."
                     data-action="input->operations-dashboard#searchLogs"
                     class="text-sm bg-white border border-slate-300 rounded-lg pl-8 pr-3 py-1 w-48">
              <svg class="absolute left-2 top-1.5 w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
              </svg>
            </div>
            
            <!-- Pause/Resume -->
            <button data-action="click->operations-dashboard#toggleLogStream"
                    class="p-1 text-slate-600 hover:text-slate-900">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </button>
          </div>
        </div>
      </div>
      
      <!-- Log Stream -->
      <div class="h-64 overflow-y-auto font-mono text-xs" data-operations-dashboard-target="logStream">
        <div class="px-6 py-2 hover:bg-slate-50 border-l-2 border-transparent hover:border-teal-500">
          <div class="flex items-start space-x-2">
            <span class="text-slate-500">2024-01-20 14:23:45</span>
            <span class="px-1.5 py-0.5 bg-blue-100 text-blue-700 rounded">INFO</span>
            <span class="text-slate-700">Categorization completed for expense #12345 (confidence: 0.92)</span>
          </div>
        </div>
        <!-- More log entries... -->
      </div>
    </div>
  </div>

  <!-- Settings Panel (Slide-over) -->
  <div class="fixed inset-0 z-50 hidden" data-operations-dashboard-target="settingsPanel">
    <!-- Backdrop -->
    <div class="fixed inset-0 bg-slate-900 bg-opacity-50" data-action="click->operations-dashboard#closeSettings"></div>
    
    <!-- Panel -->
    <div class="fixed right-0 top-0 h-full w-96 bg-white shadow-xl">
      <div class="flex items-center justify-between px-6 py-4 border-b border-slate-200">
        <h2 class="text-lg font-semibold text-slate-900">Dashboard Settings</h2>
        <button data-action="click->operations-dashboard#closeSettings"
                class="p-1 text-slate-400 hover:text-slate-600">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
      </div>
      
      <div class="px-6 py-4 space-y-6">
        <!-- Auto-refresh Settings -->
        <div>
          <h3 class="text-sm font-medium text-slate-900 mb-3">Auto-refresh</h3>
          <div class="space-y-2">
            <label class="flex items-center">
              <input type="checkbox" checked class="rounded border-slate-300 text-teal-700 focus:ring-teal-500">
              <span class="ml-2 text-sm text-slate-700">Enable auto-refresh</span>
            </label>
            <div class="flex items-center space-x-2">
              <label class="text-sm text-slate-600">Interval:</label>
              <select class="text-sm bg-white border border-slate-300 rounded-lg px-3 py-1">
                <option value="5000">5 seconds</option>
                <option value="10000" selected>10 seconds</option>
                <option value="30000">30 seconds</option>
                <option value="60000">1 minute</option>
              </select>
            </div>
          </div>
        </div>
        
        <!-- Alert Preferences -->
        <div>
          <h3 class="text-sm font-medium text-slate-900 mb-3">Alert Preferences</h3>
          <div class="space-y-2">
            <label class="flex items-center">
              <input type="checkbox" checked class="rounded border-slate-300 text-teal-700 focus:ring-teal-500">
              <span class="ml-2 text-sm text-slate-700">Desktop notifications</span>
            </label>
            <label class="flex items-center">
              <input type="checkbox" checked class="rounded border-slate-300 text-teal-700 focus:ring-teal-500">
              <span class="ml-2 text-sm text-slate-700">Sound alerts</span>
            </label>
            <label class="flex items-center">
              <input type="checkbox" class="rounded border-slate-300 text-teal-700 focus:ring-teal-500">
              <span class="ml-2 text-sm text-slate-700">Email digest</span>
            </label>
          </div>
        </div>
        
        <!-- Metric Thresholds -->
        <div>
          <h3 class="text-sm font-medium text-slate-900 mb-3">Alert Thresholds</h3>
          <div class="space-y-3">
            <div>
              <label class="text-sm text-slate-600">Error Rate (%)</label>
              <input type="number" value="1.0" step="0.1" min="0" max="100"
                     class="mt-1 block w-full text-sm bg-white border border-slate-300 rounded-lg px-3 py-2">
            </div>
            <div>
              <label class="text-sm text-slate-600">Response Time P95 (ms)</label>
              <input type="number" value="15" step="1" min="0"
                     class="mt-1 block w-full text-sm bg-white border border-slate-300 rounded-lg px-3 py-2">
            </div>
            <div>
              <label class="text-sm text-slate-600">Min Success Rate (%)</label>
              <input type="number" value="85" step="1" min="0" max="100"
                     class="mt-1 block w-full text-sm bg-white border border-slate-300 rounded-lg px-3 py-2">
            </div>
          </div>
        </div>
        
        <!-- Save Button -->
        <div class="pt-4">
          <button data-action="click->operations-dashboard#saveSettings"
                  class="w-full px-4 py-2 bg-teal-700 text-white rounded-lg font-medium hover:bg-teal-800">
            Save Settings
          </button>
        </div>
      </div>
    </div>
  </div>
</div>
```

##### Stimulus Controller for Real-time Monitoring
```javascript
// app/javascript/controllers/operations_dashboard_controller.js
import { Controller } from "@hotwired/stimulus"
import { Chart } from "chart.js/auto"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "lastUpdate", "updateTime", "activeAlerts", "alertPulse", "alertIndicator",
    "uptime", "lastIncident", "errorRate", "errorTrend", "errorCount",
    "avgResponseTime", "p50", "p95", "p99",
    "throughput", "throughputSparkline", "peakThroughput",
    "alertList", "realtimeChart", "heatmap", "logStream",
    "costSaved", "accuracyTrendChart", "settingsPanel"
  ]
  
  static values = {
    autoRefresh: Boolean,
    refreshInterval: Number
  }
  
  connect() {
    this.setupCharts()
    this.setupWebSocket()
    this.startAutoRefresh()
    this.requestNotificationPermission()
    this.loadDashboardData()
  }
  
  disconnect() {
    this.teardownWebSocket()
    this.destroyCharts()
    this.stopAutoRefresh()
  }
  
  setupWebSocket() {
    // Real-time updates via ActionCable
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "OperationsChannel" },
      {
        received: (data) => {
          this.handleRealtimeUpdate(data)
        }
      }
    )
  }
  
  handleRealtimeUpdate(data) {
    switch(data.type) {
      case 'metrics':
        this.updateMetrics(data.metrics)
        break
      case 'alert':
        this.handleNewAlert(data.alert)
        break
      case 'log':
        this.appendLog(data.log)
        break
      case 'status_change':
        this.updateServiceStatus(data.service, data.status)
        break
    }
    
    // Update last update time
    this.updateTimeTarget.textContent = new Date().toLocaleTimeString()
  }
  
  updateMetrics(metrics) {
    // Animate metric updates
    this.animateValue(this.uptimeTarget, metrics.uptime)
    this.animateValue(this.errorRateTarget, metrics.error_rate)
    this.animateValue(this.avgResponseTimeTarget, metrics.avg_response_time)
    this.animateValue(this.throughputTarget, metrics.throughput)
    
    // Update percentiles
    this.p50Target.textContent = `${metrics.p50}ms`
    this.p95Target.textContent = `${metrics.p95}ms`
    this.p99Target.textContent = `${metrics.p99}ms`
    
    // Update trend indicators
    this.updateTrendIndicator(this.errorTrendTarget, metrics.error_trend)
    
    // Update charts
    this.updateRealtimeChart(metrics)
    this.updateHeatmap(metrics.health_matrix)
  }
  
  handleNewAlert(alert) {
    // Add alert to list
    this.prependAlert(alert)
    
    // Update alert count
    const currentCount = parseInt(this.activeAlertsTarget.textContent)
    this.activeAlertsTarget.textContent = currentCount + 1
    
    // Show pulse animation
    this.alertPulseTarget.classList.remove('hidden')
    
    // Show desktop notification if enabled
    if (this.notificationsEnabled && alert.severity === 'critical') {
      this.showDesktopNotification(alert)
    }
    
    // Play sound if enabled
    if (this.soundEnabled && alert.severity in ['critical', 'high']) {
      this.playAlertSound(alert.severity)
    }
  }
  
  animateValue(element, newValue) {
    const currentValue = parseFloat(element.textContent)
    const difference = newValue - currentValue
    const duration = 500 // ms
    const steps = 20
    const stepValue = difference / steps
    const stepDuration = duration / steps
    
    let step = 0
    const animation = setInterval(() => {
      step++
      element.textContent = (currentValue + stepValue * step).toFixed(2)
      
      if (step >= steps) {
        clearInterval(animation)
        element.textContent = newValue.toFixed(2)
        
        // Apply color coding based on thresholds
        this.applyColorCoding(element)
      }
    }, stepDuration)
  }
  
  applyColorCoding(element) {
    const value = parseFloat(element.textContent)
    const threshold = parseFloat(element.dataset.operationsDashboardErrorThreshold || 1)
    
    element.classList.remove('text-emerald-600', 'text-amber-600', 'text-rose-600')
    
    if (element === this.errorRateTarget) {
      if (value < threshold * 0.5) {
        element.classList.add('text-emerald-600')
      } else if (value < threshold) {
        element.classList.add('text-amber-600')
      } else {
        element.classList.add('text-rose-600')
      }
    }
  }
  
  showDesktopNotification(alert) {
    if ("Notification" in window && Notification.permission === "granted") {
      const notification = new Notification("Critical Alert", {
        body: alert.message,
        icon: "/assets/alert-icon.png",
        badge: "/assets/badge-icon.png",
        tag: alert.id,
        requireInteraction: true
      })
      
      notification.onclick = () => {
        window.focus()
        this.investigateAlert({ currentTarget: { dataset: { alertId: alert.id } } })
      }
    }
  }
  
  investigateAlert(event) {
    const alertId = event.currentTarget.dataset.alertId
    
    // Open investigation modal or navigate to details page
    window.location.href = `/admin/categorization/alerts/${alertId}/investigate`
  }
}
```

### User Journey Flows

#### Journey 1: Incident Response
1. **Alert Trigger**: System detects anomaly (e.g., error rate spike)
2. **Notification**: Admin receives multi-channel alert:
   - Desktop notification
   - Dashboard alert banner
   - Optional: SMS/Email
3. **Initial Assessment**:
   - Admin opens Operations Dashboard
   - Reviews alert details and affected services
   - Checks real-time metrics
4. **Investigation**:
   - Clicks "Investigate" on alert
   - Reviews correlated logs and events
   - Identifies root cause
5. **Resolution**:
   - Takes corrective action
   - Monitors metrics for improvement
   - Acknowledges/resolves alert
6. **Post-Incident**:
   - Reviews incident timeline
   - Documents resolution
   - Updates runbook if needed

#### Journey 2: Performance Optimization
1. **Routine Check**: Admin performs daily dashboard review
2. **Trend Analysis**:
   - Reviews performance trends
   - Identifies degradation patterns
   - Compares against baselines
3. **Deep Dive**:
   - Switches to detailed analytics view
   - Examines specific time periods
   - Correlates with deployment events
4. **Optimization Planning**:
   - Identifies optimization opportunities
   - Reviews resource utilization
   - Plans scaling adjustments
5. **Implementation**:
   - Adjusts configurations
   - Monitors impact in real-time
   - Validates improvements

### Accessibility Requirements

#### WCAG AA Compliance
1. **High Contrast Mode**:
   ```css
   @media (prefers-contrast: high) {
     .operations-dashboard {
       --primary-color: #004d40;
       --background-color: #ffffff;
       --text-color: #000000;
       --border-color: #000000;
     }
   }
   ```

2. **Keyboard Navigation**:
   - All interactive elements accessible via Tab
   - Arrow keys navigate between metrics
   - Escape closes modals/panels
   - Shortcuts for common actions (e.g., Ctrl+R for refresh)

3. **Screen Reader Optimization**:
   ```html
   <!-- Live regions for real-time updates -->
   <div aria-live="polite" aria-atomic="true" class="sr-only">
     <span data-operations-dashboard-target="screenReaderAnnouncements"></span>
   </div>
   
   <!-- Descriptive labels for charts -->
   <canvas aria-label="Real-time performance metrics showing response time over the last hour"
           role="img">
   </canvas>
   ```

4. **Reduced Motion Support**:
   ```css
   @media (prefers-reduced-motion: reduce) {
     .operations-dashboard * {
       animation-duration: 0.01ms !important;
       animation-iteration-count: 1 !important;
       transition-duration: 0.01ms !important;
     }
   }
   ```

### Mobile Responsive Design

#### Responsive Layout
```erb
<!-- Mobile-optimized alert card -->
<div class="block sm:hidden">
  <div class="bg-white rounded-lg shadow-sm p-4 mb-3">
    <div class="flex items-start justify-between mb-2">
      <div class="flex items-center">
        <span class="w-2 h-2 rounded-full bg-rose-500 mr-2"></span>
        <span class="text-sm font-medium">Critical Alert</span>
      </div>
      <span class="text-xs text-slate-500">2m</span>
    </div>
    <p class="text-xs text-slate-600 mb-2">Error rate exceeded threshold</p>
    <div class="flex space-x-2">
      <button class="flex-1 px-3 py-1 bg-teal-700 text-white text-xs rounded">
        Investigate
      </button>
      <button class="flex-1 px-3 py-1 bg-slate-200 text-slate-700 text-xs rounded">
        Acknowledge
      </button>
    </div>
  </div>
</div>
```

#### Touch Optimization
```css
/* Larger touch targets for mobile */
@media (max-width: 768px) {
  .operations-dashboard button,
  .operations-dashboard a {
    min-height: 44px;
    min-width: 44px;
  }
  
  /* Swipe gestures for navigation */
  .swipe-container {
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    scroll-snap-type: x mandatory;
  }
  
  .swipe-item {
    scroll-snap-align: start;
  }
}
```

### Performance Optimization

#### Efficient Data Loading
```javascript
// Virtualized list for logs
class VirtualizedLogList {
  constructor(container, items) {
    this.container = container
    this.items = items
    this.visibleRange = { start: 0, end: 50 }
    this.itemHeight = 32
    
    this.render()
    this.attachScrollListener()
  }
  
  render() {
    const fragment = document.createDocumentFragment()
    const visibleItems = this.items.slice(
      this.visibleRange.start,
      this.visibleRange.end
    )
    
    visibleItems.forEach(item => {
      const element = this.createLogElement(item)
      fragment.appendChild(element)
    })
    
    this.container.innerHTML = ''
    this.container.appendChild(fragment)
  }
  
  attachScrollListener() {
    this.container.addEventListener('scroll', 
      this.throttle(this.handleScroll.bind(this), 100)
    )
  }
}
```

#### WebSocket Connection Management
```javascript
class ConnectionManager {
  constructor() {
    this.reconnectAttempts = 0
    this.maxReconnectAttempts = 5
    this.reconnectDelay = 1000
  }
  
  connect() {
    this.ws = new WebSocket(this.wsUrl)
    
    this.ws.onopen = () => {
      this.reconnectAttempts = 0
      this.onConnect()
    }
    
    this.ws.onclose = () => {
      this.handleDisconnect()
    }
    
    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error)
      this.handleError(error)
    }
  }
  
  handleDisconnect() {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      setTimeout(() => {
        this.reconnectAttempts++
        this.connect()
      }, this.reconnectDelay * Math.pow(2, this.reconnectAttempts))
    } else {
      this.showOfflineMode()
    }
  }
}
```