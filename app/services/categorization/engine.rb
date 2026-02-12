# frozen_string_literal: true

require "concurrent"
require "ostruct"
require_relative "lru_cache"
require_relative "ml_confidence_integration"
require_relative "service_registry"

module Services::Categorization
  # Simple circuit breaker implementation for fault tolerance
  class SimpleCircuitBreaker
    attr_reader :name, :state, :failures, :last_failure

    def initialize(name:, threshold:, timeout:, logger:)
      @name = name
      @threshold = threshold
      @timeout = timeout
      @logger = logger
      @state = :closed
      @failures = 0
      @last_failure = nil
      @opened_at = nil
      @mutex = Mutex.new
    end

    def call(&block)
      @mutex.synchronize do
        case @state
        when :open
          if Time.current - @opened_at > @timeout
            @state = :half_open
            @logger.info "[CircuitBreaker] #{@name} entering half-open state"
          else
            raise Engine::CircuitOpenError, "Circuit #{@name} is open"
          end
        end
      end

      begin
        result = yield
        @mutex.synchronize do
          if @state == :half_open
            @state = :closed
            @failures = 0
            @logger.info "[CircuitBreaker] #{@name} closed after successful call"
          end
        end
        result
      rescue => e
        @mutex.synchronize do
          @failures += 1
          @last_failure = Time.current

          if @failures >= @threshold
            @state = :open
            @opened_at = Time.current
            @logger.error "[CircuitBreaker] #{@name} opened after #{@failures} failures"
          end
        end
        raise
      end
    end

    def reset
      @mutex.synchronize do
        @state = :closed
        @failures = 0
        @last_failure = nil
        @opened_at = nil
      end
    end
  end

  # Production-ready orchestrator service for expense categorization
  # Uses dependency injection for better testability and flexibility
  #
  # Key features:
  # - Dependency injection for all services
  # - Thread-safe operations with concurrent-ruby primitives
  # - Memory-bounded caching with LRU eviction and TTL
  # - Efficient database queries with batching and proper indexes
  # - Specific error handling with recovery mechanisms
  # - Asynchronous processing support for non-critical operations
  # - Circuit breaker pattern for external dependencies
  # - Comprehensive logging with correlation IDs
  #
  # Performance target: <10ms per categorization with bounded resource usage
  class Engine
    include ActiveSupport::Benchmarkable
    include MlConfidenceIntegration

    # Include monitoring capabilities if available
    begin
      require_relative "monitoring/engine_integration"
      include Monitoring::EngineIntegration
    rescue LoadError
      # Monitoring integration not available, continue without it
    end

    # Performance configuration
    PERFORMANCE_TARGET_MS = 10.0
    BATCH_SIZE_LIMIT = 1000
    MAX_CONCURRENT_OPERATIONS = 10
    CIRCUIT_BREAKER_THRESHOLD = 5
    CIRCUIT_BREAKER_TIMEOUT = 30.seconds

    # Categorization thresholds
    AUTO_CATEGORIZE_THRESHOLD = 0.70
    HIGH_CONFIDENCE_THRESHOLD = 0.85
    USER_PREFERENCE_BOOST = 0.15

    # Memory management
    MAX_PATTERN_CACHE_SIZE = 1000
    PATTERN_BATCH_SIZE = 100

    # Error types for specific handling
    class CategorizationError < StandardError; end
    class DatabaseError < CategorizationError; end
    class CacheError < CategorizationError; end
    class ValidationError < CategorizationError; end
    class CircuitOpenError < CategorizationError; end

    # Factory method for creating engine instances with dependencies
    def self.create(options = {})
      new(options)
    end

    attr_reader :service_registry, :logger

    def initialize(options = {})
      @options = Concurrent::Hash.new.merge(options)
      @logger = options.fetch(:logger, Rails.logger)

      # Initialize critical state first to ensure shutdown! can be called safely
      @shutdown = false
      @shutdown_mutex = Mutex.new

      begin
        # Initialize service registry for dependency injection
        @service_registry = options[:service_registry] || ServiceRegistry.new(logger: @logger)

        # Build default services if not provided
        @service_registry.build_defaults(options) unless options[:skip_defaults]

        # Initialize thread-safe state
        initialize_thread_safe_state

        # Initialize services from registry
        initialize_services_from_registry

        # Initialize circuit breakers
        initialize_circuit_breakers

        # Track initialization metrics
        @initialized_at = Time.current

        log_initialization
      rescue => e
        @logger.error "[Engine] Failed to initialize: #{e.message}"
        @logger.error e.backtrace.join("\n")

        # Mark as shutdown to prevent further operations
        @shutdown = true
        raise
      end
    end

    # Shutdown the engine cleanly
    def shutdown!
      return if @shutdown

      # Safety check: if mutex is not initialized, engine initialization failed
      return unless @shutdown_mutex

      @shutdown_mutex.synchronize do
        return if @shutdown

        @logger.info "[Engine] Shutting down categorization engine..."

        # Shutdown thread pool
        if @thread_pool
          @thread_pool.shutdown
          @thread_pool.wait_for_termination(5)
        end

        # Clear caches
        clear_all_caches

        # Mark as shutdown
        @shutdown = true

        @logger.info "[Engine] Categorization engine shutdown complete"
      end
    end

    # Check if engine is shutdown
    def shutdown?
      @shutdown
    end

    # Main categorization method with comprehensive error handling
    #
    # @param expense [Expense] The expense to categorize
    # @param options [Hash] Options for categorization
    # @return [CategorizationResult] The categorization result
    def categorize(expense, options = {})
      # Check shutdown state and return error result instead of raising
      if shutdown?
        return CategorizationResult.error("Service temporarily unavailable")
      end

      correlation_id = generate_correlation_id

      begin
        validate_expense!(expense)

        with_circuit_breaker(:categorization) do
          with_performance_tracking(expense, correlation_id) do
            perform_categorization(expense, options.merge(correlation_id: correlation_id))
          end
        end
      rescue ValidationError => e
        log_error(correlation_id, "Validation error", e)
        # Return only the simple error message without details for nil expense
        if e.message.include?("cannot be nil")
          CategorizationResult.error("Invalid expense")
        else
          CategorizationResult.error("Invalid expense: #{e.message}")
        end
      rescue CircuitOpenError => e
        log_error(correlation_id, "Circuit breaker open", e)
        CategorizationResult.error("Service temporarily unavailable")
      rescue DatabaseError => e
        log_error(correlation_id, "Database error", e)
        handle_database_error(expense, e)
      rescue ActiveRecord::ConnectionNotEstablished => e
        log_error(correlation_id, "Database connection error", e)
        CategorizationResult.error(e.message)
      rescue => e
        log_error(correlation_id, "Unexpected error", e)
        CategorizationResult.error("Categorization failed")
      end
    end

    # Learn from user correction with error recovery
    def learn_from_correction(expense, correct_category, predicted_category = nil, options = {})
      return if options[:skip_learning]

      # Check shutdown state and return error result instead of raising
      if shutdown?
        return LearningResult.error("Service temporarily unavailable")
      end

      correlation_id = generate_correlation_id

      begin
        validate_learning_params!(expense, correct_category)

        with_performance_tracking("learning", correlation_id) do
          result = @pattern_learner.learn_from_correction(
            expense,
            correct_category,
            predicted_category,
            options.merge(correlation_id: correlation_id)
          )

          # Invalidate affected cache entries only
          invalidate_relevant_cache(correct_category) if result.success?
          @pattern_cache_service.invalidate_all if @pattern_cache_service.respond_to?(:invalidate_all)

          result
        end
      rescue ValidationError => e
        log_error(correlation_id, "Learning validation error", e)
        LearningResult.error(e.message)
      rescue => e
        log_error(correlation_id, "Learning error", e)
        LearningResult.error("Learning failed")
      end
    end

    # Batch categorize with concurrent processing
    def batch_categorize(expenses, options = {})
      return [] if expenses.blank?

      # Check shutdown state and return error results instead of raising
      if shutdown?
        return expenses.map { CategorizationResult.error("Service temporarily unavailable") }
      end

      correlation_id = generate_correlation_id

      begin
        # Validate and limit batch size
        if expenses.size > BATCH_SIZE_LIMIT
          @logger.warn "[Engine] Batch size #{expenses.size} exceeds limit of #{BATCH_SIZE_LIMIT}, processing first #{BATCH_SIZE_LIMIT}"
          expenses = expenses.first(BATCH_SIZE_LIMIT)
        end

        with_performance_tracking("batch_categorize", correlation_id) do
          # Preload cache for efficiency
          @pattern_cache_service.preload_for_expenses(expenses) if @pattern_cache_service.respond_to?(:preload_for_expenses)

          # Process in parallel with controlled concurrency
          results = process_batch_with_concurrency(expenses, options, correlation_id)

          # Log batch performance
          log_batch_performance(results, correlation_id)

          results
        end
      rescue => e
        log_error(correlation_id, "Batch categorization error", e)
        expenses.map { CategorizationResult.error("Batch processing failed") }
      end
    end

    # Warm up with controlled resource usage
    def warm_up
      return { status: :shutdown } if shutdown?

      correlation_id = generate_correlation_id

      with_performance_tracking("warm_up", correlation_id) do
        @logger.info "[Engine] Starting warm-up... (correlation_id: #{correlation_id})"

        # Warm cache with most frequently used patterns only
        warm_frequently_used_patterns

        # Also warm the pattern cache service if it supports it
        cache_stats = {}
        if @pattern_cache_service.respond_to?(:warm_cache)
          cache_stats = @pattern_cache_service.warm_cache
        end

        @logger.info "[Engine] Warm-up completed (correlation_id: #{correlation_id})"
        {
          patterns: @pattern_cache_size.value,
          composites: cache_stats[:composites] || 0,
          user_prefs: cache_stats[:user_prefs] || 0
        }
      end
    rescue => e
      log_error(correlation_id, "Warm-up error", e)
      { status: :failed, error: e.message }
    end

    # Get comprehensive metrics
    def metrics
      {
        engine: engine_metrics,
        cache: cache_metrics,
        matcher: matcher_metrics,
        confidence: confidence_metrics,
        learner: learner_metrics,
        performance: performance_metrics
      }
    end

    # Check if engine is healthy
    def healthy?
      !shutdown? &&
        all_circuits_closed? &&
        cache_healthy? &&
        performance_within_target? &&
        memory_usage_acceptable?
    rescue
      false
    end

    # Reset the engine safely
    def reset!
      # Guard against nil mutex during initialization
      return unless @reset_mutex
      return if shutdown?

      @reset_mutex.synchronize do
        # Clear all caches
        clear_all_caches

        # Reset metrics
        @total_categorizations.value = 0
        @successful_categorizations.value = 0
        @pattern_cache_size.value = 0

        # Reset circuit breakers
        @circuit_breakers.each_value(&:reset)

        # Reset performance tracker
        @performance_tracker.reset! if @performance_tracker

        # Verify engine health after reset
        unless healthy?
          @logger.error "[Engine] Engine unhealthy after reset"
          raise CircuitOpenError, "Engine unhealthy after reset"
        end

        @logger.info "[Engine] Engine reset completed successfully"
      end
    end

    private

    def initialize_thread_safe_state
      # Use concurrent-ruby atomic primitives for thread safety
      @total_categorizations = Concurrent::AtomicFixnum.new(0)
      @successful_categorizations = Concurrent::AtomicFixnum.new(0)
      @pattern_cache_size = Concurrent::AtomicFixnum.new(0)

      # Thread-safe collections
      @pattern_cache = Concurrent::Map.new

      # Mutexes for critical sections
      @reset_mutex = Mutex.new
      @batch_mutex = Mutex.new
      @shutdown_mutex = Mutex.new
    end

    def initialize_services_from_registry
      @pattern_cache_service = @service_registry.get(:pattern_cache)
      @fuzzy_matcher = @service_registry.get(:fuzzy_matcher)
      @confidence_calculator = @service_registry.get(:confidence_calculator)
      @pattern_learner = @service_registry.get(:pattern_learner)
      @performance_tracker = @service_registry.get(:performance_tracker)
      @lru_cache = @service_registry.get(:lru_cache)

      # Thread pool for async operations
      initialize_thread_pool
    end

    def initialize_thread_pool
      @thread_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 2,
        max_threads: MAX_CONCURRENT_OPERATIONS,
        max_queue: 100,
        fallback_policy: :caller_runs
      )
    end

    def initialize_circuit_breakers
      @circuit_breakers = {
        categorization: create_circuit_breaker("categorization"),
        database: create_circuit_breaker("database"),
        cache: create_circuit_breaker("cache")
      }
    end

    def create_circuit_breaker(name)
      # Simple circuit breaker implementation
      # In production, you might want to use a more robust library
      SimpleCircuitBreaker.new(
        name: name,
        threshold: CIRCUIT_BREAKER_THRESHOLD,
        timeout: CIRCUIT_BREAKER_TIMEOUT,
        logger: @logger
      )
    end

    def clear_all_caches
      # Clear all caches - notify all components
      @pattern_cache_service.invalidate_all if @pattern_cache_service.respond_to?(:invalidate_all)
      @fuzzy_matcher.clear_cache if @fuzzy_matcher.respond_to?(:clear_cache)
      @confidence_calculator.clear_cache if @confidence_calculator.respond_to?(:clear_cache)

      # Clear internal caches
      @pattern_cache.clear
      @lru_cache.clear if @lru_cache.respond_to?(:clear)
    end

    def perform_categorization(expense, options)
      opts = default_options.merge(options)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Increment counter atomically
      @total_categorizations.increment

      # Step 1: Check user preferences (highest priority)
      if expense.merchant_name? && opts[:check_user_preferences]
        user_result = check_user_preference_safely(expense, opts[:correlation_id])
        if user_result
          @successful_categorizations.increment
          return user_result
        end
      end

      # Step 2: Find matching patterns efficiently
      pattern_matches = find_pattern_matches_efficiently(expense, opts)

      # Step 3: Handle no matches
      if pattern_matches.empty?
        return CategorizationResult.no_match(
          processing_time_ms: calculate_duration(start_time)
        )
      end

      # Step 4: Score and rank matches
      scored_matches = score_matches_with_caching(expense, pattern_matches, opts)

      # Step 5: Select best category
      best_match = scored_matches.first

      if best_match[:confidence] < opts[:min_confidence]
        return CategorizationResult.no_match(
          processing_time_ms: calculate_duration(start_time)
        )
      end

      # Step 6: Build result
      result = build_categorization_result(
        expense,
        best_match,
        scored_matches,
        opts,
        calculate_duration(start_time)
      )

      # Step 7: Auto-update expense if configured
      if opts[:auto_update] && result.high_confidence?
        if Rails.env.test?
          # In test environment, update synchronously to ensure deterministic behavior
          update_expense_sync(expense, result, opts[:correlation_id])
        else
          # In other environments, update asynchronously
          update_expense_async(expense, result, opts[:correlation_id])
        end
      end

      @successful_categorizations.increment if result.successful?

      result
    end

    def check_user_preference_safely(expense, correlation_id)
      with_circuit_breaker(:cache) do
        preference = @lru_cache.fetch("user_pref:#{expense.merchant_name.downcase}") do
          @pattern_cache_service.get_user_preference(expense.merchant_name)
        end

        return nil unless preference

        # Calculate confidence based on preference weight and usage
        base_confidence = [ preference.preference_weight / 10.0, 1.0 ].min
        confidence = [ base_confidence + USER_PREFERENCE_BOOST, 1.0 ].min

        CategorizationResult.from_user_preference(
          preference.category,
          confidence,
          processing_time_ms: 0.5
        )
      end
    rescue CircuitOpenError
      @logger.warn "[Engine] Cache circuit open, skipping user preferences (correlation_id: #{correlation_id})"
      nil
    end

    def find_pattern_matches_efficiently(expense, options)
      matches = []

      # Use batched pattern loading instead of loading all patterns
      pattern_batches = load_patterns_in_batches(options)

      pattern_batches.each do |patterns|
        # Process merchant patterns
        if expense.merchant_name?
          merchant_patterns = patterns.select { |p| p.pattern_type == "merchant" }
          if merchant_patterns.any?
            merchant_matches = @fuzzy_matcher.match_pattern(
              expense.merchant_name,
              merchant_patterns,
              options.slice(:min_confidence, :max_results)
            )
            matches.concat(process_fuzzy_matches(merchant_matches))
          end
        end

        # Process description patterns
        if expense.description?
          description_patterns = patterns.select { |p| p.pattern_type.in?(%w[keyword description]) }
          if description_patterns.any?
            description_matches = @fuzzy_matcher.match_pattern(
              expense.description,
              description_patterns,
              options.slice(:min_confidence, :max_results)
            )
            matches.concat(process_fuzzy_matches(description_matches))
          end
        end

        # Check other pattern types
        patterns.each do |pattern|
          next if pattern.pattern_type.in?(%w[merchant keyword description])

          if pattern.matches?(expense)
            matches << {
              pattern: pattern,
              match_score: pattern.effective_confidence,
              match_type: pattern.pattern_type
            }
          end
        end

        # Early exit if we have enough matches
        break if matches.size >= options.fetch(:max_results, 10) * 2
      end

      matches
    end

    def load_patterns_in_batches(options)
      cache_key = "patterns:batch:#{options[:pattern_types]&.join(',')}"

      @lru_cache.fetch(cache_key, ttl: 60) do
        patterns = CategorizationPattern
          .active
          .includes(:category)
          .order(usage_count: :desc, success_rate: :desc)

        if options[:pattern_types].present?
          patterns = patterns.where(pattern_type: options[:pattern_types])
        end

        # Load in batches to avoid memory bloat
        batches = []
        patterns.find_in_batches(batch_size: PATTERN_BATCH_SIZE) do |batch|
          batches << batch
          break if batches.size >= 5 # Limit to 500 patterns total
        end

        batches
      end
    end

    def score_matches_with_caching(expense, pattern_matches, options)
      scored = []

      # Group matches by category
      grouped = pattern_matches.group_by { |m| m[:pattern].category_id }

      grouped.each do |category_id, matches|
        # Cache confidence calculations
        cache_key = "confidence:#{expense.id}:#{category_id}"

        confidence_data = @lru_cache.fetch(cache_key, ttl: 30) do
          best_match = matches.max_by { |m| m[:match_score] }
          pattern = best_match[:pattern]
          category = Category.find(category_id)

          # Calculate comprehensive confidence score
          confidence_score = @confidence_calculator.calculate(
            expense,
            pattern,
            best_match[:match_score]
          )

          {
            category: category,
            confidence: confidence_score.score,
            confidence_score: confidence_score,
            patterns: matches.map { |m| m[:pattern] },
            match_type: best_match[:match_type]
          }
        end

        scored << confidence_data
      end

      # Sort by confidence descending
      scored.sort_by! { |s| -s[:confidence] }

      # Limit to top N if specified
      if options[:max_categories]
        scored = scored.first(options[:max_categories])
      end

      scored
    end

    def process_fuzzy_matches(match_result)
      return [] unless match_result.success?

      match_result.matches.map do |match|
        pattern = match[:pattern] || match[:object]
        next unless pattern.is_a?(CategorizationPattern)

        {
          pattern: pattern,
          match_score: match[:adjusted_score] || match[:score],
          match_type: "fuzzy_match"
        }
      end.compact
    end

    def update_expense_sync(expense, result, correlation_id)
      begin
        # Use ML confidence integration to properly update all fields
        update_expense_with_ml_confidence(expense, result)
      rescue => e
        log_error(correlation_id, "Failed to update expense #{expense.id}", e)
      end
    end

    def update_expense_async(expense, result, correlation_id)
      @thread_pool.post do
        begin
          with_circuit_breaker(:database) do
            # Use ML confidence integration to properly update all fields
            update_expense_with_ml_confidence(expense, result)
          end
        rescue => e
          log_error(correlation_id, "Failed to update expense #{expense.id}", e)
        end
      end
    end

    def process_batch_with_concurrency(expenses, options, correlation_id)
      # Preload patterns once for the batch
      preload_patterns_for_batch(expenses)

      # Process in parallel with futures
      futures = expenses.map do |expense|
        Concurrent::Future.execute(executor: @thread_pool) do
          categorize(expense, options.merge(skip_cache_preload: true))
        end
      end

      # Wait for all futures with timeout
      results = futures.map do |future|
        future.value(10) || CategorizationResult.error("Timeout")
      end

      log_batch_performance(results, correlation_id)
      results
    end

    def preload_patterns_for_batch(expenses)
      # Extract unique attributes for preloading
      merchant_names = expenses.map(&:merchant_name).compact.uniq

      # Preload in parallel
      Concurrent::Future.execute {
        merchant_names.each { |name|
          @lru_cache.fetch("user_pref:#{name.downcase}") {
            @pattern_cache_service.get_user_preference(name)
          }
        }
      }.value(5)
    end

    def warm_frequently_used_patterns
      # Load only the most frequently used patterns
      patterns = CategorizationPattern
        .active
        .frequently_used
        .includes(:category)
        .limit(100)

      patterns.find_each do |pattern|
        @pattern_cache[pattern.id] = pattern
        @pattern_cache_size.increment

        # Stop if cache is getting too large
        break if @pattern_cache_size.value >= MAX_PATTERN_CACHE_SIZE
      end
    end

    def invalidate_relevant_cache(category)
      # Invalidate only relevant cache entries
      @lru_cache.keys.each do |key|
        if key.to_s.include?("confidence:") && key.to_s.include?(":#{category.id}")
          @lru_cache.delete(key)
        end
      end

      # Also invalidate pattern cache for this category
      @pattern_cache.each do |id, pattern|
        if pattern.category_id == category.id
          @pattern_cache.delete(id)
          @pattern_cache_size.decrement
        end
      end
    end

    def validate_expense!(expense)
      raise ValidationError, "Expense cannot be nil" unless expense
      raise ValidationError, "Expense must be persisted" unless expense.persisted?
      raise ValidationError, "Expense must have merchant or description" unless expense.merchant_name? || expense.description?
    end

    def validate_learning_params!(expense, category)
      validate_expense!(expense)
      raise ValidationError, "Category cannot be nil" unless category
      raise ValidationError, "Category must be persisted" unless category.persisted?
    end

    def validate_and_limit_batch(expenses, correlation_id)
      raise ValidationError, "Batch cannot be empty" if expenses.blank?

      if expenses.size > BATCH_SIZE_LIMIT
        @logger.warn "[Engine] Batch size #{expenses.size} exceeds limit, processing first #{BATCH_SIZE_LIMIT} (correlation_id: #{correlation_id})"
        expenses = expenses.first(BATCH_SIZE_LIMIT)
      end

      expenses
    end

    def handle_database_error(expense, error)
      # Try to provide a degraded response using cache
      if @lru_cache.keys.any? { |k| k.to_s.start_with?("confidence:#{expense.id}:") }
        cached_key = @lru_cache.keys.find { |k| k.to_s.start_with?("confidence:#{expense.id}:") }
        cached_data = @lru_cache.read(cached_key)

        if cached_data
          return CategorizationResult.new(
            category: cached_data[:category],
            confidence: cached_data[:confidence] * 0.8, # Lower confidence for stale data
            method: "cached_fallback",
            metadata: { error: error.message }
          )
        end
      end

      CategorizationResult.error("Database unavailable")
    end

    def with_circuit_breaker(breaker_name, &block)
      breaker = @circuit_breakers[breaker_name]

      if breaker.respond_to?(:call)
        breaker.call(&block)
      else
        yield
      end
    rescue StandardError => e
      if e.message.include?("Circuit open")
        raise CircuitOpenError, "#{breaker_name} circuit is open"
      else
        raise
      end
    end

    def with_performance_tracking(operation, correlation_id, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result = yield

      duration_ms = calculate_duration(start_time)

      # Log slow operations
      if duration_ms > PERFORMANCE_TARGET_MS
        @logger.warn "[Engine] Slow operation '#{operation}': #{duration_ms.round(2)}ms (correlation_id: #{correlation_id})"
      end

      # Track in performance tracker
      @performance_tracker.track_operation(operation) { result } if @performance_tracker

      result
    end

    def generate_correlation_id
      SecureRandom.uuid
    end

    def log_error(correlation_id, context, error)
      @logger.error "[Engine] #{context} (correlation_id: #{correlation_id}): #{error.message}"
      @logger.error error.backtrace.first(5).join("\n") if error.backtrace
    end

    def log_initialization
      @logger.info "[Engine] Categorization Engine initialized (dependency injection, production-ready)"
      @logger.info "[Engine] Configuration: max_patterns=#{MAX_PATTERN_CACHE_SIZE}, " \
                   "batch_limit=#{BATCH_SIZE_LIMIT}, max_threads=#{MAX_CONCURRENT_OPERATIONS}"
    end

    def log_batch_performance(results, correlation_id)
      successful = results.count(&:successful?)
      avg_time = results.sum(&:processing_time_ms) / results.size.to_f

      Rails.logger.info "Batch categorization completed for #{results.size} expenses"
      @logger.info "[Engine] Batch completed: #{results.size} expenses, " \
                   "#{successful} successful (#{(successful.to_f / results.size * 100).round(1)}%), " \
                   "Avg: #{avg_time.round(2)}ms (correlation_id: #{correlation_id})"
    end

    def default_options
      {
        use_cache: true,
        check_user_preferences: true,
        include_alternatives: false,
        min_confidence: 0.5,
        max_results: 10,
        max_categories: 5,
        auto_update: true,
        skip_cache_preload: false
      }
    end

    def calculate_duration(start_time)
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
    end

    def build_categorization_result(expense, best_match, all_matches, options, duration_ms)
      alternatives = if options[:include_alternatives]
        all_matches[1..2].map do |match|
          {
            category: match[:category],
            confidence: match[:confidence]
          }
        end
      else
        []
      end

      CategorizationResult.new(
        category: best_match[:category],
        confidence: best_match[:confidence],
        patterns_used: best_match[:patterns].map { |p| "#{p.pattern_type}:#{p.pattern_value}" },
        confidence_breakdown: best_match[:confidence_score].factor_breakdown,
        alternative_categories: alternatives,
        processing_time_ms: duration_ms,
        cache_hits: @lru_cache.stats[:hits] || 0,
        method: best_match[:match_type] || "pattern_match",
        metadata: {
          expense_id: expense.id,
          patterns_evaluated: all_matches.sum { |m| m[:patterns].size },
          confidence_factors: best_match[:confidence_score].metadata[:factors_used]
        }
      )
    end

    # Metrics methods

    def engine_metrics
      {
        initialized_at: @initialized_at,
        uptime_seconds: Time.current - @initialized_at,
        total_categorizations: @total_categorizations.value,
        successful_categorizations: @successful_categorizations.value,
        success_rate: calculate_success_rate,
        thread_pool_status: thread_pool_status,
        shutdown: shutdown?
      }
    end

    def cache_metrics
      stats = @lru_cache.stats
      {
        hits: stats[:hits] || 0,
        lru_cache: {
          size: @lru_cache.keys.size,
          max_size: MAX_PATTERN_CACHE_SIZE,
          stats: stats
        },
        pattern_cache: {
          size: @pattern_cache_size.value,
          max_size: MAX_PATTERN_CACHE_SIZE
        }
      }
    end

    def matcher_metrics
      @fuzzy_matcher.metrics if @fuzzy_matcher.respond_to?(:metrics)
    end

    def confidence_metrics
      @confidence_calculator.metrics if @confidence_calculator.respond_to?(:metrics)
    end

    def learner_metrics
      @pattern_learner.metrics if @pattern_learner.respond_to?(:metrics)
    end

    def performance_metrics
      return {} unless @performance_tracker

      summary = @performance_tracker.summary
      {
        categorizations: {
          count: @total_categorizations.value,
          successful: @successful_categorizations.value
        },
        operations: summary,
        cache: @lru_cache.stats
      }
    end

    def health_metrics
      {
        healthy: healthy?,
        circuits_status: @circuit_breakers.transform_values { |cb| cb.state rescue :unknown },
        memory_usage_mb: memory_usage_mb,
        performance_within_target: performance_within_target?
      }
    end

    def circuit_breaker_metrics
      @circuit_breakers.transform_values do |cb|
        {
          state: cb.state,
          failures: (cb.failures rescue 0),
          last_failure: (cb.last_failure rescue nil)
        }
      end
    end

    def thread_pool_status
      return {} unless @thread_pool

      {
        active_count: @thread_pool.active_count,
        completed_tasks: @thread_pool.completed_task_count,
        queue_length: @thread_pool.queue_length,
        pool_size: @thread_pool.max_length
      }
    end

    def calculate_success_rate
      total = @total_categorizations.value
      return 0.0 if total == 0

      (@successful_categorizations.value.to_f / total * 100).round(2)
    end

    def all_circuits_closed?
      @circuit_breakers.values.all? { |cb| cb.state == :closed rescue true }
    end

    def cache_healthy?
      @lru_cache.keys.size < MAX_PATTERN_CACHE_SIZE * 0.9
    end

    def performance_within_target?
      return true unless @performance_tracker
      @performance_tracker.within_target?
    end

    def memory_usage_mb
      # Estimate memory usage
      ((@lru_cache.keys.size + @pattern_cache.size) * 1.0 / 1024).round(2)
    rescue
      0.0
    end

    def memory_usage_acceptable?
      memory_usage_mb < (MAX_PATTERN_CACHE_SIZE * 2.0 / 1024)
    end
  end
end
