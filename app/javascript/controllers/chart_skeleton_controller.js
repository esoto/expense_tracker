import { Controller } from "@hotwired/stimulus"

// Shows a shimmer skeleton while chart libraries render, then hides it.
// Chartkick renders asynchronously — this fills the visual gap.
export default class extends Controller {
  static targets = ["skeleton", "chart"]

  connect() {
    if (!this.hasSkeletonTarget || !this.hasChartTarget) return

    this.observer = new MutationObserver(() => {
      if (this.chartTarget.querySelector("svg, canvas")) {
        this.skeletonTarget.classList.add("hidden")
        this.observer.disconnect()
      }
    })

    this.observer.observe(this.chartTarget, { childList: true, subtree: true })

    // Fallback: hide skeleton after 3s regardless
    this.timeout = setTimeout(() => {
      this.skeletonTarget.classList.add("hidden")
      this.observer?.disconnect()
    }, 3000)
  }

  disconnect() {
    this.observer?.disconnect()
    clearTimeout(this.timeout)
  }
}
