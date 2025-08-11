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
