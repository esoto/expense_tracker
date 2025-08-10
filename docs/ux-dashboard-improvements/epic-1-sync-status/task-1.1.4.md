---

## Subtask 1.1.4: Error Recovery and User Feedback

**Task ID:** EXP-1.1.4  
**Parent Task:** EXP-1.1  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 3  

### Description
Implement comprehensive error handling and recovery mechanisms with appropriate user feedback for all failure scenarios.

### Acceptance Criteria
- [ ] Connection failure displays user-friendly message
- [ ] Automatic retry with exponential backoff (max 5 attempts)
- [ ] Manual retry button available after max attempts
- [ ] Sync errors display specific, actionable messages
- [ ] Toast notifications for connection state changes
- [ ] Fallback to polling if WebSocket unavailable

### Technical Notes

#### Error Handling Implementation:

1. **Error Recovery Strategies:**
   ```ruby
   # app/services/sync_error_handler.rb
   class SyncErrorHandler
     RECOVERABLE_ERRORS = [
       Net::ReadTimeout,
       Net::OpenTimeout,
       Errno::ECONNRESET,
       Errno::ETIMEDOUT,
       ActiveRecord::LockWaitTimeout
     ].freeze
     
     def handle_error(error, sync_session, context = {})
       if recoverable?(error)
         handle_recoverable_error(error, sync_session, context)
       else
         handle_fatal_error(error, sync_session, context)
       end
     end
     
     private
     
     def recoverable?(error)
       RECOVERABLE_ERRORS.any? { |klass| error.is_a?(klass) }
     end
     
     def handle_recoverable_error(error, session, context)
       retry_count = context[:retry_count] || 0
       
       if retry_count < 3
         # Schedule retry with backoff
         delay = (2 ** retry_count).seconds
         
         EmailSyncJob.set(wait: delay).perform_later(
           session.id,
           context.merge(retry_count: retry_count + 1)
         )
         
         # Notify user of retry
         SyncStatusChannel.broadcast_activity(
           session,
           'retry',
           "Retrying in #{delay} seconds due to: #{error.message}"
         )
       else
         # Max retries reached
         handle_fatal_error(error, session, context)
       end
     end
     
     def handle_fatal_error(error, session, context)
       session.fail!(error.message)
       
       # Send detailed error notification
       SyncStatusChannel.broadcast_failure(
         session,
         build_error_message(error, context)
       )
       
       # Log for debugging
       Rails.logger.error("Sync failed: #{error.message}")
       Rails.logger.error(error.backtrace.join("\n"))
       
       # Notify admins for critical errors
       notify_admins(error, session) if critical_error?(error)
     end
   end
   ```

2. **User Feedback Components:**
   ```ruby
   # app/components/sync_error_component.rb
   class SyncErrorComponent < ViewComponent::Base
     def initialize(error_type:, message:, recoverable:)
       @error_type = error_type
       @message = message
       @recoverable = recoverable
     end
     
     def render?
       @message.present?
     end
     
     def error_class
       case @error_type
       when :network then 'bg-amber-50 border-amber-200 text-amber-700'
       when :authentication then 'bg-rose-50 border-rose-200 text-rose-700'
       when :server then 'bg-slate-50 border-slate-200 text-slate-700'
       else 'bg-rose-50 border-rose-200 text-rose-700'
       end
     end
     
     def icon
       case @error_type
       when :network then 'wifi-off'
       when :authentication then 'lock'
       when :server then 'server'
       else 'alert-circle'
       end
     end
   end
   ```

3. **Toast Notification System:**
   ```javascript
   // app/javascript/controllers/toast_controller.js
   export default class extends Controller {
     static targets = ['container']
     
     show(message, type = 'info', duration = 5000) {
       const toast = this.createToast(message, type)
       this.containerTarget.appendChild(toast)
       
       // Animate in
       requestAnimationFrame(() => {
         toast.classList.add('translate-y-0', 'opacity-100')
         toast.classList.remove('translate-y-2', 'opacity-0')
       })
       
       // Auto dismiss
       if (duration > 0) {
         setTimeout(() => this.dismiss(toast), duration)
       }
       
       return toast
     }
     
     createToast(message, type) {
       const toast = document.createElement('div')
       toast.className = this.getToastClasses(type)
       toast.innerHTML = this.getToastHTML(message, type)
       
       // Add dismiss handler
       toast.querySelector('[data-dismiss]')?.addEventListener('click', () => {
         this.dismiss(toast)
       })
       
       return toast
     }
     
     dismiss(toast) {
       toast.classList.add('translate-y-2', 'opacity-0')
       toast.classList.remove('translate-y-0', 'opacity-100')
       
       setTimeout(() => toast.remove(), 300)
     }
   }
   ```

4. **Fallback to Polling:**
   ```javascript
   // Fallback polling mechanism
   class SyncStatusPoller {
     constructor(sessionId, callback) {
       this.sessionId = sessionId
       this.callback = callback
       this.interval = 2000 // Start with 2 seconds
       this.maxInterval = 10000 // Max 10 seconds
     }
     
     start() {
       this.stop() // Clear any existing timer
       this.poll()
     }
     
     async poll() {
       try {
         const response = await fetch(`/sync_sessions/${this.sessionId}/status.json`)
         const data = await response.json()
         
         this.callback(data)
         
         // Adjust interval based on activity
         if (data.status === 'running') {
           this.interval = 2000 // Poll faster when active
         } else {
           this.interval = Math.min(this.interval * 1.5, this.maxInterval)
         }
         
         // Schedule next poll
         this.timer = setTimeout(() => this.poll(), this.interval)
       } catch (error) {
         console.error('Polling failed:', error)
         
         // Retry with backoff
         this.interval = Math.min(this.interval * 2, this.maxInterval)
         this.timer = setTimeout(() => this.poll(), this.interval)
       }
     }
     
     stop() {
       if (this.timer) {
         clearTimeout(this.timer)
         this.timer = null
       }
     }
   }
   ```

5. **Connection State UI:**
   ```erb
   <!-- app/views/shared/_connection_status.html.erb -->
   <div data-controller="connection-status"
        data-connection-status-state-value="<%= @connection_state %>"
        class="fixed bottom-4 right-4 z-50">
     
     <!-- Offline indicator -->
     <div data-connection-status-target="offline"
          class="hidden bg-slate-900 text-white px-4 py-2 rounded-lg shadow-lg">
       <div class="flex items-center space-x-2">
         <%= heroicon "wifi-off", class: "w-5 h-5" %>
         <span>Sin conexión</span>
       </div>
     </div>
     
     <!-- Reconnecting indicator -->
     <div data-connection-status-target="reconnecting"
          class="hidden bg-amber-600 text-white px-4 py-2 rounded-lg shadow-lg">
       <div class="flex items-center space-x-2">
         <%= heroicon "arrow-path", class: "w-5 h-5 animate-spin" %>
         <span>Reconectando...</span>
       </div>
     </div>
     
     <!-- Manual retry button -->
     <div data-connection-status-target="retry"
          class="hidden bg-rose-600 text-white px-4 py-2 rounded-lg shadow-lg">
       <div class="flex items-center space-x-2">
         <span>Conexión perdida</span>
         <button data-action="click->connection-status#retry"
                 class="ml-2 px-2 py-1 bg-white text-rose-600 rounded text-sm font-medium">
           Reintentar
         </button>
       </div>
     </div>
   </div>
   ```

6. **Testing:**
   ```ruby
   RSpec.describe SyncErrorHandler do
     it "retries recoverable errors with backoff" do
       error = Net::ReadTimeout.new
       session = create(:sync_session)
       
       expect(EmailSyncJob).to receive(:set).with(wait: 1.second)
       
       handler.handle_error(error, session, retry_count: 0)
     end
     
     it "fails after max retries" do
       error = Net::ReadTimeout.new
       session = create(:sync_session)
       
       handler.handle_error(error, session, retry_count: 3)
       
       expect(session.reload).to be_failed
     end
   end
   ```

7. **Monitoring & Alerting:**
   - Track error rates by type
   - Monitor retry success rates
   - Alert on connection failure spikes
   - Dashboard for WebSocket health metrics

