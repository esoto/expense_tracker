# Issue: Missing Error Boundary for JavaScript Controller

## Description
The queue monitor JavaScript controller lacks comprehensive error handling for initialization failures, WebSocket disconnections, and API communication errors. This can result in silent failures where the queue management interface appears to work but is actually non-functional.

## Severity
**CRITICAL** - Silent failures can mislead users into thinking queue operations succeeded

## Impact
- Users may attempt queue operations that silently fail
- No feedback when JavaScript controller fails to initialize
- WebSocket disconnections leave interface in inconsistent state
- API failures don't provide actionable error messages
- Debugging becomes difficult in production

## Steps to Reproduce
### Scenario 1: Controller Initialization Failure
1. Open browser developer tools and block JavaScript execution
2. Navigate to the expense dashboard
3. Attempt to interact with queue controls (pause/resume buttons)
4. Observe: Buttons appear clickable but do nothing, no error message

### Scenario 2: API Endpoint Failure  
1. Open the expense dashboard with queue visualization
2. Use browser dev tools to simulate network failure or return 500 errors for `/api/queue/status`
3. Wait for auto-refresh to trigger
4. Observe: Interface shows stale data with no error indication

### Scenario 3: WebSocket Connection Failure
1. Open the expense dashboard 
2. Disconnect network connection temporarily
3. Reconnect network
4. Start a queue operation
5. Observe: Real-time updates may not resume automatically

## Files Affected
- `/Users/soto/development/vs-agent/expense_tracker/app/javascript/controllers/queue_monitor_controller.js` (Primary)
- `/Users/soto/development/vs-agent/expense_tracker/app/views/sync_sessions/_queue_visualization.html.erb` (For error display elements)

## Code Examples
**Current problematic code:**
```javascript
async refresh() {
  try {
    const response = await fetch('/api/queue/status.json')
    const data = await response.json()
    
    this.updateDisplay(data)
  } catch (error) {
    console.error('Failed to fetch queue status:', error)
    // No user feedback, no fallback behavior
  }
}

connect() {
  this.refresh()
  this.startPolling()
  // No error handling for initialization failures
}
```

**What's missing:**
- User-visible error messages
- Graceful degradation when APIs fail
- Retry logic with exponential backoff
- Connection status indicators
- Fallback to manual refresh options

## Test Cases to Add
```gherkin
Feature: Queue Monitor Error Handling

Scenario: API endpoint returns 500 error
  Given the queue visualization is displayed
  When the API endpoint returns a server error
  Then users should see a clear error message
  And a manual refresh button should be available
  And the interface should retry with exponential backoff

Scenario: Network connection lost during polling
  Given the queue monitor is actively polling
  When the network connection is lost
  Then users should be notified of connection issues
  And polling should pause gracefully
  And connection should resume when network returns

Scenario: JavaScript controller fails to initialize
  Given the page loads with JavaScript errors
  When users attempt to interact with queue controls  
  Then clear error messages should be displayed
  And fallback functionality should be available
```

## Acceptance Criteria for Fix
- [ ] All API failures show user-friendly error messages
- [ ] Controller initialization errors are caught and displayed
- [ ] Network failures trigger retry logic with exponential backoff
- [ ] Connection status indicator shows current state
- [ ] Manual refresh option available when auto-refresh fails
- [ ] Graceful degradation when JavaScript is disabled
- [ ] Error messages include actionable next steps
- [ ] All errors are logged for debugging but don't spam console

---

## Technical Notes (from Tech-Lead-Architect)

### **Priority Assessment**
- **Priority**: P0 (Production Blocker)
- **Rationale**: Silent failures compromise data integrity
- **Risk**: Users make decisions on stale data

### **Recommended Technical Approach**
Implement a **comprehensive error boundary system** at the Stimulus controller level:

```javascript
// app/javascript/controllers/error_boundary_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "error", "fallback"]
  static values = { 
    retryDelay: { type: Number, default: 1000 },
    maxRetries: { type: Number, default: 3 }
  }

  connect() {
    this.retryCount = 0
    this.setupErrorHandling()
  }

  setupErrorHandling() {
    // Global error handler for this controller's scope
    this.element.addEventListener('error', this.handleError.bind(this), true)
    
    // Monitor child controller errors
    this.application.handleError = (error, message, controller) => {
      if (controller.element.closest(this.element.selector)) {
        this.handleControllerError(error, controller)
      }
    }
  }

  async handleError(error) {
    console.error('Error caught by boundary:', error)
    
    // Show user-friendly error
    this.showError({
      message: this.getUserMessage(error),
      technical: error.message,
      canRetry: this.canRetry()
    })

    // Attempt recovery
    if (this.canRetry()) {
      await this.attemptRecovery()
    }
  }

  async attemptRecovery() {
    this.retryCount++
    const delay = this.retryDelayValue * Math.pow(2, this.retryCount - 1)
    
    await new Promise(resolve => setTimeout(resolve, delay))
    
    try {
      // Reinitialize child controllers
      this.application.router.reload()
      this.hideError()
      this.retryCount = 0
    } catch (error) {
      if (this.retryCount < this.maxRetriesValue) {
        await this.attemptRecovery()
      } else {
        this.showFallback()
      }
    }
  }
}
```

### **Architecture Impact**
- Wraps existing controllers with error boundaries
- Provides graceful degradation path
- Maintains existing controller interfaces

### **Implementation Complexity**
- **Effort**: 3-4 days
- **Risk**: Medium - requires careful testing
- **Dependencies**: Must coordinate with all Stimulus controllers

### **Testing Strategy**
```javascript
// spec/javascript/error_boundary_spec.js
describe('ErrorBoundaryController', () => {
  it('catches and displays controller errors', async () => {
    // Simulate controller error
    controller.handleError(new Error('API failure'))
    
    expect(errorTarget).toBeVisible()
    expect(errorTarget).toHaveTextContent('connection issue')
  })

  it('implements exponential backoff retry', async () => {
    jest.useFakeTimers()
    
    controller.attemptRecovery()
    
    expect(setTimeout).toHaveBeenCalledWith(expect.any(Function), 1000)
    jest.advanceTimersByTime(1000)
    
    expect(setTimeout).toHaveBeenCalledWith(expect.any(Function), 2000)
  })
})
```

### **Recommended Solution**
Implement a **comprehensive error boundary system**:
- Provides consistent error handling across all features
- Reduces duplicate code and maintenance burden
- Enables centralized monitoring and alerting
- Follows React's proven error boundary pattern