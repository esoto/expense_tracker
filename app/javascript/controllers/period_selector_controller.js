import { Controller } from "@hotwired/stimulus"

/**
 * Period Selector Controller
 * Manages active state visually for the period selector segmented control.
 * Provides arrow key navigation between options (left/right).
 * The actual navigation happens via Turbo Frame links, not JS.
 */
export default class extends Controller {
  static values = { active: { type: String, default: "month" } }
  static targets = ["tab"]

  connect() {
    this.keydownHandler = this.handleKeydown.bind(this)
    this.element.addEventListener("keydown", this.keydownHandler)
  }

  disconnect() {
    if (this.keydownHandler) {
      this.element.removeEventListener("keydown", this.keydownHandler)
    }
  }

  handleKeydown(event) {
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return

    event.preventDefault()
    const tabs = this.tabTargets
    const currentIndex = tabs.findIndex(tab => tab.dataset.period === this.activeValue)
    if (currentIndex === -1) return

    let nextIndex
    if (event.key === "ArrowRight") {
      nextIndex = (currentIndex + 1) % tabs.length
    } else {
      nextIndex = (currentIndex - 1 + tabs.length) % tabs.length
    }

    tabs[nextIndex].focus()
    tabs[nextIndex].click()
  }
}
