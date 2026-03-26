# Migration: PER-126 — Remove redundant indexes identified by audit
#
# This migration removes 34 indexes that are clearly redundant due to:
#   1. Exact duplicates (same table, same columns, different name)
#   2. Single-column indexes fully covered by composite indexes starting with the same column
#   3. Plain (non-partial) indexes where a composite superset index exists
#
# Conservative approach: unique indexes, partial indexes with meaningful WHERE clauses,
# and any index without a clear covering replacement were all retained.
#
# Uses disable_ddl_transaction! + algorithm: :concurrently so the removals are safe
# to run against a live production database without table locks.

class RemoveRedundantIndexesPer126 < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # === bulk_operation_items ===
    # [bulk_operation_id] covered by composite [bulk_operation_id, expense_id] (unique) and [bulk_operation_id, status]
    remove_index :bulk_operation_items, name: :index_bulk_operation_items_on_bulk_operation_id,
                 algorithm: :concurrently

    # === bulk_operations ===
    # [status] covered by [status, created_at]
    remove_index :bulk_operations, name: :index_bulk_operations_on_status,
                 algorithm: :concurrently

    # [user_id] covered by [user_id, created_at]
    remove_index :bulk_operations, name: :index_bulk_operations_on_user_id,
                 algorithm: :concurrently

    # === categorization_patterns ===
    # EXACT DUPLICATE: idx_patterns_lookup == idx_patterns_type_active_success (both [pattern_type, active, success_rate])
    remove_index :categorization_patterns, name: :idx_patterns_lookup,
                 algorithm: :concurrently

    # [active, pattern_type] covered by [active, pattern_type, usage_count]
    remove_index :categorization_patterns, name: :index_categorization_patterns_on_active_and_pattern_type,
                 algorithm: :concurrently

    # [category_id] covered by composites starting with category_id
    remove_index :categorization_patterns, name: :index_categorization_patterns_on_category_id,
                 algorithm: :concurrently

    # [created_at] covered by idx_patterns_activity [created_at, updated_at]
    remove_index :categorization_patterns, name: :idx_patterns_created_at,
                 algorithm: :concurrently

    # EXACT DUPLICATE GIN: idx_patterns_value_trgm == index_categorization_patterns_on_pattern_value (both pattern_value GIN gin_trgm_ops)
    remove_index :categorization_patterns, name: :index_categorization_patterns_on_pattern_value,
                 algorithm: :concurrently

    # [active, usage_count, success_rate] WHERE (usage_count >= 10) — covered by idx_patterns_performance
    # [active, usage_count, success_rate] WHERE (active = true) and idx_patterns_performance_tracking
    # [active, usage_count, success_rate, updated_at] WHERE (active=true AND usage_count>0)
    remove_index :categorization_patterns, name: :idx_patterns_frequently_used,
                 algorithm: :concurrently

    # === composite_patterns ===
    # [category_id] covered by [category_id, active]
    remove_index :composite_patterns, name: :index_composite_patterns_on_category_id,
                 algorithm: :concurrently

    # [operator] covered by idx_composite_operator_active [operator, active]
    remove_index :composite_patterns, name: :index_composite_patterns_on_operator,
                 algorithm: :concurrently

    # EXACT DUPLICATE GIN: idx_composite_pattern_ids_gin == index_composite_patterns_on_pattern_ids (both pattern_ids GIN)
    remove_index :composite_patterns, name: :index_composite_patterns_on_pattern_ids,
                 algorithm: :concurrently

    # === email_accounts ===
    # [active] covered by [active, bank_name]
    remove_index :email_accounts, name: :index_email_accounts_on_active,
                 algorithm: :concurrently

    # === expenses ===
    # Plain [auto_categorized, categorization_confidence] — superseded by the partial index
    # idx_expenses_auto_categorization WHERE (auto_categorized=true AND deleted_at IS NULL)
    remove_index :expenses, name: :idx_on_auto_categorized_categorization_confidence_98abf3d147,
                 algorithm: :concurrently

    # [category_id] — FK covered by [category_id, transaction_date] and other composites starting with category_id
    remove_index :expenses, name: :index_expenses_on_category_id,
                 algorithm: :concurrently

    # === merchant_aliases ===
    # [canonical_merchant_id] covered by [canonical_merchant_id, confidence] and [canonical_merchant_id, confidence, match_count]
    remove_index :merchant_aliases, name: :index_merchant_aliases_on_canonical_merchant_id,
                 algorithm: :concurrently

    # EXACT DUPLICATE GIN: idx_merchant_alias_trgm == index_merchant_aliases_on_normalized_name (both normalized_name GIN)
    remove_index :merchant_aliases, name: :index_merchant_aliases_on_normalized_name,
                 algorithm: :concurrently

    # === parsing_rules ===
    # [bank_name] covered by [bank_name, active]
    remove_index :parsing_rules, name: :index_parsing_rules_on_bank_name,
                 algorithm: :concurrently

    # === pattern_feedbacks ===
    # EXACT DUPLICATE: idx_feedbacks_pattern_correct == idx_on_categorization_pattern_id_was_correct_e615042861
    # (both [categorization_pattern_id, was_correct])
    remove_index :pattern_feedbacks, name: :idx_on_categorization_pattern_id_was_correct_e615042861,
                 algorithm: :concurrently

    # [categorization_pattern_id] covered by idx_feedbacks_pattern_correct [categorization_pattern_id, was_correct],
    # idx_feedback_pattern_performance, idx_feedbacks_pattern_time
    remove_index :pattern_feedbacks, name: :index_pattern_feedbacks_on_categorization_pattern_id,
                 algorithm: :concurrently

    # [category_id] covered by idx_feedback_category_stats [category_id, was_correct, created_at] and others
    remove_index :pattern_feedbacks, name: :index_pattern_feedbacks_on_category_id,
                 algorithm: :concurrently

    # [expense_id] covered by idx_feedbacks_expense_pattern (unique) [expense_id, categorization_pattern_id]
    # and idx_feedbacks_expense_created, idx_feedbacks_expense_type_created
    remove_index :pattern_feedbacks, name: :index_pattern_feedbacks_on_expense_id,
                 algorithm: :concurrently

    # [created_at] covered by idx_feedback_analytics, idx_feedback_analytics_optimized, idx_feedbacks_created_type
    remove_index :pattern_feedbacks, name: :index_pattern_feedbacks_on_created_at,
                 algorithm: :concurrently

    # EXACT DUPLICATE: idx_feedback_category_stats == idx_feedbacks_category_correct_created
    # (both [category_id, was_correct, created_at])
    remove_index :pattern_feedbacks, name: :idx_feedbacks_category_correct_created,
                 algorithm: :concurrently

    # === pattern_learning_events ===
    # EXACT DUPLICATE: idx_learning_correct_created == idx_learning_events_correct_time (both [was_correct, created_at])
    remove_index :pattern_learning_events, name: :idx_learning_events_correct_time,
                 algorithm: :concurrently

    # [was_correct] covered by idx_learning_correct_created [was_correct, created_at]
    remove_index :pattern_learning_events, name: :index_pattern_learning_events_on_was_correct,
                 algorithm: :concurrently

    # [event_type] covered by index_pattern_learning_events_on_event_type_and_created_at [event_type, created_at]
    remove_index :pattern_learning_events, name: :index_pattern_learning_events_on_event_type,
                 algorithm: :concurrently

    # [created_at] covered by idx_learning_created_category_type, idx_learning_created_correct_category,
    # index_pattern_learning_events_on_event_type_and_created_at
    remove_index :pattern_learning_events, name: :index_pattern_learning_events_on_created_at,
                 algorithm: :concurrently

    # [category_id] covered by idx_learning_events_category_time [category_id, created_at]
    # and idx_learning_category_pattern_created [category_id, pattern_used, created_at]
    remove_index :pattern_learning_events, name: :index_pattern_learning_events_on_category_id,
                 algorithm: :concurrently

    # [pattern_used] covered by idx_learning_events_analysis [pattern_used, was_correct, created_at]
    remove_index :pattern_learning_events, name: :index_pattern_learning_events_on_pattern_used,
                 algorithm: :concurrently

    # === sync_conflicts ===
    # [status] covered by [status, conflict_type] and [sync_session_id, status]
    remove_index :sync_conflicts, name: :index_sync_conflicts_on_status,
                 algorithm: :concurrently

    # [sync_session_id] covered by [sync_session_id, status]
    remove_index :sync_conflicts, name: :index_sync_conflicts_on_sync_session_id,
                 algorithm: :concurrently

    # === sync_metrics ===
    # [metric_type] covered by [metric_type, started_at] and [metric_type, success, started_at]
    remove_index :sync_metrics, name: :index_sync_metrics_on_metric_type,
                 algorithm: :concurrently

    # [email_account_id] covered by [email_account_id, metric_type]
    remove_index :sync_metrics, name: :index_sync_metrics_on_email_account_id,
                 algorithm: :concurrently

    # [sync_session_id] covered by [sync_session_id, metric_type]
    remove_index :sync_metrics, name: :index_sync_metrics_on_sync_session_id,
                 algorithm: :concurrently

    # [started_at] covered by [started_at, completed_at]
    remove_index :sync_metrics, name: :index_sync_metrics_on_started_at,
                 algorithm: :concurrently

    # === undo_histories ===
    # [action_type] covered by [action_type, undone_at]
    remove_index :undo_histories, name: :index_undo_histories_on_action_type,
                 algorithm: :concurrently

    # [user_id] covered by [user_id, created_at]
    remove_index :undo_histories, name: :index_undo_histories_on_user_id,
                 algorithm: :concurrently

    # === user_category_preferences ===
    # [email_account_id] covered by [email_account_id, context_type, context_value] and [email_account_id, context_type, context_value, preference_weight]
    remove_index :user_category_preferences, name: :index_user_category_preferences_on_email_account_id,
                 algorithm: :concurrently

    # [email_account_id, context_type, context_value] covered by [email_account_id, context_type, context_value, preference_weight]
    remove_index :user_category_preferences, name: :idx_on_email_account_id_context_type_context_value_b40292993e,
                 algorithm: :concurrently

    # [context_type, context_value] covered by [context_type, context_value, preference_weight]
    remove_index :user_category_preferences, name: :idx_user_prefs_context,
                 algorithm: :concurrently
  end

  def down
    # Restore all removed indexes for reversibility

    add_index :bulk_operation_items, :bulk_operation_id,
              name: :index_bulk_operation_items_on_bulk_operation_id, algorithm: :concurrently

    add_index :bulk_operations, :status,
              name: :index_bulk_operations_on_status, algorithm: :concurrently

    add_index :bulk_operations, :user_id,
              name: :index_bulk_operations_on_user_id, algorithm: :concurrently

    add_index :categorization_patterns, [ :pattern_type, :active, :success_rate ],
              name: :idx_patterns_lookup, algorithm: :concurrently

    add_index :categorization_patterns, [ :active, :pattern_type ],
              name: :index_categorization_patterns_on_active_and_pattern_type, algorithm: :concurrently

    add_index :categorization_patterns, :category_id,
              name: :index_categorization_patterns_on_category_id, algorithm: :concurrently

    add_index :categorization_patterns, :created_at,
              name: :idx_patterns_created_at, algorithm: :concurrently

    add_index :categorization_patterns, :pattern_value,
              name: :index_categorization_patterns_on_pattern_value,
              using: :gin, opclass: :gin_trgm_ops, algorithm: :concurrently

    add_index :categorization_patterns, [ :active, :usage_count, :success_rate ],
              name: :idx_patterns_frequently_used,
              where: "(usage_count >= 10)", algorithm: :concurrently

    add_index :composite_patterns, :category_id,
              name: :index_composite_patterns_on_category_id, algorithm: :concurrently

    add_index :composite_patterns, :operator,
              name: :index_composite_patterns_on_operator, algorithm: :concurrently

    add_index :composite_patterns, :pattern_ids,
              name: :index_composite_patterns_on_pattern_ids, using: :gin, algorithm: :concurrently

    add_index :email_accounts, :active,
              name: :index_email_accounts_on_active, algorithm: :concurrently

    add_index :expenses, [ :auto_categorized, :categorization_confidence ],
              name: :idx_on_auto_categorized_categorization_confidence_98abf3d147, algorithm: :concurrently

    add_index :expenses, :category_id,
              name: :index_expenses_on_category_id, algorithm: :concurrently

    add_index :merchant_aliases, :canonical_merchant_id,
              name: :index_merchant_aliases_on_canonical_merchant_id, algorithm: :concurrently

    add_index :merchant_aliases, :normalized_name,
              name: :index_merchant_aliases_on_normalized_name, using: :gin, opclass: :gin_trgm_ops, algorithm: :concurrently

    add_index :parsing_rules, :bank_name,
              name: :index_parsing_rules_on_bank_name, algorithm: :concurrently

    add_index :pattern_feedbacks, [ :categorization_pattern_id, :was_correct ],
              name: :idx_on_categorization_pattern_id_was_correct_e615042861, algorithm: :concurrently

    add_index :pattern_feedbacks, :categorization_pattern_id,
              name: :index_pattern_feedbacks_on_categorization_pattern_id, algorithm: :concurrently

    add_index :pattern_feedbacks, :category_id,
              name: :index_pattern_feedbacks_on_category_id, algorithm: :concurrently

    add_index :pattern_feedbacks, :expense_id,
              name: :index_pattern_feedbacks_on_expense_id, algorithm: :concurrently

    add_index :pattern_feedbacks, :created_at,
              name: :index_pattern_feedbacks_on_created_at, algorithm: :concurrently

    add_index :pattern_feedbacks, [ :category_id, :was_correct, :created_at ],
              name: :idx_feedbacks_category_correct_created, algorithm: :concurrently

    add_index :pattern_learning_events, [ :was_correct, :created_at ],
              name: :idx_learning_events_correct_time, algorithm: :concurrently

    add_index :pattern_learning_events, :was_correct,
              name: :index_pattern_learning_events_on_was_correct, algorithm: :concurrently

    add_index :pattern_learning_events, :event_type,
              name: :index_pattern_learning_events_on_event_type, algorithm: :concurrently

    add_index :pattern_learning_events, :created_at,
              name: :index_pattern_learning_events_on_created_at, algorithm: :concurrently

    add_index :pattern_learning_events, :category_id,
              name: :index_pattern_learning_events_on_category_id, algorithm: :concurrently

    add_index :pattern_learning_events, :pattern_used,
              name: :index_pattern_learning_events_on_pattern_used, algorithm: :concurrently

    add_index :sync_conflicts, :status,
              name: :index_sync_conflicts_on_status, algorithm: :concurrently

    add_index :sync_conflicts, :sync_session_id,
              name: :index_sync_conflicts_on_sync_session_id, algorithm: :concurrently

    add_index :sync_metrics, :metric_type,
              name: :index_sync_metrics_on_metric_type, algorithm: :concurrently

    add_index :sync_metrics, :email_account_id,
              name: :index_sync_metrics_on_email_account_id, algorithm: :concurrently

    add_index :sync_metrics, :sync_session_id,
              name: :index_sync_metrics_on_sync_session_id, algorithm: :concurrently

    add_index :sync_metrics, :started_at,
              name: :index_sync_metrics_on_started_at, algorithm: :concurrently

    add_index :undo_histories, :action_type,
              name: :index_undo_histories_on_action_type, algorithm: :concurrently

    add_index :undo_histories, :user_id,
              name: :index_undo_histories_on_user_id, algorithm: :concurrently

    add_index :user_category_preferences, :email_account_id,
              name: :index_user_category_preferences_on_email_account_id, algorithm: :concurrently

    add_index :user_category_preferences, [ :email_account_id, :context_type, :context_value ],
              name: :idx_on_email_account_id_context_type_context_value_b40292993e, algorithm: :concurrently

    add_index :user_category_preferences, [ :context_type, :context_value ],
              name: :idx_user_prefs_context, algorithm: :concurrently
  end
end
