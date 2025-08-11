### Task 1.7.2: Service Integration and Orchestration
**Priority**: HIGH  
**Estimated Hours**: 6  
**Dependencies**: Task 1.7.1  

#### Description
Create main orchestrator service that properly integrates PatternCache, FuzzyMatcher, ConfidenceCalculator, and PatternLearner into a cohesive categorization engine.

#### Acceptance Criteria
- [ ] Main orchestrator service created (`Categorization::Engine`)
- [ ] Clear service boundaries and interfaces defined
- [ ] Service dependencies properly injected
- [ ] Integration points documented with sequence diagrams
- [ ] Error handling cascades properly between services
- [ ] Performance maintained at <10ms per categorization
- [ ] Integration tests cover all service interactions

#### Technical Implementation

##### Main Orchestrator Service
```ruby
# app/services/categorization/engine.rb
module Categorization
  class Engine
    include Singleton
    
    attr_reader :cache, :matcher, :calculator, :learner
    
    def initialize
      @cache = PatternCache.instance
      @matcher = Matchers::FuzzyMatcher.new
      @calculator = ConfidenceCalculator.new
      @learner = PatternLearner.new
      @performance_tracker = PerformanceTracker.new
    end
    
    def categorize(expense, options = {})
      @performance_tracker.track("categorization") do
        # Step 1: Fetch relevant patterns from cache
        patterns = fetch_patterns(expense)
        
        # Step 2: Find matching patterns using fuzzy matcher
        matches = find_matches(expense, patterns)
        
        # Step 3: Calculate confidence scores
        scored_matches = calculate_confidences(expense, matches)
        
        # Step 4: Select best category
        result = select_best_category(scored_matches)
        
        # Step 5: Record for learning (async if configured)
        record_categorization(expense, result) if options[:track_usage]
        
        result
      end
    rescue StandardError => e
      handle_categorization_error(e, expense)
    end
    
    def learn_from_correction(expense, correct_category, predicted_category = nil)
      @learner.learn_from_correction(expense, correct_category, predicted_category)
      @cache.invalidate_for_category(correct_category.id)
    end
    
    def batch_categorize(expenses, options = {})
      ActiveRecord::Base.transaction do
        expenses.map { |expense| categorize(expense, options) }
      end
    end
    
    private
    
    def fetch_patterns(expense)
      bank_name = extract_bank_name(expense)
      @cache.fetch_patterns(bank_name)
    end
    
    def find_matches(expense, patterns)
      text = build_search_text(expense)
      
      # Try different pattern types
      merchant_matches = @matcher.match_merchant(
        expense.merchant_name, 
        patterns.select { |p| p.pattern_type == 'merchant' }
      ) if expense.merchant_name.present?
      
      keyword_matches = @matcher.match_pattern(
        expense.description,
        patterns.select { |p| p.pattern_type == 'keyword' }
      )
      
      # Combine and deduplicate matches
      all_matches = [merchant_matches, keyword_matches].compact.flatten
      all_matches.uniq { |m| m[:pattern].id }
    end
    
    def calculate_confidences(expense, matches)
      matches.map do |match|
        confidence = @calculator.calculate(expense, match[:pattern], match)
        {
          category: match[:pattern].category,
          confidence: confidence,
          pattern: match[:pattern],
          breakdown: @calculator.breakdown
        }
      end
    end
    
    def select_best_category(scored_matches)
      return nil if scored_matches.empty?
      
      # Group by category and take highest confidence per category
      by_category = scored_matches.group_by { |m| m[:category] }
      
      best_per_category = by_category.map do |category, matches|
        best = matches.max_by { |m| m[:confidence] }
        {
          category: category,
          confidence: best[:confidence],
          patterns: matches.map { |m| m[:pattern] },
          breakdown: best[:breakdown]
        }
      end
      
      # Return highest confidence category
      result = best_per_category.max_by { |m| m[:confidence] }
      
      CategorizationResult.new(
        category: result[:category],
        confidence: result[:confidence],
        patterns_used: result[:patterns],
        confidence_breakdown: result[:breakdown]
      )
    end
    
    def handle_categorization_error(error, expense)
      Rails.logger.error "Categorization failed for expense #{expense.id}: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      # Return nil result with error information
      CategorizationResult.new(
        category: nil,
        confidence: 0.0,
        error: error.message
      )
    end
  end
  
  # Value object for categorization results
  class CategorizationResult
    attr_reader :category, :confidence, :patterns_used, :confidence_breakdown, :error
    
    def initialize(category:, confidence:, patterns_used: [], confidence_breakdown: {}, error: nil)
      @category = category
      @confidence = confidence
      @patterns_used = patterns_used
      @confidence_breakdown = confidence_breakdown
      @error = error
    end
    
    def successful?
      @category.present? && @error.nil?
    end
    
    def high_confidence?
      @confidence >= 0.8
    end
    
    def to_h
      {
        category_id: @category&.id,
        category_name: @category&.name,
        confidence: @confidence,
        patterns_used: @patterns_used.map(&:id),
        breakdown: @confidence_breakdown,
        error: @error
      }
    end
  end
end
```

##### Service Wiring Documentation
```yaml
# docs/categorization_improvement/service_architecture.yml
services:
  engine:
    class: Categorization::Engine
    role: Main orchestrator
    dependencies:
      - pattern_cache
      - fuzzy_matcher
      - confidence_calculator
      - pattern_learner
    
  pattern_cache:
    class: Categorization::PatternCache
    role: Pattern storage and retrieval
    dependencies:
      - redis
      - memory_store
    
  fuzzy_matcher:
    class: Categorization::Matchers::FuzzyMatcher
    role: Text similarity matching
    dependencies: []
    
  confidence_calculator:
    class: Categorization::ConfidenceCalculator
    role: Confidence scoring
    dependencies: []
    
  pattern_learner:
    class: Categorization::PatternLearner
    role: Machine learning from feedback
    dependencies:
      - pattern_cache

sequence_diagram: |
  User -> Engine: categorize(expense)
  Engine -> PatternCache: fetch_patterns
  PatternCache -> Redis: get cached patterns
  PatternCache --> Engine: patterns
  Engine -> FuzzyMatcher: find matches
  FuzzyMatcher --> Engine: match results
  Engine -> ConfidenceCalculator: calculate scores
  ConfidenceCalculator --> Engine: scored matches
  Engine -> PatternLearner: record usage (async)
  Engine --> User: CategorizationResult
```

#### Integration Tests
```ruby
# spec/services/categorization/engine_integration_spec.rb
RSpec.describe Categorization::Engine, type: :integration do
  let(:engine) { described_class.instance }
  
  describe "full categorization flow" do
    let!(:category) { create(:category, name: "Food & Dining") }
    let!(:pattern) { create(:categorization_pattern, 
      category: category,
      pattern_type: 'merchant',
      pattern_value: 'starbucks',
      confidence_weight: 0.9
    )}
    
    it "categorizes expense using all services" do
      expense = create(:expense, 
        description: "STARBUCKS COFFEE",
        merchant_name: "Starbucks"
      )
      
      result = engine.categorize(expense)
      
      expect(result).to be_successful
      expect(result.category).to eq(category)
      expect(result.confidence).to be > 0.7
      expect(result.patterns_used).to include(pattern)
    end
    
    it "handles learning from corrections" do
      expense = create(:expense, description: "NEW MERCHANT")
      correct_category = create(:category, name: "Shopping")
      
      # Learn from correction
      engine.learn_from_correction(expense, correct_category)
      
      # Should categorize similar expense
      similar_expense = create(:expense, description: "NEW MERCHANT STORE")
      result = engine.categorize(similar_expense)
      
      expect(result.category).to eq(correct_category)
    end
    
    it "maintains performance targets" do
      expenses = create_list(:expense, 100)
      
      time = Benchmark.realtime do
        expenses.each { |e| engine.categorize(e) }
      end
      
      expect(time / 100).to be < 0.010  # <10ms per expense
    end
  end
end
```
