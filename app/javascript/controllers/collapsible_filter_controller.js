import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "badge", "toggleButton"]
  static values = { open: { type: Boolean, default: false } }

  toggle() {
    this.openValue = !this.openValue
    this.contentTarget.classList.toggle("hidden", !this.openValue)
    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.setAttribute("aria-expanded", this.openValue)
    }
  }
}
