import { Controller } from "@hotwired/stimulus"

/**
 * Flash Controller
 * Auto-dismisses flash messages after a configurable delay with fade-out animation.
 * Supports manual dismiss via close button.
 * Cleans up timeouts on disconnect to prevent memory leaks.
 * Pauses auto-removal on hover and resumes on mouse leave.
 */
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }
  static FADE_DURATION = 300

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
    this.mouseEnterHandler = this.pauseAutoRemove.bind(this)
    this.mouseLeaveHandler = this.resumeAutoRemove.bind(this)
    this.element.addEventListener("mouseenter", this.mouseEnterHandler)
    this.element.addEventListener("mouseleave", this.mouseLeaveHandler)
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
    if (this.mouseEnterHandler) {
      this.element.removeEventListener("mouseenter", this.mouseEnterHandler)
    }
    if (this.mouseLeaveHandler) {
      this.element.removeEventListener("mouseleave", this.mouseLeaveHandler)
    }
  }

  pauseAutoRemove() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
  }

  resumeAutoRemove() {
    if (this.timeout || !this.element.isConnected) return
    const resumeDelay = Math.min(this.delayValue / 2, this.delayValue)
    this.timeout = setTimeout(() => this.dismiss(), resumeDelay)
  }

  dismiss() {
    if (this.isDismissing) return
    this.isDismissing = true

    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }

    this.element.classList.add("opacity-0", "transition-opacity", `duration-${this.constructor.FADE_DURATION}`)
    setTimeout(() => this.element.remove(), this.constructor.FADE_DURATION)
  }
}
