# Test Suite Migration Plan

## Phase 1: Infrastructure Setup (Week 1)

### Day 1-2: Configuration
- [ ] Set up new directory structure
- [ ] Configure RSpec with tier-based settings
- [ ] Create command-line tools
- [ ] Update CI/CD pipeline

### Day 3-4: Test Analysis
- [ ] Run `rails test:analyze` to categorize existing tests
- [ ] Identify performance tests (71 files found)
- [ ] Map service tests to appropriate tiers
- [ ] Document slow test patterns

### Day 5: Initial Migration
- [ ] Move obvious unit tests to `spec/unit/`
- [ ] Move API tests to `spec/integration/requests/`
- [ ] Move performance tests to `spec/performance/`
- [ ] Update require paths in moved tests

## Phase 2: Test Optimization (Week 2)

### Day 1-2: Unit Test Optimization
- [ ] Remove database dependencies where possible
- [ ] Use test doubles for external services
- [ ] Implement factory traits for common scenarios
- [ ] Target: All unit tests run in <30 seconds

### Day 3-4: Integration Test Refinement
- [ ] Group related integration tests
- [ ] Implement shared contexts for common setups
- [ ] Add database cleaner strategies
- [ ] Target: Integration suite runs in <5 minutes

### Day 5: Performance Test Suite
- [ ] Create benchmark baselines
- [ ] Implement performance regression detection
- [ ] Set up performance reporting
- [ ] Document performance thresholds

## Phase 3: Developer Training (Week 3)

### Documentation
- [ ] Create test writing guidelines
- [ ] Document tier criteria
- [ ] Provide migration examples
- [ ] Update CONTRIBUTING.md

### Team Training
- [ ] Host knowledge sharing session
- [ ] Create video walkthrough
- [ ] Set up pair programming sessions
- [ ] Establish code review guidelines

## Migration Checklist

### Before Starting
```bash
# 1. Create backup branch
git checkout -b test-suite-backup

# 2. Run full test suite and save results
bundle exec rspec --format json --out tmp/baseline.json

# 3. Document current test times
time bundle exec rspec
```

### During Migration
```bash
# Use the migration script
rails test:migrate_structure DRY_RUN=false

# Verify tests still pass after moving
bin/test-unit
bin/test-integration
```

### After Migration
```bash
# Compare test results
bundle exec rspec --format json --out tmp/migrated.json
diff tmp/baseline.json tmp/migrated.json

# Verify performance improvements
time bin/test-unit  # Should be <30s
time bin/test-integration  # Should be <5m
```

## Success Metrics

### Speed Targets
- Unit tests: <30 seconds
- Integration tests: <5 minutes
- Full suite: <15 minutes
- CI pipeline: <20 minutes

### Coverage Targets
- Overall: >95%
- Unit test coverage: 100%
- Integration coverage: >90%
- Critical paths: 100%

### Developer Experience
- Test feedback in <30s during development
- Clear test tier separation
- Easy-to-remember commands
- Helpful error messages

## Rollback Plan

If issues arise:

1. Tests failing after migration:
   ```bash
   git checkout test-suite-backup
   git checkout main -- spec/
   ```

2. Performance degradation:
   - Revert RSpec configuration changes
   - Keep directory structure for gradual migration

3. CI/CD issues:
   - Maintain parallel pipelines during transition
   - Gradual cutover after validation

## Common Patterns to Watch For

### Tests That Should Be Unit Tests
- Model validations
- Service object business logic
- Helper methods
- Presenter logic
- Form objects

### Tests That Should Be Integration Tests
- API endpoint testing
- Multi-service interactions
- Database transactions
- External service mocking
- Job processing

### Tests That Should Be Performance Tests
- Response time benchmarks
- Memory usage profiling
- Database query optimization
- Bulk operation testing
- Cache effectiveness

## Tools and Commands Reference

### Development Commands
```bash
# Fast feedback during development
bin/test-unit                    # Run all unit tests
bin/test-unit spec/unit/models   # Run specific directory
bin/test-watch                   # Watch mode

# Deeper validation
bin/test-integration             # Run integration tests
rails test:dev                   # Run tests for modified files

# Full validation
rails test:ci                    # Run complete suite
rails test:coverage              # Generate coverage report
```

### Debugging Commands
```bash
# Profile slow tests
rails test:profile

# Analyze test distribution
rails test:analyze

# Run specific test tiers
TEST_TIER=unit bundle exec rspec
TEST_TIER=integration bundle exec rspec
```

### CI/CD Commands
```bash
# GitHub Actions will automatically run:
- bin/test-unit (parallel)
- bin/test-integration (parallel)
- bundle exec rspec spec/system (after unit)
- bin/test-performance (main branch only)
```