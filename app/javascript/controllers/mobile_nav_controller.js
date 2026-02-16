import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.close()
    this._handleClickOutside = this._handleClickOutside.bind(this)
    this._handleKeydown = this._handleKeydown.bind(this)
    document.addEventListener("click", this._handleClickOutside)
    document.addEventListener("keydown", this._handleKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this._handleClickOutside)
    document.removeEventListener("keydown", this._handleKeydown)
  }

  toggle() {
    if (this.isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    this.isOpen = true
    this.menuTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this._focusFirstLink()
  }

  close() {
    this.isOpen = false
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  // @private
  _handleClickOutside(event) {
    if (this.isOpen && !this.element.contains(event.target)) {
      this.close()
    }
  }

  // @private
  _handleKeydown(event) {
    if (event.key === "Escape" && this.isOpen) {
      this.close()
      this.buttonTarget.focus()
    }
  }

  // @private
  _focusFirstLink() {
    const firstLink = this.menuTarget.querySelector("a")
    if (firstLink) {
      firstLink.focus()
    }
  }
}
