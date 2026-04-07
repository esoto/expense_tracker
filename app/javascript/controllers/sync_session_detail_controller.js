import { Controller } from "@hotwired/stimulus"
import { syncChannelMixin } from "mixins/sync_channel_mixin"

class SyncSessionDetailController extends Controller {
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
    sessionToken: String,
    active: Boolean
  }

  connect() {
    if (this.activeValue && this.sessionIdValue) {
      this.subscribeToChannel()
    }
  }

  disconnect() {
    this.disconnectChannel()
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

    // Update processed count (preserve styled child element)
    const processedText = accountElement.querySelector('[data-account-processed]')
    if (processedText) {
      const target = processedText.querySelector('p') || processedText
      target.textContent = `${data.processed_emails || 0} / ${data.total_emails || 0}`
    }

    // Update detected expenses (preserve styled child element)
    const detectedText = accountElement.querySelector('[data-account-detected]')
    if (detectedText) {
      const target = detectedText.querySelector('p') || detectedText
      target.textContent = `${data.detected_expenses || 0}`
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
      statusBadge.textContent = 'Completado'
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
}

Object.assign(SyncSessionDetailController.prototype, syncChannelMixin)

export default SyncSessionDetailController
