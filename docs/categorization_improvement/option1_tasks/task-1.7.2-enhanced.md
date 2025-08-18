### Task 1.7.2: Service Integration and Orchestration (Enhanced)
**Priority**: HIGH  
**Estimated Hours**: 8-10
**Dependencies**: Task 1.7.1  
**Completion Status**: 30%

#### Executive Summary
Create a robust service orchestration layer that properly integrates PatternCache, FuzzyMatcher, ConfidenceCalculator, and PatternLearner into a cohesive categorization engine with clear boundaries, dependency injection, and fault tolerance.

#### Current Issues
- Mixed responsibilities in engine orchestration (violates Single Responsibility Principle)
- Hard-coded service dependencies preventing testing and flexibility
- No circuit breaker or fallback mechanisms for service failures
- Missing service registry pattern for dependency management
- Insufficient error context propagation

#### Technical Architecture

##### 1. Service Registry Pattern
```ruby
# app/services/categorization/service_registry.rb
module Categorization
  class ServiceRegistry
    include Singleton
    
    def initialize
      @services = {}
      @factories = {}
      @health_checks = {}
      @circuit_breakers = {}
    end
    
    # Register a service with optional factory and health check
    def register(name, service: nil, factory: nil, health_check: nil)
      raise ArgumentError, "Must provide either service instance or factory" unless service || factory
      
      @services[name] = service if service
      @factories[name] = factory if factory
      @health_checks[name] = health_check if health_check
      @circuit_breakers[name] = CircuitBreaker.new(name) if factory || service
    end
    
    # Get a service with circuit breaker protection
    def get(name)
      circuit_breaker = @circuit_breakers[name]
      raise ServiceNotRegisteredError, "Service #{name} not registered" unless circuit_breaker
      
      circuit_breaker.call do
        @services[name] ||= @factories[name]&.call
      end
    rescue CircuitBreaker::OpenError => e
      Rails.logger.error "Circuit breaker open for service: #{name}"
      fallback_for(name)
    end
    
    # Health check for all registered services
    def health_status
      @health_checks.each_with_object({}) do |(name, check), status|
        status[name] = check ? check.call : { status: 'unknown' }
      end
    end
    
    # Reset the registry (mainly for testing)
    def reset!
      @services.clear
      @factories.clear
      @health_checks.clear
      @circuit_breakers.clear
    end
    
    private
    
    def fallback_for(name)
      case name
      when :pattern_cache
        FallbackPatternCache.new
      when :fuzzy_matcher
        SimpleMatcher.new
      else
        raise ServiceUnavailableError, "No fallback available for #{name}"
      end
    end
  end
  
  # Circuit Breaker implementation
  class CircuitBreaker
    attr_reader :name, :failure_count, :last_failure_time
    
    FAILURE_THRESHOLD = 5
    TIMEOUT_DURATION = 30.seconds
    HALF_OPEN_REQUESTS = 1
    
    def initialize(name)
      @name = name
      @failure_count = 0
      @last_failure_time = nil
      @half_open_attempts = 0
      @mutex = Mutex.new
    end
    
    def call
      @mutex.synchronize do
        case state
        when :closed
          execute_with_failure_tracking { yield }
        when :open
          if timeout_expired?
            @half_open_attempts = 0
            transition_to_half_open
            execute_with_failure_tracking { yield }
          else
            raise OpenError, "Circuit breaker is open for #{@name}"
          end
        when :half_open
          if @half_open_attempts < HALF_OPEN_REQUESTS
            @half_open_attempts += 1
            execute_with_failure_tracking { yield }
          else
            raise OpenError, "Circuit breaker is half-open, waiting for test requests"
          end
        end
      end
    end
    
    private
    
    def state
      return :closed if @failure_count < FAILURE_THRESHOLD
      return :half_open if timeout_expired?
      :open
    end
    
    def execute_with_failure_tracking
      result = yield
      on_success
      result
    rescue => e
      on_failure(e)
      raise
    end
    
    def on_success
      @failure_count = 0
      @last_failure_time = nil
      @half_open_attempts = 0
    end
    
    def on_failure(error)
      @failure_count += 1
      @last_failure_time = Time.current
      
      Rails.logger.error "Circuit breaker failure ##{@failure_count} for #{@name}: #{error.message}"
      
      Infrastructure::MonitoringService::ErrorTracker.report(error, {
        service: @name,
        failure_count: @failure_count,
        circuit_state: state
      })
    end
    
    def timeout_expired?
      @last_failure_time && (Time.current - @last_failure_time) > TIMEOUT_DURATION
    end
    
    def transition_to_half_open
      Rails.logger.info "Circuit breaker transitioning to half-open for #{@name}"
    end
    
    class OpenError < StandardError; end
  end
end
```

##### 2. Enhanced Engine with Dependency Injection
```ruby
# app/services/categorization/engine.rb
module Categorization
  class Engine
    attr_reader :registry, :performance_tracker, :logger
    
    def initialize(registry: ServiceRegistry.instance, logger: Rails.logger)
      @registry = registry
      @logger = logger
      @performance_tracker = Infrastructure::MonitoringService::PerformanceTracker
      @correlation_id = nil
    end
    
    def categorize(expense, options = {})
      @correlation_id = options[:correlation_id] || SecureRandom.uuid
      
      log_operation("categorization_started", expense_id: expense.id)
      
      result = nil
      duration = Benchmark.realtime do
        result = perform_categorization(expense, options)
      end
      
      track_metrics(expense, result, duration)
      log_operation("categorization_completed", {
        expense_id: expense.id,
        duration_ms: (duration * 1000).round(2),
        success: result.successful?
      })
      
      result
    rescue => e
      handle_error(e, expense)
    end
    
    def batch_categorize(expenses, options = {})
      @correlation_id = options[:correlation_id] || SecureRandom.uuid
      batch_size = options[:batch_size] || 100
      parallel = options[:parallel] || false
      
      log_operation("batch_categorization_started", count: expenses.size)
      
      results = if parallel
        categorize_in_parallel(expenses, batch_size, options)
      else
        categorize_sequentially(expenses, options)
      end
      
      log_operation("batch_categorization_completed", {
        count: expenses.size,
        successful: results.count(&:successful?)
      })
      
      results
    end
    
    def learn_from_correction(expense, correct_category, predicted_category = nil)
      @correlation_id = SecureRandom.uuid
      
      learner = @registry.get(:pattern_learner)
      learner.learn_from_correction(expense, correct_category, predicted_category)
      
      # Invalidate relevant caches
      cache = @registry.get(:pattern_cache)
      cache.invalidate_for_category(correct_category.id)
      cache.invalidate_for_merchant(expense.merchant_name) if expense.merchant_name.present?
      
      log_operation("learning_completed", {
        expense_id: expense.id,
        correct_category_id: correct_category.id
      })
    rescue => e
      handle_error(e, expense)
    end
    
    private
    
    def perform_categorization(expense, options)
      # Step 1: Enrich expense data
      enriched_data = enrich_expense_data(expense)
      
      # Step 2: Fetch relevant patterns with caching
      patterns = fetch_patterns_with_fallback(enriched_data)
      
      # Step 3: Perform multi-strategy matching
      matches = perform_matching(enriched_data, patterns, options)
      
      # Step 4: Calculate confidence scores with explanation
      scored_matches = calculate_confidence_scores(expense, matches, enriched_data)
      
      # Step 5: Apply business rules and select best category
      result = apply_business_rules_and_select(scored_matches, expense, options)
      
      # Step 6: Record for learning if enabled
      record_for_learning(expense, result) if options[:track_usage]
      
      result
    end
    
    def enrich_expense_data(expense)
      {
        expense: expense,
        merchant_normalized: normalize_merchant_name(expense.merchant_name),
        description_tokens: tokenize_description(expense.description),
        amount_range: determine_amount_range(expense.amount),
        time_context: extract_time_context(expense),
        bank_context: extract_bank_context(expense),
        historical_context: fetch_historical_context(expense)
      }
    end
    
    def fetch_patterns_with_fallback(enriched_data)
      cache = @registry.get(:pattern_cache)
      
      patterns = cache.fetch_patterns(
        bank: enriched_data[:bank_context][:bank_name],
        merchant: enriched_data[:merchant_normalized],
        amount_range: enriched_data[:amount_range]
      )
      
      # Fallback to database if cache fails
      if patterns.nil? || patterns.empty?
        patterns = fetch_patterns_from_database(enriched_data)
      end
      
      patterns
    rescue => e
      log_operation("pattern_fetch_failed", error: e.message)
      fetch_patterns_from_database(enriched_data)
    end
    
    def perform_matching(enriched_data, patterns, options)
      matcher = @registry.get(:fuzzy_matcher)
      strategies = options[:matching_strategies] || [:merchant, :keyword, :pattern, :amount]
      
      matches = []
      
      strategies.each do |strategy|
        strategy_matches = case strategy
        when :merchant
          match_merchant(matcher, enriched_data, patterns)
        when :keyword
          match_keywords(matcher, enriched_data, patterns)
        when :pattern
          match_patterns(matcher, enriched_data, patterns)
        when :amount
          match_amount_range(enriched_data, patterns)
        end
        
        matches.concat(strategy_matches) if strategy_matches
      end
      
      # Deduplicate and sort by relevance
      deduplicate_and_rank_matches(matches)
    end
    
    def calculate_confidence_scores(expense, matches, enriched_data)
      calculator = @registry.get(:confidence_calculator)
      
      matches.map do |match|
        confidence_result = calculator.calculate(
          expense: expense,
          pattern: match[:pattern],
          match_data: match,
          context: enriched_data
        )
        
        {
          category: match[:pattern].category,
          pattern: match[:pattern],
          confidence: confidence_result[:score],
          explanation: confidence_result[:explanation],
          factors: confidence_result[:factors]
        }
      end
    end
    
    def apply_business_rules_and_select(scored_matches, expense, options)
      # Apply business rules
      filtered_matches = apply_business_rules(scored_matches, expense)
      
      # Group by category and select best match per category
      by_category = filtered_matches.group_by { |m| m[:category] }
      
      best_per_category = by_category.map do |category, matches|
        best = matches.max_by { |m| m[:confidence] }
        {
          category: category,
          confidence: best[:confidence],
          patterns: matches.map { |m| m[:pattern] },
          explanation: best[:explanation],
          factors: best[:factors]
        }
      end
      
      # Select the best category based on confidence and rules
      selected = select_best_category(best_per_category, options)
      
      build_categorization_result(selected, expense)
    end
    
    def apply_business_rules(matches, expense)
      # Filter out low confidence matches
      matches = matches.select { |m| m[:confidence] >= 0.3 }
      
      # Apply merchant override rules
      if expense.merchant_name.present?
        merchant_overrides = fetch_merchant_overrides(expense.merchant_name)
        matches = apply_merchant_overrides(matches, merchant_overrides)
      end
      
      # Apply amount-based rules
      matches = apply_amount_rules(matches, expense.amount)
      
      # Apply time-based rules
      matches = apply_time_rules(matches, expense.created_at)
      
      matches
    end
    
    def select_best_category(candidates, options)
      return nil if candidates.empty?
      
      # Apply confidence threshold
      min_confidence = options[:min_confidence] || 0.5
      candidates = candidates.select { |c| c[:confidence] >= min_confidence }
      
      return nil if candidates.empty?
      
      # Sort by confidence and apply tie-breaking rules
      candidates.sort_by! { |c| -c[:confidence] }
      
      # If top two are very close, apply additional rules
      if candidates.size > 1 && (candidates[0][:confidence] - candidates[1][:confidence]) < 0.05
        apply_tie_breaking_rules(candidates)
      else
        candidates.first
      end
    end
    
    def build_categorization_result(selected, expense)
      if selected
        CategorizationResult.new(
          category: selected[:category],
          confidence: selected[:confidence],
          patterns_used: selected[:patterns],
          explanation: selected[:explanation],
          factors: selected[:factors],
          correlation_id: @correlation_id
        )
      else
        CategorizationResult.new(
          category: nil,
          confidence: 0.0,
          explanation: "No matching patterns found with sufficient confidence",
          correlation_id: @correlation_id
        )
      end
    end
    
    def categorize_in_parallel(expenses, batch_size, options)
      require 'parallel'
      
      Parallel.map(expenses.each_slice(batch_size), in_threads: 4) do |batch|
        batch.map { |expense| categorize(expense, options) }
      end.flatten
    end
    
    def categorize_sequentially(expenses, options)
      expenses.map { |expense| categorize(expense, options) }
    end
    
    def track_metrics(expense, result, duration)
      @performance_tracker.track("categorization", "process", duration * 1000, {
        success: result.successful?,
        confidence: result.confidence,
        category_id: result.category&.id
      })
      
      Infrastructure::MonitoringService::Analytics.record_custom_metric(
        "categorization_confidence",
        result.confidence,
        {
          category: result.category&.name,
          success: result.successful?
        }
      )
    end
    
    def log_operation(operation, data = {})
      @logger.info({
        service: 'categorization_engine',
        operation: operation,
        correlation_id: @correlation_id,
        timestamp: Time.current.iso8601
      }.merge(data).to_json)
    end
    
    def handle_error(error, expense)
      Infrastructure::MonitoringService::ErrorTracker.report(error, {
        service: 'categorization_engine',
        expense_id: expense&.id,
        correlation_id: @correlation_id
      })
      
      CategorizationResult.new(
        category: nil,
        confidence: 0.0,
        error: error.message,
        correlation_id: @correlation_id
      )
    end
    
    # Additional helper methods...
    def normalize_merchant_name(name)
      return nil if name.blank?
      name.downcase.strip.gsub(/[^a-z0-9\s]/, '')
    end
    
    def tokenize_description(description)
      return [] if description.blank?
      description.downcase.split(/\s+/).reject { |t| t.length < 3 }
    end
    
    def determine_amount_range(amount)
      case amount
      when 0..10 then :micro
      when 10..50 then :small
      when 50..200 then :medium
      when 200..1000 then :large
      else :extra_large
      end
    end
    
    def extract_time_context(expense)
      {
        hour: expense.created_at.hour,
        day_of_week: expense.created_at.wday,
        is_weekend: [0, 6].include?(expense.created_at.wday),
        is_business_hours: (9..17).include?(expense.created_at.hour)
      }
    end
    
    def extract_bank_context(expense)
      {
        bank_name: expense.email_account&.bank_name,
        account_type: expense.email_account&.account_type
      }
    end
    
    def fetch_historical_context(expense)
      # Fetch similar past expenses for context
      similar = Expense.where(merchant_name: expense.merchant_name)
                      .where.not(id: expense.id)
                      .where.not(category_id: nil)
                      .limit(5)
      
      {
        previous_categories: similar.pluck(:category_id).uniq,
        average_amount: similar.average(:amount),
        frequency: similar.count
      }
    end
  end
  
  # Enhanced Categorization Result
  class CategorizationResult
    attr_reader :category, :confidence, :patterns_used, :explanation, 
                :factors, :error, :correlation_id
    
    def initialize(attrs = {})
      @category = attrs[:category]
      @confidence = attrs[:confidence] || 0.0
      @patterns_used = attrs[:patterns_used] || []
      @explanation = attrs[:explanation]
      @factors = attrs[:factors] || {}
      @error = attrs[:error]
      @correlation_id = attrs[:correlation_id]
      @timestamp = Time.current
    end
    
    def successful?
      @category.present? && @error.nil?
    end
    
    def high_confidence?
      @confidence >= 0.8
    end
    
    def medium_confidence?
      @confidence >= 0.6 && @confidence < 0.8
    end
    
    def low_confidence?
      @confidence < 0.6
    end
    
    def to_h
      {
        category_id: @category&.id,
        category_name: @category&.name,
        confidence: @confidence,
        confidence_level: confidence_level,
        patterns_used: @patterns_used.map(&:id),
        explanation: @explanation,
        factors: @factors,
        error: @error,
        correlation_id: @correlation_id,
        timestamp: @timestamp.iso8601
      }
    end
    
    def to_json
      to_h.to_json
    end
    
    private
    
    def confidence_level
      return 'high' if high_confidence?
      return 'medium' if medium_confidence?
      'low'
    end
  end
end
```

##### 3. Service Initialization and Configuration
```ruby
# config/initializers/categorization_services.rb
Rails.application.config.after_initialize do
  registry = Categorization::ServiceRegistry.instance
  
  # Register Pattern Cache
  registry.register(:pattern_cache,
    factory: -> { Categorization::PatternCache.instance },
    health_check: -> { 
      cache = Categorization::PatternCache.instance
      metrics = cache.metrics
      {
        status: metrics[:hit_rate] > 70 ? 'healthy' : 'degraded',
        hit_rate: metrics[:hit_rate],
        entries: metrics[:memory_cache_entries]
      }
    }
  )
  
  # Register Fuzzy Matcher
  registry.register(:fuzzy_matcher,
    factory: -> { Categorization::Matchers::FuzzyMatcher.new },
    health_check: -> {
      matcher = Categorization::Matchers::FuzzyMatcher.new
      test_result = matcher.match_pattern("test", [])
      { status: test_result.is_a?(Array) ? 'healthy' : 'unhealthy' }
    }
  )
  
  # Register Confidence Calculator
  registry.register(:confidence_calculator,
    factory: -> { Categorization::ConfidenceCalculator.new },
    health_check: -> { { status: 'healthy' } }
  )
  
  # Register Pattern Learner
  registry.register(:pattern_learner,
    factory: -> { Categorization::PatternLearner.new },
    health_check: -> { 
      learner = Categorization::PatternLearner.new
      { 
        status: 'healthy',
        pending_feedback: PatternFeedback.pending.count
      }
    }
  )
  
  # Warm up the pattern cache on startup (async)
  if Rails.env.production?
    PatternCacheWarmupJob.perform_later
  end
end
```

#### Implementation Requirements

##### Database Changes
```ruby
# db/migrate/add_correlation_id_to_expenses.rb
class AddCorrelationIdToExpenses < ActiveRecord::Migration[8.0]
  def change
    add_column :expenses, :categorization_correlation_id, :string
    add_column :expenses, :categorization_confidence, :decimal, precision: 5, scale: 4
    add_column :expenses, :categorization_factors, :jsonb, default: {}
    
    add_index :expenses, :categorization_correlation_id
    add_index :expenses, :categorization_confidence
  end
end

# db/migrate/create_categorization_metrics.rb
class CreateCategorizationMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :categorization_metrics do |t|
      t.string :correlation_id, null: false
      t.references :expense, foreign_key: true
      t.references :category, foreign_key: true
      t.decimal :confidence, precision: 5, scale: 4
      t.decimal :duration_ms, precision: 8, scale: 2
      t.boolean :successful, default: false
      t.jsonb :factors, default: {}
      t.jsonb :patterns_used, default: []
      t.string :error_message
      
      t.timestamps
    end
    
    add_index :categorization_metrics, :correlation_id
    add_index :categorization_metrics, :successful
    add_index :categorization_metrics, :created_at
  end
end
```

##### Background Jobs
```ruby
# app/jobs/pattern_cache_warmup_job.rb
class PatternCacheWarmupJob < ApplicationJob
  queue_as :low_priority
  
  def perform
    cache = Categorization::PatternCache.instance
    
    Rails.logger.info "Starting pattern cache warmup"
    start_time = Time.current
    
    # Warm up patterns by category
    Category.active.find_each do |category|
      patterns = category.categorization_patterns.active
      cache.warm_patterns(category.id, patterns)
    end
    
    # Warm up high-frequency merchant patterns
    top_merchants = Expense.group(:merchant_name)
                           .where.not(merchant_name: nil)
                           .order('COUNT(*) DESC')
                           .limit(100)
                           .pluck(:merchant_name)
    
    top_merchants.each do |merchant|
      patterns = CategorizationPattern.joins(:category)
                                     .where(pattern_type: 'merchant')
                                     .where('pattern_value LIKE ?', "%#{merchant.downcase}%")
      cache.warm_patterns("merchant:#{merchant}", patterns)
    end
    
    duration = Time.current - start_time
    Rails.logger.info "Pattern cache warmup completed in #{duration.round(2)} seconds"
    
    # Record metrics
    Infrastructure::MonitoringService::PerformanceTracker.track(
      "pattern_cache", "warmup", duration * 1000
    )
  end
end
```

#### Testing Strategy

##### Unit Tests
```ruby
# spec/services/categorization/service_registry_spec.rb
RSpec.describe Categorization::ServiceRegistry do
  let(:registry) { described_class.instance }
  
  before { registry.reset! }
  
  describe '#register' do
    it 'registers a service instance' do
      service = double('service')
      registry.register(:test_service, service: service)
      
      expect(registry.get(:test_service)).to eq(service)
    end
    
    it 'registers a service factory' do
      factory = -> { double('service') }
      registry.register(:test_service, factory: factory)
      
      expect(registry.get(:test_service)).to be_present
    end
    
    it 'raises error without service or factory' do
      expect {
        registry.register(:test_service)
      }.to raise_error(ArgumentError)
    end
  end
  
  describe '#get with circuit breaker' do
    let(:service) { double('service') }
    
    before do
      registry.register(:test_service, service: service)
    end
    
    it 'returns service when circuit is closed' do
      allow(service).to receive(:some_method).and_return('result')
      
      expect(registry.get(:test_service)).to eq(service)
    end
    
    context 'when service fails repeatedly' do
      before do
        allow(service).to receive(:some_method).and_raise(StandardError)
        
        # Trigger failures to open circuit
        5.times do
          registry.get(:test_service) rescue nil
        end
      end
      
      it 'opens circuit breaker after threshold' do
        expect {
          registry.get(:test_service)
        }.to raise_error(Categorization::CircuitBreaker::OpenError)
      end
    end
  end
  
  describe '#health_status' do
    it 'checks health of all registered services' do
      health_check = -> { { status: 'healthy', metric: 100 } }
      registry.register(:test_service, 
        service: double('service'),
        health_check: health_check
      )
      
      status = registry.health_status
      
      expect(status[:test_service]).to eq({ status: 'healthy', metric: 100 })
    end
  end
end

# spec/services/categorization/engine_spec.rb
RSpec.describe Categorization::Engine do
  let(:registry) { Categorization::ServiceRegistry.instance }
  let(:engine) { described_class.new(registry: registry) }
  
  before do
    registry.reset!
    setup_mock_services
  end
  
  def setup_mock_services
    registry.register(:pattern_cache, service: mock_pattern_cache)
    registry.register(:fuzzy_matcher, service: mock_fuzzy_matcher)
    registry.register(:confidence_calculator, service: mock_confidence_calculator)
    registry.register(:pattern_learner, service: mock_pattern_learner)
  end
  
  describe '#categorize' do
    let(:expense) { create(:expense, description: 'STARBUCKS COFFEE', amount: 5.50) }
    let(:category) { create(:category, name: 'Food & Dining') }
    let(:pattern) { create(:categorization_pattern, category: category) }
    
    it 'successfully categorizes an expense' do
      allow(mock_pattern_cache).to receive(:fetch_patterns).and_return([pattern])
      allow(mock_fuzzy_matcher).to receive(:match_pattern).and_return([{
        pattern: pattern,
        score: 0.9
      }])
      allow(mock_confidence_calculator).to receive(:calculate).and_return({
        score: 0.85,
        explanation: 'High merchant match',
        factors: { merchant_match: 0.9, pattern_weight: 0.8 }
      })
      
      result = engine.categorize(expense)
      
      expect(result).to be_successful
      expect(result.category).to eq(category)
      expect(result.confidence).to eq(0.85)
      expect(result.explanation).to include('merchant match')
    end
    
    it 'handles service failures gracefully' do
      allow(mock_pattern_cache).to receive(:fetch_patterns).and_raise(StandardError, 'Cache error')
      
      result = engine.categorize(expense)
      
      expect(result).not_to be_successful
      expect(result.error).to include('Cache error')
    end
    
    it 'tracks performance metrics' do
      allow(mock_pattern_cache).to receive(:fetch_patterns).and_return([])
      
      expect(Infrastructure::MonitoringService::PerformanceTracker)
        .to receive(:track)
        .with('categorization', 'process', anything, anything)
      
      engine.categorize(expense)
    end
  end
  
  describe '#batch_categorize' do
    let(:expenses) { create_list(:expense, 10) }
    
    it 'processes expenses in batches' do
      allow(mock_pattern_cache).to receive(:fetch_patterns).and_return([])
      
      results = engine.batch_categorize(expenses, batch_size: 5)
      
      expect(results.size).to eq(10)
    end
    
    it 'supports parallel processing' do
      allow(mock_pattern_cache).to receive(:fetch_patterns).and_return([])
      
      results = engine.batch_categorize(expenses, parallel: true)
      
      expect(results.size).to eq(10)
    end
  end
  
  describe '#learn_from_correction' do
    let(:expense) { create(:expense) }
    let(:category) { create(:category) }
    
    it 'triggers learning and cache invalidation' do
      expect(mock_pattern_learner)
        .to receive(:learn_from_correction)
        .with(expense, category, nil)
      
      expect(mock_pattern_cache)
        .to receive(:invalidate_for_category)
        .with(category.id)
      
      engine.learn_from_correction(expense, category)
    end
  end
end
```

##### Integration Tests
```ruby
# spec/services/categorization/engine_integration_spec.rb
RSpec.describe 'Categorization Engine Integration', type: :integration do
  let(:engine) { Categorization::Engine.new }
  
  before do
    # Set up real services
    Categorization::ServiceRegistry.instance.reset!
    load Rails.root.join('config/initializers/categorization_services.rb')
    
    # Create test data
    create_test_patterns
  end
  
  def create_test_patterns
    @food_category = create(:category, name: 'Food & Dining')
    @transport_category = create(:category, name: 'Transportation')
    
    create(:categorization_pattern,
      category: @food_category,
      pattern_type: 'merchant',
      pattern_value: 'starbucks',
      confidence_weight: 0.9
    )
    
    create(:categorization_pattern,
      category: @transport_category,
      pattern_type: 'merchant',
      pattern_value: 'uber',
      confidence_weight: 0.85
    )
  end
  
  describe 'end-to-end categorization' do
    it 'categorizes food expense correctly' do
      expense = create(:expense,
        description: 'STARBUCKS COFFEE SHOP',
        merchant_name: 'Starbucks',
        amount: 6.50
      )
      
      result = engine.categorize(expense)
      
      expect(result).to be_successful
      expect(result.category).to eq(@food_category)
      expect(result.confidence).to be > 0.8
      expect(result.patterns_used).not_to be_empty
    end
    
    it 'categorizes transport expense correctly' do
      expense = create(:expense,
        description: 'UBER TRIP',
        merchant_name: 'Uber',
        amount: 15.00
      )
      
      result = engine.categorize(expense)
      
      expect(result).to be_successful
      expect(result.category).to eq(@transport_category)
      expect(result.confidence).to be > 0.7
    end
    
    it 'handles unknown merchants' do
      expense = create(:expense,
        description: 'UNKNOWN MERCHANT XYZ',
        amount: 50.00
      )
      
      result = engine.categorize(expense)
      
      expect(result).not_to be_successful
      expect(result.confidence).to eq(0.0)
      expect(result.explanation).to include('No matching patterns')
    end
  end
  
  describe 'performance requirements' do
    it 'categorizes within 10ms per expense' do
      expenses = create_list(:expense, 100)
      
      durations = expenses.map do |expense|
        Benchmark.realtime { engine.categorize(expense) }
      end
      
      average_duration = durations.sum / durations.size
      
      expect(average_duration).to be < 0.010 # 10ms
    end
    
    it 'batch categorizes efficiently' do
      expenses = create_list(:expense, 1000)
      
      duration = Benchmark.realtime do
        engine.batch_categorize(expenses, batch_size: 100, parallel: true)
      end
      
      expect(duration).to be < 5.0 # 5 seconds for 1000 expenses
    end
  end
  
  describe 'fault tolerance' do
    it 'continues processing when individual categorizations fail' do
      expenses = create_list(:expense, 10)
      
      # Make one expense problematic
      expenses[5].update!(description: nil, merchant_name: nil)
      
      results = engine.batch_categorize(expenses)
      
      expect(results.size).to eq(10)
      expect(results[5]).not_to be_successful
      expect(results.select(&:successful?).size).to eq(9)
    end
    
    it 'recovers from temporary service failures' do
      expense = create(:expense, description: 'STARBUCKS')
      
      # Simulate temporary Redis failure
      allow(Redis.current).to receive(:get).and_raise(Redis::CannotConnectError).once
      allow(Redis.current).to receive(:get).and_call_original
      
      result = engine.categorize(expense)
      
      # Should fall back to database patterns
      expect(result).to be_present
    end
  end
end
```

#### Performance Requirements
- Average categorization time: < 10ms per expense
- Batch processing: < 5ms per expense when processing 100+ expenses
- Cache hit rate: > 90% after warmup
- Circuit breaker recovery: < 30 seconds
- Memory usage: < 100MB for pattern cache
- Concurrent processing: Support 4+ parallel workers

#### Monitoring and Observability
```yaml
# config/datadog/monitors/categorization.yml
monitors:
  - name: Categorization Success Rate
    type: metric
    query: avg(last_5m):avg:categorization.success.rate < 0.85
    message: "Categorization success rate dropped below 85%"
    tags:
      - service:categorization
      - priority:high
    
  - name: Categorization Response Time
    type: metric
    query: avg(last_5m):avg:categorization.duration > 10
    message: "Categorization taking longer than 10ms on average"
    tags:
      - service:categorization
      - priority:medium
    
  - name: Circuit Breaker Open
    type: log
    query: "Circuit breaker open" service:categorization
    message: "Categorization circuit breaker is open"
    tags:
      - service:categorization
      - priority:critical
    
  - name: Pattern Cache Hit Rate
    type: metric
    query: avg(last_15m):avg:pattern_cache.hit_rate < 0.7
    message: "Pattern cache hit rate below 70%"
    tags:
      - service:categorization
      - priority:medium
```

#### Rollout Plan
1. **Phase 1**: Deploy service registry and circuit breaker (no behavior change)
2. **Phase 2**: Migrate existing engine to use registry (feature flagged)
3. **Phase 3**: Enable parallel processing for batch operations
4. **Phase 4**: Full rollout with monitoring
5. **Phase 5**: Performance tuning based on metrics

#### Success Metrics
- Categorization accuracy: > 90%
- Response time P95: < 15ms
- Service availability: > 99.9%
- Cache hit rate: > 90%
- Error rate: < 0.1%
- Learning effectiveness: 20% improvement in accuracy after 1000 corrections

## UX Specifications for Service Integration Dashboard

### Overview
The Service Integration Dashboard provides real-time visibility into the categorization engine's service health, performance metrics, and integration status. This interface enables operations teams and administrators to monitor, troubleshoot, and optimize the categorization system.

### Information Architecture

#### Primary Navigation Structure
```
Dashboard (Main View)
├── Service Health Overview
├── Integration Status
├── Performance Metrics
├── Error Recovery Center
└── Configuration Management
```

### UI Components and Design Specifications

#### 1. Service Health Overview Dashboard

##### Layout and Structure
```erb
<!-- app/views/admin/categorization/service_dashboard/index.html.erb -->
<div class="min-h-screen bg-slate-50" data-controller="service-dashboard" data-service-dashboard-refresh-interval-value="5000">
  <!-- Header with Real-time Status Indicator -->
  <div class="bg-white border-b border-slate-200 sticky top-0 z-40">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
      <div class="flex justify-between items-center">
        <div class="flex items-center space-x-4">
          <h1 class="text-2xl font-bold text-slate-900">Service Integration Dashboard</h1>
          <!-- Real-time Status Badge -->
          <div data-service-dashboard-target="overallStatus" class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium">
            <span class="w-2 h-2 rounded-full mr-2 animate-pulse"></span>
            <span data-service-dashboard-target="statusText">Checking...</span>
          </div>
        </div>
        
        <!-- Action Buttons -->
        <div class="flex gap-3">
          <button data-action="click->service-dashboard#exportMetrics"
                  class="inline-flex items-center px-4 py-2 bg-white border border-slate-300 rounded-lg text-sm font-medium text-slate-700 hover:bg-slate-50 transition-colors">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"/>
            </svg>
            Export Metrics
          </button>
          
          <button data-action="click->service-dashboard#runHealthCheck"
                  class="inline-flex items-center px-4 py-2 bg-teal-700 text-white rounded-lg text-sm font-medium hover:bg-teal-800 transition-colors">
            <svg class="w-4 h-4 mr-2 animate-spin hidden" data-service-dashboard-target="refreshIcon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
            Run Health Check
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Service Status Grid -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <!-- Critical Services Status Cards -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
      <!-- Pattern Cache Service -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 relative overflow-hidden"
           data-service-dashboard-target="patternCacheCard">
        <div class="absolute top-0 right-0 w-24 h-24 -mr-8 -mt-8">
          <div class="absolute transform rotate-45 bg-teal-100 opacity-20 rounded-xl w-24 h-24"></div>
        </div>
        <div class="relative">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-sm font-medium text-slate-700">Pattern Cache</h3>
            <span data-service-dashboard-target="patternCacheStatus" class="w-3 h-3 rounded-full"></span>
          </div>
          <div class="space-y-2">
            <div class="flex justify-between items-baseline">
              <span class="text-2xl font-bold text-slate-900" data-service-dashboard-target="cacheHitRate">--</span>
              <span class="text-xs text-slate-500">Hit Rate</span>
            </div>
            <div class="w-full bg-slate-200 rounded-full h-1.5">
              <div data-service-dashboard-target="cacheHitRateBar" class="bg-teal-700 h-1.5 rounded-full transition-all duration-300" style="width: 0%"></div>
            </div>
            <div class="grid grid-cols-2 gap-2 mt-3 pt-3 border-t border-slate-100">
              <div>
                <p class="text-xs text-slate-500">Entries</p>
                <p class="text-sm font-medium text-slate-900" data-service-dashboard-target="cacheEntries">--</p>
              </div>
              <div>
                <p class="text-xs text-slate-500">Memory</p>
                <p class="text-sm font-medium text-slate-900" data-service-dashboard-target="cacheMemory">--</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Fuzzy Matcher Service -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 relative overflow-hidden"
           data-service-dashboard-target="fuzzyMatcherCard">
        <div class="absolute top-0 right-0 w-24 h-24 -mr-8 -mt-8">
          <div class="absolute transform rotate-45 bg-amber-100 opacity-20 rounded-xl w-24 h-24"></div>
        </div>
        <div class="relative">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-sm font-medium text-slate-700">Fuzzy Matcher</h3>
            <span data-service-dashboard-target="fuzzyMatcherStatus" class="w-3 h-3 rounded-full"></span>
          </div>
          <div class="space-y-2">
            <div class="flex justify-between items-baseline">
              <span class="text-2xl font-bold text-slate-900" data-service-dashboard-target="matcherAvgTime">--</span>
              <span class="text-xs text-slate-500">Avg Time (ms)</span>
            </div>
            <div class="grid grid-cols-2 gap-2 mt-3 pt-3 border-t border-slate-100">
              <div>
                <p class="text-xs text-slate-500">Requests/min</p>
                <p class="text-sm font-medium text-slate-900" data-service-dashboard-target="matcherRPM">--</p>
              </div>
              <div>
                <p class="text-xs text-slate-500">Success Rate</p>
                <p class="text-sm font-medium text-slate-900" data-service-dashboard-target="matcherSuccess">--</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Confidence Calculator Service -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 relative overflow-hidden"
           data-service-dashboard-target="confidenceCalcCard">
        <div class="absolute top-0 right-0 w-24 h-24 -mr-8 -mt-8">
          <div class="absolute transform rotate-45 bg-emerald-100 opacity-20 rounded-xl w-24 h-24"></div>
        </div>
        <div class="relative">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-sm font-medium text-slate-700">Confidence Calculator</h3>
            <span data-service-dashboard-target="confidenceCalcStatus" class="w-3 h-3 rounded-full"></span>
          </div>
          <div class="space-y-2">
            <div class="flex justify-between items-baseline">
              <span class="text-2xl font-bold text-slate-900" data-service-dashboard-target="avgConfidence">--</span>
              <span class="text-xs text-slate-500">Avg Confidence</span>
            </div>
            <div class="grid grid-cols-2 gap-2 mt-3 pt-3 border-t border-slate-100">
              <div>
                <p class="text-xs text-slate-500">High Conf</p>
                <p class="text-sm font-medium text-emerald-600" data-service-dashboard-target="highConfCount">--</p>
              </div>
              <div>
                <p class="text-xs text-slate-500">Low Conf</p>
                <p class="text-sm font-medium text-rose-600" data-service-dashboard-target="lowConfCount">--</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Pattern Learner Service -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 relative overflow-hidden"
           data-service-dashboard-target="patternLearnerCard">
        <div class="absolute top-0 right-0 w-24 h-24 -mr-8 -mt-8">
          <div class="absolute transform rotate-45 bg-rose-100 opacity-20 rounded-xl w-24 h-24"></div>
        </div>
        <div class="relative">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-sm font-medium text-slate-700">Pattern Learner</h3>
            <span data-service-dashboard-target="patternLearnerStatus" class="w-3 h-3 rounded-full"></span>
          </div>
          <div class="space-y-2">
            <div class="flex justify-between items-baseline">
              <span class="text-2xl font-bold text-slate-900" data-service-dashboard-target="pendingFeedback">--</span>
              <span class="text-xs text-slate-500">Pending</span>
            </div>
            <div class="grid grid-cols-2 gap-2 mt-3 pt-3 border-t border-slate-100">
              <div>
                <p class="text-xs text-slate-500">Learned/day</p>
                <p class="text-sm font-medium text-slate-900" data-service-dashboard-target="learnedToday">--</p>
              </div>
              <div>
                <p class="text-xs text-slate-500">Accuracy Δ</p>
                <p class="text-sm font-medium text-emerald-600" data-service-dashboard-target="accuracyDelta">--</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Circuit Breaker Status -->
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-slate-900">Circuit Breakers</h2>
        <button data-action="click->service-dashboard#resetCircuitBreakers"
                class="text-sm text-teal-700 hover:text-teal-800 font-medium">
          Reset All
        </button>
      </div>
      
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div data-service-dashboard-target="circuitBreakers">
          <!-- Dynamically populated circuit breaker cards -->
        </div>
      </div>
    </div>

    <!-- Performance Metrics Graph -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
      <!-- Response Time Chart -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-slate-900">Response Time Trends</h3>
          <select data-action="change->service-dashboard#updateTimeRange"
                  class="text-sm bg-white border border-slate-300 rounded-lg px-3 py-1">
            <option value="1h">Last Hour</option>
            <option value="6h">Last 6 Hours</option>
            <option value="24h" selected>Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
          </select>
        </div>
        <div class="h-64" data-service-dashboard-target="responseTimeChart">
          <!-- Chart.js canvas will be inserted here -->
        </div>
      </div>

      <!-- Success Rate Chart -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-slate-900">Success Rate Trends</h3>
          <div class="flex items-center gap-3">
            <span class="flex items-center text-sm">
              <span class="w-3 h-3 bg-emerald-500 rounded-full mr-1"></span>
              Success
            </span>
            <span class="flex items-center text-sm">
              <span class="w-3 h-3 bg-rose-500 rounded-full mr-1"></span>
              Failure
            </span>
          </div>
        </div>
        <div class="h-64" data-service-dashboard-target="successRateChart">
          <!-- Chart.js canvas will be inserted here -->
        </div>
      </div>
    </div>

    <!-- Recent Errors and Recovery Actions -->
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-slate-900">Error Recovery Center</h3>
        <div class="flex gap-2">
          <span class="px-2 py-1 bg-rose-100 text-rose-700 text-xs rounded-full font-medium"
                data-service-dashboard-target="errorCount">0 errors</span>
          <button data-action="click->service-dashboard#clearErrors"
                  class="text-sm text-slate-600 hover:text-slate-900">
            Clear Resolved
          </button>
        </div>
      </div>
      
      <div class="space-y-3" data-service-dashboard-target="errorList">
        <!-- Error items will be dynamically inserted here -->
      </div>
    </div>
  </div>
</div>
```

##### Stimulus Controller for Real-time Updates
```javascript
// app/javascript/controllers/service_dashboard_controller.js
import { Controller } from "@hotwired/stimulus"
import { Chart } from "chart.js/auto"

export default class extends Controller {
  static targets = [
    "overallStatus", "statusText", "refreshIcon",
    "patternCacheStatus", "cacheHitRate", "cacheHitRateBar", "cacheEntries", "cacheMemory",
    "fuzzyMatcherStatus", "matcherAvgTime", "matcherRPM", "matcherSuccess",
    "confidenceCalcStatus", "avgConfidence", "highConfCount", "lowConfCount",
    "patternLearnerStatus", "pendingFeedback", "learnedToday", "accuracyDelta",
    "circuitBreakers", "responseTimeChart", "successRateChart",
    "errorList", "errorCount"
  ]
  
  static values = { refreshInterval: Number }
  
  connect() {
    this.initializeCharts()
    this.startPolling()
    this.loadInitialData()
  }
  
  disconnect() {
    this.stopPolling()
    this.destroyCharts()
  }
  
  startPolling() {
    this.pollInterval = setInterval(() => {
      this.refreshData()
    }, this.refreshIntervalValue || 5000)
  }
  
  async refreshData() {
    try {
      const response = await fetch('/api/v1/categorization/service_status', {
        headers: { 'Accept': 'application/json' }
      })
      
      const data = await response.json()
      this.updateDashboard(data)
    } catch (error) {
      console.error('Failed to refresh dashboard:', error)
    }
  }
  
  updateDashboard(data) {
    // Update overall status
    this.updateOverallStatus(data.overall_status)
    
    // Update service cards
    this.updateServiceCard('patternCache', data.services.pattern_cache)
    this.updateServiceCard('fuzzyMatcher', data.services.fuzzy_matcher)
    this.updateServiceCard('confidenceCalc', data.services.confidence_calculator)
    this.updateServiceCard('patternLearner', data.services.pattern_learner)
    
    // Update circuit breakers
    this.updateCircuitBreakers(data.circuit_breakers)
    
    // Update charts
    this.updateCharts(data.metrics)
    
    // Update error list
    this.updateErrorList(data.recent_errors)
  }
  
  updateOverallStatus(status) {
    const statusElement = this.overallStatusTarget
    const textElement = this.statusTextTarget
    
    // Remove all status classes
    statusElement.className = statusElement.className.replace(/bg-\w+-\d+/g, '')
    
    switch(status) {
      case 'healthy':
        statusElement.classList.add('bg-emerald-100', 'text-emerald-700')
        statusElement.querySelector('span').classList.add('bg-emerald-500')
        textElement.textContent = 'All Systems Operational'
        break
      case 'degraded':
        statusElement.classList.add('bg-amber-100', 'text-amber-700')
        statusElement.querySelector('span').classList.add('bg-amber-500')
        textElement.textContent = 'Degraded Performance'
        break
      case 'unhealthy':
        statusElement.classList.add('bg-rose-100', 'text-rose-700')
        statusElement.querySelector('span').classList.add('bg-rose-500')
        textElement.textContent = 'Service Issues Detected'
        break
    }
  }
  
  updateServiceCard(service, data) {
    const statusIndicator = this[`${service}StatusTarget`]
    
    // Update status indicator color
    statusIndicator.className = 'w-3 h-3 rounded-full'
    if (data.healthy) {
      statusIndicator.classList.add('bg-emerald-500')
    } else if (data.degraded) {
      statusIndicator.classList.add('bg-amber-500')
    } else {
      statusIndicator.classList.add('bg-rose-500')
    }
    
    // Update metrics based on service type
    switch(service) {
      case 'patternCache':
        this.cacheHitRateTarget.textContent = `${data.hit_rate}%`
        this.cacheHitRateBarTarget.style.width = `${data.hit_rate}%`
        this.cacheEntriesTarget.textContent = data.entries.toLocaleString()
        this.cacheMemoryTarget.textContent = `${data.memory_mb}MB`
        break
      // ... other service updates
    }
  }
}
```

##### Mobile Responsive Design
```css
/* Tailwind CSS classes for responsive design */
@media (max-width: 768px) {
  /* Stack service cards vertically on mobile */
  .grid-cols-1 { grid-template-columns: repeat(1, minmax(0, 1fr)); }
  
  /* Adjust chart heights for mobile */
  .h-64 { height: 12rem; }
  
  /* Simplify table views on mobile */
  .hidden-mobile { display: none; }
}

@media (min-width: 768px) and (max-width: 1024px) {
  /* 2-column layout for tablets */
  .md\:grid-cols-2 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
```

### User Journey Flows

#### Journey 1: Monitoring Service Health
1. **Entry Point**: Admin navigates to Service Integration Dashboard
2. **Initial View**: Dashboard loads with real-time status indicators
3. **Health Check**: 
   - System automatically polls every 5 seconds
   - Visual indicators update in real-time
   - Color coding: Green (healthy), Amber (degraded), Red (unhealthy)
4. **Drill Down**: Admin clicks on degraded service card
5. **Detailed View**: Modal opens with:
   - Detailed metrics
   - Recent error logs
   - Suggested recovery actions
6. **Recovery Action**: Admin clicks "Reset Service" or "Clear Cache"
7. **Confirmation**: System shows progress and confirms action
8. **Result**: Dashboard updates to reflect new status

#### Journey 2: Troubleshooting Integration Issues
1. **Alert Received**: Admin receives notification of integration failure
2. **Dashboard Access**: Opens Service Integration Dashboard
3. **Error Identification**: 
   - Views Error Recovery Center
   - Sees highlighted failing service
   - Reviews error details and stack trace
4. **Circuit Breaker Status**: Checks if circuit breaker is open
5. **Recovery Steps**:
   - Option A: Reset circuit breaker
   - Option B: Adjust configuration
   - Option C: Restart service
6. **Monitoring**: Watches real-time metrics for improvement
7. **Verification**: Confirms service recovery through status indicators

### Accessibility Requirements

#### WCAG AA Compliance
1. **Color Contrast**:
   - Text contrast ratio: minimum 4.5:1
   - UI component contrast: minimum 3:1
   - Status indicators have text labels, not just color

2. **Keyboard Navigation**:
   ```html
   <!-- All interactive elements are keyboard accessible -->
   <button tabindex="0" 
           role="button"
           aria-label="Run health check for all services"
           aria-describedby="health-check-description">
     Run Health Check
   </button>
   ```

3. **Screen Reader Support**:
   ```html
   <!-- Service status with ARIA live regions -->
   <div aria-live="polite" aria-atomic="true">
     <span class="sr-only">Pattern Cache service status:</span>
     <span data-service-dashboard-target="patternCacheStatus" 
           role="status"
           aria-label="Service is operational">
     </span>
   </div>
   ```

4. **Focus Management**:
   - Clear focus indicators on all interactive elements
   - Focus trap in modals
   - Skip navigation links

### Error Handling and Feedback

#### Error States
```erb
<!-- Connection Error State -->
<div class="bg-rose-50 border border-rose-200 rounded-xl p-4 mb-4" role="alert">
  <div class="flex">
    <svg class="w-5 h-5 text-rose-600 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
    </svg>
    <div class="ml-3">
      <h3 class="text-sm font-medium text-rose-800">Connection Error</h3>
      <p class="text-sm text-rose-700 mt-1">
        Unable to connect to categorization service. Retrying in <span data-countdown="5">5</span> seconds...
      </p>
    </div>
  </div>
</div>
```

#### Loading States
```erb
<!-- Service Card Loading State -->
<div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 animate-pulse">
  <div class="h-4 bg-slate-200 rounded w-3/4 mb-4"></div>
  <div class="h-8 bg-slate-200 rounded w-1/2 mb-2"></div>
  <div class="h-2 bg-slate-200 rounded w-full mb-4"></div>
  <div class="grid grid-cols-2 gap-2">
    <div class="h-4 bg-slate-200 rounded"></div>
    <div class="h-4 bg-slate-200 rounded"></div>
  </div>
</div>
```

#### Success Feedback
```erb
<!-- Action Success Toast -->
<div class="fixed bottom-4 right-4 z-50" data-controller="toast" data-toast-delay-value="3000">
  <div class="bg-emerald-50 border border-emerald-200 rounded-xl p-4 shadow-lg">
    <div class="flex items-center">
      <svg class="w-5 h-5 text-emerald-600" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
      </svg>
      <p class="ml-3 text-sm font-medium text-emerald-800">
        Service successfully restarted
      </p>
    </div>
  </div>
</div>
```

### Performance Optimization

#### Progressive Loading
```javascript
// Lazy load charts only when visible
const chartObserver = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      loadChart(entry.target)
      chartObserver.unobserve(entry.target)
    }
  })
})

// Debounce real-time updates
let updateTimeout
function throttleUpdate(data) {
  clearTimeout(updateTimeout)
  updateTimeout = setTimeout(() => {
    updateDashboard(data)
  }, 100)
}
```

#### Caching Strategy
```javascript
// Cache service status for offline viewing
const CACHE_KEY = 'service_dashboard_status'
const CACHE_DURATION = 60000 // 1 minute

function cacheStatus(data) {
  localStorage.setItem(CACHE_KEY, JSON.stringify({
    data: data,
    timestamp: Date.now()
  }))
}

function getCachedStatus() {
  const cached = localStorage.getItem(CACHE_KEY)
  if (!cached) return null
  
  const { data, timestamp } = JSON.parse(cached)
  if (Date.now() - timestamp > CACHE_DURATION) {
    localStorage.removeItem(CACHE_KEY)
    return null
  }
  
  return data
}
```