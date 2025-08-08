import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
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
    "retryButton"
  ]
  
  static values = {
    sessionId: Number,
    active: Boolean,
    connectionState: { type: String, default: "disconnected" },
    retryCount: { type: Number, default: 0 },
    maxRetries: { type: Number, default: 5 },
    debug: { type: Boolean, default: false }
  }

  connect() {
    // Initialize state
    this.isPaused = false
    this.isCompleted = false
    this.reconnectTimer = null
    this.lastUpdateTime = Date.now()
    this.updateQueue = []
    this.updateThrottleTimer = null
    
    // Setup event handlers
    this.setupVisibilityHandling()
    this.setupNetworkMonitoring()
    
    // Load cached state if available
    this.loadCachedState()
    
    // Start subscription if active
    if (this.activeValue && this.sessionIdValue) {
      this.subscribeToChannel()
    }
    
    this.log("info", "Sync widget initialized", {
      sessionId: this.sessionIdValue,
      active: this.activeValue
    })
  }

  disconnect() {
    this.log("info", "Disconnecting sync widget")
    
    // Clear all timers
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    
    if (this.updateThrottleTimer) {
      clearTimeout(this.updateThrottleTimer)
      this.updateThrottleTimer = null
    }
    
    // Remove event listeners
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
    
    // Unsubscribe from channel
    if (this.subscription) {
      try {
        this.subscription.unsubscribe()
      } catch (error) {
        this.log("error", "Error unsubscribing", error)
      }
      this.subscription = null
    }
    
    // Disconnect consumer
    if (this.consumer) {
      try {
        this.consumer.disconnect()
      } catch (error) {
        this.log("error", "Error disconnecting consumer", error)
      }
      this.consumer = null
    }
    
    // Clear cached state if session completed
    if (this.isCompleted) {
      this.clearCachedState()
    }
    
    // Update connection state
    this.connectionStateValue = "disconnected"
  }

  subscribeToChannel() {
    // Prevent multiple subscription attempts
    if (this.connectionStateValue === "connecting") {
      this.log("warn", "Already attempting to connect")
      return
    }
    
    this.connectionStateValue = "connecting"
    this.updateConnectionStatus("Conectando...")
    
    // Use global consumer or create one if not available
    if (!this.consumer) {
      this.consumer = window.consumer || createConsumer()
    }
    
    try {
      // Subscribe to sync status channel
      this.subscription = this.consumer.subscriptions.create(
        { 
          channel: "SyncStatusChannel",
          session_id: this.sessionIdValue
        },
        {
          connected: () => {
            this.handleConnected()
          },

          disconnected: () => {
            this.handleDisconnected()
          },

          received: (data) => {
            this.handleUpdate(data)
          },
          
          rejected: () => {
            this.handleRejected()
          }
        }
      )
    } catch (error) {
      this.log("error", "Error creating subscription", error)
      this.handleConnectionError(error)
    }
  }
  
  // Connection event handlers
  handleConnected() {
    this.log("info", "Connected to sync channel")
    
    // Reset retry count on successful connection
    this.retryCountValue = 0
    this.connectionStateValue = "connected"
    this.updateConnectionStatus("Conectado")
    
    // Resume updates if tab is active
    if (!document.hidden && !this.isPaused) {
      this.requestLatestStatus()
    }
    
    // Show success notification
    if (this.retryCountValue > 0) {
      this.showNotification("Reconexión exitosa", "success")
    }
  }
  
  handleDisconnected() {
    this.log("warn", "Disconnected from sync channel")
    
    this.connectionStateValue = "disconnected"
    this.updateConnectionStatus("Desconectado")
    
    // Attempt reconnection if not paused and not at max retries
    if (!this.isPaused && this.activeValue) {
      this.scheduleReconnect()
    }
  }
  
  handleRejected() {
    this.log("error", "Subscription rejected by server")
    
    this.connectionStateValue = "rejected"
    this.updateConnectionStatus("Conexión rechazada")
    
    // Show error and retry button
    this.showNotification("La conexión fue rechazada por el servidor", "error")
    this.showManualRetryButton()
  }
  
  handleConnectionError(error) {
    this.log("error", "Connection error", error)
    
    this.connectionStateValue = "error"
    this.updateConnectionStatus("Error de conexión")
    
    // Schedule reconnect with backoff
    this.scheduleReconnect()
  }
  
  // Reconnection logic with exponential backoff
  scheduleReconnect() {
    if (this.retryCountValue >= this.maxRetriesValue) {
      this.log("warn", "Max retries reached")
      this.showManualRetryButton()
      return
    }
    
    const delay = this.calculateBackoffDelay()
    this.log("info", `Scheduling reconnect in ${delay}ms`, {
      retryCount: this.retryCountValue,
      maxRetries: this.maxRetriesValue
    })
    
    this.updateConnectionStatus(`Reconectando en ${Math.round(delay / 1000)}s...`)
    
    // Clear existing timer if any
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
    }
    
    this.reconnectTimer = setTimeout(() => {
      this.retryCountValue++
      this.subscribeToChannel()
    }, delay)
  }
  
  calculateBackoffDelay() {
    // Exponential backoff with jitter to prevent thundering herd
    const baseDelay = Math.pow(2, this.retryCountValue) * 1000
    const jitter = Math.random() * 1000
    const totalDelay = baseDelay + jitter
    
    // Cap at 30 seconds
    return Math.min(totalDelay, 30000)
  }
  
  // Manual retry action
  manualRetry(event) {
    if (event) event.preventDefault()
    
    this.log("info", "Manual retry initiated")
    
    // Reset retry count and attempt connection
    this.retryCountValue = 0
    this.hideManualRetryButton()
    this.subscribeToChannel()
  }
  
  showManualRetryButton() {
    if (this.hasRetryButtonTarget) {
      this.retryButtonTarget.classList.remove('hidden')
    }
  }
  
  hideManualRetryButton() {
    if (this.hasRetryButtonTarget) {
      this.retryButtonTarget.classList.add('hidden')
    }
  }

  handleUpdate(data) {
    // Skip updates if paused
    if (this.isPaused) {
      this.log("debug", "Update skipped (paused)", data)
      return
    }
    
    // Track last update time
    this.lastUpdateTime = Date.now()
    
    // Cache the state for recovery
    this.cacheState(data)
    
    // Throttle UI updates to prevent performance issues
    this.throttledUIUpdate(data)
  }
  
  throttledUIUpdate(data) {
    // Add to update queue
    this.updateQueue.push(data)
    
    // Process queue if not already scheduled
    if (!this.updateThrottleTimer) {
      this.updateThrottleTimer = setTimeout(() => {
        this.processUpdateQueue()
        this.updateThrottleTimer = null
      }, 100) // Process updates every 100ms max
    }
  }
  
  processUpdateQueue() {
    if (this.updateQueue.length === 0) return
    
    // Process all queued updates
    const updates = [...this.updateQueue]
    this.updateQueue = []
    
    // Apply the most recent update of each type
    const latestByType = {}
    updates.forEach(update => {
      latestByType[update.type || 'status'] = update
    })
    
    // Apply updates
    Object.values(latestByType).forEach(data => {
      this.applyUpdate(data)
    })
  }
  
  applyUpdate(data) {
    // Update based on data type
    switch(data.type) {
      case 'initial_status':
        // Just update the UI, don't trigger any actions
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
        // General status update
        this.updateStatus(data)
    }
  }

  updateProgress(data) {
    // Update progress bar
    if (this.hasProgressBarTarget) {
      const percentage = data.progress_percentage || 0
      this.progressBarTarget.style.width = `${percentage}%`
    }

    // Update percentage text
    if (this.hasProgressPercentageTarget) {
      this.progressPercentageTarget.textContent = `${data.progress_percentage || 0}%`
    }

    // Update processed count
    if (this.hasProcessedCountTarget && data.processed_emails !== undefined) {
      this.processedCountTarget.textContent = this.formatNumber(data.processed_emails)
    }

    // Update detected expenses
    if (this.hasDetectedCountTarget && data.detected_expenses !== undefined) {
      this.detectedCountTarget.textContent = data.detected_expenses
    }

    // Update time remaining
    if (this.hasTimeRemainingTarget && data.time_remaining) {
      this.timeRemainingTarget.textContent = data.time_remaining
    }
  }

  updateAccount(data) {
    if (!this.hasAccountsListTarget) {
      return
    }

    const accountElement = this.accountsListTarget.querySelector(
      `[data-account-id="${data.account_id}"]`
    )
    
    if (accountElement) {
      // Update account status icon
      const statusIcon = accountElement.querySelector('[data-status-icon]')
      if (statusIcon) {
        this.updateStatusIcon(statusIcon, data.status)
      }

      // Update account progress
      const progressText = accountElement.querySelector('[data-progress-text]')
      if (progressText) {
        progressText.textContent = `${data.progress || 0}%`
      }

      const progressCount = accountElement.querySelector('[data-progress-count]')
      if (progressCount) {
        progressCount.textContent = `${data.processed || 0} / ${data.total || 0}`
      }
    }
  }

  updateStatus(data) {
    // Update all relevant fields from general status update
    if (data.status) {
      this.updateProgress(data)
      
      // Update accounts if provided
      if (data.accounts && Array.isArray(data.accounts)) {
        data.accounts.forEach(account => {
          // Map the account data to match what updateAccount expects
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

  logActivity(data) {
    // Could add a small activity indicator or toast notification
  }

  handleCompletion(data) {
    this.log("info", "Sync completed", data)
    
    // Mark as completed
    this.isCompleted = true
    
    // Update final progress to 100%
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = '100%'
    }
    if (this.hasProgressPercentageTarget) {
      this.progressPercentageTarget.textContent = '100%'
    }
    
    // Update final counts
    if (data.processed_emails !== undefined && this.hasProcessedCountTarget) {
      this.processedCountTarget.textContent = this.formatNumber(data.processed_emails)
    }
    if (data.detected_expenses !== undefined && this.hasDetectedCountTarget) {
      this.detectedCountTarget.textContent = data.detected_expenses
    }

    // Show completion message
    this.showNotification("Sincronización completada exitosamente", "success")
    
    // Clear cached state after completion
    setTimeout(() => {
      this.clearCachedState()
    }, 2000)
  }

  handleFailure(data) {
    // Show error state
    this.showNotification(`Error en sincronización: ${data.error || 'Error desconocido'}`, "error")
    
    // Update UI to show error state
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.classList.add('bg-rose-600')
      this.progressBarTarget.classList.remove('bg-teal-700')
    }
  }

  updateStatusIcon(element, status) {
    // Clear existing content
    element.innerHTML = ''
    
    switch(status) {
      case 'processing':
      case 'running':
        element.innerHTML = `
          <svg class="animate-spin h-4 w-4 text-teal-700" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        `
        break
      case 'completed':
        element.innerHTML = `
          <svg class="h-4 w-4 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
          </svg>
        `
        break
      case 'failed':
        element.innerHTML = `
          <svg class="h-4 w-4 text-rose-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        `
        break
      default:
        element.innerHTML = `<div class="h-4 w-4 rounded-full bg-slate-300"></div>`
    }
  }

  showNotification(message, type = 'info') {
    // Create toast notification
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 p-4 rounded-lg shadow-lg transition-all duration-300 ${
      type === 'success' ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' :
      type === 'error' ? 'bg-rose-50 text-rose-700 border border-rose-200' :
      'bg-slate-50 text-slate-700 border border-slate-200'
    }`
    notification.innerHTML = `
      <div class="flex items-center">
        <span>${message}</span>
        <button class="ml-4 text-current opacity-70 hover:opacity-100" onclick="this.parentElement.parentElement.remove()">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      notification.style.opacity = '0'
      setTimeout(() => notification.remove(), 300)
    }, 5000)
  }

  formatNumber(num) {
    return new Intl.NumberFormat('es-CR').format(num)
  }

  // Action to manually start sync
  startSync(event) {
    event.preventDefault()
    const form = event.currentTarget.closest('form')
    if (form) {
      form.submit()
    }
  }
  
  // Visibility handling for tab switching
  setupVisibilityHandling() {
    this.visibilityHandler = () => {
      if (document.hidden) {
        this.pauseUpdates()
      } else {
        this.resumeUpdates()
      }
    }
    
    document.addEventListener('visibilitychange', this.visibilityHandler)
  }
  
  pauseUpdates() {
    this.log("info", "Pausing updates (tab inactive)")
    
    this.isPaused = true
    
    // Notify server to pause updates
    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('pause_updates')
      } catch (error) {
        this.log("error", "Error pausing updates", error)
      }
    }
  }
  
  resumeUpdates() {
    this.log("info", "Resuming updates (tab active)")
    
    this.isPaused = false
    
    // Notify server to resume updates and get latest status
    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('resume_updates')
        this.requestLatestStatus()
      } catch (error) {
        this.log("error", "Error resuming updates", error)
      }
    } else if (this.connectionStateValue === "disconnected") {
      // Attempt to reconnect if disconnected
      this.scheduleReconnect()
    }
  }
  
  requestLatestStatus() {
    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('request_status')
      } catch (error) {
        this.log("error", "Error requesting status", error)
      }
    }
  }
  
  // Network monitoring
  setupNetworkMonitoring() {
    this.onlineHandler = () => this.handleOnline()
    this.offlineHandler = () => this.handleOffline()
    
    window.addEventListener('online', this.onlineHandler)
    window.addEventListener('offline', this.offlineHandler)
  }
  
  handleOffline() {
    this.log("warn", "Network offline")
    
    this.connectionStateValue = "offline"
    this.updateConnectionStatus("Sin conexión")
    
    // Pause updates while offline
    this.pauseUpdates()
    
    // Show offline notification
    this.showNotification("Sin conexión a internet", "warning")
  }
  
  handleOnline() {
    this.log("info", "Network online")
    
    this.connectionStateValue = "reconnecting"
    this.updateConnectionStatus("Reconectando...")
    
    // Show online notification
    this.showNotification("Conexión restaurada", "info")
    
    // Reset retry count for fresh attempt
    this.retryCountValue = 0
    
    // Resume updates
    this.resumeUpdates()
    
    // Attempt reconnection if not connected
    if (!this.subscription || this.connectionStateValue !== "connected") {
      this.scheduleReconnect()
    }
  }
  
  // State caching for recovery
  cacheState(data) {
    const cacheKey = `sync_state_${this.sessionIdValue}`
    const cacheData = {
      ...data,
      timestamp: Date.now(),
      sessionId: this.sessionIdValue
    }
    
    try {
      sessionStorage.setItem(cacheKey, JSON.stringify(cacheData))
    } catch (error) {
      this.log("error", "Error caching state", error)
    }
  }
  
  loadCachedState() {
    const cacheKey = `sync_state_${this.sessionIdValue}`
    
    try {
      const cached = sessionStorage.getItem(cacheKey)
      
      if (cached) {
        const data = JSON.parse(cached)
        const age = Date.now() - data.timestamp
        
        // Use cache if less than 5 minutes old
        if (age < 300000) {
          this.log("info", "Loading cached state", { age: Math.round(age / 1000) + "s" })
          
          // Apply cached state
          this.applyUpdate(data)
          
          // Show cache indicator
          this.showCacheIndicator()
        } else {
          // Clear stale cache
          this.clearCachedState()
        }
      }
    } catch (error) {
      this.log("error", "Error loading cached state", error)
    }
  }
  
  clearCachedState() {
    const cacheKey = `sync_state_${this.sessionIdValue}`
    
    try {
      sessionStorage.removeItem(cacheKey)
      this.log("debug", "Cached state cleared")
    } catch (error) {
      this.log("error", "Error clearing cache", error)
    }
  }
  
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
  
  // Connection status UI
  updateConnectionStatus(status) {
    if (this.hasConnectionStatusTarget) {
      this.connectionStatusTarget.textContent = status
      
      // Update status color based on state
      const colorClasses = {
        connected: 'text-emerald-600',
        connecting: 'text-amber-600',
        disconnected: 'text-rose-600',
        offline: 'text-slate-500',
        error: 'text-rose-600',
        rejected: 'text-rose-600'
      }
      
      // Remove all color classes
      Object.values(colorClasses).forEach(cls => {
        this.connectionStatusTarget.classList.remove(cls)
      })
      
      // Add appropriate color class
      const colorClass = colorClasses[this.connectionStateValue] || 'text-slate-600'
      this.connectionStatusTarget.classList.add(colorClass)
    }
  }
  
  // Debug logging
  log(level, message, data = {}) {
    if (this.debugValue || this.element.dataset.debug === 'true') {
      const timestamp = new Date().toISOString()
      const prefix = `[${timestamp}] SyncWidget:`
      
      if (data && Object.keys(data).length > 0) {
        console[level](prefix, message, data)
      } else {
        console[level](prefix, message)
      }
      
      // Send errors to server in production
      if (level === 'error' && window.Rails && window.Rails.env === 'production') {
        this.sendErrorToServer(message, data)
      }
    }
  }
  
  sendErrorToServer(message, data) {
    // Send error to server for monitoring
    const payload = {
      message,
      data,
      sessionId: this.sessionIdValue,
      timestamp: Date.now(),
      userAgent: navigator.userAgent,
      url: window.location.href
    }
    
    fetch('/api/client_errors', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
      },
      body: JSON.stringify(payload)
    }).catch(error => {
      // Silently fail if error reporting fails
      console.error('Failed to report error to server:', error)
    })
  }
}