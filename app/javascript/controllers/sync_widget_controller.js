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
    "inactiveSection"
  ]
  
  static values = {
    sessionId: Number,
    active: Boolean
  }

  connect() {
    if (this.activeValue && this.sessionIdValue) {
      this.subscribeToChannel()
    }
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
  }

  subscribeToChannel() {
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
            // Connection established
          },

          disconnected: () => {
            // Connection lost
          },

          received: (data) => {
            this.handleUpdate(data)
          },
          
          rejected: () => {
            console.error("❌ Subscription rejected by server")
          }
        }
      )
    } catch (error) {
      console.error("Error creating subscription:", error)
    }
  }

  handleUpdate(data) {
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
    
    // Mark as completed but don't reload - let user stay on page
    // They can manually refresh or navigate away when ready
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
}