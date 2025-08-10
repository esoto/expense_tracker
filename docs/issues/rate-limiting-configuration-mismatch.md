# Issue: Rate Limiting Configuration Mismatch

## Description
The current rate limiting configuration for queue status endpoints (60 requests per minute) provides insufficient headroom for normal operation. The JavaScript controller refreshes every 5 seconds (12 requests/minute per user), leaving only 5x normal usage before hitting limits. Multiple browser tabs or users can easily trigger false positive rate limiting.

## Severity
**HIGH** - Legitimate users will be blocked from normal queue monitoring

## Impact
- Users with multiple browser tabs get rate limited
- Team members monitoring queues simultaneously hit limits
- Auto-refresh stops working during normal usage
- False positive "Too Many Requests" errors
- Reduced user experience and trust in the system
- Support tickets from users unable to access monitoring

## Steps to Reproduce
### Scenario 1: Multiple Tab Usage
1. Open expense dashboard in 5+ browser tabs
2. Navigate to queue visualization in each tab
3. Let auto-refresh run for 5 minutes
4. Observe: Rate limiting kicks in, some tabs show "Too Many Requests"

### Scenario 2: Team Usage Simulation
1. Have 5 team members open the queue dashboard simultaneously
2. Let the auto-refresh run normally (every 5 seconds)
3. Wait for 1 minute
4. Observe: Some users get rate limited (5 users × 12 requests = 60 requests)

### Scenario 3: Browser Refresh During Monitoring
1. Open queue dashboard and let it auto-refresh
2. Manually refresh the browser page several times
3. Continue using auto-refresh
4. Observe: Combined requests exceed 60/minute limit

## Files Affected
- `/Users/soto/development/vs-agent/expense_tracker/config/initializers/rack_attack.rb` (Lines 37-39)
- `/Users/soto/development/vs-agent/expense_tracker/app/javascript/controllers/queue_monitor_controller.js` (Auto-refresh interval)

## Code Examples
**Current problematic configuration:**
```ruby
# Queue status monitoring rate limiting
# Allow 60 status checks per minute per IP (every second)
throttle("queue/status", limit: 60, period: 1.minute) do |req|
  req.ip if req.path == "/api/queue/status" || req.path == "/api/queue/status.json"
end
```

**JavaScript auto-refresh:**
```javascript
static values = { 
  refreshInterval: { type: Number, default: 5000 }, // 5 seconds = 12 requests/minute
}
```

**Math breakdown:**
- Normal usage: 12 requests/minute per tab
- 60 requests/minute limit ÷ 12 = only 5 concurrent users or tabs
- No headroom for manual refreshes or temporary spikes

## Test Cases to Add
```gherkin
Feature: Rate Limiting Effectiveness

Scenario: Normal concurrent usage
  Given 10 users are monitoring the queue dashboard
  When each user's browser auto-refreshes every 5 seconds
  Then all users should be able to continue monitoring
  And no legitimate users should be rate limited
  And system should handle normal concurrent load

Scenario: Power user with multiple tabs
  Given a user opens queue monitoring in 8 browser tabs
  When auto-refresh runs in all tabs simultaneously
  Then the user should not be rate limited
  And monitoring should continue to function normally

Scenario: Mixed usage patterns
  Given normal auto-refresh is running
  When users occasionally refresh manually or navigate between pages
  Then the additional requests should not trigger rate limiting
  And users should have reasonable headroom for normal behavior
```

## Current Rate Limit Analysis
| Scenario | Requests/Min | Within Limit? | Headroom |
|----------|-------------|---------------|----------|
| 1 user, 1 tab | 12 | ✅ Yes | 400% |
| 1 user, 3 tabs | 36 | ✅ Yes | 67% |
| 1 user, 5 tabs | 60 | ⚠️ Exactly at limit | 0% |
| 3 users, 1 tab each | 36 | ✅ Yes | 67% |
| 5 users, 1 tab each | 60 | ⚠️ Exactly at limit | 0% |
| 10 users, 1 tab each | 120 | ❌ Rate limited | -100% |

## Acceptance Criteria for Fix
- [ ] Support at least 20 concurrent users with single tabs
- [ ] Support power users with 8+ browser tabs
- [ ] Provide 200% headroom above normal usage patterns
- [ ] Maintain protection against actual abuse (1000+ req/min)
- [ ] Consider different limits for authenticated vs unauthenticated users
- [ ] Add monitoring/alerting when approaching limits
- [ ] Document expected usage patterns and limits

## Recommended Configuration
```ruby
# Queue status monitoring rate limiting
# Allow 300 status checks per minute per IP (5 requests/second)
throttle("queue/status", limit: 300, period: 1.minute) do |req|
  req.ip if req.path == "/api/queue/status" || req.path == "/api/queue/status.json"
end

# OR implement tiered limits:
# Authenticated users: Higher limits
# Unauthenticated: Lower limits
```

## Alternative Solutions
1. **User-based rate limiting** instead of IP-based for authenticated users
2. **Progressive rate limiting** with warnings before blocks
3. **Adaptive refresh intervals** that slow down when approaching limits
4. **WebSocket-only updates** to reduce HTTP requests
5. **Client-side request deduplication** across browser tabs

---

## Technical Notes (from Tech-Lead-Architect)

### **Priority Assessment**
- **Priority**: P1 (Pre-Launch)
- **Rationale**: Impacts legitimate users but not data integrity
- **Risk**: Poor user experience, support burden

### **Recommended Technical Approach**
Implement **tiered rate limiting** with user-aware thresholds:

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # Tiered rate limiting for queue status
  throttle("queue/status/authenticated", limit: 600, period: 1.minute) do |req|
    if req.path =~ /^\/api\/queue\/status/ && authenticated_request?(req)
      user_identifier(req)
    end
  end

  throttle("queue/status/anonymous", limit: 120, period: 1.minute) do |req|
    if req.path =~ /^\/api\/queue\/status/ && !authenticated_request?(req)
      req.ip
    end
  end

  # Progressive throttling with warnings
  throttle("queue/status/warning", limit: 500, period: 1.minute) do |req|
    if req.path =~ /^\/api\/queue\/status/
      # Track but don't block - just add warning header
      identifier = user_identifier(req) || req.ip
      if store.get("throttle:warning:#{identifier}").to_i > 400
        req.env['rack.attack.warning'] = true
      end
      identifier
    end
  end

  class << self
    def authenticated_request?(req)
      req.env['warden']&.authenticated? || 
      req.headers['Authorization'].present?
    end

    def user_identifier(req)
      req.env['warden']&.user&.id || 
      ApiToken.from_header(req.headers['Authorization'])&.id
    end
  end
end
```

### **Architecture Impact**
- Adds user-aware rate limiting
- Implements progressive throttling
- Provides early warning system

### **Implementation Complexity**
- **Effort**: 1 day
- **Risk**: Low - configuration change
- **Dependencies**: None

### **Testing Strategy**
```ruby
RSpec.describe "Rate Limiting" do
  it "allows higher limits for authenticated users" do
    user = create(:user)
    sign_in user
    
    600.times { get "/api/queue/status.json" }
    expect(response).to have_http_status(:ok)
  end
  
  it "provides warning headers before blocking" do
    450.times { get "/api/queue/status.json" }
    expect(response.headers['X-RateLimit-Warning']).to eq('approaching limit')
  end
end
```

### **Recommended Solution**
Implement **hybrid approach** with both user-based and IP-based limits:
- User-based for authenticated requests (higher limits)
- IP-based for anonymous requests (lower limits)
- Progressive warnings before hard blocks
- Separate limits for read vs write operations