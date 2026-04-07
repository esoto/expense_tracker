import { Controller } from "@hotwired/stimulus"
import { syncChannelMixin } from "mixins/sync_channel_mixin"
import { t } from "services/i18n"

class SyncSessionsController extends Controller {
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
    sessionToken: String,
    autoRefresh: Boolean
  }

  connect() {
    if (this.sessionIdValue) {
      this.subscribeToChannel()
    }
  }

  disconnect() {
    this.disconnectChannel()
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
        countsElement.textContent = ''
        const processed = document.createElement('span')
        processed.textContent = `${data.processed || 0} / ${data.total || 0}`
        const detected = document.createElement('span')
        detected.textContent = `${data.detected || 0} gastos`
        countsElement.appendChild(processed)
        countsElement.appendChild(detected)
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
        statusBadge.textContent = t("expenses.status.processed")
      }
    }

    // Show completion notification
    this.showNotification(t("sync.notifications.completed", { detected: 0, processed: 0 }), "success")

    // Don't reload - let user continue viewing real-time updates
  }

  handleFailure(data) {

    // Show error notification
    this.showNotification(t("sync.notifications.failed", { error: data.error || 'Error desconocido' }), "error")

    // Update UI to show error state
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.classList.add('bg-rose-600')
      this.progressBarTarget.classList.remove('bg-amber-600')
    }
  }
}

Object.assign(SyncSessionsController.prototype, syncChannelMixin)

export default SyncSessionsController
