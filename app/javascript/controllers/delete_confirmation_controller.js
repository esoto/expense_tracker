import { Controller } from "@hotwired/stimulus"

/**
 * Delete Confirmation Controller
 * Manages a styled modal for single-expense delete confirmation.
 * Listens for "expense:request-delete" events dispatched by kebab menu.
 */
export default class extends Controller {
  static targets = ["modal", "overlay", "panel", "merchantName", "amount", "deleteButton"]

  connect() {
    this.expensePath = null
    this.keydownHandler = this.handleKeydown.bind(this)
    this.openHandler = this.handleOpenRequest.bind(this)
    window.addEventListener("expense:request-delete", this.openHandler)
  }

  disconnect() {
    window.removeEventListener("expense:request-delete", this.openHandler)
    document.removeEventListener("keydown", this.keydownHandler)
  }

  handleOpenRequest(event) {
    const { expensePath, merchantName, amount } = event.detail

    this.expensePath = expensePath
    this.merchantNameTarget.textContent = merchantName || ""
    this.amountTarget.textContent = amount || ""

    // Show modal
    this.modalTarget.classList.remove("hidden")
    this.modalTarget.setAttribute("aria-hidden", "false")
    requestAnimationFrame(() => {
      this.overlayTarget.classList.remove("opacity-0")
      this.panelTarget.classList.remove("translate-y-4", "opacity-0")
      this.panelTarget.classList.add("translate-y-0", "opacity-100")
    })

    document.addEventListener("keydown", this.keydownHandler)
    this.deleteButtonTarget.focus()
  }

  close() {
    this.overlayTarget.classList.add("opacity-0")
    this.panelTarget.classList.add("translate-y-4", "opacity-0")
    this.panelTarget.classList.remove("translate-y-0", "opacity-100")

    setTimeout(() => {
      this.modalTarget.classList.add("hidden")
      this.modalTarget.setAttribute("aria-hidden", "true")
    }, 150)

    document.removeEventListener("keydown", this.keydownHandler)
    this.expensePath = null
  }

  confirm() {
    if (!this.expensePath) return

    // Submit delete via Turbo
    const link = document.createElement("a")
    link.href = this.expensePath
    link.dataset.turboMethod = "delete"
    link.style.display = "none"
    document.body.appendChild(link)
    link.click()
    link.remove()

    this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
