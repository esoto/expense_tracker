# frozen_string_literal: true

namespace :categorization do
  namespace :monitoring do
    desc "Display current health status of the categorization system"
    task health: :environment do
      
      puts "\n🏥 Categorization System Health Check"
      puts "=" * 50
      
      health_check = Categorization::Monitoring::HealthCheck.new
      result = health_check.check_all
      
      # Overall status
      status_emoji = case result[:status]
                    when :healthy then "✅"
                    when :degraded then "⚠️"
                    when :unhealthy then "❌"
                    else "❓"
                    end
      
      puts "\n#{status_emoji} Overall Status: #{result[:status].to_s.upcase}"
      puts "Healthy: #{result[:healthy]}"
      puts "Ready: #{result[:ready]}"
      puts "Live: #{result[:live]}"
      puts "Uptime: #{format_duration(result[:uptime_seconds])}"
      
      # Individual checks
      puts "\n📊 Component Status:"
      result[:checks].each do |component, status|
        component_emoji = case status[:status]
                         when :healthy then "✅"
                         when :degraded then "⚠️"
                         when :unhealthy then "❌"
                         else "❓"
                         end
        
        puts "\n  #{component_emoji} #{component.to_s.humanize}:"
        puts "    Status: #{status[:status]}"
        
        if status[:response_time_ms]
          puts "    Response Time: #{status[:response_time_ms]}ms"
        end
        
        if status[:warning]
          puts "    ⚠️  Warning: #{status[:warning]}"
        end
        
        if status[:error]
          puts "    ❌ Error: #{status[:error]}"
        end
        
        # Component-specific details
        case component
        when :pattern_cache
          puts "    Entries: #{status[:entries]}"
          puts "    Hit Rate: #{(status[:hit_rate] * 100).round(1)}%" if status[:hit_rate]
        when :service_metrics
          puts "    Active Patterns: #{status[:active_patterns]}"
          puts "    Success Rate: #{(status[:success_rate] * 100).round(1)}%" if status[:success_rate]
        when :dependencies
          status[:services]&.each do |service, service_status|
            puts "    - #{service}: #{service_status[:status]}"
          end
        end
      end
      
      # Errors
      if result[:errors].any?
        puts "\n❌ Errors:"
        result[:errors].each { |error| puts "  - #{error}" }
      end
      
      puts "\n" + "=" * 50
    end

    desc "Display monitoring dashboard metrics"
    task dashboard: :environment do
      
      puts "\n📈 Categorization Monitoring Dashboard"
      puts "=" * 50
      
      metrics = Categorization::Monitoring::DashboardHelper.metrics_summary
      
      # Health Summary
      puts "\n🏥 Health Status:"
      puts "  Status: #{metrics[:health][:status]}"
      puts "  Healthy: #{metrics[:health][:healthy]}"
      puts "  Ready: #{metrics[:health][:ready]}"
      puts "  Uptime: #{format_duration(metrics[:health][:uptime_seconds])}"
      
      # Categorization Metrics
      puts "\n📊 Categorization Metrics:"
      cat_metrics = metrics[:categorization]
      puts "  Total Expenses: #{cat_metrics[:total_expenses]}"
      puts "  Categorized: #{cat_metrics[:categorized]} (#{cat_metrics[:success_rate]}%)"
      puts "  Uncategorized: #{cat_metrics[:uncategorized]}"
      puts "  Recent (1h):"
      puts "    Processed: #{cat_metrics[:recent][:total]}"
      puts "    Success Rate: #{cat_metrics[:recent][:success_rate]}%"
      
      # Pattern Metrics
      puts "\n🎯 Pattern Metrics:"
      pattern_metrics = metrics[:patterns]
      puts "  Total Patterns: #{pattern_metrics[:total]}"
      puts "  Active: #{pattern_metrics[:active]}"
      puts "  High Confidence: #{pattern_metrics[:high_confidence]}"
      puts "  By Type:"
      pattern_metrics[:by_type].each do |type, count|
        puts "    #{type}: #{count}"
      end
      puts "  Recent Activity (24h):"
      puts "    Created: #{pattern_metrics[:recent_activity][:created_24h]}"
      puts "    Updated: #{pattern_metrics[:recent_activity][:updated_24h]}"
      
      # Cache Metrics
      puts "\n💾 Cache Performance:"
      cache_metrics = metrics[:cache]
      if cache_metrics[:error]
        puts "  Error: #{cache_metrics[:error]}"
      else
        puts "  Entries: #{cache_metrics[:entries]}"
        puts "  Memory: #{cache_metrics[:memory_mb]}MB"
        puts "  Hit Rate: #{cache_metrics[:hit_rate]}%"
        puts "  Hits/Misses: #{cache_metrics[:hits]}/#{cache_metrics[:misses]}"
      end
      
      # Performance Metrics
      puts "\n⚡ Performance:"
      perf_metrics = metrics[:performance]
      if perf_metrics[:error]
        puts "  Error: #{perf_metrics[:error]}"
      else
        puts "  Average Times:"
        puts "    Categorization: #{perf_metrics[:averages][:categorization]}ms"
        puts "    Learning: #{perf_metrics[:averages][:learning]}ms"
        puts "    Cache Lookup: #{perf_metrics[:averages][:cache_lookup]}ms"
        puts "  Throughput:"
        puts "    Per Hour: #{perf_metrics[:throughput][:expenses_per_hour]}"
        puts "    Per Minute: #{perf_metrics[:throughput][:expenses_per_minute]}"
      end
      
      # System Metrics
      puts "\n💻 System Resources:"
      sys_metrics = metrics[:system]
      if sys_metrics[:database]
        puts "  Database Pool:"
        puts "    Size: #{sys_metrics[:database][:pool_size]}"
        puts "    Busy/Idle: #{sys_metrics[:database][:busy]}/#{sys_metrics[:database][:idle]}"
      end
      if sys_metrics[:memory] && !sys_metrics[:memory].empty?
        puts "  Memory:"
        puts "    RSS: #{sys_metrics[:memory][:rss_mb]}MB"
        puts "    Percent: #{sys_metrics[:memory][:percent]}%"
      end
      
      puts "\n" + "=" * 50
    end

    desc "Test metrics collection"
    task test_metrics: :environment do
      
      puts "\n🧪 Testing Metrics Collection"
      puts "=" * 50
      
      collector = Categorization::Monitoring::MetricsCollector.instance
      
      if collector.enabled?
        puts "✅ Metrics collector is enabled"
        
        # Test categorization tracking
        puts "\nTesting categorization metrics..."
        collector.track_categorization(
          expense_id: 1,
          success: true,
          confidence: 0.85,
          duration_ms: 12.5,
          category_id: 1,
          method: "pattern_matching"
        )
        puts "  ✅ Categorization tracked"
        
        # Test cache tracking
        puts "\nTesting cache metrics..."
        collector.track_cache(
          operation: "get",
          cache_type: "pattern",
          hit: true,
          duration_ms: 0.5
        )
        puts "  ✅ Cache operation tracked"
        
        # Test learning tracking
        puts "\nTesting learning metrics..."
        collector.track_learning(
          action: "pattern_created",
          pattern_type: "merchant",
          success: true,
          confidence_change: 0.05
        )
        puts "  ✅ Learning event tracked"
        
        # Test error tracking
        puts "\nTesting error metrics..."
        collector.track_error(
          error_type: "ValidationError",
          context: { service: "test", method: "test_method" }
        )
        puts "  ✅ Error tracked"
        
        puts "\n✅ All metrics tracking tests passed"
      else
        puts "⚠️  Metrics collector is disabled"
        puts "To enable, set monitoring.enabled to true in config/categorization.yml"
      end
      
      puts "\n" + "=" * 50
    end

    desc "Generate operations runbook"
    task runbook: :environment do
      puts "\n📚 Categorization System Operations Runbook"
      puts "=" * 50
      
      puts "\n## Quick Health Check"
      puts "```bash"
      puts "rails categorization:monitoring:health"
      puts "```"
      
      puts "\n## View Dashboard"
      puts "```bash"
      puts "rails categorization:monitoring:dashboard"
      puts "```"
      
      puts "\n## API Health Endpoints"
      puts "- Comprehensive: GET /api/health"
      puts "- Readiness: GET /api/health/ready"
      puts "- Liveness: GET /api/health/live"
      puts "- Metrics: GET /api/health/metrics"
      
      puts "\n## Common Issues and Solutions"
      
      puts "\n### Low Cache Hit Rate"
      puts "1. Check cache configuration in config/categorization.yml"
      puts "2. Verify Redis connectivity (if enabled)"
      puts "3. Consider increasing cache TTL or size"
      puts "4. Run: rails categorization:cache:warm_up"
      
      puts "\n### Low Success Rate"
      puts "1. Review recent pattern changes"
      puts "2. Check for data quality issues"
      puts "3. Consider retraining patterns"
      puts "4. Run: rails categorization:patterns:analyze"
      
      puts "\n### High Response Times"
      puts "1. Check database connection pool"
      puts "2. Review slow query logs"
      puts "3. Verify cache is functioning"
      puts "4. Consider scaling workers"
      
      puts "\n### Pattern Learning Not Working"
      puts "1. Verify learning is enabled in config"
      puts "2. Check minimum occurrence thresholds"
      puts "3. Review error logs for failures"
      puts "4. Run: rails categorization:learning:status"
      
      puts "\n## Monitoring Configuration"
      puts "Edit config/categorization.yml for environment-specific settings:"
      puts "- Cache TTL and size"
      puts "- Confidence thresholds"
      puts "- Learning parameters"
      puts "- Performance limits"
      puts "- Alert thresholds"
      
      puts "\n## StatsD Integration"
      puts "To enable StatsD metrics:"
      puts "1. Set monitoring.enabled: true"
      puts "2. Configure statsd_host and statsd_port"
      puts "3. Install StatsD gem: gem 'statsd-ruby'"
      puts "4. Restart application"
      
      puts "\n## Alert Thresholds"
      config = Rails.configuration.x.categorization
      if config && config[:alerts]
        puts "Current thresholds:"
        config[:alerts].each do |key, value|
          puts "  #{key}: #{value}"
        end
      else
        puts "No alert thresholds configured"
      end
      
      puts "\n" + "=" * 50
    end

    private

    def format_duration(seconds)
      return "N/A" unless seconds
      
      days = seconds / 86400
      hours = (seconds % 86400) / 3600
      minutes = (seconds % 3600) / 60
      
      parts = []
      parts << "#{days}d" if days > 0
      parts << "#{hours}h" if hours > 0
      parts << "#{minutes}m" if minutes > 0 && days == 0
      
      parts.empty? ? "< 1m" : parts.join(" ")
    end
  end
end