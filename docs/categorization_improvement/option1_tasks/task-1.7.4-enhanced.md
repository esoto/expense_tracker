### Task 1.7.4: Data Quality and Seed Improvements (Enhanced)
**Priority**: MEDIUM  
**Estimated Hours**: 6-8
**Dependencies**: Tasks 1.7.1-1.7.3  
**Completion Status**: 70%

#### Executive Summary
Implement comprehensive data quality validation, automated pattern management, and production-grade seed data with continuous quality monitoring and self-healing capabilities.

#### Current Issues
- Pattern validation incomplete with manual processes
- No automated quality scoring or pattern effectiveness tracking
- Missing pattern lifecycle management (creation, testing, promotion, retirement)
- Insufficient test coverage for edge cases and international data
- No automated data quality remediation

#### Technical Architecture

##### 1. Advanced Pattern Validation System
```ruby
# app/models/concerns/pattern_validation.rb
module PatternValidation
  extend ActiveSupport::Concern
  
  included do
    before_validation :normalize_pattern_value
    before_validation :enrich_pattern_metadata
    
    validate :pattern_value_format
    validate :pattern_value_complexity
    validate :pattern_uniqueness
    validate :pattern_effectiveness
    
    after_validation :calculate_quality_score
  end
  
  private
  
  def normalize_pattern_value
    return unless pattern_value.present?
    
    self.pattern_value = case pattern_type
    when 'merchant', 'keyword'
      normalize_text_pattern(pattern_value)
    when 'amount_range'
      normalize_amount_range(pattern_value)
    when 'time'
      normalize_time_pattern(pattern_value)
    when 'regex'
      normalize_regex_pattern(pattern_value)
    when 'composite'
      normalize_composite_pattern(pattern_value)
    end
  end
  
  def normalize_text_pattern(value)
    # Remove extra whitespace and normalize casing
    normalized = value.strip.downcase
    
    # Handle special characters intelligently
    normalized = normalized.gsub(/[&]/, ' and ')
                          .gsub(/[@]/, ' at ')
                          .gsub(/[^\w\s-]/, '')
                          .squeeze(' ')
    
    # Stem words for better matching
    if pattern_type == 'keyword'
      normalized = stem_words(normalized)
    end
    
    normalized
  end
  
  def normalize_amount_range(value)
    if value =~ /(\d+\.?\d*)\s*-\s*(\d+\.?\d*)/
      min_val = $1.to_f
      max_val = $2.to_f
      
      # Ensure min < max
      min_val, max_val = max_val, min_val if min_val > max_val
      
      "#{min_val}-#{max_val}"
    else
      value
    end
  end
  
  def normalize_time_pattern(value)
    if value.include?(':')
      # Time range normalization
      normalize_time_range(value)
    elsif value.include?(',')
      # Day list normalization
      normalize_day_list(value)
    else
      value
    end
  end
  
  def normalize_regex_pattern(value)
    # Validate and optimize regex
    begin
      regex = Regexp.new(value)
      
      # Check for common inefficiencies
      if value.include?('.*.*') || value.include?('.+.+')
        # Optimize redundant wildcards
        value = value.gsub(/(\.\*)+/, '.*').gsub(/(\.\+)+/, '.+')
      end
      
      value
    rescue RegexpError
      value
    end
  end
  
  def pattern_value_format
    validator = case pattern_type
    when 'merchant', 'keyword'
      TextPatternValidator.new(self)
    when 'amount_range'
      AmountRangeValidator.new(self)
    when 'time'
      TimePatternValidator.new(self)
    when 'regex'
      RegexPatternValidator.new(self)
    when 'composite'
      CompositePatternValidator.new(self)
    else
      NullValidator.new(self)
    end
    
    validator.validate
  end
  
  def pattern_value_complexity
    case pattern_type
    when 'regex'
      validate_regex_complexity
    when 'composite'
      validate_composite_complexity
    end
  end
  
  def pattern_uniqueness
    # Check for duplicate or similar patterns
    similar = find_similar_patterns
    
    if similar.any?
      similarity_scores = similar.map { |p| 
        [p, calculate_similarity(self.pattern_value, p.pattern_value)]
      }
      
      exact_matches = similarity_scores.select { |_, score| score >= 0.95 }
      near_matches = similarity_scores.select { |_, score| score >= 0.85 && score < 0.95 }
      
      if exact_matches.any?
        errors.add(:pattern_value, "Duplicate pattern exists: #{exact_matches.first[0].id}")
      elsif near_matches.any?
        warnings.add(:pattern_value, "Very similar pattern exists: #{near_matches.first[0].id}")
      end
    end
  end
  
  def pattern_effectiveness
    return unless persisted? && usage_count > 10
    
    if success_rate < 0.3
      errors.add(:base, "Pattern has very low success rate (#{(success_rate * 100).round}%)")
    elsif success_rate < 0.5
      warnings.add(:base, "Pattern has low success rate (#{(success_rate * 100).round}%)")
    end
  end
  
  def calculate_quality_score
    scores = []
    
    # Specificity score (more specific = better)
    scores << calculate_specificity_score
    
    # Consistency score (stable performance = better)
    scores << calculate_consistency_score
    
    # Coverage score (matches appropriate number of expenses)
    scores << calculate_coverage_score
    
    # Uniqueness score (not overlapping with other patterns)
    scores << calculate_uniqueness_score
    
    self.quality_score = (scores.sum / scores.size.to_f * 100).round
  end
  
  def enrich_pattern_metadata
    self.metadata ||= {}
    
    # Add creation context
    self.metadata['created_by'] ||= Current.user&.email || 'system'
    self.metadata['created_at'] ||= Time.current.iso8601
    
    # Add pattern statistics
    if persisted?
      self.metadata['stats'] = {
        'total_matches': usage_count,
        'successful_matches': success_count,
        'last_match': last_matched_at&.iso8601,
        'avg_confidence': average_confidence
      }
    end
    
    # Add lifecycle stage
    self.metadata['lifecycle_stage'] = determine_lifecycle_stage
  end
  
  def determine_lifecycle_stage
    return 'testing' if usage_count < 10
    return 'probation' if usage_count < 50 && success_rate < 0.7
    return 'mature' if usage_count > 100 && success_rate > 0.8
    return 'declining' if success_rate < 0.5 && usage_count > 50
    'active'
  end
  
  class TextPatternValidator
    def initialize(pattern)
      @pattern = pattern
    end
    
    def validate
      value = @pattern.pattern_value
      
      # Length validation
      if value.length < 2
        @pattern.errors.add(:pattern_value, 'must be at least 2 characters')
      elsif value.length > 100
        @pattern.errors.add(:pattern_value, 'must be less than 100 characters')
      end
      
      # Character validation
      if value =~ /^[^a-z0-9\s&'-]+$/i
        @pattern.errors.add(:pattern_value, 'contains invalid characters')
      end
      
      # Word count validation for keywords
      if @pattern.pattern_type == 'keyword'
        word_count = value.split(/\s+/).size
        if word_count > 5
          @pattern.errors.add(:pattern_value, 'keyword patterns should have at most 5 words')
        end
      end
    end
  end
  
  class RegexPatternValidator
    def initialize(pattern)
      @pattern = pattern
    end
    
    def validate
      value = @pattern.pattern_value
      
      begin
        regex = Regexp.new(value)
        
        # Test regex performance
        test_string = "a" * 1000
        timeout = 0.1 # 100ms timeout
        
        Timeout.timeout(timeout) do
          test_string =~ regex
        end
      rescue RegexpError => e
        @pattern.errors.add(:pattern_value, "Invalid regex: #{e.message}")
      rescue Timeout::Error
        @pattern.errors.add(:pattern_value, "Regex too complex (potential ReDoS vulnerability)")
      end
    end
  end
end

# app/models/categorization_pattern.rb
class CategorizationPattern < ApplicationRecord
  include PatternValidation
  
  belongs_to :category
  has_many :pattern_feedbacks
  has_many :pattern_test_results
  
  scope :active, -> { where(active: true) }
  scope :high_quality, -> { where('quality_score >= ?', 80) }
  scope :needs_review, -> { where('quality_score < ? OR success_rate < ?', 50, 0.5) }
  
  # Lifecycle management
  def promote!
    update!(
      active: true,
      metadata: metadata.merge('promoted_at' => Time.current.iso8601)
    )
  end
  
  def demote!
    update!(
      active: false,
      metadata: metadata.merge('demoted_at' => Time.current.iso8601)
    )
  end
  
  def retire!
    update!(
      active: false,
      retired: true,
      metadata: metadata.merge('retired_at' => Time.current.iso8601)
    )
  end
end
```

##### 2. Automated Data Quality Management
```ruby
# app/services/categorization/data_quality/quality_manager.rb
module Categorization
  module DataQuality
    class QualityManager
      def self.audit_and_improve
        report = {
          timestamp: Time.current,
          patterns_audited: 0,
          patterns_improved: 0,
          patterns_retired: 0,
          new_patterns_created: 0,
          quality_score_before: calculate_overall_quality,
          issues_found: [],
          actions_taken: []
        }
        
        # Audit existing patterns
        audit_results = audit_patterns
        report[:patterns_audited] = audit_results[:total]
        report[:issues_found] = audit_results[:issues]
        
        # Improve low-quality patterns
        improvement_results = improve_patterns(audit_results[:low_quality])
        report[:patterns_improved] = improvement_results[:improved]
        report[:actions_taken].concat(improvement_results[:actions])
        
        # Retire ineffective patterns
        retirement_results = retire_ineffective_patterns
        report[:patterns_retired] = retirement_results[:retired]
        report[:actions_taken].concat(retirement_results[:actions])
        
        # Discover new patterns
        discovery_results = discover_new_patterns
        report[:new_patterns_created] = discovery_results[:created]
        report[:actions_taken].concat(discovery_results[:actions])
        
        # Merge similar patterns
        merge_results = merge_similar_patterns
        report[:actions_taken].concat(merge_results[:actions])
        
        report[:quality_score_after] = calculate_overall_quality
        report[:quality_improvement] = report[:quality_score_after] - report[:quality_score_before]
        
        # Store audit report
        store_audit_report(report)
        
        # Send notifications if significant issues
        notify_if_needed(report)
        
        report
      end
      
      private
      
      def self.audit_patterns
        issues = []
        low_quality = []
        
        CategorizationPattern.find_each do |pattern|
          audit = PatternAuditor.new(pattern).audit
          
          if audit[:issues].any?
            issues.concat(audit[:issues])
          end
          
          if audit[:quality_score] < 50
            low_quality << pattern
          end
        end
        
        {
          total: CategorizationPattern.count,
          issues: issues,
          low_quality: low_quality
        }
      end
      
      def self.improve_patterns(patterns)
        improved = 0
        actions = []
        
        patterns.each do |pattern|
          improver = PatternImprover.new(pattern)
          
          if improver.can_improve?
            result = improver.improve!
            
            if result[:success]
              improved += 1
              actions << {
                type: 'improvement',
                pattern_id: pattern.id,
                changes: result[:changes]
              }
            end
          end
        end
        
        { improved: improved, actions: actions }
      end
      
      def self.retire_ineffective_patterns
        retired = 0
        actions = []
        
        candidates = CategorizationPattern.where(
          'usage_count > ? AND success_rate < ?', 50, 0.3
        ).or(
          CategorizationPattern.where('last_matched_at < ?', 6.months.ago)
        )
        
        candidates.each do |pattern|
          pattern.retire!
          retired += 1
          
          actions << {
            type: 'retirement',
            pattern_id: pattern.id,
            reason: determine_retirement_reason(pattern)
          }
        end
        
        { retired: retired, actions: actions }
      end
      
      def self.discover_new_patterns
        created = 0
        actions = []
        
        # Find uncategorized expenses with common patterns
        uncategorized = Expense.where(category_id: nil).limit(1000)
        
        # Group by merchant
        merchant_groups = uncategorized.group_by(&:merchant_name).select { |_, v| v.size > 5 }
        
        merchant_groups.each do |merchant, expenses|
          # Check if pattern already exists
          next if CategorizationPattern.exists?(
            pattern_type: 'merchant',
            pattern_value: merchant.downcase
          )
          
          # Find most common category for this merchant
          categorized_same_merchant = Expense.where(merchant_name: merchant)
                                            .where.not(category_id: nil)
                                            .group(:category_id)
                                            .count
          
          if categorized_same_merchant.any?
            most_common_category_id = categorized_same_merchant.max_by { |_, count| count }[0]
            
            pattern = CategorizationPattern.create!(
              category_id: most_common_category_id,
              pattern_type: 'merchant',
              pattern_value: merchant.downcase,
              confidence_weight: 0.7,
              active: false, # Start inactive for testing
              metadata: {
                'source' => 'auto_discovery',
                'discovered_at' => Time.current.iso8601,
                'sample_size' => expenses.size
              }
            )
            
            created += 1
            actions << {
              type: 'discovery',
              pattern_id: pattern.id,
              merchant: merchant
            }
          end
        end
        
        { created: created, actions: actions }
      end
      
      def self.merge_similar_patterns
        actions = []
        
        # Find similar patterns
        patterns_by_type = CategorizationPattern.active.group_by(&:pattern_type)
        
        patterns_by_type.each do |type, patterns|
          similarity_matrix = build_similarity_matrix(patterns)
          
          similarity_matrix.each do |(p1, p2), score|
            next if score < 0.85 # Only merge very similar patterns
            
            # Merge the less successful pattern into the more successful one
            if p1.success_rate > p2.success_rate
              merge_patterns(p1, p2)
              actions << {
                type: 'merge',
                kept: p1.id,
                merged: p2.id,
                similarity: score
              }
            end
          end
        end
        
        { actions: actions }
      end
      
      def self.calculate_overall_quality
        return 0 if CategorizationPattern.count == 0
        
        CategorizationPattern.average(:quality_score) || 0
      end
    end
    
    # Pattern auditor
    class PatternAuditor
      def initialize(pattern)
        @pattern = pattern
      end
      
      def audit
        issues = []
        recommendations = []
        
        # Check usage
        if @pattern.usage_count == 0 && @pattern.created_at < 1.month.ago
          issues << { type: 'unused', message: 'Pattern has never been used' }
          recommendations << 'Consider removing or revising pattern'
        end
        
        # Check success rate
        if @pattern.usage_count > 10 && @pattern.success_rate < 0.5
          issues << { type: 'low_success', message: "Low success rate: #{(@pattern.success_rate * 100).round}%" }
          recommendations << 'Review pattern accuracy and specificity'
        end
        
        # Check for conflicts
        conflicts = find_conflicting_patterns
        if conflicts.any?
          issues << { type: 'conflict', message: "Conflicts with #{conflicts.size} other patterns" }
          recommendations << 'Resolve pattern conflicts to improve accuracy'
        end
        
        # Check pattern quality
        quality_score = calculate_pattern_quality
        
        {
          pattern_id: @pattern.id,
          quality_score: quality_score,
          issues: issues,
          recommendations: recommendations,
          last_audit: Time.current
        }
      end
      
      private
      
      def find_conflicting_patterns
        # Find patterns that would match the same expenses but categorize differently
        CategorizationPattern.active
                            .where.not(id: @pattern.id)
                            .where.not(category_id: @pattern.category_id)
                            .where(pattern_type: @pattern.pattern_type)
                            .select { |p| patterns_overlap?(@pattern, p) }
      end
      
      def patterns_overlap?(p1, p2)
        case p1.pattern_type
        when 'merchant', 'keyword'
          text_patterns_overlap?(p1.pattern_value, p2.pattern_value)
        when 'amount_range'
          amount_ranges_overlap?(p1.pattern_value, p2.pattern_value)
        else
          false
        end
      end
      
      def calculate_pattern_quality
        scores = []
        
        # Success rate score
        scores << (@pattern.success_rate * 100) if @pattern.usage_count > 0
        
        # Usage frequency score
        usage_score = Math.log10(@pattern.usage_count + 1) * 20
        scores << [usage_score, 100].min
        
        # Recency score
        if @pattern.last_matched_at
          days_since_use = (Date.current - @pattern.last_matched_at.to_date).to_i
          recency_score = [100 - (days_since_use * 2), 0].max
          scores << recency_score
        end
        
        # Confidence weight score
        scores << (@pattern.confidence_weight * 100)
        
        scores.empty? ? 0 : (scores.sum / scores.size).round
      end
    end
    
    # Pattern improver
    class PatternImprover
      def initialize(pattern)
        @pattern = pattern
      end
      
      def can_improve?
        @pattern.quality_score < 70 && @pattern.usage_count > 10
      end
      
      def improve!
        changes = []
        
        # Improve pattern value
        if should_update_pattern_value?
          original = @pattern.pattern_value
          @pattern.pattern_value = improve_pattern_value
          changes << { field: 'pattern_value', from: original, to: @pattern.pattern_value }
        end
        
        # Adjust confidence weight based on performance
        if should_adjust_confidence?
          original = @pattern.confidence_weight
          @pattern.confidence_weight = calculate_optimal_confidence
          changes << { field: 'confidence_weight', from: original, to: @pattern.confidence_weight }
        end
        
        # Update metadata
        @pattern.metadata['last_improved'] = Time.current.iso8601
        @pattern.metadata['improvement_version'] = (@pattern.metadata['improvement_version'] || 0) + 1
        
        if @pattern.save
          { success: true, changes: changes }
        else
          { success: false, errors: @pattern.errors.full_messages }
        end
      end
      
      private
      
      def should_update_pattern_value?
        @pattern.pattern_type.in?(['merchant', 'keyword']) && 
        @pattern.success_rate < 0.6
      end
      
      def improve_pattern_value
        # Analyze successful matches to refine pattern
        successful_matches = PatternFeedback.where(
          pattern: @pattern,
          feedback_type: 'positive'
        ).limit(100)
        
        common_terms = extract_common_terms(successful_matches)
        
        # Refine pattern based on common terms
        refine_pattern_with_terms(@pattern.pattern_value, common_terms)
      end
      
      def should_adjust_confidence?
        @pattern.usage_count > 20
      end
      
      def calculate_optimal_confidence
        # Base confidence on actual success rate
        base_confidence = @pattern.success_rate
        
        # Adjust for usage frequency
        usage_factor = Math.log10(@pattern.usage_count) / 10.0
        
        # Calculate final confidence
        optimal = base_confidence * (1 + usage_factor)
        
        [optimal, 1.0].min.round(2)
      end
    end
  end
end
```

##### 3. Comprehensive Seed Data System
```ruby
# db/seeds/categorization/pattern_seeder.rb
module Seeds
  module Categorization
    class PatternSeeder
      PATTERN_SETS = {
        us_common: 'seeds/patterns/us_common.yml',
        international: 'seeds/patterns/international.yml',
        costa_rica: 'seeds/patterns/costa_rica.yml',
        edge_cases: 'seeds/patterns/edge_cases.yml'
      }.freeze
      
      def self.seed!(locale: :all, mode: :safe)
        seeder = new(locale: locale, mode: mode)
        seeder.seed!
      end
      
      def initialize(locale: :all, mode: :safe)
        @locale = locale
        @mode = mode # :safe, :force, :update
        @stats = { created: 0, updated: 0, skipped: 0, errors: [] }
      end
      
      def seed!
        ActiveRecord::Base.transaction do
          pattern_sets = @locale == :all ? PATTERN_SETS.keys : [@locale]
          
          pattern_sets.each do |set|
            load_and_seed_set(set)
          end
          
          # Post-processing
          validate_seeded_patterns
          optimize_pattern_distribution
          generate_composite_patterns
          
          print_summary
        end
      rescue => e
        Rails.logger.error "Seeding failed: #{e.message}"
        raise ActiveRecord::Rollback
      end
      
      private
      
      def load_and_seed_set(set_name)
        file_path = Rails.root.join(PATTERN_SETS[set_name])
        patterns_data = YAML.load_file(file_path)
        
        patterns_data['patterns'].each do |pattern_data|
          seed_pattern(pattern_data)
        end
      end
      
      def seed_pattern(data)
        category = find_or_create_category(data['category'])
        
        pattern = CategorizationPattern.find_or_initialize_by(
          pattern_type: data['type'],
          pattern_value: data['value'],
          category: category
        )
        
        if pattern.persisted? && @mode == :safe
          @stats[:skipped] += 1
          return
        end
        
        pattern.assign_attributes(
          confidence_weight: data['weight'] || 0.7,
          active: data['active'] != false,
          metadata: build_metadata(data),
          quality_score: data['quality_score'] || 70
        )
        
        # Add historical data for testing
        if data['test_data']
          pattern.usage_count = data['test_data']['usage_count'] || 0
          pattern.success_count = data['test_data']['success_count'] || 0
          pattern.success_rate = calculate_success_rate(pattern)
        end
        
        if pattern.save
          @stats[pattern.id_previously_changed? ? :created : :updated] += 1
        else
          @stats[:errors] << {
            pattern: data['value'],
            errors: pattern.errors.full_messages
          }
        end
      end
      
      def find_or_create_category(category_name)
        Category.find_or_create_by!(name: category_name) do |category|
          category.color = generate_category_color(category_name)
          category.icon = generate_category_icon(category_name)
        end
      end
      
      def build_metadata(data)
        {
          'source' => 'seed',
          'locale' => data['locale'] || 'en',
          'tags' => data['tags'] || [],
          'examples' => data['examples'] || [],
          'notes' => data['notes'],
          'seeded_at' => Time.current.iso8601
        }
      end
      
      def validate_seeded_patterns
        # Check for missing categories
        categories_without_patterns = Category.left_joins(:categorization_patterns)
                                              .where(categorization_patterns: { id: nil })
        
        if categories_without_patterns.any?
          Rails.logger.warn "Categories without patterns: #{categories_without_patterns.pluck(:name)}"
        end
        
        # Check for pattern conflicts
        detect_and_resolve_conflicts
      end
      
      def optimize_pattern_distribution
        # Ensure balanced pattern distribution across categories
        pattern_counts = CategorizationPattern.group(:category_id).count
        avg_patterns = pattern_counts.values.sum / pattern_counts.size.to_f
        
        pattern_counts.each do |category_id, count|
          if count < avg_patterns * 0.5
            # Generate additional patterns for underrepresented categories
            generate_additional_patterns(category_id)
          end
        end
      end
      
      def generate_composite_patterns
        # Create composite patterns for complex matching
        Category.find_each do |category|
          merchants = category.categorization_patterns.where(pattern_type: 'merchant')
          keywords = category.categorization_patterns.where(pattern_type: 'keyword')
          
          # Create merchant + amount patterns
          merchants.each do |merchant|
            create_composite_pattern(category, [merchant], 'merchant_amount')
          end
          
          # Create keyword combinations
          if keywords.size >= 2
            keywords.combination(2).first(5).each do |combo|
              create_composite_pattern(category, combo, 'keyword_combo')
            end
          end
        end
      end
      
      def create_composite_pattern(category, base_patterns, composite_type)
        composite_value = {
          'type' => composite_type,
          'components' => base_patterns.map { |p| 
            { 'type' => p.pattern_type, 'value' => p.pattern_value }
          }
        }.to_json
        
        CategorizationPattern.find_or_create_by(
          category: category,
          pattern_type: 'composite',
          pattern_value: composite_value
        ) do |pattern|
          pattern.confidence_weight = base_patterns.map(&:confidence_weight).max * 0.9
          pattern.active = false # Start inactive for testing
          pattern.metadata = {
            'composite_type' => composite_type,
            'source_patterns' => base_patterns.map(&:id)
          }
        end
      end
      
      def print_summary
        puts "\n=== Categorization Pattern Seeding Summary ==="
        puts "Created: #{@stats[:created]} patterns"
        puts "Updated: #{@stats[:updated]} patterns"
        puts "Skipped: #{@stats[:skipped]} patterns"
        
        if @stats[:errors].any?
          puts "\nErrors:"
          @stats[:errors].each do |error|
            puts "  - #{error[:pattern]}: #{error[:errors].join(', ')}"
          end
        end
        
        puts "\nTotal active patterns: #{CategorizationPattern.active.count}"
        puts "Categories covered: #{Category.joins(:categorization_patterns).distinct.count}/#{Category.count}"
        puts "Average patterns per category: #{(CategorizationPattern.count / Category.count.to_f).round(2)}"
      end
    end
  end
end
```

##### 4. Pattern Test Data
```yaml
# db/seeds/patterns/us_common.yml
patterns:
  # Food & Dining
  - category: "Food & Dining"
    type: "merchant"
    value: "starbucks"
    weight: 0.95
    locale: "en-US"
    tags: ["coffee", "cafe", "chain"]
    examples: ["STARBUCKS #12345", "STARBUCKS COFFEE"]
    test_data:
      usage_count: 1500
      success_count: 1425
  
  - category: "Food & Dining"
    type: "merchant"
    value: "mcdonalds"
    weight: 0.95
    locale: "en-US"
    tags: ["fast_food", "chain"]
    examples: ["MCDONALD'S F1234", "MCDONALDS"]
    test_data:
      usage_count: 1200
      success_count: 1140
  
  - category: "Food & Dining"
    type: "keyword"
    value: "restaurant"
    weight: 0.75
    locale: "en-US"
    tags: ["generic", "dining"]
    
  - category: "Food & Dining"
    type: "time"
    value: "11:30-13:30"
    weight: 0.5
    locale: "en-US"
    notes: "Lunch time pattern"
  
  # Transportation
  - category: "Transportation"
    type: "merchant"
    value: "uber"
    weight: 0.9
    locale: "en-US"
    tags: ["rideshare", "taxi"]
    examples: ["UBER *TRIP", "UBER BV"]
    test_data:
      usage_count: 800
      success_count: 760
  
  - category: "Transportation"
    type: "merchant"
    value: "shell"
    weight: 0.85
    locale: "en-US"
    tags: ["gas", "fuel"]
    examples: ["SHELL OIL 12345678", "SHELL SERVICE STATION"]
  
  - category: "Transportation"
    type: "amount_range"
    value: "30-80"
    weight: 0.4
    locale: "en-US"
    notes: "Typical gas tank fill-up range"
  
  # Groceries
  - category: "Groceries"
    type: "merchant"
    value: "whole foods"
    weight: 0.95
    locale: "en-US"
    tags: ["grocery", "organic", "amazon"]
    examples: ["WHOLEFDS", "WHOLE FOODS MARKET"]
  
  - category: "Groceries"
    type: "merchant"
    value: "trader joes"
    weight: 0.95
    locale: "en-US"
    tags: ["grocery", "specialty"]
    examples: ["TRADER JOE'S #123", "TRADER JOES"]
  
  # Shopping
  - category: "Shopping"
    type: "merchant"
    value: "amazon"
    weight: 0.85
    locale: "en-US"
    tags: ["online", "ecommerce", "marketplace"]
    examples: ["AMAZON.COM", "AMZN MKTP US"]
    test_data:
      usage_count: 2000
      success_count: 1700
  
  - category: "Shopping"
    type: "merchant"
    value: "target"
    weight: 0.85
    locale: "en-US"
    tags: ["retail", "department_store"]
    examples: ["TARGET 00012345", "TARGET.COM"]
  
  # Utilities
  - category: "Utilities"
    type: "merchant"
    value: "comcast"
    weight: 0.95
    locale: "en-US"
    tags: ["internet", "cable", "telecom"]
    examples: ["COMCAST CABLE", "COMCAST XFINITY"]
  
  - category: "Utilities"
    type: "amount_range"
    value: "100-300"
    weight: 0.6
    locale: "en-US"
    notes: "Typical monthly utility bill range"

# db/seeds/patterns/costa_rica.yml
patterns:
  # Food & Dining - Costa Rica
  - category: "Food & Dining"
    type: "merchant"
    value: "automercado"
    weight: 0.9
    locale: "es-CR"
    tags: ["supermercado", "comida"]
    examples: ["AUTOMERCADO LA SABANA", "AUTO MERCADO"]
  
  - category: "Food & Dining"
    type: "merchant"
    value: "mas x menos"
    weight: 0.9
    locale: "es-CR"
    tags: ["supermercado", "walmart"]
    examples: ["MAS X MENOS", "MASXMENOS"]
  
  # Transportation - Costa Rica
  - category: "Transportation"
    type: "merchant"
    value: "uber cr"
    weight: 0.9
    locale: "es-CR"
    tags: ["transporte", "taxi"]
    examples: ["UBER CR", "UBER COSTA RICA"]
  
  # Banking & Fees - Costa Rica
  - category: "Banking & Fees"
    type: "keyword"
    value: "comision"
    weight: 0.85
    locale: "es-CR"
    tags: ["banco", "cargo"]
  
  - category: "Banking & Fees"
    type: "merchant"
    value: "bac san jose"
    weight: 0.9
    locale: "es-CR"
    tags: ["banco", "cajero"]
    examples: ["BAC SAN JOSE", "BAC CREDOMATIC"]

# db/seeds/patterns/edge_cases.yml
patterns:
  # Ambiguous patterns that need context
  - category: "Shopping"
    type: "composite"
    value: '{"type":"merchant_amount","components":[{"type":"merchant","value":"walmart"},{"type":"amount_range","value":"0-50"}]}'
    weight: 0.7
    notes: "Small Walmart purchases are usually shopping"
  
  - category: "Groceries"
    type: "composite"
    value: '{"type":"merchant_amount","components":[{"type":"merchant","value":"walmart"},{"type":"amount_range","value":"50-200"}]}'
    weight: 0.8
    notes: "Large Walmart purchases are usually groceries"
  
  # Special characters handling
  - category: "Food & Dining"
    type: "regex"
    value: "^(mc)?donald[''']?s?\\b"
    weight: 0.9
    notes: "Handles McDonald's various spellings"
  
  # Multi-language patterns
  - category: "Transportation"
    type: "keyword"
    value: "taxi|cab|uber|lyft|grab|didi"
    weight: 0.8
    notes: "International ride services"
```

##### 5. Data Quality Monitoring Dashboard
```ruby
# app/controllers/admin/data_quality_controller.rb
module Admin
  class DataQualityController < ApplicationController
    before_action :require_admin!
    
    def index
      @audit_report = fetch_latest_audit_report
      @quality_metrics = calculate_quality_metrics
      @pattern_stats = gather_pattern_statistics
      @recommendations = generate_recommendations
    end
    
    def audit
      job = DataQualityAuditJob.perform_later
      
      redirect_to admin_data_quality_path, 
                  notice: "Data quality audit started (Job ID: #{job.job_id})"
    end
    
    def pattern_detail
      @pattern = CategorizationPattern.find(params[:id])
      @audit = Categorization::DataQuality::PatternAuditor.new(@pattern).audit
      @usage_stats = gather_pattern_usage_stats(@pattern)
      @similar_patterns = find_similar_patterns(@pattern)
    end
    
    def improve_pattern
      @pattern = CategorizationPattern.find(params[:id])
      improver = Categorization::DataQuality::PatternImprover.new(@pattern)
      
      if improver.can_improve?
        result = improver.improve!
        
        if result[:success]
          redirect_to admin_pattern_detail_path(@pattern),
                     notice: "Pattern improved: #{result[:changes].map { |c| c[:field] }.join(', ')}"
        else
          redirect_to admin_pattern_detail_path(@pattern),
                     alert: "Improvement failed: #{result[:errors].join(', ')}"
        end
      else
        redirect_to admin_pattern_detail_path(@pattern),
                   alert: "Pattern cannot be automatically improved"
      end
    end
    
    private
    
    def fetch_latest_audit_report
      Rails.cache.fetch('data_quality:latest_audit', expires_in: 1.hour) do
        Categorization::DataQuality::QualityManager.audit_and_improve
      end
    end
    
    def calculate_quality_metrics
      {
        overall_quality_score: CategorizationPattern.average(:quality_score)&.round || 0,
        pattern_coverage: calculate_pattern_coverage,
        success_rate: calculate_overall_success_rate,
        data_freshness: calculate_data_freshness,
        conflict_rate: calculate_conflict_rate
      }
    end
    
    def calculate_pattern_coverage
      categories_with_patterns = Category.joins(:categorization_patterns)
                                        .distinct
                                        .count
      
      total_categories = Category.count
      
      (categories_with_patterns.to_f / total_categories * 100).round(2)
    end
    
    def calculate_overall_success_rate
      patterns = CategorizationPattern.where('usage_count > 0')
      
      return 0 if patterns.empty?
      
      total_usage = patterns.sum(:usage_count)
      total_success = patterns.sum(:success_count)
      
      (total_success.to_f / total_usage * 100).round(2)
    end
    
    def calculate_data_freshness
      last_update = CategorizationPattern.maximum(:updated_at)
      
      return 'unknown' unless last_update
      
      days_old = (Date.current - last_update.to_date).to_i
      
      case days_old
      when 0..7 then 'fresh'
      when 8..30 then 'recent'
      when 31..90 then 'aging'
      else 'stale'
      end
    end
    
    def calculate_conflict_rate
      # Simplified conflict detection
      total_patterns = CategorizationPattern.active.count
      
      return 0 if total_patterns == 0
      
      # Count patterns with overlapping values in different categories
      conflicts = CategorizationPattern.active
                                      .group(:pattern_value, :pattern_type)
                                      .having('COUNT(DISTINCT category_id) > 1')
                                      .count
                                      .size
      
      (conflicts.to_f / total_patterns * 100).round(2)
    end
  end
end
```

##### 6. Migration for Data Quality Support
```ruby
# db/migrate/add_data_quality_fields_to_categorization_patterns.rb
class AddDataQualityFieldsToCategorizationPatterns < ActiveRecord::Migration[8.0]
  def change
    add_column :categorization_patterns, :quality_score, :integer, default: 70
    add_column :categorization_patterns, :last_matched_at, :datetime
    add_column :categorization_patterns, :average_confidence, :decimal, precision: 5, scale: 4
    add_column :categorization_patterns, :metadata, :jsonb, default: {}
    add_column :categorization_patterns, :retired, :boolean, default: false
    
    add_index :categorization_patterns, :quality_score
    add_index :categorization_patterns, :last_matched_at
    add_index :categorization_patterns, :retired
    add_index :categorization_patterns, :metadata, using: :gin
    
    # Add constraints
    add_check_constraint :categorization_patterns,
                        'quality_score >= 0 AND quality_score <= 100',
                        name: 'quality_score_range'
    
    add_check_constraint :categorization_patterns,
                        'success_rate >= 0 AND success_rate <= 1',
                        name: 'success_rate_range'
  end
end

# db/migrate/create_pattern_test_results.rb
class CreatePatternTestResults < ActiveRecord::Migration[8.0]
  def change
    create_table :pattern_test_results do |t|
      t.references :categorization_pattern, foreign_key: true, null: false
      t.string :test_type # 'accuracy', 'performance', 'coverage'
      t.jsonb :test_data
      t.jsonb :results
      t.boolean :passed, default: false
      t.decimal :score, precision: 5, scale: 2
      t.text :notes
      
      t.timestamps
    end
    
    add_index :pattern_test_results, :test_type
    add_index :pattern_test_results, :passed
    add_index :pattern_test_results, :created_at
  end
end
```

#### Testing Strategy

##### Unit Tests
```ruby
# spec/models/concerns/pattern_validation_spec.rb
RSpec.describe PatternValidation do
  let(:pattern) { build(:categorization_pattern) }
  
  describe 'normalization' do
    it 'normalizes merchant patterns' do
      pattern.pattern_type = 'merchant'
      pattern.pattern_value = '  STARBUCKS & CO.  '
      pattern.valid?
      
      expect(pattern.pattern_value).to eq('starbucks and co')
    end
    
    it 'normalizes amount ranges' do
      pattern.pattern_type = 'amount_range'
      pattern.pattern_value = '100 - 50'
      pattern.valid?
      
      expect(pattern.pattern_value).to eq('50.0-100.0')
    end
  end
  
  describe 'validation' do
    it 'validates regex patterns for ReDoS' do
      pattern.pattern_type = 'regex'
      pattern.pattern_value = '(a+)+'
      
      expect(pattern).not_to be_valid
      expect(pattern.errors[:pattern_value]).to include(/too complex/)
    end
    
    it 'detects duplicate patterns' do
      existing = create(:categorization_pattern, 
        pattern_type: 'merchant',
        pattern_value: 'starbucks'
      )
      
      pattern.pattern_type = 'merchant'
      pattern.pattern_value = 'starbucks'
      pattern.category = existing.category
      
      expect(pattern).not_to be_valid
      expect(pattern.errors[:pattern_value]).to include(/Duplicate/)
    end
  end
  
  describe 'quality scoring' do
    it 'calculates quality score based on performance' do
      pattern.usage_count = 100
      pattern.success_count = 85
      pattern.success_rate = 0.85
      pattern.valid?
      
      expect(pattern.quality_score).to be_between(70, 90)
    end
  end
end

# spec/services/categorization/data_quality/quality_manager_spec.rb
RSpec.describe Categorization::DataQuality::QualityManager do
  describe '.audit_and_improve' do
    before do
      create_list(:categorization_pattern, 10, :with_usage_stats)
      create_list(:categorization_pattern, 5, success_rate: 0.2) # Low quality
    end
    
    it 'audits all patterns' do
      report = described_class.audit_and_improve
      
      expect(report[:patterns_audited]).to eq(15)
      expect(report[:issues_found]).not_to be_empty
    end
    
    it 'improves low quality patterns' do
      report = described_class.audit_and_improve
      
      expect(report[:patterns_improved]).to be > 0
      expect(report[:quality_score_after]).to be > report[:quality_score_before]
    end
    
    it 'retires ineffective patterns' do
      create(:categorization_pattern, 
        usage_count: 100,
        success_count: 20,
        success_rate: 0.2
      )
      
      report = described_class.audit_and_improve
      
      expect(report[:patterns_retired]).to be > 0
    end
    
    it 'discovers new patterns from data' do
      create_list(:expense, 10, 
        merchant_name: 'NEW MERCHANT',
        category: nil
      )
      
      create_list(:expense, 5,
        merchant_name: 'NEW MERCHANT',
        category: create(:category)
      )
      
      report = described_class.audit_and_improve
      
      expect(report[:new_patterns_created]).to be > 0
    end
  end
end

# spec/db/seeds/categorization/pattern_seeder_spec.rb
RSpec.describe Seeds::Categorization::PatternSeeder do
  describe '.seed!' do
    it 'creates patterns from seed files' do
      expect {
        described_class.seed!(locale: :us_common)
      }.to change(CategorizationPattern, :count).by_at_least(20)
    end
    
    it 'respects safe mode' do
      described_class.seed!(locale: :us_common, mode: :safe)
      initial_count = CategorizationPattern.count
      
      expect {
        described_class.seed!(locale: :us_common, mode: :safe)
      }.not_to change(CategorizationPattern, :count)
    end
    
    it 'updates in update mode' do
      pattern = create(:categorization_pattern,
        pattern_type: 'merchant',
        pattern_value: 'starbucks',
        confidence_weight: 0.5
      )
      
      described_class.seed!(locale: :us_common, mode: :update)
      
      pattern.reload
      expect(pattern.confidence_weight).to eq(0.95)
    end
    
    it 'creates composite patterns' do
      described_class.seed!(locale: :us_common)
      
      composite_patterns = CategorizationPattern.where(pattern_type: 'composite')
      
      expect(composite_patterns).not_to be_empty
    end
  end
end
```

##### Integration Tests
```ruby
# spec/integration/data_quality_integration_spec.rb
RSpec.describe 'Data Quality Integration', type: :integration do
  before do
    # Seed initial data
    Seeds::Categorization::PatternSeeder.seed!
  end
  
  describe 'pattern lifecycle' do
    it 'promotes high-performing patterns' do
      pattern = create(:categorization_pattern, active: false)
      
      # Simulate successful usage
      100.times do
        create(:pattern_feedback,
          pattern: pattern,
          feedback_type: 'positive'
        )
      end
      
      pattern.update!(
        usage_count: 100,
        success_count: 95,
        success_rate: 0.95
      )
      
      # Run quality audit
      Categorization::DataQuality::QualityManager.audit_and_improve
      
      pattern.reload
      expect(pattern.active).to be true
      expect(pattern.quality_score).to be > 80
    end
    
    it 'retires low-performing patterns' do
      pattern = create(:categorization_pattern,
        active: true,
        usage_count: 100,
        success_count: 20,
        success_rate: 0.2
      )
      
      # Run quality audit
      Categorization::DataQuality::QualityManager.audit_and_improve
      
      pattern.reload
      expect(pattern.retired).to be true
    end
  end
  
  describe 'data quality monitoring' do
    it 'tracks quality metrics over time' do
      # Initial quality
      initial_metrics = calculate_quality_metrics
      
      # Improve patterns
      Categorization::DataQuality::QualityManager.audit_and_improve
      
      # Check improvement
      final_metrics = calculate_quality_metrics
      
      expect(final_metrics[:overall_quality_score]).to be >= initial_metrics[:overall_quality_score]
    end
  end
end
```

#### Monitoring Dashboard Views
```erb
<!-- app/views/admin/data_quality/index.html.erb -->
<div class="container mx-auto px-4 py-8">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold text-slate-900">Data Quality Dashboard</h1>
    <%= link_to "Run Audit", audit_admin_data_quality_path, 
        method: :post,
        class: "bg-teal-700 text-white px-4 py-2 rounded-lg hover:bg-teal-800" %>
  </div>
  
  <!-- Quality Metrics -->
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
      <div class="text-sm text-slate-600 mb-2">Overall Quality</div>
      <div class="text-3xl font-bold text-teal-700">
        <%= @quality_metrics[:overall_quality_score] %>%
      </div>
      <div class="mt-2">
        <div class="w-full bg-slate-200 rounded-full h-2">
          <div class="bg-teal-700 h-2 rounded-full" 
               style="width: <%= @quality_metrics[:overall_quality_score] %>%">
          </div>
        </div>
      </div>
    </div>
    
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
      <div class="text-sm text-slate-600 mb-2">Pattern Coverage</div>
      <div class="text-3xl font-bold <%= @quality_metrics[:pattern_coverage] >= 80 ? 'text-emerald-600' : 'text-amber-600' %>">
        <%= @quality_metrics[:pattern_coverage] %>%
      </div>
      <div class="text-xs text-slate-500 mt-2">
        Categories with patterns
      </div>
    </div>
    
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
      <div class="text-sm text-slate-600 mb-2">Success Rate</div>
      <div class="text-3xl font-bold <%= @quality_metrics[:success_rate] >= 85 ? 'text-emerald-600' : 'text-rose-600' %>">
        <%= @quality_metrics[:success_rate] %>%
      </div>
      <div class="text-xs text-slate-500 mt-2">
        Pattern accuracy
      </div>
    </div>
    
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
      <div class="text-sm text-slate-600 mb-2">Data Freshness</div>
      <div class="text-2xl font-bold">
        <span class="<%= freshness_color_class(@quality_metrics[:data_freshness]) %>">
          <%= @quality_metrics[:data_freshness].capitalize %>
        </span>
      </div>
      <div class="text-xs text-slate-500 mt-2">
        Last pattern update
      </div>
    </div>
  </div>
  
  <!-- Pattern Statistics -->
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-8">
    <h2 class="text-lg font-semibold text-slate-900 mb-4">Pattern Statistics</h2>
    
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <div>
        <div class="text-2xl font-bold text-slate-900">
          <%= @pattern_stats[:total_patterns] %>
        </div>
        <div class="text-sm text-slate-600">Total Patterns</div>
      </div>
      
      <div>
        <div class="text-2xl font-bold text-emerald-600">
          <%= @pattern_stats[:active_patterns] %>
        </div>
        <div class="text-sm text-slate-600">Active</div>
      </div>
      
      <div>
        <div class="text-2xl font-bold text-amber-600">
          <%= @pattern_stats[:needs_review] %>
        </div>
        <div class="text-sm text-slate-600">Needs Review</div>
      </div>
      
      <div>
        <div class="text-2xl font-bold text-rose-600">
          <%= @pattern_stats[:conflicts] %>
        </div>
        <div class="text-sm text-slate-600">Conflicts</div>
      </div>
    </div>
  </div>
  
  <!-- Recommendations -->
  <% if @recommendations.any? %>
    <div class="bg-amber-50 border border-amber-200 rounded-xl p-6">
      <h2 class="text-lg font-semibold text-amber-900 mb-4">
        Recommendations
      </h2>
      <ul class="space-y-2">
        <% @recommendations.each do |recommendation| %>
          <li class="flex items-start">
            <svg class="w-5 h-5 text-amber-600 mt-0.5 mr-2" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
            </svg>
            <span class="text-amber-800"><%= recommendation %></span>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>
</div>
```

#### Rollout Plan
1. **Phase 1**: Deploy validation system to staging
2. **Phase 2**: Run initial data audit and baseline quality metrics
3. **Phase 3**: Seed production with validated patterns
4. **Phase 4**: Enable automated quality management
5. **Phase 5**: Monitor and tune based on real usage

#### Success Metrics
- Pattern quality score: >80% average
- Category coverage: 100%
- Pattern success rate: >85%
- Conflict rate: <5%
- Automated discovery rate: 10+ new patterns/week
- Data freshness: Updates within 7 days

## UX Specifications for Data Quality Management Interface

### Overview
The Data Quality Management Interface provides administrators with comprehensive tools to monitor, analyze, and improve categorization pattern quality. This interface emphasizes data visualization, actionable insights, and guided improvement workflows to maintain high-quality categorization data.

### Information Architecture

#### Navigation Structure
```
Data Quality Hub (Root)
├── Quality Overview Dashboard
│   ├── Quality Metrics
│   ├── Pattern Health
│   └── Recommendations
├── Pattern Management
│   ├── Pattern Explorer
│   ├── Conflict Resolution
│   ├── Pattern Testing
│   └── Bulk Operations
├── Data Validation
│   ├── Validation Results
│   ├── Quality Audits
│   └── Remediation Queue
└── Seed Management
    ├── Seed Data Editor
    ├── Import/Export
    └── Version Control
```

### UI Components and Design Specifications

#### 1. Data Quality Overview Dashboard

##### Layout and Structure
```erb
<!-- app/views/admin/categorization/data_quality/index.html.erb -->
<div class="min-h-screen bg-slate-50" data-controller="data-quality-dashboard"
     data-data-quality-dashboard-auto-audit-value="true">
  
  <!-- Header with Quality Score -->
  <div class="bg-gradient-to-r from-teal-700 to-teal-800 text-white">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="flex justify-between items-start">
        <div>
          <h1 class="text-2xl font-bold mb-2">Data Quality Management</h1>
          <p class="text-teal-100">Monitor and improve categorization pattern quality</p>
        </div>
        
        <!-- Overall Quality Score -->
        <div class="text-right">
          <div class="text-4xl font-bold" data-data-quality-dashboard-target="overallScore">
            --
          </div>
          <div class="text-sm text-teal-100">Overall Quality Score</div>
          <div class="mt-2 w-32 bg-teal-900 rounded-full h-2">
            <div class="bg-white h-2 rounded-full transition-all duration-500"
                 data-data-quality-dashboard-target="scoreBar"
                 style="width: 0%"></div>
          </div>
        </div>
      </div>
      
      <!-- Quick Actions Bar -->
      <div class="mt-6 flex flex-wrap gap-3">
        <button data-action="click->data-quality-dashboard#runAudit"
                class="inline-flex items-center px-4 py-2 bg-white text-teal-700 rounded-lg font-medium hover:bg-teal-50 transition-colors">
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
          </svg>
          Run Quality Audit
        </button>
        
        <button data-action="click->data-quality-dashboard#autoImprove"
                class="inline-flex items-center px-4 py-2 bg-white/20 text-white rounded-lg font-medium hover:bg-white/30 transition-colors">
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/>
          </svg>
          Auto-Improve Patterns
        </button>
        
        <button data-action="click->data-quality-dashboard#exportReport"
                class="inline-flex items-center px-4 py-2 bg-white/20 text-white rounded-lg font-medium hover:bg-white/30 transition-colors">
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
          </svg>
          Export Quality Report
        </button>
      </div>
    </div>
  </div>

  <!-- Main Content -->
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <!-- Quality Metrics Grid -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
      <!-- Pattern Coverage -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="p-2 bg-teal-100 rounded-lg">
            <svg class="w-6 h-6 text-teal-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
            </svg>
          </div>
          <span class="text-xs font-medium text-emerald-600">+2%</span>
        </div>
        <div class="text-2xl font-bold text-slate-900" data-data-quality-dashboard-target="patternCoverage">--</div>
        <div class="text-sm text-slate-600 mt-1">Pattern Coverage</div>
        <div class="mt-3 text-xs text-slate-500">
          <span data-data-quality-dashboard-target="coveredCategories">--</span> of 
          <span data-data-quality-dashboard-target="totalCategories">--</span> categories
        </div>
      </div>

      <!-- Success Rate -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="p-2 bg-emerald-100 rounded-lg">
            <svg class="w-6 h-6 text-emerald-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </div>
          <div data-data-quality-dashboard-target="successTrend" class="text-xs font-medium">
            <!-- Trend indicator -->
          </div>
        </div>
        <div class="text-2xl font-bold text-slate-900" data-data-quality-dashboard-target="successRate">--</div>
        <div class="text-sm text-slate-600 mt-1">Success Rate</div>
        <div class="mt-3 text-xs text-slate-500">
          Last 7 days average
        </div>
      </div>

      <!-- Data Freshness -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="p-2 bg-amber-100 rounded-lg">
            <svg class="w-6 h-6 text-amber-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
            </svg>
          </div>
          <span class="px-2 py-1 text-xs font-medium rounded-full"
                data-data-quality-dashboard-target="freshnessStatus">
            <!-- Status badge -->
          </span>
        </div>
        <div class="text-2xl font-bold text-slate-900" data-data-quality-dashboard-target="avgAge">--</div>
        <div class="text-sm text-slate-600 mt-1">Avg Pattern Age</div>
        <div class="mt-3 text-xs text-slate-500">
          <span data-data-quality-dashboard-target="stalePatterns">--</span> patterns need update
        </div>
      </div>

      <!-- Conflict Rate -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="p-2 bg-rose-100 rounded-lg">
            <svg class="w-6 h-6 text-rose-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
            </svg>
          </div>
          <button data-action="click->data-quality-dashboard#viewConflicts"
                  class="text-xs text-rose-700 hover:text-rose-800 font-medium">
            View All
          </button>
        </div>
        <div class="text-2xl font-bold text-slate-900" data-data-quality-dashboard-target="conflictCount">--</div>
        <div class="text-sm text-slate-600 mt-1">Active Conflicts</div>
        <div class="mt-3 text-xs text-slate-500">
          <span data-data-quality-dashboard-target="conflictRate">--</span>% conflict rate
        </div>
      </div>
    </div>

    <!-- Pattern Health Matrix -->
    <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-slate-900">Pattern Health Matrix</h2>
        <div class="flex items-center space-x-3">
          <!-- View Options -->
          <div class="flex bg-slate-100 rounded-lg p-0.5" role="tablist">
            <button class="px-3 py-1 text-sm font-medium rounded-md bg-white text-slate-900"
                    data-action="click->data-quality-dashboard#switchMatrixView"
                    data-view="category">By Category</button>
            <button class="px-3 py-1 text-sm font-medium text-slate-600"
                    data-action="click->data-quality-dashboard#switchMatrixView"
                    data-view="type">By Type</button>
            <button class="px-3 py-1 text-sm font-medium text-slate-600"
                    data-action="click->data-quality-dashboard#switchMatrixView"
                    data-view="age">By Age</button>
          </div>
        </div>
      </div>
      
      <!-- Interactive Health Matrix -->
      <div class="relative">
        <div class="grid grid-cols-12 gap-1" data-data-quality-dashboard-target="healthMatrix">
          <!-- Matrix cells will be dynamically generated -->
        </div>
        
        <!-- Tooltip on hover -->
        <div class="absolute hidden bg-slate-900 text-white text-xs rounded-lg px-2 py-1 pointer-events-none z-10"
             data-data-quality-dashboard-target="matrixTooltip">
          <!-- Tooltip content -->
        </div>
      </div>
      
      <!-- Matrix Legend -->
      <div class="mt-4 flex items-center justify-between text-xs">
        <div class="flex items-center space-x-4">
          <div class="flex items-center">
            <div class="w-4 h-4 bg-emerald-500 rounded mr-1"></div>
            <span class="text-slate-600">Excellent (90-100%)</span>
          </div>
          <div class="flex items-center">
            <div class="w-4 h-4 bg-teal-500 rounded mr-1"></div>
            <span class="text-slate-600">Good (70-90%)</span>
          </div>
          <div class="flex items-center">
            <div class="w-4 h-4 bg-amber-500 rounded mr-1"></div>
            <span class="text-slate-600">Fair (50-70%)</span>
          </div>
          <div class="flex items-center">
            <div class="w-4 h-4 bg-rose-500 rounded mr-1"></div>
            <span class="text-slate-600">Poor (<50%)</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Recommendations Panel -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
      <!-- AI-Powered Recommendations -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-slate-900">Smart Recommendations</h3>
          <button data-action="click->data-quality-dashboard#refreshRecommendations"
                  class="p-1 text-slate-600 hover:text-slate-900">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
          </button>
        </div>
        
        <div class="space-y-3" data-data-quality-dashboard-target="recommendations">
          <!-- Recommendation Cards -->
          <div class="p-4 bg-amber-50 border border-amber-200 rounded-lg">
            <div class="flex items-start">
              <div class="flex-shrink-0">
                <svg class="w-5 h-5 text-amber-600 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
                </svg>
              </div>
              <div class="ml-3 flex-1">
                <h4 class="text-sm font-medium text-amber-900">Merge Similar Patterns</h4>
                <p class="mt-1 text-sm text-amber-700">
                  Found 12 similar patterns for "Starbucks" that could be merged
                </p>
                <div class="mt-2 flex space-x-2">
                  <button class="text-xs font-medium text-amber-900 hover:text-amber-800">
                    Review Patterns
                  </button>
                  <span class="text-amber-400">•</span>
                  <button class="text-xs font-medium text-amber-900 hover:text-amber-800">
                    Auto-Merge
                  </button>
                </div>
              </div>
            </div>
          </div>
          
          <!-- More recommendations... -->
        </div>
      </div>

      <!-- Recent Activity Feed -->
      <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-slate-900">Recent Quality Actions</h3>
          <span class="text-xs text-slate-500">Auto-updates</span>
        </div>
        
        <div class="space-y-3 max-h-96 overflow-y-auto" data-data-quality-dashboard-target="activityFeed">
          <!-- Activity Items -->
          <div class="flex items-start space-x-3 pb-3 border-b border-slate-100">
            <div class="flex-shrink-0 w-8 h-8 bg-emerald-100 rounded-full flex items-center justify-center">
              <svg class="w-4 h-4 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm text-slate-900">
                Pattern quality improved from 72% to 85%
              </p>
              <p class="text-xs text-slate-500 mt-1">
                Food & Dining • 2 minutes ago
              </p>
            </div>
          </div>
          <!-- More activity items... -->
        </div>
      </div>
    </div>

    <!-- Pattern Management Table -->
    <div class="bg-white rounded-xl shadow-sm border border-slate-200">
      <div class="px-6 py-4 border-b border-slate-200">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">Pattern Management</h3>
          <div class="flex items-center space-x-3">
            <!-- Search -->
            <div class="relative">
              <input type="text"
                     placeholder="Search patterns..."
                     data-action="input->data-quality-dashboard#searchPatterns"
                     class="pl-9 pr-3 py-2 bg-white border border-slate-300 rounded-lg text-sm focus:ring-teal-500 focus:border-teal-500">
              <svg class="absolute left-3 top-2.5 w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
              </svg>
            </div>
            
            <!-- Filters -->
            <select data-action="change->data-quality-dashboard#filterPatterns"
                    class="text-sm bg-white border border-slate-300 rounded-lg px-3 py-2">
              <option value="all">All Patterns</option>
              <option value="low_quality">Low Quality</option>
              <option value="conflicts">Has Conflicts</option>
              <option value="unused">Unused</option>
              <option value="stale">Stale</option>
            </select>
            
            <!-- Bulk Actions -->
            <button data-action="click->data-quality-dashboard#showBulkActions"
                    class="px-4 py-2 bg-teal-700 text-white rounded-lg text-sm font-medium hover:bg-teal-800">
              Bulk Actions
            </button>
          </div>
        </div>
      </div>
      
      <!-- Table -->
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-slate-200">
          <thead class="bg-slate-50">
            <tr>
              <th scope="col" class="w-12 px-6 py-3">
                <input type="checkbox" 
                       data-action="change->data-quality-dashboard#selectAll"
                       class="rounded border-slate-300 text-teal-700 focus:ring-teal-500">
              </th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                Pattern
              </th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                Category
              </th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                Quality Score
              </th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                Usage
              </th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                Success Rate
              </th>
              <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                Status
              </th>
              <th scope="col" class="relative px-6 py-3">
                <span class="sr-only">Actions</span>
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-slate-200" data-data-quality-dashboard-target="patternTableBody">
            <!-- Pattern rows will be dynamically inserted -->
          </tbody>
        </table>
      </div>
      
      <!-- Pagination -->
      <div class="px-6 py-4 border-t border-slate-200">
        <div class="flex items-center justify-between">
          <div class="text-sm text-slate-700">
            Showing <span class="font-medium">1</span> to <span class="font-medium">10</span> of{' '}
            <span class="font-medium">97</span> patterns
          </div>
          <div class="flex space-x-2">
            <button class="px-3 py-1 bg-white border border-slate-300 rounded-lg text-sm hover:bg-slate-50">
              Previous
            </button>
            <button class="px-3 py-1 bg-teal-700 text-white rounded-lg text-sm">1</button>
            <button class="px-3 py-1 bg-white border border-slate-300 rounded-lg text-sm hover:bg-slate-50">2</button>
            <button class="px-3 py-1 bg-white border border-slate-300 rounded-lg text-sm hover:bg-slate-50">3</button>
            <button class="px-3 py-1 bg-white border border-slate-300 rounded-lg text-sm hover:bg-slate-50">
              Next
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Pattern Detail Modal -->
  <div class="fixed inset-0 z-50 hidden" data-data-quality-dashboard-target="patternModal">
    <div class="fixed inset-0 bg-slate-900 bg-opacity-50" data-action="click->data-quality-dashboard#closeModal"></div>
    
    <div class="fixed inset-0 overflow-y-auto">
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-white rounded-xl shadow-xl max-w-2xl w-full max-h-[90vh] overflow-hidden">
          <!-- Modal Header -->
          <div class="px-6 py-4 border-b border-slate-200">
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold text-slate-900">Pattern Details</h3>
              <button data-action="click->data-quality-dashboard#closeModal"
                      class="p-1 text-slate-400 hover:text-slate-600">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                </svg>
              </button>
            </div>
          </div>
          
          <!-- Modal Body -->
          <div class="px-6 py-4 overflow-y-auto max-h-[calc(90vh-8rem)]">
            <!-- Pattern Information -->
            <div class="space-y-6">
              <!-- Basic Info -->
              <div>
                <h4 class="text-sm font-medium text-slate-900 mb-3">Basic Information</h4>
                <dl class="grid grid-cols-2 gap-4">
                  <div>
                    <dt class="text-xs text-slate-500">Pattern Type</dt>
                    <dd class="mt-1 text-sm font-medium text-slate-900" data-data-quality-dashboard-target="modalPatternType">--</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-slate-500">Pattern Value</dt>
                    <dd class="mt-1 text-sm font-medium text-slate-900" data-data-quality-dashboard-target="modalPatternValue">--</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-slate-500">Category</dt>
                    <dd class="mt-1 text-sm font-medium text-slate-900" data-data-quality-dashboard-target="modalCategory">--</dd>
                  </div>
                  <div>
                    <dt class="text-xs text-slate-500">Confidence Weight</dt>
                    <dd class="mt-1 text-sm font-medium text-slate-900" data-data-quality-dashboard-target="modalConfidence">--</dd>
                  </div>
                </dl>
              </div>
              
              <!-- Quality Metrics -->
              <div>
                <h4 class="text-sm font-medium text-slate-900 mb-3">Quality Metrics</h4>
                <div class="grid grid-cols-3 gap-4">
                  <div class="text-center p-4 bg-slate-50 rounded-lg">
                    <div class="text-2xl font-bold text-teal-700" data-data-quality-dashboard-target="modalQualityScore">--</div>
                    <div class="text-xs text-slate-600 mt-1">Quality Score</div>
                  </div>
                  <div class="text-center p-4 bg-slate-50 rounded-lg">
                    <div class="text-2xl font-bold text-emerald-700" data-data-quality-dashboard-target="modalSuccessRate">--</div>
                    <div class="text-xs text-slate-600 mt-1">Success Rate</div>
                  </div>
                  <div class="text-center p-4 bg-slate-50 rounded-lg">
                    <div class="text-2xl font-bold text-amber-700" data-data-quality-dashboard-target="modalUsageCount">--</div>
                    <div class="text-xs text-slate-600 mt-1">Usage Count</div>
                  </div>
                </div>
              </div>
              
              <!-- Test Pattern -->
              <div>
                <h4 class="text-sm font-medium text-slate-900 mb-3">Test Pattern</h4>
                <div class="space-y-3">
                  <input type="text"
                         placeholder="Enter test text..."
                         data-data-quality-dashboard-target="testInput"
                         class="w-full px-3 py-2 bg-white border border-slate-300 rounded-lg text-sm">
                  <button data-action="click->data-quality-dashboard#testPattern"
                          class="w-full px-4 py-2 bg-teal-700 text-white rounded-lg text-sm font-medium hover:bg-teal-800">
                    Test Pattern Match
                  </button>
                  <div class="hidden p-4 bg-slate-50 rounded-lg" data-data-quality-dashboard-target="testResult">
                    <!-- Test results -->
                  </div>
                </div>
              </div>
              
              <!-- Improvement Suggestions -->
              <div>
                <h4 class="text-sm font-medium text-slate-900 mb-3">Improvement Suggestions</h4>
                <div class="space-y-2" data-data-quality-dashboard-target="suggestions">
                  <!-- Suggestions will be inserted here -->
                </div>
              </div>
            </div>
          </div>
          
          <!-- Modal Footer -->
          <div class="px-6 py-4 border-t border-slate-200 bg-slate-50">
            <div class="flex justify-between">
              <button data-action="click->data-quality-dashboard#deletePattern"
                      class="px-4 py-2 bg-rose-600 text-white rounded-lg text-sm font-medium hover:bg-rose-700">
                Delete Pattern
              </button>
              <div class="flex space-x-3">
                <button data-action="click->data-quality-dashboard#closeModal"
                        class="px-4 py-2 bg-white border border-slate-300 rounded-lg text-sm font-medium text-slate-700 hover:bg-slate-50">
                  Cancel
                </button>
                <button data-action="click->data-quality-dashboard#savePattern"
                        class="px-4 py-2 bg-teal-700 text-white rounded-lg text-sm font-medium hover:bg-teal-800">
                  Save Changes
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

##### Stimulus Controller for Data Quality Management
```javascript
// app/javascript/controllers/data_quality_dashboard_controller.js
import { Controller } from "@hotwired/stimulus"
import { Chart } from "chart.js/auto"

export default class extends Controller {
  static targets = [
    "overallScore", "scoreBar",
    "patternCoverage", "coveredCategories", "totalCategories",
    "successRate", "successTrend",
    "avgAge", "stalePatterns", "freshnessStatus",
    "conflictCount", "conflictRate",
    "healthMatrix", "matrixTooltip",
    "recommendations", "activityFeed",
    "patternTableBody", "patternModal",
    "modalPatternType", "modalPatternValue", "modalCategory",
    "modalConfidence", "modalQualityScore", "modalSuccessRate",
    "modalUsageCount", "testInput", "testResult", "suggestions"
  ]
  
  static values = {
    autoAudit: Boolean
  }
  
  connect() {
    this.loadDashboardData()
    this.initializeHealthMatrix()
    this.startActivityFeed()
    
    if (this.autoAuditValue) {
      this.scheduleAutoAudit()
    }
  }
  
  disconnect() {
    this.stopActivityFeed()
    this.cancelAutoAudit()
  }
  
  async loadDashboardData() {
    try {
      const response = await fetch('/api/v1/categorization/data_quality/metrics')
      const data = await response.json()
      
      this.updateMetrics(data.metrics)
      this.updateRecommendations(data.recommendations)
      this.updatePatternTable(data.patterns)
    } catch (error) {
      console.error('Failed to load dashboard data:', error)
      this.showError('Failed to load quality metrics')
    }
  }
  
  updateMetrics(metrics) {
    // Animate overall score
    this.animateScore(metrics.overall_score)
    
    // Update coverage metrics
    this.patternCoverageTarget.textContent = `${metrics.pattern_coverage}%`
    this.coveredCategoriesTarget.textContent = metrics.covered_categories
    this.totalCategoriesTarget.textContent = metrics.total_categories
    
    // Update success rate with trend
    this.successRateTarget.textContent = `${metrics.success_rate}%`
    this.updateTrend(this.successTrendTarget, metrics.success_trend)
    
    // Update freshness
    this.avgAgeTarget.textContent = `${metrics.avg_age} days`
    this.stalePattersTarget.textContent = metrics.stale_patterns
    this.updateFreshnessStatus(metrics.freshness_status)
    
    // Update conflicts
    this.conflictCountTarget.textContent = metrics.conflict_count
    this.conflictRateTarget.textContent = metrics.conflict_rate
  }
  
  animateScore(targetScore) {
    const currentScore = parseInt(this.overallScoreTarget.textContent) || 0
    const duration = 1000 // 1 second
    const steps = 30
    const increment = (targetScore - currentScore) / steps
    let step = 0
    
    const animation = setInterval(() => {
      step++
      const newScore = Math.round(currentScore + increment * step)
      this.overallScoreTarget.textContent = newScore
      this.scoreBarTarget.style.width = `${newScore}%`
      
      // Update color based on score
      this.updateScoreColor(newScore)
      
      if (step >= steps) {
        clearInterval(animation)
        this.overallScoreTarget.textContent = targetScore
        this.scoreBarTarget.style.width = `${targetScore}%`
      }
    }, duration / steps)
  }
  
  updateScoreColor(score) {
    const bar = this.scoreBarTarget
    bar.classList.remove('bg-rose-500', 'bg-amber-500', 'bg-teal-500', 'bg-emerald-500')
    
    if (score >= 90) {
      bar.classList.add('bg-emerald-500')
    } else if (score >= 70) {
      bar.classList.add('bg-teal-500')
    } else if (score >= 50) {
      bar.classList.add('bg-amber-500')
    } else {
      bar.classList.add('bg-rose-500')
    }
  }
  
  initializeHealthMatrix() {
    // Create interactive health matrix visualization
    const matrix = this.healthMatrixTarget
    const data = this.generateMatrixData()
    
    data.forEach(row => {
      row.forEach(cell => {
        const element = this.createMatrixCell(cell)
        matrix.appendChild(element)
      })
    })
  }
  
  createMatrixCell(data) {
    const cell = document.createElement('div')
    cell.className = `aspect-square rounded cursor-pointer transition-all hover:scale-110 ${this.getHealthColor(data.score)}`
    cell.dataset.categoryId = data.categoryId
    cell.dataset.score = data.score
    
    // Add hover interaction
    cell.addEventListener('mouseenter', (e) => {
      this.showMatrixTooltip(e, data)
    })
    
    cell.addEventListener('mouseleave', () => {
      this.hideMatrixTooltip()
    })
    
    cell.addEventListener('click', () => {
      this.drillDownCategory(data.categoryId)
    })
    
    return cell
  }
  
  getHealthColor(score) {
    if (score >= 90) return 'bg-emerald-500'
    if (score >= 70) return 'bg-teal-500'
    if (score >= 50) return 'bg-amber-500'
    return 'bg-rose-500'
  }
  
  showMatrixTooltip(event, data) {
    const tooltip = this.matrixTooltipTarget
    tooltip.innerHTML = `
      <div class="font-medium">${data.categoryName}</div>
      <div class="text-xs mt-1">Quality: ${data.score}%</div>
      <div class="text-xs">Patterns: ${data.patternCount}</div>
    `
    
    const rect = event.target.getBoundingClientRect()
    tooltip.style.left = `${rect.left + rect.width / 2}px`
    tooltip.style.top = `${rect.top - 40}px`
    tooltip.classList.remove('hidden')
  }
  
  hideMatrixTooltip() {
    this.matrixTooltipTarget.classList.add('hidden')
  }
  
  async runAudit() {
    // Show loading state
    this.showLoading('Running quality audit...')
    
    try {
      const response = await fetch('/api/v1/categorization/data_quality/audit', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const result = await response.json()
      
      // Update dashboard with audit results
      this.updateMetrics(result.metrics)
      this.showAuditResults(result)
      
      this.showSuccess('Quality audit completed successfully')
    } catch (error) {
      console.error('Audit failed:', error)
      this.showError('Failed to run quality audit')
    }
  }
  
  showAuditResults(results) {
    // Create and show audit results modal
    const modal = this.createAuditResultsModal(results)
    document.body.appendChild(modal)
  }
  
  async autoImprove() {
    if (!confirm('This will automatically improve low-quality patterns. Continue?')) {
      return
    }
    
    this.showLoading('Improving patterns...')
    
    try {
      const response = await fetch('/api/v1/categorization/data_quality/auto_improve', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const result = await response.json()
      
      this.showSuccess(`Improved ${result.improved_count} patterns`)
      this.loadDashboardData() // Refresh data
    } catch (error) {
      console.error('Auto-improve failed:', error)
      this.showError('Failed to improve patterns')
    }
  }
  
  testPattern() {
    const testText = this.testInputTarget.value
    if (!testText) return
    
    // Simulate pattern testing
    const result = this.performPatternTest(testText)
    
    this.testResultTarget.classList.remove('hidden')
    this.testResultTarget.innerHTML = `
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-slate-900">Test Result</span>
        <span class="px-2 py-1 text-xs font-medium rounded-full ${result.matches ? 'bg-emerald-100 text-emerald-700' : 'bg-rose-100 text-rose-700'}">
          ${result.matches ? 'Match' : 'No Match'}
        </span>
      </div>
      ${result.matches ? `
        <div class="text-sm text-slate-600">
          <p>Confidence: ${result.confidence}%</p>
          <p>Match Type: ${result.matchType}</p>
        </div>
      ` : `
        <div class="text-sm text-slate-600">
          Pattern did not match the test text
        </div>
      `}
    `
  }
}
```

### User Journey Flows

#### Journey 1: Quality Audit and Improvement
1. **Dashboard Entry**: Admin accesses Data Quality Management
2. **Initial Assessment**:
   - Reviews overall quality score
   - Checks key metrics (coverage, success rate, conflicts)
   - Views health matrix for problem areas
3. **Run Audit**:
   - Clicks "Run Quality Audit"
   - System analyzes all patterns
   - Results displayed with recommendations
4. **Review Recommendations**:
   - Views AI-powered suggestions
   - Prioritizes improvements by impact
5. **Take Action**:
   - Option A: Auto-improve patterns
   - Option B: Manual pattern editing
   - Option C: Bulk operations
6. **Validation**:
   - Tests improved patterns
   - Reviews quality score changes
   - Monitors success rate impact

#### Journey 2: Conflict Resolution
1. **Conflict Detection**: Dashboard shows conflict count
2. **View Conflicts**: Admin clicks to see conflict details
3. **Analyze Conflicts**:
   - Reviews overlapping patterns
   - Examines affected categories
   - Checks usage statistics
4. **Resolution Strategy**:
   - Merge similar patterns
   - Adjust pattern specificity
   - Deactivate redundant patterns
5. **Apply Resolution**:
   - Makes changes
   - Tests affected patterns
   - Validates no new conflicts
6. **Monitor Impact**:
   - Tracks success rate changes
   - Reviews categorization accuracy

### Accessibility Requirements

#### WCAG AA Compliance
1. **Visual Indicators**:
   - Never rely solely on color
   - Include text labels with color coding
   - Provide patterns/textures for charts

2. **Interactive Elements**:
   - All controls keyboard accessible
   - Clear focus indicators
   - Logical tab order
   - Keyboard shortcuts documented

3. **Data Tables**:
   ```html
   <table role="table" aria-label="Pattern quality data">
     <caption class="sr-only">
       List of categorization patterns with quality metrics
     </caption>
     <thead>
       <tr role="row">
         <th scope="col" aria-sort="ascending">Pattern</th>
         <th scope="col">Quality Score</th>
       </tr>
     </thead>
   </table>
   ```

4. **Form Controls**:
   - Clear labels for all inputs
   - Error messages associated with fields
   - Required fields marked clearly
   - Help text for complex inputs

### Mobile Responsive Design

#### Touch-Optimized Interface
```erb
<!-- Mobile pattern card -->
<div class="block sm:hidden">
  <div class="bg-white rounded-lg shadow-sm p-4 mb-3">
    <div class="flex justify-between items-start mb-2">
      <div>
        <h4 class="font-medium text-slate-900">starbucks</h4>
        <p class="text-xs text-slate-600">Merchant Pattern</p>
      </div>
      <div class="text-right">
        <div class="text-lg font-bold text-teal-700">85%</div>
        <div class="text-xs text-slate-500">Quality</div>
      </div>
    </div>
    
    <div class="grid grid-cols-3 gap-2 text-center py-2 border-t border-slate-100">
      <div>
        <div class="text-sm font-medium">92%</div>
        <div class="text-xs text-slate-500">Success</div>
      </div>
      <div>
        <div class="text-sm font-medium">1.2k</div>
        <div class="text-xs text-slate-500">Usage</div>
      </div>
      <div>
        <div class="text-sm font-medium">3d</div>
        <div class="text-xs text-slate-500">Age</div>
      </div>
    </div>
    
    <div class="flex space-x-2 mt-3">
      <button class="flex-1 px-3 py-2 bg-teal-700 text-white text-sm rounded">
        Edit
      </button>
      <button class="flex-1 px-3 py-2 bg-slate-200 text-slate-700 text-sm rounded">
        Test
      </button>
    </div>
  </div>
</div>
```

### Performance Optimization

#### Lazy Loading and Virtualization
```javascript
// Virtual scrolling for large pattern lists
class VirtualPatternList {
  constructor(container, patterns) {
    this.container = container
    this.patterns = patterns
    this.itemHeight = 60
    this.visibleItems = Math.ceil(container.clientHeight / this.itemHeight)
    this.scrollTop = 0
    
    this.init()
  }
  
  init() {
    // Create virtual scroll container
    this.scrollContainer = document.createElement('div')
    this.scrollContainer.style.height = `${this.patterns.length * this.itemHeight}px`
    
    // Render visible items
    this.render()
    
    // Attach scroll listener
    this.container.addEventListener('scroll', this.throttle(() => {
      this.handleScroll()
    }, 16))
  }
  
  render() {
    const startIndex = Math.floor(this.scrollTop / this.itemHeight)
    const endIndex = Math.min(
      startIndex + this.visibleItems + 1,
      this.patterns.length
    )
    
    // Clear and render visible patterns
    this.container.innerHTML = ''
    
    for (let i = startIndex; i < endIndex; i++) {
      const element = this.createPatternElement(this.patterns[i])
      element.style.position = 'absolute'
      element.style.top = `${i * this.itemHeight}px`
      this.container.appendChild(element)
    }
  }
}
```

#### Optimized Data Updates
```javascript
// Differential updates for real-time data
class DataQualityUpdater {
  constructor() {
    this.previousData = {}
    this.updateQueue = []
    this.isUpdating = false
  }
  
  queueUpdate(newData) {
    this.updateQueue.push(newData)
    
    if (!this.isUpdating) {
      this.processUpdates()
    }
  }
  
  async processUpdates() {
    this.isUpdating = true
    
    while (this.updateQueue.length > 0) {
      const data = this.updateQueue.shift()
      await this.applyDifferentialUpdate(data)
    }
    
    this.isUpdating = false
  }
  
  applyDifferentialUpdate(newData) {
    // Only update changed values
    const changes = this.findChanges(this.previousData, newData)
    
    changes.forEach(change => {
      this.updateElement(change.path, change.value)
    })
    
    this.previousData = newData
  }
}
```