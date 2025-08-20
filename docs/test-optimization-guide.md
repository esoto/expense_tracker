# Test Optimization Guide

## Overview
This guide provides specific recommendations for optimizing the test suite to achieve sub-30-second unit test runs while maintaining comprehensive coverage.

## Current Test Organization

### Three-Tier System
1. **Unit Tests** (Target: <30s)
   - Isolated, mocked dependencies
   - No database queries (use stubs)
   - No external service calls
   - Run with: `bin/test-unit`

2. **Integration Tests** (Target: 2-5min)
   - Database interactions
   - Service orchestration
   - API endpoint testing
   - Run with: `bin/test-integration`

3. **Performance Tests** (Target: On-demand)
   - Benchmarks and profiling
   - Memory analysis
   - Query optimization
   - Run with: `bin/test-performance`

4. **System Tests** (Target: 5-15min)
   - Full browser tests
   - End-to-end workflows
   - JavaScript interactions
   - Run with: `bin/test-system`

## Migration Strategy

### Step 1: Analyze Current Tests
```bash
# Analyze test distribution
rails test:analyze

# Verify tier configuration
bin/test-verify

# Tag existing tests
rails test:tag_tests
```

### Step 2: Identify Slow Unit Tests
Common culprits:
- Tests using `create` instead of `build_stubbed`
- Tests hitting the database unnecessarily
- Tests with external API calls
- Tests loading unnecessary Rails components

### Step 3: Apply Optimizations

#### Database Optimizations
```ruby
# BAD - Creates database records
let(:user) { create(:user) }
let(:expense) { create(:expense, user: user) }

# GOOD - Uses stubs
let(:user) { build_stubbed(:user) }
let(:expense) { build_stubbed(:expense, user: user) }
```

#### Service Mocking
```ruby
# BAD - Calls actual service
it "processes email" do
  EmailProcessingService.new(email).process
  expect(expense).to be_created
end

# GOOD - Mocks service
it "processes email" do
  service = instance_double(EmailProcessingService)
  allow(service).to receive(:process).and_return(true)
  allow(EmailProcessingService).to receive(:new).and_return(service)
  
  expect(service).to receive(:process)
  subject.handle_email(email)
end
```

#### External Service Stubs
```ruby
# spec/support/configs/unit_test_stubs.rb
RSpec.configure do |config|
  config.before(:each, :unit) do
    # Stub Redis
    allow(Redis).to receive(:new).and_return(MockRedis.new)
    
    # Stub ActionCable broadcasts
    allow(ActionCable.server).to receive(:broadcast)
    
    # Stub external HTTP calls
    stub_request(:any, /api.external.com/).to_return(status: 200)
  end
end
```

## Specific Optimizations by Test Type

### Model Tests
- Use `build` or `build_stubbed` for associations
- Test validations without saving
- Mock callbacks that trigger external services

### Controller Tests
- Disable view rendering
- Stub authentication/authorization
- Mock service layer calls

### Service Tests
- Inject dependencies for easy mocking
- Use test doubles for collaborators
- Avoid integration unless testing orchestration

### Helper Tests
- Pure functions, no database
- Mock view context if needed

## Performance Monitoring

### Continuous Monitoring
```bash
# Run with profiling
PROFILE=true bin/test-unit

# Check for N+1 queries
QUERY_LOG=true bin/test-integration

# Memory profiling
MEMORY_PROFILE=true bin/test-performance
```

### Key Metrics
- Unit tests: <0.1s per test average
- Integration tests: <1s per test average
- System tests: <5s per test average

## Parallel Execution

### Setup
```bash
# Install parallel_tests gem
bundle add parallel_tests --group test

# Setup databases
rails parallel:setup

# Run tests in parallel
rails parallel:spec
```

### Configuration
```ruby
# spec/support/configs/parallel_tests.rb
if ENV['PARALLEL_WORKERS']
  RSpec.configure do |config|
    config.before(:suite) do
      # Setup for parallel execution
      ActiveRecord::Base.connection.disconnect!
      ActiveRecord::Base.establish_connection(
        ActiveRecord::Base.configurations.configs_for(
          env_name: Rails.env
        ).first.configuration_hash.merge(
          database: "#{Rails.application.class.parent_name.underscore}_test_#{ENV['TEST_ENV_NUMBER']}"
        )
      )
    end
  end
end
```

## Quick Wins Checklist

- [ ] Replace `create` with `build_stubbed` in unit tests
- [ ] Add `:unit` tag to fast tests
- [ ] Move slow tests to integration tier
- [ ] Disable Rails cache in unit tests
- [ ] Mock all external service calls
- [ ] Use transactional fixtures for unit tests
- [ ] Disable view rendering in controller tests
- [ ] Stub time-sensitive operations
- [ ] Minimize factory associations
- [ ] Use shared contexts for common setups

## Verification

After implementing optimizations:

```bash
# Verify unit tests run in <30s
time bin/test-unit

# Check test coverage
open coverage/index.html

# Run full verification
RUN_TESTS=true bin/test-verify
```

## Troubleshooting

### Tests Still Slow?
1. Profile individual tests: `rspec --profile 10`
2. Check for database queries: `QUERY_LOG=true rspec spec/unit`
3. Look for factory cascades: `FACTORY_PROF=true rspec`
4. Identify external calls: `WEBMOCK_SHOW_UNSTUBBED=true rspec`

### False Positives?
- Ensure proper mocking boundaries
- Verify stubs match real behavior
- Run integration tests to catch gaps

### Coverage Gaps?
- Use `SimpleCov` to identify untested code
- Move critical path tests to integration tier
- Keep unit tests focused on business logic

## Next Steps

1. Run `rails test:tag_tests` to tag existing tests
2. Execute `bin/test-verify` to analyze current state
3. Focus on optimizing the slowest unit tests first
4. Set up CI to run tiers separately
5. Monitor and maintain <30s unit test target