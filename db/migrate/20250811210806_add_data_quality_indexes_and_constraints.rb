# frozen_string_literal: true

class AddDataQualityIndexesAndConstraints < ActiveRecord::Migration[8.0]
  def change
    # Add indexes for better pattern lookup performance
    add_index :categorization_patterns, [ :pattern_type, :active, :confidence_weight ],
              name: "idx_patterns_type_active_confidence"

    add_index :categorization_patterns, [ :category_id, :pattern_type, :pattern_value ],
              name: "idx_patterns_unique_lookup",
              unique: true

    add_index :categorization_patterns, [ :user_created, :active ],
              name: "idx_patterns_user_created_active"

    add_index :categorization_patterns, [ :created_at ],
              name: "idx_patterns_created_at"

    add_index :categorization_patterns, [ :updated_at ],
              name: "idx_patterns_updated_at"

    # Add index for similarity searches (if not already present)
    unless index_exists?(:categorization_patterns, :pattern_value, using: :gin)
      enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")
      add_index :categorization_patterns, :pattern_value,
                using: :gin,
                opclass: :gin_trgm_ops,
                name: "idx_patterns_value_trgm"
    end

    # Add check constraints for data integrity
    add_check_constraint :categorization_patterns,
                        "confidence_weight >= 0.1 AND confidence_weight <= 5.0",
                        name: "check_confidence_weight_range"

    add_check_constraint :categorization_patterns,
                        "success_count <= usage_count",
                        name: "check_success_count_validity"

    add_check_constraint :categorization_patterns,
                        "success_rate >= 0.0 AND success_rate <= 1.0",
                        name: "check_success_rate_range"

    add_check_constraint :categorization_patterns,
                        "usage_count >= 0",
                        name: "check_usage_count_non_negative"

    add_check_constraint :categorization_patterns,
                        "success_count >= 0",
                        name: "check_success_count_non_negative"

    # Add indexes for composite patterns if table exists
    if table_exists?(:composite_patterns)
      add_index :composite_patterns, [ :operator, :active ],
                name: "idx_composite_operator_active"

      add_index :composite_patterns, [ :success_rate, :usage_count ],
                name: "idx_composite_performance",
                where: "active = true"
    end

    # Add indexes for pattern feedbacks if table exists
    if table_exists?(:pattern_feedbacks)
      add_index :pattern_feedbacks, [ :categorization_pattern_id, :created_at ],
                name: "idx_feedbacks_pattern_time"

      add_index :pattern_feedbacks, [ :expense_id, :categorization_pattern_id ],
                name: "idx_feedbacks_expense_pattern",
                unique: true
    end

    # Add indexes for pattern learning events if table exists
    if table_exists?(:pattern_learning_events)
      add_index :pattern_learning_events, [ :category_id, :created_at ],
                name: "idx_learning_events_category_time"

      add_index :pattern_learning_events, [ :was_correct, :created_at ],
                name: "idx_learning_events_correct_time"
    end

    # Ensure foreign key constraints are in place
    unless foreign_key_exists?(:categorization_patterns, :categories)
      add_foreign_key :categorization_patterns, :categories,
                      on_delete: :cascade,
                      name: "fk_patterns_category"
    end
  end
end
