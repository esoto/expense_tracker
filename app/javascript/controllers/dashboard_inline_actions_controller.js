import { Controller } from "@hotwired/stimulus"
import { shouldSuppressShortcut } from "utilities/keyboard_shortcut_helpers"
import { createUndoNotification } from "utilities/undo_notification_helper"
import { t } from "services/i18n"
import { createElement } from "utilities/safe_dom"

// Dashboard Inline Actions Controller for Epic 3 Task 3.3
// Handles quick actions: categorize, status toggle, duplicate, and delete
export default class extends Controller {
  static targets = [
    "categoryDropdown",
    "deleteConfirmation"
  ]
  
  static values = {
    expenseId: { type: String },
    currentStatus: { type: String }
  }
  
  connect() {
    // Ensure DOM is ready before setting up interactions
    requestAnimationFrame(() => {
      this.setupKeyboardNavigation()
      this.setupClickOutside()
      
      // Mark controller as ready for tests
      this.element.dataset.controllerReady = "true"
      
      // Log connection in development and test
      if (this.element.dataset.environment === "development" || this.element.dataset.environment === "test") {
        console.log("Dashboard Inline Actions connected for expense:", this.expenseIdValue)
      }
    })
  }
  
  disconnect() {
    // Clean up event listeners
    if (this.clickOutsideHandler) {
      document.removeEventListener("click", this.clickOutsideHandler)
    }
    if (this.keyboardHandler) {
      document.removeEventListener("keydown", this.keyboardHandler)
    }
  }
  
  // Toggle category dropdown
  toggleCategoryDropdown(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (!this.hasCategoryDropdownTarget) return
    
    const isHidden = this.categoryDropdownTarget.classList.contains("hidden")
    
    // Close all other dropdowns
    this.closeAllDropdowns()
    
    if (isHidden) {
      this.showCategoryDropdown()
    } else {
      this.hideCategoryDropdown()
    }
  }
  
  // Show category dropdown
  showCategoryDropdown() {
    if (!this.hasCategoryDropdownTarget) return
    
    this.categoryDropdownTarget.classList.remove("hidden")
    this.categoryDropdownTarget.style.opacity = "0"
    this.categoryDropdownTarget.style.transform = "scale(0.95)"
    
    // Animate in
    requestAnimationFrame(() => {
      this.categoryDropdownTarget.style.transition = "opacity 0.15s ease-out, transform 0.15s ease-out"
      this.categoryDropdownTarget.style.opacity = "1"
      this.categoryDropdownTarget.style.transform = "scale(1)"
    })
    
    // Focus first category option
    const firstCategory = this.categoryDropdownTarget.querySelector("button")
    if (firstCategory) {
      firstCategory.focus()
    }
  }
  
  // Hide category dropdown
  hideCategoryDropdown() {
    if (!this.hasCategoryDropdownTarget) return
    
    this.categoryDropdownTarget.style.transition = "opacity 0.15s ease-out, transform 0.15s ease-out"
    this.categoryDropdownTarget.style.opacity = "0"
    this.categoryDropdownTarget.style.transform = "scale(0.95)"
    
    setTimeout(() => {
      this.categoryDropdownTarget.classList.add("hidden")
    }, 150)
  }
  
  // Select category and update expense
  selectCategory(event) {
    event.preventDefault()
    const categoryId = event.currentTarget.dataset.categoryId
    const categoryName = event.currentTarget.dataset.categoryName
    
    this.hideCategoryDropdown()
    this.showLoadingState(t("common.status.categorizing"))
    
    // Update category via API
    fetch(`/expenses/${this.expenseIdValue}/correct_category`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.getCSRFToken(),
        "Accept": "application/json"
      },
      body: JSON.stringify({
        category_id: categoryId
      })
    })
    .then(response => {
      if (response.ok) {
        return response.json()
      }
      throw new Error("Failed to update category")
    })
    .then(data => {
      const categoryColor = data.color || data.expense?.category?.color || '#6B7280'
      this.updateCategoryDisplay(categoryId, categoryName, categoryColor)
      this.showToast(t("expenses.notifications.categorized_as", { category: categoryName }), "success")
      this.hideLoadingState()
    })
    .catch(error => {
      console.error("Error updating category:", error)
      this.showToast(t("expenses.errors.categorize_failed"), "error")
      this.hideLoadingState()
    })
  }
  
  // Toggle status between pending and processed
  toggleStatus(event) {
    event.preventDefault()
    const currentStatus = this.currentStatusValue
    const newStatus = currentStatus === "pending" ? "processed" : "pending"
    
    this.showLoadingState(t("common.status.updating_status"))
    
    // Update status via API
    fetch(`/expenses/${this.expenseIdValue}/update_status`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.getCSRFToken(),
        "Accept": "application/json"
      },
      body: JSON.stringify({
        status: newStatus
      })
    })
    .then(response => {
      if (response.ok) {
        return response.json()
      }
      throw new Error("Failed to update status")
    })
    .then(data => {
      this.updateStatusDisplay(newStatus)
      this.currentStatusValue = newStatus
      const statusText = newStatus === "pending" ? "pendiente" : "procesado"
      this.showToast(`Estado cambiado a ${statusText}`, "success")
      this.hideLoadingState()
    })
    .catch(error => {
      console.error("Error updating status:", error)
      this.showToast(t("expenses.errors.status_update_failed"), "error")
      this.hideLoadingState()
    })
  }
  
  // Duplicate expense
  duplicateExpense(event) {
    event.preventDefault()
    
    this.showLoadingState(t("common.status.duplicating"))
    
    // Duplicate via API
    fetch(`/expenses/${this.expenseIdValue}/duplicate`, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.getCSRFToken(),
        "Accept": "application/json"
      }
    })
    .then(response => {
      if (response.ok) {
        return response.json()
      }
      throw new Error("Failed to duplicate expense")
    })
    .then(data => {
      this.showToast(t("expenses.notifications.duplicated_success"), "success")
      this.hideLoadingState()
      
      // Refresh the dashboard to show the new expense
      setTimeout(() => {
        window.location.reload()
      }, 1000)
    })
    .catch(error => {
      console.error("Error duplicating expense:", error)
      this.showToast(t("expenses.errors.duplicate_failed"), "error")
      this.hideLoadingState()
    })
  }
  
  // Show delete confirmation
  showDeleteConfirmation(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (!this.hasDeleteConfirmationTarget) return
    
    // Close other dropdowns
    this.closeAllDropdowns()
    
    this.deleteConfirmationTarget.classList.remove("hidden")
    this.deleteConfirmationTarget.style.opacity = "0"
    this.deleteConfirmationTarget.style.transform = "scale(0.95)"
    
    // Animate in
    requestAnimationFrame(() => {
      this.deleteConfirmationTarget.style.transition = "opacity 0.15s ease-out, transform 0.15s ease-out"
      this.deleteConfirmationTarget.style.opacity = "1"
      this.deleteConfirmationTarget.style.transform = "scale(1)"
    })
    
    // Focus delete button
    const deleteButton = this.deleteConfirmationTarget.querySelector("[data-action*='confirmDelete']")
    if (deleteButton) {
      deleteButton.focus()
    }
  }
  
  // Cancel delete
  cancelDelete(event) {
    event.preventDefault()
    this.hideDeleteConfirmation()
  }
  
  // Confirm delete
  confirmDelete(event) {
    event.preventDefault()
    
    this.hideDeleteConfirmation()
    this.showLoadingState(t("common.status.deleting"))
    
    // Delete via API
    fetch(`/expenses/${this.expenseIdValue}`, {
      method: "DELETE",
      headers: {
        "X-CSRF-Token": this.getCSRFToken(),
        "Accept": "application/json"
      }
    })
    .then(response => {
      if (response.ok) {
        return response.json()
      }
      throw new Error("Failed to delete expense")
    })
    .then(data => {
      this.animateRemoval()
      if (data.undo_id) {
        this.showUndoNotification(data.undo_id, data.undo_time_remaining, data.message)
      } else {
        this.showToast(t("expenses.notifications.deleted_success"), "success")
      }
    })
    .catch(error => {
      console.error("Error deleting expense:", error)
      this.showToast(t("expenses.errors.delete_failed"), "error")
      this.hideLoadingState()
    })
  }
  
  // Hide delete confirmation
  hideDeleteConfirmation() {
    if (!this.hasDeleteConfirmationTarget) return
    
    this.deleteConfirmationTarget.style.transition = "opacity 0.15s ease-out, transform 0.15s ease-out"
    this.deleteConfirmationTarget.style.opacity = "0"
    this.deleteConfirmationTarget.style.transform = "scale(0.95)"
    
    setTimeout(() => {
      this.deleteConfirmationTarget.classList.add("hidden")
    }, 150)
  }
  
  // Update category display in the UI
  updateCategoryDisplay(categoryId, categoryName, categoryColor) {
    const categoryBadge = this.element.querySelector(".expense-category-badge")
    if (categoryBadge) {
      // Ensure color is applied properly
      categoryBadge.style.backgroundColor = categoryColor
      categoryBadge.style.setProperty('background-color', categoryColor, 'important')
      categoryBadge.textContent = categoryName.charAt(0)
      categoryBadge.title = categoryName
      categoryBadge.classList.remove("uncategorized")
    }
    
    // Update category name in metadata
    const categorySpan = this.element.querySelector(".expense-metadata span:nth-child(4)")
    if (categorySpan) {
      categorySpan.textContent = categoryName
    }
  }
  
  // Update status display in the UI
  updateStatusDisplay(newStatus) {
    const statusButton = this.element.querySelector("[data-action*='toggleStatus']")
    const statusBadge = this.element.querySelector(".expense-expanded-details .bg-slate-100")
    
    if (statusButton) {
      // Update button colors and tooltip
      statusButton.className = `p-1 transition-colors ${newStatus === 'pending' ? 'text-amber-500 hover:text-emerald-600' : 'text-emerald-500 hover:text-amber-600'}`
      statusButton.title = newStatus === 'pending' ? 'Marcar como procesado (S)' : 'Marcar como pendiente (S)'
      
      // Update icon
      const icon = statusButton.querySelector("svg")
      if (icon) {
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
        path.setAttribute('stroke-linecap', 'round')
        path.setAttribute('stroke-linejoin', 'round')
        path.setAttribute('stroke-width', '2')
        path.setAttribute('d', newStatus === 'pending'
          ? 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z'
          : 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z')
        icon.replaceChildren(path)
      }
    }
    
    // Update status badge in expanded view
    if (statusBadge) {
      statusBadge.textContent = newStatus.charAt(0).toUpperCase() + newStatus.slice(1)
    }
  }
  
  // Animate removal of expense row
  animateRemoval() {
    this.element.style.transition = "all 0.3s ease-out"
    this.element.style.transform = "translateX(-100%)"
    this.element.style.opacity = "0"
    
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
  
  // Show loading state
  showLoadingState(message) {
    const quickActions = this.element.querySelector(".inline-quick-actions")
    if (quickActions) {
      quickActions.style.opacity = "0.5"
      quickActions.style.pointerEvents = "none"
    }
    
    // Show loading indicator
    this.element.classList.add("opacity-75")
  }
  
  // Hide loading state
  hideLoadingState() {
    const quickActions = this.element.querySelector(".inline-quick-actions")
    if (quickActions) {
      quickActions.style.opacity = ""
      quickActions.style.pointerEvents = ""
    }
    
    this.element.classList.remove("opacity-75")
  }
  
  // Close all dropdowns
  closeAllDropdowns() {
    // Close category dropdown
    if (this.hasCategoryDropdownTarget) {
      this.hideCategoryDropdown()
    }
    
    // Close delete confirmation
    if (this.hasDeleteConfirmationTarget) {
      this.hideDeleteConfirmation()
    }
    
    // Close other controller dropdowns
    document.querySelectorAll("[data-dashboard-inline-actions-target='categoryDropdown']").forEach(dropdown => {
      if (dropdown !== this.categoryDropdownTarget) {
        dropdown.classList.add("hidden")
      }
    })
    
    document.querySelectorAll("[data-dashboard-inline-actions-target='deleteConfirmation']").forEach(modal => {
      if (modal !== this.deleteConfirmationTarget) {
        modal.classList.add("hidden")
      }
    })
  }
  
  // Setup click outside handler
  setupClickOutside() {
    this.clickOutsideHandler = (event) => {
      // Check if click is outside this expense row
      if (!this.element.contains(event.target)) {
        this.closeAllDropdowns()
      }
    }
    
    document.addEventListener("click", this.clickOutsideHandler)
  }
  
  // Setup keyboard navigation
  setupKeyboardNavigation() {
    this.keyboardHandler = (event) => {
      // Only handle if this row has focus or contains the focused element
      if (!this.element.contains(document.activeElement)) return

      // Don't fire shortcuts when typing in form fields (except Escape)
      if (shouldSuppressShortcut(event)) return

      switch(event.key) {
        case "Escape":
          event.preventDefault()
          event.stopPropagation()
          this.closeAllDropdowns()
          break
        case "c":
        case "C":
          if (!event.ctrlKey && !event.metaKey) {
            event.preventDefault()
            event.stopPropagation()
            this.toggleCategoryDropdown(event)
          }
          break
        case "s":
        case "S":
          if (!event.ctrlKey && !event.metaKey) {
            event.preventDefault()
            event.stopPropagation()
            this.toggleStatus(event)
          }
          break
        case "d":
        case "D":
          if (!event.ctrlKey && !event.metaKey) {
            event.preventDefault()
            event.stopPropagation()
            this.duplicateExpense(event)
          }
          break
        case "Delete":
          event.preventDefault()
          event.stopPropagation()
          this.showDeleteConfirmation(event)
          break
      }
    }

    document.addEventListener("keydown", this.keyboardHandler)
  }
  
  // Show undo notification with countdown timer
  showUndoNotification(undoId, timeRemaining, message) {
    createUndoNotification(undoId, timeRemaining, message)
  }

  // Show toast notification
  showToast(message, type = "info") {
    // Create toast element
    const toast = document.createElement("div")
    toast.className = `
      fixed top-4 right-4 z-50 max-w-sm w-full
      bg-white rounded-lg shadow-lg border border-slate-200 p-4
      transform transition-all duration-300 ease-out
      translate-x-full opacity-0
    `
    
    // Set colors based on type
    const colors = {
      success: "border-emerald-200 bg-emerald-50",
      error: "border-rose-200 bg-rose-50",
      info: "border-teal-200 bg-teal-50"
    }
    
    const textColors = {
      success: "text-emerald-700",
      error: "text-rose-700", 
      info: "text-teal-700"
    }
    
    toast.className += ` ${colors[type] || colors.info}`
    
    // Build icon SVG — static paths, no user data
    const iconPaths = {
      success: { color: 'text-emerald-500', d: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z' },
      error:   { color: 'text-rose-500',    d: 'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z' },
      info:    { color: 'text-teal-500',    d: 'M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z' }
    }
    const iconCfg = iconPaths[type] || iconPaths.info
    const iconSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    iconSvg.setAttribute('aria-hidden', 'true')
    iconSvg.setAttribute('class', `w-5 h-5 ${iconCfg.color}`)
    iconSvg.setAttribute('fill', 'none')
    iconSvg.setAttribute('stroke', 'currentColor')
    iconSvg.setAttribute('viewBox', '0 0 24 24')
    const iconPath = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    iconPath.setAttribute('stroke-linecap', 'round')
    iconPath.setAttribute('stroke-linejoin', 'round')
    iconPath.setAttribute('stroke-width', '2')
    iconPath.setAttribute('d', iconCfg.d)
    iconSvg.appendChild(iconPath)

    const iconDiv = createElement('div', { classes: ['flex-shrink-0'], children: [iconSvg] })

    // message rendered as textContent — XSS-safe
    const messageP = createElement('p', {
      text: message,
      classes: ['text-sm', 'font-medium', textColors[type] || textColors.info]
    })
    const messageDiv = createElement('div', { classes: ['ml-3', 'flex-1'], children: [messageP] })

    // Close button — addEventListener replaces onclick
    const closeSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    closeSvg.setAttribute('aria-hidden', 'true')
    closeSvg.setAttribute('class', 'w-4 h-4')
    closeSvg.setAttribute('fill', 'none')
    closeSvg.setAttribute('stroke', 'currentColor')
    closeSvg.setAttribute('viewBox', '0 0 24 24')
    const closePath = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    closePath.setAttribute('stroke-linecap', 'round')
    closePath.setAttribute('stroke-linejoin', 'round')
    closePath.setAttribute('stroke-width', '2')
    closePath.setAttribute('d', 'M6 18L18 6M6 6l12 12')
    closeSvg.appendChild(closePath)

    const closeBtn = createElement('button', {
      attrs: { type: 'button' },
      classes: ['inline-flex', textColors[type] || textColors.info, 'hover:text-slate-500', 'focus:outline-none'],
      children: [closeSvg]
    })
    closeBtn.addEventListener('click', () => toast.remove())

    const closeDiv = createElement('div', { classes: ['ml-4', 'flex-shrink-0'], children: [closeBtn] })

    const innerFlex = createElement('div', {
      classes: ['flex', 'items-center'],
      children: [iconDiv, messageDiv, closeDiv]
    })

    toast.appendChild(innerFlex)

    document.body.appendChild(toast)
    
    // Animate in
    requestAnimationFrame(() => {
      toast.style.transform = "translateX(0)"
      toast.style.opacity = "1"
    })
    
    // Auto remove after 5 seconds
    setTimeout(() => {
      toast.style.transform = "translateX(100%)"
      toast.style.opacity = "0"
      setTimeout(() => {
        if (toast.parentNode) {
          toast.remove()
        }
      }, 300)
    }, 5000)
  }
  
  // Get CSRF token
  getCSRFToken() {
    const token = document.querySelector("meta[name='csrf-token']")
    return token ? token.getAttribute("content") : ""
  }
}