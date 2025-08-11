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