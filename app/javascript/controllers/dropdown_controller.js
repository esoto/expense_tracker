import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    if (this.hasMenuTarget) this.close()
  }

  toggle() {
    if (!this.hasMenuTarget) return

    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    if (!this.hasMenuTarget) return

    this.menuTarget.classList.remove("hidden")

    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "true")
    }

    // Defer adding the close-on-click handler to the next animation frame so the
    // current click event (which triggered open()) finishes bubbling to the document
    // before the listener is attached. Without this, the opening click would
    // immediately fire clickOutside and close the menu.
    this.clickOutside = this.clickOutside.bind(this)
    requestAnimationFrame(() => {
      document.addEventListener("click", this.clickOutside)
    })
  }

  close() {
    if (!this.hasMenuTarget) return

    this.menuTarget.classList.add("hidden")

    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "false")
    }

    // Remove click outside listener
    document.removeEventListener("click", this.clickOutside)
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.clickOutside)
  }
}