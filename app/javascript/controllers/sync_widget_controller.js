import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Inline error messages to avoid import issues
const errorMessages = {
  getMessage(errorCode, category = null) {
    const messages = {
      connection: {
        failed: "No se pudo conectar al servidor. Verificando conexión...",
        lost: "Se perdió la conexión con el servidor",
        timeout: "La conexión tardó demasiado tiempo. Reintentando...",
        refused: "El servidor rechazó la conexión",
        network: "Error de red. Verifica tu conexión a internet",
        offline: "Sin conexión a internet",
        online: "Conexión restaurada",
        websocket_unsupported: "Tu navegador no soporta conexiones en tiempo real. Usando modo de actualización periódica.",
        degraded_mode: "Funcionando en modo limitado"
      },
      auth: {
        expired: "Tu sesión ha expirado. Por favor, recarga la página",
        unauthorized: "No tienes permisos para acceder a este recurso"
      },
      sync: {
        email_connection: "No se pudo conectar con el servidor de correo",
        email_auth: "Error de autenticación con el correo. Verifica tus credenciales",
        rate_limit: "Demasiadas solicitudes. Esperando antes de continuar...",
        parsing_error: "Error al procesar los correos electrónicos",
        duplicate_detected: "Se detectaron transacciones duplicadas",
        no_emails: "No se encontraron correos nuevos para sincronizar",
        processing_error: "Error al procesar las transacciones"
      },
      server: {
        internal: "Error interno del servidor. El equipo ha sido notificado",
        unavailable: "Servicio temporalmente no disponible"
      },
      recovery: {
        retry_in: "Reintentando en %{seconds} segundos",
        max_retries: "Se alcanzó el máximo de intentos",
        recovered: "Conexión recuperada exitosamente",
        switching_mode: "Cambiando a modo de actualización periódica"
      },
      actions: {
        reload: "Recargar página"
      },
      status: {
        connecting: "Conectando...",
        connected: "Conectado",
        disconnected: "Desconectado",
        reconnecting: "Reconectando...",
        failed: "Error"
      }
    };

    if (category && messages[category] && messages[category][errorCode]) {
      return messages[category][errorCode];
    }

    // Search all categories
    for (const cat in messages) {
      if (messages[cat][errorCode]) {
        return messages[cat][errorCode];
      }
    }

    return "Ocurrió un error inesperado.";
  },

  getAction(action) {
    const actions = {
      reload: "Recargar página",
      retry: "Reintentar"
    };
    return actions[action] || action;
  },

  getStatus(status) {
    const statuses = {
      connecting: "Conectando...",
      connected: "Conectado",
      disconnected: "Desconectado",
      reconnecting: "Reconectando...",
      failed: "Error"
    };
    return statuses[status] || status;
  },

  getSuggestion(errorType) {
    const suggestions = {
      network: "Verifica tu conexión a internet e intenta de nuevo.",
      auth: "Por favor, recarga la página e inicia sesión nuevamente.",
      server: "El problema es temporal. Intenta de nuevo en unos minutos.",
      email: "Verifica que las credenciales del correo sean correctas."
    };
    return suggestions[errorType] || "";
  },

  format(message, params = {}) {
    let formatted = message;
    for (const key in params) {
      const placeholder = `%{${key}}`;
      formatted = formatted.replace(placeholder, params[key]);
    }
    return formatted;
  }
};

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
    "connectionMessage"
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
    this.pollingTimer = null
    this.pollingMode = false
    this.errorCount = 0
    this.lastError = null
    
    // Setup event handlers
    this.setupVisibilityHandling()
    this.setupNetworkMonitoring()
    this.setupToastNotifications()
    
    // Load cached state if available
    this.loadCachedState()
    
    // Check WebSocket support
    if (!this.isWebSocketSupported()) {
      this.enablePollingMode()
    } else if (this.activeValue && this.sessionIdValue) {
      // Start subscription if active
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
    
    // Clear polling timer
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer)
      this.pollingTimer = null
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
    // Check if in polling mode
    if (this.pollingMode) {
      this.log("info", "In polling mode, skipping WebSocket connection")
      return
    }
    
    // Prevent multiple subscription attempts
    if (this.connectionStateValue === "connecting") {
      this.log("warn", "Already attempting to connect")
      return
    }
    
    this.connectionStateValue = "connecting"
    this.updateConnectionStatus(errorMessages.getStatus("connecting"))
    
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
    
    // Reset error tracking
    this.errorCount = 0
    this.lastError = null
    
    // Reset retry count on successful connection
    const wasReconnecting = this.retryCountValue > 0
    this.retryCountValue = 0
    this.connectionStateValue = "connected"
    this.updateConnectionStatus(errorMessages.getStatus("connected"))
    
    // Resume updates if tab is active
    if (!document.hidden && !this.isPaused) {
      this.requestLatestStatus()
    }
    
    // Show success notification for reconnection
    if (wasReconnecting) {
      this.showToast(errorMessages.getMessage("recovered", "recovery"), "success")
    }
  }
  
  handleDisconnected() {
    this.log("warn", "Disconnected from sync channel")
    
    this.connectionStateValue = "disconnected"
    this.updateConnectionStatus(errorMessages.getStatus("disconnected"))
    
    // Show disconnection notification
    this.showToast(errorMessages.getMessage("lost", "connection"), "warning")
    
    // Attempt reconnection if not paused and not at max retries
    if (!this.isPaused && this.activeValue) {
      this.scheduleReconnect()
    }
  }
  
  handleRejected() {
    this.log("error", "Subscription rejected by server")
    
    this.connectionStateValue = "rejected"
    this.updateConnectionStatus(errorMessages.getMessage("refused", "connection"))
    
    // Determine specific rejection reason
    const errorType = this.determineRejectionReason()
    const message = this.getErrorMessage(errorType)
    const suggestion = errorMessages.getSuggestion(errorType)
    
    // Show error with suggestion
    this.showToast(
      `${message}${suggestion ? '. ' + suggestion : ''}`,
      "error",
      null,
      () => window.location.reload(),
      errorMessages.getAction("reload")
    )
    
    this.showManualRetryButton()
  }
  
  handleConnectionError(error) {
    this.log("error", "Connection error", error)
    
    this.errorCount++
    this.lastError = error
    this.connectionStateValue = "error"
    
    // Analyze error and provide specific feedback
    const errorInfo = this.analyzeError(error)
    this.updateConnectionStatus(errorInfo.status)
    
    // Show appropriate error message
    if (this.errorCount === 1) {
      this.showToast(errorInfo.message, "error")
    }
    
    // Check if we should fallback to polling
    if (this.shouldFallbackToPolling(error)) {
      this.enablePollingMode()
    } else {
      // Schedule reconnect with backoff
      this.scheduleReconnect()
    }
  }
  
  // Reconnection logic with exponential backoff
  scheduleReconnect() {
    if (this.retryCountValue >= this.maxRetriesValue) {
      this.log("warn", "Max retries reached")
      
      // Show max retries message and offer alternatives
      this.showToast(
        errorMessages.getMessage("max_retries", "recovery"),
        "error",
        null,
        () => this.enablePollingMode(),
        errorMessages.getMessage("switching_mode", "recovery")
      )
      
      this.showManualRetryButton()
      return
    }
    
    const delay = this.calculateBackoffDelay()
    const seconds = Math.round(delay / 1000)
    
    this.log("info", `Scheduling reconnect in ${delay}ms`, {
      retryCount: this.retryCountValue,
      maxRetries: this.maxRetriesValue
    })
    
    const statusMessage = errorMessages.format(
      errorMessages.getMessage("retry_in", "recovery"),
      { seconds }
    )
    this.updateConnectionStatus(statusMessage)
    
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
    const percentage = data.progress_percentage || 0
    
    // Update progress bar
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percentage}%`
    }

    // Update progress indicator line
    if (this.hasProgressIndicatorTarget) {
      this.progressIndicatorTarget.style.left = `${percentage}%`
    }

    // Update percentage text
    if (this.hasProgressPercentageTarget) {
      this.progressPercentageTarget.textContent = `${percentage}%`
    }

    // Update processed count
    if (this.hasProcessedCountTarget && data.processed_emails !== undefined) {
      this.processedCountTarget.textContent = this.formatNumber(data.processed_emails)
    }

    // Update detected expenses
    if (this.hasDetectedCountTarget && data.detected_expenses !== undefined) {
      this.detectedCountTarget.textContent = data.detected_expenses
    }

    // Update error count
    if (this.hasErrorCountTarget && data.error_count !== undefined) {
      this.errorCountTarget.textContent = data.error_count
      
      // Highlight errors if present
      if (data.error_count > 0) {
        this.errorCountTarget.classList.add('text-rose-600')
        this.errorCountTarget.classList.remove('text-slate-600')
      }
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

    // Show completion message with summary
    const message = `Sincronización completada: ${data.detected_expenses || 0} gastos detectados de ${data.processed_emails || 0} correos`
    this.showToast(message, "success", 7000)
    
    // Clear cached state after completion
    setTimeout(() => {
      this.clearCachedState()
    }, 2000)
  }

  handleFailure(data) {
    // Parse error details
    const error = {
      code: data.error_code,
      type: data.error_type,
      message: data.error,
      details: data.error_details
    }
    
    // Use enhanced error handling
    this.handleSyncError(error)
    
    // Update UI to show error state
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.classList.add('bg-rose-600')
      this.progressBarTarget.classList.remove('bg-teal-700')
    }
    
    // Show retry option for recoverable errors
    const errorInfo = this.analyzeError(error)
    if (errorInfo.recoverable) {
      this.showManualRetryButton()
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

  // Toast notification system integration
  setupToastNotifications() {
    // Initialize toast controller if not already present
    if (!document.querySelector('[data-controller="toast"]')) {
      const toastContainer = document.createElement('div')
      toastContainer.dataset.controller = 'toast'
      toastContainer.dataset.toastPositionValue = 'top-right'
      document.body.appendChild(toastContainer)
    }
  }

  showToast(message, type = 'info', duration = null, action = null, actionText = null) {
    // Dispatch custom event for toast controller
    const event = new CustomEvent('toast:show', {
      detail: {
        message,
        type,
        duration,
        action,
        actionText
      }
    })
    document.dispatchEvent(event)
  }

  showNotification(message, type = 'info') {
    // Delegate to toast system
    this.showToast(message, type)
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

  // Action to toggle pause/resume
  togglePause(event) {
    event.preventDefault()
    
    if (this.isPaused) {
      this.resumeSync()
    } else {
      this.pauseSync()
    }
  }

  pauseSync() {
    this.isPaused = true
    
    // Update button UI
    if (this.hasPauseButtonTarget) {
      this.pauseButtonTarget.innerHTML = `
        <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"></path>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        Reanudar
      `
      this.pauseButtonTarget.classList.add('bg-amber-50', 'border-amber-300', 'text-amber-700')
      this.pauseButtonTarget.classList.remove('bg-white', 'border-slate-300', 'text-slate-700')
    }
    
    // Update status text
    if (this.hasStatusTextTarget) {
      this.statusTextTarget.innerHTML = `
        <span class="inline-flex items-center">
          <span class="w-2 h-2 bg-amber-500 rounded-full mr-2"></span>
          Sincronización pausada
        </span>
      `
    }
    
    // Send pause command to server
    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('pause_sync')
      } catch (error) {
        this.log("error", "Error pausing sync", error)
      }
    }
    
    this.showToast("Sincronización pausada", "info")
  }

  resumeSync() {
    this.isPaused = false
    
    // Update button UI
    if (this.hasPauseButtonTarget) {
      this.pauseButtonTarget.innerHTML = `
        <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        Pausar
      `
      this.pauseButtonTarget.classList.remove('bg-amber-50', 'border-amber-300', 'text-amber-700')
      this.pauseButtonTarget.classList.add('bg-white', 'border-slate-300', 'text-slate-700')
    }
    
    // Update status text
    if (this.hasStatusTextTarget) {
      this.statusTextTarget.innerHTML = `
        <span class="inline-flex items-center">
          <span class="w-2 h-2 bg-emerald-500 rounded-full mr-2 animate-pulse"></span>
          Sincronización en progreso
        </span>
      `
    }
    
    // Send resume command to server
    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('resume_sync')
        this.requestLatestStatus()
      } catch (error) {
        this.log("error", "Error resuming sync", error)
      }
    }
    
    this.showToast("Sincronización reanudada", "success")
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
    this.updateConnectionStatus(errorMessages.getMessage("offline", "connection"))
    
    // Pause updates while offline
    this.pauseUpdates()
    
    // Show offline notification
    this.showToast(errorMessages.getMessage("offline", "connection"), "warning")
  }
  
  handleOnline() {
    this.log("info", "Network online")
    
    this.connectionStateValue = "reconnecting"
    this.updateConnectionStatus(errorMessages.getStatus("reconnecting"))
    
    // Show online notification
    this.showToast(errorMessages.getMessage("online", "connection"), "info")
    
    // Reset retry count for fresh attempt
    this.retryCountValue = 0
    
    // Resume updates
    this.resumeUpdates()
    
    // Attempt reconnection if not connected
    if (!this.pollingMode && (!this.subscription || this.connectionStateValue !== "connected")) {
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
    
    // Update connection warning section
    if (this.hasConnectionWarningTarget && this.hasConnectionMessageTarget) {
      const showWarning = ['disconnected', 'connecting', 'offline', 'error', 'rejected'].includes(this.connectionStateValue)
      
      if (showWarning) {
        this.connectionWarningTarget.classList.remove('hidden')
        this.connectionMessageTarget.textContent = status
        
        // Update warning colors based on severity
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
      url: window.location.href,
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
    }).catch(error => {
      // Silently fail if error reporting fails
      console.error('Failed to report error to server:', error)
    })
  }

  // WebSocket support detection
  isWebSocketSupported() {
    try {
      // Check for WebSocket support
      if (!window.WebSocket && !window.MozWebSocket) {
        this.log("warn", "WebSocket not supported by browser")
        return false
      }
      
      // Check if WebSocket is blocked (corporate firewall, etc)
      // This is a heuristic - if we can't create a WebSocket object, it might be blocked
      const testWs = new WebSocket('wss://echo.websocket.org/')
      testWs.close()
      
      return true
    } catch (error) {
      this.log("warn", "WebSocket appears to be blocked", error)
      return false
    }
  }

  // Enable polling mode as fallback
  enablePollingMode() {
    if (this.pollingMode) {
      return // Already in polling mode
    }
    
    this.log("info", "Enabling polling mode")
    this.pollingMode = true
    
    // Show notification about degraded mode
    this.showToast(
      errorMessages.getMessage("websocket_unsupported", "connection"),
      "warning",
      10000 // Show for 10 seconds
    )
    
    // Update UI to show polling mode
    this.updateConnectionStatus(errorMessages.getMessage("degraded_mode", "recovery"))
    this.showPollingIndicator()
    
    // Start polling if active
    if (this.activeValue && this.sessionIdValue) {
      this.startPolling()
    }
  }

  // Start polling for updates
  startPolling() {
    if (this.pollingTimer) {
      return // Already polling
    }
    
    // Poll every 5 seconds when sync is active
    const pollInterval = this.activeValue ? 5000 : 30000
    
    this.log("info", `Starting polling with ${pollInterval}ms interval`)
    
    // Initial poll
    this.pollForUpdates()
    
    // Set up recurring poll
    this.pollingTimer = setInterval(() => {
      if (!this.isPaused && this.activeValue) {
        this.pollForUpdates()
      }
    }, pollInterval)
  }

  // Stop polling
  stopPolling() {
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer)
      this.pollingTimer = null
      this.log("info", "Stopped polling")
    }
  }

  // Poll for updates via HTTP
  async pollForUpdates() {
    if (!this.sessionIdValue) return
    
    try {
      const response = await fetch(`/api/sync_sessions/${this.sessionIdValue}/status`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        this.handleUpdate(data)
        
        // Reset error count on successful poll
        this.errorCount = 0
      } else {
        throw new Error(`HTTP ${response.status}`)
      }
    } catch (error) {
      this.log("error", "Polling error", error)
      this.errorCount++
      
      // Show error after multiple failures
      if (this.errorCount > 3) {
        this.showToast(
          errorMessages.getMessage("unavailable", "server"),
          "error"
        )
        
        // Stop polling after too many errors
        if (this.errorCount > 10) {
          this.stopPolling()
          this.showManualRetryButton()
        }
      }
    }
  }

  // Show polling mode indicator
  showPollingIndicator() {
    const indicator = document.createElement('div')
    indicator.id = 'polling-indicator'
    indicator.className = 'fixed bottom-4 left-4 px-3 py-2 bg-amber-100 text-amber-700 rounded-lg text-sm flex items-center space-x-2 shadow-sm border border-amber-200'
    indicator.innerHTML = `
      <svg class="animate-pulse h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
      </svg>
      <span>Modo de actualización periódica</span>
    `
    
    // Remove existing indicator if present
    const existing = document.getElementById('polling-indicator')
    if (existing) existing.remove()
    
    document.body.appendChild(indicator)
  }

  // Analyze error to determine type and appropriate response
  analyzeError(error) {
    const errorString = error?.toString() || ''
    const errorMessage = error?.message || ''
    
    // Check for specific error types
    if (errorString.includes('NetworkError') || errorString.includes('ERR_NETWORK')) {
      return {
        type: 'network',
        message: errorMessages.getMessage('network', 'connection'),
        status: errorMessages.getMessage('offline', 'connection'),
        recoverable: true
      }
    }
    
    if (errorString.includes('SecurityError') || errorString.includes('ERR_CERT')) {
      return {
        type: 'ssl',
        message: errorMessages.getMessage('ssl', 'connection'),
        status: 'Error SSL',
        recoverable: false
      }
    }
    
    if (errorMessage.includes('401') || errorMessage.includes('Unauthorized')) {
      return {
        type: 'auth',
        message: errorMessages.getMessage('expired', 'auth'),
        status: errorMessages.getMessage('unauthorized', 'auth'),
        recoverable: false
      }
    }
    
    if (errorMessage.includes('500') || errorMessage.includes('Internal')) {
      return {
        type: 'server',
        message: errorMessages.getMessage('internal', 'server'),
        status: errorMessages.getMessage('unavailable', 'server'),
        recoverable: true
      }
    }
    
    // Default error
    return {
      type: 'unknown',
      message: errorMessages.getMessage('failed', 'connection'),
      status: errorMessages.getStatus('failed'),
      recoverable: true
    }
  }

  // Determine if we should fallback to polling based on error
  shouldFallbackToPolling(error) {
    // Fallback after multiple WebSocket errors
    if (this.errorCount > 3) {
      return true
    }
    
    // Fallback for specific error types
    const errorInfo = this.analyzeError(error)
    if (errorInfo.type === 'ssl' || !errorInfo.recoverable) {
      return true
    }
    
    return false
  }

  // Determine reason for connection rejection
  determineRejectionReason() {
    // Check various conditions to determine why connection was rejected
    const currentTime = Date.now()
    const sessionAge = currentTime - (this.element.dataset.sessionCreatedAt || currentTime)
    
    // Session too old (> 24 hours)
    if (sessionAge > 86400000) {
      return 'auth'
    }
    
    // Check if we have proper authentication
    if (!document.querySelector('[name="csrf-token"]')?.content) {
      return 'auth'
    }
    
    // Default to auth issue
    return 'auth'
  }

  // Get appropriate error message based on error type
  getErrorMessage(errorType) {
    return errorMessages.getMessage(errorType === 'auth' ? 'expired' : 'refused', errorType)
  }

  // Enhanced UI update for sync-specific errors
  handleSyncError(error) {
    const errorCode = error.code || error.type || 'unknown'
    
    // Map sync error codes to user messages
    const syncErrorMap = {
      'email_connection': errorMessages.getMessage('email_connection', 'sync'),
      'email_auth': errorMessages.getMessage('email_auth', 'sync'),
      'rate_limit': errorMessages.getMessage('rate_limit', 'sync'),
      'parsing_error': errorMessages.getMessage('parsing_error', 'sync'),
      'duplicate': errorMessages.getMessage('duplicate_detected', 'sync'),
      'no_emails': errorMessages.getMessage('no_emails', 'sync'),
      'quota_exceeded': errorMessages.getMessage('quota_exceeded', 'sync')
    }
    
    const message = syncErrorMap[errorCode] || errorMessages.getMessage('processing_error', 'sync')
    const suggestion = errorMessages.getSuggestion(errorCode.includes('email') ? 'email' : 'server')
    
    // Show error with appropriate severity
    const severity = errorCode === 'rate_limit' || errorCode === 'quota_exceeded' ? 'warning' : 'error'
    this.showToast(`${message}. ${suggestion}`, severity, 8000)
    
    // Log for debugging
    this.log('error', `Sync error: ${errorCode}`, error)
    
    // Send to server for monitoring
    this.sendErrorToServer(`Sync error: ${errorCode}`, error)
  }
}