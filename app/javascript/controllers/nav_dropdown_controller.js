import { Controller } from "@hotwired/stimulus"

/**
 * Nav Dropdown Controller
 * Simple dropdown menu for navigation grouping.
 * Click to toggle, click outside or Escape to close.
 */
export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this.closeHandler = this.closeOnClickOutside.bind(this)
    this.keydownHandler = this.handleKeydown.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.closeHandler)
    document.removeEventListener("keydown", this.keydownHandler)
  }

  toggle(event) {
    event.stopPropagation()

    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.closeHandler)
    document.addEventListener("keydown", this.keydownHandler)
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.closeHandler)
    document.removeEventListener("keydown", this.keydownHandler)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      this.buttonTarget.focus()
    }
  }
}
