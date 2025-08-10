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
