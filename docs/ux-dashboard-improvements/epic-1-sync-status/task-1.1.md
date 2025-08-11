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

