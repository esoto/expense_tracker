# frozen_string_literal: true

class AddAnalyticsIndexes < ActiveRecord::Migration[8.0]
  def change
    # Composite indexes for pattern analytics queries
    add_index :pattern_feedbacks,
              [ :created_at, :feedback_type ],
              name: "idx_feedbacks_created_type",
              if_not_exists: true

    add_index :pattern_feedbacks,
              [ :category_id, :created_at, :feedback_type ],
              name: "idx_feedbacks_category_created_type",
              if_not_exists: true

    # Index for pattern learning events analytics
    add_index :pattern_learning_events,
              [ :created_at, :category_id, :event_type ],
              name: "idx_learning_created_category_type",
              if_not_exists: true

    add_index :pattern_learning_events,
              [ :created_at, :was_correct, :category_id ],
              name: "idx_learning_created_correct_category",
              if_not_exists: true

    # Composite index for categorization patterns performance queries
    add_index :categorization_patterns,
              [ :category_id, :active, :success_rate, :usage_count ],
              name: "idx_patterns_category_performance",
              if_not_exists: true

    # Index for expenses transaction date (used in heatmap queries)
    add_index :expenses,
              [ :transaction_date ],
              name: "idx_expenses_transaction_date",
              if_not_exists: true

    add_index :expenses,
              "EXTRACT(hour FROM transaction_date), EXTRACT(dow FROM transaction_date)",
              name: "idx_expenses_hour_dow",
              if_not_exists: true

    # Composite index for pattern feedbacks with expenses join
    add_index :pattern_feedbacks,
              [ :expense_id, :feedback_type, :created_at ],
              name: "idx_feedbacks_expense_type_created",
              if_not_exists: true
  end
end
