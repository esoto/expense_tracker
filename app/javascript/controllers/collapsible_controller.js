import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "badge", "toggleButton"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.#syncState()
  }

  toggle() {
    this.openValue = !this.openValue
    this.#syncState()
  }

  #syncState() {
    this.contentTarget.classList.toggle("hidden", !this.openValue)

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.setAttribute("aria-expanded", this.openValue)

      const labelEl = this.toggleButtonTarget.querySelector("[data-collapsible-label]")
      if (labelEl) {
        labelEl.textContent = this.openValue
          ? (labelEl.dataset.collapsibleLabelOpen || labelEl.textContent)
          : (labelEl.dataset.collapsibleLabelClosed || labelEl.textContent)
      }
    }
  }
}
