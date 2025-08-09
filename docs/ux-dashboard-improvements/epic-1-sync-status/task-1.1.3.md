---

## Subtask 1.1.3: Client-side Subscription Management

**Task ID:** EXP-1.1.3  
**Parent Task:** EXP-1.1  
**Type:** Development  
**Priority:** Critical  
**Estimated Hours:** 4  

### Description
Implement robust client-side subscription management in the Stimulus controller to handle connections, reconnections, and updates.

### Acceptance Criteria
- [ ] Auto-reconnect after connection loss (with exponential backoff)
- [ ] Pause updates when browser tab is inactive
- [ ] Resume updates when tab becomes active
- [ ] Network monitoring detects connection issues
- [ ] Memory leaks prevented (proper cleanup on disconnect)
- [ ] Console logging for debugging (removable in production)

### Technical Notes

#### Client-Side Implementation:

1. **Stimulus Controller Enhancements:**
   ```javascript
   // app/javascript/controllers/sync_widget_controller.js
   export default class extends Controller {
     static values = {
       sessionId: Number,
       active: Boolean,
       connectionState: String,
       retryCount: Number,
       maxRetries: { type: Number, default: 5 }
     }
     
     connect() {
       this.retryCountValue = 0
       this.setupVisibilityHandling()
       this.setupNetworkMonitoring()
       this.loadCachedState()
       
       if (this.activeValue) {
         this.subscribeToChannel()
       }
     }
     
     setupVisibilityHandling() {
       document.addEventListener('visibilitychange', () => {
         if (document.hidden) {
           this.pauseUpdates()
         } else {
           this.resumeUpdates()
         }
       })
     }
     
     setupNetworkMonitoring() {
       window.addEventListener('online', () => this.handleOnline())
       window.addEventListener('offline', () => this.handleOffline())
     }
     
     pauseUpdates() {
       this.isPaused = true
       if (this.subscription) {
         this.subscription.perform('pause_updates')
       }
     }
     
     resumeUpdates() {
       this.isPaused = false
       if (this.subscription) {
         this.subscription.perform('resume_updates')
         this.requestLatestStatus()
       }
     }
   }
   ```

2. **Exponential Backoff Reconnection:**
   ```javascript
   reconnect() {
     if (this.retryCountValue >= this.maxRetriesValue) {
       this.showManualRetryButton()
       return
     }
     
     const delay = this.calculateBackoffDelay()
     this.showReconnectingMessage(delay)
     
     this.reconnectTimer = setTimeout(() => {
       this.retryCountValue++
       this.subscribeToChannel()
     }, delay)
   }
   
   calculateBackoffDelay() {
     // Exponential backoff with jitter
     const baseDelay = Math.pow(2, this.retryCountValue) * 1000
     const jitter = Math.random() * 1000
     return Math.min(baseDelay + jitter, 30000) // Max 30 seconds
   }
   ```

3. **State Caching:**
   ```javascript
   cacheState(data) {
     const cacheData = {
       ...data,
       timestamp: Date.now(),
       sessionId: this.sessionIdValue
     }
     
     sessionStorage.setItem(
       `sync_state_${this.sessionIdValue}`,
       JSON.stringify(cacheData)
     )
   }
   
   loadCachedState() {
     const cached = sessionStorage.getItem(`sync_state_${this.sessionIdValue}`)
     
     if (cached) {
       const data = JSON.parse(cached)
       const age = Date.now() - data.timestamp
       
       // Use cache if less than 5 minutes old
       if (age < 300000) {
         this.updateProgress(data)
         this.showCacheIndicator()
       }
     }
   }
   ```

4. **Memory Leak Prevention:**
   ```javascript
   disconnect() {
     // Clear all timers
     if (this.reconnectTimer) {
       clearTimeout(this.reconnectTimer)
     }
     
     // Remove event listeners
     document.removeEventListener('visibilitychange', this.visibilityHandler)
     window.removeEventListener('online', this.onlineHandler)
     window.removeEventListener('offline', this.offlineHandler)
     
     // Unsubscribe from channel
     if (this.subscription) {
       this.subscription.unsubscribe()
       this.subscription = null
     }
     
     // Disconnect consumer
     if (this.consumer) {
       this.consumer.disconnect()
       this.consumer = null
     }
     
     // Clear cached state if session completed
     if (this.isCompleted) {
       sessionStorage.removeItem(`sync_state_${this.sessionIdValue}`)
     }
   }
   ```

5. **Network State Handling:**
   ```javascript
   handleOffline() {
     this.connectionStateValue = 'offline'
     this.showOfflineMessage()
     
     // Pause any active operations
     this.pauseUpdates()
   }
   
   handleOnline() {
     this.connectionStateValue = 'reconnecting'
     this.showReconnectingMessage()
     
     // Reset retry count for fresh attempt
     this.retryCountValue = 0
     
     // Attempt reconnection
     this.reconnect()
   }
   ```

6. **Debug Logging:**
   ```javascript
   log(level, message, data = {}) {
     if (this.element.dataset.debug === 'true') {
       const timestamp = new Date().toISOString()
       console[level](`[${timestamp}] SyncWidget:`, message, data)
       
       // Also send to server for monitoring in production
       if (level === 'error' && window.Rails?.env === 'production') {
         this.sendErrorToServer(message, data)
       }
     }
   }
   ```

7. **Testing:**
   ```javascript
   // spec/javascript/controllers/sync_widget_controller_spec.js
   describe('SyncWidgetController', () => {
     it('reconnects with exponential backoff', async () => {
       controller.retryCountValue = 2
       const delay = controller.calculateBackoffDelay()
       
       expect(delay).toBeGreaterThan(4000)
       expect(delay).toBeLessThanOrEqual(5000)
     })
     
     it('pauses updates when tab becomes inactive', () => {
       document.hidden = true
       document.dispatchEvent(new Event('visibilitychange'))
       
       expect(controller.isPaused).toBe(true)
     })
     
     it('prevents memory leaks on disconnect', () => {
       controller.connect()
       controller.disconnect()
       
       expect(controller.subscription).toBeNull()
       expect(controller.consumer).toBeNull()
     })
   })
   ```

8. **Performance Considerations:**
   - Use requestIdleCallback for non-critical UI updates
   - Debounce rapid state changes (max 1 update per 100ms)
   - Lazy load reconnection UI components
   - Use CSS containment for progress bar animations
