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
