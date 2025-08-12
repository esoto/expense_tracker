# Production Deployment Checklist - Categorization Monitoring

## Pre-Deployment Steps

### 1. Environment Variables
Set the following environment variables in production:

```bash
# StatsD Configuration
export STATSD_HOST="your-statsd-server.example.com"
export STATSD_PORT="8125"
export CATEGORIZATION_METRICS_PREFIX="prod.categorization"

# Redis Configuration (if using)
export REDIS_URL="redis://your-redis-server:6379/1"

# Performance Tuning
export CATEGORIZATION_WORKERS="8"
export CATEGORIZATION_LOG_LEVEL="info"

# Monitoring
export ENABLE_CATEGORIZATION_MONITORING="true"
```

### 2. Dependencies
Add to Gemfile if not already present:

```ruby
# Monitoring
gem 'statsd-ruby', '~> 1.5'  # For StatsD metrics
gem 'get_process_mem', '~> 0.2'  # For memory metrics (optional)
```

Run `bundle install`

### 3. Database Setup
Ensure the production database has:
- Sufficient categorization patterns (minimum 10 for health checks)
- Proper indexes on frequently queried columns
- Connection pool configured appropriately

### 4. Configuration Review
Review `config/categorization.yml` production settings:
- Adjust thresholds based on your traffic patterns
- Configure cache sizes based on available memory
- Set appropriate alert thresholds

## Health Check Verification

### 1. Basic Health Check
```bash
curl https://your-app.com/api/health
```

Expected response (healthy):
```json
{
  "status": "healthy",
  "healthy": true,
  "timestamp": "2025-08-11T10:00:00Z"
}
```

### 2. Kubernetes Probes
Configure in your deployment:

```yaml
livenessProbe:
  httpGet:
    path: /api/health/live
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /api/health/ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 3. Metrics Verification
```bash
curl https://your-app.com/api/health/metrics
```

## Monitoring Setup

### 1. StatsD/Graphite
Metrics will be sent to StatsD with the following naming pattern:
```
prod.categorization.attempts.total
prod.categorization.attempts.success
prod.categorization.duration
prod.categorization.confidence.distribution
prod.categorization.cache.pattern.get.hit
prod.categorization.errors.total
```

### 2. Log Aggregation
Structured logs in JSON format will include:
- `correlation_id` for request tracing
- `event` for event categorization
- `timestamp` in ISO8601 format
- Sanitized data (no PII)

Example log query for errors:
```json
{
  "event": "error.*",
  "service": "categorization"
}
```

### 3. Alert Configuration
Set up alerts for:
- Error rate > 5% over 5 minutes
- Success rate < 80% over 10 minutes
- P95 response time > 300ms
- Cache hit rate < 60%
- Pattern count < 10

## Performance Baselines

Expected performance in production:
- Categorization P50: < 10ms
- Categorization P95: < 50ms
- Cache hit rate: > 80%
- Success rate: > 85%
- Memory usage: < 500MB per worker

## Troubleshooting

### Issue: Low Cache Hit Rate
```bash
rails categorization:monitoring:dashboard
# Check cache statistics
# Consider warming cache:
rails categorization:cache:warm_up
```

### Issue: High Response Times
```bash
# Check database pool
rails runner "puts ActiveRecord::Base.connection_pool.stat"

# Check slow queries
tail -f log/production.log | grep "SLOW QUERY"
```

### Issue: Unhealthy Status
```bash
# Get detailed health status
rails categorization:monitoring:health

# Check each component
curl https://your-app.com/api/health | jq '.checks'
```

## Post-Deployment Verification

1. **Monitor for 24 hours:**
   - Check error rates remain below threshold
   - Verify memory usage is stable
   - Confirm cache hit rates are improving

2. **Performance Tests:**
   ```bash
   # Load test the categorization endpoint
   ab -n 1000 -c 10 https://your-app.com/api/health
   ```

3. **Verify Logging:**
   - Check structured logs are being collected
   - Verify correlation IDs are present
   - Confirm no PII is leaking

4. **Dashboard Review:**
   ```bash
   rails categorization:monitoring:dashboard
   ```
   - Review all metrics
   - Check learning velocity
   - Verify pattern distribution

## Rollback Plan

If issues arise:

1. **Disable monitoring** (immediate):
   ```yaml
   # config/categorization.yml
   monitoring:
     enabled: false
   ```

2. **Revert to previous version:**
   ```bash
   git revert [commit-hash]
   cap production deploy
   ```

3. **Clear corrupted cache:**
   ```bash
   rails runner "Categorization::PatternCache.instance.invalidate_all"
   ```

## Success Criteria

Deployment is successful when:
- ✅ All health checks return "healthy"
- ✅ No increase in error rates
- ✅ Response times remain within SLA
- ✅ Metrics are being collected in monitoring system
- ✅ Structured logs are being aggregated
- ✅ Alerts are configured and tested
- ✅ Team has access to monitoring dashboards

## Support Contacts

- DevOps Team: For infrastructure issues
- Platform Team: For monitoring system access
- Application Team: For categorization logic issues

## Documentation

- Operations Runbook: `rails categorization:monitoring:runbook`
- API Documentation: `/docs/MONITORING_IMPLEMENTATION.md`
- Configuration Guide: `config/categorization.yml`