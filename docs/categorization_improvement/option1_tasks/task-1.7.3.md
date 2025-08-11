### Task 1.7.3: Production Readiness and Monitoring
**Priority**: HIGH  
**Estimated Hours**: 5  
**Dependencies**: Task 1.7.2  

#### Description
Implement comprehensive monitoring, observability, and configuration management for production deployment.

#### Acceptance Criteria
- [ ] Monitoring dashboards configured (response times, success rates, cache hit rates)
- [ ] Structured logging implemented with correlation IDs
- [ ] Health check endpoints created
- [ ] Environment-specific configuration files
- [ ] Performance metrics collection via StatsD/Prometheus
- [ ] Alert rules defined for critical metrics
- [ ] Graceful degradation for service failures
- [ ] Operations runbook documented

#### Technical Implementation

##### Monitoring and Observability
```ruby
# app/services/categorization/monitoring/metrics_collector.rb
module Categorization
  module Monitoring
    class MetricsCollector
      include Singleton
      
      def initialize
        @statsd = Datadog::Statsd.new('localhost', 8125)
      end
      
      def track_categorization(expense_id, result, duration_ms)
        tags = [
          "success:#{result.successful?}",
          "confidence_level:#{confidence_bucket(result.confidence)}",
          "category:#{result.category&.name&.parameterize}"
        ]
        
        @statsd.increment('categorization.attempts', tags: tags)
        @statsd.histogram('categorization.duration', duration_ms, tags: tags)
        @statsd.gauge('categorization.confidence', result.confidence, tags: tags)
        
        if result.successful?
          @statsd.increment('categorization.success', tags: tags)
        else
          @statsd.increment('categorization.failure', tags: ["error:#{result.error}"])
        end
      end
      
      def track_cache_hit(cache_type, hit)
        @statsd.increment("categorization.cache.#{cache_type}", tags: ["hit:#{hit}"])
      end
      
      def track_pattern_learning(pattern_type, action)
        @statsd.increment('categorization.learning', 
          tags: ["type:#{pattern_type}", "action:#{action}"]
        )
      end
      
      private
      
      def confidence_bucket(confidence)
        case confidence
        when 0.9..1.0 then 'very_high'
        when 0.7...0.9 then 'high'
        when 0.5...0.7 then 'medium'
        when 0.3...0.5 then 'low'
        else 'very_low'
        end
      end
    end
  end
end

# app/services/categorization/monitoring/health_check.rb
module Categorization
  module Monitoring
    class HealthCheck
      def self.status
        checks = {
          database: check_database,
          redis: check_redis,
          pattern_cache: check_pattern_cache,
          services: check_services
        }
        
        overall_status = checks.values.all? { |c| c[:status] == 'healthy' } ? 'healthy' : 'unhealthy'
        
        {
          status: overall_status,
          timestamp: Time.current.iso8601,
          checks: checks,
          metrics: collect_metrics
        }
      end
      
      private
      
      def self.check_database
        start = Time.current
        CategorizationPattern.count
        response_time = (Time.current - start) * 1000
        
        {
          status: response_time < 100 ? 'healthy' : 'degraded',
          response_time_ms: response_time
        }
      rescue => e
        { status: 'unhealthy', error: e.message }
      end
      
      def self.check_redis
        start = Time.current
        Redis.current.ping
        response_time = (Time.current - start) * 1000
        
        {
          status: response_time < 10 ? 'healthy' : 'degraded',
          response_time_ms: response_time
        }
      rescue => e
        { status: 'unhealthy', error: e.message }
      end
      
      def self.check_pattern_cache
        cache = PatternCache.instance
        stats = cache.stats
        
        {
          status: 'healthy',
          entries: stats[:entries],
          memory_used_mb: stats[:memory_used] / 1.megabyte,
          hit_rate: stats[:hit_rate]
        }
      rescue => e
        { status: 'unhealthy', error: e.message }
      end
      
      def self.collect_metrics
        {
          patterns_total: CategorizationPattern.count,
          patterns_active: CategorizationPattern.active.count,
          avg_success_rate: CategorizationPattern.active.average(:success_rate),
          last_learning: PatternFeedback.maximum(:created_at)
        }
      end
    end
  end
end
```

##### Structured Logging
```ruby
# app/services/categorization/monitoring/structured_logger.rb
module Categorization
  module Monitoring
    class StructuredLogger
      def self.log_categorization(expense, result, context = {})
        Rails.logger.info({
          event: 'categorization',
          expense_id: expense.id,
          merchant: expense.merchant_name,
          amount: expense.amount,
          result: {
            category_id: result.category&.id,
            category_name: result.category&.name,
            confidence: result.confidence,
            patterns_used: result.patterns_used.map(&:id),
            successful: result.successful?
          },
          correlation_id: context[:correlation_id] || SecureRandom.uuid,
          duration_ms: context[:duration_ms],
          timestamp: Time.current.iso8601
        }.to_json)
      end
      
      def self.log_learning(expense, category, pattern, context = {})
        Rails.logger.info({
          event: 'pattern_learning',
          expense_id: expense.id,
          category_id: category.id,
          pattern_id: pattern&.id,
          pattern_type: pattern&.pattern_type,
          action: context[:action],
          correlation_id: context[:correlation_id] || SecureRandom.uuid,
          timestamp: Time.current.iso8601
        }.to_json)
      end
      
      def self.log_error(error, context = {})
        Rails.logger.error({
          event: 'categorization_error',
          error_class: error.class.name,
          error_message: error.message,
          backtrace: error.backtrace&.first(5),
          context: context,
          correlation_id: context[:correlation_id] || SecureRandom.uuid,
          timestamp: Time.current.iso8601
        }.to_json)
      end
    end
  end
end
```

##### Environment Configuration
```yaml
# config/categorization.yml
default: &default
  cache:
    memory_size_mb: 50
    ttl_minutes: 5
    redis_ttl_hours: 24
  
  matching:
    jaro_winkler_threshold: 0.8
    levenshtein_threshold: 3
    trigram_threshold: 0.6
    max_results: 10
  
  confidence:
    min_threshold: 0.5
    high_confidence_threshold: 0.8
    very_high_confidence_threshold: 0.9
  
  learning:
    min_corrections_for_pattern: 3
    confidence_boost_correct: 0.15
    confidence_penalty_incorrect: -0.25
    merge_similarity_threshold: 0.85
    decay_after_days: 30
    decay_factor: 0.9
  
  monitoring:
    enabled: false
    statsd_host: localhost
    statsd_port: 8125

development:
  <<: *default
  monitoring:
    enabled: false

test:
  <<: *default
  cache:
    memory_size_mb: 10
    ttl_minutes: 1

production:
  <<: *default
  cache:
    memory_size_mb: 500
    ttl_minutes: 15
    redis_ttl_hours: 48
  
  monitoring:
    enabled: true
    statsd_host: <%= ENV['STATSD_HOST'] %>
    statsd_port: <%= ENV['STATSD_PORT'] || 8125 %>
  
  alerts:
    low_cache_hit_rate: 0.7
    high_error_rate: 0.05
    slow_response_ms: 50
```

##### Health Check Controller
```ruby
# app/controllers/api/health_controller.rb
module Api
  class HealthController < ApplicationController
    skip_before_action :authenticate_user!
    
    def show
      status = Categorization::Monitoring::HealthCheck.status
      
      http_status = status[:status] == 'healthy' ? :ok : :service_unavailable
      
      render json: status, status: http_status
    end
    
    def ready
      # Kubernetes readiness probe
      if ready_to_serve_traffic?
        head :ok
      else
        head :service_unavailable
      end
    end
    
    def live
      # Kubernetes liveness probe
      head :ok
    end
    
    private
    
    def ready_to_serve_traffic?
      # Check if cache is warmed
      PatternCache.instance.warmed? &&
      # Check database connection
      ActiveRecord::Base.connection.active? &&
      # Check Redis connection
      Redis.current.ping == 'PONG'
    end
  end
end
```

#### Operations Runbook
```markdown
# Categorization Service Operations Runbook

## Service Overview
The categorization service uses machine learning patterns to automatically categorize expenses.

## Key Metrics to Monitor
- **Categorization Success Rate**: Should be >85%
- **Response Time**: P95 should be <10ms
- **Cache Hit Rate**: Should be >90%
- **Pattern Learning Rate**: New patterns created per hour

## Common Issues and Solutions

### High Response Times
1. Check cache hit rates - may need cache warming
2. Review pattern count - too many patterns slow matching
3. Check database query performance

### Low Success Rate
1. Review recent pattern changes
2. Check for data quality issues in expenses
3. Verify pattern learning is functioning

### Service Degradation
1. Service automatically falls back to basic matching if ML fails
2. Check health endpoint: GET /api/health
3. Review error logs for correlation IDs

## Maintenance Tasks

### Daily
- Review categorization success metrics
- Check for patterns with low success rates

### Weekly
- Analyze pattern learning effectiveness
- Review and merge similar patterns
- Update pattern decay for unused patterns

### Monthly
- Full pattern audit and cleanup
- Performance baseline review
- Update confidence thresholds if needed
```
