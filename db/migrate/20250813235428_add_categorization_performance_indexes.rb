class AddCategorizationPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # 1. Pattern lookups index - optimized for the most common pattern matching queries
    # This composite index supports pattern matching operations by type, value, and activity status
    add_index :categorization_patterns,
              [ :pattern_type, :pattern_value, :active, :success_rate ],
              name: 'idx_patterns_optimized_lookup',
              where: 'active = true',
              if_not_exists: true,
              comment: 'Optimized index for pattern matching queries'

    # 2. Feedback analytics index - optimized for feedback analysis queries
    # Supports time-based analytics and performance tracking
    add_index :pattern_feedbacks,
              [ :created_at, :was_correct, :feedback_type ],
              name: 'idx_feedback_analytics_optimized',
              order: { created_at: :desc },
              if_not_exists: true,
              comment: 'Optimized index for feedback analytics and performance tracking'

    # 3. Uncategorized expenses index - optimized for finding expenses that need categorization
    # This index helps quickly identify expenses that need ML processing or manual review
    add_index :expenses,
              [ :category_id, :created_at, :merchant_normalized ],
              name: 'idx_expenses_uncategorized_optimized',
              where: 'category_id IS NULL',
              order: { created_at: :desc },
              if_not_exists: true,
              comment: 'Optimized index for finding uncategorized expenses'

    # 4. Pattern performance tracking index - for monitoring pattern effectiveness
    add_index :categorization_patterns,
              [ :active, :usage_count, :success_rate, :updated_at ],
              name: 'idx_patterns_performance_tracking',
              where: 'active = true AND usage_count > 0',
              if_not_exists: true,
              comment: 'Index for tracking pattern performance and effectiveness'

    # 5. User preference lookup index - optimized for merchant-based preferences
    add_index :user_category_preferences,
              [ :context_type, :context_value, :category_id ],
              name: 'idx_user_prefs_merchant_lookup',
              where: "context_type = 'merchant'",
              if_not_exists: true,
              comment: 'Optimized index for merchant preference lookups'

    # 6. Composite pattern lookup index - for complex pattern matching
    add_index :composite_patterns,
              [ :active, :operator, :success_rate ],
              name: 'idx_composite_patterns_lookup',
              where: 'active = true',
              if_not_exists: true,
              comment: 'Optimized index for composite pattern lookups'
  end

  def down
    remove_index :categorization_patterns, name: 'idx_patterns_optimized_lookup', if_exists: true
    remove_index :pattern_feedbacks, name: 'idx_feedback_analytics_optimized', if_exists: true
    remove_index :expenses, name: 'idx_expenses_uncategorized_optimized', if_exists: true
    remove_index :categorization_patterns, name: 'idx_patterns_performance_tracking', if_exists: true
    remove_index :user_category_preferences, name: 'idx_user_prefs_merchant_lookup', if_exists: true
    remove_index :composite_patterns, name: 'idx_composite_patterns_lookup', if_exists: true
  end
end
