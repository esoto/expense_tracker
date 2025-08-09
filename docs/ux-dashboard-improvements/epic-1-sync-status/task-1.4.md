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