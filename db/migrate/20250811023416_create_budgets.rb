# frozen_string_literal: true

# Creates budgets table for tracking spending limits and goals
# Supports multiple periods (daily, weekly, monthly, yearly) and category-specific budgets
# SECURITY: All budgets are scoped to email_accounts for data isolation
class CreateBudgets < ActiveRecord::Migration[8.0]
  def change
    create_table :budgets do |t|
      # Core associations
      t.references :email_account, null: false, foreign_key: true
      t.references :category, null: true, foreign_key: true

      # Budget configuration
      t.string :name, null: false
      t.text :description
      t.integer :period, null: false, default: 2 # enum: daily=0, weekly=1, monthly=2, yearly=3
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false, default: 'CRC'

      # Budget status and tracking
      t.boolean :active, null: false, default: true
      t.date :start_date, null: false
      t.date :end_date # Optional end date for temporary budgets

      # Alert thresholds (percentages)
      t.integer :warning_threshold, default: 70 # Show yellow warning at this percentage
      t.integer :critical_threshold, default: 90 # Show red alert at this percentage

      # Notification preferences
      t.boolean :notify_on_warning, default: true
      t.boolean :notify_on_critical, default: true
      t.boolean :notify_on_exceeded, default: true

      # Rollover settings
      t.boolean :rollover_enabled, default: false
      t.decimal :rollover_amount, precision: 12, scale: 2, default: 0.0

      # Tracking fields
      t.decimal :current_spend, precision: 12, scale: 2, default: 0.0 # Cached current period spend
      t.datetime :current_spend_updated_at # When the spend was last calculated
      t.integer :times_exceeded, default: 0 # Historical tracking
      t.datetime :last_exceeded_at

      # Metadata
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for performance
    add_index :budgets, [ :email_account_id, :active ]
    add_index :budgets, [ :email_account_id, :category_id, :active ]
    add_index :budgets, [ :email_account_id, :period, :active ]
    add_index :budgets, [ :start_date, :end_date ]
    add_index :budgets, [ :active, :start_date ]
    add_index :budgets, :metadata, using: :gin

    # Ensure only one active budget per email_account/category/period combination
    add_index :budgets, [ :email_account_id, :category_id, :period, :active ],
              unique: true,
              where: "active = true",
              name: 'index_budgets_unique_active'
  end
end
