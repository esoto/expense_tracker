# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_08_221245) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "unaccent"

  create_table "api_tokens", force: :cascade do |t|
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "token_hash"
    t.index ["active", "expires_at"], name: "index_api_tokens_on_active_and_expires_at"
    t.index ["active"], name: "index_api_tokens_on_active"
    t.index ["expires_at"], name: "index_api_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["token_hash"], name: "index_api_tokens_on_token_hash", unique: true
  end

  create_table "canonical_merchants", force: :cascade do |t|
    t.string "name", null: false
    t.string "display_name"
    t.string "category_hint"
    t.jsonb "metadata", default: {}
    t.integer "usage_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_canonical_merchants_on_name", unique: true
    t.index ["usage_count"], name: "index_canonical_merchants_on_usage_count"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "parent_id"
    t.string "color", limit: 7
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name"
    t.index ["parent_id"], name: "index_categories_on_parent_id"
  end

  create_table "categorization_patterns", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "pattern_type", null: false
    t.string "pattern_value", null: false
    t.float "confidence_weight", default: 1.0
    t.integer "usage_count", default: 0
    t.integer "success_count", default: 0
    t.float "success_rate", default: 0.0
    t.jsonb "metadata", default: {}
    t.boolean "active", default: true
    t.boolean "user_created", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "pattern_type"], name: "index_categorization_patterns_on_active_and_pattern_type"
    t.index ["category_id", "success_rate"], name: "index_categorization_patterns_on_category_id_and_success_rate"
    t.index ["category_id"], name: "index_categorization_patterns_on_category_id"
    t.index ["pattern_type", "pattern_value"], name: "idx_on_pattern_type_pattern_value_fad6f38255"
    t.index ["pattern_value"], name: "index_categorization_patterns_on_pattern_value", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "composite_patterns", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "name", null: false
    t.string "operator", null: false
    t.jsonb "pattern_ids", default: []
    t.jsonb "conditions", default: {}
    t.float "confidence_weight", default: 1.5
    t.integer "usage_count", default: 0
    t.integer "success_count", default: 0
    t.float "success_rate", default: 0.0
    t.boolean "active", default: true
    t.boolean "user_created", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "active"], name: "index_composite_patterns_on_category_id_and_active"
    t.index ["category_id"], name: "index_composite_patterns_on_category_id"
    t.index ["name"], name: "index_composite_patterns_on_name"
    t.index ["operator"], name: "index_composite_patterns_on_operator"
    t.index ["pattern_ids"], name: "index_composite_patterns_on_pattern_ids", using: :gin
  end

  create_table "conflict_resolutions", force: :cascade do |t|
    t.bigint "sync_conflict_id", null: false
    t.string "action", null: false
    t.jsonb "before_state", default: {}
    t.jsonb "after_state", default: {}
    t.jsonb "changes_made", default: {}
    t.boolean "undoable", default: true
    t.boolean "undone", default: false
    t.datetime "undone_at"
    t.bigint "undone_by_resolution_id"
    t.string "resolved_by"
    t.string "resolution_method"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_conflict_resolutions_on_action"
    t.index ["after_state"], name: "index_conflict_resolutions_on_after_state", using: :gin
    t.index ["before_state"], name: "index_conflict_resolutions_on_before_state", using: :gin
    t.index ["created_at"], name: "index_conflict_resolutions_on_created_at"
    t.index ["sync_conflict_id", "undone"], name: "index_conflict_resolutions_on_sync_conflict_id_and_undone"
    t.index ["sync_conflict_id"], name: "index_conflict_resolutions_on_sync_conflict_id"
    t.index ["undone"], name: "index_conflict_resolutions_on_undone"
    t.index ["undone_by_resolution_id"], name: "index_conflict_resolutions_on_undone_by_resolution_id"
  end

  create_table "email_accounts", force: :cascade do |t|
    t.string "provider", null: false
    t.string "email", null: false
    t.text "encrypted_password"
    t.text "encrypted_settings"
    t.string "bank_name", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "bank_name"], name: "index_email_accounts_on_active_and_bank_name"
    t.index ["active"], name: "index_email_accounts_on_active"
    t.index ["bank_name"], name: "index_email_accounts_on_bank_name"
    t.index ["email"], name: "index_email_accounts_on_email", unique: true
  end

  create_table "expenses", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description"
    t.datetime "transaction_date", null: false
    t.string "merchant_name"
    t.integer "email_account_id", null: false
    t.integer "category_id"
    t.text "raw_email_content"
    t.text "parsed_data"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "bank_name"
    t.integer "currency", default: 0, null: false
    t.text "email_body"
    t.string "merchant_normalized"
    t.boolean "auto_categorized", default: false
    t.float "categorization_confidence"
    t.string "categorization_method"
    t.index ["amount"], name: "index_expenses_on_amount"
    t.index ["auto_categorized", "categorization_confidence"], name: "idx_on_auto_categorized_categorization_confidence_98abf3d147"
    t.index ["bank_name", "transaction_date"], name: "index_expenses_on_bank_name_and_transaction_date"
    t.index ["category_id", "transaction_date"], name: "index_expenses_on_category_id_and_transaction_date"
    t.index ["category_id"], name: "index_expenses_on_category_id"
    t.index ["currency"], name: "index_expenses_on_currency"
    t.index ["email_account_id", "amount", "transaction_date"], name: "index_expenses_on_account_amount_date_for_duplicates"
    t.index ["email_account_id", "created_at"], name: "index_expenses_on_email_account_id_and_created_at"
    t.index ["email_account_id", "transaction_date"], name: "index_expenses_on_email_account_id_and_transaction_date"
    t.index ["email_account_id"], name: "index_expenses_on_email_account_id"
    t.index ["merchant_name", "amount"], name: "index_expenses_on_merchant_name_and_amount"
    t.index ["merchant_name"], name: "index_expenses_on_merchant_name"
    t.index ["merchant_normalized"], name: "index_expenses_on_merchant_normalized"
    t.index ["status", "transaction_date"], name: "index_expenses_on_status_and_transaction_date"
    t.index ["status"], name: "index_expenses_on_status"
    t.index ["transaction_date", "amount"], name: "index_expenses_on_transaction_date_and_amount"
    t.index ["transaction_date"], name: "index_expenses_on_transaction_date"
  end

  create_table "failed_broadcast_stores", force: :cascade do |t|
    t.string "channel_name", null: false
    t.string "target_type", null: false
    t.bigint "target_id", null: false
    t.json "data", null: false
    t.string "priority", default: "medium", null: false
    t.string "error_type", null: false
    t.text "error_message", null: false
    t.datetime "failed_at", null: false
    t.integer "retry_count", default: 0, null: false
    t.string "sidekiq_job_id"
    t.datetime "recovered_at"
    t.text "recovery_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_name", "priority"], name: "idx_failed_broadcasts_channel_priority"
    t.index ["error_type"], name: "idx_failed_broadcasts_error_type"
    t.index ["failed_at", "recovered_at"], name: "idx_failed_broadcasts_status"
    t.index ["sidekiq_job_id"], name: "idx_failed_broadcasts_job_id", unique: true
    t.index ["target_type", "target_id"], name: "idx_failed_broadcasts_target"
  end

  create_table "merchant_aliases", force: :cascade do |t|
    t.string "raw_name", null: false
    t.string "normalized_name", null: false
    t.bigint "canonical_merchant_id"
    t.float "confidence", default: 1.0
    t.integer "match_count", default: 0
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_merchant_id", "confidence"], name: "index_merchant_aliases_on_canonical_merchant_id_and_confidence"
    t.index ["canonical_merchant_id"], name: "index_merchant_aliases_on_canonical_merchant_id"
    t.index ["normalized_name"], name: "index_merchant_aliases_on_normalized_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["raw_name"], name: "index_merchant_aliases_on_raw_name"
  end

  create_table "parsing_rules", force: :cascade do |t|
    t.string "bank_name", null: false
    t.text "email_pattern"
    t.string "amount_pattern", null: false
    t.string "date_pattern", null: false
    t.string "merchant_pattern"
    t.string "description_pattern"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_parsing_rules_on_active"
    t.index ["bank_name", "active"], name: "index_parsing_rules_on_bank_name_and_active"
    t.index ["bank_name"], name: "index_parsing_rules_on_bank_name"
  end

  create_table "pattern_feedbacks", force: :cascade do |t|
    t.bigint "categorization_pattern_id"
    t.bigint "expense_id"
    t.bigint "category_id"
    t.boolean "was_correct"
    t.float "confidence_score"
    t.string "feedback_type"
    t.jsonb "context_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["categorization_pattern_id", "was_correct"], name: "idx_on_categorization_pattern_id_was_correct_e615042861"
    t.index ["categorization_pattern_id"], name: "index_pattern_feedbacks_on_categorization_pattern_id"
    t.index ["category_id"], name: "index_pattern_feedbacks_on_category_id"
    t.index ["created_at"], name: "index_pattern_feedbacks_on_created_at"
    t.index ["expense_id"], name: "index_pattern_feedbacks_on_expense_id"
  end

  create_table "pattern_learning_events", force: :cascade do |t|
    t.bigint "expense_id"
    t.bigint "category_id"
    t.string "pattern_used"
    t.boolean "was_correct"
    t.float "confidence_score"
    t.jsonb "context_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_pattern_learning_events_on_category_id"
    t.index ["created_at"], name: "index_pattern_learning_events_on_created_at"
    t.index ["expense_id"], name: "index_pattern_learning_events_on_expense_id"
    t.index ["pattern_used"], name: "index_pattern_learning_events_on_pattern_used"
    t.index ["was_correct"], name: "index_pattern_learning_events_on_was_correct"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sync_conflicts", force: :cascade do |t|
    t.bigint "existing_expense_id", null: false
    t.bigint "new_expense_id"
    t.bigint "sync_session_id", null: false
    t.string "conflict_type", null: false
    t.decimal "similarity_score", precision: 5, scale: 2
    t.jsonb "conflict_data", default: {}
    t.jsonb "differences", default: {}
    t.string "status", default: "pending", null: false
    t.string "resolution_action"
    t.jsonb "resolution_data", default: {}
    t.datetime "resolved_at"
    t.string "resolved_by"
    t.text "notes"
    t.integer "priority", default: 0
    t.boolean "bulk_resolvable", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conflict_data"], name: "index_sync_conflicts_on_conflict_data", using: :gin
    t.index ["conflict_type"], name: "index_sync_conflicts_on_conflict_type"
    t.index ["differences"], name: "index_sync_conflicts_on_differences", using: :gin
    t.index ["existing_expense_id"], name: "index_sync_conflicts_on_existing_expense_id"
    t.index ["new_expense_id"], name: "index_sync_conflicts_on_new_expense_id"
    t.index ["priority"], name: "index_sync_conflicts_on_priority"
    t.index ["resolved_at"], name: "index_sync_conflicts_on_resolved_at"
    t.index ["similarity_score"], name: "index_sync_conflicts_on_similarity_score"
    t.index ["status", "conflict_type"], name: "index_sync_conflicts_on_status_and_conflict_type"
    t.index ["status"], name: "index_sync_conflicts_on_status"
    t.index ["sync_session_id", "status"], name: "index_sync_conflicts_on_sync_session_id_and_status"
    t.index ["sync_session_id"], name: "index_sync_conflicts_on_sync_session_id"
  end

  create_table "sync_metrics", force: :cascade do |t|
    t.bigint "sync_session_id", null: false
    t.bigint "email_account_id"
    t.string "metric_type", null: false
    t.decimal "duration", precision: 10, scale: 3
    t.integer "emails_processed", default: 0
    t.boolean "success", default: true
    t.string "error_type"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_at"], name: "index_sync_metrics_on_completed_at"
    t.index ["email_account_id", "metric_type"], name: "index_sync_metrics_on_email_account_id_and_metric_type"
    t.index ["email_account_id"], name: "index_sync_metrics_on_email_account_id"
    t.index ["error_type"], name: "index_sync_metrics_on_error_type"
    t.index ["metadata"], name: "index_sync_metrics_on_metadata", using: :gin
    t.index ["metric_type", "started_at"], name: "index_sync_metrics_on_metric_type_and_started_at"
    t.index ["metric_type", "success", "started_at"], name: "index_sync_metrics_dashboard"
    t.index ["metric_type"], name: "index_sync_metrics_on_metric_type"
    t.index ["started_at", "completed_at"], name: "index_sync_metrics_on_started_at_and_completed_at"
    t.index ["started_at"], name: "index_sync_metrics_on_started_at"
    t.index ["success", "metric_type"], name: "index_sync_metrics_on_success_and_metric_type"
    t.index ["sync_session_id", "metric_type"], name: "index_sync_metrics_on_sync_session_id_and_metric_type"
    t.index ["sync_session_id"], name: "index_sync_metrics_on_sync_session_id"
  end

  create_table "sync_session_accounts", force: :cascade do |t|
    t.bigint "sync_session_id", null: false
    t.bigint "email_account_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "total_emails", default: 0
    t.integer "processed_emails", default: 0
    t.integer "detected_expenses", default: 0
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "job_id"
    t.integer "lock_version", default: 0, null: false
    t.index ["email_account_id"], name: "index_sync_session_accounts_on_email_account_id"
    t.index ["job_id"], name: "index_sync_session_accounts_on_job_id"
    t.index ["status"], name: "index_sync_session_accounts_on_status"
    t.index ["sync_session_id"], name: "index_sync_session_accounts_on_sync_session_id"
  end

  create_table "sync_sessions", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.integer "total_emails", default: 0
    t.integer "processed_emails", default: 0
    t.integer "detected_expenses", default: 0
    t.integer "errors_count", default: 0
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "job_ids", default: "[]"
    t.integer "lock_version", default: 0, null: false
    t.string "session_token"
    t.jsonb "metadata", default: {}
    t.index ["created_at"], name: "index_sync_sessions_on_created_at"
    t.index ["metadata"], name: "index_sync_sessions_on_metadata", using: :gin
    t.index ["session_token"], name: "index_sync_sessions_on_session_token", unique: true
    t.index ["status"], name: "index_sync_sessions_on_status"
  end

  create_table "user_category_preferences", force: :cascade do |t|
    t.bigint "email_account_id"
    t.bigint "category_id"
    t.string "context_type"
    t.string "context_value"
    t.integer "preference_weight", default: 1
    t.integer "usage_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_user_category_preferences_on_category_id"
    t.index ["email_account_id", "context_type", "context_value"], name: "idx_on_email_account_id_context_type_context_value_b40292993e"
    t.index ["email_account_id"], name: "index_user_category_preferences_on_email_account_id"
  end

  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "categorization_patterns", "categories"
  add_foreign_key "composite_patterns", "categories"
  add_foreign_key "conflict_resolutions", "conflict_resolutions", column: "undone_by_resolution_id"
  add_foreign_key "conflict_resolutions", "sync_conflicts"
  add_foreign_key "expenses", "categories"
  add_foreign_key "expenses", "email_accounts"
  add_foreign_key "merchant_aliases", "canonical_merchants"
  add_foreign_key "pattern_feedbacks", "categories"
  add_foreign_key "pattern_feedbacks", "categorization_patterns"
  add_foreign_key "pattern_feedbacks", "expenses"
  add_foreign_key "pattern_learning_events", "categories"
  add_foreign_key "pattern_learning_events", "expenses"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "sync_conflicts", "expenses", column: "existing_expense_id"
  add_foreign_key "sync_conflicts", "expenses", column: "new_expense_id"
  add_foreign_key "sync_conflicts", "sync_sessions"
  add_foreign_key "sync_metrics", "email_accounts"
  add_foreign_key "sync_metrics", "sync_sessions"
  add_foreign_key "sync_session_accounts", "email_accounts"
  add_foreign_key "sync_session_accounts", "sync_sessions"
  add_foreign_key "user_category_preferences", "categories"
  add_foreign_key "user_category_preferences", "email_accounts"
end
