# frozen_string_literal: true

class AddDashboardPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction! # Allow concurrent index creation

  def up
    # Composite indexes for dashboard queries
    unless index_exists?(:expenses, [ :updated_at, :category_id ])
      add_index :expenses, [ :updated_at, :category_id ],
                name: "idx_expenses_dashboard_metrics",
                algorithm: :concurrently
    end

    # The uncategorized index already exists as idx_expenses_uncategorized
    # Skip creating it

    # Index for recent expenses - check if any index on updated_at exists
    unless index_exists?(:expenses, :updated_at)
      add_index :expenses, :updated_at,
                name: "idx_expenses_updated_at",
                algorithm: :concurrently
    end

    # Skip patterns indexes that already exist
    # idx_patterns_active_confidence already covered by existing indexes
    # idx_patterns_high_confidence already exists
    # idx_patterns_type already covered by existing indexes

    # Index for recent pattern activity
    unless index_exists?(:categorization_patterns, [ :created_at, :updated_at ])
      add_index :categorization_patterns, [ :created_at, :updated_at ],
                name: "idx_patterns_activity",
                algorithm: :concurrently
    end

    # Index for SolidQueue job queries (if using SolidQueue)
    if table_exists?(:solid_queue_jobs)
      unless index_exists?(:solid_queue_jobs, :finished_at, name: "idx_solid_queue_jobs_unfinished")
        add_index :solid_queue_jobs, :finished_at,
                  where: "finished_at IS NULL",
                  name: "idx_solid_queue_jobs_unfinished",
                  algorithm: :concurrently
      end
    end

    # Create a materialized view for dashboard metrics (PostgreSQL specific)
    # SKIP in test environment to avoid transaction conflicts and performance issues
    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL" && !Rails.env.test?
      execute <<-SQL
        CREATE MATERIALIZED VIEW IF NOT EXISTS dashboard_metrics AS
        SELECT
          COUNT(*) as total_expenses,
          COUNT(category_id) as categorized_expenses,
          COUNT(*) - COUNT(category_id) as uncategorized_expenses,
          COUNT(CASE WHEN updated_at >= NOW() - INTERVAL '1 hour' THEN 1 END) as recent_total,
          COUNT(CASE WHEN updated_at >= NOW() - INTERVAL '1 hour' AND category_id IS NOT NULL THEN 1 END) as recent_categorized,
          NOW() as last_refreshed
        FROM expenses;
      SQL

      # Create an index on the materialized view
      execute <<-SQL
        CREATE UNIQUE INDEX IF NOT EXISTS idx_dashboard_metrics_refresh
        ON dashboard_metrics(last_refreshed);
      SQL
    end
  end

  def down
    remove_index :expenses, name: "idx_expenses_dashboard_metrics" if index_exists?(:expenses, name: "idx_expenses_dashboard_metrics")
    remove_index :expenses, name: "idx_expenses_uncategorized" if index_exists?(:expenses, name: "idx_expenses_uncategorized")
    remove_index :expenses, name: "idx_expenses_updated_at" if index_exists?(:expenses, name: "idx_expenses_updated_at")

    remove_index :categorization_patterns, name: "idx_patterns_active_confidence" if index_exists?(:categorization_patterns, name: "idx_patterns_active_confidence")
    remove_index :categorization_patterns, name: "idx_patterns_high_confidence" if index_exists?(:categorization_patterns, name: "idx_patterns_high_confidence")
    remove_index :categorization_patterns, name: "idx_patterns_activity" if index_exists?(:categorization_patterns, name: "idx_patterns_activity")
    remove_index :categorization_patterns, name: "idx_patterns_type" if index_exists?(:categorization_patterns, name: "idx_patterns_type")

    if table_exists?(:solid_queue_jobs)
      remove_index :solid_queue_jobs, name: "idx_solid_queue_jobs_unfinished" if index_exists?(:solid_queue_jobs, name: "idx_solid_queue_jobs_unfinished")
    end

    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      execute "DROP MATERIALIZED VIEW IF EXISTS dashboard_metrics"
    end
  end
end
