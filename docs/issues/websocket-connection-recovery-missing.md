# Issue: Missing WebSocket Connection Recovery

## Description
The queue monitoring interface lacks automatic reconnection logic for ActionCable WebSocket connections. When network interruptions occur, real-time updates stop working permanently until the page is manually refreshed. Users are not notified of connection issues and may continue thinking they're receiving live updates when they're actually viewing stale data.

## Severity
**HIGH** - Users receive stale data without knowing it, leading to incorrect queue management decisions

## Impact
- Real-time updates stop after network interruptions
- Users unaware that data is no longer live
- Queue operations may be performed on stale information
- Manual page refresh required to restore functionality
- Poor user experience during network instability
- Potential for making decisions based on outdated queue status

## Steps to Reproduce
### Scenario 1: Network Interruption
1. Open expense dashboard with queue visualization
2. Verify real-time updates are working (observe changing counters)
3. Disconnect network connection (disable WiFi/ethernet)
4. Wait 30 seconds, then reconnect network
5. Observe: Real-time updates do not automatically resume
6. Queue status remains frozen at last received state

### Scenario 2: ActionCable Server Restart
1. Open queue monitoring dashboard
2. Restart Rails server or ActionCable process
3. Return to browser without refreshing page
4. Start queue operations from another session
5. Observe: Original browser shows no real-time updates

### Scenario 3: Browser Sleep/Wake
1. Open queue dashboard on laptop
2. Close laptop (sleep mode) for 10+ minutes
3. Wake laptop and return to browser tab
4. Observe: WebSocket connection lost, no automatic reconnection

## Files Affected
- `/Users/soto/development/vs-agent/expense_tracker/app/javascript/controllers/queue_monitor_controller.js` (Primary)
- `/Users/soto/development/vs-agent/expense_tracker/app/channels/queue_channel.rb` (ActionCable channel)
- `/Users/soto/development/vs-agent/expense_tracker/app/views/sync_sessions/_queue_visualization.html.erb` (Connection status display)

## Code Examples
**Current problematic code:**
```javascript
connect() {
  this.refresh()
  this.startPolling()
  // Missing: WebSocket connection establishment and monitoring
}

disconnect() {
  this.stopPolling()
  // Missing: Connection status cleanup
}

// No reconnection logic implemented
// No connection status monitoring
// No fallback behavior when WebSocket fails
```

**What's missing:**
- WebSocket connection state monitoring
- Automatic reconnection with exponential backoff
- Connection status indicators in UI
- Graceful degradation to polling when WebSocket unavailable
- User notification of connection issues

## Test Cases to Add
```gherkin
Feature: WebSocket Connection Recovery

Scenario: Network connection lost and restored
  Given the queue dashboard is displaying real-time updates
  When the network connection is interrupted for 30 seconds
  And the network connection is restored
  Then WebSocket connection should automatically reconnect
  And real-time updates should resume within 10 seconds
  And users should be notified of connection status changes

Scenario: ActionCable server unavailable
  Given the queue dashboard is loaded
  When the ActionCable server becomes unavailable
  Then the interface should fall back to HTTP polling
  And users should be notified of degraded functionality
  And service should automatically upgrade back to WebSocket when available

Scenario: Browser tab inactive for extended period
  Given the queue dashboard is open in a background tab
  When the tab is inactive for 30+ minutes
  And the user returns to the tab
  Then connection should be re-established automatically
  And current queue status should be refreshed
  And real-time updates should resume immediately

Scenario: Connection status visibility
  Given the queue dashboard is loaded
  When WebSocket connection state changes
  Then users should see clear visual indicators
  And connection quality should be communicated
  And manual reconnect option should be available
```

## Acceptance Criteria for Fix
- [ ] Automatic WebSocket reconnection with exponential backoff
- [ ] Connection status indicator visible to users
- [ ] Graceful fallback to HTTP polling when WebSocket fails
- [ ] Manual reconnect button when automatic reconnection fails
- [ ] Connection quality indicators (connected, connecting, disconnected)
- [ ] Automatic upgrade from polling back to WebSocket when possible
- [ ] Persistent connection across browser sleep/wake cycles
- [ ] Clear user notifications for connection state changes
- [ ] No data loss during connection transitions
- [ ] Performance monitoring for connection reliability

## Recommended Implementation Approach
1. **Add Connection State Management**
   ```javascript
   this.connectionState = 'connecting' // connecting, connected, disconnected, error
   ```

2. **Implement Reconnection Logic**
   ```javascript
   reconnectWithBackoff() {
     const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000)
     setTimeout(() => this.attemptReconnection(), delay)
   }
   ```

3. **Add UI Status Indicators**
   ```erb
   <div data-queue-monitor-target="connectionStatus" class="hidden">
     <span class="text-amber-600">Connection lost - attempting to reconnect...</span>
   </div>
   ```

4. **Implement Hybrid Polling/WebSocket**
   - Use WebSocket when available
   - Fall back to HTTP polling during connection issues
   - Automatically upgrade back to WebSocket

## WebSocket Connection States to Handle
- `connecting` - Initial connection attempt
- `open` - Successfully connected and receiving updates  
- `closing` - Connection being terminated gracefully
- `closed` - Connection lost, attempting reconnection
- `error` - Connection failed, need user intervention

---

## Technical Notes (from Tech-Lead-Architect)

### **Priority Assessment**
- **Priority**: P0 (Production Blocker)
- **Rationale**: Core functionality breaks silently
- **Risk**: Stale data leads to incorrect decisions

### **Recommended Technical Approach**
Implement **robust reconnection with fallback**:

```javascript
// app/javascript/controllers/websocket_recovery_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = {
    channel: String,
    fallbackInterval: { type: Number, default: 5000 }
  }

  connect() {
    this.state = 'connecting'
    this.reconnectAttempts = 0
    this.maxReconnectDelay = 30000
    this.setupConnection()
    this.monitorConnection()
  }

  setupConnection() {
    try {
      this.consumer = createConsumer()
      
      this.subscription = this.consumer.subscriptions.create(
        { channel: this.channelValue },
        {
          connected: () => this.handleConnected(),
          disconnected: () => this.handleDisconnected(),
          received: (data) => this.handleReceived(data),
          rejected: () => this.handleRejected()
        }
      )
    } catch (error) {
      this.fallbackToPolling()
    }
  }

  handleConnected() {
    this.state = 'connected'
    this.reconnectAttempts = 0
    this.updateConnectionIndicator('connected')
    this.stopPolling()
    
    // Fetch latest state on reconnection
    if (this.wasDisconnected) {
      this.dispatch('refresh')
      this.wasDisconnected = false
    }
  }

  handleDisconnected() {
    this.state = 'disconnected'
    this.wasDisconnected = true
    this.updateConnectionIndicator('disconnected')
    this.scheduleReconnection()
    this.startPolling() // Fallback to polling
  }

  scheduleReconnection() {
    const delay = Math.min(
      1000 * Math.pow(2, this.reconnectAttempts),
      this.maxReconnectDelay
    )
    
    this.reconnectAttempts++
    
    setTimeout(() => {
      if (this.state === 'disconnected') {
        this.attemptReconnection()
      }
    }, delay)
  }

  attemptReconnection() {
    this.updateConnectionIndicator('reconnecting')
    
    // Test connection with ping
    fetch('/api/queue/ping', { method: 'HEAD' })
      .then(() => {
        this.consumer.connect()
      })
      .catch(() => {
        this.scheduleReconnection()
      })
  }

  monitorConnection() {
    // Heartbeat to detect stale connections
    this.heartbeatInterval = setInterval(() => {
      if (this.state === 'connected') {
        this.subscription.perform('ping')
      }
    }, 30000)
    
    // Handle page visibility changes
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && this.state === 'disconnected') {
        this.attemptReconnection()
      }
    })
  }

  startPolling() {
    if (this.pollingInterval) return
    
    this.pollingInterval = setInterval(() => {
      this.dispatch('poll')
    }, this.fallbackIntervalValue)
  }

  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
  }
}
```

### **Architecture Impact**
- Adds connection state management
- Implements hybrid WebSocket/polling approach
- Enhances all ActionCable-dependent features

### **Implementation Complexity**
- **Effort**: 3-4 days
- **Risk**: Medium - requires extensive testing
- **Dependencies**: Coordination with queue_monitor_controller

### **Testing Strategy**
```javascript
describe('WebSocketRecoveryController', () => {
  it('automatically reconnects with exponential backoff', () => {
    controller.handleDisconnected()
    
    expect(setTimeout).toHaveBeenCalledWith(expect.any(Function), 1000)
    
    controller.handleDisconnected()
    expect(setTimeout).toHaveBeenCalledWith(expect.any(Function), 2000)
  })
  
  it('falls back to polling when WebSocket fails', () => {
    controller.handleDisconnected()
    
    expect(controller.pollingInterval).toBeDefined()
    expect(setInterval).toHaveBeenCalledWith(
      expect.any(Function), 
      5000
    )
  })
})
```

### **Recommended Solution**
Use a **dedicated recovery controller** that other controllers can extend:
- Reusable across all WebSocket-dependent features
- Centralized connection state management
- Automatic fallback to polling
- Handles browser sleep/wake cycles