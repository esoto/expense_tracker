import { Controller } from "@hotwired/stimulus"

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
  static targets = ["card", "actions", "checkbox"]

  static values = {
    expenseId: Number,
    expanded: { type: Boolean, default: false },
    selectionMode: { type: Boolean, default: false }
  }

  connect() {
    this._longPressTimer = null
    this._touchStartX = 0
    this._touchStartY = 0
  }

  disconnect() {
    this._clearLongPressTimer()
  }

  // ---------------------------------------------------------------------------
  // Primary interaction: tap to toggle action drawer
  // ---------------------------------------------------------------------------

  toggleActions(event) {
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

  // ---------------------------------------------------------------------------
  // Touch events: long press for selection mode
  // ---------------------------------------------------------------------------

  touchStart(event) {
    if (event.touches.length !== 1) return

    this._touchStartX = event.touches[0].clientX
    this._touchStartY = event.touches[0].clientY

    this._longPressTimer = setTimeout(() => {
      this._enterSelectionMode()
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
  // Action dispatchers — called from action buttons inside the card
  // ---------------------------------------------------------------------------

  openCategoryPicker(event) {
    event.stopPropagation()
    this.dispatch("openCategoryPicker", {
      detail: { expenseId: this.expenseIdValue },
      bubbles: true
    })
  }

  toggleStatus(event) {
    event.stopPropagation()
    this.dispatch("toggleStatus", {
      detail: { expenseId: this.expenseIdValue },
      bubbles: true
    })
  }

  confirmDelete(event) {
    event.stopPropagation()
    this.dispatch("confirmDelete", {
      detail: { expenseId: this.expenseIdValue },
      bubbles: true
    })
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
    document.querySelectorAll("[data-mobile-card-target='checkbox']").forEach(cb => {
      cb.classList.add("hidden")
      cb.checked = false
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
      const input = this.checkboxTarget.querySelector('input[type="checkbox"]')
      if (input) {
        input.checked = !input.checked
        input.dispatchEvent(new Event("change", { bubbles: true }))
      }
    }
  }

  _enterSelectionMode() {
    this.selectionModeValue = true
    // Show checkboxes on all cards
    document.querySelectorAll('[data-mobile-card-target="checkbox"]').forEach((el) => {
      el.classList.remove("hidden")
    })
    // Collapse any open action drawers
    this._collapse()
    // Notify other controllers (e.g., batch-selection toolbar)
    this.dispatch("selectionModeEntered", { bubbles: true })
  }

  _exitSelectionMode() {
    this.selectionModeValue = false
    // Hide all checkboxes and uncheck them
    document.querySelectorAll('[data-mobile-card-target="checkbox"]').forEach((el) => {
      el.classList.add("hidden")
      const input = el.querySelector('input[type="checkbox"]')
      if (input) input.checked = false
    })
    this.dispatch("selectionModeExited", { bubbles: true })
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
}
