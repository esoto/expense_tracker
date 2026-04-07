import { Controller } from "@hotwired/stimulus"
import { syncConnectionMixin } from "mixins/sync_connection_mixin"
import { SyncErrorClassifier } from "services/sync_error_classifier"
import { SyncStateCache } from "services/sync_state_cache"

/**
 * SyncWidgetController — DOM-focused controller for the live sync progress widget.
 *
 * Connection management, reconnection, polling, visibility, and network monitoring
 * live in syncConnectionMixin (mixed in below).
 *
 * Error analysis lives in SyncErrorClassifier.
 * State caching lives in SyncStateCache.
 *
 * Fixes:
 *   PER-359 — isPaused dual-purpose bug (userPaused / visibilityPaused are separate flags)
 *   PER-360 — polling never stops after sync completes (handled in mixin pollForUpdates)
 */

const SyncWidgetController = class extends Controller {
  static targets = [
    "progressBar",
    "progressPercentage",
    "processedCount",
    "detectedCount",
    "activeCount",
    "timeRemaining",
    "accountsList",
    "activeSection",
    "inactiveSection",
    "connectionStatus",
    "retryButton",
    "statusText",
    "pauseButton",
    "progressSection",
    "progressIndicator",
    "errorCount",
    "accountItem",
    "accountStatusIcon",
    "accountProgress",
    "accountCount",
    "accountProgressBar",
    "connectionWarning",
    "connectionMessage",
    "iconProcessing",
    "iconCompleted",
    "iconFailed"
  ]

  static values = {
    sessionId: Number,
    active: Boolean,
    enableWebsocket: { type: Boolean, default: true },
    connectionState: { type: String, default: "disconnected" },
    retryCount: { type: Number, default: 0 },
    maxRetries: { type: Number, default: 5 },
    debug: { type: Boolean, default: false }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  connect() {
    // PER-359: split isPaused into two independent flags so that a manual user
    // pause is not overridden when the user switches back to the tab.
    this.userPaused = false
    this.visibilityPaused = false

    this.isCompleted = false
    this.reconnectTimer = null
    this.lastUpdateTime = Date.now()
    this.updateQueue = []
    this.updateThrottleTimer = null
    this.pollingTimer = null
    this.pollingMode = false
    this.errorCount = 0
    this.lastError = null

    this.setupVisibilityHandling()
    this.setupNetworkMonitoring()
    this.setupToastNotifications()

    // Restore previous state from sessionStorage (if < 5 min old)
    const cached = SyncStateCache.loadCachedState(this.sessionIdValue)
    if (cached) {
      this.log("info", "Loading cached state")
      this.applyUpdate(cached)
      this.showCacheIndicator()
    }

    if (!this.enableWebsocketValue) {
      this.log("info", "WebSocket disabled - no active sync session")
    } else if (!this.isWebSocketSupported()) {
      this.enablePollingMode()
    } else if (this.activeValue && this.sessionIdValue && this.sessionIdValue > 0) {
      this.subscribeToChannel()
      if (window.accessibilityManager) {
        window.accessibilityManager.announce('Sincronización iniciada')
      }
    }

    this.log("info", "Sync widget initialized", {
      sessionId: this.sessionIdValue,
      active: this.activeValue
    })
  }

  disconnect() {
    this.log("info", "Disconnecting sync widget")

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }

    if (this.updateThrottleTimer) {
      clearTimeout(this.updateThrottleTimer)
      this.updateThrottleTimer = null
    }

    // Use stopPolling() to also clean up the polling indicator DOM element
    this.stopPolling()

    if (this.visibilityHandler) {
      document.removeEventListener('visibilitychange', this.visibilityHandler)
      this.visibilityHandler = null
    }

    if (this.onlineHandler) {
      window.removeEventListener('online', this.onlineHandler)
      this.onlineHandler = null
    }

    if (this.offlineHandler) {
      window.removeEventListener('offline', this.offlineHandler)
      this.offlineHandler = null
    }

    if (this.subscription) {
      try {
        this.subscription.unsubscribe()
      } catch (error) {
        this.log("error", "Error unsubscribing", error)
      }
      this.subscription = null
    }

    this.consumer = null

    if (this.isCompleted) {
      SyncStateCache.clearCachedState(this.sessionIdValue)
    }

    this.connectionStateValue = "disconnected"
  }

  // ---------------------------------------------------------------------------
  // PER-359: computed isPaused getter
  // ---------------------------------------------------------------------------

  /**
   * True when either the user has manually paused OR the tab is hidden.
   * Read-only — set userPaused / visibilityPaused directly instead.
   */
  get isPaused() {
    return this.userPaused || this.visibilityPaused
  }

  // ---------------------------------------------------------------------------
  // Update pipeline
  // ---------------------------------------------------------------------------

  handleUpdate(data) {
    if (this.isPaused) {
      this.log("debug", "Update skipped (paused)", data)
      return
    }

    this.lastUpdateTime = Date.now()
    SyncStateCache.cacheState(this.sessionIdValue, data)
    this.throttledUIUpdate(data)
  }

  throttledUIUpdate(data) {
    this.updateQueue.push(data)

    if (!this.updateThrottleTimer) {
      this.updateThrottleTimer = setTimeout(() => {
        this.processUpdateQueue()
        this.updateThrottleTimer = null
      }, 100)
    }
  }

  processUpdateQueue() {
    if (this.updateQueue.length === 0) return

    const updates = [...this.updateQueue]
    this.updateQueue = []

    const latestByType = {}
    updates.forEach(update => {
      latestByType[update.type || 'status'] = update
    })

    Object.values(latestByType).forEach(data => this.applyUpdate(data))
  }

  applyUpdate(data) {
    switch (data.type) {
      case 'initial_status':
        this.updateStatus(data)
        break
      case 'progress_update':
        this.updateProgress(data)
        break
      case 'account_update':
        this.updateAccount(data)
        break
      case 'activity':
        this.logActivity(data)
        break
      case 'completed':
        this.handleCompletion(data)
        break
      case 'failed':
        this.handleFailure(data)
        break
      default:
        this.updateStatus(data)
    }
  }

  // ---------------------------------------------------------------------------
  // DOM update methods
  // ---------------------------------------------------------------------------

  updateProgress(data) {
    const percentage = data.progress_percentage || 0

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percentage}%`
      this.progressBarTarget.setAttribute('aria-valuenow', percentage)
    }

    if (this.hasProgressIndicatorTarget) {
      this.progressIndicatorTarget.style.left = `${percentage}%`
    }

    if (this.hasProgressPercentageTarget) {
      this.progressPercentageTarget.textContent = `${percentage}%`
    }

    if (this.hasProcessedCountTarget && data.processed_emails !== undefined) {
      this.processedCountTarget.textContent = this.formatNumber(data.processed_emails)
    }

    if (this.hasDetectedCountTarget && data.detected_expenses !== undefined) {
      this.detectedCountTarget.textContent = data.detected_expenses
    }

    if (this.hasErrorCountTarget && data.error_count !== undefined) {
      this.errorCountTarget.textContent = data.error_count

      if (data.error_count > 0) {
        this.errorCountTarget.classList.add('text-rose-600')
        this.errorCountTarget.classList.remove('text-slate-600')
      }
    }

    if (this.hasTimeRemainingTarget && data.time_remaining) {
      this.timeRemainingTarget.textContent = data.time_remaining
    }
  }

  updateAccount(data) {
    if (!this.hasAccountsListTarget) return

    const accountElement = this.accountsListTarget.querySelector(
      `[data-account-id="${data.account_id}"]`
    )

    if (accountElement) {
      const statusIcon = accountElement.querySelector('[data-status-icon]')
      if (statusIcon) this.updateStatusIcon(statusIcon, data.status)

      const progressText = accountElement.querySelector('[data-progress-text]')
      if (progressText) progressText.textContent = `${data.progress || 0}%`

      const progressCount = accountElement.querySelector('[data-progress-count]')
      if (progressCount) {
        progressCount.textContent = `${data.processed || 0} / ${data.total || 0}`
      }
    }
  }

  updateStatus(data) {
    if (data.status) {
      this.updateProgress(data)

      if (data.accounts && Array.isArray(data.accounts)) {
        data.accounts.forEach(account => {
          this.updateAccount({
            account_id: account.id || account.account_id,
            status: account.status,
            progress: account.progress,
            processed: account.processed,
            total: account.total,
            detected: account.detected
          })
        })
      }
    }
  }

  logActivity(_data) {
    // Reserved for activity log feature
  }

  handleCompletion(data) {
    this.log("info", "Sync completed", data)
    this.isCompleted = true

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = '100%'
    }
    if (this.hasProgressPercentageTarget) {
      this.progressPercentageTarget.textContent = '100%'
    }

    if (data.processed_emails !== undefined && this.hasProcessedCountTarget) {
      this.processedCountTarget.textContent = this.formatNumber(data.processed_emails)
    }
    if (data.detected_expenses !== undefined && this.hasDetectedCountTarget) {
      this.detectedCountTarget.textContent = data.detected_expenses
    }

    const message = `Sincronización completada: ${data.detected_expenses || 0} gastos detectados de ${data.processed_emails || 0} correos`
    this.showToast(message, "success", 7000)
    if (window.accessibilityManager) {
      window.accessibilityManager.announce(message)
    }

    setTimeout(() => {
      SyncStateCache.clearCachedState(this.sessionIdValue)
    }, 2000)
  }

  handleFailure(data) {
    const error = {
      code: data.error_code,
      type: data.error_type,
      message: data.error,
      details: data.error_details
    }

    SyncErrorClassifier.handleSyncError(error, {
      showToast: this.showToast.bind(this),
      log: this.log.bind(this),
      sendErrorToServer: this.sendErrorToServer.bind(this)
    })

    const failureMessage = `Error en sincronización: ${data.error || 'Error desconocido'}`
    if (window.accessibilityManager) {
      window.accessibilityManager.announce(failureMessage, 'assertive')
    }

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.classList.add('bg-rose-600')
      this.progressBarTarget.classList.remove('bg-teal-700')
    }

    const errorInfo = SyncErrorClassifier.analyzeError(error)
    if (errorInfo.recoverable) {
      this.showManualRetryButton()
    }
  }

  updateStatusIcon(element, status) {
    element.textContent = ''
    const templateMap = {
      processing: 'iconProcessingTarget',
      running: 'iconProcessingTarget',
      completed: 'iconCompletedTarget',
      failed: 'iconFailedTarget'
    }
    const targetName = templateMap[status]
    if (targetName && this[`has${targetName.charAt(0).toUpperCase() + targetName.slice(1)}`]) {
      element.appendChild(this[targetName].content.cloneNode(true))
    } else {
      const dot = document.createElement('div')
      dot.className = 'h-4 w-4 rounded-full bg-slate-300'
      element.appendChild(dot)
    }
  }

  // ---------------------------------------------------------------------------
  // Toast / notification
  // ---------------------------------------------------------------------------

  setupToastNotifications() {
    if (!document.querySelector('[data-controller="toast"]')) {
      const toastContainer = document.createElement('div')
      toastContainer.dataset.controller = 'toast'
      toastContainer.dataset.toastPositionValue = 'top-right'
      document.body.appendChild(toastContainer)
    }
  }

  showToast(message, type = 'info', duration = null, action = null, actionText = null) {
    const event = new CustomEvent('toast:show', {
      detail: { message, type, duration, action, actionText }
    })
    document.dispatchEvent(event)
  }

  showNotification(message, type = 'info') {
    this.showToast(message, type)
  }

  // ---------------------------------------------------------------------------
  // Pause / resume (user-initiated — PER-359)
  // ---------------------------------------------------------------------------

  togglePause(event) {
    event.preventDefault()

    if (this.isPaused) {
      this.resumeSync()
    } else {
      this.pauseSync()
    }
  }

  pauseSync() {
    // Only the user-pause flag is set here; visibilityPaused is managed by the mixin
    this.userPaused = true

    if (this.hasPauseButtonTarget) {
      this.pauseButtonTarget.textContent = ''
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
      svg.setAttribute('aria-hidden', 'true')
      svg.setAttribute('class', 'w-4 h-4 mr-1.5')
      svg.setAttribute('fill', 'none')
      svg.setAttribute('stroke', 'currentColor')
      svg.setAttribute('viewBox', '0 0 24 24')
      const path1 = document.createElementNS('http://www.w3.org/2000/svg', 'path')
      path1.setAttribute('stroke-linecap', 'round')
      path1.setAttribute('stroke-linejoin', 'round')
      path1.setAttribute('stroke-width', '2')
      path1.setAttribute('d', 'M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z')
      const path2 = document.createElementNS('http://www.w3.org/2000/svg', 'path')
      path2.setAttribute('stroke-linecap', 'round')
      path2.setAttribute('stroke-linejoin', 'round')
      path2.setAttribute('stroke-width', '2')
      path2.setAttribute('d', 'M21 12a9 9 0 11-18 0 9 9 0 0118 0z')
      svg.appendChild(path1)
      svg.appendChild(path2)
      this.pauseButtonTarget.appendChild(svg)
      this.pauseButtonTarget.appendChild(document.createTextNode('Reanudar'))
      this.pauseButtonTarget.classList.add('bg-amber-50', 'border-amber-300', 'text-amber-700')
      this.pauseButtonTarget.classList.remove('bg-white', 'border-slate-300', 'text-slate-700')
    }

    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = ''
      const span = document.createElement('span')
      span.className = 'inline-flex items-center'
      const dot = document.createElement('span')
      dot.className = 'w-2 h-2 bg-amber-500 rounded-full mr-2'
      span.appendChild(dot)
      span.appendChild(document.createTextNode('Sincronización pausada'))
      this.statusTextTarget.appendChild(span)
    }

    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('pause_sync')
      } catch (error) {
        this.log("error", "Error pausing sync", error)
      }
    }

    this.showToast("Sincronización pausada", "info")
    if (window.accessibilityManager) {
      window.accessibilityManager.announce('Sincronización pausada')
    }
  }

  resumeSync() {
    // Only the user-pause flag is cleared here
    this.userPaused = false

    if (this.hasPauseButtonTarget) {
      this.pauseButtonTarget.textContent = ''
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
      svg.setAttribute('aria-hidden', 'true')
      svg.setAttribute('class', 'w-4 h-4 mr-1.5')
      svg.setAttribute('fill', 'none')
      svg.setAttribute('stroke', 'currentColor')
      svg.setAttribute('viewBox', '0 0 24 24')
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
      path.setAttribute('stroke-linecap', 'round')
      path.setAttribute('stroke-linejoin', 'round')
      path.setAttribute('stroke-width', '2')
      path.setAttribute('d', 'M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z')
      svg.appendChild(path)
      this.pauseButtonTarget.appendChild(svg)
      this.pauseButtonTarget.appendChild(document.createTextNode('Pausar'))
      this.pauseButtonTarget.classList.remove('bg-amber-50', 'border-amber-300', 'text-amber-700')
      this.pauseButtonTarget.classList.add('bg-white', 'border-slate-300', 'text-slate-700')
    }

    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = ''
      const span = document.createElement('span')
      span.className = 'inline-flex items-center'
      const dot = document.createElement('span')
      dot.className = 'w-2 h-2 bg-emerald-500 rounded-full mr-2 animate-pulse'
      span.appendChild(dot)
      span.appendChild(document.createTextNode('Sincronización en progreso'))
      this.statusTextTarget.appendChild(span)
    }

    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('resume_sync')
        this.requestLatestStatus()
      } catch (error) {
        this.log("error", "Error resuming sync", error)
      }
    }

    this.showToast("Sincronización reanudada", "success")
    if (window.accessibilityManager) {
      window.accessibilityManager.announce('Sincronización reanudada')
    }
  }

  // ---------------------------------------------------------------------------
  // Connection status UI
  // ---------------------------------------------------------------------------

  updateConnectionStatus(status) {
    if (window.accessibilityManager) {
      const isError = ['disconnected', 'offline', 'error', 'rejected'].includes(this.connectionStateValue)
      window.accessibilityManager.announce(status, isError ? 'assertive' : 'polite')
    }

    if (this.hasConnectionStatusTarget) {
      this.connectionStatusTarget.textContent = status

      const colorClasses = {
        connected: 'text-emerald-600',
        connecting: 'text-amber-600',
        disconnected: 'text-rose-600',
        offline: 'text-slate-500',
        error: 'text-rose-600',
        rejected: 'text-rose-600'
      }

      Object.values(colorClasses).forEach(cls => {
        this.connectionStatusTarget.classList.remove(cls)
      })

      const colorClass = colorClasses[this.connectionStateValue] || 'text-slate-600'
      this.connectionStatusTarget.classList.add(colorClass)
    }

    if (this.hasConnectionWarningTarget && this.hasConnectionMessageTarget) {
      const showWarning = ['disconnected', 'connecting', 'offline', 'error', 'rejected']
        .includes(this.connectionStateValue)

      if (showWarning) {
        this.connectionWarningTarget.classList.remove('hidden')
        this.connectionMessageTarget.textContent = status

        if (this.connectionStateValue === 'error' || this.connectionStateValue === 'rejected') {
          this.connectionWarningTarget.classList.remove('bg-amber-50', 'border-amber-200')
          this.connectionWarningTarget.classList.add('bg-rose-50', 'border-rose-200')
          this.connectionMessageTarget.classList.remove('text-amber-800')
          this.connectionMessageTarget.classList.add('text-rose-800')
        } else {
          this.connectionWarningTarget.classList.remove('bg-rose-50', 'border-rose-200')
          this.connectionWarningTarget.classList.add('bg-amber-50', 'border-amber-200')
          this.connectionMessageTarget.classList.remove('text-rose-800')
          this.connectionMessageTarget.classList.add('text-amber-800')
        }
      } else {
        this.connectionWarningTarget.classList.add('hidden')
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Cache indicator (DOM — stays in controller)
  // ---------------------------------------------------------------------------

  showCacheIndicator() {
    const indicator = document.createElement('div')
    indicator.className = 'fixed top-4 right-4 z-40 px-3 py-1 text-xs bg-amber-100 text-amber-700 rounded-lg'
    indicator.textContent = 'Datos desde caché'
    document.body.appendChild(indicator)

    setTimeout(() => {
      indicator.style.opacity = '0'
      setTimeout(() => indicator.remove(), 300)
    }, 2000)
  }

  // ---------------------------------------------------------------------------
  // Utility actions
  // ---------------------------------------------------------------------------

  startSync(event) {
    event.preventDefault()
    const form = event.currentTarget.closest('form')
    if (form) form.submit()
  }

  formatNumber(num) {
    return new Intl.NumberFormat('es-CR').format(num)
  }

  // ---------------------------------------------------------------------------
  // Logging and error reporting
  // ---------------------------------------------------------------------------

  log(level, message, data = {}) {
    // Console logging only in debug mode
    if (this.debugValue || this.element.dataset.debug === 'true') {
      const timestamp = new Date().toISOString()
      const prefix = `[${timestamp}] SyncWidget:`

      if (data && Object.keys(data).length > 0) {
        console[level](prefix, message, data)
      } else {
        console[level](prefix, message)
      }
    }

    // Error reporting always active (server-side handles environment check)
    if (level === 'error') {
      this.sendErrorToServer(message, data)
    }
  }

  sendErrorToServer(message, data) {
    // Throttle: max 1 report per second, deduplicated by message
    const now = Date.now()
    if (!this._errorReportLog) this._errorReportLog = {}
    if (this._errorReportLog[message] && now - this._errorReportLog[message] < 1000) return
    this._errorReportLog[message] = now

    // Only report in production (check server-rendered meta tag)
    const env = document.querySelector('meta[name="rails-env"]')?.content
    if (!env || env !== 'production') return

    const payload = {
      message,
      data,
      sessionId: this.sessionIdValue,
      timestamp: now,
      errorCount: this.errorCount,
      pollingMode: this.pollingMode,
      connectionState: this.connectionStateValue
    }

    fetch('/api/client_errors', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
      },
      body: JSON.stringify(payload)
    }).catch(() => {
      // Silently fail — avoid recursive error reporting
    })
  }
}

// Mix connection management into the controller prototype
Object.assign(SyncWidgetController.prototype, syncConnectionMixin)

export default SyncWidgetController
