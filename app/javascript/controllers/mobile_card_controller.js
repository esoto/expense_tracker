import { Controller } from "@hotwired/stimulus"
import { t } from "services/i18n"

/**
 * Mobile Card Controller
 *
 * Manages compact expense cards on mobile screens:
 * - Tap to expand/collapse quick action buttons
 * - Long press (500ms) to enter batch selection mode
 * - Touch scrolling detection (cancels long press if user scrolls)
 * - Selection mode: shows checkboxes on all cards globally
 * - Dispatches custom events for category picker, status toggle, and delete
 */
export default class extends Controller {
  static targets = ["actions", "checkbox", "categoryDropdown"]

  static values = {
    expenseId: Number,
    expanded: { type: Boolean, default: false },
    selectionMode: { type: Boolean, default: false }
  }

  connect() {
    this._longPressTimer = null
    this._touchStartX = 0
    this._touchStartY = 0
    this._ignoreNextClick = false
    this._selectingCategory = false

    this._outsideClickHandler = (event) => {
      if (this.hasCategoryDropdownTarget &&
          !this.categoryDropdownTarget.classList.contains("hidden") &&
          !this.categoryDropdownTarget.contains(event.target) &&
          !event.target.closest('[data-action*="openCategoryPicker"]')) {
        this.categoryDropdownTarget.classList.add("hidden")
      }
    }
    document.addEventListener("click", this._outsideClickHandler)
  }

  disconnect() {
    this._clearLongPressTimer()
    if (this._outsideClickHandler) {
      document.removeEventListener("click", this._outsideClickHandler)
    }
  }

  // ---------------------------------------------------------------------------
  // Primary interaction: tap to toggle action drawer
  // ---------------------------------------------------------------------------

  toggleActions(event) {
    // Guard against click events fired immediately after a long-press on mobile.
    // On touch devices, touchstart → touchend → click all fire for a single tap.
    // After a long press enters selection mode the trailing click would undo it.
    if (this._ignoreNextClick) {
      this._ignoreNextClick = false
      return
    }

    // In selection mode, tapping the card toggles the checkbox instead
    if (this.selectionModeValue) {
      this._toggleCheckbox()
      return
    }

    // If the tap originated inside the open actions area, let that button handle it
    if (this.hasActionsTarget && this.actionsTarget.contains(event.target)) {
      return
    }

    if (this.expandedValue) {
      this._collapse()
    } else {
      this._collapseOtherCards()
      this._expand()
    }
  }

  collapseActions() {
    if (this.expandedValue) {
      this._collapse()
    }
  }

  // ---------------------------------------------------------------------------
  // Touch events: long press for selection mode
  // ---------------------------------------------------------------------------

  touchStart(event) {
    if (event.touches.length !== 1) return

    this._touchStartX = event.touches[0].clientX
    this._touchStartY = event.touches[0].clientY

    this._longPressTimer = setTimeout(() => {
      this._ignoreNextClick = true
      this.enterSelectionMode()
      this._toggleCheckbox()
      this._vibrate(50)
    }, 500)
  }

  touchEnd(_event) {
    this._clearLongPressTimer()
  }

  touchMove(event) {
    if (!this._longPressTimer) return

    const dx = Math.abs(event.touches[0].clientX - this._touchStartX)
    const dy = Math.abs(event.touches[0].clientY - this._touchStartY)

    // Cancel long press if the user is clearly scrolling (>10px movement)
    if (dx > 10 || dy > 10) {
      this._clearLongPressTimer()
    }
  }

  // ---------------------------------------------------------------------------
  // Action handlers — called from action buttons inside the card
  // ---------------------------------------------------------------------------

  openCategoryPicker(event) {
    event.stopPropagation()
    if (this.hasCategoryDropdownTarget) {
      this.categoryDropdownTarget.classList.toggle("hidden")
    }
  }

  selectCategory(event) {
    event.stopPropagation()

    if (this._selectingCategory) return
    this._selectingCategory = true

    const categoryId = event.currentTarget.dataset.categoryId
    const categoryName = event.currentTarget.dataset.categoryName

    // Close the dropdown immediately for responsive feel
    if (this.hasCategoryDropdownTarget) {
      this.categoryDropdownTarget.classList.add("hidden")
    }

    fetch(`/expenses/${this.expenseIdValue}/correct_category`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this._csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: JSON.stringify({ category_id: categoryId })
    })
    .then(response => {
      if (response.ok) {
        this._showToast(t("expenses.notifications.category_updated"), "success")
        return response.text()
      } else {
        throw new Error("Failed to update category")
      }
    })
    .then(turboStream => {
      if (turboStream) {
        Turbo.renderStreamMessage(turboStream)
      }
    })
    .catch(error => {
      console.error("[mobile-card] selectCategory failed:", error)
      this._showToast(t("expenses.errors.category_update_failed"), "error")
    })
    .finally(() => {
      this._selectingCategory = false
    })
  }

  async toggleStatus(event) {
    event.stopPropagation()
    const response = await fetch(`/expenses/${this.expenseIdValue}/update_status`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this._csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: JSON.stringify({ status: this._nextStatus() })
    })
    if (response.ok) {
      const turboStream = await response.text()
      if (turboStream) {
        Turbo.renderStreamMessage(turboStream)
      }
    }
  }

  confirmDelete(event) {
    event.stopPropagation()
    if (confirm(t("expenses.confirmations.delete_expense"))) {
      this.element.classList.add("opacity-50", "pointer-events-none")
      fetch(`/expenses/${this.expenseIdValue}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": this._csrfToken,
          "Accept": "application/json"
        }
      })
      .then(response => {
        if (response.ok) {
          this.element.style.transition = "all 300ms ease-out"
          this.element.style.transform = "translateX(100%)"
          this.element.style.opacity = "0"
          setTimeout(() => { this.element.remove() }, 300)
        } else {
          this.element.classList.remove("opacity-50", "pointer-events-none")
        }
      })
      .catch(() => {
        this.element.classList.remove("opacity-50", "pointer-events-none")
      })
    }
  }

  toggleCheckbox(event) {
    event.stopPropagation()
    this._toggleCheckbox()
  }

  // ---------------------------------------------------------------------------
  // Selection mode — called globally via enterSelectionMode / exitSelectionMode
  // ---------------------------------------------------------------------------

  enterSelectionMode() {
    // Set ALL cards to selection mode so tapping any card toggles its checkbox
    document.querySelectorAll("[data-controller='mobile-card']").forEach(el => {
      const controller = this.application.getControllerForElementAndIdentifier(el, "mobile-card")
      if (controller) controller.selectionModeValue = true
    })
    // Show all checkboxes
    document.querySelectorAll("[data-mobile-card-target='checkbox']").forEach(cb => {
      cb.classList.remove("hidden")
    })
    this.dispatch("selectionModeEntered", { detail: { active: true } })
  }

  exitSelectionMode() {
    // Clear selection mode on ALL cards
    document.querySelectorAll("[data-controller='mobile-card']").forEach(el => {
      const controller = this.application.getControllerForElementAndIdentifier(el, "mobile-card")
      if (controller) controller.selectionModeValue = false
    })
    // Hide checkboxes and uncheck their inputs
    document.querySelectorAll("[data-mobile-card-target='checkbox']").forEach(cb => {
      cb.classList.add("hidden")
      const input = cb.querySelector("input[type='checkbox']")
      if (input) input.checked = false
    })
    this.dispatch("selectionModeExited", { detail: { active: false } })
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  _expand() {
    this.expandedValue = true
    if (this.hasActionsTarget) {
      this.actionsTarget.classList.remove("hidden")
    }
  }

  _collapse() {
    this.expandedValue = false
    if (this.hasActionsTarget) {
      this.actionsTarget.classList.add("hidden")
    }
  }

  _collapseOtherCards() {
    // Find all other mobile-card controllers and collapse them
    document.querySelectorAll('[data-controller~="mobile-card"]').forEach((el) => {
      if (el !== this.element) {
        const otherController = this.application.getControllerForElementAndIdentifier(el, "mobile-card")
        if (otherController && otherController.expandedValue) {
          otherController._collapse()
        }
      }
    })
  }

  _toggleCheckbox() {
    if (this.hasCheckboxTarget) {
      const input = this.checkboxTarget.querySelector("input[type='checkbox']")
      if (input) {
        input.checked = !input.checked
        input.dispatchEvent(new Event("change", { bubbles: true }))
      }
    }
  }

  _nextStatus() {
    const currentStatus = this.element.dataset.currentStatus || "pending"
    return currentStatus === "pending" ? "processed" : "pending"
  }

  _clearLongPressTimer() {
    if (this._longPressTimer) {
      clearTimeout(this._longPressTimer)
      this._longPressTimer = null
    }
  }

  _vibrate(duration) {
    if (navigator.vibrate) {
      navigator.vibrate(duration)
    }
  }

  _showToast(message, type = "info") {
    const event = new CustomEvent("toast:show", {
      bubbles: true,
      detail: { message, type }
    })
    document.dispatchEvent(event)
  }

  get _csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
