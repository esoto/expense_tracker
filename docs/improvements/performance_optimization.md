# Performance Optimization - Expense Tracker

## Current Performance Status
- **API Token Auth**: O(1) lookup with token_hash ✅
- **Database Indexes**: Comprehensive composite indexes added ✅
- **Test Suite**: 615 tests in 4.87 seconds ✅
- **PostgreSQL**: Migrated from SQLite ✅

## High Priority Optimizations

### 1. Fix N+1 Queries in DashboardService

**File**: `app/services/dashboard_service.rb`

**Problem**: The sync_info method causes N+1 queries

**Current problematic code** (lines 86-96):
```ruby
def sync_info
  last_expenses = Expense.select("email_account_id, MAX(created_at) as last_created")
                        .group(:email_account_id)
                        .includes(:email_account)  # This doesn't work with custom select
  
  sync_data = {}
  last_expenses.each do |expense|
    sync_data[expense.email_account_id] = {
      last_sync: expense.last_created,
      account: expense.email_account  # N+1 query here!
    }
  end
```

**Optimized solution**:
```ruby
def sync_info
  # Single query approach
  sync_data = EmailAccount.active
    .left_joins(:expenses)
    .group(:id)
    .select('email_accounts.*, MAX(expenses.created_at) as last_expense_created')
    .index_by(&:id)
    .transform_values do |account|
      {
        last_sync: account.last_expense_created,
        account: account
      }
    end

  # Check for running jobs
  running_jobs = SolidQueue::Job.where(
    class_name: "ProcessEmailsJob",
    finished_at: nil
  ).where("created_at > ?", 5.minutes.ago)

  sync_data[:has_running_jobs] = running_jobs.exists?
  sync_data[:running_job_count] = running_jobs.count

  sync_data
end
```

### 2. Fix N+1 in Recent Expenses

**File**: `app/services/dashboard_service.rb`

**Update line 42**:
```ruby
def recent_expenses
  Expense.includes(:category, :email_account)  # Add :email_account
         .order(transaction_date: :desc, created_at: :desc)
         .limit(10)
end
```

### 3. Implement Dashboard Caching

**File**: `app/services/dashboard_service.rb`

**Complete cached implementation**:
```ruby
class DashboardService
  CACHE_EXPIRY = 5.minutes

  def analytics
    # Don't cache sync_info as it needs real-time data
    sync_data = sync_info
    
    # Cache everything else
    cached_analytics = Rails.cache.fetch("dashboard_analytics", expires_in: CACHE_EXPIRY) do
      {
        totals: calculate_totals,
        recent_expenses: recent_expenses,
        category_breakdown: category_breakdown,
        monthly_trend: monthly_trend,
        bank_breakdown: bank_breakdown,
        top_merchants: top_merchants,
        email_accounts: active_email_accounts
      }
    end
    
    # Merge real-time sync info with cached data
    cached_analytics.merge(sync_info: sync_data)
  end

  # Add cache clearing
  def self.clear_cache
    Rails.cache.delete_matched("dashboard_*")
  end
end
```

**File**: `app/models/expense.rb`

**Add cache invalidation**:
```ruby
class Expense < ApplicationRecord
  # existing code...
  
  after_commit :clear_dashboard_cache
  
  private
  
  def clear_dashboard_cache
    DashboardService.clear_cache
  end
end
```

## Medium Priority Optimizations

### 1. Add Missing Duplicate Detection Index

**Create migration**: `rails g migration AddDuplicateDetectionIndex`

```ruby
class AddDuplicateDetectionIndex < ActiveRecord::Migration[8.0]
  def change
    # Optimize duplicate detection queries
    add_index :expenses, [:email_account_id, :amount, :transaction_date], 
              name: "index_expenses_on_account_amount_date_for_duplicates"
              
    # Also add index for merchant name lookups
    add_index :expenses, :merchant_name,
              name: "index_expenses_on_merchant_name"
  end
end
```

### 2. Optimize ExpensesController Queries

**File**: `app/controllers/expenses_controller.rb`

**Optimized index method**:
```ruby
def index
  # Base query with includes
  @expenses = Expense.includes(:category, :email_account)
  
  # Apply filters efficiently
  @expenses = apply_filters(@expenses)
  
  # Order and limit
  @expenses = @expenses.order(transaction_date: :desc, created_at: :desc)
                      .limit(25)
  
  # Calculate summary with separate optimized query
  calculate_summary_statistics
end

private

def apply_filters(scope)
  # Use left_joins instead of joins to maintain includes
  scope = scope.left_joins(:category).where(categories: { name: params[:category] }) if params[:category].present?
  scope = scope.where(transaction_date: params[:start_date]..params[:end_date]) if date_range_present?
  scope = scope.where(bank_name: params[:bank]) if params[:bank].present?
  scope
end

def date_range_present?
  params[:start_date].present? && params[:end_date].present?
end

def calculate_summary_statistics
  # Build a separate query for aggregations
  summary_scope = Expense.all
  summary_scope = apply_filters(summary_scope)
  
  # Single query for both sum and count
  result = summary_scope.pick('SUM(amount)', 'COUNT(*)')
  @total_amount = result[0] || 0
  @expense_count = result[1] || 0
  
  # Category summary with single query
  @categories_summary = summary_scope
    .joins(:category)
    .group("categories.name")
    .sum(:amount)
    .sort_by { |_, amount| -amount }
end
```

### 3. Background Job Optimization

**File**: `app/jobs/process_emails_job.rb`

**Optimized batch processing**:
```ruby
class ProcessEmailsJob < ApplicationJob
  queue_as :email_processing
  
  # Add retry logic
  retry_on ImapConnectionService::ConnectionError, wait: :exponentially_longer, attempts: 3
  retry_on Net::ReadTimeout, wait: 5.seconds, attempts: 2
  
  # Add performance monitoring
  around_perform do |job, block|
    start_time = Time.current
    account_id = job.arguments.first
    
    Rails.logger.info "[ProcessEmailsJob] Starting for account #{account_id}"
    
    block.call
    
    duration = Time.current - start_time
    Rails.logger.info "[ProcessEmailsJob] Completed in #{duration.round(2)}s"
    
    # Alert on slow processing
    if duration > 30.seconds
      Rails.logger.warn "[ProcessEmailsJob] Slow processing: #{duration.round(2)}s for account #{account_id}"
    end
  end

  def perform(email_account_id = nil, since: 1.week.ago)
    if email_account_id
      process_single_account(email_account_id, since)
    else
      process_all_accounts_in_batches(since)
    end
  end

  private

  def process_all_accounts_in_batches(since)
    EmailAccount.active.find_in_batches(batch_size: 5) do |batch|
      batch.each do |email_account|
        ProcessEmailsJob.perform_later(email_account.id, since: since)
      end
      
      # Prevent IMAP server overload
      sleep(1) if batch.size == 5
    end
  end
end
```

### 4. Memory Optimization for Email Processing

**File**: `app/services/email_processing/parser.rb`

**Memory-efficient email processing**:
```ruby
class EmailProcessing::Parser
  MAX_EMAIL_SIZE = 50_000  # 50KB threshold
  TRUNCATE_SIZE = 10_000   # Store only 10KB for large emails

  def email_content
    @email_content ||= begin
      content = email_data[:body].to_s
      
      if content.bytesize > MAX_EMAIL_SIZE
        process_large_email(content)
      else
        process_standard_email(content)
      end
    end
  end

  private

  def process_large_email(content)
    # Extract only the essential parts for large emails
    Rails.logger.warn "[EmailProcessing] Large email detected: #{content.bytesize} bytes"
    
    # Process in chunks to avoid memory bloat
    processed = StringIO.new
    content.each_line.first(100).each do |line|  # Process only first 100 lines
      processed << decode_quoted_printable_line(line)
    end
    
    result = processed.string.force_encoding("UTF-8").scrub
    processed.close
    result
  end

  def process_standard_email(content)
    content = content.gsub(/=\r\n/, "")
    content = content.gsub(/=([A-F0-9]{2})/) { [$1.hex].pack("C") }
    content.force_encoding("UTF-8").scrub
  end

  def decode_quoted_printable_line(line)
    line.gsub(/=\r\n/, "")
        .gsub(/=([A-F0-9]{2})/) { [$1.hex].pack("C") }
  end
end
```

**File**: `app/jobs/process_email_job.rb`

**Update save_failed_parsing to limit stored content**:
```ruby
def save_failed_parsing(email_account, email_data, errors)
  email_body = email_data[:body].to_s
  truncated = false
  
  if email_body.bytesize > TRUNCATE_SIZE
    email_body = email_body.byteslice(0, TRUNCATE_SIZE) + "\n... [truncated]"
    truncated = true
  end

  Expense.create!(
    email_account: email_account,
    amount: 0.01,
    transaction_date: Time.current,
    merchant_name: nil,  # Explicitly set to nil for failed parsing
    description: "Failed to parse: #{errors.first}",  # Only first error
    raw_email_content: email_body,
    parsed_data: { 
      errors: errors,
      truncated: truncated,
      original_size: email_data[:body].to_s.bytesize
    }.to_json,
    status: "failed",
    bank_name: email_account.bank_name
  )
end
```

## Low Priority Optimizations

### 1. API Token Caching

**File**: `app/models/api_token.rb`

**Add application-level caching**:
```ruby
def self.authenticate(token_string)
  return nil unless token_string.present?

  # Short-lived cache for successful authentications
  cache_key = "api_token:#{Digest::SHA256.hexdigest(token_string)[0..16]}"
  
  Rails.cache.fetch(cache_key, expires_in: 1.minute) do
    token_hash = Digest::SHA256.hexdigest(token_string)
    api_token = active.find_by(token_hash: token_hash)
    
    if api_token&.valid_token?
      api_token.touch_last_used!
      api_token
    else
      nil
    end
  end
end
```

### 2. Database Connection Pool Tuning

**File**: `config/database.yml`

```yaml
production:
  primary:
    <<: *default
    database: expense_tracker_production
    pool: <%= ENV.fetch("RAILS_MAX_THREADS", 25) %>
    checkout_timeout: 5
    reaping_frequency: 10
    idle_timeout: 300
    
  # Add read replica for reporting queries
  replica:
    <<: *default
    database: expense_tracker_production
    replica: true
    pool: 5
```

### 3. Add Query Monitoring

**File**: `config/initializers/slow_query_logger.rb`

```ruby
# Log slow queries in development and staging
if Rails.env.development? || Rails.env.staging?
  ActiveSupport::Notifications.subscribe "sql.active_record" do |name, start, finish, id, payload|
    duration = (finish - start) * 1000  # Convert to milliseconds
    
    if duration > 100  # Log queries slower than 100ms
      Rails.logger.warn "[SLOW QUERY] #{duration.round(2)}ms: #{payload[:sql]}"
    end
  end
end
```

## Performance Monitoring Commands

```bash
# Analyze query performance
rails runner "puts Expense.connection.execute('EXPLAIN ANALYZE SELECT * FROM expenses WHERE merchant_name IS NULL').values"

# Check index usage
rails db:indexes

# Memory profiling
RAILS_ENV=production bundle exec derailed bundle:mem

# Benchmark specific endpoints
ab -n 100 -c 10 -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3000/api/webhooks/recent_expenses

# Check cache hit rates
rails runner "puts Rails.cache.stats"
```

## Expected Performance Improvements

1. **Dashboard Loading**: 5-10x faster with caching (from ~50ms to ~5-10ms)
2. **N+1 Query Fix**: Reduce database queries from 15+ to 3-4 per dashboard load
3. **Memory Usage**: 50% reduction in large email processing
4. **API Response Time**: 30% improvement with token caching
5. **Background Jobs**: More reliable with retry logic and monitoring

## Monitoring Metrics to Track

- Average response time for dashboard
- Cache hit rate
- Background job processing time
- Memory usage during email processing
- Database query count per request
- Slow query frequency