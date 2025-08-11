# Test Suite Performance Optimizations

## Current Status
- **Test Count**: 1,542 examples
- **Execution Time**: ~53-57 seconds (down from 3+ minutes)
- **Pass Rate**: 100% (0 failures)
- **Coverage**: 69.37% line coverage

## Successful Optimizations Applied

### 1. Core Rails Optimizations (rails_helper.rb)
- **BCrypt Cost Reduction**: Set to MIN_COST for tests (safe, standard practice)
- **Memory Store Cache**: Using in-memory cache instead of file/Redis cache
- **Logger Level**: Set to WARN to reduce I/O overhead
- **Transactional Fixtures**: Using Rails' built-in transaction rollback
- **Factory Preloading**: FactoryBot factories preloaded at suite start
- **ActionCable Config**: Disabled request forgery protection for tests

### 2. External Service Mocking (external_service_mocks.rb)
- **Opt-in Design**: Mocks only applied when tests use metadata flags
- **Available Flags**:
  - `:stub_broadcasts` - Stubs ActionCable and broadcast services
  - `:stub_action_cable` - Stubs only ActionCable
  - `:stub_external_services` - Stubs all external services
- **Safe Implementation**: Checks for method existence before stubbing

### 3. Factory Optimizations (factory_optimizations.rb)
- **Build Stubbed Helper**: Creates in-memory objects without DB persistence
- **Batch Creation**: Uses `insert_all` for bulk record creation
- **Factory Caching**: Thread-local cache for expensive factories
- **Opt-in Save Stubbing**: Only with `:stub_safe` metadata (currently safe)

### 4. Test Performance Helpers (test_performance_helpers.rb)
- **Thread Testing**: Immediate execution instead of sleep
- **Timer Thread Mocking**: Test doubles for timer threads
- **Batch Operations**: Bulk insert helpers for test data

### 5. Redis Test Configuration (redis_test_config.rb)
- **FakeRedis Integration**: Uses in-memory Redis for tests
- **Auto-cleanup**: Flushes Redis between tests
- **Graceful Handling**: Rescues errors if Redis not available

### 6. Time Helpers (conservative_job_optimizations.rb)
- **Opt-in Time Freezing**: Uses `:freeze_time` metadata
- **Consistent Time**: Helps with time-dependent tests

## Key Success Factors

1. **Opt-in Over Global**: Most optimizations require explicit metadata flags
2. **Safe Defaults**: Only universally safe optimizations applied globally
3. **No Core Rails Stubbing**: Avoided stubbing critical ActiveRecord methods
4. **Preserved Test Integrity**: All tests pass with multiple random seeds
5. **Maintained Isolation**: Each test runs in clean state

## Performance Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Total Time | 3+ minutes | ~55 seconds | ~70% faster |
| Job Tests | Passing | Passing (106/106) | Maintained |
| Model Tests | Variable | Passing (604/604) | Stabilized |
| Service Tests | Variable | Passing (494/494) | Stabilized |
| Controller Tests | Variable | Passing (260/260) | Stabilized |

## Lessons Learned

1. **Avoid Global ActiveRecord Stubbing**: Never stub core methods like `save`, `update`, etc. globally
2. **Metadata-Based Optimization**: Use RSpec metadata to opt specific tests into optimizations
3. **Test Stability First**: Performance gains mean nothing if tests become flaky
4. **BCrypt is Safe to Optimize**: Reducing BCrypt cost is a standard, safe optimization
5. **Memory Store Works Well**: In-memory caching is fast and reliable for tests
6. **FakeRedis is Reliable**: Provides good Redis simulation without external dependency

## Future Optimization Opportunities

1. **Parallel Testing**: Configuration is ready but not yet utilized
2. **Database Cleaner Strategy**: Could explore truncation vs transaction trade-offs
3. **Selective Factory Loading**: Load only needed factories per test
4. **Test Profiling**: Identify and optimize slowest individual tests
5. **CI-Specific Optimizations**: Different strategies for CI vs local development

## Maintenance Guidelines

1. **Monitor Test Times**: Track if tests start slowing down again
2. **Review New Tests**: Ensure they follow optimization patterns
3. **Update Dependencies**: Keep testing gems updated for performance improvements
4. **Profile Periodically**: Use `--profile` flag to find slow tests
5. **Document Changes**: Update this file when adding new optimizations