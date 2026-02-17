import { Controller } from "@hotwired/stimulus"

/**
 * Flash Controller
 * Auto-dismisses flash messages after a configurable delay with fade-out animation.
 * Supports manual dismiss via close button.
 * Cleans up timeouts on disconnect to prevent memory leaks.
 */
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  dismiss() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }

    this.element.classList.add("opacity-0", "transition-opacity", "duration-300")
    setTimeout(() => this.element.remove(), 300)
  }
}
