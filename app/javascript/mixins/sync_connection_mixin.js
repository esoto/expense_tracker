import { getSharedConsumer, resetSharedConsumer } from "services/sync_cable_consumer"
import errorMessages from "services/error_messages"
import { SyncErrorClassifier } from "services/sync_error_classifier"

/**
 * syncConnectionMixin — connection management, reconnection, polling,
 * visibility handling, and network monitoring for the sync widget controller.
 *
 * Mixed into SyncWidgetController via:
 *   Object.assign(SyncWidgetController.prototype, syncConnectionMixin)
 *
 * All methods reference `this.*` from the host controller (targets, values, etc.)
 * since the mixin is merged onto the prototype at class definition time.
 */
export const syncConnectionMixin = {
  // ---------------------------------------------------------------------------
  // Channel subscription
  // ---------------------------------------------------------------------------

  subscribeToChannel() {
    if (this.pollingMode) {
      this.log("info", "In polling mode, skipping WebSocket connection")
      return
    }

    if (this.connectionStateValue === "connecting") {
      this.log("warn", "Already attempting to connect")
      return
    }

    this.connectionStateValue = "connecting"
    this.updateConnectionStatus(errorMessages.getStatus("connecting"))

    if (!this.consumer) {
      this.consumer = getSharedConsumer()
    }

    try {
      this.subscription = this.consumer.subscriptions.create(
        {
          channel: "SyncStatusChannel",
          session_id: this.sessionIdValue
        },
        {
          connected: () => this.handleConnected(),
          disconnected: () => this.handleDisconnected(),
          received: (data) => this.handleUpdate(data),
          rejected: () => this.handleRejected()
        }
      )
    } catch (error) {
      this.log("error", "Error creating subscription", error)
      this.handleConnectionError(error)
    }
  },

  // ---------------------------------------------------------------------------
  // Connection event handlers
  // ---------------------------------------------------------------------------

  handleConnected() {
    this.log("info", "Connected to sync channel")

    this.errorCount = 0
    this.lastError = null

    const wasReconnecting = this.retryCountValue > 0
    this.retryCountValue = 0
    this.connectionStateValue = "connected"
    this.updateConnectionStatus(errorMessages.getStatus("connected"))

    if (!document.hidden && !this.isPaused) {
      this.requestLatestStatus()
    }

    if (wasReconnecting) {
      this.showToast(errorMessages.getMessage("recovered", "recovery"), "success")
    }
  },

  handleDisconnected() {
    this.log("warn", "Disconnected from sync channel")

    this.connectionStateValue = "disconnected"
    this.updateConnectionStatus(errorMessages.getStatus("disconnected"))

    this.showToast(errorMessages.getMessage("lost", "connection"), "warning")

    if (!this.isPaused && this.activeValue) {
      this.scheduleReconnect()
    }
  },

  handleRejected() {
    this.log("error", "Subscription rejected by server")

    this.connectionStateValue = "rejected"
    this.updateConnectionStatus(errorMessages.getMessage("refused", "connection"))

    const errorType = SyncErrorClassifier.determineRejectionReason(this.element)
    const message = SyncErrorClassifier.getErrorMessage(errorType)
    const suggestion = errorMessages.getSuggestion(errorType)

    this.showToast(
      `${message}${suggestion ? '. ' + suggestion : ''}`,
      "error",
      null,
      () => window.location.reload(),
      errorMessages.getAction("reload")
    )

    this.showManualRetryButton()
  },

  handleConnectionError(error) {
    this.log("error", "Connection error", error)

    this.errorCount++
    this.lastError = error
    this.connectionStateValue = "error"

    const errorInfo = SyncErrorClassifier.analyzeError(error)
    this.updateConnectionStatus(errorInfo.status)

    if (this.errorCount === 1) {
      this.showToast(errorInfo.message, "error")
    }

    if (this.shouldFallbackToPolling(error)) {
      this.enablePollingMode()
    } else {
      this.scheduleReconnect()
    }
  },

  // ---------------------------------------------------------------------------
  // Reconnection with exponential backoff
  // ---------------------------------------------------------------------------

  scheduleReconnect() {
    if (this.retryCountValue >= this.maxRetriesValue) {
      this.log("warn", "Max retries reached")

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

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
    }

    this.reconnectTimer = setTimeout(() => {
      this.retryCountValue++
      if (this.subscription) {
        try { this.subscription.unsubscribe() } catch (_) {}
        this.subscription = null
      }
      resetSharedConsumer()
      this.consumer = null
      this.subscribeToChannel()
    }, delay)
  },

  calculateBackoffDelay() {
    const baseDelay = Math.pow(2, this.retryCountValue) * 1000
    const jitter = Math.random() * 1000
    return Math.min(baseDelay + jitter, 30000)
  },

  // ---------------------------------------------------------------------------
  // Manual retry
  // ---------------------------------------------------------------------------

  manualRetry(event) {
    if (event) event.preventDefault()

    this.log("info", "Manual retry initiated")

    if (this.subscription) {
      try { this.subscription.unsubscribe() } catch (_) {}
      this.subscription = null
    }
    resetSharedConsumer()
    this.consumer = null
    this.retryCountValue = 0
    this.hideManualRetryButton()
    this.subscribeToChannel()
  },

  showManualRetryButton() {
    if (this.hasRetryButtonTarget) {
      this.retryButtonTarget.classList.remove('hidden')
    }
  },

  hideManualRetryButton() {
    if (this.hasRetryButtonTarget) {
      this.retryButtonTarget.classList.add('hidden')
    }
  },

  // ---------------------------------------------------------------------------
  // Visibility handling (tab switching)
  // ---------------------------------------------------------------------------

  setupVisibilityHandling() {
    this.visibilityHandler = () => {
      if (document.hidden) {
        this.pauseUpdates()
      } else {
        this.resumeUpdates()
      }
    }

    document.addEventListener('visibilitychange', this.visibilityHandler)
  },

  /**
   * Called when the tab becomes hidden.
   * Sets visibilityPaused — does NOT touch userPaused (fixes PER-359).
   */
  pauseUpdates() {
    this.log("info", "Pausing updates (tab inactive)")

    this.visibilityPaused = true

    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('pause_updates')
      } catch (error) {
        this.log("error", "Error pausing updates", error)
      }
    }
  },

  /**
   * Called when the tab becomes visible.
   * Clears visibilityPaused — does NOT clear userPaused (fixes PER-359).
   */
  resumeUpdates() {
    this.log("info", "Resuming updates (tab active)")

    this.visibilityPaused = false

    // Only perform server call if the user hasn't explicitly paused
    if (!this.userPaused) {
      if (this.subscription && this.connectionStateValue === "connected") {
        try {
          this.subscription.perform('resume_updates')
          this.requestLatestStatus()
        } catch (error) {
          this.log("error", "Error resuming updates", error)
        }
      } else if (this.connectionStateValue === "disconnected") {
        this.scheduleReconnect()
      }
    }
  },

  requestLatestStatus() {
    if (this.subscription && this.connectionStateValue === "connected") {
      try {
        this.subscription.perform('request_status')
      } catch (error) {
        this.log("error", "Error requesting status", error)
      }
    }
  },

  // ---------------------------------------------------------------------------
  // Network monitoring
  // ---------------------------------------------------------------------------

  setupNetworkMonitoring() {
    this.onlineHandler = () => this.handleOnline()
    this.offlineHandler = () => this.handleOffline()

    window.addEventListener('online', this.onlineHandler)
    window.addEventListener('offline', this.offlineHandler)
  },

  handleOffline() {
    this.log("warn", "Network offline")

    this.connectionStateValue = "offline"
    this.updateConnectionStatus(errorMessages.getMessage("offline", "connection"))

    this.pauseUpdates()
    this.showToast(errorMessages.getMessage("offline", "connection"), "warning")
  },

  handleOnline() {
    const wasConnected = this.connectionStateValue === "connected"

    this.log("info", "Network online")
    this.connectionStateValue = "reconnecting"
    this.updateConnectionStatus(errorMessages.getStatus("reconnecting"))

    this.showToast(errorMessages.getMessage("online", "connection"), "info")

    this.retryCountValue = 0
    this.resumeUpdates()

    if (!this.pollingMode && !wasConnected) {
      this.scheduleReconnect()
    }
  },

  // ---------------------------------------------------------------------------
  // WebSocket support + polling fallback
  // ---------------------------------------------------------------------------

  isWebSocketSupported() {
    try {
      return 'WebSocket' in window && window.WebSocket !== undefined
    } catch (_) {
      return false
    }
  },

  enablePollingMode() {
    if (this.pollingMode) return

    this.log("info", "Enabling polling mode")
    this.pollingMode = true

    this.showToast(
      errorMessages.getMessage("websocket_unsupported", "connection"),
      "warning",
      10000
    )

    this.updateConnectionStatus(errorMessages.getMessage("degraded_mode", "recovery"))
    this.showPollingIndicator()

    if (this.activeValue && this.sessionIdValue) {
      this.startPolling()
    }
  },

  startPolling() {
    if (this.pollingTimer) return

    const pollInterval = this.activeValue ? 5000 : 30000
    this.log("info", `Starting polling with ${pollInterval}ms interval`)

    this.pollForUpdates()

    this.pollingTimer = setInterval(() => {
      if (!this.isPaused && this.activeValue) {
        this.pollForUpdates()
      }
    }, pollInterval)
  },

  stopPolling() {
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer)
      this.pollingTimer = null
      this.log("info", "Stopped polling")
    }
    // Clean up polling indicator element if present
    document.getElementById('polling-indicator')?.remove()
  },

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
        this.errorCount = 0

        // PER-360: stop polling when sync reaches a terminal state
        if (data.status === 'completed' || data.status === 'failed') {
          this.stopPolling()
        }
      } else {
        throw new Error(`HTTP ${response.status}`)
      }
    } catch (error) {
      this.log("error", "Polling error", error)
      this.errorCount++

      if (this.errorCount > 3) {
        this.showToast(
          errorMessages.getMessage("unavailable", "server"),
          "error"
        )

        if (this.errorCount > 10) {
          this.stopPolling()
          this.showManualRetryButton()
        }
      }
    }
  },

  showPollingIndicator() {
    const indicator = document.createElement('div')
    indicator.id = 'polling-indicator'
    indicator.className = 'fixed bottom-4 left-4 px-3 py-2 bg-amber-100 text-amber-700 rounded-lg text-sm flex items-center space-x-2 shadow-sm border border-amber-200'

    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('aria-hidden', 'true')
    svg.setAttribute('class', 'animate-pulse h-4 w-4')
    svg.setAttribute('fill', 'none')
    svg.setAttribute('stroke', 'currentColor')
    svg.setAttribute('viewBox', '0 0 24 24')
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    path.setAttribute('stroke-linecap', 'round')
    path.setAttribute('stroke-linejoin', 'round')
    path.setAttribute('stroke-width', '2')
    path.setAttribute('d', 'M13 10V3L4 14h7v7l9-11h-7z')
    svg.appendChild(path)

    const textSpan = document.createElement('span')
    textSpan.textContent = 'Modo de actualización periódica'

    const existing = document.getElementById('polling-indicator')
    if (existing) existing.remove()

    indicator.appendChild(svg)
    indicator.appendChild(textSpan)
    document.body.appendChild(indicator)
  },

  // ---------------------------------------------------------------------------
  // Error analysis helpers (delegates to SyncErrorClassifier)
  // ---------------------------------------------------------------------------

  analyzeError(error) {
    return SyncErrorClassifier.analyzeError(error)
  },

  shouldFallbackToPolling(error) {
    if (this.errorCount > 3) return true
    const errorInfo = SyncErrorClassifier.analyzeError(error)
    return errorInfo.type === 'ssl' || !errorInfo.recoverable
  }
}
