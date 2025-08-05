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

ActiveRecord::Schema[8.0].define(version: 2025_08_04_232625) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["amount"], name: "index_expenses_on_amount"
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
    t.index ["status", "transaction_date"], name: "index_expenses_on_status_and_transaction_date"
    t.index ["status"], name: "index_expenses_on_status"
    t.index ["transaction_date", "amount"], name: "index_expenses_on_transaction_date_and_amount"
    t.index ["transaction_date"], name: "index_expenses_on_transaction_date"
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
    t.index ["created_at"], name: "index_sync_sessions_on_created_at"
    t.index ["status"], name: "index_sync_sessions_on_status"
  end

  add_foreign_key "categories", "categories", column: "parent_id"
  add_foreign_key "expenses", "categories"
  add_foreign_key "expenses", "email_accounts"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "sync_session_accounts", "email_accounts"
  add_foreign_key "sync_session_accounts", "sync_sessions"
end
