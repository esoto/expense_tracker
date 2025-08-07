# Real-time Dashboard Updates

## Overview
The dashboard now supports real-time updates during email synchronization using a combination of:
- **Action Cable** for WebSocket connections
- **Turbo Streams** for partial page updates
- **Stimulus Controllers** for JavaScript interactions

## Architecture

### 1. WebSocket Connection
- Established via `application.js` when the page loads
- Creates a global consumer for Action Cable
- Maintains persistent connection for real-time updates

### 2. Turbo Streams
- Dashboard subscribes to `dashboard_sync_updates` channel
- SyncSession model broadcasts updates on status changes
- Partial updates without page refresh

### 3. Stimulus Controllers
- `sync-widget` controller manages real-time UI updates
- Listens to SyncStatusChannel for progress updates
- Updates progress bars, counters, and status indicators

## How It Works

### Starting a Sync
1. User clicks "Sincronizar" button on dashboard
2. SyncSession is created with status "pending"
3. Initial broadcast sent to dashboard
4. Progress bar and status indicators appear

### During Sync
1. Background jobs process emails
2. SyncProgressUpdater updates session progress
3. Broadcasts sent via:
   - Action Cable (SyncStatusChannel)
   - Turbo Streams (dashboard_sync_updates)
4. Dashboard UI updates in real-time:
   - Progress bar advances
   - Email count updates
   - Detected expenses counter increases
   - Account status icons animate

### Completion
1. Session marked as "completed"
2. Final broadcast sent
3. UI shows completion status
4. Success notification displayed

## Testing Real-time Updates

### Manual Testing
1. Open dashboard at `/expenses/dashboard`
2. Open browser console (F12)
3. Start a sync session
4. Observe real-time updates without refresh

### Automated Testing
Run the test script in Rails console:
```ruby
load 'test_dashboard_realtime.rb'
```

This simulates a sync session with progress updates.

## Debugging

### Check WebSocket Connection
In browser console:
```javascript
// Should show connected status
console.log(window.consumer)
```

### Monitor Action Cable Activity
Look for console logs:
- "✅ Connected to Action Cable"
- "✅ Connected to SyncStatusChannel"
- "📨 Received data: {progress data}"

### Common Issues

1. **No real-time updates**
   - Check Action Cable is running: `rails s`
   - Verify WebSocket connection in browser console
   - Check for JavaScript errors

2. **Updates stop working**
   - WebSocket may have disconnected
   - Refresh page to reconnect
   - Check server logs for errors

3. **Partial updates not rendering**
   - Verify Turbo Stream subscription
   - Check partial path is correct
   - Ensure target IDs match

## Files Modified

### Controllers
- `app/javascript/controllers/sync_widget_controller.js` - Handles real-time UI updates
- `app/javascript/controllers/sync_sessions_controller.js` - Manages sync session page

### Models
- `app/models/sync_session.rb` - Added Turbo Stream broadcasts

### Services
- `app/services/sync_progress_updater.rb` - Triggers dashboard broadcasts

### Views
- `app/views/expenses/dashboard.html.erb` - Added Turbo frames and data attributes
- `app/views/expenses/_sync_status_section.html.erb` - Partial for updates

### JavaScript
- `app/javascript/application.js` - Global Action Cable consumer

## Performance Considerations

- Broadcasts throttled to avoid overwhelming clients
- Uses partial updates instead of full page refreshes
- WebSocket connection reused for multiple updates
- Automatic reconnection on disconnect