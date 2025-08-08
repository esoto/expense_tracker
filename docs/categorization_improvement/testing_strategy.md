# Testing Strategy - Categorization Improvement System

## Overview

This document outlines the comprehensive testing strategy for all three categorization improvement options, ensuring quality, performance, and reliability.

## Testing Pyramid

```
                    E2E Tests
                   /         \
                  /   (5%)    \
                 /-----------\
                /             \
               / Integration   \
              /     Tests      \
             /      (25%)       \
            /-------------------\
           /                     \
          /     Unit Tests        \
         /        (70%)           \
        /-------------------------\
```

## Test Coverage Goals

- **Overall Coverage**: 95%+
- **Unit Tests**: 100% for critical paths
- **Integration Tests**: All service interactions
- **E2E Tests**: Critical user workflows
- **Performance Tests**: All categorization paths

## Option 1: Quick Intelligence Testing

### Unit Tests

```ruby
# spec/services/categorization/quick_intelligence_spec.rb
require 'rails_helper'

RSpec.describe Categorization::QuickIntelligence do
  let(:service) { described_class.new }
  
  describe '#categorize' do
    context 'with exact merchant match' do
      let(:expense) { build(:expense, merchant_name: 'WALMART #1234') }
      
      before do
        create(:canonical_merchant, name: 'walmart')
        create(:merchant_alias, 
          raw_name: 'WALMART #1234',
          normalized_name: 'walmart'
        )
      end
      
      it 'returns correct category with high confidence' do
        result = service.categorize(expense)
        
        expect(result[:category]).to eq(shopping_category)
        expect(result[:confidence]).to be > 0.85
      end
      
      it 'normalizes merchant name' do
        service.categorize(expense)
        expect(expense.merchant_normalized).to eq('walmart')
      end
    end
    
    context 'with fuzzy merchant match' do
      let(:expense) { build(:expense, merchant_name: 'WAL-MART SUPERCENTER') }
      
      it 'finds similar merchant' do
        create(:merchant_alias, normalized_name: 'walmart')
        
        result = service.categorize(expense)
        expect(result[:category]).not_to be_nil
      end
    end
    
    context 'with pattern detection' do
      it 'detects morning coffee pattern' do
        expense = build(:expense,
          merchant_name: 'STARBUCKS',
          amount: 5.50,
          transaction_date: monday_at_8am
        )
        
        result = service.categorize(expense)
        
        expect(result[:patterns_detected][:is_morning_coffee]).to be true
        expect(result[:category]).to eq(food_category)
      end
      
      it 'detects recurring patterns' do
        merchant = 'NETFLIX'
        create_list(:expense, 3,
          merchant_name: merchant,
          amount: 15.99,
          transaction_date: 30.days.ago
        )
        
        expense = build(:expense, merchant_name: merchant, amount: 15.99)
        result = service.categorize(expense)
        
        expect(result[:patterns_detected][:is_recurring]).to be true
      end
    end
    
    context 'with learning from corrections' do
      it 'creates new pattern from correction' do
        expense = create(:expense)
        
        expect {
          service.learn_from_correction(expense, food_category)
        }.to change(CategoryPattern, :count).by_at_least(1)
      end
      
      it 'updates pattern success rates' do
        pattern = create(:category_pattern,
          success_count: 10,
          failure_count: 2
        )
        
        expense = create(:expense)
        service.learn_from_correction(expense, pattern.category)
        
        pattern.reload
        expect(pattern.success_count).to eq(11)
      end
    end
  end
  
  describe 'MerchantIntelligence' do
    let(:merchant_intel) { MerchantIntelligence.new }
    
    it 'normalizes merchant variations' do
      variations = [
        'WALMART #1234',
        'WAL-MART SUPERCENTER',
        'WMT*WALMART',
        'Walmart.com'
      ]
      
      normalized = variations.map { |v| 
        merchant_intel.normalize(v) 
      }.uniq
      
      expect(normalized.size).to eq(1)
      expect(normalized.first).to eq('walmart')
    end
    
    it 'handles special characters' do
      merchant = 'COMPRA*EN*TIENDA*CR'
      normalized = merchant_intel.normalize(merchant)
      
      expect(normalized).not_to include('*')
    end
  end
end

# spec/services/categorization/pattern_learner_spec.rb
RSpec.describe Categorization::PatternLearner do
  let(:learner) { described_class.new }
  
  describe '#learn' do
    let(:expense) { create(:expense, merchant_normalized: 'amazon') }
    let(:category) { create(:category, name: 'Shopping') }
    
    it 'creates merchant pattern' do
      expect {
        learner.learn(expense, category)
      }.to change { 
        CategoryPattern.where(
          pattern_type: 'merchant',
          pattern_value: 'amazon'
        ).count 
      }.by(1)
    end
    
    it 'extracts keyword patterns' do
      expense.update(description: 'Online shopping purchase')
      
      learner.learn(expense, category)
      
      keywords = CategoryPattern.where(pattern_type: 'keyword')
      expect(keywords.pluck(:pattern_value)).to include('shopping', 'online')
    end
    
    it 'creates amount range patterns' do
      create_list(:expense, 10, 
        category: category,
        amount: 50..150
      )
      
      learner.learn(expense, category)
      
      amount_pattern = CategoryPattern.find_by(pattern_type: 'amount')
      expect(amount_pattern).not_to be_nil
    end
  end
end
```

### Integration Tests

```ruby
# spec/integration/option1_integration_spec.rb
require 'rails_helper'

RSpec.describe 'Option 1 Integration' do
  describe 'Complete categorization flow' do
    it 'categorizes expense through full pipeline' do
      # Setup
      expense = create(:expense, 
        merchant_name: 'UBER EATS MCDONALDS',
        amount: 25.43
      )
      
      # Create patterns
      create(:category_pattern,
        category: food_category,
        pattern_type: 'keyword',
        pattern_value: 'eats'
      )
      
      # Execute
      result = Categorization::QuickIntelligence.new.categorize(expense)
      
      # Verify
      expect(result[:category]).to eq(food_category)
      expect(result[:confidence]).to be > 0.7
      expect(expense.reload.merchant_normalized).not_to be_nil
    end
    
    it 'learns from user corrections' do
      expense = create(:expense, merchant_name: 'NEW STORE')
      service = Categorization::QuickIntelligence.new
      
      # Initial categorization
      initial_result = service.categorize(expense)
      initial_confidence = initial_result[:confidence]
      
      # User correction
      service.learn_from_correction(expense, shopping_category)
      
      # Next similar expense
      similar_expense = create(:expense, merchant_name: 'NEW STORE')
      new_result = service.categorize(similar_expense)
      
      # Should improve
      expect(new_result[:category]).to eq(shopping_category)
      expect(new_result[:confidence]).to be > initial_confidence
    end
  end
end
```

## Option 2: Statistical Learning Testing

### Unit Tests

```ruby
# spec/services/ml/naive_bayes_classifier_spec.rb
require 'rails_helper'

RSpec.describe ML::NaiveBayesClassifier do
  let(:classifier) { described_class.new }
  
  describe '#train' do
    let(:training_data) { create_list(:expense, 100, :categorized) }
    
    it 'trains model successfully' do
      expect { classifier.train(training_data) }.not_to raise_error
      
      expect(classifier.model[:accuracy]).to be > 0
      expect(classifier.model[:priors]).not_to be_empty
    end
    
    it 'achieves minimum accuracy' do
      classifier.train(training_data)
      
      test_data = create_list(:expense, 20, :categorized)
      correct = 0
      
      test_data.each do |expense|
        prediction = classifier.predict(expense)
        correct += 1 if prediction[:category] == expense.category
      end
      
      accuracy = correct.to_f / test_data.size
      expect(accuracy).to be > 0.70
    end
    
    it 'handles imbalanced data' do
      # Create imbalanced dataset
      dominant = create(:category)
      rare = create(:category)
      
      create_list(:expense, 90, category: dominant)
      create_list(:expense, 10, category: rare)
      
      classifier.train(Expense.all)
      
      # Should still predict rare category
      rare_expense = build(:expense, :with_features_for, rare)
      prediction = classifier.predict(rare_expense)
      
      alternatives = prediction[:alternatives].map { |a| a[:category] }
      expect(alternatives).to include(rare)
    end
  end
  
  describe '#predict' do
    before { classifier.train(create_list(:expense, 50, :categorized)) }
    
    it 'returns prediction with confidence' do
      expense = create(:expense)
      prediction = classifier.predict(expense)
      
      expect(prediction).to include(
        :category,
        :confidence,
        :alternatives,
        :method
      )
      
      expect(prediction[:confidence]).to be_between(0, 1)
      expect(prediction[:method]).to eq('naive_bayes')
    end
    
    it 'provides alternatives' do
      expense = create(:expense)
      prediction = classifier.predict(expense)
      
      expect(prediction[:alternatives]).to be_an(Array)
      expect(prediction[:alternatives].size).to be <= 3
    end
  end
  
  describe '#update_online' do
    before { classifier.train(create_list(:expense, 50, :categorized)) }
    
    it 'improves with corrections' do
      expense = create(:expense, merchant_normalized: 'teststore')
      
      # Initial prediction
      initial = classifier.predict(expense)
      
      # Correct multiple times
      5.times do
        similar = create(:expense, merchant_normalized: 'teststore')
        classifier.update_online(similar, shopping_category)
      end
      
      # Should improve
      final = classifier.predict(expense)
      expect(final[:confidence]).to be > initial[:confidence]
    end
  end
end

# spec/services/ml/feature_extractor_spec.rb
RSpec.describe ML::FeatureExtractor do
  let(:extractor) { described_class.new }
  let(:expense) { create(:expense) }
  
  describe '#extract_features' do
    it 'extracts all feature categories' do
      features = extractor.extract_features(expense)
      
      expect(features).to include(
        :text_features,
        :numerical_features,
        :temporal_features,
        :historical_features
      )
    end
    
    it 'generates consistent features' do
      features1 = extractor.extract_features(expense)
      features2 = extractor.extract_features(expense)
      
      expect(features1).to eq(features2)
    end
    
    it 'handles missing data gracefully' do
      expense = build(:expense, 
        merchant_name: nil,
        description: nil
      )
      
      expect { extractor.extract_features(expense) }.not_to raise_error
    end
  end
  
  describe 'feature scaling' do
    let(:scaler) { ML::FeatureScaler.new }
    
    it 'normalizes features to 0-1 range' do
      features = { amount: 100, day_of_week: 3, confidence: 0.8 }
      scaled = scaler.transform(features)
      
      scaled.values.each do |value|
        expect(value).to be_between(0, 1)
      end
    end
  end
end
```

### Performance Tests

```ruby
# spec/performance/ml_performance_spec.rb
require 'rails_helper'
require 'benchmark'

RSpec.describe 'ML Performance' do
  let(:ensemble) { ML::EnsembleClassifier.new }
  
  describe 'training performance' do
    it 'trains on 1000 samples in under 30 seconds' do
      training_data = create_list(:expense, 1000, :categorized)
      
      time = Benchmark.realtime do
        ensemble.train(training_data)
      end
      
      expect(time).to be < 30
    end
  end
  
  describe 'prediction performance' do
    before do
      training_data = create_list(:expense, 500, :categorized)
      ensemble.train(training_data)
    end
    
    it 'predicts 100 expenses per second' do
      expenses = create_list(:expense, 100)
      
      time = Benchmark.realtime do
        expenses.each { |e| ensemble.predict(e) }
      end
      
      expect(time).to be < 1
    end
    
    it 'batch prediction is faster than individual' do
      expenses = create_list(:expense, 100)
      
      individual_time = Benchmark.realtime do
        expenses.each { |e| ensemble.predict(e) }
      end
      
      batch_time = Benchmark.realtime do
        ML::BatchPredictor.new.predict_batch(expenses)
      end
      
      expect(batch_time).to be < (individual_time * 0.5)
    end
  end
  
  describe 'memory usage' do
    it 'maintains stable memory with large datasets' do
      require 'get_process_mem'
      
      initial_memory = GetProcessMem.new.mb
      
      # Process large dataset
      1000.times do
        expense = create(:expense)
        ensemble.predict(expense)
      end
      
      final_memory = GetProcessMem.new.mb
      memory_increase = final_memory - initial_memory
      
      expect(memory_increase).to be < 100  # MB
    end
  end
end
```

## Option 3: Hybrid AI Testing

### Unit Tests

```ruby
# spec/services/ai/intelligent_router_spec.rb
require 'rails_helper'

RSpec.describe AI::IntelligentRouter do
  let(:router) { described_class.new }
  
  describe '#categorize' do
    context 'routing decisions' do
      it 'uses cache for identical expense' do
        expense = create(:expense)
        
        # First call
        result1 = router.categorize(expense)
        
        # Second call should hit cache
        expect_any_instance_of(AI::CacheLayer)
          .to receive(:check)
          .and_return(result1)
        
        result2 = router.categorize(expense)
        expect(result2[:route]).to eq('cache')
      end
      
      it 'uses vector search for similar expenses' do
        original = create(:expense, :categorized)
        similar = create(:expense,
          merchant_normalized: original.merchant_normalized,
          amount: original.amount * 1.05
        )
        
        allow_any_instance_of(AI::VectorSearchLayer)
          .to receive(:find_similar)
          .and_return([{ 
            category: original.category,
            confidence: 0.95 
          }])
        
        result = router.categorize(similar)
        expect(result[:route]).to eq('vector')
      end
      
      it 'uses ML for moderate complexity' do
        expense = create(:expense)
        
        allow_any_instance_of(AI::ComplexityAnalyzer)
          .to receive(:analyze)
          .and_return({ score: 0.5, factors: {} })
        
        result = router.categorize(expense)
        expect(result[:route]).to include('ml')
      end
      
      it 'uses LLM for high complexity when budget allows' do
        expense = create(:expense,
          merchant_name: 'CRYPTIC*XYZ*123',
          amount: 1500
        )
        
        allow_any_instance_of(AI::CostTracker)
          .to receive(:within_budget?)
          .and_return(true)
        
        allow_any_instance_of(AI::ComplexityAnalyzer)
          .to receive(:analyze)
          .and_return({ score: 0.9, factors: {} })
        
        allow_any_instance_of(AI::LLMLayer)
          .to receive(:categorize)
          .and_return({ 
            category: food_category,
            confidence: 0.95,
            cost: 0.001
          })
        
        result = router.categorize(expense)
        expect(result[:route]).to eq('llm')
      end
      
      it 'falls back when LLM unavailable' do
        expense = create(:expense)
        
        allow_any_instance_of(AI::CostTracker)
          .to receive(:within_budget?)
          .and_return(false)
        
        result = router.categorize(expense)
        expect(result[:route]).not_to eq('llm')
      end
    end
  end
  
  describe 'AI::ComplexityAnalyzer' do
    let(:analyzer) { AI::ComplexityAnalyzer.new }
    
    it 'calculates complexity score' do
      expense = create(:expense)
      complexity = analyzer.analyze(expense, nil)
      
      expect(complexity[:score]).to be_between(0, 1)
      expect(complexity[:factors]).to be_a(Hash)
    end
    
    it 'identifies high complexity' do
      expense = create(:expense,
        merchant_name: nil,
        description: 'Complex transaction with multiple items'
      )
      
      complexity = analyzer.analyze(expense, nil)
      expect(complexity[:score]).to be > 0.7
    end
  end
  
  describe 'AI::CostTracker' do
    let(:tracker) { AI::CostTracker.new }
    
    it 'tracks daily costs' do
      tracker.track(0.10)
      tracker.track(0.20)
      
      expect(tracker.daily_spent).to eq(0.30)
    end
    
    it 'enforces budget limits' do
      # Simulate reaching limit
      allow(tracker).to receive(:daily_spent).and_return(4.99)
      
      expect(tracker.within_budget?).to be true
      
      tracker.track(0.02)
      
      expect(tracker.within_budget?).to be false
    end
  end
end

# spec/services/ai/embedding_service_spec.rb
RSpec.describe AI::EmbeddingService do
  let(:service) { described_class.new }
  
  describe '#generate_embedding' do
    let(:expense) { create(:expense) }
    
    it 'generates embedding vector' do
      embedding = service.generate_embedding(expense)
      
      expect(embedding).to be_an(Array)
      expect(embedding.size).to eq(384)
      expect(embedding.all? { |v| v.is_a?(Float) }).to be true
    end
    
    it 'generates consistent embeddings' do
      embedding1 = service.generate_embedding(expense)
      embedding2 = service.generate_embedding(expense)
      
      expect(embedding1).to eq(embedding2)
    end
    
    it 'stores embedding in database' do
      service.generate_embedding(expense)
      
      expense.reload
      expect(expense.embedding).not_to be_nil
    end
  end
  
  describe '#batch_generate' do
    let(:expenses) { create_list(:expense, 10) }
    
    it 'generates embeddings for multiple expenses' do
      service.batch_generate(expenses)
      
      expenses.each do |expense|
        expense.reload
        expect(expense.embedding).not_to be_nil
      end
    end
  end
end
```

### Integration Tests

```ruby
# spec/integration/ai_integration_spec.rb
require 'rails_helper'

RSpec.describe 'AI System Integration' do
  describe 'complete AI flow' do
    it 'routes through all layers appropriately' do
      # Simple expense - should use cache/ML
      simple = create(:expense, merchant_name: 'WALMART')
      result = AI::IntelligentRouter.new.categorize(simple)
      expect(['cache', 'vector', 'ml']).to include(result[:route])
      
      # Complex expense - might use LLM
      complex = create(:expense,
        merchant_name: 'XYZ*CRYPTIC*123',
        amount: 999.99
      )
      
      allow_any_instance_of(AI::CostTracker)
        .to receive(:within_budget?)
        .and_return(true)
      
      result = AI::IntelligentRouter.new.categorize(complex)
      expect(result[:confidence]).to be > 0.6
    end
    
    it 'learns from corrections' do
      expense = create(:expense)
      router = AI::IntelligentRouter.new
      
      # Initial categorization
      initial = router.categorize(expense)
      
      # Correction
      learner = AI::ContinuousLearningPipeline.new
      learner.process_feedback(
        expense,
        initial[:category],
        food_category
      )
      
      # Similar expense should improve
      similar = create(:expense,
        merchant_normalized: expense.merchant_normalized
      )
      
      new_result = router.categorize(similar)
      expect(new_result[:category]).to eq(food_category)
    end
  end
  
  describe 'cost management' do
    it 'stays within daily budget' do
      tracker = AI::CostTracker.new
      router = AI::IntelligentRouter.new
      
      100.times do
        expense = create(:expense)
        router.categorize(expense)
      end
      
      expect(tracker.daily_spent).to be <= 5.00
    end
  end
  
  describe 'privacy protection' do
    it 'anonymizes data for LLM' do
      expense = create(:expense,
        merchant_name: 'STORE 1234567890',
        description: 'Payment from john@example.com'
      )
      
      anonymizer = AI::DataAnonymizer.new
      anonymized = anonymizer.anonymize_for_llm(expense)
      
      expect(anonymized[:merchant]).not_to include('1234567890')
      expect(anonymized[:description]).not_to include('john@example.com')
    end
  end
end
```

## E2E Tests

```ruby
# spec/e2e/categorization_e2e_spec.rb
require 'rails_helper'

RSpec.describe 'Categorization E2E', type: :system do
  describe 'Manual categorization' do
    it 'allows user to categorize with keyboard shortcuts' do
      expense = create(:expense, :uncategorized)
      
      visit expenses_path
      
      # Open categorization modal
      click_on expense.merchant_name
      
      # Use keyboard shortcut
      send_keys '1'  # First suggestion
      
      expect(page).to have_content('Categorized successfully')
      expect(expense.reload.category).not_to be_nil
    end
  end
  
  describe 'Bulk categorization' do
    it 'categorizes multiple expenses at once' do
      create_list(:expense, 10, :uncategorized, merchant_name: 'WALMART')
      
      visit bulk_categorization_path
      
      # Should see group
      expect(page).to have_content('WALMART')
      expect(page).to have_content('10 expenses')
      
      # Accept suggestion
      click_on 'Accept All'
      
      expect(page).to have_content('Categorized 10 expenses')
      expect(Expense.uncategorized.count).to eq(0)
    end
  end
  
  describe 'Learning from corrections' do
    it 'improves suggestions based on user feedback' do
      expense1 = create(:expense, merchant_name: 'NEW STORE')
      
      visit expense_path(expense1)
      
      # Correct category
      select 'Food', from: 'expense_category_id'
      click_on 'Save'
      
      # Create similar expense
      expense2 = create(:expense, merchant_name: 'NEW STORE')
      
      visit expense_path(expense2)
      
      # Should suggest Food category
      within '.suggested-category' do
        expect(page).to have_content('Food')
      end
    end
  end
end
```

## Performance Testing

### Load Testing

```ruby
# spec/performance/load_test_spec.rb
require 'rails_helper'

RSpec.describe 'Load Testing' do
  describe 'concurrent categorization' do
    it 'handles 100 concurrent requests' do
      expenses = create_list(:expense, 100)
      
      threads = expenses.map do |expense|
        Thread.new do
          MasterCategorizer.new.categorize(expense)
        end
      end
      
      expect { threads.each(&:join) }.not_to raise_error
    end
  end
  
  describe 'throughput' do
    it 'processes 1000 expenses per minute' do
      expenses = create_list(:expense, 1000)
      
      start_time = Time.current
      
      expenses.each do |expense|
        MasterCategorizer.new.categorize(expense)
      end
      
      duration = Time.current - start_time
      
      expect(duration).to be < 60  # seconds
    end
  end
end
```

### Stress Testing

```ruby
# spec/performance/stress_test_spec.rb
require 'rails_helper'

RSpec.describe 'Stress Testing' do
  describe 'memory under stress' do
    it 'handles memory pressure gracefully' do
      initial_memory = GetProcessMem.new.mb
      
      # Create memory pressure
      10_000.times do
        expense = build(:expense)
        MasterCategorizer.new.categorize(expense)
      end
      
      # Force garbage collection
      GC.start
      
      final_memory = GetProcessMem.new.mb
      memory_increase = final_memory - initial_memory
      
      expect(memory_increase).to be < 500  # MB
    end
  end
  
  describe 'degradation under load' do
    it 'maintains accuracy under high load' do
      accuracies = []
      
      10.times do
        # Simulate high load
        Thread.new { 100.times { create(:expense) } }
        
        # Test accuracy
        test_expenses = create_list(:expense, 10, :categorized)
        correct = 0
        
        test_expenses.each do |expense|
          result = MasterCategorizer.new.categorize(expense)
          correct += 1 if result[:category] == expense.category
        end
        
        accuracies << (correct.to_f / test_expenses.size)
      end
      
      avg_accuracy = accuracies.sum / accuracies.size
      expect(avg_accuracy).to be > 0.75
    end
  end
end
```

## Security Testing

```ruby
# spec/security/security_spec.rb
require 'rails_helper'

RSpec.describe 'Security Testing' do
  describe 'data protection' do
    it 'never sends PII to external APIs' do
      expense = create(:expense,
        description: 'Payment from john.doe@example.com SSN: 123-45-6789'
      )
      
      # Mock LLM call
      allow_any_instance_of(AI::LLMLayer)
        .to receive(:call_api) do |_, prompt, _|
          expect(prompt).not_to include('john.doe@example.com')
          expect(prompt).not_to include('123-45-6789')
          
          { 'choices' => [{ 'message' => { 'content' => '{}' } }] }
        end
      
      AI::IntelligentRouter.new.categorize(expense)
    end
    
    it 'sanitizes log output' do
      expense = create(:expense,
        merchant_name: 'STORE 1234567890123456'  # Credit card number
      )
      
      logger = double('logger')
      allow(Rails).to receive(:logger).and_return(logger)
      
      expect(logger).to receive(:info) do |message|
        expect(message).not_to include('1234567890123456')
      end
      
      MasterCategorizer.new.categorize(expense)
    end
  end
  
  describe 'API security' do
    it 'enforces rate limiting' do
      100.times do
        post api_v1_categorize_path, params: { expense_id: 1 }
      end
      
      # 101st request should be rate limited
      post api_v1_categorize_path, params: { expense_id: 1 }
      expect(response).to have_http_status(:too_many_requests)
    end
    
    it 'validates API tokens' do
      post api_v1_categorize_path, 
           params: { expense_id: 1 },
           headers: { 'X-API-Token' => 'invalid' }
      
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

## Test Data Management

### Factories

```ruby
# spec/factories/expenses.rb
FactoryBot.define do
  factory :expense do
    merchant_name { Faker::Company.name }
    amount { Faker::Commerce.price(range: 10..500) }
    transaction_date { Faker::Date.between(from: 30.days.ago, to: Date.current) }
    description { Faker::Lorem.sentence }
    
    trait :categorized do
      association :category
    end
    
    trait :uncategorized do
      category { nil }
    end
    
    trait :with_embedding do
      embedding { Array.new(384) { rand(-1.0..1.0) } }
    end
    
    trait :complex do
      merchant_name { "XYZ*#{rand(1000..9999)}*ABC" }
      description { Faker::Lorem.paragraph(sentence_count: 5) }
      amount { rand(500..5000) }
    end
  end
end

# spec/factories/categories.rb
FactoryBot.define do
  factory :category do
    name { Faker::Commerce.department }
    
    trait :with_patterns do
      after(:create) do |category|
        create_list(:category_pattern, 3, category: category)
      end
    end
  end
end

# spec/factories/ml_patterns.rb
FactoryBot.define do
  factory :ml_pattern do
    pattern_type { %w[merchant keyword amount time].sample }
    pattern_value { Faker::Lorem.word }
    association :category
    probability { rand(0.5..0.95) }
    confidence_score { rand(0.6..0.9) }
  end
end
```

### Test Helpers

```ruby
# spec/support/categorization_helpers.rb
module CategorizationHelpers
  def mock_successful_categorization(category, confidence = 0.85)
    allow_any_instance_of(MasterCategorizer)
      .to receive(:categorize)
      .and_return({
        category: category,
        confidence: confidence,
        method: 'mock',
        route: 'test'
      })
  end
  
  def create_training_data(count: 100)
    categories = create_list(:category, 5)
    
    count.times do
      create(:expense, category: categories.sample)
    end
  end
  
  def measure_categorization_accuracy(expenses)
    correct = 0
    
    expenses.each do |expense|
      result = MasterCategorizer.new.categorize(expense)
      correct += 1 if result[:category] == expense.category
    end
    
    correct.to_f / expenses.size
  end
end

RSpec.configure do |config|
  config.include CategorizationHelpers
end
```

## CI/CD Testing

### GitHub Actions Workflow

```yaml
# .github/workflows/test.yml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgis/postgis:14-3.2
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
      
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: 3.3.0
        bundler-cache: true
    
    - name: Setup Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'
    
    - name: Install Python dependencies
      run: |
        pip install onnxruntime transformers torch
    
    - name: Setup database
      run: |
        bundle exec rails db:create
        bundle exec rails db:schema:load
        bundle exec rails db:seed
    
    - name: Download ML models
      run: bundle exec rails ml:download_models
    
    - name: Run tests
      run: |
        bundle exec rspec --format progress --format json --out rspec.json
    
    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage/coverage.json
    
    - name: Performance tests
      run: bundle exec rspec spec/performance --tag performance
    
    - name: Security scan
      run: |
        bundle exec brakeman
        bundle exec bundle-audit check --update
```

## Test Metrics

### Coverage Requirements

```ruby
# spec/spec_helper.rb
require 'simplecov'

SimpleCov.start 'rails' do
  add_filter '/spec/'
  add_filter '/config/'
  
  add_group 'Services', 'app/services'
  add_group 'ML', 'app/services/ml'
  add_group 'AI', 'app/services/ai'
  
  minimum_coverage 95
  minimum_coverage_by_file 90
end
```

### Quality Gates

```ruby
# Rakefile
task :quality_check do
  puts "Running quality checks..."
  
  # Test coverage
  system("bundle exec rspec") || exit(1)
  
  # Code quality
  system("bundle exec rubocop") || exit(1)
  
  # Security
  system("bundle exec brakeman -q") || exit(1)
  
  # Performance
  system("bundle exec rspec spec/performance") || exit(1)
  
  puts "All quality checks passed!"
end
```

## Test Monitoring

### Test Performance Dashboard

```ruby
# spec/support/test_reporter.rb
class TestReporter
  def self.report
    {
      total_tests: test_count,
      passing: passing_count,
      failing: failing_count,
      coverage: coverage_percentage,
      slowest_tests: slowest_tests(10),
      flaky_tests: detect_flaky_tests,
      test_duration: total_duration
    }
  end
  
  private
  
  def self.detect_flaky_tests
    # Tests that failed in last 10 runs but passed eventually
    TestRun.where('created_at > ?', 10.days.ago)
           .group(:test_name)
           .having('COUNT(DISTINCT passed) > 1')
           .pluck(:test_name)
  end
end
```

## Conclusion

This comprehensive testing strategy ensures:

1. **Quality**: 95%+ test coverage across all components
2. **Performance**: Sub-second response times verified
3. **Security**: No PII leakage, proper sanitization
4. **Reliability**: Load and stress testing passed
5. **Maintainability**: Clear test structure and helpers

The testing pyramid approach ensures fast feedback with unit tests while maintaining confidence through integration and E2E tests.