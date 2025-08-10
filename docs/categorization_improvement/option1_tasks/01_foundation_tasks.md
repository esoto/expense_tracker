# Option 1: Foundation Tasks - Pattern-Based Categorization

## Phase 1: Foundation Setup (Week 1, Days 1-3)

### Task 1.1: Database Schema Setup
**Priority**: Critical  
**Estimated Hours**: 3  
**Dependencies**: None  

#### Description
Create the database tables and migrations needed for pattern-based categorization.

#### Acceptance Criteria
- [ ] Migration creates `categorization_patterns` table with all required fields
- [ ] Migration creates `pattern_feedbacks` table for learning history
- [ ] Migration creates `composite_patterns` table for complex rules
- [ ] All foreign keys and indexes properly configured
- [ ] Migration runs successfully on test and development databases
- [ ] Rollback tested and works correctly

#### Technical Implementation
```ruby
# db/migrate/[timestamp]_create_categorization_patterns.rb
class CreateCategorizationPatterns < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')
    enable_extension 'unaccent' unless extension_enabled?('unaccent')
    
    create_table :categorization_patterns do |t|
      t.references :category, null: false, foreign_key: true
      t.string :pattern_type, null: false
      t.string :pattern_value, null: false
      t.float :confidence_weight, default: 1.0
      t.integer :usage_count, default: 0
      t.integer :success_count, default: 0
      t.float :success_rate, default: 0.0
      t.json :metadata, default: {}
      t.boolean :active, default: true
      t.timestamps
      
      t.index [:pattern_type, :pattern_value]
      t.index [:category_id, :success_rate]
      t.index :pattern_value, using: :gin, opclass: :gin_trgm_ops
    end
  end
end
```

#### Testing Approach
```ruby
RSpec.describe "Categorization Pattern Migration" do
  it "creates tables with correct schema" do
    expect(ActiveRecord::Base.connection.table_exists?('categorization_patterns')).to be true
    expect(ActiveRecord::Base.connection.index_exists?('categorization_patterns', :pattern_value)).to be true
  end
end
```

---

### Task 1.2: Pattern Model Implementation
**Priority**: Critical  
**Estimated Hours**: 4  
**Dependencies**: Task 1.1  

#### Description
Create ActiveRecord models with validations, associations, and business logic.

#### Acceptance Criteria
- [ ] `CategorizationPattern` model with all validations
- [ ] `PatternFeedback` model for tracking learning
- [ ] Scopes for active patterns, successful patterns
- [ ] Methods for calculating success rates
- [ ] Pattern uniqueness validation
- [ ] 100% test coverage for models

#### Technical Implementation
```ruby
# app/models/categorization_pattern.rb
class CategorizationPattern < ApplicationRecord
  belongs_to :category
  has_many :pattern_feedbacks, dependent: :destroy
  
  PATTERN_TYPES = %w[merchant keyword description amount_range regex].freeze
  
  validates :pattern_type, inclusion: { in: PATTERN_TYPES }
  validates :pattern_value, presence: true, length: { minimum: 2 }
  validates :confidence_weight, numericality: { in: 0..1 }
  validates :pattern_value, uniqueness: { scope: [:pattern_type, :category_id] }
  
  scope :active, -> { where(active: true) }
  scope :successful, -> { where('success_rate > ?', 0.7) }
  scope :by_confidence, -> { order(success_rate: :desc, usage_count: :desc) }
  scope :for_type, ->(type) { where(pattern_type: type) }
  
  def record_usage(was_correct)
    self.usage_count += 1
    self.success_count += 1 if was_correct
    self.success_rate = success_count.to_f / usage_count
    save!
  end
  
  def confidence_score
    return 0.5 if usage_count == 0
    
    # Bayesian average to handle low sample sizes
    prior_weight = 10
    prior_success_rate = 0.5
    
    (success_count + prior_weight * prior_success_rate) / 
    (usage_count + prior_weight)
  end
end
```

---

### Task 1.3: Pattern Cache Service
**Priority**: High  
**Estimated Hours**: 3  
**Dependencies**: Task 1.2  

#### Description
Implement efficient caching layer for pattern lookups with Redis and memory store.

#### Acceptance Criteria
- [ ] Two-tier cache (memory + Redis) implemented
- [ ] Automatic cache warming on startup
- [ ] Cache invalidation on pattern updates
- [ ] Performance: < 1ms for cache hits
- [ ] Monitoring for cache hit rates
- [ ] Configurable TTL values

#### Technical Implementation
```ruby
# app/services/categorization/pattern_cache.rb
class Categorization::PatternCache
  include Singleton
  
  def initialize
    @memory_store = ActiveSupport::Cache::MemoryStore.new(
      size: 50.megabytes,
      expires_in: 5.minutes
    )
    @redis = Redis::Namespace.new('patterns', redis: Redis.current)
    warm_cache
  end
  
  def fetch_patterns(bank_name = nil)
    cache_key = "patterns:#{bank_name || 'all'}:#{Date.current}"
    
    # Try memory first
    @memory_store.fetch(cache_key) do
      # Then Redis
      redis_data = @redis.get(cache_key)
      return JSON.parse(redis_data) if redis_data
      
      # Finally database
      patterns = load_patterns_from_db(bank_name)
      
      # Store in both caches
      @redis.setex(cache_key, 24.hours.to_i, patterns.to_json)
      patterns
    end
  end
  
  def invalidate(pattern_id = nil)
    if pattern_id
      # Selective invalidation
      @memory_store.delete_matched("patterns:*")
      @redis.del(@redis.keys("patterns:*"))
    else
      # Full invalidation
      @memory_store.clear
      @redis.flushdb
    end
  end
  
  private
  
  def warm_cache
    Rails.logger.info "Warming pattern cache..."
    fetch_patterns # Load all patterns
    Rails.logger.info "Pattern cache warmed with #{@memory_store.stats[:entries]} entries"
  end
end
```

---

### Task 1.4: Fuzzy Matching Implementation
**Priority**: High  
**Estimated Hours**: 5  
**Dependencies**: Task 1.3  

#### Description
Implement fuzzy string matching algorithms for merchant name variations.

#### Acceptance Criteria
- [ ] Jaro-Winkler distance implementation
- [ ] Levenshtein distance as fallback
- [ ] Trigram similarity using PostgreSQL
- [ ] Configurable similarity thresholds
- [ ] Performance: < 10ms per match
- [ ] Handle Spanish and English text

#### Technical Implementation
```ruby
# app/services/categorization/matchers/fuzzy_matcher.rb
class Categorization::Matchers::FuzzyMatcher
  def initialize(threshold: 0.8)
    @threshold = threshold
    @jaro = FuzzyStringMatch::JaroWinkler.create(:pure)
  end
  
  def find_best_match(text, patterns)
    normalized_text = normalize(text)
    
    matches = patterns.map do |pattern|
      score = calculate_similarity(normalized_text, pattern.pattern_value)
      { pattern: pattern, score: score }
    end
    
    best_match = matches.max_by { |m| m[:score] }
    
    return nil if best_match[:score] < @threshold
    
    MatchResult.new(
      pattern: best_match[:pattern],
      confidence: best_match[:score],
      match_type: determine_match_type(best_match[:score])
    )
  end
  
  private
  
  def normalize(text)
    text.downcase
        .gsub(/[^\w\s]/, ' ')  # Remove special chars
        .gsub(/\b\d{4,}\b/, '') # Remove long numbers
        .strip
        .squeeze(' ')
  end
  
  def calculate_similarity(text1, text2)
    # Try exact match first
    return 1.0 if text1 == text2
    
    # Jaro-Winkler for close matches
    jw_score = @jaro.getDistance(text1, text2)
    
    # Trigram similarity as secondary measure
    trgm_score = trigram_similarity(text1, text2)
    
    # Weighted average
    (jw_score * 0.7 + trgm_score * 0.3)
  end
  
  def trigram_similarity(text1, text2)
    trgm1 = text1.chars.each_cons(3).map(&:join).to_set
    trgm2 = text2.chars.each_cons(3).map(&:join).to_set
    
    intersection = (trgm1 & trgm2).size
    union = (trgm1 | trgm2).size
    
    return 0.0 if union.zero?
    intersection.to_f / union
  end
end
```

---

### Task 1.5: Confidence Calculator
**Priority**: High  
**Estimated Hours**: 4  
**Dependencies**: Task 1.4  

#### Description
Build sophisticated confidence scoring system combining multiple signals.

#### Acceptance Criteria
- [ ] Multi-factor confidence calculation
- [ ] Configurable weight factors
- [ ] Score normalization (0.0 to 1.0)
- [ ] Explainable scores (breakdown by factor)
- [ ] Handle missing factors gracefully
- [ ] Performance tracking per factor

#### Technical Implementation
```ruby
# app/services/categorization/confidence_calculator.rb
class Categorization::ConfidenceCalculator
  attr_reader :breakdown
  
  FACTORS = {
    text_match: { weight: 0.35, required: true },
    historical_success: { weight: 0.25, required: false },
    usage_frequency: { weight: 0.15, required: false },
    amount_similarity: { weight: 0.15, required: false },
    temporal_pattern: { weight: 0.10, required: false }
  }.freeze
  
  def calculate(expense, pattern, match_result)
    @breakdown = {}
    scores = {}
    
    # Text matching score (required)
    scores[:text_match] = match_result.score
    
    # Historical performance
    if pattern.usage_count > 5
      scores[:historical_success] = pattern.success_rate
    end
    
    # Usage frequency (popular patterns more reliable)
    if pattern.usage_count > 0
      scores[:usage_frequency] = Math.log10(pattern.usage_count + 1) / 4.0
    end
    
    # Amount similarity
    if pattern.metadata['typical_amount']
      scores[:amount_similarity] = calculate_amount_similarity(
        expense.amount,
        pattern.metadata['typical_amount']
      )
    end
    
    # Temporal patterns (day of week, time of day)
    if pattern.metadata['temporal_pattern']
      scores[:temporal_pattern] = calculate_temporal_similarity(
        expense.transaction_date,
        pattern.metadata['temporal_pattern']
      )
    end
    
    # Calculate weighted average
    total_weight = 0
    weighted_sum = 0
    
    scores.each do |factor, score|
      weight = FACTORS[factor][:weight]
      total_weight += weight
      weighted_sum += score * weight
      @breakdown[factor] = { score: score, weight: weight }
    end
    
    final_score = weighted_sum / total_weight
    
    # Apply sigmoid for smoother distribution
    normalize_score(final_score)
  end
  
  private
  
  def normalize_score(raw_score)
    # Sigmoid function to push scores toward 0 or 1
    1.0 / (1.0 + Math.exp(-10 * (raw_score - 0.5)))
  end
  
  def calculate_amount_similarity(actual, expected)
    return 0 if expected.zero?
    
    # Use log scale for amounts
    log_actual = Math.log10(actual + 1)
    log_expected = Math.log10(expected + 1)
    
    difference = (log_actual - log_expected).abs
    
    # Convert to similarity score
    Math.exp(-difference)
  end
end
```

---

### Task 1.6: Pattern Learning Service
**Priority**: Critical  
**Estimated Hours**: 6  
**Dependencies**: Tasks 1.2, 1.5  

#### Description
Implement service that learns from user corrections and creates new patterns.

#### Acceptance Criteria
- [ ] Learn from manual categorizations
- [ ] Update pattern confidence based on feedback
- [ ] Create new patterns from repeated corrections
- [ ] Merge similar patterns automatically
- [ ] Decay unused patterns over time
- [ ] Batch learning for performance

#### Technical Implementation
```ruby
# app/services/categorization/pattern_learner.rb
class Categorization::PatternLearner
  def learn_from_correction(expense, correct_category, predicted_category = nil)
    ActiveRecord::Base.transaction do
      # Record feedback for existing patterns
      if predicted_category
        record_negative_feedback(expense, predicted_category)
      end
      
      # Learn new pattern
      create_or_strengthen_pattern(expense, correct_category)
      
      # Update pattern statistics
      update_pattern_stats
      
      # Check for pattern merging opportunities
      merge_similar_patterns(correct_category)
    end
  end
  
  def batch_learn(corrections)
    ActiveRecord::Base.transaction do
      corrections.each do |correction|
        learn_from_correction(
          correction[:expense],
          correction[:correct_category],
          correction[:predicted_category]
        )
      end
      
      # Optimize patterns after batch
      optimize_all_patterns
    end
  end
  
  private
  
  def create_or_strengthen_pattern(expense, category)
    # Try to find existing pattern
    pattern = find_or_create_pattern(expense, category)
    
    # Update pattern strength
    pattern.record_usage(true)
    
    # Update metadata with new information
    update_pattern_metadata(pattern, expense)
  end
  
  def find_or_create_pattern(expense, category)
    # Check if merchant pattern exists
    if expense.merchant_name.present?
      pattern = CategorizationPattern.find_or_initialize_by(
        pattern_type: 'merchant',
        pattern_value: normalize_merchant(expense.merchant_name),
        category: category
      )
      
      return pattern if pattern.persisted?
    end
    
    # Create keyword patterns from description
    create_keyword_patterns(expense, category)
  end
  
  def optimize_all_patterns
    # Remove low-performing patterns
    CategorizationPattern
      .where('usage_count > 10 AND success_rate < 0.3')
      .update_all(active: false)
    
    # Decay unused patterns
    CategorizationPattern
      .where('updated_at < ?', 30.days.ago)
      .update_all('confidence_weight = confidence_weight * 0.9')
  end
end
```

---

## Testing Requirements

### Unit Test Coverage
```ruby
# spec/services/categorization/pattern_engine_spec.rb
RSpec.describe Categorization::PatternEngine do
  describe "pattern matching" do
    let(:engine) { described_class.new }
    
    context "with exact matches" do
      # Test exact merchant name matches
    end
    
    context "with fuzzy matches" do
      # Test variations and typos
    end
    
    context "with composite patterns" do
      # Test multiple condition patterns
    end
    
    context "confidence calculation" do
      # Test confidence scoring accuracy
    end
  end
end
```

### Performance Benchmarks
```ruby
# spec/benchmarks/pattern_performance_spec.rb
require 'benchmark'

RSpec.describe "Pattern Engine Performance" do
  it "categorizes 1000 expenses in under 1 second" do
    expenses = create_list(:expense, 1000)
    engine = Categorization::PatternEngine.new
    
    time = Benchmark.realtime do
      expenses.each { |e| engine.categorize(e) }
    end
    
    expect(time).to be < 1.0
  end
end
```

### Integration Tests
```ruby
# spec/integration/pattern_learning_spec.rb
RSpec.describe "Pattern Learning Integration" do
  it "improves accuracy with corrections" do
    # Create test data
    # Make predictions
    # Apply corrections
    # Test improved accuracy
  end
end
```

---

## Deployment Checklist

- [ ] Database migrations tested
- [ ] Pattern cache warmed
- [ ] Feature flags configured
- [ ] Monitoring dashboards set up
- [ ] Performance benchmarks passing
- [ ] Documentation updated
- [ ] Team trained on pattern management

---

## Next Phase: Core Implementation
After foundation tasks are complete, proceed to:
- Pattern UI implementation
- API endpoint creation
- Bulk operations
- Advanced pattern types