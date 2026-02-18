import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.isOpen = false
    this._handleClickOutside = this._handleClickOutside.bind(this)
    this._handleKeydown = this._handleKeydown.bind(this)
    this._handleMediaChange = this._handleMediaChange.bind(this)

    // Set up media query listener for desktop breakpoint
    this.mediaQuery = window.matchMedia("(min-width: 768px)")
    this.mediaQuery.addEventListener("change", this._handleMediaChange)
  }

  disconnect() {
    this._removeEventListeners()
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener("change", this._handleMediaChange)
    }
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
    this._addEventListeners()
    this._focusFirstLink()
  }

  close() {
    this.isOpen = false
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this._removeEventListeners()
  }

  // @private
  _addEventListeners() {
    document.addEventListener("click", this._handleClickOutside)
    document.addEventListener("keydown", this._handleKeydown)
  }

  // @private
  _removeEventListeners() {
    document.removeEventListener("click", this._handleClickOutside)
    document.removeEventListener("keydown", this._handleKeydown)
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
  _handleMediaChange(event) {
    if (event.matches) {
      // Viewport is now desktop-sized, close the menu
      this.close()
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
