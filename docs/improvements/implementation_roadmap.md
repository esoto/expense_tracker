# Implementation Roadmap - Expense Tracker Improvements

## Overview
This roadmap prioritizes improvements based on impact and effort, organized into sprints.

## Sprint 1: Critical Fixes (Week 1)
**Goal**: Fix parsing failures and security basics

### 1. Fix BAC Merchant Pattern (2 hours)
- [ ] Update `db/seeds.rb` with new merchant pattern
- [ ] Create migration to update existing parsing rules
- [ ] Test against failing expenses
- [ ] Run `bundle exec rake parsing:validate`

### 2. Add Password Validation (1 hour)
- [ ] Update `EmailAccount` model with password validations
- [ ] Add password strength requirements
- [ ] Update forms to show validation errors
- [ ] Test with weak passwords

### 3. Fix Dashboard N+1 Queries (2 hours)
- [ ] Update `DashboardService#sync_info` method
- [ ] Update `DashboardService#recent_expenses` to include email_account
- [ ] Test query count reduction
- [ ] Verify dashboard still loads correctly

## Sprint 2: Performance & Security (Week 2)
**Goal**: Implement caching and rate limiting

### 1. Implement Dashboard Caching (3 hours)
- [ ] Add caching to `DashboardService`
- [ ] Add cache invalidation to `Expense` model
- [ ] Configure cache store for production
- [ ] Test cache hit rates

### 2. Add API Rate Limiting (3 hours)
- [ ] Add `rack-attack` gem
- [ ] Configure rate limiting rules
- [ ] Add custom throttled responses
- [ ] Test with automated requests

### 3. Add Duplicate Detection Index (1 hour)
- [ ] Create and run migration
- [ ] Test duplicate detection performance
- [ ] Verify no duplicate expenses created

## Sprint 3: Reliability Improvements (Week 3)
**Goal**: Better error handling and monitoring

### 1. Implement Fallback Parsing (4 hours)
- [ ] Add fallback merchant extraction methods
- [ ] Add comprehensive test cases
- [ ] Update existing parsing strategies
- [ ] Reprocess failed expenses

### 2. Memory Optimization (2 hours)
- [ ] Update email processing for large emails
- [ ] Add content truncation for failed parsing
- [ ] Monitor memory usage
- [ ] Test with large email samples

### 3. Add Background Job Monitoring (2 hours)
- [ ] Add performance logging to jobs
- [ ] Implement retry logic
- [ ] Add slow job alerts
- [ ] Configure job queues

## Sprint 4: Polish & Monitoring (Week 4)
**Goal**: Long-term maintainability

### 1. Security Headers & Monitoring (2 hours)
- [ ] Add security headers to ApplicationController
- [ ] Implement API request logging
- [ ] Add slow query monitoring
- [ ] Test security headers

### 2. Add Parsing Validation Tools (3 hours)
- [ ] Create rake tasks for pattern testing
- [ ] Add pattern validation to ParsingRule model
- [ ] Document pattern syntax
- [ ] Create pattern testing UI (optional)

### 3. Performance Monitoring Setup (3 hours)
- [ ] Configure APM tool (New Relic/Scout)
- [ ] Set up alerts for slow queries
- [ ] Add custom metrics for email processing
- [ ] Create performance dashboard

## Quick Wins (Can do anytime)
These can be done in parallel or when blocked:

- [ ] Update test coverage for real email formats
- [ ] Add `.editorconfig` for code consistency
- [ ] Update README with new features
- [ ] Add API documentation
- [ ] Create data cleanup rake tasks

## Testing Checklist
After each sprint, verify:

- [ ] All tests pass: `bundle exec rspec`
- [ ] No security issues: `bundle exec brakeman`
- [ ] Code quality: `bundle exec rubocop`
- [ ] Dashboard loads in <100ms
- [ ] API endpoints respond in <50ms
- [ ] Background jobs complete in <30s

## Success Metrics

### After Sprint 1:
- Merchant name extraction success rate > 95%
- No weak passwords allowed
- Dashboard queries reduced by 70%

### After Sprint 2:
- Dashboard cached response time < 10ms
- API rate limiting prevents abuse
- Zero duplicate expenses created

### After Sprint 3:
- Failed parsing rate < 5%
- Memory usage stable under load
- Job failure rate < 1%

### After Sprint 4:
- Full monitoring coverage
- All security headers present
- Automated performance alerts

## Rollback Plan
For each change:
1. Tag release before deployment
2. Monitor error rates for 24 hours
3. Have rollback script ready
4. Keep previous parsing rules as backup

## Dependencies
- PostgreSQL already set up ✅
- Redis needed for caching
- Background job processor (Solid Queue) ✅
- Error tracking (Sentry/Rollbar) recommended

## Notes
- Start with Sprint 1 fixes as they address critical issues
- Each sprint builds on the previous one
- Quick wins can be picked up during downtime
- Consider pair programming for complex changes
- Document any deviations from this plan