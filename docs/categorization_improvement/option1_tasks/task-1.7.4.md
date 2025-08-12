### Task 1.7.4: Data Quality and Seed Improvements
**Priority**: MEDIUM  
**Estimated Hours**: 3  
**Dependencies**: Tasks 1.7.1-1.7.3  

#### Description
Expand test data, add comprehensive seed patterns, and implement data quality validation.

#### Acceptance Criteria
- [ ] Seed data expanded to 50+ diverse patterns
- [ ] Pattern validation rules prevent invalid data
- [ ] Data quality checks integrated into health monitoring
- [ ] Test fixtures cover edge cases
- [ ] Migration to add missing indexes and constraints
- [ ] Data audit report showing current quality metrics

#### Technical Implementation

##### Enhanced Seed Data
```ruby
# db/seeds/categorization_patterns.rb
module Seeds
  class CategorizationPatterns
    def self.seed!
      categories = {
        food_dining: Category.find_by(name: 'Food & Dining'),
        groceries: Category.find_by(name: 'Groceries'),
        transportation: Category.find_by(name: 'Transportation'),
        utilities: Category.find_by(name: 'Utilities'),
        entertainment: Category.find_by(name: 'Entertainment'),
        shopping: Category.find_by(name: 'Shopping'),
        healthcare: Category.find_by(name: 'Healthcare')
      }
      
      patterns = [
        # Food & Dining - Merchant patterns
        { category: :food_dining, type: 'merchant', value: 'mcdonalds', weight: 0.95 },
        { category: :food_dining, type: 'merchant', value: 'starbucks', weight: 0.95 },
        { category: :food_dining, type: 'merchant', value: 'subway', weight: 0.95 },
        { category: :food_dining, type: 'merchant', value: 'pizza hut', weight: 0.9 },
        { category: :food_dining, type: 'merchant', value: 'dominos', weight: 0.9 },
        { category: :food_dining, type: 'merchant', value: 'uber eats', weight: 0.85 },
        { category: :food_dining, type: 'merchant', value: 'doordash', weight: 0.85 },
        
        # Food & Dining - Keyword patterns
        { category: :food_dining, type: 'keyword', value: 'restaurant', weight: 0.8 },
        { category: :food_dining, type: 'keyword', value: 'cafe', weight: 0.8 },
        { category: :food_dining, type: 'keyword', value: 'coffee', weight: 0.75 },
        { category: :food_dining, type: 'keyword', value: 'lunch', weight: 0.7 },
        { category: :food_dining, type: 'keyword', value: 'dinner', weight: 0.7 },
        
        # Groceries - Merchant patterns
        { category: :groceries, type: 'merchant', value: 'walmart', weight: 0.85 },
        { category: :groceries, type: 'merchant', value: 'kroger', weight: 0.95 },
        { category: :groceries, type: 'merchant', value: 'safeway', weight: 0.95 },
        { category: :groceries, type: 'merchant', value: 'whole foods', weight: 0.95 },
        { category: :groceries, type: 'merchant', value: 'trader joes', weight: 0.95 },
        { category: :groceries, type: 'merchant', value: 'costco', weight: 0.8 },
        
        # Transportation - Merchant patterns
        { category: :transportation, type: 'merchant', value: 'uber', weight: 0.9 },
        { category: :transportation, type: 'merchant', value: 'lyft', weight: 0.9 },
        { category: :transportation, type: 'merchant', value: 'shell', weight: 0.85 },
        { category: :transportation, type: 'merchant', value: 'chevron', weight: 0.85 },
        { category: :transportation, type: 'merchant', value: 'exxon', weight: 0.85 },
        
        # Transportation - Keyword patterns
        { category: :transportation, type: 'keyword', value: 'gas station', weight: 0.8 },
        { category: :transportation, type: 'keyword', value: 'parking', weight: 0.75 },
        { category: :transportation, type: 'keyword', value: 'toll', weight: 0.8 },
        
        # Utilities - Merchant patterns
        { category: :utilities, type: 'merchant', value: 'pg&e', weight: 0.95 },
        { category: :utilities, type: 'merchant', value: 'comcast', weight: 0.9 },
        { category: :utilities, type: 'merchant', value: 'at&t', weight: 0.85 },
        { category: :utilities, type: 'merchant', value: 'verizon', weight: 0.85 },
        
        # Entertainment - Merchant patterns
        { category: :entertainment, type: 'merchant', value: 'netflix', weight: 0.95 },
        { category: :entertainment, type: 'merchant', value: 'spotify', weight: 0.95 },
        { category: :entertainment, type: 'merchant', value: 'amc', weight: 0.9 },
        { category: :entertainment, type: 'merchant', value: 'ticketmaster', weight: 0.85 },
        
        # Shopping - Merchant patterns
        { category: :shopping, type: 'merchant', value: 'amazon', weight: 0.85 },
        { category: :shopping, type: 'merchant', value: 'target', weight: 0.85 },
        { category: :shopping, type: 'merchant', value: 'best buy', weight: 0.9 },
        { category: :shopping, type: 'merchant', value: 'home depot', weight: 0.85 },
        
        # Healthcare - Merchant patterns
        { category: :healthcare, type: 'merchant', value: 'cvs', weight: 0.8 },
        { category: :healthcare, type: 'merchant', value: 'walgreens', weight: 0.8 },
        { category: :healthcare, type: 'merchant', value: 'kaiser', weight: 0.95 },
        
        # Amount range patterns
        { category: :groceries, type: 'amount_range', value: '50.00-300.00', weight: 0.6 },
        { category: :utilities, type: 'amount_range', value: '100.00-500.00', weight: 0.5 },
        { category: :entertainment, type: 'amount_range', value: '10.00-50.00', weight: 0.4 },
        
        # Time patterns
        { category: :food_dining, type: 'time', value: '11:30-13:30', weight: 0.5 }, # Lunch time
        { category: :food_dining, type: 'time', value: '18:00-21:00', weight: 0.5 }, # Dinner time
        { category: :entertainment, type: 'time', value: 'friday,saturday,sunday', weight: 0.4 } # Weekends
      ]
      
      patterns.each do |pattern_data|
        category = categories[pattern_data[:category]]
        next unless category
        
        pattern = CategorizationPattern.find_or_initialize_by(
          category: category,
          pattern_type: pattern_data[:type],
          pattern_value: pattern_data[:value]
        )
        
        pattern.confidence_weight = pattern_data[:weight]
        pattern.active = true
        
        # Add some historical data for testing
        if pattern.new_record?
          pattern.usage_count = rand(10..100)
          pattern.success_count = (pattern.usage_count * rand(0.7..0.95)).to_i
          pattern.success_rate = pattern.success_count.to_f / pattern.usage_count
        end
        
        pattern.save!
      end
      
      puts "Seeded #{CategorizationPattern.count} categorization patterns"
    end
  end
end

# db/seeds.rb
Seeds::CategorizationPatterns.seed!
```

##### Data Quality Validation
```ruby
# app/models/concerns/pattern_validation.rb
module PatternValidation
  extend ActiveSupport::Concern
  
  included do
    before_validation :normalize_pattern_value
    validate :pattern_value_format
    validate :pattern_value_complexity
  end
  
  private
  
  def normalize_pattern_value
    return unless pattern_value.present?
    
    case pattern_type
    when 'merchant', 'keyword'
      self.pattern_value = pattern_value.strip.downcase
    when 'amount_range'
      # Ensure proper format
      if pattern_value =~ /(\d+\.?\d*)-(\d+\.?\d*)/
        min, max = $1.to_f, $2.to_f
        self.pattern_value = "#{min}-#{max}"
      end
    end
  end
  
  def pattern_value_format
    case pattern_type
    when 'merchant', 'keyword'
      if pattern_value.length < 2
        errors.add(:pattern_value, 'must be at least 2 characters')
      end
      if pattern_value =~ /^[^a-z0-9\s&'-]+$/i
        errors.add(:pattern_value, 'contains invalid characters')
      end
    when 'regex'
      begin
        Regexp.new(pattern_value)
      rescue RegexpError => e
        errors.add(:pattern_value, "invalid regex: #{e.message}")
      end
    when 'amount_range'
      unless pattern_value =~ /^\d+\.?\d*-\d+\.?\d*$/
        errors.add(:pattern_value, 'must be in format: min-max')
      end
    when 'time'
      validate_time_pattern
    end
  end
  
  def pattern_value_complexity
    case pattern_type
    when 'regex'
      # Prevent catastrophic backtracking
      if pattern_value.include?('.*.*') || pattern_value.count('*') > 3
        errors.add(:pattern_value, 'regex too complex - may cause performance issues')
      end
    end
  end
  
  def validate_time_pattern
    # Validate time ranges like "11:30-13:30" or days like "monday,tuesday"
    if pattern_value.include?(':')
      # Time range validation
      unless pattern_value =~ /^\d{1,2}:\d{2}-\d{1,2}:\d{2}$/
        errors.add(:pattern_value, 'invalid time range format')
      end
    else
      # Day list validation
      valid_days = %w[monday tuesday wednesday thursday friday saturday sunday]
      days = pattern_value.split(',').map(&:strip)
      invalid_days = days - valid_days
      if invalid_days.any?
        errors.add(:pattern_value, "invalid days: #{invalid_days.join(', ')}")
      end
    end
  end
end

# app/models/categorization_pattern.rb
class CategorizationPattern < ApplicationRecord
  include PatternValidation
  # ... rest of model
end
```

##### Data Quality Monitoring
```ruby
# app/services/categorization/monitoring/data_quality_checker.rb
module Categorization
  module Monitoring
    class DataQualityChecker
      def self.audit
        {
          timestamp: Time.current.iso8601,
          patterns: audit_patterns,
          coverage: calculate_coverage,
          quality_score: calculate_quality_score,
          recommendations: generate_recommendations
        }
      end
      
      private
      
      def self.audit_patterns
        {
          total: CategorizationPattern.count,
          active: CategorizationPattern.active.count,
          by_type: CategorizationPattern.group(:pattern_type).count,
          with_low_success: CategorizationPattern.where('usage_count > 10 AND success_rate < 0.5').count,
          unused: CategorizationPattern.where('usage_count = 0').count,
          duplicates: find_duplicate_patterns.count
        }
      end
      
      def self.calculate_coverage
        categories_with_patterns = CategorizationPattern.distinct.pluck(:category_id)
        total_categories = Category.count
        
        {
          categories_covered: categories_with_patterns.count,
          total_categories: total_categories,
          coverage_percentage: (categories_with_patterns.count.to_f / total_categories * 100).round(2),
          categories_without_patterns: Category.where.not(id: categories_with_patterns).pluck(:name)
        }
      end
      
      def self.calculate_quality_score
        scores = []
        
        # Pattern diversity score
        type_distribution = CategorizationPattern.group(:pattern_type).count
        diversity_score = type_distribution.keys.count / 5.0  # 5 pattern types
        scores << diversity_score
        
        # Success rate score
        avg_success_rate = CategorizationPattern.where('usage_count > 5').average(:success_rate) || 0
        scores << avg_success_rate
        
        # Coverage score
        coverage = calculate_coverage
        scores << coverage[:coverage_percentage] / 100.0
        
        # Active patterns score
        active_ratio = CategorizationPattern.active.count.to_f / CategorizationPattern.count
        scores << active_ratio
        
        (scores.sum / scores.count * 100).round(2)
      end
      
      def self.find_duplicate_patterns
        CategorizationPattern
          .select('pattern_type, pattern_value, COUNT(*) as count')
          .group(:pattern_type, :pattern_value)
          .having('COUNT(*) > 1')
      end
      
      def self.generate_recommendations
        recommendations = []
        
        audit = audit_patterns
        coverage = calculate_coverage
        
        if audit[:with_low_success] > 5
          recommendations << "Review #{audit[:with_low_success]} patterns with low success rates"
        end
        
        if audit[:unused] > 10
          recommendations << "Remove or review #{audit[:unused]} unused patterns"
        end
        
        if coverage[:coverage_percentage] < 80
          recommendations << "Add patterns for: #{coverage[:categories_without_patterns].join(', ')}"
        end
        
        if audit[:duplicates] > 0
          recommendations << "Merge #{audit[:duplicates]} duplicate patterns"
        end
        
        recommendations
      end
    end
  end
end
```

#### Testing Requirements
```ruby
# spec/db/seeds/categorization_patterns_spec.rb
RSpec.describe Seeds::CategorizationPatterns do
  describe '.seed!' do
    it 'creates at least 50 patterns' do
      described_class.seed!
      expect(CategorizationPattern.count).to be >= 50
    end
    
    it 'covers all categories' do
      described_class.seed!
      categories_with_patterns = CategorizationPattern.distinct.pluck(:category_id)
      expect(categories_with_patterns.count).to eq(Category.count)
    end
    
    it 'creates diverse pattern types' do
      described_class.seed!
      types = CategorizationPattern.distinct.pluck(:pattern_type)
      expect(types).to include('merchant', 'keyword', 'amount_range', 'time')
    end
  end
end

# spec/services/categorization/monitoring/data_quality_checker_spec.rb
RSpec.describe Categorization::Monitoring::DataQualityChecker do
  describe '.audit' do
    before do
      create_list(:categorization_pattern, 10)
    end
    
    it 'generates comprehensive audit report' do
      audit = described_class.audit
      
      expect(audit).to include(:patterns, :coverage, :quality_score, :recommendations)
      expect(audit[:quality_score]).to be_between(0, 100)
    end
    
    it 'identifies data quality issues' do
      # Create problematic patterns
      create(:categorization_pattern, usage_count: 20, success_count: 5)
      
      audit = described_class.audit
      expect(audit[:patterns][:with_low_success]).to be > 0
      expect(audit[:recommendations]).not_to be_empty
    end
  end
end
```
