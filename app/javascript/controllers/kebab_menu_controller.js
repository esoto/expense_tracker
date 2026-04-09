import { Controller } from "@hotwired/stimulus"

/**
 * Kebab Menu Controller
 * Three-dot dropdown menu for expense row actions.
 * Handles positioning, click-outside-to-close, and viewport overflow.
 */
export default class extends Controller {
  static targets = ["menu"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.closeHandler = this.closeOnClickOutside.bind(this)
    this.turboCloseHandler = this.close.bind(this)
    document.addEventListener("turbo:before-render", this.turboCloseHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.closeHandler)
    document.removeEventListener("turbo:before-render", this.turboCloseHandler)
  }

  toggle(event) {
    event.stopPropagation()

    if (this.openValue) {
      this.close()
    } else {
      this.open(event.currentTarget)
    }
  }

  open(trigger) {
    // Close any other open kebab menus
    document.querySelectorAll("[data-kebab-menu-open-value='true']").forEach(el => {
      const controller = this.application.getControllerForElementAndIdentifier(el, "kebab-menu")
      if (controller && controller !== this) controller.close()
    })

    this.openValue = true
    this.menuTarget.classList.remove("hidden")

    // Position the dropdown
    const rect = trigger.getBoundingClientRect()
    this.menuTarget.style.position = "fixed"
    this.menuTarget.style.top = `${rect.bottom + 4}px`
    this.menuTarget.style.left = `${rect.right - 176}px` // 176px = w-44

    // Adjust if overflowing viewport bottom
    requestAnimationFrame(() => {
      const menuRect = this.menuTarget.getBoundingClientRect()
      if (menuRect.bottom > window.innerHeight) {
        this.menuTarget.style.top = `${rect.top - menuRect.height - 4}px`
      }
      if (menuRect.left < 0) {
        this.menuTarget.style.left = "8px"
      }
    })

    document.addEventListener("click", this.closeHandler)
  }

  close() {
    this.openValue = false
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this.closeHandler)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
}
