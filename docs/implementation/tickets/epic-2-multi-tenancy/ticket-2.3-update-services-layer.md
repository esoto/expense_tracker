# Ticket 2.3: Update Service Layer for Multi-tenancy

## Ticket Information
- **Epic**: Epic 2 - Multi-tenancy (Weeks 3-4)
- **Priority**: HIGH
- **Story Points**: 8
- **Risk Level**: HIGH
- **Dependencies**: 
  - Ticket 2.1 (Tenant Scoping Models)
  - Ticket 2.2 (Update Controllers)

## Description
Update all service objects to work within tenant context. This includes email processing services, categorization services, and infrastructure services. Services must maintain tenant isolation, properly set tenant context for background jobs, and handle multi-tenant scenarios correctly.

## Technical Requirements
1. Update all services to accept/use tenant context
2. Modify background jobs to maintain tenant context
3. Update email sync to be tenant-aware
4. Fix categorization services for tenant isolation
5. Create multi-tenant service utilities
6. Update monitoring and broadcast services

## Acceptance Criteria
- [ ] Email services updated:
  - ProcessingService works within account context
  - SyncService maintains tenant isolation
  - Email parsing respects account-specific rules
  - Sync sessions scoped to account
- [ ] Categorization services updated:
  - BulkCategorizationService scoped to account
  - Pattern matching uses account-specific patterns
  - ML categorization trained per account
  - Category suggestions account-specific
- [ ] Infrastructure services updated:
  - BroadcastService sends to account-specific channels
  - MonitoringService tracks per-account metrics
  - CacheService uses tenant-aware keys
- [ ] Background jobs maintain tenant context:
  - Tenant ID passed to job arguments
  - Tenant context restored in job execution
  - Jobs fail gracefully if tenant missing
- [ ] New utility services created:
  - TenantContextService for context management
  - AccountCreatorService for new accounts
  - TenantSwitcherService for switching logic
  - DataMigratorService for migration

## Implementation Details
```ruby
# app/services/concerns/tenant_aware.rb
module TenantAware
  extend ActiveSupport::Concern
  
  included do
    attr_reader :account
  end
  
  def initialize(account, *args, **kwargs)
    @account = account
    super(*args, **kwargs) if defined?(super)
  end
  
  def with_tenant(&block)
    ActsAsTenant.with_tenant(account, &block)
  end
  
  def ensure_tenant_context!
    raise "No account context provided" unless account
    ActsAsTenant.current_tenant = account
  end
end

# app/services/email/processing_service.rb (updated)
module Services
  module Email
    class ProcessingService
      include TenantAware
      
      def initialize(account, email_account)
        @account = account
        @email_account = email_account
        validate_email_account!
      end
      
      def process_emails
        with_tenant do
          fetch_emails.each do |email|
            process_single_email(email)
          end
        end
      end
      
      private
      
      def validate_email_account!
        unless @email_account.account_id == @account.id
          raise "EmailAccount doesn't belong to the current account"
        end
      end
      
      def process_single_email(email)
        # Processing logic with tenant context
        expense = create_expense_from_email(email)
        categorize_expense(expense)
        broadcast_new_expense(expense)
      end
      
      def create_expense_from_email(email)
        @account.expenses.create!(
          email_account: @email_account,
          amount: extract_amount(email),
          description: extract_description(email),
          transaction_date: extract_date(email),
          merchant_name: extract_merchant(email),
          user: @email_account.default_user
        )
      end
      
      def categorize_expense(expense)
        Services::Categorization::AutoCategorizer
          .new(@account, expense)
          .categorize
      end
      
      def broadcast_new_expense(expense)
        Services::Infrastructure::BroadcastService
          .new(@account)
          .broadcast_expense_created(expense)
      end
    end
  end
end

# app/services/categorization/bulk_categorization_service.rb (updated)
module Services
  module Categorization
    class BulkCategorizationService
      include TenantAware
      
      def initialize(account, expense_ids, category_id)
        @account = account
        @expense_ids = expense_ids
        @category_id = category_id
      end
      
      def execute
        with_tenant do
          validate_inputs!
          
          expenses = @account.expenses.where(id: @expense_ids)
          category = @account.categories.find(@category_id)
          
          ActiveRecord::Base.transaction do
            expenses.update_all(
              category_id: category.id,
              categorized_at: Time.current,
              auto_categorized: false
            )
            
            create_categorization_pattern(expenses, category)
            update_stats(expenses.count, category)
          end
          
          { success: true, count: expenses.count }
        end
      rescue => e
        { success: false, error: e.message }
      end
      
      private
      
      def validate_inputs!
        raise "No expenses provided" if @expense_ids.blank?
        raise "Invalid category" unless @account.categories.exists?(@category_id)
      end
      
      def create_categorization_pattern(expenses, category)
        # Learn from manual categorization
        patterns = expenses.map(&:merchant_name).uniq.compact
        
        patterns.each do |pattern|
          @account.categorization_patterns.find_or_create_by(
            pattern: pattern,
            category: category
          ) do |p|
            p.confidence_score = 0.8
            p.usage_count = 1
          end
        end
      end
    end
  end
end

# app/jobs/concerns/tenant_job.rb
module TenantJob
  extend ActiveSupport::Concern
  
  included do
    before_perform :set_tenant_context
    after_perform :clear_tenant_context
    
    rescue_from ActsAsTenant::Errors::NoTenantSet do |exception|
      Rails.logger.error "Job failed: No tenant context - #{exception.message}"
      # Optionally retry or notify
    end
  end
  
  def set_tenant_context
    if arguments.first.is_a?(Hash) && arguments.first['account_id']
      account = Account.find(arguments.first['account_id'])
      ActsAsTenant.current_tenant = account
    end
  end
  
  def clear_tenant_context
    ActsAsTenant.current_tenant = nil
  end
end

# app/jobs/email_sync_job.rb (updated)
class EmailSyncJob < ApplicationJob
  include TenantJob
  
  def perform(account_id, email_account_id)
    account = Account.find(account_id)
    email_account = account.email_accounts.find(email_account_id)
    
    ActsAsTenant.with_tenant(account) do
      Services::Email::ProcessingService
        .new(account, email_account)
        .process_emails
    end
  end
end

# app/services/multi_tenancy/tenant_context_service.rb
module Services
  module MultiTenancy
    class TenantContextService
      def self.with_account(account, &block)
        previous_tenant = ActsAsTenant.current_tenant
        
        begin
          ActsAsTenant.current_tenant = account
          yield
        ensure
          ActsAsTenant.current_tenant = previous_tenant
        end
      end
      
      def self.clear_context
        ActsAsTenant.current_tenant = nil
      end
      
      def self.current_account
        ActsAsTenant.current_tenant
      end
      
      def self.ensure_context!(account = nil)
        account ||= ActsAsTenant.current_tenant
        raise "No tenant context available" unless account
        ActsAsTenant.current_tenant = account
      end
    end
  end
end
```

## Testing Requirements
- [ ] Service specs with tenant context:
  - Services properly scope data
  - Cannot access other tenant's data
  - Tenant context maintained throughout execution
- [ ] Background job specs:
  - Jobs maintain tenant context
  - Jobs fail gracefully without tenant
  - Tenant context cleared after job
- [ ] Integration tests:
  - Email processing respects tenant
  - Categorization uses tenant patterns
  - Broadcasting to correct channels
- [ ] Performance tests:
  - Service execution time with tenant scoping
  - Background job performance
  - Caching effectiveness

## Performance Considerations
- [ ] Cache tenant-specific data appropriately
- [ ] Batch operations within tenant context
- [ ] Optimize database queries with proper indexes
- [ ] Monitor background job queue times
- [ ] Use connection pooling efficiently

## Security Considerations
- [ ] Verify tenant isolation in all services
- [ ] Audit service access patterns
- [ ] Log tenant context violations
- [ ] Prevent tenant context manipulation
- [ ] Secure background job arguments

## Migration Strategy
- [ ] Update existing job arguments to include account_id
- [ ] Migrate running jobs gracefully
- [ ] Handle jobs without tenant context
- [ ] Provide fallback for legacy code

## Definition of Done
- [ ] All services updated with TenantAware concern
- [ ] Background jobs maintain tenant context
- [ ] Email processing fully tenant-aware
- [ ] Categorization services isolated per tenant
- [ ] Infrastructure services support multi-tenancy
- [ ] All service tests passing
- [ ] Integration tests verify isolation
- [ ] Performance benchmarks met
- [ ] Security audit completed
- [ ] Documentation updated with service patterns
- [ ] Code reviewed and approved