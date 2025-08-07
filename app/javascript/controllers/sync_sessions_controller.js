import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "sessionRow",
    "activeSection",
    "progressBar",
    "progressText",
    "processedCount",
    "detectedCount",
    "accountCard"
  ]
  
  static values = {
    sessionId: Number,
    autoRefresh: Boolean
  }

  connect() {
    if (this.sessionIdValue) {
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
      this.consumer = window.consumer || createConsumer()
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
    // Update main progress bar in active section
    if (this.hasProgressBarTarget) {
      const percentage = data.progress_percentage || 0
      this.progressBarTarget.style.width = `${percentage}%`
    }

    // Update progress text
    if (this.hasProgressTextTarget) {
      const percentage = data.progress_percentage || 0
      this.progressTextTarget.textContent = `Progreso: ${percentage}%`
    }

    // Update processed count
    if (this.hasProcessedCountTarget) {
      this.processedCountTarget.textContent = `${data.processed_emails || 0} / ${data.total_emails || 0} emails`
    }

    // Update detected expenses
    if (this.hasDetectedCountTarget) {
      this.detectedCountTarget.textContent = `${data.detected_expenses || 0} gastos`
    }

    // Update the session row in the history table
    this.updateSessionRow(data)
  }

  updateSessionRow(data) {
    // Find the row for this session
    const rowSelector = `[data-session-id="${this.sessionIdValue}"]`
    const row = document.querySelector(rowSelector)
    
    if (row) {
      // Update progress in the row
      const progressBarCell = row.querySelector('[data-progress-bar]')
      if (progressBarCell) {
        const bar = progressBarCell.querySelector('.bg-teal-600')
        if (bar) {
          bar.style.width = `${data.progress_percentage || 0}%`
        }
        const text = progressBarCell.querySelector('[data-progress-text]')
        if (text) {
          text.textContent = `${data.processed_emails || 0} / ${data.total_emails || 0}`
        }
      }

      // Update detected expenses
      const expensesCell = row.querySelector('[data-expenses-count]')
      if (expensesCell) {
        expensesCell.textContent = data.detected_expenses || 0
      }
    }
  }

  updateAccount(data) {
    if (!this.hasAccountCardTargets) return

    // Find the account card
    const accountCard = this.accountCardTargets.find(card => 
      card.dataset.accountId === String(data.account_id)
    )
    
    if (accountCard) {
      // Update status badge
      const statusBadge = accountCard.querySelector('[data-status-badge]')
      if (statusBadge) {
        statusBadge.textContent = data.status === 'processing' ? 'Procesando' : data.status
        statusBadge.className = data.status === 'processing' 
          ? 'text-xs px-2 py-1 rounded-full bg-teal-100 text-teal-700'
          : 'text-xs px-2 py-1 rounded-full bg-emerald-100 text-emerald-700'
      }

      // Update counts
      const countsElement = accountCard.querySelector('[data-account-counts]')
      if (countsElement) {
        countsElement.innerHTML = `
          <span>${data.processed || 0} / ${data.total || 0}</span>
          <span>${data.detected || 0} gastos</span>
        `
      }
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
    
    // Update UI to show completion
    this.updateProgress(data)
    
    // Update status badge in the table row
    const rowSelector = `[data-session-id="${this.sessionIdValue}"]`
    const row = document.querySelector(rowSelector)
    if (row) {
      const statusBadge = row.querySelector('[data-status-badge]')
      if (statusBadge) {
        statusBadge.className = 'px-2 py-1 inline-flex text-xs leading-5 font-semibold rounded-full bg-emerald-100 text-emerald-800'
        statusBadge.textContent = 'Completado'
      }
    }
    
    // Show completion notification
    this.showNotification("Sincronización completada exitosamente", "success")
    
    // Don't reload - let user continue viewing real-time updates
  }

  handleFailure(data) {
    
    // Show error notification
    this.showNotification(`Error en sincronización: ${data.error || 'Error desconocido'}`, "error")
    
    // Update UI to show error state
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.classList.add('bg-rose-600')
      this.progressBarTarget.classList.remove('bg-amber-600')
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