import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "progressBar",
    "progressPercentage",
    "progressText",
    "processedCount",
    "detectedCount",
    "elapsedTime",
    "accountProgress",
    "accountStatus",
    "accountProcessed",
    "accountDetected"
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
    if (!this.consumer) {
      this.consumer = createConsumer()
    }
    
    try {
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

  updateProgress(data) {
    // Update main progress bar
    if (this.hasProgressBarTarget) {
      const percentage = data.progress_percentage || 0
      this.progressBarTarget.style.width = `${percentage}%`
      
      // Update inline percentage if bar is wide enough
      const percentageSpan = this.progressBarTarget.querySelector('span')
      if (percentageSpan) {
        percentageSpan.textContent = `${percentage}%`
      }
    }

    // Update percentage text
    if (this.hasProgressPercentageTarget) {
      this.progressPercentageTarget.textContent = `${data.progress_percentage || 0}% completado`
    }

    // Update progress text
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `${data.progress_percentage || 0}% completado`
    }

    // Update processed count
    if (this.hasProcessedCountTarget) {
      this.processedCountTarget.textContent = data.processed_emails || 0
    }

    // Update detected expenses
    if (this.hasDetectedCountTarget) {
      this.detectedCountTarget.textContent = data.detected_expenses || 0
    }
  }

  updateAccount(data) {
    // Find account elements by data-account-id
    const accountSelector = `[data-account-id="${data.account_id}"]`
    const accountElement = document.querySelector(accountSelector)
    
    if (!accountElement) {
      return
    }

    // Update status badge
    const statusBadge = accountElement.querySelector('[data-account-status]')
    if (statusBadge) {
      const statusText = data.status === 'processing' ? 'Procesando' : 
                        data.status === 'completed' ? 'Completado' :
                        data.status === 'failed' ? 'Error' : data.status
      
      statusBadge.textContent = statusText
      statusBadge.className = `px-3 py-1 rounded-full text-xs font-medium ${
        data.status === 'completed' ? 'bg-emerald-100 text-emerald-800' :
        data.status === 'failed' ? 'bg-rose-100 text-rose-800' :
        data.status === 'processing' ? 'bg-teal-100 text-teal-800' :
        'bg-slate-100 text-slate-800'
      }`
    }

    // Update progress bar
    const progressBar = accountElement.querySelector('[data-account-progress-bar]')
    if (progressBar && data.progress_percentage !== undefined) {
      progressBar.style.width = `${data.progress_percentage}%`
    }

    // Update processed count
    const processedText = accountElement.querySelector('[data-account-processed]')
    if (processedText) {
      processedText.innerHTML = `
        <span class="text-lg font-semibold text-slate-900">
          ${data.processed_emails || 0} / ${data.total_emails || 0}
        </span>
      `
    }

    // Update detected expenses
    const detectedText = accountElement.querySelector('[data-account-detected]')
    if (detectedText) {
      detectedText.innerHTML = `
        <span class="text-lg font-semibold text-emerald-600">${data.detected_expenses || 0}</span>
      `
    }
  }

  updateStatus(data) {
    if (data.status) {
      this.updateProgress(data)
      
      if (data.accounts && Array.isArray(data.accounts)) {
        data.accounts.forEach(account => {
          this.updateAccount(account)
        })
      }
    }
  }

  handleCompletion(data) {
    
    // Update final progress
    this.updateProgress(data)
    
    // Show completion notification
    this.showNotification("Sincronización completada exitosamente", "success")
    
    // Update status badge
    const statusBadge = document.querySelector('[data-sync-status]')
    if (statusBadge) {
      statusBadge.className = 'px-3 py-1 rounded-full text-sm font-medium inline-flex items-center bg-emerald-100 text-emerald-800'
      statusBadge.innerHTML = 'Completado'
    }
    
    // Don't reload - let user see the final state
  }

  handleFailure(data) {
    
    // Show error notification
    this.showNotification(`Error en sincronización: ${data.error || 'Error desconocido'}`, "error")
    
    // Update UI to show error state
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.classList.remove('from-teal-500', 'to-emerald-500')
      this.progressBarTarget.classList.add('from-rose-500', 'to-rose-600')
    }
  }

  showNotification(message, type = 'info') {
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
    
    setTimeout(() => {
      notification.style.opacity = '0'
      setTimeout(() => notification.remove(), 300)
    }, 5000)
  }
}