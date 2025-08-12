class AddPerformanceIndexesToPatternTables < ActiveRecord::Migration[8.0]
  def change
    # Composite indexes for pattern lookups
    add_index :categorization_patterns, [ :pattern_type, :active, :success_rate ],
              name: 'idx_patterns_type_active_success',
              if_not_exists: true

    add_index :categorization_patterns, [ :category_id, :active, :pattern_type ],
              name: 'idx_patterns_category_active_type',
              if_not_exists: true

    add_index :categorization_patterns, [ :usage_count, :success_rate ],
              name: 'idx_patterns_usage_success',
              where: "active = true",
              if_not_exists: true

    # Index for user-created patterns
    add_index :categorization_patterns, [ :user_created, :active, :created_at ],
              name: 'idx_patterns_user_active_created',
              if_not_exists: true

    # Composite indexes for pattern feedbacks
    add_index :pattern_feedbacks, [ :expense_id, :created_at ],
              name: 'idx_feedbacks_expense_created',
              if_not_exists: true

    add_index :pattern_feedbacks, [ :category_id, :was_correct, :created_at ],
              name: 'idx_feedbacks_category_correct_created',
              if_not_exists: true

    # Composite indexes for composite patterns
    add_index :composite_patterns, [ :active, :success_rate ],
              name: 'idx_composite_active_success',
              where: "active = true",
              if_not_exists: true

    # Indexes for API tokens optimization
    add_index :api_tokens, [ :active, :expires_at ],
              name: 'idx_tokens_active_expires',
              if_not_exists: true

    add_index :api_tokens, :last_used_at,
              name: 'idx_tokens_last_used',
              if_not_exists: true

    # Indexes for pattern learning events
    add_index :pattern_learning_events, [ :was_correct, :created_at ],
              name: 'idx_learning_correct_created',
              if_not_exists: true

    add_index :pattern_learning_events, [ :category_id, :pattern_used, :created_at ],
              name: 'idx_learning_category_pattern_created',
              if_not_exists: true
  end
end
