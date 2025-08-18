# Ticket 4.1: Create Data Migration Script

## Ticket Information
- **Epic**: Epic 4 - Polish and Migration (Weeks 7-8)
- **Priority**: CRITICAL
- **Story Points**: 8
- **Risk Level**: HIGH
- **Dependencies**: 
  - All previous epics completed
  - Database backup system in place

## Description
Create a comprehensive data migration script to transition from the current single-user EmailAccount system to the multi-tenant architecture. This must handle all existing data with zero data loss, maintain referential integrity, and be reversible. The migration must work in production with minimal downtime.

## Technical Requirements
1. Create migration rake tasks
2. Handle existing EmailAccount to Account conversion
3. Create User records from EmailAccounts
4. Migrate all related data with proper associations
5. Implement rollback capability
6. Add data validation and integrity checks

## Acceptance Criteria
- [ ] Migration script created with:
  - Pre-migration validation checks
  - Backup creation before migration
  - Step-by-step migration process
  - Progress reporting and logging
  - Rollback capability
  - Post-migration validation
- [ ] Data transformation handles:
  - EmailAccount → Account + User creation
  - Expense association to new Account
  - Category migration with deduplication
  - Budget and parsing rule migration
  - Sync session and history preservation
- [ ] Migration safeguards:
  - Dry-run mode for testing
  - Transaction wrapping for atomicity
  - Data integrity validation
  - Duplicate prevention
  - Orphaned record handling
- [ ] Performance optimizations:
  - Batch processing for large datasets
  - Index management during migration
  - Memory-efficient processing
  - Parallel processing where safe
- [ ] Rollback mechanism:
  - Complete rollback script
  - Data restoration from backup
  - Association cleanup
  - State verification

## Implementation Details
```ruby
# lib/tasks/multi_tenant_migration.rake
namespace :multi_tenant do
  desc "Migrate from single-user to multi-tenant architecture"
  task migrate: :environment do
    migrator = MultiTenantMigrator.new
    migrator.run!
  end
  
  desc "Dry run of multi-tenant migration"
  task migrate_dry_run: :environment do
    migrator = MultiTenantMigrator.new(dry_run: true)
    migrator.run!
  end
  
  desc "Rollback multi-tenant migration"
  task rollback: :environment do
    rollback = MultiTenantRollback.new
    rollback.run!
  end
  
  desc "Validate migration readiness"
  task validate: :environment do
    validator = MigrationValidator.new
    validator.check_all
  end
end

# app/services/multi_tenancy/multi_tenant_migrator.rb
module Services
  module MultiTenancy
    class MultiTenantMigrator
      attr_reader :dry_run, :logger, :stats
      
      def initialize(dry_run: false)
        @dry_run = dry_run
        @logger = Logger.new(Rails.root.join('log', 'migration.log'))
        @stats = Hash.new(0)
      end
      
      def run!
        log_info "Starting multi-tenant migration (dry_run: #{dry_run})"
        
        begin
          validate_preconditions!
          create_backup! unless dry_run
          
          ActiveRecord::Base.transaction do
            migrate_email_accounts_to_accounts
            migrate_expenses
            migrate_categories
            migrate_budgets
            migrate_parsing_rules
            migrate_sync_sessions
            cleanup_orphaned_records
            validate_migration!
            
            raise ActiveRecord::Rollback if dry_run
          end
          
          log_info "Migration completed successfully!"
          report_statistics
          
        rescue => e
          log_error "Migration failed: #{e.message}"
          log_error e.backtrace.join("\n")
          raise
        end
      end
      
      private
      
      def validate_preconditions!
        log_info "Validating preconditions..."
        
        # Check for required tables
        required_tables = %w[accounts users account_memberships]
        missing_tables = required_tables.reject { |t| ActiveRecord::Base.connection.table_exists?(t) }
        
        if missing_tables.any?
          raise "Missing required tables: #{missing_tables.join(', ')}"
        end
        
        # Check for unmigrated email accounts
        unmigrated_count = EmailAccount.where(account_id: nil).count
        log_info "Found #{unmigrated_count} EmailAccounts to migrate"
        
        if unmigrated_count == 0
          raise "No EmailAccounts to migrate. Migration may have already been completed."
        end
        
        # Check for data inconsistencies
        orphaned_expenses = Expense.includes(:email_account)
                                  .where(email_accounts: { id: nil })
                                  .count
        
        if orphaned_expenses > 0
          log_warning "Found #{orphaned_expenses} orphaned expenses"
        end
      end
      
      def create_backup!
        log_info "Creating backup..."
        
        timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
        backup_file = Rails.root.join('backups', "pre_migration_#{timestamp}.sql")
        
        # Use database-specific backup command
        case ActiveRecord::Base.connection.adapter_name
        when 'PostgreSQL'
          system("pg_dump #{Rails.configuration.database_configuration[Rails.env]['database']} > #{backup_file}")
        when 'MySQL', 'Mysql2'
          system("mysqldump #{Rails.configuration.database_configuration[Rails.env]['database']} > #{backup_file}")
        end
        
        log_info "Backup created at #{backup_file}"
      end
      
      def migrate_email_accounts_to_accounts
        log_info "Migrating EmailAccounts to Accounts..."
        
        EmailAccount.where(account_id: nil).find_in_batches(batch_size: 100) do |batch|
          batch.each do |email_account|
            migrate_single_email_account(email_account)
          end
        end
      end
      
      def migrate_single_email_account(email_account)
        # Create or find user
        user = User.find_or_create_by!(email: email_account.email) do |u|
          u.password = SecureRandom.hex(16)
          u.name = email_account.email.split('@').first.capitalize
          u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
        end
        
        # Create account for this email
        account_name = determine_account_name(email_account)
        account = Account.create!(
          name: account_name,
          account_type: :personal,
          settings: {
            migrated_from_email_account_id: email_account.id,
            migration_date: Time.current
          }
        )
        
        # Create membership
        AccountMembership.create!(
          account: account,
          user: user,
          role: :owner,
          joined_at: email_account.created_at
        )
        
        # Update email_account
        email_account.update_columns(
          account_id: account.id,
          updated_at: Time.current
        )
        
        @stats[:accounts_created] += 1
        @stats[:users_created] += 1 if user.created_at > 1.minute.ago
        
        log_info "Migrated EmailAccount #{email_account.id} to Account #{account.id}"
        
      rescue => e
        log_error "Failed to migrate EmailAccount #{email_account.id}: #{e.message}"
        raise
      end
      
      def determine_account_name(email_account)
        if email_account.bank_name.present?
          "#{email_account.bank_name} - #{email_account.email.split('@').first}"
        else
          "Personal - #{email_account.email.split('@').first}"
        end
      end
      
      def migrate_expenses
        log_info "Migrating expenses..."
        
        Expense.where(account_id: nil).includes(:email_account).find_in_batches(batch_size: 500) do |batch|
          updates = []
          
          batch.each do |expense|
            if expense.email_account&.account_id
              updates << {
                id: expense.id,
                account_id: expense.email_account.account_id,
                visibility: Expense.visibilities[:shared]
              }
            end
          end
          
          if updates.any?
            Expense.upsert_all(updates, unique_by: :id) unless dry_run
            @stats[:expenses_migrated] += updates.size
          end
        end
        
        log_info "Migrated #{@stats[:expenses_migrated]} expenses"
      end
      
      def migrate_categories
        log_info "Migrating categories..."
        
        # Group categories by name to handle duplicates
        categories_by_name = {}
        
        Category.where(account_id: nil).find_each do |category|
          # Find which account uses this category most
          expense_with_category = Expense.where(category_id: category.id)
                                        .where.not(account_id: nil)
                                        .first
          
          if expense_with_category
            account_id = expense_with_category.account_id
            
            # Check for existing category with same name in account
            existing = Category.find_by(
              account_id: account_id,
              name: category.name
            )
            
            if existing
              # Merge into existing category
              Expense.where(category_id: category.id)
                    .update_all(category_id: existing.id) unless dry_run
              
              category.destroy unless dry_run
              @stats[:categories_merged] += 1
            else
              # Assign to account
              category.update_columns(account_id: account_id) unless dry_run
              @stats[:categories_migrated] += 1
            end
          else
            # Orphaned category - assign to first account
            first_account = Account.first
            if first_account
              category.update_columns(account_id: first_account.id) unless dry_run
              @stats[:categories_orphaned] += 1
            end
          end
        end
        
        log_info "Categories: #{@stats[:categories_migrated]} migrated, #{@stats[:categories_merged]} merged"
      end
      
      def cleanup_orphaned_records
        log_info "Cleaning up orphaned records..."
        
        # Remove expenses without accounts
        orphaned = Expense.where(account_id: nil).count
        Expense.where(account_id: nil).destroy_all unless dry_run
        @stats[:orphaned_expenses_removed] = orphaned
        
        # Remove categories without accounts
        orphaned = Category.where(account_id: nil).count
        Category.where(account_id: nil).destroy_all unless dry_run
        @stats[:orphaned_categories_removed] = orphaned
      end
      
      def validate_migration!
        log_info "Validating migration..."
        
        # Check no NULL account_ids remain
        tables_to_check = %w[expenses categories email_accounts budgets]
        
        tables_to_check.each do |table|
          if ActiveRecord::Base.connection.table_exists?(table)
            null_count = ActiveRecord::Base.connection.execute(
              "SELECT COUNT(*) FROM #{table} WHERE account_id IS NULL"
            ).first['count'].to_i
            
            if null_count > 0
              raise "Found #{null_count} records in #{table} without account_id"
            end
          end
        end
        
        log_info "Validation passed!"
      end
      
      def report_statistics
        log_info "Migration Statistics:"
        @stats.each do |key, value|
          log_info "  #{key.to_s.humanize}: #{value}"
        end
      end
      
      def log_info(message)
        logger.info message
        puts message
      end
      
      def log_warning(message)
        logger.warn message
        puts "WARNING: #{message}"
      end
      
      def log_error(message)
        logger.error message
        puts "ERROR: #{message}"
      end
    end
  end
end
```

## Testing Requirements
- [ ] Migration specs:
  - Test with sample data
  - Verify all associations maintained
  - Check data integrity
  - Test rollback functionality
- [ ] Performance tests:
  - Measure migration time with large datasets
  - Monitor memory usage
  - Check for query optimization
- [ ] Integration tests:
  - Full migration flow
  - Rollback and re-migration
  - Edge cases and error handling
- [ ] Manual testing:
  - Dry run on production copy
  - Verify UI works post-migration
  - Check all features functional

## Deployment Strategy
1. **Pre-deployment**:
   - Full database backup
   - Run validation task
   - Dry run on production copy
   - Schedule maintenance window

2. **Deployment**:
   - Enable maintenance mode
   - Run migration with monitoring
   - Validate results
   - Test critical paths

3. **Post-deployment**:
   - Monitor for errors
   - Keep backup for 30 days
   - Document any issues
   - Update runbooks

## Rollback Plan
1. Stop application servers
2. Restore database from backup
3. Revert code to previous version
4. Clear all caches
5. Restart application servers
6. Verify functionality

## Risk Mitigation
- [ ] Test on production data copy
- [ ] Have DBA on standby
- [ ] Prepare rollback scripts
- [ ] Monitor system resources
- [ ] Have communication plan ready
- [ ] Document all steps

## Technical Implementation

### Database Considerations

#### Migration Code Examples
```ruby
# db/migrate/add_tenant_fields_to_expenses.rb
class AddTenantFieldsToExpenses < ActiveRecord::Migration[8.0]
  disable_ddl_transaction! # For concurrent index creation
  
  def up
    # Add account_id with concurrent index for zero-downtime
    add_column :expenses, :account_id, :bigint unless column_exists?(:expenses, :account_id)
    add_index :expenses, :account_id, algorithm: :concurrently, if_not_exists: true
    
    # Add composite indexes for performance
    add_index :expenses, [:account_id, :transaction_date], 
              algorithm: :concurrently, 
              name: 'idx_expenses_account_date',
              if_not_exists: true
    
    add_index :expenses, [:account_id, :category_id, :transaction_date],
              algorithm: :concurrently,
              name: 'idx_expenses_account_category_date',
              if_not_exists: true
    
    # Add visibility column with default
    add_column :expenses, :visibility, :integer, default: 0, null: false unless column_exists?(:expenses, :visibility)
    add_index :expenses, [:account_id, :visibility], 
              algorithm: :concurrently,
              name: 'idx_expenses_account_visibility',
              if_not_exists: true
  end
  
  def down
    remove_index :expenses, name: 'idx_expenses_account_visibility', if_exists: true
    remove_index :expenses, name: 'idx_expenses_account_category_date', if_exists: true
    remove_index :expenses, name: 'idx_expenses_account_date', if_exists: true
    remove_index :expenses, :account_id, if_exists: true
    remove_column :expenses, :visibility, if_exists: true
    remove_column :expenses, :account_id, if_exists: true
  end
end
```

#### Index Strategies for Performance
```ruby
# PostgreSQL-specific optimizations
class OptimizeTenantQueries < ActiveRecord::Migration[8.0]
  def up
    # Partial indexes for common queries
    execute <<-SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_pending_categorization
      ON expenses(account_id, created_at)
      WHERE category_id IS NULL;
    SQL
    
    # BRIN index for time-series data
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_expenses_transaction_date_brin
      ON expenses USING brin(transaction_date)
      WITH (pages_per_range = 128);
    SQL
    
    # Statistics target for better query planning
    execute <<-SQL
      ALTER TABLE expenses ALTER COLUMN account_id SET STATISTICS 1000;
      ANALYZE expenses;
    SQL
  end
end
```

#### Foreign Key Constraints
```ruby
# Ensure referential integrity with proper cascading
class AddForeignKeyConstraints < ActiveRecord::Migration[8.0]
  def up
    # Use validate: false initially, then validate in background
    add_foreign_key :expenses, :accounts, validate: false
    add_foreign_key :categories, :accounts, validate: false
    add_foreign_key :email_accounts, :accounts, validate: false
    
    # Validate constraints in background job to avoid locking
    ValidateForeignKeysJob.perform_later
  end
end

# app/jobs/validate_foreign_keys_job.rb
class ValidateForeignKeysJob < ApplicationJob
  def perform
    ActiveRecord::Base.connection.execute(
      "ALTER TABLE expenses VALIDATE CONSTRAINT fk_rails_expenses_accounts;"
    )
    # Repeat for other tables
  end
end
```

#### Data Integrity Measures
```ruby
# app/services/multi_tenancy/data_integrity_checker.rb
module Services
  module MultiTenancy
    class DataIntegrityChecker
      def check_all
        check_referential_integrity
        check_orphaned_records
        check_duplicate_prevention
        check_tenant_isolation
      end
      
      private
      
      def check_referential_integrity
        # Verify all foreign keys are valid
        sql = <<-SQL
          SELECT 'expenses' as table_name, COUNT(*) as orphaned_count
          FROM expenses e
          LEFT JOIN accounts a ON e.account_id = a.id
          WHERE e.account_id IS NOT NULL AND a.id IS NULL
          
          UNION ALL
          
          SELECT 'categories', COUNT(*)
          FROM categories c
          LEFT JOIN accounts a ON c.account_id = a.id
          WHERE c.account_id IS NOT NULL AND a.id IS NULL
        SQL
        
        results = ActiveRecord::Base.connection.execute(sql)
        results.each do |row|
          if row['orphaned_count'].to_i > 0
            raise "Found #{row['orphaned_count']} orphaned records in #{row['table_name']}"
          end
        end
      end
      
      def check_tenant_isolation
        # Verify no cross-tenant data leakage
        sql = <<-SQL
          SELECT e1.account_id, e2.account_id, COUNT(*)
          FROM expenses e1
          JOIN expense_relations er ON e1.id = er.expense_id
          JOIN expenses e2 ON er.related_expense_id = e2.id
          WHERE e1.account_id != e2.account_id
          GROUP BY e1.account_id, e2.account_id
        SQL
        
        violations = ActiveRecord::Base.connection.execute(sql)
        if violations.count > 0
          raise "Found cross-tenant data violations"
        end
      end
    end
  end
end
```

#### PostgreSQL-specific Optimizations
```ruby
# Use PostgreSQL advisory locks for migration safety
class MultiTenantMigrator
  MIGRATION_LOCK_ID = 12345
  
  def run!
    obtained_lock = obtain_advisory_lock
    unless obtained_lock
      raise "Could not obtain migration lock. Another migration may be running."
    end
    
    begin
      perform_migration
    ensure
      release_advisory_lock
    end
  end
  
  private
  
  def obtain_advisory_lock
    ActiveRecord::Base.connection.execute(
      "SELECT pg_try_advisory_lock(#{MIGRATION_LOCK_ID})"
    ).first['pg_try_advisory_lock']
  end
  
  def release_advisory_lock
    ActiveRecord::Base.connection.execute(
      "SELECT pg_advisory_unlock(#{MIGRATION_LOCK_ID})"
    )
  end
  
  def perform_migration
    # Use COPY for bulk data operations
    ActiveRecord::Base.connection.execute(<<-SQL)
      COPY (
        SELECT e.*, ea.account_id as new_account_id
        FROM expenses e
        JOIN email_accounts ea ON e.email_account_id = ea.id
        WHERE e.account_id IS NULL
      ) TO '/tmp/expenses_to_migrate.csv' WITH CSV HEADER;
    SQL
    
    # Process in batches with explicit memory management
    CSV.foreach('/tmp/expenses_to_migrate.csv', headers: true).each_slice(1000) do |batch|
      process_batch(batch)
      GC.start # Force garbage collection between batches
    end
  end
end
```

### Code Architecture

#### Migration Service Architecture
```ruby
# app/services/multi_tenancy/migration_orchestrator.rb
module Services
  module MultiTenancy
    class MigrationOrchestrator
      include ActiveModel::Model
      
      attr_accessor :dry_run, :batch_size, :parallel_workers
      
      validates :batch_size, numericality: { greater_than: 0, less_than_or_equal_to: 10000 }
      
      def initialize(dry_run: false, batch_size: 500, parallel_workers: 4)
        @dry_run = dry_run
        @batch_size = batch_size
        @parallel_workers = parallel_workers
        @progress_tracker = ProgressTracker.new
        @error_handler = ErrorHandler.new
      end
      
      def execute
        validate!
        
        with_transaction_management do
          with_performance_monitoring do
            execute_migration_pipeline
          end
        end
      end
      
      private
      
      def execute_migration_pipeline
        pipeline = [
          PreMigrationValidator.new,
          DatabaseBackupCreator.new,
          SchemaPreparator.new,
          DataTransformer.new(batch_size: batch_size),
          ParallelMigrator.new(workers: parallel_workers),
          PostMigrationValidator.new,
          IndexOptimizer.new,
          CacheWarmer.new
        ]
        
        pipeline.each do |step|
          @progress_tracker.start_step(step.class.name)
          
          begin
            step.execute(dry_run: dry_run)
            @progress_tracker.complete_step(step.class.name)
          rescue => e
            @error_handler.handle(e, step: step.class.name)
            raise unless @error_handler.can_continue?
          end
        end
      end
      
      def with_transaction_management(&block)
        if dry_run
          ActiveRecord::Base.transaction(requires_new: true) do
            yield
            raise ActiveRecord::Rollback
          end
        else
          # Use separate transactions for each major step
          yield
        end
      end
      
      def with_performance_monitoring(&block)
        start_time = Time.current
        initial_memory = GetProcessMem.new.mb
        
        yield
        
        duration = Time.current - start_time
        memory_delta = GetProcessMem.new.mb - initial_memory
        
        Rails.logger.info("Migration completed in #{duration}s, memory delta: #{memory_delta}MB")
      end
    end
  end
end
```

#### Error Handling Strategy
```ruby
# app/services/multi_tenancy/migration_error_handler.rb
module Services
  module MultiTenancy
    class MigrationErrorHandler
      attr_reader :errors, :warnings
      
      def initialize
        @errors = []
        @warnings = []
        @recoverable_errors = Set.new([
          ActiveRecord::LockWaitTimeout,
          ActiveRecord::StatementTimeout,
          PG::TRDeadlockDetected
        ])
      end
      
      def handle(error, context = {})
        log_error(error, context)
        
        if recoverable?(error)
          handle_recoverable(error, context)
        else
          handle_critical(error, context)
        end
      end
      
      private
      
      def recoverable?(error)
        @recoverable_errors.include?(error.class) ||
          error.message.include?('timeout') ||
          error.message.include?('deadlock')
      end
      
      def handle_recoverable(error, context)
        @warnings << {
          error: error.class.name,
          message: error.message,
          context: context,
          timestamp: Time.current,
          retry_count: context[:retry_count] || 0
        }
        
        if context[:retry_count].to_i < 3
          sleep(2 ** context[:retry_count].to_i) # Exponential backoff
          retry_operation(context)
        else
          escalate_to_critical(error, context)
        end
      end
      
      def handle_critical(error, context)
        @errors << {
          error: error.class.name,
          message: error.message,
          backtrace: error.backtrace&.first(10),
          context: context,
          timestamp: Time.current
        }
        
        notify_operations_team(error, context)
        initiate_rollback if should_rollback?(error)
        
        raise MigrationCriticalError, "Critical error during migration: #{error.message}"
      end
      
      def should_rollback?(error)
        error.is_a?(DataIntegrityError) ||
          error.message.include?('constraint violation') ||
          error.message.include?('data corruption')
      end
    end
  end
end
```

### Migration Strategy

#### Step-by-Step Technical Migration Approach
```ruby
# lib/migration_strategies/zero_downtime_migrator.rb
class ZeroDowntimeMigrator
  def execute
    # Phase 1: Schema preparation (can run while app is live)
    prepare_schema_changes
    
    # Phase 2: Dual-write phase (app writes to both old and new structures)
    enable_dual_write_mode
    
    # Phase 3: Background data migration
    migrate_existing_data_in_background
    
    # Phase 4: Verification and consistency checks
    verify_data_consistency
    
    # Phase 5: Switch reads to new structure
    switch_read_path
    
    # Phase 6: Stop writes to old structure
    disable_old_write_path
    
    # Phase 7: Cleanup old structure (can be delayed)
    schedule_cleanup
  end
  
  private
  
  def prepare_schema_changes
    # Add new columns without NOT NULL constraints initially
    ActiveRecord::Base.connection.execute(<<-SQL)
      ALTER TABLE expenses 
      ADD COLUMN IF NOT EXISTS account_id BIGINT,
      ADD COLUMN IF NOT EXISTS visibility INTEGER DEFAULT 0;
    SQL
    
    # Create indexes concurrently
    ActiveRecord::Base.connection.execute(<<-SQL)
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_account_id 
      ON expenses(account_id);
    SQL
  end
  
  def enable_dual_write_mode
    # Deploy app version that writes to both old and new fields
    # This is handled via feature flags
    FeatureFlag.enable(:dual_write_mode)
    
    # Example model callback
    # class Expense < ApplicationRecord
    #   after_save :sync_to_new_structure, if: -> { FeatureFlag.enabled?(:dual_write_mode) }
    # end
  end
  
  def migrate_existing_data_in_background
    MigrationWorker.perform_async(
      batch_size: 1000,
      pause_between_batches: 100.milliseconds,
      priority: :low
    )
  end
end

# app/workers/migration_worker.rb
class MigrationWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low_priority, retry: 10
  
  def perform(options = {})
    batch_size = options['batch_size'] || 1000
    pause_ms = options['pause_between_batches'] || 100
    
    unmigrated_count = EmailAccount.where(account_id: nil).count
    batches = (unmigrated_count / batch_size.to_f).ceil
    
    batches.times do |batch_num|
      migrate_batch(batch_size, batch_num)
      sleep(pause_ms / 1000.0) # Pause to reduce database load
      
      # Check system load and adjust
      if database_load_high?
        sleep(1) # Additional pause if load is high
      end
    end
  end
  
  private
  
  def database_load_high?
    active_connections = ActiveRecord::Base.connection.execute(
      "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'"
    ).first['count'].to_i
    
    active_connections > 50 # Threshold for high load
  end
end
```

#### Data Validation and Integrity Checks
```ruby
# app/services/multi_tenancy/migration_validator.rb
module Services
  module MultiTenancy
    class MigrationValidator
      def validate_pre_migration
        validations = [
          check_source_data_completeness,
          check_no_active_transactions,
          check_disk_space,
          check_database_connections
        ]
        
        validations.all?
      end
      
      def validate_post_migration
        validations = [
          check_all_records_migrated,
          check_referential_integrity,
          check_data_consistency,
          check_performance_benchmarks
        ]
        
        validations.all?
      end
      
      private
      
      def check_source_data_completeness
        # Verify source data is complete and valid
        issues = []
        
        # Check for NULL emails in EmailAccounts
        null_emails = EmailAccount.where(email: nil).count
        issues << "Found #{null_emails} EmailAccounts with NULL email" if null_emails > 0
        
        # Check for orphaned expenses
        orphaned = Expense.left_joins(:email_account)
                         .where(email_accounts: { id: nil })
                         .count
        issues << "Found #{orphaned} orphaned expenses" if orphaned > 0
        
        if issues.any?
          Rails.logger.error "Pre-migration validation failed: #{issues.join(', ')}"
          return false
        end
        
        true
      end
      
      def check_data_consistency
        # Compare counts and checksums
        sql = <<-SQL
          WITH old_system AS (
            SELECT 
              COUNT(*) as expense_count,
              SUM(amount_cents) as total_amount,
              COUNT(DISTINCT email_account_id) as account_count
            FROM expenses
            WHERE email_account_id IS NOT NULL
          ),
          new_system AS (
            SELECT 
              COUNT(*) as expense_count,
              SUM(amount_cents) as total_amount,
              COUNT(DISTINCT account_id) as account_count
            FROM expenses
            WHERE account_id IS NOT NULL
          )
          SELECT 
            old_system.expense_count = new_system.expense_count as count_match,
            old_system.total_amount = new_system.total_amount as amount_match,
            old_system.account_count <= new_system.account_count as account_match
          FROM old_system, new_system
        SQL
        
        result = ActiveRecord::Base.connection.execute(sql).first
        
        unless result['count_match'] && result['amount_match'] && result['account_match']
          raise "Data consistency check failed"
        end
        
        true
      end
    end
  end
end
```

### Performance Considerations

#### Database Query Optimization
```ruby
# app/models/concerns/tenant_performance_optimizations.rb
module TenantPerformanceOptimizations
  extend ActiveSupport::Concern
  
  included do
    # Use prepared statements for common queries
    scope :for_account_optimized, ->(account_id) {
      # Use index hint for PostgreSQL
      from("#{table_name} /*+ INDEX(#{table_name} idx_#{table_name}_account_id) */")
        .where(account_id: account_id)
    }
    
    # Batch loading for associations
    scope :with_associations_optimized, -> {
      includes(:category, :email_account)
        .references(:categories, :email_accounts)
    }
  end
  
  class_methods do
    # Optimized count query using index-only scan
    def optimized_count_for_account(account_id)
      connection.execute(
        sanitize_sql_array([
          "SELECT COUNT(*) FROM #{table_name} WHERE account_id = ? /*+ INDEX_ONLY */",
          account_id
        ])
      ).first['count'].to_i
    end
    
    # Use EXPLAIN to verify query plans in development
    def explain_query_for_account(account_id)
      sql = sanitize_sql_array([
        "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM #{table_name} WHERE account_id = ?",
        account_id
      ])
      connection.execute(sql).values
    end
  end
end
```

#### Memory Usage Optimization
```ruby
# app/services/multi_tenancy/memory_efficient_migrator.rb
module Services
  module MultiTenancy
    class MemoryEfficientMigrator
      BATCH_SIZE = 500
      MEMORY_LIMIT_MB = 512
      
      def migrate_large_dataset
        # Use find_in_batches to avoid loading all records
        EmailAccount.find_in_batches(batch_size: BATCH_SIZE) do |batch|
          process_batch(batch)
          
          # Check memory usage and garbage collect if needed
          if memory_usage_high?
            GC.start(full_mark: true, immediate_sweep: true)
            sleep(0.5) # Brief pause for GC to complete
          end
        end
      end
      
      private
      
      def process_batch(batch)
        # Use raw SQL for updates to avoid AR overhead
        account_mappings = batch.map do |ea|
          "('#{ea.id}', '#{create_account_for(ea).id}')"
        end.join(',')
        
        ActiveRecord::Base.connection.execute(<<-SQL)
          UPDATE email_accounts 
          SET account_id = mappings.account_id
          FROM (VALUES #{account_mappings}) AS mappings(id, account_id)
          WHERE email_accounts.id = mappings.id::bigint
        SQL
      end
      
      def memory_usage_high?
        GetProcessMem.new.mb > MEMORY_LIMIT_MB
      end
    end
  end
end
```

### Security Implementation

#### Tenant Isolation Verification
```ruby
# app/services/multi_tenancy/tenant_isolation_verifier.rb
module Services
  module MultiTenancy
    class TenantIsolationVerifier
      def verify_complete_isolation
        verify_model_scoping
        verify_controller_filtering
        verify_service_boundaries
        verify_database_constraints
      end
      
      private
      
      def verify_model_scoping
        # Test that default scopes are applied
        ActsAsTenant.without_tenant do
          # Should raise an error or return empty
          begin
            Expense.all.to_a
            raise "Tenant scoping not enforced on Expense model!"
          rescue ActsAsTenant::Errors::NoTenantSet
            # Expected behavior
          end
        end
      end
      
      def verify_database_constraints
        # Try to insert data violating tenant isolation
        account1 = Account.first
        account2 = Account.second
        
        expense = account1.expenses.create!(
          amount_cents: 100,
          description: "Test"
        )
        
        # Try to associate with different account's category
        category = account2.categories.first
        
        begin
          expense.update!(category_id: category.id)
          raise "Cross-tenant association allowed!"
        rescue ActiveRecord::RecordInvalid
          # Expected behavior
        end
      end
    end
  end
end
```

### Testing Strategy

#### Migration Test Helpers
```ruby
# spec/support/migration_test_helpers.rb
module MigrationTestHelpers
  def setup_pre_migration_state
    # Create data in old structure
    @email_accounts = create_list(:email_account, 5, account_id: nil)
    @expenses = @email_accounts.flat_map do |ea|
      create_list(:expense, 10, email_account: ea, account_id: nil)
    end
    @categories = create_list(:category, 10, account_id: nil)
  end
  
  def run_migration(dry_run: false)
    migrator = Services::MultiTenancy::MultiTenantMigrator.new(dry_run: dry_run)
    migrator.run!
  end
  
  def verify_migration_success
    # Check all email accounts have accounts
    expect(EmailAccount.where(account_id: nil).count).to eq(0)
    
    # Check all expenses migrated
    expect(Expense.where(account_id: nil).count).to eq(0)
    
    # Check user creation
    @email_accounts.each do |ea|
      ea.reload
      expect(ea.account).to be_present
      expect(ea.account.users.count).to be > 0
    end
    
    # Verify data integrity
    original_expense_sum = @expenses.sum(&:amount_cents)
    migrated_expense_sum = Expense.sum(:amount_cents)
    expect(migrated_expense_sum).to eq(original_expense_sum)
  end
  
  def benchmark_migration_performance
    time = Benchmark.realtime { run_migration }
    
    expect(time).to be < 60.seconds # For test dataset
    
    # Check query performance post-migration
    account = Account.first
    query_time = Benchmark.realtime do
      account.expenses.includes(:category).limit(100).to_a
    end
    
    expect(query_time).to be < 0.05 # 50ms target
  end
end
```

#### Performance Test Benchmarks
```ruby
# spec/performance/migration_performance_spec.rb
require 'rails_helper'

RSpec.describe 'Migration Performance', type: :performance do
  before do
    # Create large dataset for performance testing
    create_large_test_dataset(
      email_accounts: 100,
      expenses_per_account: 1000,
      categories: 50
    )
  end
  
  it 'completes migration within performance targets' do
    metrics = {}
    
    # Measure overall time
    metrics[:total_time] = Benchmark.realtime do
      Services::MultiTenancy::MultiTenantMigrator.new.run!
    end
    
    # Measure memory usage
    metrics[:peak_memory] = GetProcessMem.new.mb
    
    # Verify performance targets
    expect(metrics[:total_time]).to be < 300.seconds # 5 minutes for 100k records
    expect(metrics[:peak_memory]).to be < 1024 # Less than 1GB RAM
    
    # Log metrics for monitoring
    Rails.logger.info "Migration Performance Metrics: #{metrics}"
  end
  
  it 'maintains query performance post-migration' do
    run_migration
    
    # Test common query patterns
    account = Account.first
    
    # Dashboard query
    dashboard_time = Benchmark.realtime do
      account.expenses
             .where(transaction_date: 30.days.ago..Date.current)
             .includes(:category)
             .group(:category_id)
             .sum(:amount_cents)
    end
    
    expect(dashboard_time).to be < 0.05 # 50ms target
    
    # Search query
    search_time = Benchmark.realtime do
      account.expenses
             .where("description ILIKE ?", "%payment%")
             .order(transaction_date: :desc)
             .limit(50)
             .to_a
    end
    
    expect(search_time).to be < 0.1 # 100ms target
  end
end
```

### Risk Mitigation

#### Critical Path Dependencies
```ruby
# app/services/multi_tenancy/dependency_checker.rb
module Services
  module MultiTenancy
    class DependencyChecker
      CRITICAL_DEPENDENCIES = {
        gems: {
          'acts_as_tenant' => '~> 1.0',
          'pg' => '~> 1.5',
          'sidekiq' => '~> 7.0'
        },
        database_extensions: %w[uuid-ossp pgcrypto],
        system_resources: {
          min_memory_gb: 4,
          min_disk_space_gb: 10,
          min_cpu_cores: 2
        }
      }.freeze
      
      def check_all
        check_gem_versions
        check_database_extensions
        check_system_resources
        check_database_version
      end
      
      private
      
      def check_gem_versions
        CRITICAL_DEPENDENCIES[:gems].each do |gem_name, version_requirement|
          installed_version = Gem.loaded_specs[gem_name]&.version&.to_s
          
          unless installed_version && Gem::Requirement.new(version_requirement).satisfied_by?(Gem::Version.new(installed_version))
            raise "Required gem #{gem_name} #{version_requirement} not satisfied (found: #{installed_version})"
          end
        end
      end
      
      def check_database_version
        result = ActiveRecord::Base.connection.execute("SELECT version()").first
        version = result['version']
        
        unless version.include?('PostgreSQL') && version.match(/\d+/).to_s.to_i >= 13
          raise "PostgreSQL 13+ required (found: #{version})"
        end
      end
    end
  end
end
```

### Code Quality Standards

#### Migration Code Review Checklist
```ruby
# .github/pull_request_template/migration_checklist.md
# Migration Code Review Checklist

## Database Changes
- [ ] All migrations are reversible
- [ ] Indexes created concurrently for zero downtime
- [ ] Foreign keys added with `validate: false` initially
- [ ] No breaking changes to existing columns
- [ ] Migration tested on production-size dataset

## Performance
- [ ] Query execution plans reviewed (EXPLAIN ANALYZE)
- [ ] N+1 queries prevented
- [ ] Batch processing for large datasets
- [ ] Memory usage stays under 512MB
- [ ] Response times meet <50ms target

## Security
- [ ] Tenant isolation verified
- [ ] No SQL injection vulnerabilities
- [ ] Sensitive data properly handled
- [ ] Audit trail maintained

## Testing
- [ ] Unit tests for all migration logic
- [ ] Integration tests for full flow
- [ ] Performance benchmarks pass
- [ ] Rollback tested successfully

## Documentation
- [ ] Runbook updated
- [ ] Monitoring alerts configured
- [ ] Team notified of changes
```

## Definition of Done
- [ ] Migration script fully implemented
- [ ] Dry run mode working
- [ ] Rollback functionality tested
- [ ] All data integrity checks pass
- [ ] Performance benchmarks met (<50ms queries, <5min migration for 100k records)
- [ ] Documentation complete
- [ ] Runbook created
- [ ] Tested on production copy
- [ ] Code reviewed by senior developer
- [ ] DBA approval obtained
- [ ] Rollback plan tested
- [ ] Zero-downtime deployment verified
- [ ] Monitoring and alerts configured
- [ ] Load testing completed successfully