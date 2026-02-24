import { Controller } from "@hotwired/stimulus"

// Undo Manager Controller
// Manages undo notifications with a 30-second countdown.
// Once the notification closes (timer expires or user dismisses), the action is permanent.
export default class extends Controller {
  static targets = ["message", "timer", "undoButton", "progressBar"]
  static values = {
    undoId: Number,
    timeRemaining: { type: Number, default: 30 },
    totalTime: { type: Number, default: 30 }
  }

  connect() {
    this.timerInterval = null
    this.totalTimeValue = this.timeRemainingValue

    if (this.hasUndoIdValue && this.undoIdValue) {
      this.startTimer()
    }
  }

  disconnect() {
    this.stopTimer()
  }

  showUndoNotification(event) {
    const { undoId, message, timeRemaining } = event.detail

    this.undoIdValue = undoId
    this.timeRemainingValue = timeRemaining || 30
    this.totalTimeValue = this.timeRemainingValue

    if (this.hasMessageTarget) {
      this.messageTarget.textContent = message || "Gasto eliminado"
    }

    this.show()
    this.startTimer()
  }

  show() {
    this.element.classList.remove("hidden")
    this.element.classList.add("slide-in-bottom")
  }

  hide() {
    this.element.classList.add("fade-out")

    setTimeout(() => {
      this.element.classList.add("hidden")
      this.element.classList.remove("slide-in-bottom", "fade-out")
      this.stopTimer()
    }, 300)
  }

  startTimer() {
    this.stopTimer()

    if (this.timeRemainingValue <= 0) return

    this.updateTimerDisplay()
    this.updateProgressBar()

    this.timerInterval = setInterval(() => {
      this.timeRemainingValue--
      this.updateTimerDisplay()
      this.updateProgressBar()

      if (this.timeRemainingValue <= 0) {
        this.handleExpiration()
      }
    }, 1000)
  }

  stopTimer() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval)
      this.timerInterval = null
    }
  }

  updateTimerDisplay() {
    if (!this.hasTimerTarget) return

    this.timerTarget.textContent = `${this.timeRemainingValue}s`

    // Urgent styling when running low
    if (this.timeRemainingValue <= 5) {
      this.timerTarget.style.color = "#e11d48" // rose-600
      this.timerTarget.style.fontWeight = "700"
    } else if (this.timeRemainingValue <= 10) {
      this.timerTarget.style.color = "#d97706" // amber-600
      this.timerTarget.style.fontWeight = "600"
    }
  }

  updateProgressBar() {
    if (!this.hasProgressBarTarget) return

    const pct = (this.timeRemainingValue / this.totalTimeValue) * 100
    this.progressBarTarget.style.width = `${pct}%`

    // Color shifts: teal → amber → rose
    if (this.timeRemainingValue <= 5) {
      this.progressBarTarget.style.backgroundColor = "#e11d48" // rose-600
    } else if (this.timeRemainingValue <= 10) {
      this.progressBarTarget.style.backgroundColor = "#d97706" // amber-600
    } else {
      this.progressBarTarget.style.backgroundColor = "#0f766e" // teal-700
    }
  }

  handleExpiration() {
    this.stopTimer()

    if (this.hasUndoButtonTarget) {
      this.undoButtonTarget.disabled = true
      this.undoButtonTarget.style.opacity = "0.5"
      this.undoButtonTarget.style.cursor = "not-allowed"
      this.undoButtonTarget.textContent = "Expirado"
    }

    if (this.hasTimerTarget) {
      this.timerTarget.textContent = "sin recuperación"
      this.timerTarget.style.color = "#e11d48"
    }

    setTimeout(() => this.hide(), 2000)
  }

  async undo() {
    if (!this.undoIdValue || this.timeRemainingValue <= 0) return

    this.setLoading(true)

    try {
      const response = await fetch(`/undo_histories/${this.undoIdValue}/undo`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
          "Content-Type": "application/json",
          "Accept": "application/json"
        }
      })

      if (!response.ok) throw new Error("Undo failed")

      this.stopTimer()
      this.hide()
      this.showToast("Gasto restaurado exitosamente", "success")

      setTimeout(() => window.location.reload(), 1500)
    } catch (error) {
      console.error("Undo error:", error)
      this.showToast("No se pudo deshacer la acción", "error")
    } finally {
      this.setLoading(false)
    }
  }

  setLoading(loading) {
    if (!this.hasUndoButtonTarget) return

    if (loading) {
      this.undoButtonTarget.disabled = true
      this.undoButtonTarget.innerHTML =
        '<span class="undo-spinner"></span> Deshaciendo...'
    } else {
      this.undoButtonTarget.disabled = false
      this.undoButtonTarget.textContent = "Deshacer"
    }
  }

  showToast(message, type) {
    const div = document.createElement("div")
    const isSuccess = type === "success"

    Object.assign(div.style, {
      position: "fixed",
      bottom: "1rem",
      right: "1rem",
      zIndex: "60",
      padding: "0.75rem 1rem",
      borderRadius: "0.5rem",
      boxShadow: "0 10px 15px -3px rgb(0 0 0 / 0.1)",
      border: `1px solid ${isSuccess ? "#a7f3d0" : "#fecdd3"}`,
      backgroundColor: isSuccess ? "#ecfdf5" : "#fff1f2",
      color: isSuccess ? "#047857" : "#be123c",
      fontSize: "0.875rem",
      fontWeight: "500",
      display: "flex",
      alignItems: "center",
      gap: "0.5rem",
      animation: "slideInBottom 0.3s ease-out"
    })

    const icon = isSuccess
      ? '<svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>'
      : '<svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>'

    div.innerHTML = `${icon}<span>${message}</span>`
    document.body.appendChild(div)

    setTimeout(() => {
      div.style.animation = "fadeOut 0.3s ease-out"
      setTimeout(() => div.remove(), 300)
    }, 3000)
  }

  dismiss() {
    this.stopTimer()
    this.hide()
  }
}