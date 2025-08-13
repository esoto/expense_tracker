# Dependency Injection Solution for Categorization Engine

## Problem Statement
The Categorization::Engine was using a singleton pattern that caused test isolation failures. Tests would pass individually but fail when run as a full suite due to state pollution between tests.

## Root Causes
1. **Singleton State Pollution**: The Engine singleton maintained state between tests
2. **Cache Contamination**: Shared caches polluted test data
3. **Thread Pool State Issues**: Background threads persisted between tests
4. **Test Isolation Problems**: Transactional fixtures didn't handle singleton state

## Solution Implemented

### Phase 1: Engine Architecture Refactor
- **Removed singleton enforcement** from Categorization::Engine
- **Created ServiceRegistry** for dependency management (`app/services/categorization/service_registry.rb`)
- **Implemented proper initialization** with dependency injection
- **Added lifecycle management** with `shutdown!` method for clean teardown

### Phase 2: Test Infrastructure Updates
- **Updated test helpers** to create fresh engine instances (`spec/support/categorization_helper.rb`)
- **Added `create_test_engine` method** that creates isolated engine instances with fresh dependencies
- **Implemented proper cleanup** in test lifecycle hooks
- **Added `shutdown!` calls** to properly terminate engines after each test

### Phase 3: Service Updates
- **PatternCache**: Removed singleton enforcement, added support for creating independent instances
- **FuzzyMatcher**: Removed singleton enforcement, added support for creating independent instances
- **Consumer Services**: Updated to support optional dependency injection while maintaining backward compatibility

### Phase 4: Backward Compatibility
- **Maintained `.instance` methods** for backward compatibility
- **Added `.create` methods** for explicit instance creation
- **Consumer services** can now accept optional `engine:` parameter for dependency injection

## Key Changes

### 1. ServiceRegistry (`app/services/categorization/service_registry.rb`)
```ruby
module Categorization
  class ServiceRegistry
    def initialize(logger: Rails.logger)
      @logger = logger
      @services = {}
      @mutex = Mutex.new
    end

    def register(key, service)
      @mutex.synchronize { @services[key] = service }
    end

    def get(key)
      @mutex.synchronize { @services[key] }
    end

    def build_defaults(options = {})
      # Creates fresh instances of all services
    end
  end
end
```

### 2. Engine Refactoring (`app/services/categorization/engine.rb`)
- Removed singleton pattern enforcement
- Added dependency injection via ServiceRegistry
- Added `shutdown!` method for clean resource cleanup
- Made thread pool management more robust

### 3. Test Helper Updates (`spec/support/categorization_helper.rb`)
```ruby
def create_test_engine(options = {})
  service_registry = Categorization::ServiceRegistry.new(logger: Rails.logger)
  
  # Create fresh instances of all services
  service_registry.register(:pattern_cache, Categorization::PatternCache.new)
  service_registry.register(:fuzzy_matcher, Categorization::Matchers::FuzzyMatcher.new)
  # ... other services ...
  
  Categorization::Engine.new(
    service_registry: service_registry,
    skip_defaults: true,
    **options
  )
end
```

## Verification

### Test Results
- ✅ All 34 engine tests pass consistently
- ✅ Tests pass when run individually
- ✅ Tests pass when run as a full suite
- ✅ No state pollution between test runs
- ✅ Multiple consecutive test runs succeed

### Commands to Verify
```bash
# Run individual test
bundle exec rspec spec/services/categorization/engine_spec.rb:56

# Run full engine spec
bundle exec rspec spec/services/categorization/engine_spec.rb

# Run multiple times to check for state pollution
for i in 1 2 3; do 
  bundle exec rspec spec/services/categorization/engine_spec.rb --format progress
done

# Run all categorization tests
bundle exec rspec spec/services/categorization/
```

## Benefits

1. **Test Isolation**: Each test gets a fresh engine instance with clean state
2. **Better Testability**: Can inject mock/stub services for testing
3. **Cleaner Architecture**: Explicit dependencies instead of hidden singletons
4. **Backward Compatible**: Existing code continues to work unchanged
5. **Thread Safety**: Proper shutdown ensures threads are terminated cleanly

## Migration Path for Existing Code

### Option 1: No Changes Required (Backward Compatible)
```ruby
# Existing code continues to work
engine = Categorization::Engine.instance
result = engine.categorize(expense)
```

### Option 2: Explicit Dependency Injection (Recommended for Tests)
```ruby
# Create engine with custom dependencies
engine = Categorization::Engine.create(
  pattern_cache: custom_cache,
  fuzzy_matcher: custom_matcher
)
result = engine.categorize(expense)
engine.shutdown! # Clean shutdown
```

### Option 3: Service-Level Injection
```ruby
# Pass engine to services that need it
service = BulkCategorization::AutoCategorizationService.new(
  engine: custom_engine,
  confidence_threshold: 0.8
)
```

## Performance Impact

- **Minimal overhead**: ServiceRegistry adds negligible overhead
- **Same performance characteristics**: Core categorization logic unchanged
- **Better resource management**: Explicit shutdown prevents resource leaks
- **Improved test performance**: No need for complex singleton reset logic

## Conclusion

The dependency injection refactoring successfully resolves the test isolation issues while:
- Maintaining backward compatibility
- Improving code architecture
- Enabling better testing practices
- Providing cleaner resource management

The solution follows Rails best practices and Ruby idioms while solving the immediate problem and improving long-term maintainability.