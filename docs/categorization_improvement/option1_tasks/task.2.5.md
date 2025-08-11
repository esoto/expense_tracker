### Task 2.5: Pattern Analytics Dashboard
**Priority**: Medium  
**Estimated Hours**: 5  
**Dependencies**: Tasks 2.1-2.4  

#### Description
Create dashboard showing pattern performance and system metrics.

#### Acceptance Criteria
- [ ] Overall accuracy metrics
- [ ] Per-category performance breakdown
- [ ] Most/least effective patterns
- [ ] Trend charts over time
- [ ] Pattern usage heatmap
- [ ] Export functionality
- [ ] Real-time updates

#### Technical Implementation
```ruby
# app/services/pattern_analytics.rb
class PatternAnalytics
  def dashboard_metrics
    {
      overall: overall_metrics,
      by_category: category_breakdown,
      top_patterns: top_performing_patterns,
      weak_patterns: patterns_needing_review,
      trends: calculate_trends,
      recent_activity: recent_corrections
    }
  end
  
  private
  
  def overall_metrics
    total = CategorizationFeedback.count
    correct = CategorizationFeedback.where(correct: true).count
    
    {
      accuracy: (correct.to_f / total * 100).round(1),
      total_patterns: CategorizationPattern.active.count,
      total_categorizations: total,
      uncategorized_expenses: Expense.uncategorized.count,
      avg_confidence: Expense.where.not(ml_confidence: nil)
                             .average(:ml_confidence).to_f.round(3)
    }
  end
  
  def category_breakdown
    Category.all.map do |category|
      patterns = category.categorization_patterns.active
      feedbacks = CategorizationFeedback
        .joins(:expense)
        .where(expenses: { category_id: category.id })
      
      {
        category: category.name,
        pattern_count: patterns.count,
        avg_success_rate: patterns.average(:success_rate).to_f.round(3),
        total_uses: patterns.sum(:usage_count),
        accuracy: calculate_category_accuracy(category)
      }
    end
  end
end
```

---

## Performance Optimizations

### Database Indexes
```ruby
class AddPatternPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # For pattern lookups
    add_index :categorization_patterns, 
              [:pattern_type, :active, :success_rate],
              name: 'idx_patterns_lookup'
    
    # For feedback queries
    add_index :categorization_feedbacks,
              [:created_at, :correct],
              name: 'idx_feedback_analytics'
    
    # For bulk operations
    add_index :expenses,
              [:category_id, :created_at],
              where: 'category_id IS NULL',
              name: 'idx_uncategorized_expenses'
  end
end
```

### Caching Strategy
```ruby
# config/initializers/pattern_caching.rb
Rails.application.config.after_initialize do
  # Warm pattern cache on startup
  if Rails.env.production?
    PatternCacheWarmer.perform_async
  end
  
  # Set up cache expiration
  Rails.cache.redis.config(:expire_after, 1.hour)
end
```

---

## Next Steps
- Integration testing
- Performance benchmarking
- User acceptance testing
- Production deployment planning