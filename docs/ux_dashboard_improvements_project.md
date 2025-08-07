# UX Dashboard Improvements Project

## Project Overview
**Project Name:** Expense Tracker Dashboard UX Improvements  
**Duration:** 8-10 weeks  
**Team Size:** 2 developers, 1 QA (40%), 1 UX Designer (20%)  
**Priority:** High  
**Start Date:** TBD  
**End Date:** TBD  

### Executive Summary
Enhance the expense tracker dashboard user experience through three major improvements focused on information hierarchy, visual organization, and interaction efficiency. This project will reduce cognitive load by 40%, improve task completion time, and double information density for better financial management.

### Business Goals
- Improve user engagement with financial data
- Reduce time to complete common tasks by 70%
- Increase dashboard scanability and usability
- Enable efficient bulk operations for expense management

---

## Epic 1: Consolidate and Optimize Sync Status Interface

**Epic ID:** EXP-EPIC-001  
**Priority:** Critical  
**Status:** 77% Implemented  
**Estimated Duration:** 2 weeks  
**Epic Owner:** TBD  

### Epic Description
Eliminate redundancy in sync status display and improve clarity by consolidating two separate sync sections into a unified, real-time widget with clear action hierarchy and dedicated management page.

### Business Value
- Reduces cognitive load by 40% through elimination of duplicate information
- Improves sync initiation task completion time
- Frees dashboard space for financial data
- Provides clear, real-time sync progress visibility

### Success Metrics
- Single sync status widget on dashboard
- Real-time update latency < 100ms
- 100% of users see real-time progress
- Zero duplicate sync information

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

### Description
Configure the ActionCable channel with proper authentication and authorization. Ensure only authenticated users can subscribe to their own sync status updates.

### Acceptance Criteria
- [ ] SyncStatusChannel properly authenticates user sessions
- [ ] Channel rejects unauthorized subscription attempts
- [ ] Stream isolation: users only receive their own sync updates
- [ ] Connection identified by session_id
- [ ] Security: No sensitive data exposed in broadcasts
- [ ] Subscription confirmed in browser console

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

### Description
Build the server-side broadcasting infrastructure within the SyncProgressUpdater service to emit real-time updates during email processing.

### Acceptance Criteria
- [ ] SyncProgressUpdater broadcasts on every 100 emails processed
- [ ] Broadcasts include: progress_percentage, processed_count, total_count, time_remaining
- [ ] Redis-backed progress tracking implemented
- [ ] Atomic increment operations prevent race conditions
- [ ] Time estimation algorithm provides accurate remaining time
- [ ] Broadcasts throttled to maximum 1 per second

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

### Designs
```
┌─────────────────────────────────────┐
│ Sync Conflict Resolution            │
├─────────────────────────────────────┤
│ 3 potential duplicates found        │
│                                     │
│ ┌─────────┬─────────┬─────────┐   │
│ │Existing │  New    │ Action  │   │
│ ├─────────┼─────────┼─────────┤   │
│ │$45.00   │$45.00   │[Keep]   │   │
│ │Walmart  │WALMART  │[Merge]  │   │
│ │Jan 15   │Jan 15   │[Skip]   │   │
│ └─────────┴─────────┴─────────┘   │
│                                     │
│ [Apply to All Similar] [Review Each]│
└─────────────────────────────────────┘
```

### Technical Notes

#### Conflict Resolution Implementation:

1. **Duplicate Detection Algorithm:**
   ```ruby
   # app/services/duplicate_detector.rb
   class DuplicateDetector
     SIMILARITY_THRESHOLD = 0.85
     
     def find_duplicates(new_expense, existing_expenses)
       potential_duplicates = []
       
       existing_expenses.each do |existing|
         similarity = calculate_similarity(new_expense, existing)
         
         if similarity >= SIMILARITY_THRESHOLD
           potential_duplicates << {
             expense: existing,
             similarity: similarity,
             differences: identify_differences(new_expense, existing)
           }
         end
       end
       
       potential_duplicates.sort_by { |d| -d[:similarity] }
     end
     
     private
     
     def calculate_similarity(expense1, expense2)
       scores = []
       
       # Amount similarity (exact match or within 1%)
       amount_diff = (expense1.amount - expense2.amount).abs
       amount_score = amount_diff <= expense1.amount * 0.01 ? 1.0 : 0.0
       scores << amount_score * 0.4 # 40% weight
       
       # Date similarity (same day)
       date_score = expense1.date == expense2.date ? 1.0 : 0.0
       scores << date_score * 0.3 # 30% weight
       
       # Description similarity (fuzzy match)
       desc_score = fuzzy_match(expense1.description, expense2.description)
       scores << desc_score * 0.3 # 30% weight
       
       scores.sum
     end
     
     def fuzzy_match(str1, str2)
       return 0.0 if str1.nil? || str2.nil?
       
       # Normalize strings
       s1 = str1.downcase.gsub(/[^a-z0-9]/, '')
       s2 = str2.downcase.gsub(/[^a-z0-9]/, '')
       
       # Calculate Levenshtein distance
       distance = levenshtein_distance(s1, s2)
       max_length = [s1.length, s2.length].max
       
       return 1.0 if max_length == 0
       
       1.0 - (distance.to_f / max_length)
     end
   end
   ```

2. **Conflict Resolution UI Component:**
   ```erb
   <!-- app/views/sync_sessions/_conflict_modal.html.erb -->
   <div data-controller="conflict-resolver"
        data-conflict-resolver-conflicts-value="<%= @conflicts.to_json %>"
        class="fixed inset-0 z-50 overflow-y-auto hidden"
        data-conflict-resolver-target="modal">
     
     <div class="min-h-screen px-4 text-center">
       <div class="fixed inset-0 bg-slate-900 bg-opacity-75 transition-opacity"></div>
       
       <div class="inline-block w-full max-w-4xl my-8 text-left align-middle transition-all transform bg-white shadow-xl rounded-xl">
         <div class="px-6 py-4 border-b border-slate-200">
           <h3 class="text-xl font-semibold text-slate-900">
             Resolver Conflictos de Sincronización
           </h3>
           <p class="mt-1 text-sm text-slate-600">
             Se encontraron <%= @conflicts.size %> posibles duplicados
           </p>
         </div>
         
         <div class="px-6 py-4 max-h-96 overflow-y-auto">
           <% @conflicts.each_with_index do |conflict, index| %>
             <div class="mb-6 p-4 bg-slate-50 rounded-lg" 
                  data-conflict-index="<%= index %>">
               
               <div class="grid grid-cols-3 gap-4">
                 <!-- Existing expense -->
                 <div class="space-y-2">
                   <h4 class="font-medium text-slate-700">Existente</h4>
                   <div class="bg-white p-3 rounded border border-slate-200">
                     <p class="font-semibold"><%= format_currency(conflict[:existing].amount) %></p>
                     <p class="text-sm text-slate-600"><%= conflict[:existing].description %></p>
                     <p class="text-xs text-slate-500"><%= l(conflict[:existing].date) %></p>
                   </div>
                 </div>
                 
                 <!-- New expense -->
                 <div class="space-y-2">
                   <h4 class="font-medium text-slate-700">Nuevo</h4>
                   <div class="bg-white p-3 rounded border border-teal-200">
                     <p class="font-semibold"><%= format_currency(conflict[:new].amount) %></p>
                     <p class="text-sm text-slate-600"><%= conflict[:new].description %></p>
                     <p class="text-xs text-slate-500"><%= l(conflict[:new].date) %></p>
                   </div>
                 </div>
                 
                 <!-- Actions -->
                 <div class="space-y-2">
                   <h4 class="font-medium text-slate-700">Acción</h4>
                   <div class="space-y-2">
                     <button data-action="click->conflict-resolver#keepExisting"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm hover:bg-slate-50">
                       Mantener Existente
                     </button>
                     <button data-action="click->conflict-resolver#keepNew"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-teal-700 text-white rounded-lg text-sm hover:bg-teal-800">
                       Usar Nuevo
                     </button>
                     <button data-action="click->conflict-resolver#keepBoth"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-amber-600 text-white rounded-lg text-sm hover:bg-amber-700">
                       Mantener Ambos
                     </button>
                     <button data-action="click->conflict-resolver#merge"
                             data-conflict-index="<%= index %>"
                             class="w-full px-3 py-2 bg-slate-600 text-white rounded-lg text-sm hover:bg-slate-700">
                       Combinar
                     </button>
                   </div>
                 </div>
               </div>
               
               <!-- Similarity indicator -->
               <div class="mt-3 flex items-center space-x-2">
                 <span class="text-xs text-slate-500">Similaridad:</span>
                 <div class="flex-1 bg-slate-200 rounded-full h-2">
                   <div class="bg-amber-600 h-2 rounded-full"
                        style="width: <%= (conflict[:similarity] * 100).round %>%"></div>
                 </div>
                 <span class="text-xs font-medium text-slate-700">
                   <%= (conflict[:similarity] * 100).round %>%
                 </span>
               </div>
             </div>
           <% end %>
         </div>
         
         <!-- Bulk actions -->
         <div class="px-6 py-4 bg-slate-50 border-t border-slate-200">
           <div class="flex items-center justify-between">
             <div class="flex items-center space-x-2">
               <input type="checkbox" 
                      data-conflict-resolver-target="applyToAll"
                      class="rounded border-slate-300 text-teal-700 focus:ring-teal-500">
               <label class="text-sm text-slate-700">
                 Aplicar a todos los conflictos similares
               </label>
             </div>
             
             <div class="flex space-x-3">
               <button data-action="click->conflict-resolver#cancel"
                       class="px-4 py-2 bg-white border border-slate-200 rounded-lg text-slate-700 hover:bg-slate-50">
                 Cancelar
               </button>
               <button data-action="click->conflict-resolver#resolve"
                       class="px-4 py-2 bg-teal-700 text-white rounded-lg hover:bg-teal-800">
                 Resolver Conflictos
               </button>
             </div>
           </div>
         </div>
       </div>
     </div>
   </div>
   ```

3. **Conflict Resolution Controller:**
   ```javascript
   // app/javascript/controllers/conflict_resolver_controller.js
   export default class extends Controller {
     static targets = ['modal', 'applyToAll']
     static values = { conflicts: Array }
     
     connect() {
       this.resolutions = new Map()
       this.initializeResolutions()
     }
     
     initializeResolutions() {
       this.conflictsValue.forEach((conflict, index) => {
         this.resolutions.set(index, { action: null, data: conflict })
       })
     }
     
     keepExisting(event) {
       const index = parseInt(event.currentTarget.dataset.conflictIndex)
       this.setResolution(index, 'keep_existing')
       
       if (this.applyToAllTarget.checked) {
         this.applyToSimilar(index, 'keep_existing')
       }
     }
     
     keepNew(event) {
       const index = parseInt(event.currentTarget.dataset.conflictIndex)
       this.setResolution(index, 'keep_new')
       
       if (this.applyToAllTarget.checked) {
         this.applyToSimilar(index, 'keep_new')
       }
     }
     
     merge(event) {
       const index = parseInt(event.currentTarget.dataset.conflictIndex)
       this.showMergeDialog(index)
     }
     
     async resolve() {
       const resolutions = Array.from(this.resolutions.values())
         .filter(r => r.action !== null)
       
       try {
         const response = await fetch('/sync_sessions/resolve_conflicts', {
           method: 'POST',
           headers: {
             'Content-Type': 'application/json',
             'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
           },
           body: JSON.stringify({ resolutions })
         })
         
         if (response.ok) {
           this.hideModal()
           this.showSuccessMessage('Conflictos resueltos exitosamente')
         } else {
           throw new Error('Failed to resolve conflicts')
         }
       } catch (error) {
         this.showErrorMessage('Error al resolver conflictos')
       }
     }
   }
   ```

4. **Conflict History Tracking:**
   ```ruby
   # app/models/sync_conflict_resolution.rb
   class SyncConflictResolution < ApplicationRecord
     belongs_to :sync_session
     belongs_to :existing_expense, class_name: 'Expense', optional: true
     belongs_to :new_expense, class_name: 'Expense', optional: true
     
     validates :action, inclusion: { 
       in: %w[keep_existing keep_new keep_both merge skip] 
     }
     
     scope :recent, -> { order(created_at: :desc) }
     scope :by_action, ->(action) { where(action: action) }
     
     def undo!
       case action
       when 'keep_new'
         new_expense&.destroy
       when 'keep_existing'
         # Re-create the new expense if we have the data
         recreate_new_expense if new_expense_data.present?
       when 'merge'
         # Revert to original states
         revert_merge
       end
       
       update!(undone: true, undone_at: Time.current)
     end
   end
   ```

5. **Testing:**
   ```ruby
   RSpec.describe DuplicateDetector do
     it "detects exact duplicates" do
       expense1 = create(:expense, amount: 100, date: Date.today)
       expense2 = build(:expense, amount: 100, date: Date.today)
       
       duplicates = detector.find_duplicates(expense2, [expense1])
       
       expect(duplicates).not_to be_empty
       expect(duplicates.first[:similarity]).to be >= 0.85
     end
     
     it "handles fuzzy description matching" do
       expense1 = create(:expense, description: "WALMART STORE #1234")
       expense2 = build(:expense, description: "Walmart Store")
       
       score = detector.fuzzy_match(
         expense1.description,
         expense2.description
       )
       
       expect(score).to be > 0.5
     end
   end
   ```

6. **Performance Considerations:**
   - Index on (amount, date) for fast duplicate queries
   - Cache similarity calculations for session
   - Batch conflict resolution to minimize DB calls
   - Use PostgreSQL full-text search for descriptions

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

#### Performance Monitoring Implementation:

1. **Metrics Collection Service:**
   ```ruby
   # app/services/sync_metrics_collector.rb
   class SyncMetricsCollector
     METRICS_RETENTION = 90.days
     
     def record_sync_metrics(sync_session)
       metrics = {
         session_id: sync_session.id,
         duration: sync_session.duration,
         total_emails: sync_session.total_emails,
         processed_emails: sync_session.processed_emails,
         detected_expenses: sync_session.detected_expenses,
         success_rate: calculate_success_rate(sync_session),
         processing_speed: calculate_processing_speed(sync_session),
         error_count: sync_session.sync_session_accounts.sum(:error_count),
         timestamp: Time.current
       }
       
       # Store in time-series format
       store_metrics(metrics)
       
       # Update aggregated stats
       update_aggregated_stats(sync_session)
       
       # Check for anomalies
       detect_performance_anomalies(metrics)
     end
     
     private
     
     def store_metrics(metrics)
       # Store in Redis for real-time access
       redis_key = "metrics:sync:#{metrics[:session_id]}:#{metrics[:timestamp].to_i}"
       
       Redis.current.multi do |redis|
         redis.hset(redis_key, metrics)
         redis.expire(redis_key, METRICS_RETENTION)
         
         # Add to sorted set for time-based queries
         redis.zadd(
           "metrics:sync:timeline",
           metrics[:timestamp].to_i,
           redis_key
         )
       end
       
       # Also persist to database for long-term storage
       SyncMetric.create!(metrics)
     end
     
     def calculate_processing_speed(session)
       return 0 if session.duration.nil? || session.duration.zero?
       
       (session.processed_emails.to_f / session.duration) * 60 # emails per minute
     end
     
     def detect_performance_anomalies(metrics)
       # Get baseline from last 30 days
       baseline = calculate_baseline_performance
       
       # Check for significant deviations
       if metrics[:processing_speed] < baseline[:speed] * 0.5
         notify_performance_degradation(metrics, baseline)
       end
       
       if metrics[:error_count] > baseline[:errors] * 2
         notify_error_spike(metrics, baseline)
       end
     end
   end
   ```

2. **Dashboard Controller:**
   ```ruby
   # app/controllers/sync_performance_controller.rb
   class SyncPerformanceController < ApplicationController
     def index
       @metrics = SyncMetricsService.new.dashboard_data(
         period: params[:period] || '7d',
         account_id: params[:account_id]
       )
       
       respond_to do |format|
         format.html
         format.json { render json: @metrics }
       end
     end
     
     def export
       data = SyncMetricsService.new.export_data(
         start_date: params[:start_date],
         end_date: params[:end_date]
       )
       
       respond_to do |format|
         format.csv { send_data data.to_csv, filename: "sync_metrics_#{Date.current}.csv" }
         format.xlsx { send_data data.to_xlsx, filename: "sync_metrics_#{Date.current}.xlsx" }
       end
     end
   end
   ```

3. **Performance Dashboard View:**
   ```erb
   <!-- app/views/sync_performance/index.html.erb -->
   <div class="p-6" data-controller="performance-dashboard">
     <div class="mb-6">
       <h2 class="text-2xl font-bold text-slate-900">Monitor de Rendimiento de Sincronización</h2>
       
       <!-- Period selector -->
       <div class="mt-4 flex space-x-2">
         <% %w[1d 7d 30d 90d].each do |period| %>
           <%= link_to period.upcase,
                       sync_performance_path(period: period),
                       class: "px-3 py-1 rounded-lg #{
                         params[:period] == period ? 
                         'bg-teal-700 text-white' : 
                         'bg-slate-200 text-slate-700'
                       }" %>
         <% end %>
       </div>
     </div>
     
     <!-- Key metrics cards -->
     <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Velocidad Promedio</div>
         <div class="text-2xl font-bold text-slate-900">
           <%= @metrics[:avg_speed] %> emails/min
         </div>
         <div class="text-xs text-<%= @metrics[:speed_trend] > 0 ? 'emerald' : 'rose' %>-600">
           <%= @metrics[:speed_trend] > 0 ? '↑' : '↓' %>
           <%= number_to_percentage(@metrics[:speed_trend].abs, precision: 1) %>
         </div>
       </div>
       
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Tasa de Éxito</div>
         <div class="text-2xl font-bold text-slate-900">
           <%= number_to_percentage(@metrics[:success_rate], precision: 1) %>
         </div>
         <div class="mt-2">
           <div class="w-full bg-slate-200 rounded-full h-2">
             <div class="bg-emerald-600 h-2 rounded-full" 
                  style="width: <%= @metrics[:success_rate] %>%"></div>
           </div>
         </div>
       </div>
       
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Errores Totales</div>
         <div class="text-2xl font-bold text-<%= @metrics[:error_count] > 0 ? 'rose' : 'emerald' %>-600">
           <%= @metrics[:error_count] %>
         </div>
         <div class="text-xs text-slate-500">
           <%= @metrics[:error_categories].to_sentence %>
         </div>
       </div>
       
       <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-4">
         <div class="text-sm text-slate-600">Duración Promedio</div>
         <div class="text-2xl font-bold text-slate-900">
           <%= distance_of_time_in_words(@metrics[:avg_duration]) %>
         </div>
         <div class="text-xs text-slate-500">
           Por <%= number_with_delimiter(@metrics[:avg_email_count]) %> emails
         </div>
       </div>
     </div>
     
     <!-- Performance chart -->
     <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 mb-6">
       <h3 class="text-lg font-semibold text-slate-900 mb-4">Rendimiento en el Tiempo</h3>
       
       <div data-performance-dashboard-target="chart"
            data-chart-data="<%= @metrics[:chart_data].to_json %>">
         <%= line_chart @metrics[:chart_data],
                        height: "300px",
                        library: {
                          scales: {
                            y: { beginAtZero: true }
                          },
                          plugins: {
                            legend: { position: 'bottom' }
                          }
                        } %>
       </div>
     </div>
     
     <!-- Account-specific metrics -->
     <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
       <h3 class="text-lg font-semibold text-slate-900 mb-4">Rendimiento por Cuenta</h3>
       
       <div class="overflow-x-auto">
         <table class="min-w-full divide-y divide-slate-200">
           <thead>
             <tr>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Cuenta
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Sincronizaciones
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Velocidad Promedio
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Tasa de Éxito
               </th>
               <th class="px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider">
                 Último Error
               </th>
             </tr>
           </thead>
           <tbody class="divide-y divide-slate-200">
             <% @metrics[:by_account].each do |account_metrics| %>
               <tr>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-900">
                   <%= account_metrics[:name] %>
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                   <%= account_metrics[:sync_count] %>
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                   <%= account_metrics[:avg_speed] %> emails/min
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm">
                   <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full 
                          bg-<%= account_metrics[:success_rate] > 95 ? 'emerald' : 'amber' %>-100 
                          text-<%= account_metrics[:success_rate] > 95 ? 'emerald' : 'amber' %>-800">
                     <%= number_to_percentage(account_metrics[:success_rate], precision: 0) %>
                   </span>
                 </td>
                 <td class="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                   <%= account_metrics[:last_error] || 'Ninguno' %>
                 </td>
               </tr>
             <% end %>
           </tbody>
         </table>
       </div>
     </div>
     
     <!-- Export button -->
     <div class="mt-6 flex justify-end">
       <%= link_to "Exportar Datos",
                   export_sync_performance_path(format: :csv),
                   class: "px-4 py-2 bg-teal-700 text-white rounded-lg hover:bg-teal-800" %>
     </div>
   </div>
   ```

4. **Peak Time Analysis:**
   ```ruby
   # app/services/sync_peak_analyzer.rb
   class SyncPeakAnalyzer
     def analyze_peak_times(period = 30.days)
       data = SyncSession.where(created_at: period.ago..Time.current)
                        .group_by_hour_of_day(:created_at)
                        .count
       
       peak_hours = data.sort_by { |_, count| -count }.first(3)
       
       {
         peak_hours: peak_hours.map { |hour, count| 
           { hour: hour, count: count, label: format_hour(hour) }
         },
         recommendations: generate_recommendations(peak_hours)
       }
     end
     
     private
     
     def generate_recommendations(peak_hours)
       recommendations = []
       
       if peak_hours.any? { |hour, _| hour.between?(9, 17) }
         recommendations << "Consider scheduling syncs outside business hours for better performance"
       end
       
       if peak_hours.any? { |hour, _| hour.between?(0, 6) }
         recommendations << "Early morning syncs show good performance"
       end
       
       recommendations
     end
   end
   ```

5. **Testing:**
   ```ruby
   RSpec.describe SyncMetricsCollector do
     it "records metrics correctly" do
       session = create(:sync_session, :completed)
       
       collector.record_sync_metrics(session)
       
       metrics = SyncMetric.last
       expect(metrics.session_id).to eq(session.id)
       expect(metrics.processing_speed).to be > 0
     end
     
     it "detects performance anomalies" do
       allow(collector).to receive(:notify_performance_degradation)
       
       slow_session = create(:sync_session, 
         processed_emails: 10,
         duration: 3600 # Very slow
       )
       
       collector.record_sync_metrics(slow_session)
       
       expect(collector).to have_received(:notify_performance_degradation)
     end
   end
   ```

6. **Performance Optimizations:**
   - Use materialized views for aggregated metrics
   - Cache dashboard data for 5 minutes
   - Background job for heavy calculations
   - Index on created_at for time-based queries

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

#### Job Queue Visualization Implementation:

1. **Queue Monitoring Service:**
   ```ruby
   # app/services/queue_monitor.rb
   class QueueMonitor
     def queue_status
       {
         pending: pending_jobs,
         processing: processing_jobs,
         completed: completed_jobs,
         failed: failed_jobs,
         queue_depth: total_pending,
         estimated_completion: estimate_completion_time,
         workers: worker_status
       }
     end
     
     private
     
     def pending_jobs
       SolidQueue::Job.where(finished_at: nil)
                      .where("scheduled_at <= ?", Time.current)
                      .includes(:job_class)
                      .map { |job| format_job(job) }
     end
     
     def processing_jobs
       SolidQueue::Job.joins(:execution)
                      .where(solid_queue_executions: { finished_at: nil })
                      .map { |job| format_job(job) }
     end
     
     def format_job(job)
       {
         id: job.id,
         class: job.job_class,
         queue: job.queue_name,
         priority: job.priority,
         scheduled_at: job.scheduled_at,
         started_at: job.execution&.started_at,
         arguments: sanitize_arguments(job.arguments),
         retries: job.executions.count - 1
       }
     end
     
     def estimate_completion_time
       return nil if pending_jobs.empty? || processing_rate.zero?
       
       (total_pending / processing_rate).seconds.from_now
     end
     
     def processing_rate
       # Calculate average processing rate over last hour
       completed_last_hour = SolidQueue::Job
         .where(finished_at: 1.hour.ago..Time.current)
         .count
       
       completed_last_hour / 60.0 # jobs per minute
     end
   end
   ```

2. **Queue Visualization Component:**
   ```erb
   <!-- app/views/sync_sessions/_queue_visualization.html.erb -->
   <div data-controller="queue-monitor"
        data-queue-monitor-refresh-interval-value="5000"
        class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
     
     <div class="flex items-center justify-between mb-4">
       <h3 class="text-lg font-semibold text-slate-900">Cola de Sincronización</h3>
       
       <div class="flex items-center space-x-2">
         <!-- Pause/Resume controls -->
         <button data-action="click->queue-monitor#pause"
                 data-queue-monitor-target="pauseButton"
                 class="px-3 py-1 bg-amber-600 text-white rounded-lg text-sm hover:bg-amber-700">
           <%= heroicon "pause", class: "w-4 h-4 inline" %>
           Pausar
         </button>
         
         <button data-action="click->queue-monitor#resume"
                 data-queue-monitor-target="resumeButton"
                 class="hidden px-3 py-1 bg-emerald-600 text-white rounded-lg text-sm hover:bg-emerald-700">
           <%= heroicon "play", class: "w-4 h-4 inline" %>
           Reanudar
         </button>
       </div>
     </div>
     
     <!-- Queue depth indicator -->
     <div class="mb-6">
       <div class="flex items-center justify-between mb-2">
         <span class="text-sm text-slate-600">Profundidad de Cola</span>
         <span class="text-sm font-medium text-slate-900" 
               data-queue-monitor-target="queueDepth">0</span>
       </div>
       
       <div class="w-full bg-slate-200 rounded-full h-3">
         <div data-queue-monitor-target="queueDepthBar"
              class="bg-gradient-to-r from-emerald-500 to-teal-600 h-3 rounded-full transition-all duration-500"
              style="width: 0%"></div>
       </div>
       
       <div class="mt-1 text-xs text-slate-500">
         Tiempo estimado: 
         <span data-queue-monitor-target="estimatedTime">Calculando...</span>
       </div>
     </div>
     
     <!-- Job states visualization -->
     <div class="grid grid-cols-4 gap-4 mb-6">
       <div class="text-center">
         <div class="text-2xl font-bold text-slate-600" 
              data-queue-monitor-target="pendingCount">0</div>
         <div class="text-xs text-slate-500">Pendientes</div>
       </div>
       
       <div class="text-center">
         <div class="text-2xl font-bold text-teal-600" 
              data-queue-monitor-target="processingCount">0</div>
         <div class="text-xs text-slate-500">Procesando</div>
       </div>
       
       <div class="text-center">
         <div class="text-2xl font-bold text-emerald-600" 
              data-queue-monitor-target="completedCount">0</div>
         <div class="text-xs text-slate-500">Completados</div>
       </div>
       
       <div class="text-center">
         <div class="text-2xl font-bold text-rose-600" 
              data-queue-monitor-target="failedCount">0</div>
         <div class="text-xs text-slate-500">Fallidos</div>
       </div>
     </div>
     
     <!-- Active jobs list -->
     <div class="border-t border-slate-200 pt-4">
       <h4 class="text-sm font-medium text-slate-700 mb-3">Trabajos Activos</h4>
       
       <div data-queue-monitor-target="activeJobs" 
            class="space-y-2 max-h-48 overflow-y-auto">
         <!-- Jobs populated via JavaScript -->
       </div>
     </div>
     
     <!-- Failed jobs with retry -->
     <div data-queue-monitor-target="failedSection" 
          class="hidden border-t border-slate-200 pt-4 mt-4">
       <h4 class="text-sm font-medium text-rose-700 mb-3">Trabajos Fallidos</h4>
       
       <div data-queue-monitor-target="failedJobs" 
            class="space-y-2">
         <!-- Failed jobs populated via JavaScript -->
       </div>
     </div>
   </div>
   ```

3. **Queue Monitor Stimulus Controller:**
   ```javascript
   // app/javascript/controllers/queue_monitor_controller.js
   export default class extends Controller {
     static targets = [
       'queueDepth', 'queueDepthBar', 'estimatedTime',
       'pendingCount', 'processingCount', 'completedCount', 'failedCount',
       'activeJobs', 'failedJobs', 'failedSection',
       'pauseButton', 'resumeButton'
     ]
     
     static values = { 
       refreshInterval: { type: Number, default: 5000 },
       maxQueueDepth: { type: Number, default: 100 }
     }
     
     connect() {
       this.refresh()
       this.startPolling()
     }
     
     disconnect() {
       this.stopPolling()
     }
     
     startPolling() {
       this.pollTimer = setInterval(() => {
         this.refresh()
       }, this.refreshIntervalValue)
     }
     
     stopPolling() {
       if (this.pollTimer) {
         clearInterval(this.pollTimer)
       }
     }
     
     async refresh() {
       try {
         const response = await fetch('/api/queue/status.json')
         const data = await response.json()
         
         this.updateDisplay(data)
       } catch (error) {
         console.error('Failed to fetch queue status:', error)
       }
     }
     
     updateDisplay(data) {
       // Update counts
       this.pendingCountTarget.textContent = data.pending.length
       this.processingCountTarget.textContent = data.processing.length
       this.completedCountTarget.textContent = data.completed_count
       this.failedCountTarget.textContent = data.failed.length
       
       // Update queue depth
       this.queueDepthTarget.textContent = data.queue_depth
       const depthPercentage = Math.min(
         (data.queue_depth / this.maxQueueDepthValue) * 100,
         100
       )
       this.queueDepthBarTarget.style.width = `${depthPercentage}%`
       
       // Update bar color based on depth
       this.updateQueueDepthColor(depthPercentage)
       
       // Update estimated time
       if (data.estimated_completion) {
         const time = new Date(data.estimated_completion)
         this.estimatedTimeTarget.textContent = this.formatTime(time)
       } else {
         this.estimatedTimeTarget.textContent = 'N/A'
       }
       
       // Update active jobs
       this.renderActiveJobs(data.processing)
       
       // Update failed jobs if any
       if (data.failed.length > 0) {
         this.failedSectionTarget.classList.remove('hidden')
         this.renderFailedJobs(data.failed)
       } else {
         this.failedSectionTarget.classList.add('hidden')
       }
     }
     
     updateQueueDepthColor(percentage) {
       const bar = this.queueDepthBarTarget
       
       bar.classList.remove('from-emerald-500', 'from-amber-500', 'from-rose-500')
       bar.classList.remove('to-teal-600', 'to-amber-600', 'to-rose-600')
       
       if (percentage < 50) {
         bar.classList.add('from-emerald-500', 'to-teal-600')
       } else if (percentage < 80) {
         bar.classList.add('from-amber-500', 'to-amber-600')
       } else {
         bar.classList.add('from-rose-500', 'to-rose-600')
       }
     }
     
     renderActiveJobs(jobs) {
       this.activeJobsTarget.innerHTML = jobs.map(job => `
         <div class="flex items-center justify-between p-2 bg-slate-50 rounded-lg">
           <div class="flex items-center space-x-2">
             <div class="animate-spin h-4 w-4 border-2 border-teal-600 border-t-transparent rounded-full"></div>
             <span class="text-sm text-slate-700">${job.class}</span>
           </div>
           <span class="text-xs text-slate-500">
             ${this.formatDuration(job.started_at)}
           </span>
         </div>
       `).join('')
     }
     
     renderFailedJobs(jobs) {
       this.failedJobsTarget.innerHTML = jobs.map(job => `
         <div class="flex items-center justify-between p-2 bg-rose-50 rounded-lg">
           <div>
             <div class="text-sm text-rose-700">${job.class}</div>
             <div class="text-xs text-rose-500">${job.error}</div>
           </div>
           <button data-job-id="${job.id}"
                   data-action="click->queue-monitor#retryJob"
                   class="px-2 py-1 bg-rose-600 text-white rounded text-xs hover:bg-rose-700">
             Reintentar
           </button>
         </div>
       `).join('')
     }
     
     async pause() {
       try {
         await fetch('/api/queue/pause', { method: 'POST' })
         
         this.pauseButtonTarget.classList.add('hidden')
         this.resumeButtonTarget.classList.remove('hidden')
         
         this.showNotification('Cola pausada', 'info')
       } catch (error) {
         this.showNotification('Error al pausar la cola', 'error')
       }
     }
     
     async resume() {
       try {
         await fetch('/api/queue/resume', { method: 'POST' })
         
         this.resumeButtonTarget.classList.add('hidden')
         this.pauseButtonTarget.classList.remove('hidden')
         
         this.showNotification('Cola reanudada', 'success')
       } catch (error) {
         this.showNotification('Error al reanudar la cola', 'error')
       }
     }
     
     async retryJob(event) {
       const jobId = event.currentTarget.dataset.jobId
       
       try {
         await fetch(`/api/queue/jobs/${jobId}/retry`, { method: 'POST' })
         
         this.showNotification('Trabajo reencolado', 'success')
         this.refresh()
       } catch (error) {
         this.showNotification('Error al reintentar el trabajo', 'error')
       }
     }
   }
   ```

4. **Queue Control API:**
   ```ruby
   # app/controllers/api/queue_controller.rb
   class Api::QueueController < ApplicationController
     before_action :authenticate_admin!
     
     def status
       render json: QueueMonitor.new.queue_status
     end
     
     def pause
       SolidQueue::Worker.pause_all
       broadcast_queue_status_change('paused')
       
       render json: { status: 'paused' }
     end
     
     def resume
       SolidQueue::Worker.resume_all
       broadcast_queue_status_change('resumed')
       
       render json: { status: 'resumed' }
     end
     
     def retry_job
       job = SolidQueue::Job.find(params[:id])
       
       # Re-enqueue the job
       job.retry!
       
       render json: { status: 'retried', job_id: job.id }
     rescue => e
       render json: { error: e.message }, status: :unprocessable_entity
     end
     
     private
     
     def broadcast_queue_status_change(status)
       ActionCable.server.broadcast(
         'queue_status',
         { type: 'status_change', status: status }
       )
     end
   end
   ```

5. **Testing:**
   ```ruby
   RSpec.describe QueueMonitor do
     it "calculates queue depth correctly" do
       create_list(:solid_queue_job, 5, :pending)
       create_list(:solid_queue_job, 2, :processing)
       
       status = monitor.queue_status
       
       expect(status[:queue_depth]).to eq(5)
       expect(status[:processing].size).to eq(2)
     end
     
     it "estimates completion time based on processing rate" do
       # Create completed jobs in last hour
       10.times do |i|
         create(:solid_queue_job, 
           finished_at: i.minutes.ago,
           created_at: (i + 5).minutes.ago
         )
       end
       
       # Create pending jobs
       create_list(:solid_queue_job, 20, :pending)
       
       status = monitor.queue_status
       
       expect(status[:estimated_completion]).to be_within(5.minutes).of(30.minutes.from_now)
     end
   end
   ```

6. **Performance Considerations:**
   - Cache queue status for 5 seconds
   - Use database views for aggregated counts
   - Limit active jobs display to 10 most recent
   - Background job for heavy calculations

---

## Epic 2: Enhanced Metric Cards with Progressive Disclosure

**Epic ID:** EXP-EPIC-002  
**Priority:** Medium  
**Status:** Not Started  
**Estimated Duration:** 3 weeks  
**Epic Owner:** TBD  

### Epic Description
Transform static metric cards into interactive, contextual displays with visual hierarchy, tooltips showing trends, budget indicators, and clickable navigation to filtered views.

### Business Value
- Improves information scent by 60% through visual hierarchy
- Reduces time to insight with contextual information
- Increases engagement with financial data
- Supports data-driven financial decisions

### Success Metrics
- Hover interaction rate > 40%
- Click-through rate to detailed views > 25%
- Page load time impact < 50ms
- User satisfaction score increase > 20%

---

## Task 2.1: Data Aggregation Service Layer

**Task ID:** EXP-2.1  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 10  

### Description
Create a service layer for efficient calculation and caching of metric data, including trends, comparisons, and projections.

### Acceptance Criteria
- [ ] MetricsCalculator service class implemented
- [ ] Calculations cached with 1-hour expiration
- [ ] Support for multiple time periods (day, week, month, year)
- [ ] Trend calculation (% change vs previous period)
- [ ] Category-wise breakdowns calculated
- [ ] Performance: Calculations complete in < 100ms

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 2.2: Primary Metric Visual Enhancement

**Task ID:** EXP-2.2  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 6  

### Description
Implement 1.5x sizing for the primary "Total de Gastos" metric card with enhanced visual design to establish clear hierarchy.

### Acceptance Criteria
- [ ] Primary card 1.5x size of secondary cards
- [ ] Responsive grid layout maintains proportions
- [ ] Typography scaled appropriately (larger font)
- [ ] Visual weight through color/shadow enhanced
- [ ] Animation on value changes
- [ ] Mobile responsive design maintained

### Designs
```
┌─────────────────────────────────────────┐
│         TOTAL DE GASTOS                 │
│         ₡ 1,250,000                     │
│         ↑ 12% vs mes anterior           │
│         ▂▃▅▇█▇▅ (mini sparkline)       │
└─────────────────────────────────────────┘

┌──────────────┬──────────────┬──────────┐
│ Este Mes     │ Semana       │ Hoy      │
│ ₡ 425,000    │ ₡ 98,000     │ ₡ 12,500 │
└──────────────┴──────────────┴──────────┘
```

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 2.3: Interactive Tooltips with Sparklines

**Task ID:** EXP-2.3  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 12  

### Description
Implement hover tooltips displaying 7-day trend sparklines and additional context for each metric card.

### Acceptance Criteria
- [ ] Tooltip appears on hover after 200ms delay
- [ ] Sparkline shows 7-day trend
- [ ] Min/max values indicated on sparkline
- [ ] Average line displayed
- [ ] Smooth fade in/out animation
- [ ] Touch-friendly alternative for mobile
- [ ] Chart renders in < 50ms

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Subtask 2.3.1: Chart Library Integration

**Task ID:** EXP-2.3.1  
**Parent Task:** EXP-2.3  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 4  

### Description
Integrate Chart.js or similar lightweight charting library for rendering sparklines and other data visualizations.

### Acceptance Criteria
- [ ] Chart library added to project dependencies
- [ ] Bundle size increase < 50KB
- [ ] Library loaded asynchronously
- [ ] Fallback for chart loading failure
- [ ] Configuration for consistent styling
- [ ] Documentation for chart usage

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Subtask 2.3.2: Sparkline Component Development

**Task ID:** EXP-2.3.2  
**Parent Task:** EXP-2.3  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 4  

### Description
Create reusable Stimulus controller for rendering sparkline charts within tooltips with configurable options.

### Acceptance Criteria
- [ ] Stimulus controller accepts data array
- [ ] Configurable colors and styling
- [ ] Responsive sizing
- [ ] Smooth line interpolation
- [ ] Points for min/max values
- [ ] Error handling for invalid data

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Subtask 2.3.3: Tooltip Interaction Handler

**Task ID:** EXP-2.3.3  
**Parent Task:** EXP-2.3  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 4  

### Description
Implement tooltip display logic with proper positioning, timing, and interaction handling for both desktop and mobile.

### Acceptance Criteria
- [ ] Tooltip positioned to avoid viewport edges
- [ ] 200ms hover delay before showing
- [ ] Immediate hide on mouse leave
- [ ] Touch: tap to show, tap elsewhere to hide
- [ ] Keyboard accessible (focus shows tooltip)
- [ ] Z-index properly managed

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 2.4: Budget and Goal Indicators

**Task ID:** EXP-2.4  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 10  

### Description
Add budget tracking indicators and goal progress visualization to metric cards, showing spending against defined limits.

### Acceptance Criteria
- [ ] Budget progress bar below amount
- [ ] Percentage of budget used displayed
- [ ] Color coding: green (< 70%), yellow (70-90%), red (> 90%)
- [ ] "Set Budget" action if not defined
- [ ] Monthly/weekly/daily budget options
- [ ] Historical budget adherence indicator

### Designs
```
┌─────────────────────────────────────┐
│ Total de Gastos                     │
│ ₡ 1,250,000                        │
│ ████████░░ 78% of ₡1,600,000       │
│ ✓ On track for monthly goal         │
└─────────────────────────────────────┘
```

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 2.5: Clickable Card Navigation

**Task ID:** EXP-2.5  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Low  
**Estimated Hours:** 6  

### Description
Make metric cards clickable to navigate to filtered expense views showing relevant transactions for each metric.

### Acceptance Criteria
- [ ] Cards have hover state indicating clickability
- [ ] Click navigates to expense list with appropriate filters
- [ ] Filter state reflected in URL parameters
- [ ] Smooth scroll to expense list section
- [ ] Back button returns to dashboard
- [ ] Loading state during navigation

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 2.6: Metric Calculation Background Jobs

**Task ID:** EXP-2.6  
**Parent Epic:** EXP-EPIC-002  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 8  

### Description
Implement background jobs for calculating complex metrics and maintaining materialized views for performance.

### Acceptance Criteria
- [ ] Hourly job recalculates all metrics
- [ ] Triggered recalculation on expense changes
- [ ] Materialized view for aggregations
- [ ] Job monitoring and error recovery
- [ ] Performance: Job completes in < 30 seconds
- [ ] Prevents concurrent calculation jobs

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Epic 3: Optimized Expense List with Batch Operations

**Epic ID:** EXP-EPIC-003  
**Priority:** High  
**Status:** Not Started  
**Estimated Duration:** 3 weeks  
**Epic Owner:** TBD  

### Epic Description
Transform the expense list to display more information efficiently with compact view, inline actions, batch operations, and smart filtering for improved productivity.

### Business Value
- Doubles information density for better overview
- Reduces interaction cost by 70% for common tasks
- Enables efficient bulk categorization
- Improves pattern recognition in spending

### Success Metrics
- 10 expenses visible without scrolling
- Batch operation usage > 30% of users
- Filter interaction rate > 50%
- Task completion time reduced by 70%

---

## Task 3.1: Database Optimization for Filtering

**Task ID:** EXP-3.1  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Critical  
**Estimated Hours:** 8  

### Description
Implement database indexes and query optimizations to support fast filtering and sorting of large expense datasets.

### Acceptance Criteria
- [ ] Composite index for common filter combinations
- [ ] Covering indexes to avoid table lookups
- [ ] Query performance < 50ms for 10k records
- [ ] EXPLAIN ANALYZE shows index usage
- [ ] No N+1 queries in expense list
- [ ] Database migrations reversible

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.2: Compact View Mode Toggle

**Task ID:** EXP-3.2  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 6  

### Description
Implement a toggle to switch between standard and compact view modes for the expense list with preference persistence.

### Acceptance Criteria
- [ ] Toggle button in expense list header
- [ ] Compact mode reduces row height by 50%
- [ ] Single-line layout in compact mode
- [ ] View preference saved to localStorage
- [ ] Smooth transition animation between modes
- [ ] Mobile automatically uses compact mode

### Designs
```
Standard View:
┌─────────────────────────────────────┐
│ □ Walmart                           │
│   ₡ 45,000 - Comida                │
│   Jan 15, 2024 - BAC San José      │
└─────────────────────────────────────┘

Compact View:
┌─────────────────────────────────────┐
│ □ Walmart | ₡45,000 | Comida | 1/15│
└─────────────────────────────────────┘
```

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.3: Inline Quick Actions

**Task ID:** EXP-3.3  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 10  

### Description
Add hover-activated inline actions for quick editing of categories and notes without leaving the expense list.

### Acceptance Criteria
- [ ] Action buttons appear on row hover
- [ ] Edit category with dropdown
- [ ] Add/edit note with popover
- [ ] Delete with confirmation
- [ ] Keyboard shortcuts (E=edit, D=delete, N=note)
- [ ] Optimistic updates with rollback on error
- [ ] Touch: long-press shows actions

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.4: Batch Selection System

**Task ID:** EXP-3.4  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 12  

### Description
Implement checkbox-based selection system for performing bulk operations on multiple expenses simultaneously.

### Acceptance Criteria
- [ ] Checkbox for each expense row
- [ ] Select all checkbox in header
- [ ] Shift-click for range selection
- [ ] Selected count display
- [ ] Floating action bar appears with selection
- [ ] Persist selection during pagination
- [ ] Clear selection button

### Designs
```
┌─────────────────────────────────────┐
│ ☑ Select All  (3 selected)         │
├─────────────────────────────────────┤
│ ☑ Expense 1                         │
│ ☑ Expense 2                         │
│ ☑ Expense 3                         │
│ ☐ Expense 4                         │
└─────────────────────────────────────┘
│                                     │
│ [Categorize] [Delete] [Export]      │
└─────────────────────────────────────┘
```

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.5: Bulk Categorization Modal

**Task ID:** EXP-3.5  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 8  

### Description
Create modal interface for applying categories to multiple selected expenses with conflict resolution options.

### Acceptance Criteria
- [ ] Modal shows selected expense count
- [ ] Category dropdown with search
- [ ] Preview of changes before applying
- [ ] Option to skip already categorized
- [ ] Progress indicator for bulk update
- [ ] Undo capability after completion
- [ ] Success/error summary

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.6: Inline Filter Chips

**Task ID:** EXP-3.6  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Medium  
**Estimated Hours:** 8  

### Description
Add interactive filter chips above the expense list for quick filtering by category, bank, and date ranges.

### Acceptance Criteria
- [ ] Chips for top 5 categories
- [ ] Chips for all active banks
- [ ] Date range quick filters (today, week, month)
- [ ] Active chip highlighting
- [ ] Multiple chip selection (AND logic)
- [ ] Clear all filters button
- [ ] Filter count badge

### Designs
```
┌─────────────────────────────────────┐
│ Filters:                            │
│ [All] [Comida] [Transporte] [Casa] │
│ [BAC] [Scotia] [This Month] [Clear]│
└─────────────────────────────────────┘
```

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.7: Virtual Scrolling Implementation

**Task ID:** EXP-3.7  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Low  
**Estimated Hours:** 10  

### Description
Implement virtual scrolling for efficiently displaying large expense lists (1000+ items) without performance degradation.

### Acceptance Criteria
- [ ] Smooth scrolling with 1000+ items
- [ ] Maintains 60fps scrolling performance
- [ ] Correct scroll position preservation
- [ ] Search/filter works with virtual list
- [ ] Selection state maintained
- [ ] Fallback for browsers without support

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.8: Filter State Persistence

**Task ID:** EXP-3.8  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** Low  
**Estimated Hours:** 6  

### Description
Implement URL-based filter state persistence to maintain filters across navigation and enable sharing of filtered views.

### Acceptance Criteria
- [ ] Filters reflected in URL parameters
- [ ] Browser back/forward navigation works
- [ ] Bookmarkable filtered views
- [ ] Share button copies filtered URL
- [ ] Load filters from URL on page load
- [ ] Clear filters updates URL

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Task 3.9: Accessibility for Inline Actions

**Task ID:** EXP-3.9  
**Parent Epic:** EXP-EPIC-003  
**Type:** Development  
**Priority:** High  
**Estimated Hours:** 8  

### Description
Ensure all inline actions and batch operations are fully accessible via keyboard and screen readers.

### Acceptance Criteria
- [ ] All actions keyboard accessible
- [ ] Proper ARIA labels and roles
- [ ] Screen reader announcements for state changes
- [ ] Focus management for modals
- [ ] Skip links for repetitive content
- [ ] High contrast mode support
- [ ] WCAG 2.1 AA compliance

### Technical Notes

#### Data Aggregation Service Implementation:

1. **MetricsCalculator Service:**
   ```ruby
   # app/services/metrics_calculator.rb
   class MetricsCalculator
     include ActionView::Helpers::NumberHelper
     
     CACHE_EXPIRATION = 1.hour
     TIME_PERIODS = {
       day: 1.day,
       week: 1.week,
       month: 1.month,
       year: 1.year
     }.freeze
     
     def initialize(user_id = nil)
       @user_id = user_id
     end
     
     def calculate_metrics(period = :month)
       Rails.cache.fetch(cache_key(period), expires_in: CACHE_EXPIRATION) do
         {
           total_expenses: calculate_total(period),
           period_comparison: calculate_comparison(period),
           category_breakdown: calculate_categories(period),
           daily_average: calculate_daily_average(period),
           trend_data: calculate_trend(period),
           projections: calculate_projections(period)
         }
       end
     end
     
     private
     
     def calculate_total(period)
       scope = base_scope(period)
       
       {
         amount: scope.sum(:amount),
         count: scope.count,
         period: period,
         formatted: format_currency(scope.sum(:amount))
       }
     end
     
     def calculate_comparison(period)
       current = base_scope(period).sum(:amount)
       previous = base_scope(period, offset: 1).sum(:amount)
       
       return { change: 0, percentage: 0, trend: 'stable' } if previous.zero?
       
       change = current - previous
       percentage = ((change / previous) * 100).round(2)
       
       {
         current: current,
         previous: previous,
         change: change,
         percentage: percentage,
         trend: percentage > 0 ? 'up' : 'down',
         formatted_change: format_currency(change.abs)
       }
     end
     
     def calculate_categories(period)
       scope = base_scope(period)
       
       categories = scope
         .joins(:category)
         .group('categories.name')
         .sum(:amount)
         .sort_by { |_, amount| -amount }
         .first(5)
       
       total = categories.sum { |_, amount| amount }
       
       categories.map do |name, amount|
         {
           name: name,
           amount: amount,
           percentage: total > 0 ? (amount / total * 100).round(1) : 0,
           formatted: format_currency(amount)
         }
       end
     end
     
     def calculate_trend(period)
       # Get daily totals for sparkline
       days = period == :week ? 7 : 30
       
       (0...days).map do |i|
         date = i.days.ago.to_date
         amount = Expense
           .where(user_id: @user_id)
           .where(date: date)
           .sum(:amount)
         
         { date: date, amount: amount }
       end.reverse
     end
     
     def base_scope(period, offset: 0)
       time_range = period_range(period, offset)
       
       Expense.where(user_id: @user_id)
              .where(date: time_range)
     end
     
     def period_range(period, offset = 0)
       duration = TIME_PERIODS[period]
       start_date = (duration * (offset + 1)).ago
       end_date = offset.zero? ? Time.current : (duration * offset).ago
       
       start_date..end_date
     end
     
     def cache_key(period)
       "metrics:#{@user_id}:#{period}:#{Date.current}"
     end
   end
   ```

2. **Background Job for Calculations:**
   ```ruby
   # app/jobs/metrics_calculation_job.rb
   class MetricsCalculationJob < ApplicationJob
     queue_as :low_priority
     
     def perform(user_id)
       calculator = MetricsCalculator.new(user_id)
       
       # Pre-calculate for all periods
       %i[day week month year].each do |period|
         calculator.calculate_metrics(period)
       end
       
       # Broadcast updated metrics
       broadcast_metrics_update(user_id)
     end
     
     private
     
     def broadcast_metrics_update(user_id)
       ActionCable.server.broadcast(
         "metrics_#{user_id}",
         { type: 'metrics_updated', timestamp: Time.current }
       )
     end
   end
   ```

3. **Database Optimization:**
   ```ruby
   # db/migrate/add_metrics_indexes.rb
   class AddMetricsIndexes < ActiveRecord::Migration[7.0]
     def change
       # Composite index for date range queries
       add_index :expenses, [:user_id, :date, :amount]
       
       # Index for category aggregations
       add_index :expenses, [:user_id, :category_id, :date]
       
       # Partial index for recent expenses
       add_index :expenses, [:user_id, :date],
                 where: "date > CURRENT_DATE - INTERVAL '90 days'",
                 name: 'index_recent_expenses'
     end
   end
   ```

4. **Caching Strategy:**
   ```ruby
   # config/initializers/cache_store.rb
   Rails.application.configure do
     config.cache_store = :redis_cache_store, {
       url: ENV['REDIS_URL'],
       expires_in: 1.hour,
       namespace: 'metrics',
       pool_size: 5,
       pool_timeout: 5
     }
   end
   ```

5. **Performance Monitoring:**
   ```ruby
   # app/services/metrics_performance_monitor.rb
   class MetricsPerformanceMonitor
     include ActiveSupport::Benchmarkable
     
     def measure_calculation_time
       benchmark "Metrics Calculation" do
         MetricsCalculator.new.calculate_metrics(:month)
       end
     end
     
     def ensure_performance_target
       time = Benchmark.measure do
         calculate_metrics
       end
       
       if time.real > 0.1 # 100ms threshold
         Rails.logger.warn "Metrics calculation exceeded 100ms: #{time.real}s"
         notify_performance_issue(time.real)
       end
     end
   end
   ```

6. **Testing:**
   ```ruby
   RSpec.describe MetricsCalculator do
     it "calculates metrics within 100ms" do
       create_list(:expense, 1000, user_id: user.id)
       
       time = Benchmark.realtime do
         calculator.calculate_metrics(:month)
       end
       
       expect(time).to be < 0.1
     end
     
     it "caches calculations for 1 hour" do
       expect(Rails.cache).to receive(:fetch)
         .with(/metrics:/, expires_in: 1.hour)
       
       calculator.calculate_metrics(:month)
     end
   end
   ```

---

## Cross-Cutting Concerns

### Performance Requirements
- Page load time < 200ms (P95)
- Real-time update latency < 100ms
- Filter response time < 150ms
- Batch operations < 2s for 100 items
- Memory usage stable over 24 hours

### Testing Strategy
- Unit tests: 90% coverage minimum
- Integration tests for all user workflows
- Performance tests with 10k+ records
- Accessibility audit with axe-core
- Cross-browser testing (Chrome, Firefox, Safari, Edge)
- Mobile testing (iOS Safari, Chrome Android)

### Security Considerations
- CSRF protection for all actions
- Rate limiting on API endpoints
- Input sanitization for filters
- SQL injection prevention
- XSS protection in user content
- Audit logging for bulk operations

### Monitoring & Analytics
- Track feature adoption rates
- Monitor performance metrics
- Error tracking with Sentry/Rollbar
- User behavior analytics
- A/B testing framework ready
- Custom events for key interactions

---

## Implementation Timeline

### Sprint 1 (Weeks 1-2): Foundation
- Complete ActionCable implementation
- Database optimizations
- Performance monitoring setup

### Sprint 2 (Weeks 3-4): Core Features
- Compact view mode
- Inline quick actions
- Basic filtering

### Sprint 3 (Weeks 5-6): Batch Operations
- Selection system
- Bulk categorization
- Filter chips

### Sprint 4 (Weeks 7-8): Enhancements
- Metric cards visual hierarchy
- Interactive tooltips
- Budget indicators

### Sprint 5 (Weeks 9-10): Polish & Launch
- Accessibility improvements
- Performance optimization
- Bug fixes and testing
- Gradual rollout

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| ActionCable scalability | Medium | High | Connection pooling, rate limiting |
| Complex filters slow queries | High | Medium | Indexes, query optimization |
| Browser compatibility | Low | Medium | Progressive enhancement |
| Data inconsistency in batch ops | Medium | High | Transactions, audit logs |
| User overwhelm with features | Medium | Low | Progressive disclosure, tutorials |

---

## Definition of Done

### For Each Task:
- [ ] Code reviewed by peer
- [ ] Unit tests written and passing
- [ ] Integration tests passing
- [ ] Documentation updated
- [ ] No console errors
- [ ] Performance benchmarks met
- [ ] Accessibility checked
- [ ] Works on mobile
- [ ] Translation keys added
- [ ] Deployed to staging

### For Each Epic:
- [ ] All tasks completed
- [ ] End-to-end tests passing
- [ ] User acceptance testing passed
- [ ] Performance testing passed
- [ ] Security review completed
- [ ] Documentation complete
- [ ] Training materials created
- [ ] Rollback plan defined
- [ ] Metrics tracking enabled
- [ ] Deployed to production

---

## Appendix

### Technology Stack
- Rails 8.0.2
- PostgreSQL
- Redis (for ActionCable)
- Turbo & Stimulus (Hotwire)
- Tailwind CSS
- Chart.js (for visualizations)
- Solid Queue (background jobs)

### Color Palette (Financial Confidence)
- Primary: teal-700 (#0F766E)
- Secondary: amber-600 (#D97706)
- Accent: rose-400 (#FB7185)
- Success: emerald-500
- Warning: amber-600
- Error: rose-600

### Related Documents
- [Original UX Analysis](./ux_analysis.md)
- [Technical Architecture](./tech_architecture.md)
- [API Documentation](./api_docs.md)

---

## Complete HTML/ERB Implementations

### Epic 1: Unified Sync Status Widget
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

### Epic 2: Enhanced Metric Cards with Progressive Disclosure
**File Path:** `app/views/expenses/_enhanced_metrics.html.erb`

```erb
<!-- Enhanced Metric Cards with Progressive Disclosure -->
<div class="grid grid-cols-1 lg:grid-cols-3 gap-6" 
     data-controller="metrics-cards"
     data-metrics-cards-refresh-interval-value="60000">
  
  <!-- Primary Metric Card (1.5x size) -->
  <div class="lg:col-span-2 group relative">
    <%= turbo_frame_tag "primary_metric", class: "block" do %>
      <div class="bg-gradient-to-br from-teal-700 to-teal-800 rounded-xl shadow-lg hover:shadow-2xl transition-all duration-300 transform hover:-translate-y-1 p-8 text-white overflow-hidden"
           data-metrics-cards-target="primaryCard"
           data-action="mouseenter->metrics-cards#showTooltip mouseleave->metrics-cards#hideTooltip click->metrics-cards#navigateToDetails">
        
        <!-- Background Pattern -->
        <div class="absolute inset-0 opacity-10">
          <svg class="w-full h-full" viewBox="0 0 100 100" preserveAspectRatio="none">
            <pattern id="grid" width="10" height="10" patternUnits="userSpaceOnUse">
              <circle cx="5" cy="5" r="1" fill="currentColor"/>
            </pattern>
            <rect width="100" height="100" fill="url(#grid)"/>
          </svg>
        </div>
        
        <!-- Content Container -->
        <div class="relative z-10">
          <!-- Header with Icon -->
          <div class="flex items-start justify-between mb-6">
            <div class="flex items-center space-x-3">
              <div class="w-14 h-14 bg-white/20 backdrop-blur rounded-full flex items-center justify-center">
                <svg class="w-8 h-8" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1.41 16.09V20h-2.67v-1.93c-1.71-.36-3.16-1.46-3.27-3.4h1.96c.1.81.45 1.61 1.67 1.61 1.16 0 1.6-.64 1.6-1.46 0-.84-.36-1.31-1.75-1.7-1.98-.53-3.37-1.34-3.37-3.21 0-1.51 1.22-2.65 2.79-3v-1.9h2.67v1.91c1.51.32 2.83 1.31 2.96 3.16h-1.96c-.09-.72-.38-1.42-1.42-1.42-1.04 0-1.52.51-1.52 1.25 0 .77.39 1.08 1.73 1.46 2.17.65 3.39 1.41 3.39 3.37 0 1.65-1.21 2.83-2.81 3.35z"/>
                </svg>
              </div>
              <div>
                <h3 class="text-sm font-medium text-teal-100 uppercase tracking-wider">Total de Gastos</h3>
                <p class="text-xs text-teal-200 mt-1">Todos los tiempos</p>
              </div>
            </div>
            
            <!-- Live Indicator -->
            <div class="flex items-center space-x-2">
              <span class="flex h-2 w-2">
                <span class="animate-ping absolute inline-flex h-2 w-2 rounded-full bg-white opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2 w-2 bg-white"></span>
              </span>
              <span class="text-xs text-teal-100">En vivo</span>
            </div>
          </div>
          
          <!-- Main Amount with Animation -->
          <div class="mb-6">
            <div class="flex items-baseline space-x-2">
              <span class="text-5xl lg:text-6xl font-bold tracking-tight" 
                    data-metrics-cards-target="primaryAmount"
                    data-countup="<%= @total_expenses.to_i %>">
                ₡<%= number_with_delimiter(@total_expenses.to_i) %>
              </span>
            </div>
            
            <!-- Change Indicator -->
            <div class="flex items-center space-x-4 mt-4">
              <% 
                change = @current_month_total - @last_month_total
                percentage = @last_month_total > 0 ? ((change / @last_month_total) * 100) : 0
                is_increase = change > 0
              %>
              <div class="flex items-center space-x-2">
                <div class="w-8 h-8 <%= is_increase ? 'bg-rose-500/20' : 'bg-emerald-500/20' %> backdrop-blur rounded-full flex items-center justify-center">
                  <svg class="w-4 h-4 <%= is_increase ? 'text-rose-300' : 'text-emerald-300' %>" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                          d="<%= is_increase ? 'M13 7h8m0 0v8m0-8l-8 8-4-4-6 6' : 'M13 17h8m0 0V9m0 8l-8-8-4 4-6-6' %>">
                    </path>
                  </svg>
                </div>
                <div>
                  <p class="text-2xl font-semibold <%= is_increase ? 'text-rose-300' : 'text-emerald-300' %>">
                    <%= is_increase ? '+' : '' %><%= percentage.round(1) %>%
                  </p>
                  <p class="text-xs text-teal-100 mt-0.5">vs mes anterior</p>
                </div>
              </div>
              
              <!-- Mini Sparkline Container -->
              <div class="flex-1 max-w-xs">
                <div class="h-12" data-metrics-cards-target="primarySparkline">
                  <!-- Sparkline will be rendered here via JavaScript -->
                  <svg viewBox="0 0 100 40" class="w-full h-full" preserveAspectRatio="none">
                    <polyline
                      fill="none"
                      stroke="rgba(255,255,255,0.3)"
                      stroke-width="2"
                      points="<%= @monthly_data.map.with_index { |(_month, value), i| "#{i * 10},#{40 - (value.to_f / @monthly_data.values.max * 35)}" }.join(' ') %>"
                    />
                  </svg>
                </div>
              </div>
            </div>
          </div>
          
          <!-- Quick Stats Bar -->
          <div class="grid grid-cols-3 gap-4 pt-6 border-t border-teal-600/30">
            <div>
              <p class="text-xs text-teal-200 mb-1">Promedio diario</p>
              <p class="text-lg font-semibold">₡<%= number_with_delimiter((@current_month_total / Date.current.day).to_i) %></p>
            </div>
            <div>
              <p class="text-xs text-teal-200 mb-1">Mayor gasto</p>
              <p class="text-lg font-semibold">₡<%= number_with_delimiter(@recent_expenses.maximum(:amount).to_i) %></p>
            </div>
            <div>
              <p class="text-xs text-teal-200 mb-1">Transacciones</p>
              <p class="text-lg font-semibold"><%= number_with_delimiter(@expense_count) %></p>
            </div>
          </div>
        </div>
        
        <!-- Hover Tooltip -->
        <div class="absolute top-full left-1/2 transform -translate-x-1/2 mt-2 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 z-50 pointer-events-none"
             data-metrics-cards-target="primaryTooltip">
          <div class="bg-slate-900 text-white rounded-lg shadow-xl p-4 min-w-[250px]">
            <div class="absolute -top-2 left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-8 border-l-transparent border-r-8 border-r-transparent border-b-8 border-b-slate-900"></div>
            <p class="text-xs text-slate-400 mb-2">Desglose del mes actual</p>
            <div class="space-y-1">
              <% @sorted_categories.first(3).each do |category, amount| %>
                <div class="flex justify-between text-sm">
                  <span><%= category %></span>
                  <span class="font-medium">₡<%= number_with_delimiter(amount.to_i) %></span>
                </div>
              <% end %>
            </div>
            <div class="mt-3 pt-3 border-t border-slate-700">
              <p class="text-xs text-slate-400">Click para ver detalles completos</p>
            </div>
          </div>
        </div>
      </div>
    <% end %>
  </div>
  
  <!-- Secondary Metrics Grid -->
  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-1 gap-4">
    
    <!-- This Month Card -->
    <div class="group relative">
      <%= turbo_frame_tag "metric_month", class: "block" do %>
        <div class="bg-white rounded-xl shadow-sm border border-slate-200 hover:shadow-lg hover:border-teal-300 transition-all duration-300 p-6 cursor-pointer"
             data-metrics-cards-target="secondaryCard"
             data-metric-type="month"
             data-action="click->metrics-cards#filterByPeriod">
          
          <div class="flex items-start justify-between mb-4">
            <div class="p-2 bg-amber-100 rounded-lg">
              <svg class="w-6 h-6 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
              </svg>
            </div>
            <% if @current_month_total > @last_month_total %>
              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-rose-100 text-rose-800">
                <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z" clip-rule="evenodd"></path>
                </svg>
                Mayor
              </span>
            <% else %>
              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-emerald-100 text-emerald-800">
                <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z" clip-rule="evenodd"></path>
                </svg>
                Menor
              </span>
            <% end %>
          </div>
          
          <div>
            <p class="text-sm font-medium text-slate-600 mb-1">Este Mes</p>
            <p class="text-2xl font-bold text-slate-900" data-metrics-cards-target="monthAmount">
              ₡<%= number_with_delimiter(@current_month_total.to_i) %>
            </p>
            <p class="text-xs text-slate-500 mt-2">
              <%= Date.current.strftime("%B %Y") %>
            </p>
          </div>
          
          <!-- Hover Action -->
          <div class="mt-4 pt-4 border-t border-slate-200 opacity-0 group-hover:opacity-100 transition-opacity">
            <p class="text-xs text-teal-600 font-medium flex items-center">
              Ver gastos del mes
              <svg class="w-3 h-3 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
              </svg>
            </p>
          </div>
        </div>
      <% end %>
    </div>
    
    <!-- This Week Card -->
    <div class="group relative">
      <%= turbo_frame_tag "metric_week", class: "block" do %>
        <div class="bg-white rounded-xl shadow-sm border border-slate-200 hover:shadow-lg hover:border-teal-300 transition-all duration-300 p-6 cursor-pointer"
             data-metrics-cards-target="secondaryCard"
             data-metric-type="week"
             data-action="click->metrics-cards#filterByPeriod">
          
          <div class="flex items-start justify-between mb-4">
            <div class="p-2 bg-emerald-100 rounded-lg">
              <svg class="w-6 h-6 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 11h.01M12 11h.01M9 11h.01M7 21h10a2 2 0 002-2V5a2 2 0 00-2-2H7a2 2 0 00-2 2v14a2 2 0 002 2z"></path>
              </svg>
            </div>
          </div>
          
          <div>
            <p class="text-sm font-medium text-slate-600 mb-1">Esta Semana</p>
            <p class="text-2xl font-bold text-slate-900" data-metrics-cards-target="weekAmount">
              ₡<%= number_with_delimiter(@current_week_total.to_i) %>
            </p>
            <p class="text-xs text-slate-500 mt-2">
              <%= @expense_count_week %> transacciones
            </p>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### Epic 3: Optimized Expense List with Batch Operations
**File Path:** `app/views/expenses/_optimized_list.html.erb`

```erb
<!-- Optimized Expense List with Batch Operations -->
<div class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden"
     data-controller="expense-list"
     data-expense-list-view-mode-value="<%= @view_mode || 'standard' %>">
  
  <!-- Header with View Toggle and Filter Chips -->
  <div class="px-6 py-4 border-b border-slate-200 bg-gradient-to-r from-slate-50 to-white">
    <div class="flex items-center justify-between mb-4">
      <div class="flex items-center space-x-4">
        <h2 class="text-lg font-semibold text-slate-900">Gastos Recientes</h2>
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-teal-100 text-teal-800">
          <%= @expenses.count %> registros
        </span>
      </div>
      
      <!-- View Mode Toggle -->
      <div class="flex items-center space-x-2">
        <span class="text-sm text-slate-600">Vista:</span>
        <div class="inline-flex rounded-lg shadow-sm" role="group">
          <button type="button"
                  data-action="click->expense-list#setCompactView"
                  class="px-3 py-1.5 text-sm font-medium rounded-l-lg border <%= @view_mode == 'compact' ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-slate-700 border-slate-300 hover:bg-slate-50' %>"
                  aria-pressed="<%= @view_mode == 'compact' %>">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
            </svg>
          </button>
          <button type="button"
                  data-action="click->expense-list#setStandardView"
                  class="px-3 py-1.5 text-sm font-medium rounded-r-lg border-t border-r border-b <%= @view_mode == 'standard' ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-slate-700 border-slate-300 hover:bg-slate-50' %>"
                  aria-pressed="<%= @view_mode == 'standard' %>">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"></path>
            </svg>
          </button>
        </div>
      </div>
    </div>
    
    <!-- Filter Chips Bar -->
    <div class="flex items-center space-x-2 overflow-x-auto pb-2" data-expense-list-target="filterChips">
      <!-- Active Filters -->
      <% if params[:category].present? %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-teal-100 text-teal-800 whitespace-nowrap">
          <%= Category.find(params[:category]).name %>
          <button type="button" 
                  data-action="click->expense-list#removeFilter"
                  data-filter-type="category"
                  class="ml-1.5 inline-flex items-center justify-center w-4 h-4 text-teal-600 hover:text-teal-800">
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
            </svg>
          </button>
        </span>
      <% end %>
      
      <% if params[:date_range].present? %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-amber-100 text-amber-800 whitespace-nowrap">
          <%= params[:date_range] %>
          <button type="button"
                  data-action="click->expense-list#removeFilter"
                  data-filter-type="date_range"
                  class="ml-1.5 inline-flex items-center justify-center w-4 h-4 text-amber-600 hover:text-amber-800">
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd"></path>
            </svg>
          </button>
        </span>
      <% end %>
      
      <!-- Quick Filter Buttons -->
      <button type="button"
              data-action="click->expense-list#showFilterModal"
              class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-slate-100 text-slate-700 hover:bg-slate-200 whitespace-nowrap transition-colors">
        <svg class="w-3 h-3 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"></path>
        </svg>
        Agregar filtro
      </button>
      
      <% if params.keys.any? { |k| %w[category date_range amount_min amount_max bank].include?(k) } %>
        <button type="button"
                data-action="click->expense-list#clearAllFilters"
                class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium text-rose-600 hover:text-rose-700 whitespace-nowrap">
          Limpiar filtros
        </button>
      <% end %>
    </div>
  </div>
  
  <!-- Batch Selection Bar (Hidden by default) -->
  <div class="hidden px-6 py-3 bg-teal-50 border-b border-teal-200"
       data-expense-list-target="batchBar">
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-3">
        <input type="checkbox"
               data-action="change->expense-list#toggleSelectAll"
               data-expense-list-target="selectAllCheckbox"
               class="rounded border-slate-300 text-teal-600 focus:ring-teal-500">
        <span class="text-sm font-medium text-slate-700">
          <span data-expense-list-target="selectedCount">0</span> seleccionados
        </span>
      </div>
      
      <!-- Batch Actions -->
      <div class="flex items-center space-x-2">
        <button type="button"
                data-action="click->expense-list#batchCategorize"
                class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-teal-700 bg-white border border-teal-300 rounded-lg hover:bg-teal-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500">
          <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z"></path>
          </svg>
          Categorizar
        </button>
        
        <button type="button"
                data-action="click->expense-list#batchExport"
                class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-slate-700 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-slate-500">
          <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
          </svg>
          Exportar
        </button>
        
        <button type="button"
                data-action="click->expense-list#batchDelete"
                class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-white bg-rose-600 rounded-lg hover:bg-rose-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-rose-500">
          <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
          </svg>
          Eliminar
        </button>
      </div>
    </div>
  </div>
  
  <!-- Expense List -->
  <div class="divide-y divide-slate-200" data-expense-list-target="listContainer">
    <% @expenses.each_with_index do |expense, index| %>
      <div class="group hover:bg-slate-50 transition-colors <%= @view_mode == 'compact' ? 'px-6 py-2' : 'px-6 py-4' %>"
           data-expense-id="<%= expense.id %>"
           data-expense-list-target="expenseRow">
        
        <div class="flex items-center">
          <!-- Checkbox -->
          <div class="flex-shrink-0 mr-4">
            <input type="checkbox"
                   data-action="change->expense-list#toggleSelection"
                   data-expense-id="<%= expense.id %>"
                   class="rounded border-slate-300 text-teal-600 focus:ring-teal-500 opacity-0 group-hover:opacity-100 transition-opacity">
          </div>
          
          <!-- Main Content -->
          <div class="flex-1 min-w-0">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="flex items-center space-x-3">
                  <!-- Category Icon -->
                  <div class="flex-shrink-0">
                    <% if expense.category %>
                      <div class="w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-bold"
                           style="background-color: <%= expense.category.color %>;">
                        <%= expense.category.icon || expense.category.name.first %>
                      </div>
                    <% else %>
                      <div class="w-8 h-8 rounded-full bg-slate-300 flex items-center justify-center text-white text-xs font-bold">
                        ?
                      </div>
                    <% end %>
                  </div>
                  
                  <!-- Expense Details -->
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-slate-900 truncate">
                      <%= expense.merchant_name %>
                    </p>
                    <div class="flex items-center space-x-2 text-xs text-slate-500">
                      <span><%= expense.transaction_date.strftime("%d/%m/%Y") %></span>
                      <span>•</span>
                      <span><%= expense.category&.name || "Sin categoría" %></span>
                      <span>•</span>
                      <span><%= expense.bank_name %></span>
                    </div>
                  </div>
                </div>
              </div>
              
              <!-- Amount and Actions -->
              <div class="flex items-center space-x-4 ml-4">
                <div class="text-right">
                  <p class="text-sm font-semibold text-slate-900">
                    <%= currency_symbol(expense) %><%= number_with_delimiter(expense.amount.to_i) %>
                  </p>
                  <% if @view_mode == 'standard' %>
                    <p class="text-xs text-slate-500">
                      <%= expense.payment_method %>
                    </p>
                  <% end %>
                </div>
                
                <!-- Inline Actions (Show on hover) -->
                <div class="flex items-center space-x-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <%= link_to edit_expense_path(expense),
                      class: "p-1.5 text-slate-400 hover:text-teal-600 hover:bg-teal-50 rounded transition-colors",
                      title: "Editar" do %>
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
                    </svg>
                  <% end %>
                  
                  <button type="button"
                          data-action="click->expense-list#duplicateExpense"
                          data-expense-id="<%= expense.id %>"
                          class="p-1.5 text-slate-400 hover:text-amber-600 hover:bg-amber-50 rounded transition-colors"
                          title="Duplicar">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
                    </svg>
                  </button>
                  
                  <%= link_to expense_path(expense),
                      method: :delete,
                      data: { confirm: "¿Estás seguro?" },
                      class: "p-1.5 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded transition-colors",
                      title: "Eliminar" do %>
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                    </svg>
                  <% end %>
                </div>
              </div>
            </div>
            
            <!-- Expandable Details (Standard View Only) -->
            <% if @view_mode == 'standard' && expense.notes.present? %>
              <div class="mt-2 text-sm text-slate-600">
                <p class="line-clamp-2"><%= expense.notes %></p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
  </div>
  
  <!-- Pagination -->
  <div class="px-6 py-4 bg-slate-50 border-t border-slate-200">
    <div class="flex items-center justify-between">
      <div class="text-sm text-slate-700">
        Mostrando <span class="font-medium"><%= @expenses.offset_value + 1 %></span> a 
        <span class="font-medium"><%= [@expenses.offset_value + @expenses.limit_value, @expenses.total_count].min %></span> de 
        <span class="font-medium"><%= @expenses.total_count %></span> resultados
      </div>
      
      <div class="flex items-center space-x-2">
        <%= paginate @expenses, theme: 'tailwind' %>
      </div>
    </div>
  </div>
  
  <!-- Floating Batch Operations Toolbar -->
  <div class="hidden fixed bottom-6 left-1/2 transform -translate-x-1/2 z-50"
       data-expense-list-target="floatingToolbar">
    <div class="bg-slate-900 text-white rounded-lg shadow-2xl px-6 py-3 flex items-center space-x-4">
      <span class="text-sm font-medium">
        <span data-expense-list-target="floatingSelectedCount">0</span> seleccionados
      </span>
      <div class="h-6 w-px bg-slate-700"></div>
      <button type="button"
              data-action="click->expense-list#floatingCategorize"
              class="text-sm hover:text-teal-300 transition-colors">
        Categorizar
      </button>
      <button type="button"
              data-action="click->expense-list#floatingExport"
              class="text-sm hover:text-amber-300 transition-colors">
        Exportar
      </button>
      <button type="button"
              data-action="click->expense-list#floatingDelete"
              class="text-sm hover:text-rose-300 transition-colors">
        Eliminar
      </button>
      <button type="button"
              data-action="click->expense-list#cancelSelection"
              class="ml-4 text-sm text-slate-400 hover:text-white transition-colors">
        Cancelar
      </button>
    </div>
  </div>
</div>
```
- [Testing Strategy](./testing_strategy.md)