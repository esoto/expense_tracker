import { Controller } from "@hotwired/stimulus"

// Shows a shimmer skeleton while chart libraries render, then hides it.
// Chartkick renders asynchronously — this fills the visual gap.
export default class extends Controller {
  static targets = ["skeleton", "chart"]

  connect() {
    if (!this.hasSkeletonTarget || !this.hasChartTarget) return

    // Chart may already be rendered (Turbo cache restore, fast render)
    if (this.chartTarget.querySelector("svg, canvas")) {
      this.hideSkeleton()
      return
    }

    this.observer = new MutationObserver(() => {
      if (this.chartTarget.querySelector("svg, canvas")) {
        this.hideSkeleton()
      }
    })

    this.observer.observe(this.chartTarget, { childList: true, subtree: true })

    // Fallback: hide skeleton after 5s only if chart rendered
    this.timeout = setTimeout(() => {
      if (this.chartTarget.querySelector("svg, canvas")) {
        this.hideSkeleton()
      }
      // If chart didn't render, keep skeleton visible as loading indicator
    }, 5000)
  }

  disconnect() {
    this.observer?.disconnect()
    clearTimeout(this.timeout)
  }

  hideSkeleton() {
    this.skeletonTarget.classList.add("hidden")
    this.observer?.disconnect()
    clearTimeout(this.timeout)
  }
}
