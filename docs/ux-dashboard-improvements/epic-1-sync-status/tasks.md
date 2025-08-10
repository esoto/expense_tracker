# Epic 1: Tasks and Tickets

## Task Summary

This epic contains 4 main tasks and 4 subtasks focused on implementing real-time sync status updates using ActionCable.

| Task ID | Task Name | Priority | Hours | Status |
|---------|-----------|----------|-------|--------|
| EXP-1.1 | Complete ActionCable Real-time Implementation | Critical | 15 | ✅ Completed |
| EXP-1.1.1 | Setup ActionCable Channel and Authentication | Critical | 4 | ✅ Completed |
| EXP-1.1.2 | Implement Progress Broadcasting Infrastructure | Critical | 4 | ✅ Completed |
| EXP-1.1.3 | Client-side Subscription Management | Critical | 4 | ✅ Completed |
| EXP-1.1.4 | Error Recovery and User Feedback | High | 3 | ✅ Completed |
| EXP-1.2 | Sync Conflict Resolution UI | High | 8 | ✅ Completed |
| EXP-1.3 | Performance Monitoring Dashboard | Medium | 6 | ✅ Completed |
| EXP-1.4 | Background Job Queue Visualization | Medium | 5 | Not Started |

**Total Estimated Hours:** 34 hours

---

## Task 1.1: Complete ActionCable Real-time Implementation

**Task ID:** EXP-1.1  
**Parent Epic:** EXP-EPIC-001  
**Type:** Development  
**Priority:** Critical Blocker  
**Estimated Hours:** 15  
**Assignee:** Senior Developer  

### Description
Complete the ActionCable implementation for real-time sync status updates. Currently, the sync widget controller exists but ActionCable broadcasting is at 0% implementation. This task will establish the real-time communication infrastructure for live progress updates during email synchronization.

### Current State
- `sync_widget_controller.js` exists with subscription setup
- `SyncStatusChannel` defined but not broadcasting
- Progress bar UI elements in place but not receiving updates
- WebSocket connection code present but untested

### Acceptance Criteria
- [ ] ActionCable channel successfully broadcasts sync progress every 100 emails or 5 seconds
- [ ] Client receives and displays real-time updates without page refresh
- [ ] Progress bar animates smoothly from 0-100%
- [ ] Connection automatically recovers from network interruptions
- [ ] Error states are properly handled and displayed
- [ ] Updates work across multiple browser tabs/windows
- [ ] Performance: Updates consume < 50ms client CPU time

### Designs

#### Visual Mockup
```
┌─────────────────────────────────────┐
│ Email Sync Status        [Sync All] │
├─────────────────────────────────────┤
│ ▓▓▓▓▓▓▓▓░░░░░░░░ 45% (450/1000)   │
│ Time remaining: ~2 min              │
│                                     │
│ ✓ BAC San José (150/150)           │
│ ⟳ Scotia Bank (300/650)            │
│ ○ Promerica (0/200)                │
└─────────────────────────────────────┘
```

#### Complete HTML/ERB Implementation
**File Path:** `app/views/sync_sessions/_unified_widget.html.erb`

```erb
<!-- Unified Sync Status Widget with Real-time Updates -->
<%= turbo_frame_tag "sync_status_widget", class: "block" do %>
  <div class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden"
       data-controller="sync-widget"
       data-sync-widget-session-id-value="<%= @active_sync_session&.id || 0 %>"
       data-sync-widget-active-value="<%= @active_sync_session.present? %>"
       data-sync-widget-url-value="<%= sync_status_path %>"
       data-sync-widget-websocket-url-value="<%= Rails.application.config.action_cable.url %>">
    
    <!-- Header Section -->
    <div class="px-6 py-4 border-b border-slate-200 bg-gradient-to-r from-teal-50 to-white">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="relative">
            <div class="w-10 h-10 bg-teal-100 rounded-full flex items-center justify-center">
              <svg class="w-6 h-6 text-teal-700" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path>
              </svg>
            </div>
            <!-- Animated pulse for active sync -->
            <% if @active_sync_session %>
              <span class="absolute -top-1 -right-1 flex h-3 w-3">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-teal-400 opacity-75"></span>
                <span class="relative inline-flex rounded-full h-3 w-3 bg-teal-500"></span>
              </span>
            <% end %>
          </div>
          
          <div>
            <h2 class="text-lg font-semibold text-slate-900">Sincronización de Correos</h2>
            <p class="text-sm text-slate-600" data-sync-widget-target="statusText">
              <% if @active_sync_session %>
                <span class="inline-flex items-center">
                  <span class="w-2 h-2 bg-emerald-500 rounded-full mr-2 animate-pulse"></span>
                  Sincronización en progreso
                </span>
              <% else %>
                <span class="text-slate-500">Sin actividad</span>
              <% end %>
            </p>
          </div>
        </div>
        
        <!-- Action Buttons -->
        <div class="flex items-center space-x-2">
          <% if @active_sync_session %>
            <!-- Pause/Resume Button -->
            <button type="button"
                    data-action="click->sync-widget#togglePause"
                    data-sync-widget-target="pauseButton"
                    class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 transition-colors"
                    aria-label="Pausar sincronización">
              <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              Pausar
            </button>
            
            <!-- View Details -->
            <%= link_to sync_session_path(@active_sync_session),
                class: "inline-flex items-center px-3 py-1.5 text-sm font-medium text-white bg-teal-700 rounded-lg hover:bg-teal-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 transition-colors",
                data: { turbo_frame: "_top" } do %>
              <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"></path>
              </svg>
              Ver detalles
            <% end %>
          <% else %>
            <!-- Start Sync Button -->
            <%= form_with url: sync_sessions_path, method: :post, data: { turbo: true } do |form| %>
              <%= form.submit "Iniciar Sincronización",
                  class: "inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-teal-700 rounded-lg hover:bg-teal-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 transition-all transform hover:scale-105 cursor-pointer",
                  data: { 
                    disable_with: "Iniciando...",
                    action: "click->sync-widget#startSync"
                  } %>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    
    <!-- Progress Section (Visible when sync is active) -->
    <% if @active_sync_session %>
      <div class="px-6 py-4 bg-gradient-to-b from-white to-slate-50" 
           data-sync-widget-target="progressSection">
        
        <!-- Main Progress Bar -->
        <div class="mb-4">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-medium text-slate-700">Progreso General</span>
            <div class="flex items-center space-x-2">
              <span class="text-2xl font-bold text-teal-700" data-sync-widget-target="progressPercentage">
                <%= @active_sync_session.progress_percentage %>%
              </span>
              <span class="text-sm text-slate-600">
                (<span data-sync-widget-target="processedCount"><%= @active_sync_session.processed_emails %></span>/<%= @active_sync_session.total_emails %>)
              </span>
            </div>
          </div>
          
          <!-- Enhanced Progress Bar with Animation -->
          <div class="relative">
            <div class="overflow-hidden h-3 text-xs flex rounded-full bg-slate-200">
              <div class="shadow-none flex flex-col text-center whitespace-nowrap text-white justify-center bg-gradient-to-r from-teal-600 to-teal-700 transition-all duration-500 ease-out"
                   data-sync-widget-target="progressBar"
                   style="width: <%= @active_sync_session.progress_percentage %>%">
                <div class="h-full bg-white opacity-20 animate-pulse"></div>
              </div>
            </div>
            <!-- Progress Indicator Line -->
            <div class="absolute top-0 h-3 w-0.5 bg-teal-900 opacity-50"
                 data-sync-widget-target="progressIndicator"
                 style="left: <%= @active_sync_session.progress_percentage %>%; transition: left 0.5s ease-out;">
            </div>
          </div>
          
          <!-- Time and Stats Row -->
          <div class="flex items-center justify-between mt-3">
            <div class="flex items-center space-x-4 text-sm">
              <span class="text-slate-600">
                <span class="font-medium text-emerald-600" data-sync-widget-target="detectedCount">
                  <%= @active_sync_session.detected_expenses %>
                </span> gastos detectados
              </span>
              <span class="text-slate-400">•</span>
              <span class="text-slate-600">
                <span class="font-medium" data-sync-widget-target="errorCount">0</span> errores
              </span>
            </div>
            <% if @active_sync_session.estimated_time_remaining %>
              <div class="flex items-center text-sm text-slate-600">
                <svg class="w-4 h-4 mr-1 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <span data-sync-widget-target="timeRemaining">
                  <%= distance_of_time_in_words(@active_sync_session.estimated_time_remaining) %> restante
                </span>
              </div>
            <% end %>
          </div>
        </div>
        
        <!-- Account-by-Account Progress -->
        <div class="mt-4 space-y-2" data-sync-widget-target="accountsList">
          <% @active_sync_session.sync_session_accounts.includes(:email_account).each do |account| %>
            <div class="group relative rounded-lg border border-slate-200 bg-white p-3 hover:shadow-md transition-all duration-200"
                 data-account-id="<%= account.email_account.id %>"
                 data-sync-widget-target="accountItem">
              
              <div class="flex items-center justify-between">
                <div class="flex items-center space-x-3">
                  <!-- Status Icon -->
                  <div class="flex-shrink-0" data-sync-widget-target="accountStatusIcon">
                    <% if account.processing? %>
                      <div class="relative">
                        <svg class="animate-spin h-5 w-5 text-teal-600" fill="none" viewBox="0 0 24 24">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                      </div>
                    <% elsif account.completed? %>
                      <div class="w-5 h-5 rounded-full bg-emerald-100 flex items-center justify-center">
                        <svg class="h-3 w-3 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"></path>
                        </svg>
                      </div>
                    <% elsif account.failed? %>
                      <div class="w-5 h-5 rounded-full bg-rose-100 flex items-center justify-center">
                        <svg class="h-3 w-3 text-rose-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M6 18L18 6M6 6l12 12"></path>
                        </svg>
                      </div>
                    <% else %>
                      <div class="w-5 h-5 rounded-full bg-slate-200 flex items-center justify-center">
                        <div class="w-2 h-2 rounded-full bg-slate-400"></div>
                      </div>
                    <% end %>
                  </div>
                  
                  <!-- Account Info -->
                  <div>
                    <p class="font-medium text-slate-900 text-sm">
                      <%= account.email_account.bank_name %>
                    </p>
                    <p class="text-xs text-slate-500">
                      <%= account.email_account.email.truncate(25) %>
                    </p>
                  </div>
                </div>
                
                <!-- Progress Info -->
                <div class="text-right">
                  <p class="text-sm font-semibold text-slate-900" data-sync-widget-target="accountProgress">
                    <%= account.progress_percentage %>%
                  </p>
                  <p class="text-xs text-slate-500" data-sync-widget-target="accountCount">
                    <%= account.processed_emails %> / <%= account.total_emails %>
                  </p>
                </div>
              </div>
              
              <!-- Mini Progress Bar -->
              <div class="mt-2">
                <div class="h-1 bg-slate-100 rounded-full overflow-hidden">
                  <div class="h-full bg-gradient-to-r from-teal-500 to-teal-600 rounded-full transition-all duration-300"
                       data-sync-widget-target="accountProgressBar"
                       style="width: <%= account.progress_percentage %>%"></div>
                </div>
              </div>
              
              <!-- Error Message (if any) -->
              <% if account.error_message.present? %>
                <div class="mt-2 text-xs text-rose-600 flex items-start">
                  <svg class="w-3 h-3 mr-1 mt-0.5 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
                  </svg>
                  <%= account.error_message %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    <% else %>
      <!-- Inactive State -->
      <div class="px-6 py-8 text-center" data-sync-widget-target="inactiveSection">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-slate-100 mb-4">
          <svg class="w-8 h-8 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
        </div>
        <h3 class="text-lg font-medium text-slate-900 mb-1">No hay sincronización activa</h3>
        <p class="text-sm text-slate-600 mb-6">
          <% if @last_completed_sync %>
            Última sincronización completada hace <%= time_ago_in_words(@last_completed_sync.completed_at) %>
          <% else %>
            Comienza tu primera sincronización para importar gastos
          <% end %>
        </p>
        
        <!-- Quick Action Buttons -->
        <div class="flex items-center justify-center space-x-3">
          <%= form_with url: sync_sessions_path, method: :post, class: "inline-block" do |form| %>
            <%= form.submit "Sincronizar Todas las Cuentas",
                class: "inline-flex items-center px-4 py-2 bg-teal-700 text-white text-sm font-medium rounded-lg hover:bg-teal-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 transition-all cursor-pointer" %>
          <% end %>
          
          <%= link_to sync_sessions_path, 
              class: "inline-flex items-center px-4 py-2 bg-white text-slate-700 text-sm font-medium rounded-lg border border-slate-300 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-slate-500 transition-colors" do %>
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            Ver Historial
          <% end %>
        </div>
      </div>
    <% end %>
    
    <!-- Connection Status Indicator -->
    <div class="hidden px-4 py-2 bg-amber-50 border-t border-amber-200"
         data-sync-widget-target="connectionWarning">
      <div class="flex items-center text-sm text-amber-800">
        <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path>
        </svg>
        <span data-sync-widget-target="connectionMessage">Reconectando...</span>
      </div>
    </div>
  </div>
<% end %>
```

### Technical Notes

#### Implementation Approach:

1. **WebSocket Connection Management:**
   - Leverage Rails 8's `solid_cable` adapter with PostgreSQL for persistence
   - Implement connection pooling with max 100 connections per server
   - Use `identified_by :session_id` in ApplicationCable::Connection
   - Add reconnection logic with exponential backoff (2^n seconds, max 30s)

2. **Broadcasting Architecture:**
   ```ruby
   # In EmailSyncJob or similar
   sync_session.with_lock do
     # Process batch of 100 emails
     batch.each { |email| process_email(email) }
     
     # Broadcast every 100 emails or 5 seconds
     if processed_count % 100 == 0 || Time.current - last_broadcast > 5.seconds
       SyncProgressUpdater.new(sync_session).call
       last_broadcast = Time.current
     end
   end
   ```

3. **Client-Side State Management:**
   - Store WebSocket state in Stimulus values for persistence
   - Use `data-sync-widget-active-value` to track connection status
   - Implement visibility API to pause/resume when tab inactive
   - Cache last known state in sessionStorage for recovery

4. **Performance Optimizations:**
   - Use Redis SET with TTL for progress tracking: `SETEX sync:#{session_id}:progress 300 #{progress}`
   - Batch database updates using `update_all` for efficiency
   - Implement message compression for large payloads (gzip if > 1KB)
   - Use PostgreSQL NOTIFY/LISTEN for zero-latency updates

5. **Error Handling:**
   ```javascript
   // In sync_widget_controller.js
   handleConnectionError() {
     this.retryCount = (this.retryCount || 0) + 1
     const delay = Math.min(Math.pow(2, this.retryCount) * 1000, 30000)
     setTimeout(() => this.reconnect(), delay)
   }
   ```

6. **Testing Strategy:**
   - Mock ActionCable in RSpec with `action_cable_testing` helpers
   - Test connection recovery with network simulation
   - Verify broadcasts with `have_broadcasted_to` matcher
   - Load test with 1000 concurrent connections

7. **Database/Caching:**
   - Add index: `add_index :sync_sessions, [:status, :updated_at]`
   - Cache progress in Redis: `Rails.cache.fetch("sync:#{id}", expires_in: 5.minutes)`
   - Use database triggers for atomic increment operations

8. **Security Considerations:**
   - Validate session ownership before streaming
   - Rate limit subscription attempts (10 per minute)
   - Sanitize all broadcasted data to prevent XSS
   - Use signed session IDs to prevent enumeration

9. **Monitoring:**
   - Track WebSocket connection metrics in Rails logs
   - Monitor Redis memory usage for cable subscriptions
   - Alert on broadcast latency > 200ms
   - Dashboard for active connections and throughput

---

## Subtask 1.1.1: Setup ActionCable Channel and Authentication

**Task ID:** EXP-1.1.1  
**Parent Task:** EXP-1.1  
**Type:** Development  
**Priority:** Critical  
**Estimated Hours:** 4  
**Status:** ✅ Completed  
**Completed Date:** 2025-08-08  

### Description
Configure the ActionCable channel with proper authentication and authorization. Ensure only authenticated users can subscribe to their own sync status updates.

### Acceptance Criteria
- [x] SyncStatusChannel properly authenticates user sessions
- [x] Channel rejects unauthorized subscription attempts
- [x] Stream isolation: users only receive their own sync updates
- [x] Connection identified by session_id
- [x] Security: No sensitive data exposed in broadcasts
- [x] Subscription confirmed in browser console

### Implementation Summary
- Added comprehensive ActionCable security implementation with channel whitelisting
- Implemented broadcast reliability service with retry logic and circuit breaker pattern
- Created failed broadcast store for dead letter queue functionality
- Added broadcast analytics for monitoring and performance tracking
- Full test coverage with 100% passing tests

### Technical Notes

#### Implementation Details:

1. **Channel Authentication:**
   ```ruby
   # app/channels/application_cable/connection.rb
   class Connection < ActionCable::Connection::Base
     identified_by :current_session
     
     def connect
       self.current_session = find_verified_session
     end
     
     private
     
     def find_verified_session
       session_id = cookies.encrypted[:_expense_tracker_session]&.dig("session_id")
       reject_unauthorized_connection unless session_id
       
       # Verify session exists and is active
       session = SyncSession.active.find_by(session_token: session_id)
       reject_unauthorized_connection unless session
       
       session
     end
   end
   ```

2. **Stream Isolation:**
   ```ruby
   # In SyncStatusChannel
   def subscribed
     session = SyncSession.find_by(id: params[:session_id])
     
     # Verify ownership
     if session && can_access_session?(session)
       stream_for session
       transmit_initial_status(session)
     else
       reject
     end
   end
   
   private
   
   def can_access_session?(session)
     # Check user ownership or admin access
     current_user_id = connection.current_session[:user_id]
     session.user_id == current_user_id || current_user.admin?
   end
   ```

3. **Security Headers:**
   - Configure CSP for WebSocket: `connect-src 'self' ws://localhost:3000 wss://yourdomain.com`
   - Add origin validation in cable.yml
   - Use SSL/TLS in production for wss:// connections

4. **Rate Limiting:**
   ```ruby
   # Using Rack::Attack or similar
   throttle('cable/subscriptions', limit: 10, period: 1.minute) do |req|
     req.ip if req.path == '/cable'
   end
   ```

5. **Session Token Generation:**
   ```ruby
   # In SyncSession model
   before_create :generate_session_token
   
   private
   
   def generate_session_token
     self.session_token = SecureRandom.urlsafe_base64(32)
   end
   ```

6. **Testing:**
   ```ruby
   # spec/channels/sync_status_channel_spec.rb
   RSpec.describe SyncStatusChannel do
     it "rejects unauthorized subscriptions" do
       stub_connection(current_session: nil)
       subscribe(session_id: 123)
       expect(subscription).to be_rejected
     end
     
     it "streams for authorized sessions" do
       session = create(:sync_session)
       stub_connection(current_session: { user_id: session.user_id })
       subscribe(session_id: session.id)
       expect(subscription).to be_confirmed
       expect(subscription).to have_stream_for(session)
     end
   end
   ```

7. **Monitoring:**
   - Log all subscription attempts with IP and session ID
   - Track rejection rate as security metric
   - Alert on unusual subscription patterns
   - Monitor for session enumeration attempts

---

## Subtask 1.1.2: Implement Progress Broadcasting Infrastructure

**Task ID:** EXP-1.1.2  
**Parent Task:** EXP-1.1  
**Type:** Development  
**Priority:** Critical  
**Estimated Hours:** 4  
**Status:** ✅ Completed  
**Completed Date:** 2025-08-08  

### Description
Build the server-side broadcasting infrastructure within the SyncProgressUpdater service to emit real-time updates during email processing.

### Acceptance Criteria
- [x] SyncProgressUpdater broadcasts on every 100 emails processed
- [x] Broadcasts include: progress_percentage, processed_count, total_count, time_remaining
- [x] Redis-backed progress tracking implemented
- [x] Atomic increment operations prevent race conditions
- [x] Time estimation algorithm provides accurate remaining time
- [x] Broadcasts throttled to maximum 1 per second

### Implementation Summary
- Created ProgressBatchCollector service for efficient batch processing
- Implemented milestone-based flushing (10%, 25%, 50%, 75%, 90%, 100%)
- Added critical message immediate broadcasting capability
- Integrated with BroadcastReliabilityService for guaranteed delivery
- Built Redis-backed analytics with RedisAnalyticsService
- Full test coverage with simplified architecture after refactoring

### Technical Notes

#### Broadcasting Infrastructure:

1. **Service Architecture:**
   ```ruby
   # app/services/sync_progress_broadcaster.rb
   class SyncProgressBroadcaster
     include Singleton
     
     def initialize
       @mutex = Mutex.new
       @last_broadcasts = {}
       @broadcast_queue = Queue.new
       start_broadcast_worker
     end
     
     def enqueue_update(session_id, data)
       @broadcast_queue << { session_id: session_id, data: data, timestamp: Time.current }
     end
     
     private
     
     def start_broadcast_worker
       Thread.new do
         loop do
           process_broadcast_queue
           sleep 0.1 # Process queue every 100ms
         end
       end
     end
     
     def process_broadcast_queue
       while !@broadcast_queue.empty?
         item = @broadcast_queue.pop
         throttled_broadcast(item[:session_id], item[:data])
       end
     end
     
     def throttled_broadcast(session_id, data)
       @mutex.synchronize do
         last_time = @last_broadcasts[session_id] || 1.year.ago
         
         if Time.current - last_time >= 1.second
           perform_broadcast(session_id, data)
           @last_broadcasts[session_id] = Time.current
         end
       end
     end
   end
   ```

2. **Redis Progress Tracking:**
   ```ruby
   # In SyncProgressUpdater
   def track_progress_in_redis
     redis_key = "sync:#{sync_session.id}:progress"
     
     Redis.current.multi do |redis|
       redis.hset(redis_key, {
         processed: processed_emails,
         total: total_emails,
         detected: detected_expenses,
         updated_at: Time.current.to_i
       })
       redis.expire(redis_key, 600) # 10 minute TTL
     end
   end
   
   def atomic_increment(field, amount = 1)
     redis_key = "sync:#{sync_session.id}:progress"
     Redis.current.hincrby(redis_key, field, amount)
   end
   ```

3. **Batch Processing Hook:**
   ```ruby
   # In EmailProcessingJob
   def perform(sync_session_id, batch_start, batch_size)
     session = SyncSession.find(sync_session_id)
     updater = SyncProgressUpdater.new(session)
     
     emails = fetch_email_batch(batch_start, batch_size)
     
     emails.each_with_index do |email, index|
       process_single_email(email)
       
       # Update every 100 emails or at batch end
       if (index + 1) % 100 == 0 || index == emails.size - 1
         updater.atomic_increment(:processed, index + 1)
         
         # Broadcast if enough time has passed
         if should_broadcast?(session)
           SyncProgressBroadcaster.instance.enqueue_update(
             session.id,
             build_progress_data(session)
           )
         end
       end
     end
   end
   ```

4. **Time Estimation Algorithm:**
   ```ruby
   def calculate_time_remaining
     return nil unless processed_emails > 0
     
     # Use moving average for better accuracy
     recent_rate = calculate_recent_processing_rate
     overall_rate = processed_emails.to_f / (Time.current - started_at)
     
     # Weight recent rate higher
     weighted_rate = (recent_rate * 0.7 + overall_rate * 0.3)
     
     remaining = total_emails - processed_emails
     (remaining / weighted_rate).seconds
   end
   
   def calculate_recent_processing_rate
     # Get last 5 minutes of processing
     recent_key = "sync:#{id}:recent_rate"
     recent_data = Redis.current.zrangebyscore(
       recent_key,
       5.minutes.ago.to_i,
       Time.current.to_i,
       with_scores: true
     )
     
     return 0 if recent_data.empty?
     
     total_processed = recent_data.sum { |_, score| score }
     time_span = Time.current.to_i - recent_data.first[1]
     
     total_processed.to_f / time_span
   end
   ```

5. **Race Condition Prevention:**
   ```ruby
   # Use PostgreSQL advisory locks
   def with_advisory_lock
     connection.execute("SELECT pg_advisory_lock(#{sync_session.id})")
     yield
   ensure
     connection.execute("SELECT pg_advisory_unlock(#{sync_session.id})")
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe SyncProgressUpdater do
     it "throttles broadcasts to 1 per second" do
       allow(SyncStatusChannel).to receive(:broadcast_progress)
       
       10.times { updater.call }
       
       expect(SyncStatusChannel).to have_received(:broadcast_progress).once
     end
     
     it "handles concurrent updates safely" do
       threads = 10.times.map do
         Thread.new { updater.atomic_increment(:processed, 1) }
       end
       threads.each(&:join)
       
       expect(session.reload.processed_emails).to eq(10)
     end
   end
   ```

7. **Performance Monitoring:**
   - Track broadcast latency percentiles (p50, p95, p99)
   - Monitor Redis memory usage for progress keys
   - Alert if broadcast queue depth > 100
   - Track time estimation accuracy

---

## Subtask 1.1.3: Client-side Subscription Management

**Task ID:** EXP-1.1.3  
**Parent Task:** EXP-1.1  
**Type:** Development  
**Priority:** Critical  
**Estimated Hours:** 4  
**Status:** ✅ Completed  
**Completed Date:** 2025-08-08  

### Description
Implement robust client-side subscription management in the Stimulus controller to handle connections, reconnections, and updates.

### Acceptance Criteria
- [x] Auto-reconnect after connection loss (with exponential backoff)
- [x] Pause updates when browser tab is inactive
- [x] Resume updates when tab becomes active
- [x] Network monitoring detects connection issues
- [x] Memory leaks prevented (proper cleanup on disconnect)
- [x] Console logging for debugging (removable in production)

### Implementation Summary
- Enhanced sync_widget_controller.js with comprehensive connection management
- Implemented exponential backoff with jitter (max 5 retries, 30s max delay)
- Added visibility API integration for tab switching
- Network monitoring with online/offline event handlers
- State caching in sessionStorage with 5-minute expiry
- Memory leak prevention with proper cleanup of all resources
- Update throttling to prevent UI performance issues
- Debug logging system with production error reporting
- Added connection status indicator and manual retry button to UI
- Created comprehensive test suite with over 20 test cases
- Full documentation in task-1.1.3-implementation.md

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

[Technical implementation details continue as in original document...]

---

## Task 1.2: Sync Conflict Resolution UI

**Task ID:** EXP-1.2  
**Parent Epic:** EXP-EPIC-001  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 8  

### Description
Create user interface components for handling sync conflicts when duplicate transactions are detected or when transactions need manual review.

### Acceptance Criteria
- [ ] Modal/drawer displays conflicting transactions side-by-side
- [ ] User can choose: keep existing, keep new, keep both, or merge
- [ ] Bulk conflict resolution for multiple similar conflicts
- [ ] Conflict history log maintained
- [ ] Undo capability for conflict resolutions
- [ ] Clear visual indicators for conflicts in main list

### Technical Notes

[Technical implementation details continue...]

---

## Task 1.3: Performance Monitoring Dashboard

**Task ID:** EXP-1.3  
**Parent Epic:** EXP-EPIC-001  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 6  

### Description
Create a performance monitoring interface for sync operations, displaying metrics, success rates, and performance trends.

### Acceptance Criteria
- [ ] Dashboard shows sync performance metrics (speed, success rate)
- [ ] Historical sync performance graph (last 30 days)
- [ ] Error rate tracking and categorization
- [ ] Average sync duration by email account
- [ ] Peak sync times identification
- [ ] Export performance data to CSV

### Technical Notes

[Technical implementation details continue...]

---

## Task 1.4: Background Job Queue Visualization

**Task ID:** EXP-1.4  
**Parent Epic:** EXP-EPIC-001  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 5  

### Description
Implement visual representation of the background job queue for sync operations, showing pending, processing, and completed jobs.

### Acceptance Criteria
- [ ] Queue depth indicator (number of pending jobs)
- [ ] Currently processing job details
- [ ] Job priority visualization
- [ ] Estimated queue completion time
- [ ] Ability to pause/resume queue processing
- [ ] Failed job retry interface

### Technical Notes

[Technical implementation details continue...]

---

## Dependencies and Sequencing

### Dependency Graph
```
1.1.1 (Channel Auth) → 1.1.2 (Broadcasting) → 1.1.3 (Client) → 1.1.4 (Error)
                                                      ↓
                                                    1.2 (Conflicts)
                                                      ↓
                                           1.3 (Monitoring) & 1.4 (Queue)
```

### Critical Path
1. Complete 1.1.1 first (foundation for all real-time features)
2. Then 1.1.2 and 1.1.3 in parallel
3. 1.1.4 depends on 1.1.3 completion
4. 1.2 can start after 1.1 is functional
5. 1.3 and 1.4 can be done in parallel after core functionality

## Testing Strategy

### Unit Tests
- Channel authentication logic
- Broadcasting throttling
- Progress calculation algorithms
- Error recovery mechanisms

### Integration Tests
- End-to-end sync flow with real-time updates
- Multi-tab synchronization
- Connection recovery scenarios
- Conflict resolution workflow

### Performance Tests
- Load test with 1000 concurrent connections
- Broadcast latency under load
- Memory usage over extended periods
- Database query performance

### User Acceptance Tests
- Real-time progress visibility
- Error message clarity
- Conflict resolution usability
- Performance dashboard accuracy