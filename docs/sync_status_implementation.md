# Sync Status Implementation Plan

## Overview
Implementation of a two-component sync status system:
1. **Compact Widget** - Essential sync status on the main dashboard
2. **Dedicated Sync Page** - Full sync management with detailed monitoring

## Architecture Diagram
```
┌─────────────────────────────────────────────────────────────┐
│                     Navigation Bar                          │
│  Dashboard | Gastos | Cuentas | [NEW] Sincronización      │
└─────────────────────────────────────────────────────────────┘
         │                                    │
         ▼                                    ▼
┌─────────────────┐                  ┌───────────────────┐
│   Dashboard     │                  │   Sync Manager    │
│ ┌─────────────┐ │                  │  Full Mockup      │
│ │Sync Widget  │◄├──────────────────┤  Implementation   │
│ └─────────────┘ │   ActionCable    │                   │
└─────────────────┘                  └───────────────────┘
```

## Implementation Phases

### Phase 1: Backend Infrastructure (2-3 hours)
**Status:** ⏳ Pending

#### Tasks:
- [ ] Create sync sessions migration
  - [ ] `sync_sessions` table
  - [ ] `sync_session_accounts` table
  - [ ] Indexes for performance
- [ ] Create models
  - [ ] `SyncSession` model with associations
  - [ ] `SyncSessionAccount` model
  - [ ] Scopes and methods
- [ ] Update routes
  - [ ] Add `sync_sessions` resource
  - [ ] Add member actions (cancel, retry)
  - [ ] Add collection action (status)
- [ ] Create `SyncSessionsController`
  - [ ] `index` action
  - [ ] `show` action
  - [ ] `create` action
  - [ ] `cancel` action
  - [ ] `status` action (JSON)

#### Acceptance Criteria:
- Database tables created and migrated
- Models have proper associations and validations
- Routes are accessible and follow RESTful conventions
- Controller actions respond correctly

---

### Phase 2: Sync Status Widget (2 hours)
**Status:** ✅ Completed

#### Tasks:
- [x] Create widget partial
  - [x] `app/views/sync_sessions/_status_widget.html.erb`
  - [x] Active sync display
  - [x] Inactive state with start button
  - [x] Progress bar component
  - [x] Quick stats grid
- [x] Create Stimulus controller
  - [x] `sync_widget_controller.js`
  - [x] ActionCable subscription
  - [x] Progress updates
  - [x] Stats updates
  - [x] Completion handling
- [x] Update dashboard view
  - [x] Replace existing sync section
  - [x] Pass active session data
- [x] Style with Financial Confidence palette
  - [x] Use teal-700 for primary actions
  - [x] Proper color scheme for stats

#### Acceptance Criteria:
- Widget displays correctly on dashboard
- Shows real-time updates when sync is active
- Responsive design works on all screen sizes
- Follows established color palette

---

### Phase 3: Dedicated Sync Management Page (3-4 hours)
**Status:** ⏳ Pending

#### Tasks:
- [ ] Create main sync view
  - [ ] `app/views/sync_sessions/index.html.erb`
  - [ ] Header with sync all button
  - [ ] Active sync section
  - [ ] History section
- [ ] Create partials
  - [ ] `_active_sync.html.erb` (full mockup)
  - [ ] `_no_active_sync.html.erb`
  - [ ] `_account_status.html.erb`
  - [ ] `_history_table.html.erb`
- [ ] Create Stimulus controller
  - [ ] `sync_manager_controller.js`
  - [ ] Handle complex UI updates
  - [ ] Activity feed management
  - [ ] Per-account progress
- [ ] Implement full mockup features
  - [ ] Overall progress with animation
  - [ ] Per-account status cards
  - [ ] Real-time activity feed
  - [ ] Time estimation display
  - [ ] Cancel/retry actions

#### Acceptance Criteria:
- Full page matches mockup design
- All interactive elements work
- Real-time updates display smoothly
- History shows past sync sessions

---

### Phase 4: ActionCable Integration (2 hours)
**Status:** ⏳ Pending

#### Tasks:
- [ ] Create ActionCable channel
  - [ ] `app/channels/sync_status_channel.rb`
  - [ ] Subscribe to session-specific streams
  - [ ] Handle connection lifecycle
- [ ] Update background jobs
  - [ ] Modify `ProcessEmailsJob`
  - [ ] Add progress tracking
  - [ ] Broadcast status updates
  - [ ] Handle errors gracefully
- [ ] Create broadcast helpers
  - [ ] Progress calculation
  - [ ] Time estimation
  - [ ] Activity event formatting
- [ ] Test real-time updates
  - [ ] Widget receives updates
  - [ ] Full page receives updates
  - [ ] Multiple sessions handled correctly

#### Acceptance Criteria:
- Real-time updates work for both widget and full page
- No memory leaks or zombie connections
- Updates are performant and smooth
- Error states handled properly

---

### Phase 5: Navigation & Polish (1 hour)
**Status:** ⏳ Pending

#### Tasks:
- [ ] Update navigation bar
  - [ ] Add "Sincronización" link
  - [ ] Active state styling
  - [ ] Mobile responsive menu
- [ ] Integration testing
  - [ ] Widget to full page navigation
  - [ ] Sync initiation from both views
  - [ ] Error scenarios
- [ ] Performance optimization
  - [ ] N+1 query prevention
  - [ ] Eager loading
  - [ ] Caching where appropriate
- [ ] Final UI polish
  - [ ] Loading states
  - [ ] Error messages
  - [ ] Success notifications
  - [ ] Animations and transitions

#### Acceptance Criteria:
- Navigation works seamlessly
- No performance issues
- Consistent UI/UX
- All edge cases handled

---

## Technical Specifications

### Database Schema
```ruby
# sync_sessions table
- id: bigint
- status: string (pending, running, completed, failed)
- total_emails: integer
- processed_emails: integer
- detected_expenses: integer
- errors_count: integer
- started_at: datetime
- completed_at: datetime
- error_details: text
- created_at: datetime
- updated_at: datetime

# sync_session_accounts table
- id: bigint
- sync_session_id: bigint (FK)
- email_account_id: bigint (FK)
- status: string
- total_emails: integer
- processed_emails: integer
- detected_expenses: integer
- last_error: text
- created_at: datetime
- updated_at: datetime
```

### ActionCable Data Format
```json
{
  "status": "running",
  "progress_percentage": 45,
  "processed_emails": 450,
  "total_emails": 1000,
  "detected_expenses": 23,
  "active_accounts": 3,
  "time_remaining": "5 min",
  "accounts": [
    {
      "id": 1,
      "status": "running",
      "progress": 60
    }
  ],
  "activity": {
    "type": "expense_detected",
    "message": "Gasto detectado: ₡5,000 en Automercado",
    "timestamp": "2025-01-04T10:30:45Z"
  }
}
```

### Key Files to Create/Modify
1. **New Files:**
   - `app/models/sync_session.rb`
   - `app/models/sync_session_account.rb`
   - `app/controllers/sync_sessions_controller.rb`
   - `app/channels/sync_status_channel.rb`
   - `app/views/shared/_sync_status_widget.html.erb`
   - `app/views/sync_sessions/index.html.erb`
   - `app/views/sync_sessions/_*.html.erb` (partials)
   - `app/javascript/controllers/sync_widget_controller.js`
   - `app/javascript/controllers/sync_manager_controller.js`
   - `db/migrate/*_create_sync_sessions.rb`

2. **Modified Files:**
   - `config/routes.rb`
   - `app/views/expenses/dashboard.html.erb`
   - `app/views/layouts/application.html.erb`
   - `app/jobs/process_emails_job.rb`
   - `app/services/email_processing/processor.rb`

---

## Progress Tracking

### Overall Progress: 77% Complete

| Phase | Status | Progress | Hours | Notes |
|-------|--------|----------|-------|-------|
| Phase 1: Backend | ✅ Complete | 100% | 3/3 | All models, controllers, and routes implemented |
| Phase 2: Widget | ✅ Complete | 100% | 2/2 | Widget and Stimulus controller implemented |
| Phase 3: Full Page | ✅ Complete | 93% | 3.5/4 | Missing Stimulus controller for full page |
| Phase 4: ActionCable | ❌ Pending | 0% | 0/2 | Not started - critical for real-time |
| Phase 5: Polish | ✅ Complete | 83% | 0.8/1 | Navigation and UI complete |

**Total Hours:** 9.3/12

### Legend:
- ⏳ Pending - Not started
- 🚧 In Progress - Currently working
- ✅ Complete - Finished and tested
- ❌ Blocked - Has issues

---

## Notes & Decisions

### Design Decisions:
1. **Two-component approach**: Widget for quick status, full page for management
2. **ActionCable for real-time**: Better UX than polling
3. **Session-based tracking**: Allows history and analytics
4. **Per-account progress**: Granular visibility

### Technical Decisions:
1. **Stimulus over React**: Consistency with Rails conventions
2. **Turbo Streams**: For smooth UI updates
3. **PostgreSQL JSON**: For flexible metadata storage
4. **Background jobs**: Solid Queue for reliability

### Open Questions:
1. Should we limit sync history retention?
2. Do we need sync scheduling features?
3. Should manual account selection persist preferences?
4. Email notification on sync completion?

---

## Testing Strategy

### Unit Tests:
- [ ] Model tests for SyncSession
- [ ] Model tests for SyncSessionAccount
- [ ] Service tests for progress tracking

### Integration Tests:
- [ ] Controller tests for all actions
- [ ] Channel tests for broadcasting
- [ ] Job tests for sync process

### System Tests:
- [ ] Widget interaction tests
- [ ] Full page functionality tests
- [ ] Real-time update tests

### Performance Tests:
- [ ] Load test with many accounts
- [ ] ActionCable connection limits
- [ ] Database query optimization

---

Last Updated: 2025-01-04