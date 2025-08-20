# Ticket 2.1: Add Tenant Scoping to All Models

## Ticket Information
- **Epic**: Epic 2 - Multi-tenancy (Weeks 3-4)
- **Priority**: HIGH
- **Story Points**: 8
- **Risk Level**: HIGH
- **Dependencies**: 
  - Epic 1 completed (Foundation)

## Description
Add account_id (tenant identifier) to all existing models and implement acts_as_tenant scoping. This is a critical ticket that modifies the core data model to support multi-tenancy. All existing models must be updated to belong to an account, with proper scoping and validation.

## Technical Requirements
1. Add account_id foreign key to all tenant-scoped tables
2. Create and apply ActsAsAccountScoped concern
3. Update all model associations
4. Add proper database indexes
5. Implement automatic tenant assignment
6. Update existing scopes to respect tenant boundaries

## Acceptance Criteria
- [ ] account_id column added to all tenant-scoped tables:
  - expenses
  - categories
  - email_accounts
  - budgets
  - parsing_rules
  - sync_sessions
  - user_category_preferences
  - categorization_patterns
  - bulk_operations
- [ ] ActsAsAccountScoped concern created and includes:
  - acts_as_tenant(:account) declaration
  - Automatic account assignment on create
  - Tenant-specific scopes
  - Validation for account presence
- [ ] All models updated to include the concern:
  - Expense model
  - Category model
  - EmailAccount model
  - Budget model
  - ParsingRule model
  - SyncSession model
  - UserCategoryPreference model
  - CategorizationPattern model
  - BulkOperation model
- [ ] Database indexes added for optimal performance:
  - Single column index on account_id
  - Compound indexes for common queries
  - Partial indexes where appropriate
- [ ] Existing scopes updated to respect tenant boundaries
- [ ] No data accessible across tenant boundaries
- [ ] All existing tests updated and passing

## Implementation Details
```ruby
# db/migrate/add_tenant_scoping_to_models.rb
class AddTenantScopingToModels < ActiveRecord::Migration[8.0]
  def change
    # Add account_id to all tenant-scoped tables
    tables_to_scope = %w[
      expenses categories budgets email_accounts
      parsing_rules sync_sessions user_category_preferences
      categorization_patterns bulk_operations
    ]
    
    tables_to_scope.each do |table_name|
      unless column_exists?(table_name, :account_id)
        add_reference table_name, :account, foreign_key: true, null: true
        
        # Add performance indexes
        add_index table_name, [:account_id, :created_at]
        
        # Table-specific compound indexes
        case table_name
        when 'expenses'
          add_index table_name, [:account_id, :transaction_date, :deleted_at]
          add_index table_name, [:account_id, :category_id]
          add_index table_name, [:account_id, :email_account_id]
        when 'categories'
          add_index table_name, [:account_id, :name], unique: true
          add_index table_name, [:account_id, :deleted_at]
        when 'email_accounts'
          add_index table_name, [:account_id, :email], unique: true
        when 'budgets'
          add_index table_name, [:account_id, :category_id]
          add_index table_name, [:account_id, :start_date, :end_date]
        end
      end
    end
  end
end

# app/models/concerns/acts_as_account_scoped.rb
module ActsAsAccountScoped
  extend ActiveSupport::Concern
  
  included do
    acts_as_tenant(:account)
    
    # Automatic account assignment
    before_validation :set_account, on: :create
    
    # Validation
    validates :account, presence: true
    
    # Scopes
    scope :for_account, ->(account) { where(account: account) }
    scope :for_current_account, -> { where(account: ActsAsTenant.current_tenant) }
  end
  
  private
  
  def set_account
    self.account ||= ActsAsTenant.current_tenant
    
    if self.account.nil?
      errors.add(:account, "must be set for #{self.class.name}")
      throw :abort
    end
  end
end

# app/models/expense.rb (updated)
class Expense < ApplicationRecord
  include ActsAsAccountScoped
  
  # Existing associations
  belongs_to :email_account
  belongs_to :category, optional: true
  belongs_to :user, optional: true # Who created it
  
  # Update scopes to respect tenant
  scope :recent, -> { order(transaction_date: :desc) }
  scope :for_month, ->(date) { 
    where(transaction_date: date.beginning_of_month..date.end_of_month)
  }
  
  # Remove any global scopes that could leak data
  # default_scope -> { where(account: ActsAsTenant.current_tenant) } 
  # ^ This is handled by acts_as_tenant
end

# Similar updates for all other models...
```

## Data Migration Strategy
- [ ] Create temporary backup of all tables
- [ ] Run migration in transaction
- [ ] Set account_id to default migrated account for existing records
- [ ] Verify no NULL account_id values remain
- [ ] Add NOT NULL constraint to account_id in follow-up migration

## Testing Requirements
- [ ] Unit tests for ActsAsAccountScoped concern:
  - Automatic account assignment
  - Validation of account presence
  - Scoping behavior
- [ ] Model tests for each updated model:
  - Tenant isolation verified
  - Cannot access other tenant's data
  - Scopes respect tenant boundaries
- [ ] Integration tests:
  - Data isolation across requests
  - Tenant switching doesn't leak data
  - Background jobs respect tenant context
- [ ] Performance tests:
  - Query performance with tenant scoping
  - Index effectiveness
  - No N+1 queries introduced

## Performance Considerations
- [ ] All account_id columns must have indexes
- [ ] Compound indexes for common query patterns
- [ ] Monitor query performance after migration
- [ ] Consider partitioning for large tables
- [ ] Update query optimizer statistics

## Security Considerations
- [ ] Verify acts_as_tenant prevents cross-tenant access
- [ ] Audit all custom SQL queries for tenant scoping
- [ ] Ensure background jobs maintain tenant context
- [ ] Add logging for tenant boundary violations
- [ ] Review all finder methods for proper scoping

## Rollback Plan
1. Remove ActsAsAccountScoped from all models
2. Drop account_id columns from all tables
3. Restore from backup if data corrupted
4. Revert code changes
5. Clear cache

## Technical Implementation

### Database Considerations

#### Migration with Zero Downtime
```ruby
# db/migrate/add_account_id_to_models_safely.rb
class AddAccountIdToModelsSafely < ActiveRecord::Migration[8.0]
  disable_ddl_transaction! # Allow concurrent index creation
  
  def up
    tables_to_migrate.each do |table_config|
      table_name = table_config[:name]
      
      # Step 1: Add column without NOT NULL constraint
      unless column_exists?(table_name, :account_id)
        add_column table_name, :account_id, :bigint
      end
      
      # Step 2: Add foreign key without validation (validate later)
      unless foreign_key_exists?(table_name, :accounts)
        add_foreign_key table_name, :accounts, validate: false
      end
      
      # Step 3: Add indexes concurrently
      add_concurrent_indexes(table_name, table_config[:indexes])
    end
    
    # Step 4: Validate foreign keys in background
    ValidateForeignKeysJob.set(wait: 5.minutes).perform_later(tables_to_migrate.map { |t| t[:name] })
  end
  
  def down
    tables_to_migrate.each do |table_config|
      table_name = table_config[:name]
      
      # Remove indexes first
      table_config[:indexes].each do |index_config|
        remove_index table_name, name: index_config[:name], if_exists: true
      end
      
      # Remove foreign key and column
      remove_foreign_key table_name, :accounts, if_exists: true
      remove_column table_name, :account_id, if_exists: true
    end
  end
  
  private
  
  def tables_to_migrate
    [
      {
        name: 'expenses',
        indexes: [
          { columns: [:account_id], name: 'idx_expenses_account' },
          { columns: [:account_id, :transaction_date], name: 'idx_expenses_account_date' },
          { columns: [:account_id, :category_id], name: 'idx_expenses_account_category' },
          { columns: [:account_id, :email_account_id], name: 'idx_expenses_account_email' },
          { columns: [:account_id, :deleted_at], name: 'idx_expenses_account_deleted', where: 'deleted_at IS NULL' }
        ]
      },
      {
        name: 'categories',
        indexes: [
          { columns: [:account_id], name: 'idx_categories_account' },
          { columns: [:account_id, :name], name: 'idx_categories_account_name', unique: true },
          { columns: [:account_id, :deleted_at], name: 'idx_categories_account_deleted', where: 'deleted_at IS NULL' }
        ]
      },
      {
        name: 'email_accounts',
        indexes: [
          { columns: [:account_id], name: 'idx_email_accounts_account' },
          { columns: [:account_id, :email], name: 'idx_email_accounts_account_email', unique: true }
        ]
      },
      {
        name: 'budgets',
        indexes: [
          { columns: [:account_id], name: 'idx_budgets_account' },
          { columns: [:account_id, :category_id], name: 'idx_budgets_account_category' },
          { columns: [:account_id, :start_date, :end_date], name: 'idx_budgets_account_period' }
        ]
      }
    ]
  end
  
  def add_concurrent_indexes(table_name, indexes)
    indexes.each do |index_config|
      index_name = index_config[:name]
      columns = index_config[:columns]
      options = {
        algorithm: :concurrently,
        if_not_exists: true,
        name: index_name
      }
      
      options[:unique] = true if index_config[:unique]
      options[:where] = index_config[:where] if index_config[:where]
      
      add_index table_name, columns, **options
    end
  end
end
```

#### PostgreSQL-Specific Performance Optimizations
```ruby
# db/migrate/optimize_tenant_queries.rb
class OptimizeTenantQueries < ActiveRecord::Migration[8.0]
  def up
    # Create partial indexes for common filtered queries
    execute <<-SQL
      -- Expenses pending categorization per account
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_uncategorized
      ON expenses(account_id, created_at DESC)
      WHERE category_id IS NULL AND deleted_at IS NULL;
      
      -- Active categories per account
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_categories_active
      ON categories(account_id, LOWER(name))
      WHERE deleted_at IS NULL;
      
      -- Recent expenses for dashboard
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_expenses_recent
      ON expenses(account_id, transaction_date DESC)
      WHERE transaction_date > CURRENT_DATE - INTERVAL '90 days';
    SQL
    
    # BRIN indexes for time-series data
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS idx_expenses_date_brin
      ON expenses USING brin(account_id, transaction_date)
      WITH (pages_per_range = 32);
    SQL
    
    # Update table statistics for better query planning
    execute <<-SQL
      ALTER TABLE expenses ALTER COLUMN account_id SET STATISTICS 1000;
      ALTER TABLE categories ALTER COLUMN account_id SET STATISTICS 500;
      ANALYZE expenses, categories, email_accounts;
    SQL
    
    # Create custom statistics for correlated columns
    execute <<-SQL
      CREATE STATISTICS IF NOT EXISTS expenses_account_category
      ON account_id, category_id FROM expenses;
      
      CREATE STATISTICS IF NOT EXISTS expenses_account_date
      ON account_id, transaction_date FROM expenses;
    SQL
  end
end
```

#### Data Integrity Constraints
```ruby
# db/migrate/add_tenant_constraints.rb
class AddTenantConstraints < ActiveRecord::Migration[8.0]
  def up
    # Add check constraints to ensure tenant consistency
    execute <<-SQL
      -- Ensure expenses reference categories from same account
      ALTER TABLE expenses
      ADD CONSTRAINT chk_expense_category_same_account
      CHECK (
        category_id IS NULL OR
        EXISTS (
          SELECT 1 FROM categories c
          WHERE c.id = expenses.category_id
          AND c.account_id = expenses.account_id
        )
      )
      NOT VALID;
      
      -- Validate constraint in background to avoid locking
      ALTER TABLE expenses VALIDATE CONSTRAINT chk_expense_category_same_account;
    SQL
    
    # Add trigger to enforce cross-tenant reference prevention
    execute <<-SQL
      CREATE OR REPLACE FUNCTION prevent_cross_tenant_references()
      RETURNS TRIGGER AS $$
      BEGIN
        -- Check category belongs to same account
        IF NEW.category_id IS NOT NULL THEN
          PERFORM 1 FROM categories
          WHERE id = NEW.category_id
          AND account_id = NEW.account_id;
          
          IF NOT FOUND THEN
            RAISE EXCEPTION 'Category % does not belong to account %',
              NEW.category_id, NEW.account_id;
          END IF;
        END IF;
        
        -- Check email_account belongs to same account
        IF NEW.email_account_id IS NOT NULL THEN
          PERFORM 1 FROM email_accounts
          WHERE id = NEW.email_account_id
          AND account_id = NEW.account_id;
          
          IF NOT FOUND THEN
            RAISE EXCEPTION 'EmailAccount % does not belong to account %',
              NEW.email_account_id, NEW.account_id;
          END IF;
        END IF;
        
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      
      CREATE TRIGGER enforce_tenant_consistency
      BEFORE INSERT OR UPDATE ON expenses
      FOR EACH ROW
      EXECUTE FUNCTION prevent_cross_tenant_references();
    SQL
  end
end
```

### Code Architecture

#### Enhanced ActsAsAccountScoped Concern
```ruby
# app/models/concerns/acts_as_account_scoped.rb
module ActsAsAccountScoped
  extend ActiveSupport::Concern
  
  included do
    # Core tenant setup
    acts_as_tenant(:account)
    
    # Associations
    belongs_to :account, inverse_of: model_name.plural.to_sym
    
    # Validations
    validates :account, presence: true
    validate :ensure_tenant_consistency
    
    # Callbacks
    before_validation :set_account_from_context, on: :create
    after_initialize :verify_tenant_context
    
    # Default scope handled by acts_as_tenant
    # Additional scopes
    scope :for_account, ->(account) {
      unscoped.where(account: account)
    }
    
    scope :accessible_by, ->(user) {
      joins(:account)
        .joins("INNER JOIN account_memberships am ON am.account_id = accounts.id")
        .where("am.user_id = ?", user.id)
    }
    
    # Class-level configuration
    class_attribute :tenant_safe_attributes, default: []
    class_attribute :cross_tenant_associations, default: []
  end
  
  class_methods do
    # Mark attributes that can be set without tenant context
    def tenant_safe_attribute(*attrs)
      self.tenant_safe_attributes += attrs.map(&:to_s)
    end
    
    # Mark associations that can cross tenant boundaries
    def allow_cross_tenant_association(*assocs)
      self.cross_tenant_associations += assocs.map(&:to_s)
    end
    
    # Bulk operations with tenant safety
    def bulk_insert_with_tenant(records, account = ActsAsTenant.current_tenant)
      raise ActsAsTenant::Errors::NoTenantSet if account.nil?
      
      records_with_account = records.map do |record|
        record.merge(account_id: account.id)
      end
      
      insert_all(records_with_account)
    end
    
    # Safe find methods that enforce tenant
    def find_by_id_for_account(id, account = ActsAsTenant.current_tenant)
      for_account(account).find_by(id: id)
    end
  end
  
  private
  
  def set_account_from_context
    self.account ||= ActsAsTenant.current_tenant
    
    if account.nil? && !tenant_safe_operation?
      errors.add(:account, "must be set for #{self.class.name}")
      throw :abort
    end
  end
  
  def verify_tenant_context
    return if new_record?
    return if account_id.nil? # Migration in progress
    
    if ActsAsTenant.current_tenant && account_id != ActsAsTenant.current_tenant.id
      unless explicitly_allowed_cross_tenant?
        raise ActsAsTenant::Errors::TenantAccessViolation,
              "Attempted to access #{self.class.name}##{id} from wrong tenant context"
      end
    end
  end
  
  def ensure_tenant_consistency
    return if account.nil?
    
    # Check all belongs_to associations for tenant consistency
    self.class.reflect_on_all_associations(:belongs_to).each do |association|
      next if association.name == :account
      next if cross_tenant_associations.include?(association.name.to_s)
      
      associated = send(association.name)
      next if associated.nil?
      
      if associated.respond_to?(:account_id) && associated.account_id != account_id
        errors.add(association.name, "must belong to the same account")
      end
    end
  end
  
  def tenant_safe_operation?
    # Check if operation is allowed without tenant
    return true if Rails.env.test? && ENV['SKIP_TENANT_CHECKS']
    false
  end
  
  def explicitly_allowed_cross_tenant?
    # Check if cross-tenant access is explicitly allowed
    Thread.current[:allow_cross_tenant_access] == true
  end
end
```

#### Model Implementation Patterns
```ruby
# app/models/expense.rb
class Expense < ApplicationRecord
  include ActsAsAccountScoped
  include SoftDeletable
  
  # Associations with tenant validation
  belongs_to :category, optional: true
  belongs_to :email_account
  belongs_to :user, optional: true
  
  # Has many through with tenant scoping
  has_many :expense_tags, dependent: :destroy
  has_many :tags, through: :expense_tags
  
  # Tenant-aware validations
  validates :description, presence: true
  validates :amount_cents, numericality: { greater_than: 0 }
  validate :category_belongs_to_account
  validate :email_account_belongs_to_account
  
  # Scopes that automatically respect tenant
  scope :recent, -> { order(transaction_date: :desc) }
  scope :uncategorized, -> { where(category_id: nil) }
  scope :for_period, ->(start_date, end_date) {
    where(transaction_date: start_date..end_date)
  }
  
  # Optimize queries with includes
  scope :with_associations, -> {
    includes(:category, :email_account, :tags)
  }
  
  # Custom tenant-aware methods
  def self.monthly_summary(month = Date.current)
    for_period(month.beginning_of_month, month.end_of_month)
      .group(:category_id)
      .sum(:amount_cents)
  end
  
  def self.search(query)
    where("description ILIKE ? OR merchant_name ILIKE ?", "%#{query}%", "%#{query}%")
  end
  
  private
  
  def category_belongs_to_account
    return if category_id.nil?
    
    unless category&.account_id == account_id
      errors.add(:category, "must belong to the same account")
    end
  end
  
  def email_account_belongs_to_account
    return if email_account_id.nil?
    
    unless email_account&.account_id == account_id
      errors.add(:email_account, "must belong to the same account")
    end
  end
end

# app/models/category.rb
class Category < ApplicationRecord
  include ActsAsAccountScoped
  
  # Associations
  has_many :expenses, dependent: :nullify
  has_many :budgets, dependent: :destroy
  has_many :categorization_patterns, dependent: :destroy
  
  # Validations with tenant uniqueness
  validates :name, presence: true,
                   uniqueness: { scope: :account_id,
                               case_sensitive: false,
                               message: "already exists in this account" }
  
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/,
                             message: "must be a valid hex color" },
                   allow_nil: true
  
  # Tenant-aware scopes
  scope :active, -> { where(deleted_at: nil) }
  scope :with_expenses, -> { joins(:expenses).distinct }
  scope :ordered, -> { order(:name) }
  
  # Optimize category loading
  def self.for_select
    ordered.pluck(:name, :id)
  end
  
  # Calculate spending with tenant safety
  def total_spending(period = nil)
    scope = expenses
    scope = scope.for_period(period.beginning_of_month, period.end_of_month) if period
    scope.sum(:amount_cents)
  end
end
```

### acts_as_tenant Integration Best Practices

#### Configuration and Setup
```ruby
# config/initializers/acts_as_tenant.rb
ActsAsTenant.configure do |config|
  # Require tenant to be set explicitly
  config.require_tenant = true
  
  # Custom error handling
  config.tenant_not_set_exception = ActsAsTenant::Errors::NoTenantSet
  
  # Enable query caching per tenant
  config.query_caching = true
  
  # Performance: Use prepared statements
  config.use_prepared_statements = true
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :set_current_account
  
  private
  
  def set_current_account
    if user_signed_in?
      # Use most recently accessed account or default
      account = current_user.current_account ||
                current_user.accounts.first
      
      if account
        set_current_tenant(account)
        
        # Store in request store for background jobs
        RequestStore.store[:current_account_id] = account.id
      else
        redirect_to new_account_path,
                   alert: "Please create or join an account first"
      end
    end
  end
  
  # Helper to switch tenant context temporarily
  def with_account(account, &block)
    ActsAsTenant.with_tenant(account, &block)
  end
  
  # Verify tenant access for specific resources
  def ensure_account_access!(resource)
    unless resource.account_id == current_tenant.id
      raise ActsAsTenant::Errors::TenantAccessViolation
    end
  end
end
```

#### Background Job Tenant Context
```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  include ActsAsTenant::JobExtensions
  
  # Automatically capture and restore tenant context
  before_enqueue :capture_tenant
  before_perform :restore_tenant
  
  private
  
  def capture_tenant
    self.tenant_id = ActsAsTenant.current_tenant&.id
  end
  
  def restore_tenant
    if tenant_id.present?
      account = Account.find(tenant_id)
      ActsAsTenant.current_tenant = account
    end
  end
  
  # Enhanced error handling
  rescue_from ActsAsTenant::Errors::NoTenantSet do |exception|
    Rails.logger.error "Job executed without tenant context: #{self.class.name}"
    raise exception unless Rails.env.development?
  end
end

# Example job with tenant safety
class ProcessExpensesJob < ApplicationJob
  def perform(expense_ids)
    # Tenant is automatically set from context
    expenses = Expense.where(id: expense_ids)
    
    expenses.find_each do |expense|
      # Verify expense belongs to current tenant
      ensure_same_tenant!(expense)
      
      # Process expense
      Services::Categorization::AutoCategorizer.new(expense).categorize!
    end
  end
  
  private
  
  def ensure_same_tenant!(resource)
    unless resource.account_id == ActsAsTenant.current_tenant.id
      raise "Attempted to process resource from different tenant"
    end
  end
end
```

### Performance Considerations

#### Query Optimization Strategies
```ruby
# app/models/concerns/tenant_query_optimizer.rb
module TenantQueryOptimizer
  extend ActiveSupport::Concern
  
  class_methods do
    # Use prepared statements for common queries
    def prepare_tenant_statements
      connection.prepare(
        "tenant_expenses",
        "SELECT * FROM expenses WHERE account_id = $1 ORDER BY transaction_date DESC LIMIT $2"
      )
      
      connection.prepare(
        "tenant_categories",
        "SELECT * FROM categories WHERE account_id = $1 AND deleted_at IS NULL ORDER BY name"
      )
    end
    
    # Efficient bulk loading with tenant
    def bulk_load_for_tenant(ids, account = ActsAsTenant.current_tenant)
      return [] if ids.empty?
      
      # Use WHERE IN with tenant constraint
      where(account: account, id: ids)
        .load
    end
    
    # Optimize count queries
    def fast_count_for_tenant(account = ActsAsTenant.current_tenant)
      connection.select_value(
        sanitize_sql_array([
          "SELECT COUNT(*) FROM #{table_name} WHERE account_id = ?",
          account.id
        ])
      ).to_i
    end
  end
end

# app/services/tenant_performance_monitor.rb
class TenantPerformanceMonitor
  def self.analyze_query_performance(account)
    results = {}
    
    # Check index usage
    results[:index_usage] = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT 
        schemaname,
        tablename,
        indexname,
        idx_scan,
        idx_tup_read,
        idx_tup_fetch
      FROM pg_stat_user_indexes
      WHERE schemaname = 'public'
      AND indexname LIKE '%account%'
      ORDER BY idx_scan DESC;
    SQL
    
    # Check slow queries
    results[:slow_queries] = ActiveRecord::Base.connection.execute(<<-SQL)
      SELECT 
        query,
        calls,
        mean_exec_time,
        total_exec_time
      FROM pg_stat_statements
      WHERE query LIKE '%account_id%'
      AND mean_exec_time > 50
      ORDER BY mean_exec_time DESC
      LIMIT 10;
    SQL
    
    results
  end
end
```

### Security Implementation

#### Tenant Isolation Enforcement
```ruby
# app/services/security/tenant_isolation_enforcer.rb
module Security
  class TenantIsolationEnforcer
    class TenantViolation < StandardError; end
    
    def self.enforce!
      install_query_interceptor
      install_association_validators
      enable_audit_logging
    end
    
    private
    
    def self.install_query_interceptor
      ActiveRecord::Base.connection.class.prepend(QueryInterceptor)
    end
    
    module QueryInterceptor
      TENANT_TABLES = %w[expenses categories budgets email_accounts].freeze
      
      def execute(sql, name = nil)
        validate_tenant_query(sql) if should_validate?(sql)
        super
      end
      
      def exec_query(sql, name = nil, binds = [])
        validate_tenant_query(sql) if should_validate?(sql)
        super
      end
      
      private
      
      def should_validate?(sql)
        return false if sql.downcase.start_with?('select pg_')
        
        TENANT_TABLES.any? { |table| sql.include?(table) }
      end
      
      def validate_tenant_query(sql)
        if extract_table_from_query(sql) && !sql.include?('account_id')
          unless allowed_query?(sql)
            raise TenantViolation, "Query missing tenant constraint: #{sql[0..100]}"
          end
        end
      end
      
      def allowed_query?(sql)
        # Allow schema queries and migrations
        sql.include?('information_schema') ||
        sql.include?('pg_') ||
        sql.include?('ALTER TABLE') ||
        sql.include?('CREATE INDEX')
      end
      
      def extract_table_from_query(sql)
        sql.match(/FROM\s+(\w+)/i)&.captures&.first
      end
    end
    
    def self.install_association_validators
      ActiveRecord::Base.descendants.each do |model|
        next unless model.column_names.include?('account_id')
        
        model.class_eval do
          # Validate associations on save
          before_save :validate_tenant_associations
          
          def validate_tenant_associations
            self.class.reflect_on_all_associations.each do |association|
              next if association.name == :account
              
              if associated = send(association.name)
                if associated.respond_to?(:account_id)
                  if associated.account_id != self.account_id
                    errors.add(association.name, "crosses tenant boundary")
                    throw :abort
                  end
                end
              end
            end
          end
        end
      end
    end
    
    def self.enable_audit_logging
      ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        
        if potential_violation?(event.payload[:sql])
          Rails.logger.warn("Potential tenant violation: #{event.payload[:sql][0..200]}")
          
          TenantAuditLog.create!(
            query: event.payload[:sql],
            account_id: ActsAsTenant.current_tenant&.id,
            user_id: Current.user&.id,
            controller: Current.controller_name,
            action: Current.action_name,
            flagged_at: Time.current
          )
        end
      end
    end
    
    def self.potential_violation?(sql)
      # Detection logic for suspicious queries
      sql.include?('account_id IS NULL') ||
      sql.match(/WHERE\s+1\s*=\s*1/i) ||
      (sql.include?('DELETE') && !sql.include?('account_id'))
    end
  end
end

# config/initializers/tenant_security.rb
Rails.application.config.after_initialize do
  Security::TenantIsolationEnforcer.enforce! if Rails.env.production?
end
```

### Testing Strategy

#### RSpec Helpers for Tenant Testing
```ruby
# spec/support/tenant_test_helpers.rb
module TenantTestHelpers
  def with_tenant(account, &block)
    ActsAsTenant.with_tenant(account, &block)
  end
  
  def without_tenant(&block)
    ActsAsTenant.without_tenant(&block)
  end
  
  def create_tenant_context(user: nil)
    account = create(:account)
    user ||= create(:user)
    create(:account_membership, account: account, user: user, role: :owner)
    
    ActsAsTenant.current_tenant = account
    Current.user = user
    
    { account: account, user: user }
  end
  
  def expect_tenant_isolation
    account1 = create(:account)
    account2 = create(:account)
    
    # Create data in account1
    with_tenant(account1) do
      @account1_expense = create(:expense)
      @account1_category = create(:category)
    end
    
    # Try to access from account2
    with_tenant(account2) do
      expect(Expense.find_by(id: @account1_expense.id)).to be_nil
      expect(Category.find_by(id: @account1_category.id)).to be_nil
    end
  end
end

RSpec.configure do |config|
  config.include TenantTestHelpers
  
  config.before(:each, type: :model) do
    # Ensure clean tenant state
    ActsAsTenant.current_tenant = nil
  end
  
  config.before(:each, :tenant) do
    create_tenant_context
  end
end
```

#### Comprehensive Tenant Isolation Tests
```ruby
# spec/models/concerns/acts_as_account_scoped_spec.rb
RSpec.describe ActsAsAccountScoped do
  let(:account1) { create(:account) }
  let(:account2) { create(:account) }
  
  describe 'tenant isolation' do
    it 'prevents access to other tenant data' do
      expense1 = with_tenant(account1) { create(:expense) }
      expense2 = with_tenant(account2) { create(:expense) }
      
      with_tenant(account1) do
        expect(Expense.all).to include(expense1)
        expect(Expense.all).not_to include(expense2)
      end
    end
    
    it 'prevents cross-tenant associations' do
      category1 = with_tenant(account1) { create(:category) }
      
      with_tenant(account2) do
        expense = build(:expense, category: category1)
        expect(expense).not_to be_valid
        expect(expense.errors[:category]).to include("must belong to the same account")
      end
    end
    
    it 'automatically sets account on create' do
      with_tenant(account1) do
        expense = Expense.create!(valid_expense_attributes)
        expect(expense.account).to eq(account1)
      end
    end
    
    it 'raises error when no tenant is set' do
      without_tenant do
        expect {
          Expense.create!(valid_expense_attributes)
        }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
      end
    end
  end
  
  describe 'performance' do
    it 'uses indexes for tenant queries' do
      with_tenant(account1) do
        create_list(:expense, 100)
        
        expect {
          Expense.all.load
        }.to make_database_queries(count: 1, matching: /account_id/)
        
        # Verify index usage
        explain = Expense.connection.execute(
          "EXPLAIN SELECT * FROM expenses WHERE account_id = #{account1.id}"
        )
        expect(explain.values.flatten.join).to include('Index Scan')
      end
    end
  end
end
```

### Risk Mitigation

#### Gradual Rollout Strategy
```ruby
# lib/tenant_migration/gradual_rollout.rb
module TenantMigration
  class GradualRollout
    def self.execute
      # Phase 1: Add columns and indexes
      AddTenantColumns.new.up
      
      # Phase 2: Deploy code with dual-write
      enable_dual_write_mode
      
      # Phase 3: Backfill data in batches
      backfill_tenant_data
      
      # Phase 4: Add NOT NULL constraints
      add_null_constraints
      
      # Phase 5: Enable tenant enforcement
      enable_tenant_enforcement
    end
    
    private
    
    def self.enable_dual_write_mode
      # Feature flag to write to both old and new structure
      Flipper.enable(:dual_write_tenant_data)
      
      # Monitor for issues
      TenantMigrationMonitor.start
    end
    
    def self.backfill_tenant_data
      tables = %w[expenses categories budgets]
      
      tables.each do |table|
        BackfillTenantDataJob.perform_later(
          table_name: table,
          batch_size: 1000,
          sleep_between: 0.1
        )
      end
    end
    
    def self.add_null_constraints
      # Only after all data is migrated
      if verify_no_null_tenant_ids
        AddNotNullToTenantColumns.new.up
      else
        raise "Cannot add NOT NULL constraints: NULL account_ids found"
      end
    end
    
    def self.verify_no_null_tenant_ids
      tables = %w[expenses categories budgets]
      
      tables.all? do |table|
        count = ActiveRecord::Base.connection.select_value(
          "SELECT COUNT(*) FROM #{table} WHERE account_id IS NULL"
        ).to_i
        
        count == 0
      end
    end
  end
end
```

### Code Quality Standards

#### Tenant Code Review Checklist
```markdown
# Tenant Implementation Review Checklist

## Model Changes
- [ ] ActsAsAccountScoped concern included
- [ ] account_id indexed appropriately
- [ ] Compound indexes for common queries
- [ ] Associations validate same tenant
- [ ] Scopes respect tenant boundaries
- [ ] No global scopes that bypass tenant

## Query Patterns
- [ ] All queries include account_id
- [ ] No raw SQL without tenant constraint
- [ ] Joins maintain tenant boundary
- [ ] Aggregations scoped to tenant

## Performance
- [ ] Explain plan shows index usage
- [ ] No full table scans
- [ ] Query time < 50ms
- [ ] No N+1 queries

## Security
- [ ] Cross-tenant access prevented
- [ ] Validation of associations
- [ ] Audit logging enabled
- [ ] No data leakage in logs

## Testing
- [ ] Isolation tests pass
- [ ] Performance benchmarks met
- [ ] Edge cases covered
- [ ] Background jobs tested
```

## Definition of Done
- [ ] All models include ActsAsAccountScoped concern
- [ ] All migrations executed successfully
- [ ] No NULL account_id values in database
- [ ] All existing tests updated and passing
- [ ] New tests for tenant isolation passing
- [ ] Performance benchmarks show <5% degradation
- [ ] Query response time < 50ms with tenant scoping
- [ ] Security audit confirms no data leakage
- [ ] Cross-tenant reference prevention verified
- [ ] Background jobs maintain tenant context
- [ ] Documentation updated with tenant model
- [ ] Code reviewed by senior developer
- [ ] Load testing completed (1000+ concurrent tenants)
- [ ] Rollback plan tested on staging
- [ ] Monitoring and alerts configured for tenant violations