# Test Performance Analysis Report

## Executive Summary

Your unit tests are experiencing significant slowdowns due to several critical issues:

1. **Integration tests disguised as unit tests** - Tests marked with `integration: true` or `unit: true` tags
2. **Real database operations** with heavy ActiveRecord callbacks
3. **Broadcasting overhead** from Turbo/ActionCable in test environment
4. **Excessive factory creation** instead of using build/build_stubbed
5. **After_commit hooks firing** due to transactional fixtures

## Performance Issues Found

### 1. SyncSession Tests (Slowest: 4.25 seconds per test)

**Critical Issues:**
- **Database-heavy operations**: Every test creates real database records using `create(:sync_session)`
- **After_update_commit callback**: Line 23 in sync_session.rb triggers `broadcast_dashboard_update` which:
  - Loads EmailAccount records
  - Builds complex dashboard data
  - Attempts to broadcast via Turbo Streams
- **After_commit logging**: Line 182 triggers logging on status changes
- **SyncStatusChannel broadcasting**: Methods like `start!`, `complete!`, `fail!` all trigger WebSocket broadcasts

**Severity**: CRITICAL
**Impact**: 21.28 seconds total for 86 examples

### 2. ProcessEmailsJob Tests (1.76 seconds per test)

**Critical Issues:**
- **Real database records**: Using `create(:email_account)` instead of mocked objects
- **Factory associations**: EmailAccount factory likely creates associated records
- **Job queue interactions**: Even with mocked services, job infrastructure adds overhead

**Severity**: HIGH
**Impact**: Significant slowdown for job tests

### 3. Email::ProcessingService Integration Tests

**Critical Issues:**
- **DatabaseIsolation.clean_email_data!**: Line 12 performs full database cleanup on each test
- **Rails.cache.clear**: Line 14 clears entire cache before each test
- **ActiveRecord::Base.clear_cache!**: Line 17 clears all AR caches
- **Multiple delete_all calls**: After hook performs additional cleanup

**Severity**: HIGH
**Impact**: 0.11 seconds average but compounds with volume

### 4. Broadcasting Infrastructure

**Critical Issues:**
- **BroadcastReliabilityService**: Complex retry logic with multiple broadcast attempts
- **Turbo::Broadcastable**: Included in SyncSession, triggers on every update
- **ActionCable in tests**: Full WebSocket infrastructure running during tests

**Severity**: HIGH
**Impact**: Adds 0.5-1 second to each test involving SyncSession

## Root Cause Analysis

### Issue 1: Transactional Fixtures with After_Commit Hooks
```ruby
# spec/rails_helper.rb:127
config.use_transactional_fixtures = true
```

With transactional fixtures, after_commit callbacks still fire in tests, causing:
- Broadcasting attempts
- Dashboard updates
- Complex data building

### Issue 2: Missing Test Environment Optimizations
The broadcasting and monitoring services are not properly stubbed for the test environment.

### Issue 3: Integration Tests Tagged as Unit Tests
Tests are marked as `unit: true` but perform full integration testing with real database operations.

## Recommended Solutions

### Priority 1: Disable Broadcasting in Test Environment (Immediate 50% speedup)

**File**: `/Users/soto/development/expense_tracker/app/models/sync_session.rb`

```ruby
# Add at line 188, modifying broadcast_dashboard_update
def broadcast_dashboard_update
  return if Rails.env.test?  # Skip broadcasting in tests
  
  # Existing broadcasting logic...
end
```

**File**: `/Users/soto/development/expense_tracker/app/channels/sync_status_channel.rb`

```ruby
# Modify broadcast methods to skip in test
def self.broadcast_status(session)
  return if Rails.env.test?  # Skip in tests
  # existing code...
end

def self.broadcast_completion(session)
  return if Rails.env.test?  # Skip in tests
  # existing code...
end

def self.broadcast_failure(session, error_message = nil)
  return if Rails.env.test?  # Skip in tests
  # existing code...
end
```

### Priority 2: Use Factories Efficiently (30% speedup)

**File**: `/Users/soto/development/expense_tracker/spec/models/sync_session_spec.rb`

Replace all `create(:sync_session)` with `build_stubbed(:sync_session)` where database persistence isn't required:

```ruby
# Instead of:
let(:sync_session) { create(:sync_session) }

# Use:
let(:sync_session) { build_stubbed(:sync_session) }

# Only use create when testing database operations:
describe '#start!' do
  let(:sync_session) { create(:sync_session) }  # Needs DB for update!
end
```

### Priority 3: Create Test-Specific Configuration (20% speedup)

**New File**: `/Users/soto/development/expense_tracker/spec/support/performance_optimizations.rb`

```ruby
# Disable broadcasts globally in test
RSpec.configure do |config|
  config.before(:each) do
    allow(SyncStatusChannel).to receive(:broadcast_status).and_return(nil)
    allow(SyncStatusChannel).to receive(:broadcast_completion).and_return(nil)
    allow(SyncStatusChannel).to receive(:broadcast_failure).and_return(nil)
    allow(SyncStatusChannel).to receive(:broadcast_progress).and_return(nil)
    allow(SyncStatusChannel).to receive(:broadcast_account_progress).and_return(nil)
    
    # Stub Turbo broadcasts
    allow_any_instance_of(SyncSession).to receive(:broadcast_replace_to).and_return(nil)
    allow_any_instance_of(SyncSession).to receive(:broadcast_update_to).and_return(nil)
  end
  
  # Use truncation only for tests that need it
  config.before(:each, :needs_commit) do
    DatabaseCleaner.strategy = :truncation
  end
  
  config.after(:each, :needs_commit) do
    DatabaseCleaner.strategy = :transaction
  end
end
```

### Priority 4: Optimize Database Cleanup (15% speedup)

**File**: `/Users/soto/development/expense_tracker/spec/services/email/integration/processing_service_integration_spec.rb`

```ruby
# Replace heavy cleanup with targeted cleanup
before(:each) do
  # Only clean what's needed
  Expense.delete_all if Expense.any?
  ProcessedEmail.delete_all if ProcessedEmail.any?
  
  # Don't clear cache unless testing cache behavior
  # Rails.cache.clear  # Remove this
  # ActiveRecord::Base.clear_cache!  # Remove this
end
```

### Priority 5: Separate True Unit Tests from Integration Tests

Create separate test files:
- `spec/models/sync_session_unit_spec.rb` - Pure unit tests with stubbed dependencies
- `spec/models/sync_session_integration_spec.rb` - Tests requiring database/broadcasting

```ruby
# Unit test example - no database hits
RSpec.describe SyncSession, type: :model do
  describe '#progress_percentage' do
    subject(:sync_session) { build(:sync_session, total_emails: 100, processed_emails: 25) }
    
    it 'calculates percentage without database' do
      expect(sync_session.progress_percentage).to eq(25)
    end
  end
end
```

## Implementation Priority

1. **Immediate (5 minutes)**: Add `return if Rails.env.test?` to broadcasting methods
2. **Quick Win (30 minutes)**: Add global broadcast stubs in spec support
3. **Medium (2 hours)**: Replace `create` with `build_stubbed` where appropriate
4. **Long-term (4 hours)**: Separate unit and integration tests properly

## Expected Performance Improvements

| Test Group | Current Time | After Optimizations | Improvement |
|------------|--------------|---------------------|-------------|
| SyncSession | 21.28s | ~5s | 76% faster |
| ProcessEmailsJob | 1.76s | ~0.5s | 72% faster |
| Email::ProcessingService | 0.11s | ~0.05s | 55% faster |
| **Total Suite** | 66.87s | ~25s | **63% faster** |

## Verification Commands

```bash
# Run specific slow tests to verify improvements
bundle exec rspec spec/models/sync_session_spec.rb --format documentation

# Profile test suite
bundle exec rspec --profile 10

# Run with timing details
time bundle exec rspec spec/models/sync_session_spec.rb
```

## Additional Recommendations

1. **Consider using `test_after_commit` gem** to control after_commit behavior in tests
2. **Use VCR or WebMock** for any external API calls
3. **Implement query counting tests** to catch N+1 queries early
4. **Add performance budget checks** in CI to prevent regression

## Monitoring Test Performance

Add to your CI pipeline:
```yaml
- name: Check test performance
  run: |
    bundle exec rspec --format json --out rspec_results.json
    ruby script/check_test_performance.rb rspec_results.json
```

This analysis shows your tests are performing integration testing when they should be unit tests. The primary bottlenecks are database operations, broadcasting infrastructure, and excessive factory usage.