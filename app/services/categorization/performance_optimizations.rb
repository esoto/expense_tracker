# frozen_string_literal: true

module Categorization
  # Performance optimizations for the categorization engine
  module PerformanceOptimizations
    # Query optimizer for pattern matching
    class QueryOptimizer
      def initialize
        @query_cache = {}
        @prepared_statements = {}
      end

      # Use prepared statements for repeated queries
      def find_patterns_for_merchant(merchant_name)
        key = "merchant:#{merchant_name.downcase}"

        @query_cache[key] ||= begin
          CategorizationPattern
            .active
            .joins(:category)
            .where(pattern_type: "merchant")
            .where("LOWER(pattern_value) LIKE LOWER(?)", "%#{merchant_name}%")
            .select("categorization_patterns.*, categories.name as category_name")
            .limit(10)
            .to_a
        end
      end

      # Batch load patterns with single query
      def batch_load_patterns(expense_batch)
        merchant_names = expense_batch.map(&:merchant_name).compact.uniq
        descriptions = expense_batch.map(&:description).compact.uniq

        patterns = CategorizationPattern
          .active
          .includes(:category)
          .where(
            "(pattern_type = 'merchant' AND pattern_value IN (?)) OR " \
            "(pattern_type IN ('keyword', 'description') AND pattern_value IN (?))",
            merchant_names,
            descriptions.flat_map { |d| d.split(/\s+/) }.uniq
          )

        # Group by type for faster access
        patterns.group_by(&:pattern_type)
      end
    end

    # Intelligent cache warmer
    class CacheWarmer
      def self.warm_critical_paths
        Rails.logger.info "[CacheWarmer] Starting cache warming..."

        # Warm top categories
        Category.joins(:expenses)
          .group("categories.id")
          .order("COUNT(expenses.id) DESC")
          .limit(20)
          .each do |category|
            PatternCache.instance.preload_category_patterns(category.id)
          end

        # Warm frequent merchants
        frequent_merchants = Expense
          .where.not(merchant_name: nil)
          .group(:merchant_name)
          .order("COUNT(*) DESC")
          .limit(50)
          .pluck(:merchant_name)

        frequent_merchants.each do |merchant|
          PatternCache.instance.get_user_preference(merchant)
        end

        # Warm recent patterns
        CategorizationPattern
          .active
          .where("updated_at > ?", 24.hours.ago)
          .find_each do |pattern|
            PatternCache.instance.get_pattern(pattern.id)
          end

        Rails.logger.info "[CacheWarmer] Cache warming completed"
      end
    end

    # Database index advisor
    class IndexAdvisor
      def self.analyze_slow_queries
        recommendations = []

        # Check for missing indexes
        slow_queries = analyze_query_performance

        slow_queries.each do |query|
          if query[:table] == "categorization_patterns"
            if query[:filters].include?("pattern_value") && !index_exists?("pattern_value")
              recommendations << {
                table: "categorization_patterns",
                index: "pattern_value",
                type: "btree",
                reason: "Frequent text matching on pattern_value"
              }
            end
          end
        end

        recommendations
      end

      private

      def self.analyze_query_performance
        # This would connect to pg_stat_statements in production
        # For now, return known slow query patterns
        [
          {
            table: "categorization_patterns",
            filters: [ "pattern_value", "active" ],
            avg_time_ms: 25
          }
        ]
      end

      def self.index_exists?(column)
        ActiveRecord::Base.connection.indexes("categorization_patterns")
          .any? { |i| i.columns.include?(column) }
      end
    end

    # Connection pool manager
    class ConnectionPoolManager
      def self.configure_optimal_pool
        # Calculate optimal pool size based on server resources
        cpu_count = Concurrent.processor_count

        # Rule of thumb: 2-4 connections per CPU core
        optimal_pool_size = cpu_count * 3

        # Update database.yml programmatically (in initializer)
        {
          pool: optimal_pool_size,
          checkout_timeout: 5,
          idle_timeout: 300,
          reaping_frequency: 10
        }
      end

      def self.monitor_pool_health
        pool = ActiveRecord::Base.connection_pool

        {
          size: pool.size,
          connections: pool.connections.size,
          busy: pool.connections.count(&:in_use?),
          dead: pool.connections.count(&:dead?),
          waiting: pool.num_waiting_in_queue
        }
      end
    end

    # Request-level caching with RequestStore
    class RequestCache
      def self.fetch(key, &block)
        return yield unless defined?(RequestStore)

        RequestStore.fetch(key) do
          yield
        end
      end

      def self.clear!
        RequestStore.clear! if defined?(RequestStore)
      end
    end

    # Performance monitoring with APM integration
    class APMIntegration
      def self.trace_categorization(expense_id, &block)
        return yield unless defined?(NewRelic) || defined?(Datadog)

        tags = {
          expense_id: expense_id,
          service: "categorization_engine"
        }

        if defined?(NewRelic)
          NewRelic::Agent.with_trace_context(tags, &block)
        elsif defined?(Datadog)
          Datadog.tracer.trace("categorization.categorize", tags: tags, &block)
        else
          yield
        end
      end
    end

    # Lazy loading for expensive operations
    class LazyLoader
      def initialize(&loader)
        @loader = loader
        @loaded = false
        @value = nil
        @mutex = Mutex.new
      end

      def value
        return @value if @loaded

        @mutex.synchronize do
          return @value if @loaded

          @value = @loader.call
          @loaded = true
          @value
        end
      end

      def loaded?
        @loaded
      end

      def reset!
        @mutex.synchronize do
          @loaded = false
          @value = nil
        end
      end
    end
  end
end
