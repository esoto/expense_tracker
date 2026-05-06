import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { t } from "services/i18n"
import { createElement } from "utilities/safe_dom"

// Helper: build a single <path> element with the standard stroke options.
// Used for icon SVGs whose <svg> wrapper already exists in the DOM.
function buildSvgPath(d) {
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
  path.setAttribute('stroke-linecap', 'round')
  path.setAttribute('stroke-linejoin', 'round')
  path.setAttribute('stroke-width', '2')
  path.setAttribute('d', d)
  return path
}

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
    console.log("Monitor de cola conectado")
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
    console.log("Actualización en tiempo real de la cola recibida:", data)

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
        throw new Error(`Error HTTP! estado: ${response.status}`)
      }

      const result = await response.json()
      if (result.success) {
        this.updateDisplay(result.data)
        this.updateLastRefreshTime()
      }
    } catch (error) {
      console.error("Error al obtener estado de la cola:", error)
      this.showError(t("queue.errors.load_status"))
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
    this.processingRateTarget.textContent = `${rate.toFixed(1)} trabajos/min`

    // Estimated completion time
    if (performance.estimated_minutes) {
      const minutes = performance.estimated_minutes
      if (minutes < 60) {
        this.estimatedTimeTarget.textContent = `~${minutes} min restantes`
      } else {
        const hours = Math.floor(minutes / 60)
        const mins = minutes % 60
        this.estimatedTimeTarget.textContent = `~${hours}h ${mins}m restantes`
      }
    } else {
      this.estimatedTimeTarget.textContent = "Sin cola pendiente"
    }
  }

  // Update pause button state
  updatePauseButton(pausedQueues) {
    this.isPaused = pausedQueues && pausedQueues.length > 0
    
    if (this.isPaused) {
      this.pauseButtonTarget.className = "px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-medium rounded-lg transition-colors flex items-center space-x-1"
      this.pauseTextTarget.textContent = t("queue.actions.resume_all")
      this.pauseIconTarget.replaceChildren(
        buildSvgPath("M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"),
        buildSvgPath("M21 12a9 9 0 11-18 0 9 9 0 0118 0z")
      )
    } else {
      this.pauseButtonTarget.className = "px-3 py-1.5 bg-amber-600 hover:bg-amber-700 text-white text-sm font-medium rounded-lg transition-colors flex items-center space-x-1"
      this.pauseTextTarget.textContent = t("queue.actions.pause_all")
      this.pauseIconTarget.replaceChildren(
        buildSvgPath("M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z")
      )
    }
  }

  // Update active jobs list
  updateActiveJobs(activeJobs) {
    if (!activeJobs || activeJobs.length === 0) {
      this.activeJobsSectionTarget.style.display = "none"
      return
    }

    this.activeJobsSectionTarget.style.display = "block"
    // Build DOM nodes safely — no innerHTML for job data
    const nodes = activeJobs.map(job => this.renderActiveJob(job))
    this.activeJobsListTarget.replaceChildren(...nodes)
  }

  // Render a single active job — safe DOM construction (no innerHTML for user data)
  renderActiveJob(job) {
    const duration = job.duration ? this.formatDuration(job.duration) : t("queue.status.just_started")

    const classSpan = createElement('span', {
      text: this.formatJobClass(job.class_name),
      classes: ['text-sm', 'font-medium', 'text-slate-900']
    })
    const queueSpan = createElement('span', {
      text: job.queue_name,
      classes: ['text-xs', 'px-2', 'py-0.5', 'bg-teal-100', 'text-teal-700', 'rounded-full']
    })
    const headerRow = createElement('div', {
      classes: ['flex', 'items-center', 'space-x-2'],
      children: [classSpan, queueSpan]
    })

    const metaDiv = createElement('div', { classes: ['text-xs', 'text-slate-600', 'mt-1'] })
    if (job.process_info) {
      const pidSpan = createElement('span', {
        text: `Trabajador ${job.process_info.pid}@${job.process_info.hostname}`,
        classes: ['text-xs', 'text-slate-500']
      })
      // Trailing space preserves the visual gap between meta line and PID
      // span. Without it the rendered text reads "Prioridad 1Trabajador …"
      metaDiv.append(`${duration} • Prioridad ${job.priority} `, pidSpan)
    } else {
      metaDiv.append(`${duration} • Prioridad ${job.priority}`)
    }

    const innerDiv = createElement('div', { classes: ['flex-1'], children: [headerRow, metaDiv] })

    return createElement('div', {
      classes: ['flex', 'items-center', 'justify-between', 'p-3', 'bg-teal-50', 'rounded-lg'],
      children: [innerDiv]
    })
  }

  // Update failed jobs list
  updateFailedJobs(failedJobs) {
    if (!failedJobs || failedJobs.length === 0) {
      this.failedJobsSectionTarget.style.display = "none"
      return
    }

    this.failedJobsSectionTarget.style.display = "block"
    // Build DOM nodes safely — no innerHTML for job data
    const nodes = failedJobs.map(job => this.renderFailedJob(job))
    this.failedJobsListTarget.replaceChildren(...nodes)
  }

  // Render a single failed job — safe DOM construction (no innerHTML for user data)
  renderFailedJob(job) {
    const errorMessage = this.extractErrorMessage(job.error)
    const failedAt = new Date(job.created_at).toLocaleString()

    const classSpan = createElement('span', {
      text: this.formatJobClass(job.class_name),
      classes: ['text-sm', 'font-medium', 'text-slate-900']
    })
    const queueSpan = createElement('span', {
      text: job.queue_name,
      classes: ['text-xs', 'px-2', 'py-0.5', 'bg-rose-100', 'text-rose-700', 'rounded-full']
    })
    const headerRow = createElement('div', {
      classes: ['flex', 'items-center', 'space-x-2'],
      children: [classSpan, queueSpan]
    })

    const errorDiv = createElement('div', {
      text: errorMessage,
      classes: ['text-xs', 'text-rose-600', 'mt-1']
    })
    const failedAtDiv = createElement('div', {
      text: `${t("queue.status.failed_at")}${failedAt}`,
      classes: ['text-xs', 'text-slate-500', 'mt-1']
    })
    const infoDiv = createElement('div', { classes: ['flex-1'], children: [headerRow, errorDiv, failedAtDiv] })

    const retryBtn = createElement('button', {
      text: t("common.actions.retry"),
      attrs: {
        'data-job-id': String(job.id),
        'data-action': 'click->queue-monitor#retryJob'
      },
      classes: ['px-2', 'py-1', 'bg-rose-600', 'hover:bg-rose-700', 'text-white', 'text-xs', 'font-medium', 'rounded', 'transition-colors']
    })
    const clearBtn = createElement('button', {
      text: t("common.actions.clear"),
      attrs: {
        'data-job-id': String(job.id),
        'data-action': 'click->queue-monitor#clearJob'
      },
      classes: ['px-2', 'py-1', 'bg-slate-600', 'hover:bg-slate-700', 'text-white', 'text-xs', 'font-medium', 'rounded', 'transition-colors']
    })
    const actionsDiv = createElement('div', {
      classes: ['flex', 'items-center', 'space-x-1', 'ml-4'],
      children: [retryBtn, clearBtn]
    })

    const rowFlex = createElement('div', {
      classes: ['flex', 'items-start', 'justify-between'],
      children: [infoDiv, actionsDiv]
    })

    return createElement('div', {
      classes: ['p-3', 'bg-rose-50', 'rounded-lg'],
      children: [rowFlex]
    })
  }

  // Update queue breakdown
  updateQueueBreakdown(queueDepths) {
    if (!queueDepths || Object.keys(queueDepths).length === 0) {
      this.queueBreakdownTarget.style.display = "none"
      return
    }

    this.queueBreakdownTarget.style.display = "block"

    const sortedQueues = Object.entries(queueDepths).sort((a, b) => b[1] - a[1])

    // Build DOM nodes safely — no innerHTML for queue names or counts
    const nodes = sortedQueues.map(([name, count]) => createElement('div', {
      classes: ['flex', 'items-center', 'justify-between', 'p-2', 'bg-slate-50', 'rounded'],
      children: [
        createElement('span', { text: name,        classes: ['text-sm', 'text-slate-700'] }),
        createElement('span', { text: String(count), classes: ['text-sm', 'font-medium', 'text-slate-900'] })
      ]
    }))
    this.queueListTarget.replaceChildren(...nodes)
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
        this.showError(result.error || t("queue.errors.operation_failed"))
      }
    } catch (error) {
      console.error("Error al cambiar pausa:", error)
      this.showError(t("queue.errors.toggle_pause"))
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
        this.showSuccess(t("queue.notifications.job_queued_retry", { jobId }))
        this.fetchQueueStatus()
      } else {
        this.showError(result.error || t("queue.errors.retry_job"))
      }
    } catch (error) {
      console.error("Error al reintentar trabajo:", error)
      this.showError(t("queue.errors.retry_job"))
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
        this.showSuccess(t("queue.notifications.job_cleared", { jobId }))
        this.fetchQueueStatus()
      } else {
        this.showError(result.error || t("queue.errors.clear_job"))
      }
    } catch (error) {
      console.error("Error al limpiar trabajo:", error)
      this.showError(t("queue.errors.clear_job"))
    }
  }

  // Retry all failed jobs
  async retryAllFailed(event) {
    event.preventDefault()

    if (!confirm(t("queue.confirmations.retry_all_jobs"))) {
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
        this.showError(result.error || t("queue.errors.retry_all_failed"))
      }
    } catch (error) {
      console.error("Error al reintentar todos los trabajos:", error)
      this.showError(t("queue.errors.retry_all"))
    }
  }

  // Clear all failed jobs (not implemented in controller, but placeholder)
  async clearAllFailed(event) {
    event.preventDefault()

    if (!confirm(t("queue.confirmations.clear_all_jobs"))) {
      return
    }

    this.showError(t("queue.errors.clear_all_not_implemented"))
  }

  // Update last refresh time
  updateLastRefreshTime() {
    const now = new Date()
    const timeStr = now.toLocaleTimeString()
    this.lastUpdateTarget.textContent = `Actualizado ${timeStr}`
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
    if (!error) return t("queue.errors.unknown_error")

    try {
      // If it's a string, try to parse it as JSON
      if (typeof error === "string") {
        const parsed = JSON.parse(error)
        return parsed.message || parsed.error || error
      }
      return error.message || error.error || t("queue.errors.unknown_error")
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