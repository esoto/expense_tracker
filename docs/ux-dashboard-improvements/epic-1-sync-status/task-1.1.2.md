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
