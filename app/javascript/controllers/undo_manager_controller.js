import { Controller } from "@hotwired/stimulus"

// Undo Manager Controller
// Manages undo operations and displays notifications for recoverable actions
export default class extends Controller {
  static targets = ["notification", "message", "timer", "undoButton"]
  static values = {
    undoId: Number,
    timeRemaining: Number,
    autoHide: { type: Boolean, default: true },
    hideDelay: { type: Number, default: 30000 } // 30 seconds
  }

  connect() {
    this.timerInterval = null
    
    if (this.hasUndoIdValue && this.undoIdValue) {
      this.startTimer()
    }
  }

  disconnect() {
    this.stopTimer()
  }

  // Show undo notification for a deletion
  showUndoNotification(event) {
    const { undoId, message, timeRemaining } = event.detail
    
    this.undoIdValue = undoId
    this.timeRemainingValue = timeRemaining || 30
    
    if (this.hasMessageTarget) {
      this.messageTarget.textContent = message || "Items deleted successfully"
    }
    
    this.show()
    this.startTimer()
  }

  // Show the notification
  show() {
    this.element.classList.remove("hidden")
    this.element.classList.add("slide-in-bottom")
    
    // Announce to screen readers
    this.element.setAttribute("role", "alert")
    this.element.setAttribute("aria-live", "polite")
  }

  // Hide the notification
  hide() {
    this.element.classList.add("fade-out")
    
    setTimeout(() => {
      this.element.classList.add("hidden")
      this.element.classList.remove("slide-in-bottom", "fade-out")
      this.stopTimer()
    }, 300)
  }

  // Start countdown timer
  startTimer() {
    this.stopTimer() // Clear any existing timer
    
    if (this.timeRemainingValue <= 0) return
    
    this.updateTimerDisplay()
    
    this.timerInterval = setInterval(() => {
      this.timeRemainingValue--
      this.updateTimerDisplay()
      
      if (this.timeRemainingValue <= 0) {
        this.handleExpiration()
      }
    }, 1000)
  }

  // Stop countdown timer
  stopTimer() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval)
      this.timerInterval = null
    }
  }

  // Update timer display
  updateTimerDisplay() {
    if (!this.hasTimerTarget) return
    
    const minutes = Math.floor(this.timeRemainingValue / 60)
    const seconds = this.timeRemainingValue % 60
    
    if (minutes > 0) {
      this.timerTarget.textContent = `${minutes}m ${seconds}s`
    } else {
      this.timerTarget.textContent = `${seconds}s`
    }
    
    // Change color as time runs out
    if (this.timeRemainingValue <= 10) {
      this.timerTarget.classList.add("text-rose-600")
      this.timerTarget.classList.remove("text-slate-600")
    }
  }

  // Handle timer expiration
  handleExpiration() {
    this.stopTimer()
    
    if (this.hasUndoButtonTarget) {
      this.undoButtonTarget.disabled = true
      this.undoButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
      this.undoButtonTarget.textContent = "Expired"
    }
    
    // Auto-hide after expiration
    setTimeout(() => this.hide(), 2000)
  }

  // Perform undo action
  async undo() {
    if (!this.undoIdValue || this.timeRemainingValue <= 0) return
    
    this.setLoading(true)
    
    try {
      const response = await fetch(`/undo_histories/${this.undoIdValue}/undo`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json',
          'Accept': 'text/vnd.turbo-stream.html'
        }
      })
      
      if (!response.ok) throw new Error('Undo failed')
      
      // Success - Turbo will handle the response
      this.hide()
      
      // Show success message
      this.showSuccessMessage("Action undone successfully")
      
    } catch (error) {
      console.error('Undo error:', error)
      this.showErrorMessage("Failed to undo action")
    } finally {
      this.setLoading(false)
    }
  }

  // Set loading state
  setLoading(loading) {
    if (!this.hasUndoButtonTarget) return
    
    if (loading) {
      this.undoButtonTarget.disabled = true
      this.undoButtonTarget.innerHTML = `
        <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Undoing...
      `
    } else {
      this.undoButtonTarget.disabled = false
      this.undoButtonTarget.innerHTML = 'Undo'
    }
  }

  // Show success message
  showSuccessMessage(message) {
    const notification = this.createNotification(message, 'success')
    document.body.appendChild(notification)
    
    setTimeout(() => notification.remove(), 3000)
  }

  // Show error message
  showErrorMessage(message) {
    const notification = this.createNotification(message, 'error')
    document.body.appendChild(notification)
    
    setTimeout(() => notification.remove(), 3000)
  }

  // Create notification element
  createNotification(message, type) {
    const div = document.createElement('div')
    div.className = `fixed bottom-4 right-4 z-50 px-4 py-3 rounded-lg shadow-lg transition-all duration-300 ${
      type === 'success' ? 'bg-emerald-50 border border-emerald-200 text-emerald-700' : 'bg-rose-50 border border-rose-200 text-rose-700'
    }`
    div.innerHTML = `
      <div class="flex items-center">
        ${type === 'success' ? 
          '<svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>' :
          '<svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>'
        }
        <span>${message}</span>
      </div>
    `
    
    return div
  }

  // Dismiss notification
  dismiss() {
    this.hide()
  }
}