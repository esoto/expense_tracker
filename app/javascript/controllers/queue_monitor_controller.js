import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Queue Monitor Stimulus Controller
// Manages real-time queue visualization and control operations
export default class extends Controller {
  static targets = [
    "healthIndicator", "healthDot", "healthText",
    "pendingCount", "processingCount", "completedCount", "failedCount",
    "queueDepthBar", "queueDepthMax",
    "processingRate", "estimatedTime",
    "pauseButton", "pauseIcon", "pauseText",
    "activeJobsSection", "activeJobsList",
    "failedJobsSection", "failedJobsList",
    "queueBreakdown", "queueList",
    "workerCount", "utilization",
    "lastUpdate", "retryAllButton", "noFailedText"
  ]

  static values = {
    refreshInterval: { type: Number, default: 5000 },
    apiEndpoint: { type: String, default: "/api/queue/status.json" }
  }

  connect() {
    console.log("Queue monitor connected")
    this.isPaused = false
    this.setupActionCable()
    this.startAutoRefresh()
    this.fetchQueueStatus()
  }

  disconnect() {
    this.stopAutoRefresh()
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  // Setup ActionCable subscription for real-time updates
  setupActionCable() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create("QueueChannel", {
      received: (data) => {
        this.handleRealtimeUpdate(data)
      }
    })
  }

  // Handle real-time updates from ActionCable
  handleRealtimeUpdate(data) {
    console.log("Received real-time queue update:", data)
    
    // If it's a significant change, refresh immediately
    if (data.action === "job_failed" || data.action === "paused" || data.action === "resumed") {
      this.fetchQueueStatus()
    }
  }

  // Start auto-refresh timer
  startAutoRefresh() {
    this.refreshTimer = setInterval(() => {
      this.fetchQueueStatus()
    }, this.refreshIntervalValue)
  }

  // Stop auto-refresh timer
  stopAutoRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = null
    }
  }

  // Manual refresh action
  refresh(event) {
    event?.preventDefault()
    this.fetchQueueStatus()
  }

  // Fetch queue status from API
  async fetchQueueStatus() {
    try {
      const response = await fetch(this.apiEndpointValue, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const result = await response.json()
      if (result.success) {
        this.updateDisplay(result.data)
        this.updateLastRefreshTime()
      }
    } catch (error) {
      console.error("Failed to fetch queue status:", error)
      this.showError("Failed to load queue status")
    }
  }

  // Update all display elements with new data
  updateDisplay(data) {
    // Update counts
    this.updateCounts(data.summary)
    
    // Update health status
    this.updateHealthStatus(data.summary.health)
    
    // Update queue depth visualization
    this.updateQueueDepth(data.summary, data.queues.depth)
    
    // Update performance metrics
    this.updatePerformanceMetrics(data.performance)
    
    // Update pause button state
    this.updatePauseButton(data.queues.paused)
    
    // Update active jobs list
    this.updateActiveJobs(data.jobs.active)
    
    // Update failed jobs list
    this.updateFailedJobs(data.jobs.failed)
    
    // Update queue breakdown
    this.updateQueueBreakdown(data.queues.depth)
    
    // Update worker status
    this.updateWorkerStatus(data.workers)
  }

  // Update job counts
  updateCounts(summary) {
    this.pendingCountTarget.textContent = this.formatNumber(summary.pending)
    this.processingCountTarget.textContent = this.formatNumber(summary.processing)
    this.completedCountTarget.textContent = this.formatNumber(summary.completed)
    this.failedCountTarget.textContent = this.formatNumber(summary.failed)
    
    // Show/hide retry all button
    if (summary.failed > 0) {
      this.retryAllButtonTarget.classList.remove("hidden")
      this.noFailedTextTarget.classList.add("hidden")
    } else {
      this.retryAllButtonTarget.classList.add("hidden")
      this.noFailedTextTarget.classList.remove("hidden")
    }
  }

  // Update health status indicator
  updateHealthStatus(health) {
    const statusColors = {
      healthy: "bg-emerald-500",
      warning: "bg-amber-500",
      critical: "bg-rose-500"
    }

    // Update dot color
    this.healthDotTarget.className = `w-2 h-2 rounded-full ${statusColors[health.status] || "bg-slate-400"}`
    
    // Update text
    this.healthTextTarget.textContent = health.message
    this.healthTextTarget.className = `text-sm ${
      health.status === "critical" ? "text-rose-600" : 
      health.status === "warning" ? "text-amber-600" : 
      "text-emerald-600"
    }`
  }

  // Update queue depth visualization
  updateQueueDepth(summary, queueDepths) {
    const total = summary.pending + summary.processing
    const maxDepth = Math.max(100, total)
    
    // Update progress bar
    const percentage = Math.min((total / maxDepth) * 100, 100)
    this.queueDepthBarTarget.style.width = `${percentage}%`
    
    // Update bar color based on depth
    let barClass = "bg-gradient-to-r "
    if (total === 0) {
      barClass += "from-slate-300 to-slate-400"
    } else if (total < 50) {
      barClass += "from-teal-500 to-teal-700"
    } else if (total < 200) {
      barClass += "from-amber-500 to-amber-700"
    } else {
      barClass += "from-rose-500 to-rose-700"
    }
    
    this.queueDepthBarTarget.className = `h-full rounded-full transition-all duration-500 ease-out ${barClass}`
    
    // Update max label
    this.queueDepthMaxTarget.textContent = this.formatNumber(maxDepth)
  }

  // Update performance metrics
  updatePerformanceMetrics(performance) {
    // Processing rate
    const rate = performance.processing_rate || 0
    this.processingRateTarget.textContent = `${rate.toFixed(1)} jobs/min`
    
    // Estimated completion time
    if (performance.estimated_minutes) {
      const minutes = performance.estimated_minutes
      if (minutes < 60) {
        this.estimatedTimeTarget.textContent = `~${minutes} min remaining`
      } else {
        const hours = Math.floor(minutes / 60)
        const mins = minutes % 60
        this.estimatedTimeTarget.textContent = `~${hours}h ${mins}m remaining`
      }
    } else {
      this.estimatedTimeTarget.textContent = "No backlog"
    }
  }

  // Update pause button state
  updatePauseButton(pausedQueues) {
    this.isPaused = pausedQueues && pausedQueues.length > 0
    
    if (this.isPaused) {
      this.pauseButtonTarget.className = "px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-medium rounded-lg transition-colors flex items-center space-x-1"
      this.pauseTextTarget.textContent = "Resume All"
      this.pauseIconTarget.innerHTML = `
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"></path>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      `
    } else {
      this.pauseButtonTarget.className = "px-3 py-1.5 bg-amber-600 hover:bg-amber-700 text-white text-sm font-medium rounded-lg transition-colors flex items-center space-x-1"
      this.pauseTextTarget.textContent = "Pause All"
      this.pauseIconTarget.innerHTML = `
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      `
    }
  }

  // Update active jobs list
  updateActiveJobs(activeJobs) {
    if (!activeJobs || activeJobs.length === 0) {
      this.activeJobsSectionTarget.style.display = "none"
      return
    }

    this.activeJobsSectionTarget.style.display = "block"
    this.activeJobsListTarget.innerHTML = activeJobs.map(job => this.renderActiveJob(job)).join("")
  }

  // Render a single active job
  renderActiveJob(job) {
    const duration = job.duration ? this.formatDuration(job.duration) : "Just started"
    const processInfo = job.process_info ? 
      `<span class="text-xs text-slate-500">Worker ${job.process_info.pid}@${job.process_info.hostname}</span>` : ""

    return `
      <div class="flex items-center justify-between p-3 bg-teal-50 rounded-lg">
        <div class="flex-1">
          <div class="flex items-center space-x-2">
            <span class="text-sm font-medium text-slate-900">${this.formatJobClass(job.class_name)}</span>
            <span class="text-xs px-2 py-0.5 bg-teal-100 text-teal-700 rounded-full">${job.queue_name}</span>
          </div>
          <div class="text-xs text-slate-600 mt-1">
            ${duration} • Priority ${job.priority}
            ${processInfo}
          </div>
        </div>
      </div>
    `
  }

  // Update failed jobs list
  updateFailedJobs(failedJobs) {
    if (!failedJobs || failedJobs.length === 0) {
      this.failedJobsSectionTarget.style.display = "none"
      return
    }

    this.failedJobsSectionTarget.style.display = "block"
    this.failedJobsListTarget.innerHTML = failedJobs.map(job => this.renderFailedJob(job)).join("")
  }

  // Render a single failed job
  renderFailedJob(job) {
    const errorMessage = this.extractErrorMessage(job.error)
    const failedAt = new Date(job.created_at).toLocaleString()

    return `
      <div class="p-3 bg-rose-50 rounded-lg">
        <div class="flex items-start justify-between">
          <div class="flex-1">
            <div class="flex items-center space-x-2">
              <span class="text-sm font-medium text-slate-900">${this.formatJobClass(job.class_name)}</span>
              <span class="text-xs px-2 py-0.5 bg-rose-100 text-rose-700 rounded-full">${job.queue_name}</span>
            </div>
            <div class="text-xs text-rose-600 mt-1">${errorMessage}</div>
            <div class="text-xs text-slate-500 mt-1">Failed at ${failedAt}</div>
          </div>
          <div class="flex items-center space-x-1 ml-4">
            <button data-job-id="${job.id}" 
                    data-action="click->queue-monitor#retryJob"
                    class="px-2 py-1 bg-rose-600 hover:bg-rose-700 text-white text-xs font-medium rounded transition-colors">
              Retry
            </button>
            <button data-job-id="${job.id}"
                    data-action="click->queue-monitor#clearJob"
                    class="px-2 py-1 bg-slate-600 hover:bg-slate-700 text-white text-xs font-medium rounded transition-colors">
              Clear
            </button>
          </div>
        </div>
      </div>
    `
  }

  // Update queue breakdown
  updateQueueBreakdown(queueDepths) {
    if (!queueDepths || Object.keys(queueDepths).length === 0) {
      this.queueBreakdownTarget.style.display = "none"
      return
    }

    this.queueBreakdownTarget.style.display = "block"
    
    const sortedQueues = Object.entries(queueDepths).sort((a, b) => b[1] - a[1])
    
    this.queueListTarget.innerHTML = sortedQueues.map(([name, count]) => `
      <div class="flex items-center justify-between p-2 bg-slate-50 rounded">
        <span class="text-sm text-slate-700">${name}</span>
        <span class="text-sm font-medium text-slate-900">${count}</span>
      </div>
    `).join("")
  }

  // Update worker status
  updateWorkerStatus(workers) {
    if (!workers) return

    this.workerCountTarget.textContent = `${workers.healthy}/${workers.total}`
    
    // Calculate utilization (simplified - you might want to refine this)
    const utilization = workers.workers > 0 ? 
      Math.min(100, Math.round((this.processingCountTarget.textContent / workers.workers) * 100)) : 0
    
    this.utilizationTarget.textContent = `${utilization}%`
  }

  // Toggle pause/resume
  async togglePause(event) {
    event.preventDefault()
    
    const endpoint = this.isPaused ? "/api/queue/resume" : "/api/queue/pause"
    
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        }
      })

      const result = await response.json()
      
      if (result.success) {
        this.showSuccess(result.message)
        this.fetchQueueStatus()
      } else {
        this.showError(result.error || "Operation failed")
      }
    } catch (error) {
      console.error("Failed to toggle pause:", error)
      this.showError("Failed to toggle queue pause")
    }
  }

  // Retry a specific failed job
  async retryJob(event) {
    event.preventDefault()
    const jobId = event.currentTarget.dataset.jobId
    
    try {
      const response = await fetch(`/api/queue/jobs/${jobId}/retry`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        }
      })

      const result = await response.json()
      
      if (result.success) {
        this.showSuccess(`Job ${jobId} queued for retry`)
        this.fetchQueueStatus()
      } else {
        this.showError(result.error || "Failed to retry job")
      }
    } catch (error) {
      console.error("Failed to retry job:", error)
      this.showError("Failed to retry job")
    }
  }

  // Clear a specific failed job
  async clearJob(event) {
    event.preventDefault()
    const jobId = event.currentTarget.dataset.jobId
    
    try {
      const response = await fetch(`/api/queue/jobs/${jobId}/clear`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        }
      })

      const result = await response.json()
      
      if (result.success) {
        this.showSuccess(`Job ${jobId} cleared`)
        this.fetchQueueStatus()
      } else {
        this.showError(result.error || "Failed to clear job")
      }
    } catch (error) {
      console.error("Failed to clear job:", error)
      this.showError("Failed to clear job")
    }
  }

  // Retry all failed jobs
  async retryAllFailed(event) {
    event.preventDefault()
    
    if (!confirm("Are you sure you want to retry all failed jobs?")) {
      return
    }
    
    try {
      const response = await fetch("/api/queue/retry_all_failed", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.getCSRFToken()
        }
      })

      const result = await response.json()
      
      if (result.success) {
        this.showSuccess(result.message)
        this.fetchQueueStatus()
      } else {
        this.showError(result.error || "Failed to retry jobs")
      }
    } catch (error) {
      console.error("Failed to retry all jobs:", error)
      this.showError("Failed to retry all failed jobs")
    }
  }

  // Clear all failed jobs (not implemented in controller, but placeholder)
  async clearAllFailed(event) {
    event.preventDefault()
    
    if (!confirm("Are you sure you want to clear all failed jobs? This cannot be undone.")) {
      return
    }
    
    this.showError("Clear all not yet implemented")
  }

  // Update last refresh time
  updateLastRefreshTime() {
    const now = new Date()
    const timeStr = now.toLocaleTimeString()
    this.lastUpdateTarget.textContent = `Updated ${timeStr}`
  }

  // Format job class name
  formatJobClass(className) {
    // Remove "Job" suffix and add spaces before capitals
    return className
      .replace(/Job$/, "")
      .replace(/([A-Z])/g, " $1")
      .trim()
  }

  // Extract error message from error JSON
  extractErrorMessage(error) {
    if (!error) return "Unknown error"
    
    try {
      // If it's a string, try to parse it as JSON
      if (typeof error === "string") {
        const parsed = JSON.parse(error)
        return parsed.message || parsed.error || error
      }
      return error.message || error.error || "Unknown error"
    } catch {
      // If parsing fails, return first 100 chars of the error
      return error.substring(0, 100) + (error.length > 100 ? "..." : "")
    }
  }

  // Format duration in seconds to human-readable
  formatDuration(seconds) {
    if (seconds < 60) {
      return `${Math.round(seconds)}s`
    } else if (seconds < 3600) {
      const minutes = Math.floor(seconds / 60)
      const secs = Math.round(seconds % 60)
      return `${minutes}m ${secs}s`
    } else {
      const hours = Math.floor(seconds / 3600)
      const minutes = Math.floor((seconds % 3600) / 60)
      return `${hours}h ${minutes}m`
    }
  }

  // Format large numbers with commas
  formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }

  // Get CSRF token for POST requests
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  // Show success message (you might want to integrate with your notification system)
  showSuccess(message) {
    console.log("Success:", message)
    // You could dispatch a custom event here for a notification system
  }

  // Show error message
  showError(message) {
    console.error("Error:", message)
    // You could dispatch a custom event here for a notification system
  }
}