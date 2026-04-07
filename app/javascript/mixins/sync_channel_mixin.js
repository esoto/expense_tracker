import { getSharedConsumer } from "services/sync_cable_consumer"

/**
 * Shared mixin for sync channel Stimulus controllers.
 *
 * Extracts the duplicated ActionCable subscription setup, message dispatch,
 * status update, and DOM notification code that was copy-pasted across
 * sync_sessions_controller and sync_session_detail_controller.
 *
 * Usage:
 *   import { syncChannelMixin } from "mixins/sync_channel_mixin"
 *   // after class definition:
 *   Object.assign(MyController.prototype, syncChannelMixin)
 *
 * Each controller MUST implement its own:
 *   - updateProgress(data)
 *   - updateAccount(data)
 *   - handleCompletion(data)
 *   - handleFailure(data)
 *
 * Each controller MAY override:
 *   - updateStatus(data) — default calls updateProgress + updateAccount per account
 *   - showNotification(message, type) — default builds a DOM toast
 */

export const syncChannelMixin = {
  /**
   * Create an ActionCable subscription to SyncStatusChannel for the given session.
   * Expects `this.sessionIdValue` to be set by the Stimulus controller.
   */
  subscribeToChannel() {
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
          connected: () => {
            this.showNotification('Conectado al servidor', 'success')
          },

          disconnected: () => {
            this.showNotification('Conexión perdida con el servidor', 'error')
          },

          received: (data) => {
            this.handleUpdate(data)
          },

          rejected: () => {
            this.showNotification('Conexión rechazada por el servidor', 'error')
          }
        }
      )
    } catch (error) {
      console.error("Error creating subscription:", error)
    }
  },

  /**
   * Unsubscribe from the channel and release references.
   * Call from the controller's disconnect() lifecycle hook.
   */
  disconnectChannel() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    // Release consumer reference (shared consumer stays alive for other controllers)
    this.consumer = null
  },

  /**
   * Route incoming messages to the appropriate handler based on data.type.
   * Controllers override updateProgress/updateAccount/handleCompletion/handleFailure
   * to provide their own DOM updates.
   */
  handleUpdate(data) {
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
      case 'completed':
        this.handleCompletion(data)
        break
      case 'failed':
        this.handleFailure(data)
        break
      case 'batch_update':
        if (data.updates && Array.isArray(data.updates)) {
          data.updates.forEach(update => this.applyUpdate ? this.applyUpdate(update) : this.handleUpdate(update))
        }
        break
      case 'status_update':
        // Normalize account shape: server uses 'id', client expects 'account_id'
        if (data.accounts && Array.isArray(data.accounts)) {
          data.accounts.forEach(account => {
            this.updateAccount({
              account_id: account.id || account.account_id,
              status: account.status,
              progress: account.progress,
              processed: account.processed,
              total: account.total
            })
          })
        }
        if (data.status) this.updateProgress(data)
        break
      default:
        this.updateStatus(data)
    }
  },

  /**
   * Default status handler — updates progress and iterates over accounts.
   * Controllers can override if they need different behavior.
   */
  updateStatus(data) {
    if (data.status) {
      this.updateProgress(data)

      if (data.accounts && Array.isArray(data.accounts)) {
        data.accounts.forEach(account => {
          this.updateAccount(account)
        })
      }
    }
  },

  /**
   * Display a transient notification banner.
   * Builds a DOM element with close button and auto-dismiss after 5 seconds.
   * Uses the Financial Confidence palette (emerald/rose/slate).
   */
  showNotification(message, type = 'info') {
    const existing = document.querySelector('[data-sync-notification]')
    if (existing) existing.remove()

    const notification = document.createElement('div')
    notification.dataset.syncNotification = ''
    notification.className = `fixed top-4 right-4 z-50 p-4 rounded-lg shadow-lg transition-all duration-300 ${
      type === 'success' ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' :
      type === 'error' ? 'bg-rose-50 text-rose-700 border border-rose-200' :
      'bg-slate-50 text-slate-700 border border-slate-200'
    }`
    const flexDiv = document.createElement('div')
    flexDiv.className = 'flex items-center'
    const messageSpan = document.createElement('span')
    messageSpan.textContent = message
    const closeBtn = document.createElement('button')
    closeBtn.className = 'ml-4 text-current opacity-70 hover:opacity-100'
    closeBtn.addEventListener('click', () => notification.remove())
    const closeSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    closeSvg.setAttribute('class', 'w-4 h-4')
    closeSvg.setAttribute('fill', 'none')
    closeSvg.setAttribute('stroke', 'currentColor')
    closeSvg.setAttribute('viewBox', '0 0 24 24')
    const closePath = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    closePath.setAttribute('stroke-linecap', 'round')
    closePath.setAttribute('stroke-linejoin', 'round')
    closePath.setAttribute('stroke-width', '2')
    closePath.setAttribute('d', 'M6 18L18 6M6 6l12 12')
    closeSvg.appendChild(closePath)
    closeBtn.appendChild(closeSvg)
    flexDiv.appendChild(messageSpan)
    flexDiv.appendChild(closeBtn)
    notification.appendChild(flexDiv)

    document.body.appendChild(notification)

    setTimeout(() => {
      notification.style.opacity = '0'
      setTimeout(() => notification.remove(), 300)
    }, 5000)
  }
}
