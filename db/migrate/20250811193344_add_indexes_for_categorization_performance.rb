class AddIndexesForCategorizationPerformance < ActiveRecord::Migration[8.0]
  def change
    # Composite indexes for categorization pattern queries
    add_index :categorization_patterns, [ :active, :pattern_type, :usage_count ],
              name: 'idx_patterns_active_type_usage'

    add_index :categorization_patterns, [ :active, :success_rate, :usage_count ],
              name: 'idx_patterns_active_success_usage'

    add_index :categorization_patterns, [ :category_id, :active, :pattern_type ],
              name: 'idx_patterns_category_active_type'

    # Index for frequently used patterns
    add_index :categorization_patterns, [ :active, :usage_count, :success_rate ],
              name: 'idx_patterns_frequently_used',
              where: 'usage_count >= 10'

    # Index for pattern value lookups (using gin for text search if available)
    add_index :categorization_patterns, :pattern_value,
              name: 'idx_patterns_value'

    # Composite patterns indexes
    if table_exists?(:composite_patterns)
      if column_exists?(:composite_patterns, :priority)
        add_index :composite_patterns, [ :active, :priority ],
                  name: 'idx_composite_active_priority'
      else
        add_index :composite_patterns, [ :active, :usage_count ],
                  name: 'idx_composite_active_usage'
      end
    end

    # User preferences indexes
    if table_exists?(:user_category_preferences)
      # Non-unique index since there might be duplicate context values
      add_index :user_category_preferences, [ :context_type, :context_value ],
                name: 'idx_user_prefs_context' unless index_exists?(:user_category_preferences, [ :context_type, :context_value ])
    end

    add_index :user_category_preferences, [ :context_type, :context_value, :preference_weight ],
              name: 'idx_user_prefs_context_weight' if table_exists?(:user_category_preferences)

    # Pattern feedbacks indexes for learning
    add_index :pattern_feedbacks, [ :categorization_pattern_id, :was_correct ],
              name: 'idx_feedbacks_pattern_correct' if table_exists?(:pattern_feedbacks)

    add_index :pattern_feedbacks, [ :expense_id, :created_at ],
              name: 'idx_feedbacks_expense_created' if table_exists?(:pattern_feedbacks)

    # Expenses indexes for faster categorization queries
    add_index :expenses, [ :merchant_name, :category_id ],
              name: 'idx_expenses_merchant_category' unless index_exists?(:expenses, [ :merchant_name, :category_id ])

    add_index :expenses, [ :auto_categorized, :categorization_confidence ],
              name: 'idx_expenses_auto_confidence' unless index_exists?(:expenses, [ :auto_categorized, :categorization_confidence ])

    add_index :expenses, [ :transaction_date, :category_id ],
              name: 'idx_expenses_date_category' unless index_exists?(:expenses, [ :transaction_date, :category_id ])
  end
end
